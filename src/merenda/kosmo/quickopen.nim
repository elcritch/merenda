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
  QuickOpenPresentationDurationMilliseconds = 100
  QuickOpenOuterBlurRadius = 20.0'f32
  QuickOpenInnerBlurRadius = 14.0'f32
  QuickOpenOuterTintOpacity = 0.18'f32
  QuickOpenInnerTintOpacity = 0.58'f32
  QuickOpenControlFillOpacity = 0.10'f32
  QuickOpenRowFillOpacity = 0.10'f32
  QuickOpenHighlightedRowFillOpacity = 0.38'f32
  QuickOpenPanelStyleId = "kosmo.quick-open.panel"
  QuickOpenFieldStyleId = "kosmo.quick-open.field"
  QuickOpenResultsStyleId = "kosmo.quick-open.results"
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
    xObservedWindow: WeakRef[nimkit.Window]
    xPresentationOffset: float32
    xPresentationAnimation: nimkit.Animation

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

protocol KosmoQuickOpenPresentationProtocol {.
  selectorScope: protocol, setterStyle: nim
.}:
  property presentationOffset -> float32

protocol DefaultKosmoQuickOpenPresentation of KosmoQuickOpenPresentationProtocol:
  method presentationOffset(panel: KosmoQuickOpenPanel): float32 =
    panel.xPresentationOffset

  method `presentationOffset=`(panel: KosmoQuickOpenPanel, offset: float32) =
    if panel.xPresentationOffset == offset:
      return
    panel.xPresentationOffset = offset
    let parent = panel.superview()
    if not parent.isNil:
      parent.needsLayout = true
    panel.needsDisplay = true

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

proc stopPresentationAnimation(panel: KosmoQuickOpenPanel, finished = true) =
  if panel.isNil or panel.xPresentationAnimation.isNil:
    return
  let owner = panel.window()
  if owner of nimkit.Window:
    discard nimkit.Window(owner).stopAnimation(
        panel.xPresentationAnimation, finished = finished
      )
  else:
    panel.xPresentationAnimation.stop(finished)
  panel.xPresentationAnimation = nil

proc finishDismiss(panel: KosmoQuickOpenPanel) =
  if panel.isNil:
    return
  panel.stopPresentationAnimation()
  panel.presentationOffset = 0.0'f32
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

func tint(fill: nimkit.Fill, opacity: float32): nimkit.Fill =
  let base = fill.centerColor()
  nimkit.fill(nimkit.color(base.r, base.g, base.b, opacity))

proc frameInPanel(panel: KosmoQuickOpenPanel, view: nimkit.View): nimkit.Rect =
  let
    contentFrame = panel.contentRect()
    childFrame = view.frame()
  nimkit.rect(
    contentFrame.origin.x + childFrame.origin.x,
    contentFrame.origin.y + childFrame.origin.y,
    childFrame.size.width,
    childFrame.size.height,
  )

