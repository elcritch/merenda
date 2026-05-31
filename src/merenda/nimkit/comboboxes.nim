import std/options

from figdraw/fignodes import FigIdx
from figdraw/figbasics import ZLevel

import ./controls
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
    xTrackingPopup: bool
    xPopupWindow: Window
    xPopupPresentation: PopupPresentation

  ComboBoxCell* = ref object of ActionCell
    xItems: seq[string]
    xStringValue: string
    xSelectedIndex: int
    xEditable: bool
    xNumberOfVisibleItems: int
    xItemHeight: float32

  ComboBoxPopupView = ref object of View
    xComboBox: ComboBox

proc comboBoxCell*(comboBox: ComboBox): ComboBoxCell
proc dataSource*(comboBox: ComboBox): DynamicAgent
proc popupHighlightedIndex*(comboBox: ComboBox): int
proc setPopupHighlightedIndex*(comboBox: ComboBox, index: int)
proc visibleItemCount*(comboBox: ComboBox): int
proc popupItemHeight*(comboBox: ComboBox): float32
proc popupFirstItemIndex*(comboBox: ComboBox): int
proc popupRect*(comboBox: ComboBox, bounds: Rect): Rect
proc popupItemRect*(comboBox: ComboBox, bounds: Rect, itemIndex: int): Rect
proc popupItemIndexAtPoint*(comboBox: ComboBox, bounds: Rect, point: Point): int
proc popupItemRectInPopup(comboBox: ComboBox, itemIndex: int): Rect
proc popupItemIndexAtPopupPoint(comboBox: ComboBox, point: Point): int
proc movePopupHighlight*(comboBox: ComboBox, delta: int)
proc notifyComboBoxSelectionIsChanging(comboBox: ComboBox)
proc notifyComboBoxSelectionDidChange(comboBox: ComboBox)
proc popupPresentationPreference(comboBox: ComboBox): PopupPresentation
proc shouldUseWindowPopup(comboBox: ComboBox): bool
proc usesInlinePopup(comboBox: ComboBox): bool
proc openPopupWindow(comboBox: ComboBox)
proc closePopupWindow(comboBox: ComboBox)
proc reactivateOwnerWindow(comboBox: ComboBox)
proc updatePopupPresentation(comboBox: ComboBox)
proc drawPopupContents(
  comboBox: ComboBox,
  context: DrawContext,
  popupBounds: Rect,
  layer: ZLevel,
  parent: FigIdx,
  popupWindowLocal: bool,
)

proc cellStringValue(cell: ComboBoxCell): string
proc setCellSelectedIndex(cell: ComboBoxCell, index: int)
proc cellNumberOfVisibleItems(cell: ComboBoxCell): int
proc setCellNumberOfVisibleItems(cell: ComboBoxCell, value: int)
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
  property numberOfVisibleItems -> int
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
      comboBox.updatePopupPresentation()
    else:
      comboBox.closePopupWindow()
      comboBox.xPopupHighlightedIndex = -1
      comboBox.xButtonPressed = false
      comboBox.xTrackingPopup = false
    comboBox.setNeedsDisplay(true)

  method numberOfVisibleItems(comboBox: ComboBox): int =
    comboBox.comboBoxCell().cellNumberOfVisibleItems()

  method setNumberOfVisibleItems(comboBox: ComboBox, value: int) =
    comboBox.comboBoxCell().setCellNumberOfVisibleItems(value)

  method itemHeight(comboBox: ComboBox): float32 =
    comboBox.comboBoxCell().cellItemHeight()

  method setItemHeight(comboBox: ComboBox, value: float32) =
    comboBox.comboBoxCell().setCellItemHeight(value)

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
    cell.updateControlView()

  method deselectItem*(comboBox: ComboBox) =
    let cell = comboBox.comboBoxCell()
    if cell.xSelectedIndex < 0 and cell.xStringValue.len == 0:
      return
    cell.xSelectedIndex = -1
    cell.xStringValue = ""
    comboBox.setPopupHighlightedIndex(-1)
    cell.updateControlView()

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
          initColor(0.88, 0.90, 0.94, 1.0)
        else:
          initColor(0.94, 0.95, 0.97, 1.0)
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
      comboBox.drawPopupContents(
        context,
        comboBox.popupRect(comboBox.bounds),
        PopupDrawLevel,
        (-1).FigIdx,
        popupWindowLocal = false,
      )

