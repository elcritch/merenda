## Asynchronous Matter syntax highlighting for Kosmo's embedded Moe editor.
##
## Matter owns mutable grammar and tokenizer state, so the worker builds and
## retains that state on the shared Sigils pool. Results contain only plain
## value data and are applied to Moe buffers by the owner thread.

import std/[atomics, isolation, monotimes, os, strutils, tables, times, unicode]

from matter/engine import hasActiveScope
import sigils/[core, threadProxies, threads]
import threading/smartptrs

import moepkg/highlight as moeHighlight
import moepkg/syntax/matter_backend as moeMatter
import moepkg/syntax/tokenizer as moeTokenizer

import ../nimkit/foundation/backgroundworkers

const KosmoMatterTimeLimitMs* {.intdefine.} = 100
  ## Soft per-line deadline used by the asynchronous adapter. A zero value
  ## disables the deadline for deterministic equivalence tests.
const KosmoMatterMaximumLineBytes* {.intdefine.} = 1024
  ## Maximum line size passed to Matter's TextMate tokenizer.
  ## Longer lines stay plain to bound parsing work on generated or minified input.

const
  MatterHighlightBatchLines* = 64
  MatterHighlightBatchMilliseconds = 8

static:
  doAssert KosmoMatterTimeLimitMs >= 0, "KosmoMatterTimeLimitMs must be non-negative"
  doAssert KosmoMatterMaximumLineBytes > 0,
    "KosmoMatterMaximumLineBytes must be positive"

type
  MatterHighlightControl* = object
    cancelled*: Atomic[bool]

  MatterHighlightResult* = object
    requestId*: uint64
    bufferId*: int
    contentVersion*: int
    workerThreadId*: int
    firstRow*, endRow*: int ## Half-open range replaced by this batch.
    finished*: bool ## True only for the final batch of this request.
    segments*: seq[moeHighlight.ColorSegment]
    markdownCodeBlockStates*: seq[bool]
    errorMessage*: string

  MatterGrammarFileType* = object
    ## Installed VS Code file associations and the corresponding root grammar.
    identifier*: string
    languageId*: string
    rootPath*: string
    extensions*: seq[string]
    fileNames*: seq[string]

  MarkdownFence = object
    marker: char
    length: int
    language: moeHighlight.SourceLanguage

  MatterHighlightJob = object
    requestId: uint64
    bufferId, contentVersion: int
    source: string
    lineStart, row: int
    control: SharedPtr[MatterHighlightControl]
    selected:
      tuple[language: moeHighlight.SourceLanguage, grammars: moeMatter.MatterGrammarSet]
    state, continuingState, recoveryState, embeddedState: moeMatter.MatterLineState
    fence: MarkdownFence

  MatterHighlightWorker = ref object of AgentActor
    sources: seq[moeMatter.MatterGrammarSource]
    grammars: moeMatter.MatterGrammarSet
    terraformGrammars: moeMatter.MatterGrammarSet
    installedGrammars: Table[
      string,
      tuple[language: moeHighlight.SourceLanguage, grammars: moeMatter.MatterGrammarSet],
    ]
    fileTypes: seq[MatterGrammarFileType]
    jobs: Table[int, MatterHighlightJob]

  MatterHighlighting* = ref object of Agent
    worker: AgentProxy[MatterHighlightWorker]
    pending: seq[MatterHighlightResult]
    controls: Table[int, SharedPtr[MatterHighlightControl]]
    requested: Table[int, uint64]
    completed: Table[int, uint64]
    nextRequestId: uint64
    closed: bool

proc matterHighlightCompleted*(highlighting: MatterHighlighting) {.signal.}
  ## A batch is ready to consume; query readiness separately for EOF.

proc newMatterHighlightControl*(): SharedPtr[MatterHighlightControl] =
  result = newSharedPtr(MatterHighlightControl)
  result[].cancelled.store(false, moRelaxed)

proc cancel(control: SharedPtr[MatterHighlightControl]) {.inline.} =
  if not control.isNil:
    control[].cancelled.store(true, moRelease)

proc cancelled(control: SharedPtr[MatterHighlightControl]): bool {.inline.} =
  not control.isNil and control[].cancelled.load(moAcquire)

proc sourceIsTerraform(path: string): bool {.inline.} =
  path.endsWith("terraform.tmGrammar.json")

