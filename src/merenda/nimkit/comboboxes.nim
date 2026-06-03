import std/options

import ./controls
import ./listviews
import ./selectors
import ./textfields
import ./theme
import ./types
import ./windows

export controls

type
  ComboBox* = ref object of Control
    xDataSource: DynamicAgent
    xDelegate: DynamicAgent
    xPopupOpen: bool
    xPopupHighlightedIndex: int
    xButtonPressed: bool
    xPopupWindow: Window
    xPopupPresentation: PopupPresentation
    xPopupViewport: ListViewport
    xPopupList: PopupListView

  ComboBoxCell* = ref object of ActionCell
    xItems: seq[string]
    xStringValue: string
    xSelectedIndex: int
    xEditable: bool
    xMaxVisibleItems: int
    xItemHeight: float32

proc comboBoxCell*(comboBox: ComboBox): ComboBoxCell
proc dataSource*(comboBox: ComboBox): DynamicAgent
proc highlightedIndex*(comboBox: ComboBox): int
proc setHighlightedIndex*(comboBox: ComboBox, index: int)
proc popupListData(comboBox: ComboBox): PopupListData
proc popupListActions(comboBox: ComboBox): PopupListActions
proc popupList(comboBox: ComboBox): PopupListView
proc visibleItemCount*(comboBox: ComboBox): int
proc popupItemHeight*(comboBox: ComboBox): float32
proc popupFirstItemIndex*(comboBox: ComboBox): int
proc scrollPopupItemToVisible(comboBox: ComboBox, itemIndex: int)
proc setPopupNeedsDisplay(comboBox: ComboBox)
proc setHoveredPopupIndex(comboBox: ComboBox, index: int)
proc popupRect*(comboBox: ComboBox, bounds: Rect): Rect
proc popupItemRect*(comboBox: ComboBox, bounds: Rect, itemIndex: int): Rect
proc popupItemIndexAtPoint*(comboBox: ComboBox, bounds: Rect, point: Point): int
proc popupScrollIndicatorRect*(comboBox: ComboBox, bounds: Rect): Rect
proc movePopupHighlight*(comboBox: ComboBox, delta: int)
proc movePopupHighlightTo(comboBox: ComboBox, index: int)
proc pagePopupHighlight(comboBox: ComboBox, deltaPages: int)
proc scrollPopupRows(comboBox: ComboBox, delta: int)
proc notifyComboBoxSelectionIsChanging(comboBox: ComboBox)
proc notifyComboBoxSelectionDidChange(comboBox: ComboBox)
proc popupPresentationPreference(comboBox: ComboBox): PopupPresentation
proc popupWindowActive(comboBox: ComboBox): bool
proc shouldUseWindowPopup(comboBox: ComboBox): bool
proc usesInlinePopup(comboBox: ComboBox): bool
proc beginPopupSession(comboBox: ComboBox)
proc endPopupSession(comboBox: ComboBox, reason = tdrProgrammatic): bool
proc dismissPopupFromSession(comboBox: ComboBox, reason: TransientDismissReason)
proc openPopupWindow(comboBox: ComboBox)
proc closePopupWindow(comboBox: ComboBox, restoreOwner = true)
proc reactivateOwnerWindow(comboBox: ComboBox)
proc updatePopupPresentation(comboBox: ComboBox)

proc cellStringValue(cell: ComboBoxCell): string
proc setCellSelectedIndex(cell: ComboBoxCell, index: int)
proc cellMaxVisibleItems(cell: ComboBoxCell): int
proc setCellMaxVisibleItems(cell: ComboBoxCell, value: int)
proc cellItemHeight(cell: ComboBoxCell): float32
proc setCellItemHeight(cell: ComboBoxCell, value: float32)
proc cellIsEditable(cell: ComboBoxCell): bool
proc setCellEditable(cell: ComboBoxCell, editable: bool)
proc cellNumberOfItems(cell: ComboBoxCell): int
proc cellItemAtIndex(cell: ComboBoxCell, index: int): string
proc cellAddItem(cell: ComboBoxCell, value: string)
proc cellInsertItem(cell: ComboBoxCell, value: string, index: int)
proc cellRemoveItemAtIndex(cell: ComboBoxCell, index: int)
proc cellRemoveAllItems(cell: ComboBoxCell)

protocol ComboBoxDataSourceProtocolInternal:
  method numberOfItemsInComboBox*(comboBox: ComboBox): int {.optional.}
  method comboBoxObjectValueForItemAtIndex*(
    comboBox: ComboBox, index: int
  ): string {.optional.}

protocol ComboBoxDelegateProtocolInternal:
  method comboBoxSelectionIsChanging*(args: ActionArgs) {.optional.}
  method comboBoxSelectionDidChange*(args: ActionArgs) {.optional.}

protocol ComboBoxViewProtocolInternal:
  method pointInside*(point: Point): bool