protocol KosmoQuickOpenPanelDrawing of nimkit.ViewDrawingProtocol:
  method draw(panel: KosmoQuickOpenPanel, context: nimkit.DrawContext) =
    let bounds = panel.bounds()
    if bounds.isEmpty:
      return

    let
      appearance = context.appearance()
      panelStyle = appearance.resolveBoxStyle(
        nimkit.controlStyle(nimkit.srBox, id = QuickOpenPanelStyleId)
      )
      basePanelStyle = appearance.resolveBoxStyle(nimkit.controlStyle(nimkit.srBox))
      fieldStyle = appearance.resolveTextFieldStyle(
        nimkit.controlStyle(nimkit.srTextField, id = QuickOpenFieldStyleId)
      )
      baseFieldStyle =
        appearance.resolveTextFieldStyle(nimkit.controlStyle(nimkit.srTextField))
      popupStates = {nimkit.ssFocused, nimkit.ssOpen}
      popupStyle = appearance.resolveComboBoxStyle(
        nimkit.controlStyle(
          nimkit.srComboBox, popupStates, id = QuickOpenResultsStyleId
        )
      )
      basePopupStyle = appearance.resolveComboBoxStyle(
        nimkit.controlStyle(nimkit.srComboBox, popupStates)
      )
      panelFrame = context.renderRectFor(bounds)
      queryFrame = context.renderRectFor(panel.frameInPanel(panel.queryField))
      resultsFrame = context.renderRectFor(panel.frameInPanel(panel.resultsView))

    discard context.addRenderBackdropBlur(
      context.renderLayer(),
      context.renderParent(),
      panelFrame,
      basePanelStyle.box.fill.tint(QuickOpenOuterTintOpacity),
      QuickOpenOuterBlurRadius,
      panelStyle.box.cornerRadius,
      panelStyle.box.cornerRadii,
    )
    discard context.addRenderRectangle(
      panelFrame,
      nimkit.fill(nimkit.color(0.0, 0.0, 0.0, 0.0)),
      panelStyle.box.borderColor,
      panelStyle.box.borderWidth,
      panelStyle.box.cornerRadius,
      panelStyle.box.shadows,
      cornerRadii = panelStyle.box.cornerRadii,
    )
    discard context.addRenderBackdropBlur(
      context.renderLayer(),
      context.renderParent(),
      queryFrame,
      baseFieldStyle.box.fill.tint(QuickOpenInnerTintOpacity),
      QuickOpenInnerBlurRadius,
      fieldStyle.box.cornerRadius,
      fieldStyle.box.cornerRadii,
    )
    discard context.addRenderBackdropBlur(
      nimkit.PopupDrawLevel,
      resultsFrame,
      basePopupStyle.box.fill.tint(QuickOpenInnerTintOpacity),
      QuickOpenInnerBlurRadius,
      popupStyle.box.cornerRadius,
      popupStyle.box.cornerRadii,
    )

    let title = panel.boxTitle()
    if title.len > 0:
      let
        textRect = nimkit.rect(
          bounds.origin.x + panelStyle.contentInsets.left + panelStyle.text.insets.left,
          bounds.origin.y,
          max(
            bounds.size.width - panelStyle.contentInsets.horizontal -
              panelStyle.text.insets.horizontal,
            0.0'f32,
          ),
          max(panelStyle.titleHeight, title.textNaturalSize(panelStyle.text).height),
        )
        titleText = title.clippedText(textRect.size.width, panelStyle.text)
      if titleText.len > 0 and not textRect.isEmpty:
        context.addText(textRect, titleText, panelStyle.text)

proc applyQuickOpenAppearance(panel: KosmoQuickOpenPanel, base: nimkit.Appearance) =
  var appearance = base
  let
    panelSelector = nimkit.initStyleSelector(nimkit.srBox, id = QuickOpenPanelStyleId)
    fieldSelector =
      nimkit.initStyleSelector(nimkit.srTextField, id = QuickOpenFieldStyleId)
    resultsSelector =
      nimkit.initStyleSelector(nimkit.srComboBox, id = QuickOpenResultsStyleId)
    rowSelector =
      nimkit.initStyleSelector(nimkit.srComboBoxItem, id = QuickOpenResultsStyleId)
    highlightedRowSelector = nimkit.initStyleSelector(
      nimkit.srComboBoxItem, {nimkit.ssHovered}, id = QuickOpenResultsStyleId
    )
    fieldFill =
      base.resolveTextFieldStyle(nimkit.controlStyle(nimkit.srTextField)).box.fill
    resultsFill = base.resolveComboBoxStyle(
      nimkit.controlStyle(nimkit.srComboBox, {nimkit.ssFocused, nimkit.ssOpen})
    ).box.fill
    rowFill =
      base.resolveRowItemStyle(nimkit.controlStyle(nimkit.srComboBoxItem)).box.fill
    highlightedRowFill = base.resolveRowItemStyle(
      nimkit.controlStyle(nimkit.srComboBoxItem, {nimkit.ssHovered})
    ).box.fill
    titleText = base.resolveTextFieldStyle(
      nimkit.controlStyle(
        nimkit.srTextField,
        classes = @[nimkit.LabelStyleClass, nimkit.LabelTitleStyleClass],
      )
    ).text

  appearance.setStyle(
    panelSelector,
    nimkit.StyleFill,
    base.resolveBoxStyle(nimkit.controlStyle(nimkit.srBox)).box.fill.tint(
      QuickOpenOuterTintOpacity
    ),
  )
  appearance.setStyle(panelSelector, nimkit.StyleTextColor, titleText.color)
  appearance.setStyle(panelSelector, nimkit.StyleFontSize, titleText.fontSize)
  appearance.setStyle(
    fieldSelector, nimkit.StyleFill, fieldFill.tint(QuickOpenControlFillOpacity)
  )
  appearance.setStyle(
    fieldSelector, nimkit.StyleChrome, nimkit.styleKeyword(nimkit.DefaultChromeName)
  )
  appearance.setStyle(fieldSelector, nimkit.StyleBoxShadows, newSeq[nimkit.BoxShadow]())
  appearance.setStyle(
    resultsSelector, nimkit.StyleFill, resultsFill.tint(QuickOpenControlFillOpacity)
  )
  appearance.setStyle(
    resultsSelector, nimkit.StyleChrome, nimkit.styleKeyword(nimkit.DefaultChromeName)
  )
  appearance.setStyle(
    resultsSelector, nimkit.StyleBoxShadows, newSeq[nimkit.BoxShadow]()
  )
  appearance.setStyle(
    rowSelector, nimkit.StyleFill, rowFill.tint(QuickOpenRowFillOpacity)
  )
  appearance.setStyle(
    highlightedRowSelector,
    nimkit.StyleFill,
    highlightedRowFill.tint(QuickOpenHighlightedRowFillOpacity),
  )
  panel.appearance = appearance