proc newTerraformGrammarSources(
    sources: openArray[moeMatter.MatterGrammarSource]
): seq[moeMatter.MatterGrammarSource] =
  ## The selected Moe branch predates file-type grammar selection. Give the
  ## Terraform root a private compatibility binding while retaining every
  ## grammar in the registry for includes.
  result = newSeqOfCap[moeMatter.MatterGrammarSource](sources.len)
  for source in sources:
    var selected = source
    if source.path.sourceIsTerraform:
      selected.language = moeHighlight.SourceLanguage.langHyprland
    result.add move selected

proc ensureGrammars(worker: MatterHighlightWorker) =
  if worker.grammars.isNil:
    worker.grammars = moeMatter.newMatterGrammarSet(worker.sources)

proc ensureTerraformGrammars(worker: MatterHighlightWorker) =
  if worker.terraformGrammars.isNil:
    worker.terraformGrammars =
      moeMatter.newMatterGrammarSet(newTerraformGrammarSources(worker.sources))

proc matchingFileType(
    worker: MatterHighlightWorker, fileName: string
): MatterGrammarFileType =
  let baseName = extractFilename(fileName)
  for fileType in worker.fileTypes:
    for candidateName in fileType.fileNames:
      if cmpIgnoreCase(baseName, candidateName) == 0:
        return fileType
  let normalizedFileName = fileName.toLowerAscii()
  for fileType in worker.fileTypes:
    for candidateExtension in fileType.extensions:
      if normalizedFileName.endsWith(candidateExtension.toLowerAscii()):
        return fileType

proc matchesMatterFileType*(
    fileTypes: openArray[MatterGrammarFileType], fileName: string
): bool =
  let baseName = extractFilename(fileName)
  for fileType in fileTypes:
    for candidateName in fileType.fileNames:
      if cmpIgnoreCase(baseName, candidateName) == 0:
        return true
  let normalizedFileName = fileName.toLowerAscii()
  for fileType in fileTypes:
    for candidateExtension in fileType.extensions:
      if normalizedFileName.endsWith(candidateExtension.toLowerAscii()):
        return true

proc installedGrammar(
    worker: MatterHighlightWorker, fileType: MatterGrammarFileType
): tuple[language: moeHighlight.SourceLanguage, grammars: moeMatter.MatterGrammarSet] =
  if worker.installedGrammars.hasKey(fileType.identifier):
    return worker.installedGrammars[fileType.identifier]

  var language = moeTokenizer.getSourceLanguage(fileType.languageId)
  if language in {
    moeHighlight.SourceLanguage.langNone, moeHighlight.SourceLanguage.langDiff,
    moeHighlight.SourceLanguage.langLog,
  }:
    # Matter uses the enum as a root selector; unknown VS Code languages use a
    # private selector while preserving their grammar's actual token scopes.
    language = moeHighlight.SourceLanguage.langAstro

  var sources = newSeqOfCap[moeMatter.MatterGrammarSource](worker.sources.len)
  var rootFound: bool
  for source in worker.sources:
    var selected = source
    selected.language = moeHighlight.SourceLanguage.langNone
    if source.path == fileType.rootPath:
      selected.language = language
      rootFound = true
    sources.add move selected
  if not rootFound:
    raise newException(ValueError, "installed TextMate root grammar is unavailable")

  let grammars = moeMatter.newMatterGrammarSet(sources)
  if not grammars.matterSupports(language):
    raise
      newException(ValueError, "installed TextMate root grammar could not be compiled")
  result = (language, grammars)
  worker.installedGrammars[fileType.identifier] = result

proc requestGrammar(
    worker: MatterHighlightWorker,
    language: moeHighlight.SourceLanguage,
    fileName: string,
): tuple[language: moeHighlight.SourceLanguage, grammars: moeMatter.MatterGrammarSet] =
  let fileType = worker.matchingFileType(fileName)
  if fileType.identifier.len > 0:
    return worker.installedGrammar(fileType)
  let extension = fileName.splitFile.ext.toLowerAscii()
  if extension in [".hcl", ".tf", ".tfvars"]:
    worker.ensureTerraformGrammars()
    return (moeHighlight.SourceLanguage.langHyprland, worker.terraformGrammars)
  worker.ensureGrammars()
  (language, worker.grammars)

proc scopeMatches(scope, prefix: string): bool {.inline.} =
  scope == prefix or scope.startsWith(prefix & ".")

