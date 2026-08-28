## Fuzzy project-file picker used by Kosmo's quick-open command.

import std/[algorithm, math, os, osproc, sets, streams, strutils]

import sigils/core

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout

const
  QuickOpenRowHeight = 24.0'f32
  QuickOpenFieldHeight = 30.0'f32
  QuickOpenSpacing = 8.0'f32
  QuickOpenMaximumVisibleItems = 12
  NoMatchingFilesTitle = "No matching files"
  GitProcessStartAttempts = 20
  GitProcessStartRetryMilliseconds = 25

type
  KosmoQuickOpenHandler* = proc(path: string) {.closure.}

  KosmoQuickOpenPanel* = ref object of nimkit.Box
    queryField*: nimkit.TextField
    resultsView*: nimkit.PopupListView
    xRootPath: string
    xProjectFiles: seq[string]
    xFilteredFiles: seq[string]
    xHighlightedIndex: int
    xFirstIndex: int
    xOnOpen: KosmoQuickOpenHandler

  KosmoQuickOpenFieldEditor = ref object of nimkit.FieldEditor
    panel: WeakRef[KosmoQuickOpenPanel]

  KosmoQuickOpenFieldCell = ref object of nimkit.TextFieldCell
    editor: KosmoQuickOpenFieldEditor

  GitCommandResult = object
    output: string
    exitCode: int

  RankedFile = object
    path: string
    score: int

proc moveHighlight(panel: KosmoQuickOpenPanel, delta: int)
proc activateHighlighted(panel: KosmoQuickOpenPanel)

func fuzzyFileScore*(candidate, query: string): int =
  ## Score a case-insensitive fuzzy subsequence match.
  let
    normalizedCandidate = candidate.toLowerAscii()
    normalizedQuery = query.strip().toLowerAscii()
  if normalizedQuery.len == 0:
    return 0

  var
    candidateIndex = 0
    firstMatch = -1
    previousMatch = -2
  for queryCharacter in normalizedQuery:
    var matchIndex = -1
    while candidateIndex < normalizedCandidate.len:
      if normalizedCandidate[candidateIndex] == queryCharacter:
        matchIndex = candidateIndex
        inc candidateIndex
        break
      inc candidateIndex
    if matchIndex < 0:
      return low(int)
    if firstMatch < 0:
      firstMatch = matchIndex
    result += 10
    if matchIndex == 0 or
        normalizedCandidate[matchIndex - 1] in {'/', '\\', '_', '-', '.'}:
      result += 18
    if matchIndex == previousMatch + 1:
      result += 12
    previousMatch = matchIndex

  result -= firstMatch * 2
  result -= normalizedCandidate.len div 4

proc fuzzyFilterFiles*(files: openArray[string], query: string): seq[string] =
  ## Return fuzzy matches ranked by score and then by their relative path.
  let normalizedQuery = query.strip()
  if normalizedQuery.len == 0:
    result = @files
    result.sort(system.cmp[string])
    return

  var ranked: seq[RankedFile]
  for path in files:
    let score = path.fuzzyFileScore(normalizedQuery)
    if score != low(int):
      ranked.add RankedFile(path: path, score: score)
  ranked.sort do(first, second: RankedFile) -> int:
    result = cmp(second.score, first.score)
    if result == 0:
      result = cmp(first.path.len, second.path.len)
    if result == 0:
      result = cmp(first.path, second.path)
  for match in ranked:
    result.add match.path

proc runGit(rootPath: string, arguments: openArray[string]): GitCommandResult =
  var gitArguments = @["-C", rootPath, "--no-optional-locks"]
  gitArguments.add arguments
  for attempt in 0 ..< GitProcessStartAttempts:
    result = GitCommandResult(exitCode: -1)
    var
      process: Process
      processStarted = false
    try:
      process = startProcess(
        "git", args = gitArguments, options = {poUsePath, poStdErrToStdOut}
      )
      processStarted = true
      result.output = process.outputStream().readAll()
      result.exitCode = process.waitForExit()
    except CatchableError:
      result.output = getCurrentExceptionMsg()
    finally:
      if not process.isNil:
        process.close()
    if processStarted:
      return
    if attempt + 1 < GitProcessStartAttempts:
      sleep(GitProcessStartRetryMilliseconds)