protocol DefaultComboBoxPopupDrawing of ViewDrawingProtocol:
  method draw(popupView: ComboBoxPopupView, context: DrawContext) =
    let comboBox = popupView.xComboBox
    if comboBox.isNil or not comboBox.popupOpen:
      return
    comboBox.drawPopupContents(
      context, popupView.bounds, DefaultDrawLevel, (-1).FigIdx, popupWindowLocal = true
    )

protocol DefaultComboBoxPopupEvents of ResponderEventProtocol:
  method mouseDown(popupView: ComboBoxPopupView, event: MouseEvent) =
    let comboBox = popupView.xComboBox
    if comboBox.isNil or not comboBox.isEnabled or event.button != mbPrimary:
      return
    comboBox.xTrackingPopup = true
    comboBox.setPopupHighlightedIndex(
      comboBox.popupItemIndexAtPopupPoint(event.location)
    )

  method mouseDragged(popupView: ComboBoxPopupView, event: MouseEvent) =
    let comboBox = popupView.xComboBox
    if comboBox.isNil or not comboBox.popupOpen:
      return
    comboBox.setPopupHighlightedIndex(
      comboBox.popupItemIndexAtPopupPoint(event.location)
    )

  method mouseMoved(popupView: ComboBoxPopupView, event: MouseEvent) =
    let comboBox = popupView.xComboBox
    if comboBox.isNil or not comboBox.popupOpen:
      return
    comboBox.setPopupHighlightedIndex(
      comboBox.popupItemIndexAtPopupPoint(event.location)
    )

  method mouseUp(popupView: ComboBoxPopupView, event: MouseEvent) =
    let comboBox = popupView.xComboBox
    if comboBox.isNil or not comboBox.isEnabled or event.button != mbPrimary:
      return
    let itemIndex =
      if comboBox.popupOpen() and comboBox.xTrackingPopup:
        comboBox.popupItemIndexAtPopupPoint(event.location)
      else:
        -1
    comboBox.xTrackingPopup = false
    if itemIndex >= 0:
      comboBox.activateItemAtIndex(itemIndex)
    comboBox.closePopup()

  method keyDown(popupView: ComboBoxPopupView, event: KeyEvent) =
    let comboBox = popupView.xComboBox
    if comboBox.isNil:
      return
    comboBox.keyDown(event)

protocol DefaultComboBoxEvents of ResponderEventProtocol:
  method mouseDown(comboBox: ComboBox, event: MouseEvent) =
    if not comboBox.isEnabled or event.button != mbPrimary:
      return
    if comboBox.popupOpen() and
        comboBox.popupRect(comboBox.bounds()).contains(event.location):
      comboBox.xTrackingPopup = true
      comboBox.setPopupHighlightedIndex(
        comboBox.popupItemIndexAtPoint(comboBox.bounds(), event.location)
      )
    else:
      comboBox.xTrackingPopup = false
      comboBox.xButtonPressed = true
      comboBox.togglePopup()
      comboBox.setNeedsDisplay(true)

  method mouseDragged(comboBox: ComboBox, event: MouseEvent) =
    if comboBox.popupOpen():
      comboBox.setPopupHighlightedIndex(
        comboBox.popupItemIndexAtPoint(comboBox.bounds(), event.location)
      )

  method mouseMoved(comboBox: ComboBox, event: MouseEvent) =
    if comboBox.popupOpen():
      comboBox.setPopupHighlightedIndex(
        comboBox.popupItemIndexAtPoint(comboBox.bounds(), event.location)
      )

  method mouseUp(comboBox: ComboBox, event: MouseEvent) =
    if not comboBox.isEnabled or event.button != mbPrimary:
      return
    comboBox.xButtonPressed = false
    let itemIndex =
      if comboBox.popupOpen() and comboBox.xTrackingPopup:
        comboBox.popupItemIndexAtPoint(comboBox.bounds(), event.location)
      else:
        -1
    comboBox.xTrackingPopup = false
    if itemIndex >= 0:
      comboBox.activateItemAtIndex(itemIndex)
      comboBox.closePopup()
    comboBox.setNeedsDisplay(true)

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
    of keyEnter:
      if comboBox.popupOpen() and comboBox.popupHighlightedIndex() >= 0:
        comboBox.activateItemAtIndex(comboBox.popupHighlightedIndex())
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
    cell.updateControlView()
    return
  if index >= cell.xItems.len:
    return
  cell.xSelectedIndex = index
  cell.xStringValue = cell.xItems[index]
  cell.updateControlView()