proc isYamlMappingKey(scopes: openArray[string]): bool {.inline.} =
  for scope in scopes:
    if scope.scopeMatches("entity.name.tag"):
      return true

proc isYamlSimpleMappingKey(line: string, firstByte, lastByte: int): bool {.inline.} =
  ## The stock VS Code YAML grammar applies YAML 1.1 implicit scalar rules
  ## before its mapping-key scope, so keys such as `on:` arrive as booleans.
  ## A plain block key immediately followed by `:` is still a property in the
  ## editor, regardless of the scalar spelling.
  if firstByte < 0 or lastByte <= firstByte or lastByte >= line.len or
      line[lastByte] != ':' or
      (lastByte + 1 < line.len and not line[lastByte + 1].isSpaceAscii):
    return
  var keyStart: int
  while keyStart < line.len and line[keyStart] in {' ', '\t'}:
    inc keyStart
  if keyStart < line.len and line[keyStart] == '-' and keyStart + 1 < line.len and
      line[keyStart + 1].isSpaceAscii:
    inc keyStart, 2
    while keyStart < line.len and line[keyStart] in {' ', '\t'}:
      inc keyStart
  firstByte == keyStart

proc isHeading(scopes: openArray[string]): bool =
  for scope in scopes:
    if scope.scopeMatches("entity.name.section") or scope.scopeMatches("markup.heading"):
      return true

proc shouldRestartMarkdownListState(
    language: moeHighlight.SourceLanguage,
    line: string,
    state: moeMatter.MatterLineState,
): bool =
  ## The VS Code Markdown grammar keeps list state only for blank or indented
  ## continuation lines. Matter currently leaves that begin/while state active
  ## when the first unindented block arrives, making the rest of the document
  ## look like list text. Restart at the same boundary the grammar declares.
  language == moeHighlight.SourceLanguage.langMarkdown and line.len > 0 and
    not line[0].isSpaceAscii and not state.isMatterCodeBlock and
    state.stack.hasActiveScope("markup.list")

proc exceedsMatterParsingBudget(line: string): bool =
  line.len > KosmoMatterMaximumLineBytes

proc markdownFence(line: string): MarkdownFence =
  var first: int
  while first < line.len and line[first] in {' ', '\t'}:
    inc first
  if first > 3 or first >= line.len or line[first] notin {'`', '~'}:
    return
  result.marker = line[first]
  var last = first
  while last < line.len and line[last] == result.marker:
    inc last
  if last - first < 3:
    result = default(MarkdownFence)
    return
  result.length = last - first
  var languageStart = last
  while languageStart < line.len and line[languageStart].isSpaceAscii:
    inc languageStart
  var languageStop = languageStart
  while languageStop < line.len and not line[languageStop].isSpaceAscii:
    inc languageStop
  if languageStop > languageStart:
    result.language =
      moeTokenizer.getSourceLanguage(line[languageStart ..< languageStop])

proc closes(fence: MarkdownFence, line: string): bool =
  if fence.length < 3:
    return
  let candidate = line.markdownFence()
  if candidate.marker != fence.marker or candidate.length < fence.length:
    return
  var last: int
  while last < line.len and line[last].isSpaceAscii:
    inc last
  last += candidate.length
  while last < line.len:
    if not line[last].isSpaceAscii:
      return
    inc last
  true

proc continuingMatterState(
    grammars: moeMatter.MatterGrammarSet, language: moeHighlight.SourceLanguage
): moeMatter.MatterLineState =
  ## A parsed blank line gives recovery a root state that cannot re-enable
  ## document-start-only rules such as Markdown frontmatter in mid-document.
  let initial = moeMatter.initialMatterState(grammars, language)

  moeMatter.tokenizeMatterLine(
    "", language, initial, timeLimitMs = 0, grammars = grammars
  ).nextState

proc supportsEmbeddedMatterLanguage(
    grammars: moeMatter.MatterGrammarSet, language: moeHighlight.SourceLanguage
): bool {.inline.} =
  language notin
    {moeHighlight.SourceLanguage.langNone, moeHighlight.SourceLanguage.langMarkdown} and
    grammars.matterSupports(language)

proc initialEmbeddedMatterState(
    grammars: moeMatter.MatterGrammarSet, language: moeHighlight.SourceLanguage
): moeMatter.MatterLineState =
  if grammars.supportsEmbeddedMatterLanguage(language):
    return moeMatter.initialMatterState(grammars, language)