proc nextNulField(value: string, cursor: var int): string =
  if cursor >= value.len:
    return
  let fieldEnd = value.find('\0', cursor)
  if fieldEnd < 0:
    result = value[cursor ..^ 1]
    cursor = value.len
  else:
    result = value[cursor ..< fieldEnd]
    cursor = fieldEnd + 1

proc gitProjectFiles(
    rootPath: string
): tuple[isRepository, succeeded: bool, files: seq[string]] =
  let listing = runGit(
    rootPath,
    ["ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "."],
  )
  if listing.exitCode != 0:
    return
  result.isRepository = true
  result.succeeded = true

  var
    cursor = 0
    seen = initHashSet[string]()
  while cursor < listing.output.len:
    let relativePath = listing.output.nextNulField(cursor)
    if relativePath.len == 0:
      continue
    if relativePath notin seen and fileExists(rootPath / relativePath):
      seen.incl relativePath
      result.files.add relativePath

proc filesystemProjectFiles(rootPath: string): seq[string] =
  var
    directories = @[rootPath]
    seen = initHashSet[string]()
  while directories.len > 0:
    let directory = directories.pop()
    try:
      for kind, path in walkDir(directory):
        case kind
        of pcDir:
          if path.extractFilename() != ".git":
            directories.add path
        of pcLinkToDir:
          discard
        of pcFile, pcLinkToFile:
          let relativePath = relativePath(path, rootPath)
          if relativePath notin seen:
            seen.incl relativePath
            result.add relativePath
    except OSError:
      discard

proc projectFiles*(rootPath: string): seq[string] =
  ## List project files, respecting Git's standard ignore rules in work trees.
  if rootPath.len == 0 or not dirExists(rootPath):
    return
  let root = absolutePath(rootPath)
  let gitFiles = gitProjectFiles(root)
  if gitFiles.isRepository:
    if gitFiles.succeeded:
      result = gitFiles.files
  else:
    result = filesystemProjectFiles(root)
  result.sort(system.cmp[string])

proc visibleItemCount(panel: KosmoQuickOpenPanel): int =
  let availableRows =
    max(int(floor(panel.resultsView.bounds().size.height / QuickOpenRowHeight)), 1)
  min(availableRows, QuickOpenMaximumVisibleItems)

proc itemCount(panel: KosmoQuickOpenPanel): int =
  max(panel.xFilteredFiles.len, 1)

proc clampFirstIndex(panel: KosmoQuickOpenPanel) =
  panel.xFirstIndex = max(
    0,
    min(panel.xFirstIndex, max(panel.xFilteredFiles.len - panel.visibleItemCount(), 0)),
  )

proc scrollHighlightedToVisible(panel: KosmoQuickOpenPanel) =
  if panel.xHighlightedIndex < panel.xFirstIndex:
    panel.xFirstIndex = panel.xHighlightedIndex
  elif panel.xHighlightedIndex >= panel.xFirstIndex + panel.visibleItemCount():
    panel.xFirstIndex = panel.xHighlightedIndex - panel.visibleItemCount() + 1
  panel.clampFirstIndex()

proc setHighlightedIndex(panel: KosmoQuickOpenPanel, index: int) =
  let boundedIndex =
    if panel.xFilteredFiles.len == 0:
      -1
    else:
      max(0, min(index, panel.xFilteredFiles.high))
  if panel.xHighlightedIndex == boundedIndex:
    return
  panel.xHighlightedIndex = boundedIndex
  panel.scrollHighlightedToVisible()
  panel.resultsView.needsDisplay = true

proc moveHighlight(panel: KosmoQuickOpenPanel, delta: int) =
  if panel.isNil or panel.xFilteredFiles.len == 0:
    return
  let current = max(panel.xHighlightedIndex, 0)
  panel.setHighlightedIndex(current + delta)

proc finishDismiss(panel: KosmoQuickOpenPanel) =
  if panel.isNil:
    return
  panel.hidden = true
  panel.needsDisplay = true
  let parent = panel.superview()
  if not parent.isNil:
    parent.needsDisplay = true

proc dismiss*(panel: KosmoQuickOpenPanel, reason = nimkit.tdrProgrammatic) =
  ## Dismiss the picker and restore the responder active before it opened.
  if panel.isNil:
    return
  let owner = panel.window()
  if owner of nimkit.Window and nimkit.Window(owner).hasActiveTransientSession():
    discard nimkit.Window(owner).endTransientSession(reason)
  panel.finishDismiss()

proc activateIndex(panel: KosmoQuickOpenPanel, index: int) =
  if panel.isNil or index notin 0 ..< panel.xFilteredFiles.len:
    return
  let
    path = panel.xRootPath / panel.xFilteredFiles[index]
    handler = panel.xOnOpen
  panel.dismiss()
  if not handler.isNil:
    handler(path)

proc activateHighlighted(panel: KosmoQuickOpenPanel) =
  if not panel.isNil:
    panel.activateIndex(panel.xHighlightedIndex)

proc filterFiles(panel: KosmoQuickOpenPanel) =
  panel.xFilteredFiles = panel.xProjectFiles.fuzzyFilterFiles(panel.queryField.text())
  panel.xFirstIndex = 0
  panel.xHighlightedIndex = if panel.xFilteredFiles.len > 0: 0 else: -1
  panel.resultsView.needsDisplay = true

proc quickOpenQueryDidChange(
    panel: KosmoQuickOpenPanel, sender: nimkit.DynamicAgent
) {.slot.} =
  discard sender
  panel.filterFiles()

protocol KosmoQuickOpenFieldCellEditing of nimkit.CellEditingProtocol:
  method fieldEditorForView(
      cell: KosmoQuickOpenFieldCell, controlView: nimkit.View
  ): nimkit.FieldEditor =
    discard controlView
    cell.editor

protocol KosmoQuickOpenEditorMovement of nimkit.TextEditingCommandProtocol:
  method moveUp(editor: KosmoQuickOpenFieldEditor, args: nimkit.ActionArgs) =
    discard args
    if not editor.panel.isNil:
      editor.panel[].moveHighlight(-1)

  method moveDown(editor: KosmoQuickOpenFieldEditor, args: nimkit.ActionArgs) =
    discard args
    if not editor.panel.isNil:
      editor.panel[].moveHighlight(1)

protocol KosmoQuickOpenEditorActivation of nimkit.KeyViewCommandProtocol:
  method insertNewline(editor: KosmoQuickOpenFieldEditor, args: nimkit.ActionArgs) =
    discard args
    if not editor.panel.isNil:
      editor.panel[].activateHighlighted()

protocol KosmoQuickOpenEditorCancellation of nimkit.MenuCommandProtocol:
  method cancelOperation(editor: KosmoQuickOpenFieldEditor, args: nimkit.ActionArgs) =
    discard args
    if not editor.panel.isNil:
      editor.panel[].dismiss(nimkit.tdrEscape)

protocol KosmoQuickOpenLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(panel: KosmoQuickOpenPanel) =
    let contentFrame = panel.contentRect()
    panel.contentView().setFrameFromLayout(contentFrame)
    let bounds = panel.contentView().bounds()
    panel.queryField.setFrameFromLayout(
      nimkit.rect(
        0, 0, bounds.size.width, min(QuickOpenFieldHeight, bounds.size.height)
      )
    )
    let resultsY = min(QuickOpenFieldHeight + QuickOpenSpacing, bounds.size.height)
    panel.resultsView.setFrameFromLayout(
      nimkit.rect(
        0, resultsY, bounds.size.width, max(bounds.size.height - resultsY, 0.0'f32)
      )
    )
    panel.clampFirstIndex()

proc newKosmoQuickOpenPanel*(rootPath = ""): KosmoQuickOpenPanel =
  result = KosmoQuickOpenPanel(xRootPath: rootPath)
  result.initBoxFields("Open File")
  let
    panel = result.unsafeWeakRef()
    editor = KosmoQuickOpenFieldEditor(panel: panel)
  editor.initFieldEditorFields()
  discard editor.withProtocol(KosmoQuickOpenEditorMovement)
  discard editor.withProtocol(KosmoQuickOpenEditorActivation)
  discard editor.withProtocol(KosmoQuickOpenEditorCancellation)

  let cell = KosmoQuickOpenFieldCell(editor: editor)
  cell.initTextFieldCellFields()
  discard cell.withProtocol(KosmoQuickOpenFieldCellEditing)
  result.queryField = nimkit.newTextField()
  result.queryField.setCell(cell)
  result.queryField.accessibilityLabel = "Open file by name"

  result.resultsView = nimkit.newPopupListView(
    nimkit.PopupListData(
      itemCount: proc(): int =
        if panel.isNil:
          0
        else:
          panel[].itemCount(),
      visibleCount: proc(): int =
        if panel.isNil:
          0
        else:
          panel[].visibleItemCount(),
      firstIndex: proc(): int =
        if panel.isNil:
          0
        else:
          panel[].xFirstIndex,
      selectedIndex: proc(): int =
        -1,
      highlightedIndex: proc(): int =
        if panel.isNil:
          -1
        else:
          panel[].xHighlightedIndex,
      rowHeight: proc(): float32 =
        QuickOpenRowHeight,
      itemText: proc(index: int): string =
        if panel.isNil or panel[].xFilteredFiles.len == 0:
          NoMatchingFilesTitle
        elif index in 0 ..< panel[].xFilteredFiles.len:
          panel[].xFilteredFiles[index]
        else:
          "",
      itemIsEnabled: proc(index: int): bool =
        not panel.isNil and index in 0 ..< panel[].xFilteredFiles.len,
      focused: proc(): bool =
        if panel.isNil:
          false
        else:
          let owner = panel[].window()
          owner of nimkit.Window and
            nimkit.Window(owner).fieldEditorClient() == panel[].queryField,
      opened: proc(): bool =
        not panel.isNil and not panel[].hidden(),
    ),
    nimkit.PopupListActions(
      highlight: proc(index: int) =
        if not panel.isNil:
          panel[].setHighlightedIndex(index)
      ,
      activate: proc(index: int) =
        if not panel.isNil:
          panel[].activateIndex(index)
      ,
      close: proc() =
        if not panel.isNil:
          panel[].dismiss()
      ,
      scroll: proc(delta: int) =
        if not panel.isNil:
          panel[].xFirstIndex += delta
          panel[].clampFirstIndex()
          panel[].resultsView.needsDisplay = true
      ,
    ),
  )
  result.contentView().addSubview(result.queryField)
  result.contentView().addSubview(result.resultsView)
  discard result.withProtocol(KosmoQuickOpenLayout)
  result.queryField.connect(nimkit.textDidChange, result, quickOpenQueryDidChange)
  result.hidden = true
  result.filterFiles()

proc rootPath*(panel: KosmoQuickOpenPanel): string =
  if panel.isNil: "" else: panel.xRootPath

proc projectFiles*(panel: KosmoQuickOpenPanel): seq[string] =
  if not panel.isNil:
    result = panel.xProjectFiles

proc filteredFiles*(panel: KosmoQuickOpenPanel): seq[string] =
  if not panel.isNil:
    result = panel.xFilteredFiles

proc highlightedIndex*(panel: KosmoQuickOpenPanel): int =
  if panel.isNil: -1 else: panel.xHighlightedIndex

proc highlightedFile*(panel: KosmoQuickOpenPanel): string =
  if not panel.isNil and panel.xHighlightedIndex in 0 ..< panel.xFilteredFiles.len:
    result = panel.xFilteredFiles[panel.xHighlightedIndex]

proc isOpen*(panel: KosmoQuickOpenPanel): bool =
  not panel.isNil and not panel.hidden()

proc reloadProjectFiles*(panel: KosmoQuickOpenPanel, rootPath = "") =
  ## Refresh the picker index for a project root.
  if panel.isNil:
    return
  if rootPath.len > 0:
    panel.xRootPath = absolutePath(rootPath)
  panel.xProjectFiles = projectFiles(panel.xRootPath)
  panel.filterFiles()

proc present*(
    panel: KosmoQuickOpenPanel,
    window: nimkit.Window,
    rootPath: string,
    onOpen: KosmoQuickOpenHandler,
): bool {.discardable.} =
  ## Show the picker, focus its query, and preserve the previous responder.
  if panel.isNil or window.isNil:
    return
  panel.xOnOpen = onOpen
  if panel.isOpen():
    return window.makeFirstResponder(panel.queryField)

  panel.queryField.text = ""
  panel.reloadProjectFiles(rootPath)
  panel.hidden = false
  panel.needsDisplay = true
  let weakPanel = panel.unsafeWeakRef()
  window.beginTransientSession(
    owner = nimkit.Responder(panel),
    onDismiss = proc(reason: nimkit.DismissReason) =
      discard reason
      if not weakPanel.isNil:
        weakPanel[].finishDismiss()
    ,
  )
  result = window.makeFirstResponder(panel.queryField)
  if not result:
    discard window.endTransientSession()
    panel.finishDismiss()
