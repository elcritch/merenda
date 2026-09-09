## Asynchronous Matter syntax highlighting for Kosmo's embedded Moe editor.
##
## Matter owns mutable grammar and tokenizer state, so the worker builds and
## retains that state on the shared Sigils pool. Results contain only plain
## value data and are applied to Moe buffers by the owner thread.

import std/[atomics, isolation, os, strutils, tables, unicode]

from matter/engine import hasActiveScope
import sigils/[core, threadProxies, threads]
import threading/smartptrs

import moepkg/highlight as moeHighlight
import moepkg/syntax/matter_backend as moeMatter

import ../nimkit/foundation/backgroundworkers

const KosmoMatterTimeLimitMs* {.intdefine.} = 100
  ## Soft per-line deadline used by the asynchronous adapter. A zero value
  ## disables the deadline for deterministic equivalence tests.
const KosmoMatterMaximumLineBytes* {.intdefine.} = 256
  ## Maximum line size passed to Matter's recursive TextMate regex engine.
  ## Builds with smaller worker stacks can lower this value.

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
    segments*: seq[moeHighlight.ColorSegment]
    markdownCodeBlockStates*: seq[bool]
    errorMessage*: string

  MatterHighlightWorker = ref object of AgentActor
    sources: seq[moeMatter.MatterGrammarSource]
    grammars: moeMatter.MatterGrammarSet
    terraformGrammars: moeMatter.MatterGrammarSet

  MatterHighlighting* = ref object of Agent
    worker: AgentProxy[MatterHighlightWorker]
    pending: seq[MatterHighlightResult]
    controls: Table[int, SharedPtr[MatterHighlightControl]]
    completed: Table[int, uint64]
    nextRequestId: uint64
    closed: bool

proc matterHighlightCompleted*(highlighting: MatterHighlighting) {.signal.}

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

proc requestGrammar(
    worker: MatterHighlightWorker,
    language: moeHighlight.SourceLanguage,
    fileName: string,
): tuple[language: moeHighlight.SourceLanguage, grammars: moeMatter.MatterGrammarSet] =
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

type MarkdownFence = object
  marker: char
  length: int

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

proc closes(fence: MarkdownFence, line: string): bool =
  if fence.length < 3:
    return
  let candidate = line.markdownFence()
  if candidate.marker != fence.marker or candidate.length < fence.length:
    return
  var last: int
  while last < line.len and line[last] in {' ', '\t'}:
    inc last
  last += candidate.length
  while last < line.len:
    if line[last] notin {' ', '\t'}:
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