proc matterColor(
    category: moeMatter.MatterColorCategory
): moeHighlight.EditorColorPairIndex =
  case category
  of moeMatter.mccComment: moeHighlight.EditorColorPairIndex.comment
  of moeMatter.mccString: moeHighlight.EditorColorPairIndex.stringLit
  of moeMatter.mccNumber: moeHighlight.EditorColorPairIndex.decNumber
  of moeMatter.mccKeyword: moeHighlight.EditorColorPairIndex.keyword
  of moeMatter.mccFunction: moeHighlight.EditorColorPairIndex.functionName
  of moeMatter.mccType: moeHighlight.EditorColorPairIndex.typeName
  of moeMatter.mccBuiltin: moeHighlight.EditorColorPairIndex.builtin
  of moeMatter.mccIdentifier: moeHighlight.EditorColorPairIndex.identifier
  of moeMatter.mccBoolean: moeHighlight.EditorColorPairIndex.boolean
  of moeMatter.mccOperator: moeHighlight.EditorColorPairIndex.operator
  of moeMatter.mccPreprocessor: moeHighlight.EditorColorPairIndex.preprocessor
  of moeMatter.mccProperty: moeHighlight.EditorColorPairIndex.property
  of moeMatter.mccDefault: moeHighlight.EditorColorPairIndex.default

proc runeColumns(line: string): seq[int] =
  result = newSeq[int](line.len + 1)
  var
    bytePos: int
    column: int
  while bytePos < line.len:
    let size = max(runeLenAt(line, bytePos), 1)
    let lastByte = min(bytePos + size, line.len)
    for index in bytePos ..< lastByte:
      result[index] = column
    bytePos = lastByte
    inc column
  result[line.len] = column

proc addSegment(
    segments: var seq[moeHighlight.ColorSegment],
    row, firstColumn, lastColumn: int,
    color: moeHighlight.EditorColorPairIndex,
) =
  if lastColumn < firstColumn:
    return
  if segments.len > 0:
    var previous = addr segments[^1]
    if previous[].firstRow == row and previous[].lastRow == row and
        previous[].lastColumn + 1 == firstColumn and previous[].color == color:
      previous[].lastColumn = lastColumn
      return
  segments.add moeHighlight.ColorSegment(
    firstRow: row,
    firstColumn: firstColumn,
    lastRow: row,
    lastColumn: lastColumn,
    color: color,
    style: moeHighlight.defaultStyle,
  )

proc addLineSegments(
    segments: var seq[moeHighlight.ColorSegment],
    row: int,
    line: string,
    language: moeHighlight.SourceLanguage,
    spans: openArray[moeMatter.MatterSpan],
) =
  let columns = line.runeColumns()
  if line.len == 0:
    segments.add moeHighlight.ColorSegment(
      firstRow: row,
      firstColumn: 0,
      lastRow: row,
      lastColumn: 0,
      color: moeHighlight.EditorColorPairIndex.default,
      style: moeHighlight.defaultStyle,
    )
    return

  var coveredByte: int
  for span in spans:
    let firstByte = clamp(span.firstByte, coveredByte, line.len)
    let lastByte = clamp(span.lastByte, firstByte, line.len)
    if firstByte > coveredByte:
      segments.addSegment(
        row,
        columns[coveredByte],
        columns[firstByte] - 1,
        moeHighlight.EditorColorPairIndex.default,
      )
    if lastByte > firstByte:
      let color =
        if language == moeHighlight.SourceLanguage.langYaml and (
          span.scopes.isYamlMappingKey or
          line.isYamlSimpleMappingKey(firstByte, lastByte)
        ):
          moeHighlight.EditorColorPairIndex.property
        elif span.category == moeMatter.mccDefault and span.scopes.isHeading:
          moeHighlight.EditorColorPairIndex.builtin
        else:
          span.category.matterColor
      segments.addSegment(row, columns[firstByte], columns[lastByte] - 1, color)
      coveredByte = lastByte
  if coveredByte < line.len:
    segments.addSegment(
      row,
      columns[coveredByte],
      columns[line.len] - 1,
      moeHighlight.EditorColorPairIndex.default,
    )