proc cellNumberOfVisibleItems(cell: ComboBoxCell): int =
  if cell.isNil:
    return 0
  cell.xNumberOfVisibleItems

proc setCellNumberOfVisibleItems(cell: ComboBoxCell, value: int) =
  if cell.isNil:
    return
  let count = max(value, 1)
  if cell.xNumberOfVisibleItems == count:
    return
  cell.xNumberOfVisibleItems = count
  cell.updateControlView()

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
  cell.updateControlView()

proc cellIsEditable(cell: ComboBoxCell): bool =
  not cell.isNil and cell.xEditable

proc setCellEditable(cell: ComboBoxCell, editable: bool) =
  if cell.isNil or cell.xEditable == editable:
    return
  cell.xEditable = editable
  cell.updateControlView()

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
  cell.updateControlView()

proc cellInsertItem(cell: ComboBoxCell, value: string, index: int) =
  if cell.isNil:
    return
  let boundedIndex = max(0, min(index, cell.xItems.len))
  cell.xItems.insert(value, boundedIndex)
  if cell.xSelectedIndex >= boundedIndex:
    inc cell.xSelectedIndex
  cell.updateControlView()

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
  cell.updateControlView()

proc cellRemoveAllItems(cell: ComboBoxCell) =
  if cell.isNil:
    return
  cell.xItems.setLen(0)
  cell.xStringValue = ""
  cell.xSelectedIndex = -1
  cell.updateControlView()

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
  cell.updateControlView()

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
  cell.xNumberOfVisibleItems = 5
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

proc dataSource*(comboBox: ComboBox): DynamicAgent =
  if comboBox.isNil:
    return nil
  comboBox.xDataSource

proc setDataSource*(comboBox: ComboBox, dataSource: DynamicAgent) =
  if comboBox.isNil or comboBox.xDataSource == dataSource:
    return
  comboBox.xDataSource = dataSource
  comboBox.reloadData()

proc setDataSource*(comboBox: ComboBox, dataSource: Responder) =
  comboBox.setDataSource(DynamicAgent(dataSource))

proc delegate*(comboBox: ComboBox): DynamicAgent =
  if comboBox.isNil:
    return nil
  comboBox.xDelegate

proc setDelegate*(comboBox: ComboBox, delegate: DynamicAgent) =
  if comboBox.isNil:
    return
  comboBox.xDelegate = delegate

proc setDelegate*(comboBox: ComboBox, delegate: Responder) =
  comboBox.setDelegate(DynamicAgent(delegate))

proc popupHighlightedIndex*(comboBox: ComboBox): int =
  if comboBox.isNil:
    return -1
  comboBox.xPopupHighlightedIndex

proc setPopupHighlightedIndex*(comboBox: ComboBox, index: int) =
  if comboBox.isNil:
    return
  let boundedIndex = if index < 0 or index >= comboBox.numberOfItems(): -1 else: index
  if comboBox.xPopupHighlightedIndex == boundedIndex:
    return
  comboBox.xPopupHighlightedIndex = boundedIndex
  comboBox.notifyComboBoxSelectionIsChanging()
  comboBox.setNeedsDisplay(true)

proc isButtonPressed*(comboBox: ComboBox): bool =
  not comboBox.isNil and comboBox.xButtonPressed

proc visibleItemCount*(comboBox: ComboBox): int =
  if comboBox.isNil:
    return 0
  let count = comboBox.numberOfItems()
  if count <= 0:
    return 0
  min(count, max(comboBox.numberOfVisibleItems(), 1))