proc highlightMatter(
    worker: MatterHighlightWorker,
    source: string,
    language: moeHighlight.SourceLanguage,
    fileName: string,
    control: SharedPtr[MatterHighlightControl],
): tuple[
  segments: seq[moeHighlight.ColorSegment],
  markdownCodeBlockStates: seq[bool],
  errorMessage: string,
] =
  let selected = worker.requestGrammar(language, fileName)
  if not selected.grammars.matterSupports(selected.language):
    return (
      segments: @[],
      markdownCodeBlockStates: @[],
      errorMessage: "No Matter grammar for " & $selected.language,
    )
  let
    initialState = moeMatter.initialMatterState(selected.grammars, selected.language)
    continuingState = continuingMatterState(selected.grammars, selected.language)
    recoveryState =
      if selected.language == moeHighlight.SourceLanguage.langMarkdown:
        continuingState
      else:
        initialState
  var state = initialState
  var fence: MarkdownFence

  let lines = source.split('\n')
  result.segments = newSeqOfCap[moeHighlight.ColorSegment](max(lines.len, 1))
  if selected.language == moeHighlight.SourceLanguage.langMarkdown:
    result.markdownCodeBlockStates = newSeqOfCap[bool](lines.len)
  for row, line in lines:
    if control.cancelled:
      return (segments: @[], markdownCodeBlockStates: @[], errorMessage: "")
    if line.exceedsMatterParsingBudget():
      let
        closesSkippedFence =
          selected.language == moeHighlight.SourceLanguage.langMarkdown and
          fence.closes(line)
        skippedOpeningFence =
          if selected.language == moeHighlight.SourceLanguage.langMarkdown and
              fence.length < 3:
            line.markdownFence()
          else:
            default(MarkdownFence)
      result.segments.addLineSegments(row, line, selected.language, [])
      if selected.language != moeHighlight.SourceLanguage.langMarkdown:
        # A skipped YAML scalar does not change the surrounding indentation or
        # block structure. Retaining the prior stack lets the next line unwind
        # naturally instead of injecting a synthetic document root mid-file.
        discard
      elif closesSkippedFence:
        state = recoveryState
        fence = default(MarkdownFence)
      elif fence.length >= 3:
        # Keep the enclosing grammar state. Skipping one oversized embedded
        # line must not turn all following code into Markdown prose.
        discard
      else:
        state = recoveryState
        fence = skippedOpeningFence
      if selected.language == moeHighlight.SourceLanguage.langMarkdown:
        result.markdownCodeBlockStates.add fence.length >= 3
      continue
    if shouldRestartMarkdownListState(selected.language, line, state):
      state = continuingState
    let
      wasInMarkdownFence =
        selected.language == moeHighlight.SourceLanguage.langMarkdown and
        (fence.length >= 3 or state.stack.hasActiveScope("markup.fenced_code.block"))
      openingFence =
        if wasInMarkdownFence:
          default(MarkdownFence)
        else:
          line.markdownFence()
      closesMarkdownFence = wasInMarkdownFence and fence.closes(line)
    let parsed = moeMatter.tokenizeMatterLine(
      line,
      selected.language,
      state,
      timeLimitMs = KosmoMatterTimeLimitMs,
      grammars = selected.grammars,
    )
    result.segments.addLineSegments(row, line, selected.language, parsed.spans)
    if closesMarkdownFence:
      state = recoveryState
      fence = default(MarkdownFence)
    elif parsed.nextState.failed:
      # A soft timeout must not poison every later line. The failed line is
      # covered plainly above; restart from a continuation root so headings
      # and later independent constructs can recover without re-enabling
      # document-start-only rules.
      state = recoveryState
      if not wasInMarkdownFence:
        fence = default(MarkdownFence)
    else:
      state = parsed.nextState
      if not wasInMarkdownFence and
          state.stack.hasActiveScope("markup.fenced_code.block"):
        fence = openingFence
      elif fence.length < 3 and
          not state.stack.hasActiveScope("markup.fenced_code.block"):
        fence = default(MarkdownFence)
    if selected.language == moeHighlight.SourceLanguage.langMarkdown:
      result.markdownCodeBlockStates.add fence.length >= 3 or state.isMatterCodeBlock

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
  if control.cancelled:
    return
  var highlightResult = MatterHighlightResult(
    requestId: requestId,
    bufferId: bufferId,
    contentVersion: contentVersion,
    workerThreadId: getThreadId(),
  )
  try:
    var parsed = worker.highlightMatter(source, language, fileName, control)
    if control.cancelled:
      return
    highlightResult.segments = move parsed.segments
    highlightResult.markdownCodeBlockStates = move parsed.markdownCodeBlockStates
    highlightResult.errorMessage = move parsed.errorMessage
  except CatchableError as error:
    if control.cancelled:
      return
    highlightResult.errorMessage = error.msg
  emit worker.matterHighlightFinished(newSharedPtr(unsafeIsolate(move highlightResult)))

proc receiveMatterHighlight(
    highlighting: MatterHighlighting, result: SharedPtr[MatterHighlightResult]
) {.slot.} =
  if not highlighting.closed:
    highlighting.completed[result[].bufferId] = result[].requestId
    highlighting.pending.add move result[]
    emit highlighting.matterHighlightCompleted()

proc newMatterHighlighting*(
    sources: sink seq[moeMatter.MatterGrammarSource]
): MatterHighlighting =
  result = MatterHighlighting(
    controls: initTable[int, SharedPtr[MatterHighlightControl]](),
    completed: initTable[int, uint64](),
  )
  var worker = MatterHighlightWorker(sources: move sources)
  result.worker = worker.moveToThread(nimkitWorkerPool())
  connectThreaded(
    result.worker, requestMatterHighlight, result.worker, requestMatterHighlight
  )
  connectThreaded(
    result.worker,
    matterHighlightFinished,
    result,
    MatterHighlighting.receiveMatterHighlight(),
  )

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
  if highlighting.controls.hasKey(bufferId):
    highlighting.controls[bufferId].cancel()
  let control = newMatterHighlightControl()
  highlighting.controls[bufferId] = control
  highlighting.completed.del(bufferId)
  emit highlighting.worker.requestMatterHighlight(
    result, bufferId, contentVersion, source, language, fileName, control
  )

proc takeMatterHighlightResults*(
    highlighting: MatterHighlighting
): seq[MatterHighlightResult] =
  if highlighting.isNil:
    return
  result = move highlighting.pending
  highlighting.pending = @[]

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
  highlighting.controls.clear()
  highlighting.completed.clear()
  highlighting.pending.setLen(0)
  highlighting.worker = nil

var matterWorkerLifetime {.used.}: NimkitBackgroundWorkerLifetime