proc highlightMatterLine(
    job: var MatterHighlightJob,
    result: var MatterHighlightResult,
    row: int,
    line: string,
) =
  if line.exceedsMatterParsingBudget():
    let
      closesSkippedFence =
        job.selected.language == moeHighlight.SourceLanguage.langMarkdown and
        job.fence.closes(line)
      skippedOpeningFence =
        if job.selected.language == moeHighlight.SourceLanguage.langMarkdown and
            job.fence.length < 3:
          line.markdownFence()
        else:
          default(MarkdownFence)
    result.segments.addLineSegments(row, line, job.selected.language, [])
    if job.selected.language != moeHighlight.SourceLanguage.langMarkdown:
      # A skipped YAML scalar does not change the surrounding indentation or
      # block structure. Retaining the prior stack lets the next line unwind
      # naturally instead of injecting a synthetic document root mid-file.
      discard
    elif closesSkippedFence:
      job.state = job.recoveryState
      job.fence = default(MarkdownFence)
      job.embeddedState = default(moeMatter.MatterLineState)
    elif job.fence.length >= 3:
      # Keep the enclosing grammar state. Skipping one oversized embedded
      # line must not turn all following code into Markdown prose.
      discard
    else:
      job.state = job.recoveryState
      job.fence = skippedOpeningFence
      job.embeddedState =
        job.selected.grammars.initialEmbeddedMatterState(job.fence.language)
    if job.selected.language == moeHighlight.SourceLanguage.langMarkdown:
      result.markdownCodeBlockStates.add job.fence.length >= 3
    return
  if shouldRestartMarkdownListState(job.selected.language, line, job.state):
    job.state = job.continuingState
  let
    wasInMarkdownFence =
      job.selected.language == moeHighlight.SourceLanguage.langMarkdown and (
        job.fence.length >= 3 or
        job.state.stack.hasActiveScope("markup.fenced_code.block")
      )
    openingFence =
      if wasInMarkdownFence:
        default(MarkdownFence)
      else:
        line.markdownFence()
    closesMarkdownFence = wasInMarkdownFence and job.fence.closes(line)
  let parsed = moeMatter.tokenizeMatterLine(
    line,
    job.selected.language,
    job.state,
    timeLimitMs = KosmoMatterTimeLimitMs,
    grammars = job.selected.grammars,
  )
  var
    lineLanguage = job.selected.language
    lineSpans = parsed.spans
  if job.selected.language == moeHighlight.SourceLanguage.langMarkdown and
      wasInMarkdownFence and not closesMarkdownFence and
      job.selected.grammars.supportsEmbeddedMatterLanguage(job.fence.language):
    let embedded = moeMatter.tokenizeMatterLine(
      line,
      job.fence.language,
      job.embeddedState,
      timeLimitMs = KosmoMatterTimeLimitMs,
      grammars = job.selected.grammars,
    )
    if embedded.nextState.failed:
      # Keep a slow or malformed embedded line plain without poisoning the
      # rest of the fenced block. The next line gets a fresh continuation
      # root, matching the outer Markdown recovery behavior above.
      job.embeddedState =
        job.selected.grammars.continuingMatterState(job.fence.language)
      lineSpans = @[]
    else:
      job.embeddedState = embedded.nextState
      lineLanguage = job.fence.language
      lineSpans = embedded.spans
  result.segments.addLineSegments(row, line, lineLanguage, lineSpans)
  if closesMarkdownFence:
    job.state = job.recoveryState
    job.fence = default(MarkdownFence)
    job.embeddedState = default(moeMatter.MatterLineState)
  elif parsed.nextState.failed:
    # A soft timeout must not poison every later line. The failed line is
    # covered plainly above; restart from a continuation root so headings
    # and later independent constructs can recover without re-enabling
    # document-start-only rules.
    job.state = job.recoveryState
    if not wasInMarkdownFence:
      job.fence = default(MarkdownFence)
      job.embeddedState = default(moeMatter.MatterLineState)
  else:
    job.state = parsed.nextState
    if not wasInMarkdownFence and
        job.state.stack.hasActiveScope("markup.fenced_code.block"):
      job.fence = openingFence
      job.embeddedState =
        job.selected.grammars.initialEmbeddedMatterState(job.fence.language)
    elif job.fence.length < 3 and
        not job.state.stack.hasActiveScope("markup.fenced_code.block"):
      job.fence = default(MarkdownFence)
      job.embeddedState = default(moeMatter.MatterLineState)
  if job.selected.language == moeHighlight.SourceLanguage.langMarkdown:
    result.markdownCodeBlockStates.add job.fence.length >= 3 or
      job.state.isMatterCodeBlock