protocol ComboBoxProtocolInternal from ComboBox:
  property selectedIndex -> int
  property popupOpen -> bool
  property maxVisibleItems -> int
  property itemHeight -> float32
  property popupPresentation -> PopupPresentation

  method selectedIndex(comboBox: ComboBox): int =
    comboBox.indexOfSelectedItem()

  method setSelectedIndex(comboBox: ComboBox, index: int) =
    if index < 0:
      comboBox.deselectItem()
    else:
      comboBox.selectItemAtIndex(index)

  method popupOpen(comboBox: ComboBox): bool =
    not comboBox.isNil and comboBox.xPopupOpen

  method setPopupOpen(comboBox: ComboBox, open: bool) =
    if comboBox.isNil:
      return
    let shouldOpen = open and comboBox.isEnabled and comboBox.numberOfItems() > 0
    if comboBox.xPopupOpen == shouldOpen:
      if shouldOpen:
        comboBox.updatePopupPresentation()
      return

    comboBox.xPopupOpen = shouldOpen
    if comboBox.xPopupOpen:
      let selected = comboBox.indexOfSelectedItem()
      comboBox.xPopupHighlightedIndex = if selected >= 0: selected else: 0
      comboBox.scrollPopupItemToVisible(comboBox.xPopupHighlightedIndex)
      comboBox.updatePopupPresentation()
    else:
      discard comboBox.endPopupSession()
      comboBox.closePopupWindow()
      comboBox.xPopupHighlightedIndex = -1
      comboBox.xButtonPressed = false
      comboBox.popupList().resetPopupListTracking()
      comboBox.xPopupViewport.reset()
    comboBox.setNeedsDisplay(true)

  method maxVisibleItems(comboBox: ComboBox): int =
    comboBox.comboBoxCell().cellMaxVisibleItems()

  method setMaxVisibleItems(comboBox: ComboBox, value: int) =
    comboBox.comboBoxCell().setCellMaxVisibleItems(value)
    if comboBox.popupOpen():
      comboBox.scrollPopupItemToVisible(comboBox.highlightedIndex())
      comboBox.updatePopupPresentation()
      comboBox.setPopupNeedsDisplay()

  method itemHeight(comboBox: ComboBox): float32 =
    comboBox.comboBoxCell().cellItemHeight()

  method setItemHeight(comboBox: ComboBox, value: float32) =
    comboBox.comboBoxCell().setCellItemHeight(value)
    if comboBox.popupOpen():
      comboBox.scrollPopupItemToVisible(comboBox.highlightedIndex())
      comboBox.updatePopupPresentation()
      comboBox.setPopupNeedsDisplay()

  method popupPresentation(comboBox: ComboBox): PopupPresentation =
    if comboBox.isNil:
      return ppAutomatic
    comboBox.xPopupPresentation

  method setPopupPresentation(comboBox: ComboBox, presentation: PopupPresentation) =
    if comboBox.isNil or comboBox.xPopupPresentation == presentation:
      return
    comboBox.xPopupPresentation = presentation
    comboBox.updatePopupPresentation()
    comboBox.setNeedsDisplay(true)

  method numberOfItems*(comboBox: ComboBox): int =
    let source = comboBox.dataSource()
    if not source.isNil:
      let count = source.trySendLocal(numberOfItemsInComboBox(), comboBox)
      if count.isSome:
        return max(count.get(), 0)
    comboBox.comboBoxCell().cellNumberOfItems()

  method itemAtIndex*(comboBox: ComboBox, index: int): string =
    if index < 0 or index >= comboBox.numberOfItems():
      return ""
    let source = comboBox.dataSource()
    if not source.isNil:
      let item = source.trySendLocal(
        comboBoxObjectValueForItemAtIndex(), (comboBox: comboBox, index: index)
      )
      if item.isSome:
        return item.get()
    comboBox.comboBoxCell().cellItemAtIndex(index)

  method indexOfItem*(comboBox: ComboBox, value: string): int =
    for idx in 0 ..< comboBox.numberOfItems():
      if comboBox.itemAtIndex(idx) == value:
        return idx
    -1

  method indexOfSelectedItem*(comboBox: ComboBox): int =
    let cell = comboBox.comboBoxCell()
    if cell.xSelectedIndex >= 0 and cell.xSelectedIndex < comboBox.numberOfItems() and
        comboBox.itemAtIndex(cell.xSelectedIndex) == cell.xStringValue:
      return cell.xSelectedIndex
    cell.xSelectedIndex = comboBox.indexOfItem(cell.xStringValue)
    cell.xSelectedIndex

  method selectItemAtIndex*(comboBox: ComboBox, index: int) =
    if index < 0 or index >= comboBox.numberOfItems():
      return
    let
      cell = comboBox.comboBoxCell()
      value = comboBox.itemAtIndex(index)
    if cell.xSelectedIndex == index and cell.xStringValue == value:
      return
    cell.xSelectedIndex = index
    cell.xStringValue = value
    cell.invalidateControlMetrics()

  method deselectItem*(comboBox: ComboBox) =
    let cell = comboBox.comboBoxCell()
    if cell.xSelectedIndex < 0 and cell.xStringValue.len == 0:
      return
    cell.xSelectedIndex = -1
    cell.xStringValue = ""
    comboBox.setHighlightedIndex(-1)
    cell.invalidateControlMetrics()

  method addItem*(comboBox: ComboBox, value: string) =
    comboBox.comboBoxCell().cellAddItem(value)

  method insertItem*(comboBox: ComboBox, value: string, index: int) =
    comboBox.comboBoxCell().cellInsertItem(value, index)

  method removeItemAtIndex*(comboBox: ComboBox, index: int) =
    comboBox.comboBoxCell().cellRemoveItemAtIndex(index)
    if comboBox.numberOfItems() == 0:
      comboBox.closePopup()

  method removeAllItems*(comboBox: ComboBox) =
    comboBox.comboBoxCell().cellRemoveAllItems()
    comboBox.closePopup()

  method activateItemAtIndex*(comboBox: ComboBox, index: int) =
    if index < 0 or index >= comboBox.numberOfItems():
      return
    comboBox.selectItemAtIndex(index)
    comboBox.notifyComboBoxSelectionDidChange()
    discard comboBox.sendAction()

  method openPopup*(comboBox: ComboBox) =
    comboBox.setPopupOpen(true)

  method closePopup*(comboBox: ComboBox) =
    comboBox.setPopupOpen(false)

  method togglePopup*(comboBox: ComboBox) =
    comboBox.setPopupOpen(not comboBox.popupOpen())

  method reloadData*(comboBox: ComboBox) =
    let cell = comboBox.comboBoxCell()
    if comboBox.numberOfItems() == 0:
      cell.xSelectedIndex = -1
      cell.xStringValue = ""
      comboBox.closePopup()
    else:
      cell.xSelectedIndex = comboBox.indexOfItem(cell.xStringValue)
      if cell.xSelectedIndex < 0 and cell.xStringValue.len > 0:
        cell.xStringValue = ""
    comboBox.invalidateIntrinsicContentSize()
    comboBox.setNeedsDisplay(true)

