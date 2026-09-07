## Fuzzy project-file picker used by Kosmo's quick-open command.

import std/[algorithm, math, monotimes, os, strutils, tables, times]

import sigils/[core, threads]
from figdraw import ZLevel

import ../nimkit as nimkit
import ./workspacefiles
export workspacefiles.projectFiles
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
  LoadingFilesTitle = "Loading files…"

type
  KosmoQuickOpenHandler* = proc(path: string) {.closure.}

  QuickOpenProgressIndicator = ref object of nimkit.ProgressIndicator

  KosmoQuickOpenPanel* = ref object of nimkit.Box
    queryField*: nimkit.TextField
    resultsView*: nimkit.PopupListView
    progressIndicator*: nimkit.ProgressIndicator
    xRootPath: string
    xRootPaths: seq[string]
    xFilePaths: Table[string, string]
    xProjectFiles: seq[string]
    xFilteredFiles: seq[string]
    xHighlightedIndex: int
    xFirstIndex: int
    xOnOpen: KosmoQuickOpenHandler
    xObservedWindow: WeakRef[nimkit.Window]
    xPresentationOffset: float32
    xPresentationAnimation: nimkit.Animation
    xWorkspaceFiles: WorkspaceFiles
    xLoading: bool

  KosmoQuickOpenFieldEditor = ref object of nimkit.FieldEditor
    panel: WeakRef[KosmoQuickOpenPanel]

  KosmoQuickOpenFieldCell = ref object of nimkit.TextFieldCell
    editor: KosmoQuickOpenFieldEditor

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

protocol QuickOpenProgressDrawing of nimkit.ViewDrawingProtocol:
  method drawLevel(indicator: QuickOpenProgressIndicator): ZLevel =
    nimkit.PopupDrawLevel

proc moveHighlight(panel: KosmoQuickOpenPanel, delta: int)
proc activateHighlighted(panel: KosmoQuickOpenPanel)
proc filterFiles(panel: KosmoQuickOpenPanel)
proc scrollHighlightedToVisible(panel: KosmoQuickOpenPanel)

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

proc applyProjectFiles(panel: KosmoQuickOpenPanel) {.slot.} =
  template files(): untyped =
    panel.xWorkspaceFiles.snapshot()

  let highlighted =
    if panel.xHighlightedIndex in 0 ..< panel.xFilteredFiles.len:
      panel.xFilteredFiles[panel.xHighlightedIndex]
    else:
      ""
  panel.xRootPaths = files.roots
  panel.xRootPath =
    if files.roots.len > 0:
      files.roots[0]
    else:
      ""
  panel.xProjectFiles = files.labels
  panel.xFilePaths.clear()
  for index, label in files.labels:
    panel.xFilePaths[label] = files.paths[index]
  panel.xLoading = false
  panel.progressIndicator.stopAnimation()
  panel.filterFiles()
  let selected = panel.xFilteredFiles.find(highlighted)
  if selected >= 0:
    panel.xHighlightedIndex = selected
    panel.scrollHighlightedToVisible()

proc workspaceFiles*(panel: KosmoQuickOpenPanel): WorkspaceFiles =
  panel.xWorkspaceFiles

proc `workspaceFiles=`*(panel: KosmoQuickOpenPanel, files: WorkspaceFiles) =
  ## Borrow the browser's controller, rather than maintaining a second index.
  if files.isNil or panel.xWorkspaceFiles == files:
    return
  if not panel.xWorkspaceFiles.isNil:
    panel.xWorkspaceFiles.disconnect(workspaceFilesDidChange, panel, applyProjectFiles)
  panel.xWorkspaceFiles = files
  files.connect(workspaceFilesDidChange, panel, applyProjectFiles)
  panel.applyProjectFiles()