proc popupItemHeight*(comboBox: ComboBox): float32 =
  if comboBox.isNil:
    return 0.0
  max(comboBox.itemHeight(), 18.0'f32)

proc popupFirstItemIndex*(comboBox: ComboBox): int =
  if comboBox.isNil:
    return 0
  let
    total = comboBox.numberOfItems()
    visible = comboBox.visibleItemCount()
  if total <= visible or visible <= 0:
    return 0
  let selected = comboBox.indexOfSelectedItem()
  if selected < 0:
    return 0
  max(0, min(selected - visible + 1, total - visible))

proc popupRect*(comboBox: ComboBox, bounds: Rect): Rect =
  let visible = comboBox.visibleItemCount()
  if visible <= 0:
    return initRect(bounds.origin.x, bounds.maxY, 0.0, 0.0)
  initRect(
    bounds.origin.x,
    bounds.maxY,
    bounds.size.width,
    comboBox.popupItemHeight() * visible.float32 + 2.0'f32,
  )

proc popupItemRect*(comboBox: ComboBox, bounds: Rect, itemIndex: int): Rect =
  let
    first = comboBox.popupFirstItemIndex()
    visibleIndex = itemIndex - first
    visible = comboBox.visibleItemCount()
  if visibleIndex < 0 or visibleIndex >= visible:
    return initRect(bounds.origin.x, bounds.maxY, 0.0, 0.0)
  let
    popup = comboBox.popupRect(bounds)
    height = comboBox.popupItemHeight()
  initRect(
    popup.origin.x + 1.0'f32,
    popup.origin.y + 1.0'f32 + visibleIndex.float32 * height,
    max(popup.size.width - 2.0'f32, 0.0'f32),
    height,
  )

proc popupItemIndexAtPoint*(comboBox: ComboBox, bounds: Rect, point: Point): int =
  let popup = comboBox.popupRect(bounds)
  if popup.isEmpty or not popup.contains(point):
    return -1
  let
    height = comboBox.popupItemHeight()
    visibleIndex = int((point.y - popup.origin.y - 1.0'f32) / height)
  if height <= 0.0'f32 or visibleIndex < 0 or visibleIndex >= comboBox.visibleItemCount():
    return -1
  let index = comboBox.popupFirstItemIndex() + visibleIndex
  if index < 0 or index >= comboBox.numberOfItems():
    return -1
  index

proc popupItemRectInPopup(comboBox: ComboBox, itemIndex: int): Rect =
  let
    first = comboBox.popupFirstItemIndex()
    visibleIndex = itemIndex - first
    visible = comboBox.visibleItemCount()
  if visibleIndex < 0 or visibleIndex >= visible:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let height = comboBox.popupItemHeight()
  initRect(
    1.0'f32,
    1.0'f32 + visibleIndex.float32 * height,
    max(comboBox.bounds.size.width - 2.0'f32, 0.0'f32),
    height,
  )

proc popupItemIndexAtPopupPoint(comboBox: ComboBox, point: Point): int =
  let popupBounds = initRect(
    0.0'f32,
    0.0'f32,
    comboBox.bounds.size.width,
    comboBox.popupItemHeight() * comboBox.visibleItemCount().float32 + 2.0'f32,
  )
  if popupBounds.isEmpty or not popupBounds.contains(point):
    return -1
  let
    height = comboBox.popupItemHeight()
    visibleIndex = int((point.y - 1.0'f32) / height)
  if height <= 0.0'f32 or visibleIndex < 0 or visibleIndex >= comboBox.visibleItemCount():
    return -1
  let index = comboBox.popupFirstItemIndex() + visibleIndex
  if index < 0 or index >= comboBox.numberOfItems():
    return -1
  index

proc popupWindowSize(comboBox: ComboBox): Size =
  let popup = comboBox.popupRect(comboBox.bounds)
  initSize(max(popup.size.width, 1.0'f32), max(popup.size.height, 1.0'f32))

proc ownerWindow(comboBox: ComboBox): Window =
  if comboBox.isNil:
    return nil
  let owner = comboBox.window()
  if owner of Window:
    result = Window(owner)

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

proc newComboBoxPopupView(comboBox: ComboBox, size: Size): ComboBoxPopupView =
  result = ComboBoxPopupView(xComboBox: comboBox)
  initViewFields(result, initRect(0.0, 0.0, size.width, size.height))
  result.setBackgroundColor(initColor(1.0, 1.0, 1.0, 1.0))
  result.setAcceptsFirstResponder(true)
  discard result.withProtocol(DefaultComboBoxPopupDrawing)
  discard result.withProtocol(DefaultComboBoxPopupEvents)

proc openPopupWindow(comboBox: ComboBox) =
  if comboBox.isNil or not comboBox.popupOpen():
    return
  if comboBox.popupWindowActive():
    return
  if not comboBox.shouldUseWindowPopup():
    return
  if not comboBox.xPopupWindow.isNil:
    comboBox.closePopupWindow()
  let owner = comboBox.ownerWindow()
  if owner.isNil or not owner.nativeReady:
    return

  let
    anchorFrame = comboBox.rectToWindow(comboBox.bounds)
    size = comboBox.popupWindowSize()
    popupWindow = owner.newPopupWindow(anchorFrame, size, "ComboBox Popup")
    popupView = newComboBoxPopupView(comboBox, size)

  popupWindow.setContentView(popupView)
  popupWindow.setPopupDoneHandler(
    proc() =
      if comboBox.xPopupWindow == popupWindow:
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

proc closePopupWindow(comboBox: ComboBox) =
  if comboBox.isNil:
    return
  let popupWindow = comboBox.xPopupWindow
  comboBox.xPopupWindow = nil
  if not popupWindow.isNil and not popupWindow.isClosed:
    popupWindow.close()
  if not popupWindow.isNil:
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
    comboBox.closePopupWindow()

proc drawPopupContents(
    comboBox: ComboBox,
    context: DrawContext,
    popupBounds: Rect,
    layer: ZLevel,
    parent: FigIdx,
    popupWindowLocal: bool,
) =
  if comboBox.isNil or popupBounds.isEmpty:
    return
  let
    style = context.appearance.resolveComboBoxStyle(
      initControlStyleContext(
        srComboBox,
        enabled = comboBox.isEnabled,
        focused = comboBox.isFocused,
        opened = comboBox.popupOpen,
        id = comboBox.styleId,
        classes = comboBox.styleClasses,
      )
    )
    popupRoot = context.addWindowRectangle(
      layer,
      parent,
      context.localRectToWindow(popupBounds),
      initColor(1.0, 1.0, 1.0, 1.0),
      style.box.borderColor,
      style.box.borderWidth,
      2.0'f32,
    )
    first = comboBox.popupFirstItemIndex()
  for visibleIndex in 0 ..< comboBox.visibleItemCount():
    let
      itemIndex = first + visibleIndex
      selected = itemIndex == comboBox.indexOfSelectedItem()
      hovered = itemIndex == comboBox.popupHighlightedIndex()
      itemStyle = context.appearance.resolveTextFieldStyle(
        initControlStyleContext(
          srComboBoxItem,
          enabled = comboBox.isEnabled,
          hovered = hovered,
          selected = selected,
          id = comboBox.styleId,
          classes = comboBox.styleClasses,
        )
      )
      itemRect =
        if popupWindowLocal:
          comboBox.popupItemRectInPopup(itemIndex)
        else:
          comboBox.popupItemRect(comboBox.bounds, itemIndex)
    discard context.addWindowRectangle(
      layer,
      popupRoot,
      context.localRectToWindow(itemRect),
      itemStyle.box.fill,
      itemStyle.box.borderColor,
      itemStyle.box.borderWidth,
      itemStyle.box.cornerRadius,
    )
    context.addText(
      layer,
      popupRoot,
      itemStyle.textFieldTextRect(itemRect),
      comboBox.itemAtIndex(itemIndex),
      itemStyle.text.color,
    )

proc movePopupHighlight*(comboBox: ComboBox, delta: int) =
  if comboBox.isNil or comboBox.numberOfItems() == 0:
    return
  let current =
    if comboBox.popupHighlightedIndex() >= 0:
      comboBox.popupHighlightedIndex()
    elif comboBox.indexOfSelectedItem() >= 0:
      comboBox.indexOfSelectedItem()
    else:
      0
  comboBox.setPopupHighlightedIndex(
    max(0, min(current + delta, comboBox.numberOfItems() - 1))
  )

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
  initControlFields(comboBox, frame)
  comboBox.setCell(newComboBoxCell())
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