proc matterHighlightFinished*(
  worker: MatterHighlightWorker, highlighted: SharedPtr[MatterHighlightResult]
) {.signal.}

proc requestMatterHighlight*(
  worker: AgentProxy[MatterHighlightWorker],
  requestId: uint64,
  bufferId: int,
  contentVersion: int,
  source: string,
  language: moeHighlight.SourceLanguage,
  fileName: string,
  control: SharedPtr[MatterHighlightControl],
) {.signal.}

proc continueMatterHighlight*(
  worker: AgentProxy[MatterHighlightWorker], bufferId: int, requestId: uint64
) {.signal.}

proc discardMatterHighlight*(
  worker: AgentProxy[MatterHighlightWorker], bufferId: int, requestId: uint64
) {.signal.}

proc discardMatterHighlight(
    worker: MatterHighlightWorker, bufferId: int, requestId: uint64
) {.slot.} =
  if worker.jobs.hasKey(bufferId) and worker.jobs[bufferId].requestId == requestId:
    worker.jobs.del(bufferId)

proc continueMatterHighlight(
    worker: MatterHighlightWorker, bufferId: int, requestId: uint64
) {.slot.} =
  if not worker.jobs.hasKey(bufferId) or worker.jobs[bufferId].requestId != requestId:
    return
  var job = move worker.jobs[bufferId]
  worker.jobs.del(bufferId)
  if job.control.cancelled:
    return
  var batch = MatterHighlightResult(
    requestId: job.requestId,
    bufferId: bufferId,
    contentVersion: job.contentVersion,
    workerThreadId: getThreadId(),
    firstRow: job.row,
    endRow: job.row,
  )
  let started = getMonoTime()
  try:
    while job.lineStart <= job.source.len and
        batch.endRow - batch.firstRow < MatterHighlightBatchLines:
      if job.control.cancelled:
        return
      var lineStop = job.source.find('\n', job.lineStart)
      if lineStop < 0:
        lineStop = job.source.len
      job.highlightMatterLine(batch, job.row, job.source[job.lineStart ..< lineStop])
      job.lineStart = lineStop + 1
      inc job.row
      batch.endRow = job.row
      if (getMonoTime() - started).inMilliseconds >= MatterHighlightBatchMilliseconds:
        break
    batch.finished = job.lineStart > job.source.len
  except CatchableError as error:
    batch.errorMessage = error.msg
    batch.finished = true
  if job.control.cancelled:
    return
  if not batch.finished:
    worker.jobs[bufferId] = move job
  emit worker.matterHighlightFinished(newSharedPtr(unsafeIsolate(move batch)))

proc requestMatterHighlight(
    worker: MatterHighlightWorker,
    requestId: uint64,
    bufferId: int,
    contentVersion: int,
    source: string,
    language: moeHighlight.SourceLanguage,
    fileName: string,
    control: SharedPtr[MatterHighlightControl],
) {.slot.} =
  worker.jobs.del(bufferId)
  if control.cancelled:
    return
  var job = MatterHighlightJob(
    requestId: requestId,
    bufferId: bufferId,
    contentVersion: contentVersion,
    source: source,
    control: control,
  )
  try:
    job.selected = worker.requestGrammar(language, fileName)
    if not job.selected.grammars.matterSupports(job.selected.language):
      raise newException(ValueError, "No Matter grammar for " & $job.selected.language)
    job.state =
      moeMatter.initialMatterState(job.selected.grammars, job.selected.language)
    job.continuingState =
      continuingMatterState(job.selected.grammars, job.selected.language)
    job.recoveryState =
      if job.selected.language == moeHighlight.SourceLanguage.langMarkdown:
        job.continuingState
      else:
        job.state
    worker.jobs[bufferId] = move job
    worker.continueMatterHighlight(bufferId, requestId)
  except CatchableError as error:
    var batch = MatterHighlightResult(
      requestId: requestId,
      bufferId: bufferId,
      contentVersion: contentVersion,
      workerThreadId: getThreadId(),
      finished: true,
      errorMessage: error.msg,
    )
    emit worker.matterHighlightFinished(newSharedPtr(unsafeIsolate(move batch)))