protocol DefaultComboBoxView of ComboBoxViewProtocolInternal:
  method pointInside(comboBox: ComboBox, point: Point): bool =
    comboBox.bounds().contains(point) or (
      comboBox.usesInlinePopup() and
      comboBox.popupRect(comboBox.bounds()).contains(point)
    )

  method hitTestLevel(comboBox: ComboBox, point: Point): int =
    if comboBox.usesInlinePopup() and
        comboBox.popupRect(comboBox.bounds()).contains(point):
      PopupDrawLevel.int
    else:
      DefaultDrawLevel.int

protocol DefaultComboBoxAction of ButtonActionProtocol:
  method performClick(comboBox: ComboBox, args: ActionArgs) =
    if comboBox.isEnabled:
      if comboBox.popupOpen() and comboBox.highlightedIndex() >= 0:
        comboBox.activateItemAtIndex(comboBox.highlightedIndex())
        comboBox.closePopup()
      else:
        comboBox.togglePopup()

protocol DefaultComboBoxDrawing of ViewDrawingProtocol:
  method draw(comboBox: ComboBox, context: DrawContext) =
    let
      absoluteFrame = comboBox.rectToWindow(comboBox.bounds)
      style = context.appearance.resolveComboBoxStyle(
        initControlStyleContext(
          srComboBox,
          enabled = comboBox.isEnabled,
          highlighted = comboBox.isButtonPressed,
          hovered = comboBox.isHovered,
          active = comboBox.isActive,
          focused = comboBox.isFocused,
          focusVisible = comboBox.isFocusVisible,
          opened = comboBox.popupOpen,
          id = comboBox.styleId,
          classes = comboBox.styleClasses,
        )
      )

    discard context.addWindowRectangle(
      absoluteFrame, style.box.fill, style.box.borderColor, style.box.borderWidth,
      style.box.cornerRadius, style.box.shadows,
    )
    if comboBox.isFocusVisible:
      context.addFocusRing(absoluteFrame, style.box)

    let
      arrowRect = style.comboBoxArrowRect(comboBox.bounds)
      arrowFrame = comboBox.rectToWindow(arrowRect)
      arrowFill =
        if comboBox.isButtonPressed or comboBox.popupOpen:
          linear(
            initColor(0.86, 0.93, 1.0, 1.0), initColor(0.56, 0.76, 0.96, 1.0), fgaY
          )
        else:
          linear(initColor(1.0, 1.0, 1.0, 1.0), initColor(0.83, 0.90, 0.98, 1.0), fgaY)
      separatorRect = initRect(
        arrowRect.origin.x,
        arrowRect.origin.y + 2.0'f32,
        1.0'f32,
        max(arrowRect.size.height - 4.0'f32, 0.0'f32),
      )
    discard
      context.addWindowRectangle(arrowFrame, arrowFill, style.box.borderColor, 0.0'f32)
    discard context.addWindowRectangle(
      comboBox.rectToWindow(separatorRect), style.box.borderColor, style.box.borderColor
    )
    context.addComboBoxArrow(arrowFrame, style.arrowColor)
    context.addText(
      style.comboBoxTextRect(comboBox.bounds), comboBox.stringValue, style.text.color
    )

    if comboBox.usesInlinePopup:
      comboBox.popupList().drawPopupList(
        context, comboBox.popupRect(comboBox.bounds), PopupDrawLevel
      )

protocol DefaultComboBoxEvents of ResponderEventProtocol:
  method mouseDown(comboBox: ComboBox, event: MouseEvent) =
    if not comboBox.isEnabled or event.button != mbPrimary:
      return
    if comboBox.popupOpen() and
        comboBox.popupRect(comboBox.bounds()).contains(event.location):
      comboBox.popupList().beginPopupListTracking(
        comboBox.popupRect(comboBox.bounds()), event.location
      )
    else:
      comboBox.popupList().resetPopupListTracking()
      comboBox.xButtonPressed = true
      comboBox.togglePopup()
      comboBox.setNeedsDisplay(true)

  method mouseDragged(comboBox: ComboBox, event: MouseEvent) =
    if comboBox.popupOpen():
      comboBox.popupList().trackPopupListPoint(
        comboBox.popupRect(comboBox.bounds()), event.location
      )

  method mouseMoved(comboBox: ComboBox, event: MouseEvent) =
    if comboBox.popupOpen():
      comboBox.popupList().trackPopupListPoint(
        comboBox.popupRect(comboBox.bounds()), event.location
      )

  method mouseUp(comboBox: ComboBox, event: MouseEvent) =
    if not comboBox.isEnabled or event.button != mbPrimary:
      return
    comboBox.xButtonPressed = false
    if comboBox.popupOpen() and
        comboBox.popupRect(comboBox.bounds()).contains(event.location):
      comboBox.popupList().finishPopupListTracking(
        comboBox.popupRect(comboBox.bounds()), event.location, closeWhenDone = false
      )
    comboBox.setNeedsDisplay(true)

  method scrollWheel(comboBox: ComboBox, event: ScrollEvent) =
    if comboBox.popupOpen():
      comboBox.scrollPopupRows(popupListScrollRows(event))

  method keyDown(comboBox: ComboBox, event: KeyEvent) =
    if not comboBox.isEnabled:
      return
    case event.key
    of keyArrowDown:
      if not comboBox.popupOpen():
        comboBox.openPopup()
      else:
        comboBox.movePopupHighlight(1)
    of keyArrowUp:
      if not comboBox.popupOpen():
        comboBox.openPopup()
      else:
        comboBox.movePopupHighlight(-1)
    of keyPageDown:
      if comboBox.popupOpen():
        comboBox.pagePopupHighlight(1)
    of keyPageUp:
      if comboBox.popupOpen():
        comboBox.pagePopupHighlight(-1)
    of keyHome:
      if comboBox.popupOpen():
        comboBox.movePopupHighlightTo(0)
    of keyEnd:
      if comboBox.popupOpen():
        comboBox.movePopupHighlightTo(comboBox.numberOfItems() - 1)
    of keyEnter:
      if comboBox.popupOpen() and comboBox.highlightedIndex() >= 0:
        comboBox.activateItemAtIndex(comboBox.highlightedIndex())
        comboBox.closePopup()
      elif comboBox.indexOfSelectedItem() >= 0:
        discard comboBox.sendAction()
    of keyEscape:
      comboBox.closePopup()
    else:
      if comboBox.isEditable and event.text.len > 0:
        comboBox.setStringValue(event.text)

proc cellStringValue(cell: ComboBoxCell): string =
  if cell.isNil:
    return ""
  cell.xStringValue

proc setCellSelectedIndex(cell: ComboBoxCell, index: int) =
  if cell.isNil:
    return
  if index < 0:
    if cell.xSelectedIndex < 0 and cell.xStringValue.len == 0:
      return
    cell.xSelectedIndex = -1
    cell.xStringValue = ""
    cell.invalidateControlMetrics()
    return
  if index >= cell.xItems.len:
    return
  cell.xSelectedIndex = index
  cell.xStringValue = cell.xItems[index]
  cell.invalidateControlMetrics()

proc cellMaxVisibleItems(cell: ComboBoxCell): int =
  if cell.isNil:
    return 0
  cell.xMaxVisibleItems

proc setCellMaxVisibleItems(cell: ComboBoxCell, value: int) =
  if cell.isNil:
    return
  let count = max(value, 1)
  if cell.xMaxVisibleItems == count:
    return
  cell.xMaxVisibleItems = count
  cell.invalidateControlMetrics()

proc cellItemHeight(cell: ComboBoxCell): float32 =
  if cell.isNil:
    return 0.0
  cell.xItemHeight

proc setCellItemHeight(cell: ComboBoxCell, value: float32) =
  if cell.isNil:
    return
  let height = max(value, 1.0'f32)
  if cell.xItemHeight == height:
    return
  cell.xItemHeight = height
  cell.invalidateControlMetrics()

proc cellIsEditable(cell: ComboBoxCell): bool =
  not cell.isNil and cell.xEditable

proc setCellEditable(cell: ComboBoxCell, editable: bool) =
  if cell.isNil or cell.xEditable == editable:
    return
  cell.xEditable = editable
  cell.invalidateControlMetrics()

proc cellNumberOfItems(cell: ComboBoxCell): int =
  if cell.isNil:
    return 0
  cell.xItems.len

proc cellItemAtIndex(cell: ComboBoxCell, index: int): string =
  if cell.isNil or index < 0 or index >= cell.xItems.len:
    return ""
  cell.xItems[index]

proc cellAddItem(cell: ComboBoxCell, value: string) =
  if cell.isNil:
    return
  cell.xItems.add value
  cell.invalidateControlMetrics()

proc cellInsertItem(cell: ComboBoxCell, value: string, index: int) =
  if cell.isNil:
    return
  let boundedIndex = max(0, min(index, cell.xItems.len))
  cell.xItems.insert(value, boundedIndex)
  if cell.xSelectedIndex >= boundedIndex:
    inc cell.xSelectedIndex
  cell.invalidateControlMetrics()

proc cellRemoveItemAtIndex(cell: ComboBoxCell, index: int) =
  if cell.isNil or index < 0 or index >= cell.xItems.len:
    return
  cell.xItems.delete(index)
  if cell.xItems.len == 0:
    cell.xSelectedIndex = -1
    cell.xStringValue = ""
  elif cell.xSelectedIndex == index:
    cell.setCellSelectedIndex(min(index, cell.xItems.len - 1))
  elif index < cell.xSelectedIndex:
    dec cell.xSelectedIndex
  cell.invalidateControlMetrics()

proc cellRemoveAllItems(cell: ComboBoxCell) =
  if cell.isNil:
    return
  cell.xItems.setLen(0)
  cell.xStringValue = ""
  cell.xSelectedIndex = -1
  cell.invalidateControlMetrics()

proc comboBoxStyleContext(comboBox: ComboBox): StyleContext =
  initControlStyleContext(
    srComboBox,
    enabled = comboBox.isEnabled,
    highlighted = comboBox.xButtonPressed,
    hovered = comboBox.isHovered,
    active = comboBox.isActive,
    focused = comboBox.isFocused,
    focusVisible = comboBox.isFocusVisible,
    opened = comboBox.popupOpen,
    id = comboBox.styleId,
    classes = comboBox.styleClasses,
  )

proc comboBoxMeasuredTextSize(cell: ComboBoxCell): Size =
  let view = cell.controlView()
  if view of ComboBox:
    let comboBox = ComboBox(view)
    result = textNaturalSize(comboBox.stringValue())
    for idx in 0 ..< comboBox.numberOfItems():
      let itemSize = textNaturalSize(comboBox.itemAtIndex(idx))
      result.width = max(result.width, itemSize.width)
      result.height = max(result.height, itemSize.height)
    return

  result = textNaturalSize(cell.cellStringValue())
  for item in cell.xItems:
    let itemSize = textNaturalSize(item)
    result.width = max(result.width, itemSize.width)
    result.height = max(result.height, itemSize.height)

protocol DefaultComboBoxCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: ComboBoxCell): IntrinsicSize =
    let
      view = cell.controlView()
      appearance =
        if view.isNil:
          initAppearance()
        else:
          view.effectiveAppearance()
      context =
        if view of ComboBox:
          ComboBox(view).comboBoxStyleContext()
        else:
          initControlStyleContext(srComboBox)
      style = appearance.resolveComboBoxStyle(context)
    initIntrinsicSize(style.comboBoxControlSize(cell.comboBoxMeasuredTextSize()))

  method cellSizeForBounds(cell: ComboBoxCell, bounds: Rect): Size =
    cell.cellSize().resolveIntrinsicSize(bounds.size)

proc setComboBoxStringValue(comboBox: ComboBox, value: string) =
  if comboBox.isNil:
    return
  let
    cell = comboBox.comboBoxCell()
    index = comboBox.indexOfItem(value)
  if cell.xStringValue == value and cell.xSelectedIndex == index:
    return
  cell.xStringValue = value
  cell.xSelectedIndex = index
  cell.invalidateControlMetrics()

proc comboBoxStringValueMethod(self: DynamicAgent, invocation: var Invocation) =
  invocation.setResult(ComboBox(self).comboBoxCell().cellStringValue())

proc comboBoxSetStringValueMethod(self: DynamicAgent, invocation: var Invocation) =
  ComboBox(self).setComboBoxStringValue(invocation.argsAs(string))
  invocation.setResult(())

proc comboBoxIsEditableMethod(self: DynamicAgent, invocation: var Invocation) =
  invocation.setResult(ComboBox(self).comboBoxCell().cellIsEditable())

proc comboBoxSetEditableMethod(self: DynamicAgent, invocation: var Invocation) =
  ComboBox(self).comboBoxCell().setCellEditable(invocation.argsAs(bool))
  invocation.setResult(())

proc installComboBoxTextSelectors(comboBox: ComboBox) =
  discard comboBox.replaceMethod(stringValue(), comboBoxStringValueMethod)
  discard comboBox.replaceMethod(setStringValue(), comboBoxSetStringValueMethod)
  discard comboBox.replaceMethod(isEditable(), comboBoxIsEditableMethod)
  discard comboBox.replaceMethod(setEditable(), comboBoxSetEditableMethod)

proc initComboBoxCellFields*(cell: ComboBoxCell) =
  initActionCellFields(cell)
  cell.xSelectedIndex = -1
  cell.xEditable = true
  cell.xMaxVisibleItems = 5
  cell.xItemHeight = 22.0
  discard cell.withProtocol(DefaultComboBoxCellMeasurement)

proc newComboBoxCell*(): ComboBoxCell =
  result = ComboBoxCell()
  initComboBoxCellFields(result)

proc comboBoxCell*(comboBox: ComboBox): ComboBoxCell =
  if comboBox.isNil:
    return nil
  let controlCell = comboBox.cell()
  if controlCell of ComboBoxCell:
    return ComboBoxCell(controlCell)
  let replacement = newComboBoxCell()
  comboBox.setCell(replacement)
  replacement

proc text*(comboBox: ComboBox): string =
  comboBox.stringValue()

proc `text=`*(comboBox: ComboBox, value: string) =
  comboBox.setStringValue(value)

proc `stringValue=`*(comboBox: ComboBox, value: string) =
  comboBox.setStringValue(value)

proc editable*(comboBox: ComboBox): bool =
  (not comboBox.isNil) and comboBox.isEditable()

proc `editable=`*(comboBox: ComboBox, editable: bool) =
  if not comboBox.isNil:
    comboBox.setEditable(editable)

proc `selectedIndex=`*(comboBox: ComboBox, index: int) =
  comboBox.setSelectedIndex(index)

proc `popupOpen=`*(comboBox: ComboBox, open: bool) =
  comboBox.setPopupOpen(open)

proc `maxVisibleItems=`*(comboBox: ComboBox, value: int) =
  comboBox.setMaxVisibleItems(value)

proc `itemHeight=`*(comboBox: ComboBox, value: float32) =
  comboBox.setItemHeight(value)

proc `popupPresentation=`*(comboBox: ComboBox, popupPresentation: PopupPresentation) =
  comboBox.setPopupPresentation(popupPresentation)

proc dataSource*(comboBox: ComboBox): DynamicAgent =
  if comboBox.isNil:
    return nil
  comboBox.xDataSource

proc setDataSource*(comboBox: ComboBox, dataSource: DynamicAgent) =
  if comboBox.isNil or comboBox.xDataSource == dataSource:
    return
  comboBox.xDataSource = dataSource
  comboBox.reloadData()

proc `dataSource=`*(comboBox: ComboBox, dataSource: DynamicAgent) =
  comboBox.setDataSource(dataSource)

proc setDataSource*(comboBox: ComboBox, dataSource: Responder) =
  comboBox.setDataSource(DynamicAgent(dataSource))

proc `dataSource=`*(comboBox: ComboBox, dataSource: Responder) =
  comboBox.setDataSource(dataSource)

proc delegate*(comboBox: ComboBox): DynamicAgent =
  if comboBox.isNil:
    return nil
  comboBox.xDelegate

proc setDelegate*(comboBox: ComboBox, delegate: DynamicAgent) =
  if comboBox.isNil:
    return
  comboBox.xDelegate = delegate

proc `delegate=`*(comboBox: ComboBox, delegate: DynamicAgent) =
  comboBox.setDelegate(delegate)

proc setDelegate*(comboBox: ComboBox, delegate: Responder) =
  comboBox.setDelegate(DynamicAgent(delegate))

proc `delegate=`*(comboBox: ComboBox, delegate: Responder) =
  comboBox.setDelegate(delegate)

proc highlightedIndex*(comboBox: ComboBox): int =
  if comboBox.isNil:
    return -1
  comboBox.xPopupHighlightedIndex

proc setPopupNeedsDisplay(comboBox: ComboBox) =
  if comboBox.isNil:
    return
  comboBox.setNeedsDisplay(true)
  if not comboBox.xPopupWindow.isNil:
    let contentView = comboBox.xPopupWindow.contentView()
    if not contentView.isNil:
      contentView.setNeedsDisplay(true)

proc setHighlightedIndex*(comboBox: ComboBox, index: int) =
  if comboBox.isNil:
    return
  let boundedIndex = if index < 0 or index >= comboBox.numberOfItems(): -1 else: index
  let oldFirst = comboBox.popupFirstItemIndex()
  comboBox.scrollPopupItemToVisible(boundedIndex)
  let firstChanged = comboBox.popupFirstItemIndex() != oldFirst
  if comboBox.xPopupHighlightedIndex == boundedIndex:
    if firstChanged:
      comboBox.setPopupNeedsDisplay()
    return
  comboBox.xPopupHighlightedIndex = boundedIndex
  comboBox.notifyComboBoxSelectionIsChanging()
  comboBox.setPopupNeedsDisplay()

proc `highlightedIndex=`*(comboBox: ComboBox, index: int) =
  comboBox.setHighlightedIndex(index)

proc popupListData(comboBox: ComboBox): PopupListData =
  PopupListData(
    itemCount: proc(): int =
      comboBox.numberOfItems(),
    visibleCount: proc(): int =
      comboBox.visibleItemCount(),
    firstIndex: proc(): int =
      comboBox.popupFirstItemIndex(),
    selectedIndex: proc(): int =
      comboBox.indexOfSelectedItem(),
    highlightedIndex: proc(): int =
      comboBox.highlightedIndex(),
    rowHeight: proc(): float32 =
      comboBox.popupItemHeight(),
    itemText: proc(index: int): string =
      comboBox.itemAtIndex(index),
    enabled: proc(): bool =
      comboBox.isEnabled(),
    focused: proc(): bool =
      comboBox.isFocused(),
    opened: proc(): bool =
      comboBox.popupOpen(),
    styleId: proc(): string =
      comboBox.styleId(),
    styleClasses: proc(): seq[string] =
      comboBox.styleClasses(),
  )

proc popupListActions(comboBox: ComboBox): PopupListActions =
  PopupListActions(
    highlight: proc(index: int) =
      comboBox.setHoveredPopupIndex(index),
    activate: proc(index: int) =
      comboBox.activateItemAtIndex(index)
      comboBox.closePopup(),
    close: proc() =
      comboBox.closePopup(),
    scroll: proc(delta: int) =
      comboBox.scrollPopupRows(delta),
    keyDown: proc(event: KeyEvent) =
      comboBox.keyDown(event),
  )

proc popupList(comboBox: ComboBox): PopupListView =
  if comboBox.isNil:
    return nil
  if comboBox.xPopupList.isNil:
    comboBox.xPopupList =
      newPopupListView(comboBox.popupListData(), comboBox.popupListActions())
  comboBox.xPopupList

proc setHoveredPopupIndex(comboBox: ComboBox, index: int) =
  if comboBox.isNil or index < 0:
    return
  comboBox.setHighlightedIndex(index)

proc isButtonPressed*(comboBox: ComboBox): bool =
  not comboBox.isNil and comboBox.xButtonPressed

proc visibleItemCount*(comboBox: ComboBox): int =
  if comboBox.isNil:
    return 0
  visibleListItemCount(comboBox.numberOfItems(), comboBox.maxVisibleItems())

proc popupItemHeight*(comboBox: ComboBox): float32 =
  if comboBox.isNil:
    return 0.0
  max(comboBox.itemHeight(), 18.0'f32).normalizedRowHeight()

proc popupFirstItemIndex*(comboBox: ComboBox): int =
  if comboBox.isNil:
    return 0
  let
    total = comboBox.numberOfItems()
    visible = comboBox.visibleItemCount()
  comboBox.xPopupViewport.firstIndex.clampFirstIndex(total, visible)

proc scrollPopupItemToVisible(comboBox: ComboBox, itemIndex: int) =
  if comboBox.isNil:
    return
  comboBox.xPopupViewport.scrollToVisible(
    itemIndex, comboBox.numberOfItems(), comboBox.visibleItemCount()
  )

proc scrollPopupRows(comboBox: ComboBox, delta: int) =
  if comboBox.isNil or delta == 0:
    return
  let oldFirst = comboBox.popupFirstItemIndex()
  comboBox.xPopupViewport.scrollBy(
    delta, comboBox.numberOfItems(), comboBox.visibleItemCount()
  )
  if comboBox.popupFirstItemIndex() != oldFirst:
    comboBox.setPopupNeedsDisplay()

proc popupRect*(comboBox: ComboBox, bounds: Rect): Rect =
  if comboBox.isNil:
    return initRect(bounds.origin.x, bounds.maxY, 0.0, 0.0)
  listPopupRect(
    bounds,
    comboBox.numberOfItems(),
    comboBox.maxVisibleItems(),
    comboBox.popupItemHeight(),
  )

proc popupItemRect*(comboBox: ComboBox, bounds: Rect, itemIndex: int): Rect =
  let
    first = comboBox.popupFirstItemIndex()
    visible = comboBox.visibleItemCount()
    popup = comboBox.popupRect(bounds)
  listItemRect(popup, first, visible, itemIndex, comboBox.popupItemHeight())

proc popupItemIndexAtPoint*(comboBox: ComboBox, bounds: Rect, point: Point): int =
  if comboBox.isNil:
    return -1
  let
    popup = comboBox.popupRect(bounds)
    first = comboBox.popupFirstItemIndex()
  listItemIndexAtPoint(
    popup,
    point,
    first,
    comboBox.visibleItemCount(),
    comboBox.numberOfItems(),
    comboBox.popupItemHeight(),
  )

proc popupScrollIndicatorRect*(comboBox: ComboBox, bounds: Rect): Rect =
  if comboBox.isNil:
    return initRect(bounds.origin.x, bounds.maxY, 0.0, 0.0)
  listScrollIndicatorRect(
    comboBox.popupRect(bounds),
    comboBox.popupFirstItemIndex(),
    comboBox.visibleItemCount(),
    comboBox.numberOfItems(),
  )

proc popupWindowSize(comboBox: ComboBox): Size =
  let popup = comboBox.popupRect(comboBox.bounds)
  initSize(max(popup.size.width, 1.0'f32), max(popup.size.height, 1.0'f32))

proc ownerWindow(comboBox: ComboBox): Window =
  if comboBox.isNil:
    return nil
  let owner = comboBox.window()
  if owner of Window:
    result = Window(owner)

proc dismissPopupFromSession(comboBox: ComboBox, reason: TransientDismissReason) =
  if comboBox.isNil:
    return
  case reason
  of tdrProgrammatic, tdrOutsideClick, tdrEscape, tdrFocusChange, tdrOwnerClosed,
      tdrNativeDone:
    if comboBox.popupOpen():
      comboBox.closePopup()

proc beginPopupSession(comboBox: ComboBox) =
  let owner = comboBox.ownerWindow()
  if comboBox.isNil or owner.isNil:
    return
  let popupWindow = if comboBox.popupWindowActive(): comboBox.xPopupWindow else: nil
  owner.beginTransientSession(
    owner = Responder(comboBox),
    transientWindow = popupWindow,
    restoreResponder = Responder(comboBox),
    onDismiss = proc(reason: TransientDismissReason) =
      comboBox.dismissPopupFromSession(reason),
  )

proc endPopupSession(comboBox: ComboBox, reason = tdrProgrammatic): bool =
  let owner = comboBox.ownerWindow()
  if comboBox.isNil or owner.isNil:
    return false
  owner.endTransientSession(reason)

proc popupWindowActive(comboBox: ComboBox): bool =
  not comboBox.isNil and not comboBox.xPopupWindow.isNil and
    not comboBox.xPopupWindow.isClosed and comboBox.xPopupWindow.nativeReady

proc popupPresentationPreference(comboBox: ComboBox): PopupPresentation =
  if comboBox.isNil:
    return ppAutomatic
  if comboBox.xPopupPresentation == ppAutomatic:
    let owner = comboBox.ownerWindow()
    if owner.isNil:
      return platformDefaultPopupPresentation()
    return owner.effectivePopupPresentation()
  comboBox.xPopupPresentation

proc canUseWindowPopup(comboBox: ComboBox): bool =
  if comboBox.isNil or not nativePopupWindowsSupported():
    return false
  let owner = comboBox.ownerWindow()
  not owner.isNil and owner.nativeReady

proc wantsWindowPopup(comboBox: ComboBox): bool =
  case comboBox.popupPresentationPreference()
  of ppAutomatic:
    nativePopupWindowsSupported()
  of ppWindow:
    true
  of ppInline:
    false

proc shouldUseWindowPopup(comboBox: ComboBox): bool =
  comboBox.wantsWindowPopup() and comboBox.canUseWindowPopup()

proc usesInlinePopup(comboBox: ComboBox): bool =
  if comboBox.isNil or not comboBox.popupOpen():
    return false
  case comboBox.popupPresentationPreference()
  of ppInline:
    true
  of ppAutomatic:
    not comboBox.popupWindowActive()
  of ppWindow:
    false

proc openPopupWindow(comboBox: ComboBox) =
  if comboBox.isNil or not comboBox.popupOpen():
    return
  if comboBox.popupWindowActive():
    return
  if not comboBox.shouldUseWindowPopup():
    return
  if not comboBox.xPopupWindow.isNil:
    discard comboBox.endPopupSession()
    comboBox.closePopupWindow(restoreOwner = false)
  let owner = comboBox.ownerWindow()
  if owner.isNil or not owner.nativeReady:
    return

  let
    anchorFrame = comboBox.rectToWindow(comboBox.bounds)
    size = comboBox.popupWindowSize()
    popupWindow = owner.newPopupWindow(anchorFrame, size, "ComboBox Popup")
    popupView = comboBox.popupList()

  popupView.setFrame(initRect(0.0, 0.0, size.width, size.height))
  popupWindow.setContentView(popupView)
  popupWindow.setPopupDoneHandler(
    proc() =
      if owner.hasActiveTransientSession():
        discard owner.dismissTransientSession(tdrNativeDone)
      elif comboBox.xPopupWindow == popupWindow:
        comboBox.closePopup()
  )
  comboBox.xPopupWindow = popupWindow
  popupWindow.makeKeyAndOrderFront()
  popupWindow.ensureNativeWindow()
  if popupWindow.nativeReady:
    discard popupWindow.makeFirstResponder(popupView)
  else:
    comboBox.xPopupWindow = nil
    popupWindow.close()

proc closePopupWindow(comboBox: ComboBox, restoreOwner = true) =
  if comboBox.isNil:
    return
  let popupWindow = comboBox.xPopupWindow
  comboBox.xPopupWindow = nil
  if not popupWindow.isNil and not popupWindow.isClosed:
    popupWindow.close()
  if restoreOwner and not popupWindow.isNil:
    comboBox.reactivateOwnerWindow()

proc reactivateOwnerWindow(comboBox: ComboBox) =
  let owner = comboBox.ownerWindow()
  if owner.isNil or owner.isClosed:
    return
  if owner.isVisible:
    owner.makeKeyAndOrderFront()
  discard owner.makeFirstResponder(comboBox)

proc updatePopupPresentation(comboBox: ComboBox) =
  if comboBox.isNil:
    return
  if not comboBox.popupOpen():
    comboBox.closePopupWindow()
    return
  if comboBox.shouldUseWindowPopup():
    comboBox.openPopupWindow()
  elif not comboBox.xPopupWindow.isNil:
    discard comboBox.endPopupSession()
    comboBox.closePopupWindow(restoreOwner = false)
  if comboBox.popupOpen():
    comboBox.beginPopupSession()

proc movePopupHighlight*(comboBox: ComboBox, delta: int) =
  if comboBox.isNil or comboBox.numberOfItems() == 0:
    return
  let current =
    if comboBox.highlightedIndex() >= 0:
      comboBox.highlightedIndex()
    elif comboBox.indexOfSelectedItem() >= 0:
      comboBox.indexOfSelectedItem()
    else:
      0
  comboBox.setHighlightedIndex(
    max(0, min(current + delta, comboBox.numberOfItems() - 1))
  )

proc movePopupHighlightTo(comboBox: ComboBox, index: int) =
  if comboBox.isNil or comboBox.numberOfItems() == 0:
    return
  comboBox.setHighlightedIndex(max(0, min(index, comboBox.numberOfItems() - 1)))

proc pagePopupHighlight(comboBox: ComboBox, deltaPages: int) =
  if comboBox.isNil or comboBox.numberOfItems() == 0 or deltaPages == 0:
    return

  let
    total = comboBox.numberOfItems()
    visible = comboBox.visibleItemCount()
    current =
      if comboBox.highlightedIndex() >= 0:
        comboBox.highlightedIndex()
      elif comboBox.indexOfSelectedItem() >= 0:
        comboBox.indexOfSelectedItem()
      else:
        0
  if visible <= 0:
    comboBox.movePopupHighlightTo(current)
    return

  let target = max(0, min(current + deltaPages * visible, total - 1))
  comboBox.xPopupViewport.firstIndex = clampFirstIndex(target, total, visible)
  comboBox.movePopupHighlightTo(target)

proc notifyComboBoxSelectionIsChanging(comboBox: ComboBox) =
  if comboBox.isNil or comboBox.xDelegate.isNil:
    return
  discard comboBox.xDelegate.sendLocalIfHandled(
    comboBoxSelectionIsChanging(), ActionArgs(sender: DynamicAgent(comboBox))
  )

proc notifyComboBoxSelectionDidChange(comboBox: ComboBox) =
  if comboBox.isNil or comboBox.xDelegate.isNil:
    return
  discard comboBox.xDelegate.sendLocalIfHandled(
    comboBoxSelectionDidChange(), ActionArgs(sender: DynamicAgent(comboBox))
  )

proc addItems*(comboBox: ComboBox, values: openArray[string]) =
  if comboBox.isNil:
    return
  for value in values:
    comboBox.addItem(value)

proc initComboBoxFields*(
    comboBox: ComboBox, items: openArray[string] = [], frame: Rect = AutoRect
) =
  initControlFields(comboBox, frame, newComboBoxCell())
  comboBox.xPopupHighlightedIndex = -1
  comboBox.setAcceptsFirstResponder(true)
  discard comboBox.withProto()
  comboBox.installComboBoxTextSelectors()
  discard comboBox.withProtocol(DefaultComboBoxView)
  discard comboBox.withProtocol(DefaultComboBoxAction)
  discard comboBox.withProtocol(DefaultComboBoxDrawing)
  discard comboBox.withProtocol(DefaultComboBoxEvents)
  comboBox.addItems(items)
  comboBox.applyInitialFrame(frame)

proc newComboBox*(items: openArray[string] = [], frame: Rect = AutoRect): ComboBox =
  result = ComboBox()
  initComboBoxFields(result, items, frame)

let
  ComboBoxProtocol* = ComboBoxProtocolInternal
  ComboBoxDataSource* = ComboBoxDataSourceProtocolInternal
  ComboBoxDelegate* = ComboBoxDelegateProtocolInternal
  ComboBoxViewProtocol* = ComboBoxViewProtocolInternal
