## Default table mouse/keyboard input and responder-event dispatch.

import ../app/windows
import ../controls/controls
import ../foundation/events
import ../foundation/selectors
import ../view/views
import ./tablecore
import ./tablepresentation
import ./tableselection
import ./tablecells
import ./tabledragging

proc defaultTableViewMouseDown*(tableView: TableView, event: MouseEvent): bool =
  if not tableView.isEnabled() or event.button != mbPrimary:
    return false
  let owner = tableView.window()
  if owner of Window:
    discard Window(owner).makeFirstResponder(tableView)
  tableView.xTrackingItem = true
  let index = tableView.updateHighlightedCellAtPoint(event.location)
  tableView.xPressedIndex = tableView.highlightedIndex()
  tableView.xDragging.rowStart = TableRowDragStart(row: index, point: event.location)
  tableView.invalidateTableRows()
  true

proc defaultTableViewMouseDragged*(tableView: TableView, event: MouseEvent): bool =
  if tableView.tryBeginRowReorderDrag(event):
    return true
  if tableView.isEnabled() and tableView.xTrackingItem:
    discard tableView.updateHighlightedCellAtPoint(event.location)
    tableView.xPressedIndex = tableView.highlightedIndex()
    tableView.invalidateTableRows()
    return true
  false

proc defaultTableViewMouseUp*(tableView: TableView, event: MouseEvent): bool =
  if not tableView.isEnabled() or event.button != mbPrimary:
    return false
  let index =
    if tableView.xTrackingItem:
      tableView.rowItemIndexAtPoint(event.location)
    else:
      -1
  tableView.xTrackingItem = false
  tableView.xPressedIndex = -1
  tableView.clearRowDragState()
  if index >= 0:
    tableView.activateCellAtIndex(
      index, tableView.tableColumnAtPoint(event.location), event.modifiers
    )
  tableView.needsDisplay = true
  true

proc defaultTableViewKeyDown*(tableView: TableView, event: KeyEvent): bool =
  if not tableView.isEnabled():
    return false
  result = true
  let extendSelection = kmShift in event.modifiers
  case event.key
  of keyArrowDown:
    tableView.moveSelection(1, extendSelection)
  of keyArrowUp:
    tableView.moveSelection(-1, extendSelection)
  of keyArrowRight:
    result = tableView.moveFocusedCell(1)
  of keyArrowLeft:
    result = tableView.moveFocusedCell(-1)
  of keyPageDown:
    tableView.pageSelection(1, extendSelection)
  of keyPageUp:
    tableView.pageSelection(-1, extendSelection)
  of keyHome:
    tableView.moveSelectionTo(tableView.firstSelectableIndex(), extendSelection)
  of keyEnd:
    tableView.moveSelectionTo(tableView.lastSelectableIndex(), extendSelection, -1)
  of keyEnter, keySpace:
    let activeIndex = tableView.selectionLeadIndex()
    if activeIndex >= 0:
      tableView.sendTableActivation(activeIndex)
  else:
    result =
      tableView.beginEditingFocusedCellWithText(event) or
      tableView.handleTypeSelect(event) or event.text.len > 0

protocol DefaultTableViewEvents of ResponderEventProtocol:
  method updateTrackingAreas(tableView: TableView, event: MouseEvent): bool =
    discard event
    tableView.syncHeaderTrackingAreas()
    true

  method cursorUpdate(tableView: TableView, event: MouseEvent): bool =
    tableView.tableHeaderHitTest(event.location).part in
      {thpResizeHandle, thpRowHeaderResizeHandle, thpRowHeaderRowResizeHandle}

  method mouseDown(tableView: TableView, event: MouseEvent): bool =
    if tableView.headerMouseDown(event):
      return true
    tableView.defaultTableViewMouseDown(event)

  method mouseDragged(tableView: TableView, event: MouseEvent): bool =
    if tableView.xHeaderTracking.isActive():
      return tableView.headerMouseDragged(event)
    if tableView.updateActiveTableDrag(event):
      return true
    tableView.defaultTableViewMouseDragged(event)

  method mouseUp(tableView: TableView, event: MouseEvent): bool =
    if tableView.xHeaderTracking.isActive():
      return tableView.headerMouseUp(event)
    if tableView.performActiveTableDrag(event):
      return true
    let handled = tableView.defaultTableViewMouseUp(event)
    if event.clickCount >= 2:
      let
        row = tableView.rowItemIndexAtPoint(event.location)
        column = tableView.tableColumnAtPoint(event.location)
      if tableView.shouldBeginEditingCell(row, column):
        return tableView.beginEditingCell(row, column)
    handled

  method mouseMoved(tableView: TableView, event: MouseEvent): bool =
    if tableView.headerMouseMoved(event):
      tableView.clearPointerRowHighlight()
      tableView.setHighlightedColumn(nil)
      return true
    if tableView.isEnabled():
      discard tableView.updateHighlightedCellAtPoint(event.location)
      return true
    false

  method keyDown(tableView: TableView, event: KeyEvent): bool =
    tableView.clearPointerHighlights()
    if event.key == keyEnter and tableView.beginEditingFocusedCell():
      return true
    tableView.defaultTableViewKeyDown(event)

proc installTableInputProtocol*(tableView: TableView) =
  discard tableView.withProtocol(DefaultTableViewEvents)
