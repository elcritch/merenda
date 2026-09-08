## Asynchronous Matter syntax highlighting for Kosmo's embedded Moe editor.
##
## Matter owns mutable grammar and tokenizer state, so the worker builds and
## retains that state on the shared Sigils pool. Results contain only plain
## value data and are applied to Moe buffers by the owner thread.

import std/[atomics, isolation, os, strutils, tables, unicode]

import sigils/[core, threadProxies, threads]
import threading/smartptrs

import moepkg/highlight as moeHighlight
import moepkg/syntax/matter_backend as moeMatter

import ../nimkit/foundation/backgroundworkers

const KosmoMatterTimeLimitMs* {.intdefine.} = 100
  ## Soft per-line deadline used by the asynchronous adapter. A zero value
  ## disables the deadline for deterministic equivalence tests.

static:
  doAssert KosmoMatterTimeLimitMs >= 0, "KosmoMatterTimeLimitMs must be non-negative"

type
  MatterHighlightControl* = object
    cancelled*: Atomic[bool]

  MatterHighlightResult* = object
    requestId*: uint64
    bufferId*: int
    contentVersion*: int
    workerThreadId*: int
    segments*: seq[moeHighlight.ColorSegment]
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

proc isHeading(scopes: openArray[string]): bool =
  for scope in scopes:
    if scope.scopeMatches("entity.name.section") or scope.scopeMatches("markup.heading"):
      return true

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
        if span.category == moeMatter.mccDefault and span.scopes.isHeading:
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
): tuple[segments: seq[moeHighlight.ColorSegment], errorMessage: string] =
  let selected = worker.requestGrammar(language, fileName)
  var state = moeMatter.initialMatterState(selected.grammars, selected.language)
  if not selected.grammars.matterSupports(selected.language):
    return (segments: @[], errorMessage: "No Matter grammar for " & $selected.language)

  let lines = source.split('\n')
  result.segments = newSeqOfCap[moeHighlight.ColorSegment](max(lines.len, 1))
  for row, line in lines:
    if control.cancelled:
      return (segments: @[], errorMessage: "")
    let parsed = moeMatter.tokenizeMatterLine(
      line,
      selected.language,
      state,
      timeLimitMs = KosmoMatterTimeLimitMs,
      grammars = selected.grammars,
    )
    result.segments.addLineSegments(row, line, parsed.spans)
    if parsed.nextState.failed:
      # A soft timeout must not poison every later line. The failed line is
      # covered plainly above; restart from a fresh grammar state so headings
      # and later independent constructs can recover on the next line.
      state = moeMatter.initialMatterState(selected.grammars, selected.language)
    else:
      state = parsed.nextState

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