proc receiveMatterHighlight(
    highlighting: MatterHighlighting, result: SharedPtr[MatterHighlightResult]
) {.slot.} =
  if not highlighting.closed and
      highlighting.requested.getOrDefault(result[].bufferId) == result[].requestId:
    if result[].finished:
      highlighting.completed[result[].bufferId] = result[].requestId
    highlighting.pending.add move result[]
    emit highlighting.matterHighlightCompleted()

proc newMatterHighlighting*(
    sources: sink seq[moeMatter.MatterGrammarSource],
    fileTypes: sink seq[MatterGrammarFileType] = @[],
): MatterHighlighting =
  result = MatterHighlighting(
    controls: initTable[int, SharedPtr[MatterHighlightControl]](),
    completed: initTable[int, uint64](),
  )
  var worker = MatterHighlightWorker(
    sources: move sources,
    fileTypes: move fileTypes,
    installedGrammars: initTable[
      string,
      tuple[language: moeHighlight.SourceLanguage, grammars: moeMatter.MatterGrammarSet],
    ](),
  )
  result.worker = worker.moveToThread(nimkitWorkerPool())
  connectThreaded(
    result.worker, requestMatterHighlight, result.worker, requestMatterHighlight
  )
  connectThreaded(
    result.worker, continueMatterHighlight, result.worker, continueMatterHighlight
  )
  connectThreaded(
    result.worker, discardMatterHighlight, result.worker, discardMatterHighlight
  )
  connectThreaded(
    result.worker,
    matterHighlightFinished,
    result,
    MatterHighlighting.receiveMatterHighlight(),
  )

proc cancelMatterHighlight*(highlighting: MatterHighlighting, bufferId: int) =
  ## Discard a closed buffer's pending batch and retained worker state.
  if highlighting.isNil or highlighting.closed:
    return
  if highlighting.controls.hasKey(bufferId):
    highlighting.controls[bufferId].cancel()
    highlighting.controls.del(bufferId)
  if highlighting.requested.hasKey(bufferId):
    emit highlighting.worker.discardMatterHighlight(
      bufferId, highlighting.requested[bufferId]
    )
    highlighting.requested.del(bufferId)
  highlighting.completed.del(bufferId)
  for index in countdown(highlighting.pending.high, 0):
    if highlighting.pending[index].bufferId == bufferId:
      highlighting.pending.delete(index)

proc requestMatterHighlight*(
    highlighting: MatterHighlighting,
    bufferId: int,
    contentVersion: int,
    source: string,
    language: moeHighlight.SourceLanguage,
    fileName: string,
): uint64 =
  if highlighting.isNil or highlighting.closed:
    return
  inc highlighting.nextRequestId
  result = highlighting.nextRequestId
  highlighting.cancelMatterHighlight(bufferId)
  let control = newMatterHighlightControl()
  highlighting.controls[bufferId] = control
  highlighting.completed.del(bufferId)
  highlighting.requested[bufferId] = result
  emit highlighting.worker.requestMatterHighlight(
    result, bufferId, contentVersion, source, language, fileName, control
  )

proc takeMatterHighlightResults*(
    highlighting: MatterHighlighting
): seq[MatterHighlightResult] =
  ## Consume available deltas and acknowledge their next worker slices.
  ## Call while work is pending; readiness alone does not consume batches.
  if highlighting.isNil:
    return
  result = move highlighting.pending
  highlighting.pending = @[]
  # Consuming a batch grants the worker one more bounded slice. There is at
  # most one unconsumed result per buffer, including for hidden documents.
  for batch in result:
    if not batch.finished and not highlighting.closed:
      emit highlighting.worker.continueMatterHighlight(batch.bufferId, batch.requestId)

proc matterHighlightingReady*(
    highlighting: MatterHighlighting, bufferId: int, requestId: uint64
): bool =
  not highlighting.isNil and highlighting.completed.getOrDefault(bufferId) == requestId

proc close*(highlighting: MatterHighlighting) =
  if highlighting.isNil or highlighting.closed:
    return
  highlighting.closed = true
  for control in highlighting.controls.values:
    control.cancel()
  for bufferId, requestId in highlighting.requested:
    emit highlighting.worker.discardMatterHighlight(bufferId, requestId)
  highlighting.controls.clear()
  highlighting.completed.clear()
  highlighting.requested.clear()
  highlighting.pending.setLen(0)
  highlighting.worker = nil

var matterWorkerLifetime {.used.}: NimkitBackgroundWorkerLifetime