protocol KosmoQuickOpenAppearanceObserver of nimkit.WindowAppearanceEvents:
  proc didChangeEffectiveAppearance(
      panel: KosmoQuickOpenPanel, appearance: nimkit.Appearance
  ) {.slot.} =
    panel.applyQuickOpenAppearance(appearance)

proc stopObservingWindow*(panel: KosmoQuickOpenPanel) =
  ## Stop mirroring appearance changes from the popup's host window.
  if panel.isNil or panel.xObservedWindow.isNil:
    return
  panel.unobserveProtocol(panel.xObservedWindow[], nimkit.WindowAppearanceEvents)
  panel.xObservedWindow = default(WeakRef[nimkit.Window])

proc observeWindow*(panel: KosmoQuickOpenPanel, window: nimkit.Window) =
  ## Keep the popup's translucent styling synchronized with its host window.
  if panel.isNil:
    return
  panel.stopObservingWindow()
  if window.isNil:
    return
  panel.xObservedWindow = window.unsafeWeakRef()
  panel.observeProtocol(window, nimkit.WindowAppearanceEvents)
  panel.applyQuickOpenAppearance(window.effectiveAppearance())

proc newKosmoQuickOpenPanel*(rootPath = ""): KosmoQuickOpenPanel =
  result = KosmoQuickOpenPanel(xRootPath: rootPath)
  result.initBoxFields("Open File")
  result.styleId = QuickOpenPanelStyleId
  discard result.withProtocol(DefaultKosmoQuickOpenPresentation)
  discard result.withProtocol(KosmoQuickOpenPanelDrawing)
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
  result.queryField.styleId = QuickOpenFieldStyleId
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
      styleId: proc(): string =
        QuickOpenResultsStyleId,
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
  result.applyQuickOpenAppearance(result.effectiveAppearance())
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

proc startPresentationAnimation(panel: KosmoQuickOpenPanel, window: nimkit.Window) =
  if panel.isNil or window.isNil:
    return
  panel.stopPresentationAnimation()
  let parent = panel.superview()
  if parent.isNil:
    return

  parent.layoutSubtreeIfNeeded()
  let
    restingFrame = panel.frame()
    topEdge = parent.bounds().origin.y
    startOffset = topEdge - restingFrame.origin.y - restingFrame.size.height
  if restingFrame.size.height <= 0.0'f32 or abs(startOffset) <= 0.001'f32:
    return

  panel.presentationOffset = startOffset
  parent.layoutSubtreeIfNeeded()
  let animation = nimkit.newPropertyAnimation[float32](
    DynamicAgent(panel),
    `presentationOffset=`(),
    startOffset,
    0.0'f32,
    duration = nimkit.ms(QuickOpenPresentationDurationMilliseconds),
  )
  animation.timing = nimkit.easeOutTiming()
  panel.xPresentationAnimation = nimkit.Animation(animation)
  if not window.startAnimation(panel.xPresentationAnimation):
    panel.presentationOffset = 0.0'f32
    parent.layoutSubtreeIfNeeded()
    panel.xPresentationAnimation = nil

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
  else:
    panel.startPresentationAnimation(window)