proc beginProjectFileLoad(panel: KosmoQuickOpenPanel, rootPaths: openArray[string]) =
  panel.xWorkspaceFiles.setRoots(rootPaths)
  panel.applyProjectFiles()
  panel.xLoading = panel.xWorkspaceFiles.isLoading()
  if panel.xLoading:
    panel.progressIndicator.startAnimation()
  panel.resultsView.needsDisplay = true

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
    path = panel.xFilePaths[panel.xFilteredFiles[index]]
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
    panel.progressIndicator.setFrameFromLayout(
      nimkit.rect(
        max(bounds.size.width - 28, 0),
        resultsY + 2,
        20,
        min(20, max(bounds.size.height - resultsY - 4, 0)),
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
      contentFrame = panel.contentRect()
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
        titleHeight = title.textNaturalSize(panelStyle.text).height
        textRect = nimkit.rect(
          bounds.origin.x + panelStyle.contentInsets.left + panelStyle.text.insets.left,
          bounds.origin.y,
          max(
            bounds.size.width - panelStyle.contentInsets.horizontal -
              panelStyle.text.insets.horizontal,
            0.0'f32,
          ),
          max(contentFrame.origin.y - bounds.origin.y, titleHeight),
        )
        titleText = title.clippedText(textRect.size.width, panelStyle.text)
      if titleText.len > 0 and not textRect.isEmpty:
        context.addText(
          textRect, titleText, panelStyle.text, alignment = nimkit.taCenter
        )

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
        if panel.isNil: 0 else: panel[].xFirstIndex,
      selectedIndex: proc(): int =
        -1,
      highlightedIndex: proc(): int =
        if panel.isNil: -1 else: panel[].xHighlightedIndex,
      rowHeight: proc(): float32 =
        QuickOpenRowHeight,
      itemText: proc(index: int): string =
        if not panel.isNil and panel[].xLoading:
          LoadingFilesTitle
        elif panel.isNil or panel[].xFilteredFiles.len == 0:
          NoMatchingFilesTitle
        elif index in 0 ..< panel[].xFilteredFiles.len:
          panel[].xFilteredFiles[index]
        else:
          "",
      itemIsEnabled: proc(index: int): bool =
        not panel.isNil and not panel[].xLoading and
          index in 0 ..< panel[].xFilteredFiles.len,
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
  let progressIndicator = QuickOpenProgressIndicator()
  progressIndicator.initProgressIndicatorFields()
  discard progressIndicator.withProtocol(QuickOpenProgressDrawing)
  result.progressIndicator = progressIndicator
  result.progressIndicator.indeterminate = true
  result.progressIndicator.displayedWhenStopped = false
  result.progressIndicator.progressIndicatorStyle = nimkit.pisSpinning
  result.progressIndicator.accessibilityLabel = LoadingFilesTitle
  result.contentView().addSubview(result.queryField)
  result.contentView().addSubview(result.resultsView)
  result.contentView().addSubview(result.progressIndicator)
  discard result.withProtocol(KosmoQuickOpenLayout)
  result.queryField.connect(nimkit.textDidChange, result, quickOpenQueryDidChange)
  result.applyQuickOpenAppearance(result.effectiveAppearance())
  result.hidden = true
  result.filterFiles()

  result.workspaceFiles = newWorkspaceFiles()

proc rootPath*(panel: KosmoQuickOpenPanel): string =
  if panel.isNil: "" else: panel.xRootPath

proc rootPaths*(panel: KosmoQuickOpenPanel): seq[string] =
  ## Return the indexed folders in browser order.
  if not panel.isNil:
    result = panel.xRootPaths

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

proc isLoading*(panel: KosmoQuickOpenPanel): bool =
  ## Return whether the picker is indexing its current project roots.
  not panel.isNil and panel.xLoading

proc waitForProjectFiles*(
    panel: KosmoQuickOpenPanel, timeoutMilliseconds = 10_000
): bool =
  ## Deliver worker results until project indexing finishes in tests or tools.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
  while panel.isLoading() and getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    sleep(1)
  not panel.isLoading()

proc reloadProjectFiles*(panel: KosmoQuickOpenPanel, rootPaths: openArray[string]) =
  ## Index all roots, preserving distinct names and deduplicating overlapping files.
  if panel.isNil:
    return
  panel.xWorkspaceFiles.reload(rootPaths)

proc reloadProjectFiles*(panel: KosmoQuickOpenPanel, rootPath = "") =
  ## Refresh a single root, or the current roots when no argument is supplied.
  if not panel.isNil:
    if rootPath.len > 0:
      panel.reloadProjectFiles([rootPath])
    elif panel.xRootPaths.len > 0:
      panel.reloadProjectFiles(panel.xRootPaths)
    else:
      panel.reloadProjectFiles([panel.xRootPath])

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
    rootPaths: openArray[string],
    onOpen: KosmoQuickOpenHandler,
): bool {.discardable.} =
  ## Show the picker, focus its query, and preserve the previous responder.
  if panel.isNil or window.isNil:
    return
  panel.xOnOpen = onOpen
  if panel.isOpen():
    if @rootPaths != panel.xRootPaths:
      panel.beginProjectFileLoad(rootPaths)
    return window.makeFirstResponder(panel.queryField)

  panel.queryField.text = ""
  panel.hidden = false
  panel.beginProjectFileLoad(rootPaths)
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

proc present*(
    panel: KosmoQuickOpenPanel,
    window: nimkit.Window,
    rootPath: string,
    onOpen: KosmoQuickOpenHandler,
): bool {.discardable.} =
  ## Show a picker for one folder.
  panel.present(window, [rootPath], onOpen)
