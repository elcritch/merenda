## Table row/column drag sessions, drop validation, and reorder orchestration.

import std/options
import ../app/dragging
import ../app/pasteboards
import ../controls/controls
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../view/views
import ./tablecore
import ./tablepresentation
import ./tableselection
import ./tablemodels

proc autoscrollDraggingInfo(tableView: TableView, info: DraggingInfo): bool =
  let bounds = tableView.bounds()
  if bounds.isEmpty:
    return false
  let edge = max(tableView.rowHeight(), 12.0'f32)
  if info.location.y < bounds.minY + edge:
    tableView.scrollRows(-1)
    return true
  if info.location.y > bounds.maxY - edge:
    tableView.scrollRows(1)
    return true

proc updateTableDropTarget(tableView: TableView, target: DraggingDropTarget) =
  if tableView.xDragging.dropTarget == target:
    return
  tableView.xDragging.dropTarget = target
  tableView.invalidateTableRows()

proc `allowsRowReordering=`*(tableView: TableView, value: bool) =
  if (tvoRowReordering in tableView.xOptions) == value:
    return
  tableView.xOptions[tvoRowReordering] = value
  if not value:
    tableView.xDragging.rowStart.row = -1
    tableView.updateTableDropTarget(initDraggingDropTarget())

proc defaultReorderRows(
    tableView: TableView, rows: openArray[int], target: DraggingDropTarget
): bool =
  let normalizedRows = tableView.normalizedReorderRows(rows)
  if not tableView.canReorderRows(normalizedRows, target):
    return false

  let delegate = tableView.delegate()
  if not delegate.isNil:
    let performed = delegate.trySendLocal(
      performRowReorder(), (tableView: tableView, rows: normalizedRows, target: target)
    )
    if performed.isSome:
      return performed.get()

  let source = tableView.dataSource()
  if source of TableModel:
    return tableView.reorderTableModelRows(TableModel(source), normalizedRows, target)
  false

proc reorderRows*(
    tableView: TableView, rows: openArray[int], target: DraggingDropTarget
): bool =
  let reordered =
    tableView.trySendLocal(reorderTableRows(), (rows: @rows, target: target))
  if reordered.isSome:
    reordered.get()
  else:
    false

func hasExceededDragThreshold(startPoint, location: Point, threshold: float32): bool =
  max(abs(location.x - startPoint.x), abs(location.y - startPoint.y)) >= threshold

proc clearRowDragState*(tableView: TableView) =
  tableView.xDragging.rowStart = TableRowDragStart()

proc rowReorderDragRows(tableView: TableView): seq[int] =
  if tableView.xDragging.rowStart.row < 0:
    return
  if tableView.selectionMode() != tsmNone and
      tableView.selectionContains(tableView.xDragging.rowStart.row):
    tableView.selectedIndexes()
  else:
    @[tableView.xDragging.rowStart.row]

proc shouldBeginRowReorderDrag(tableView: TableView, event: MouseEvent): bool =
  if not tableView.isEnabled() or event.button != mbPrimary:
    return false
  if not tableView.allowsRowReordering() or not tableView.xTrackingItem:
    return false
  if tableView.xDragging.rowStart.row < 0 or
      not tableView.rowEnabled(tableView.xDragging.rowStart.row):
    return false
  if tableView.selectionMode() != tsmNone and
      not tableView.rowSelectable(tableView.xDragging.rowStart.row):
    return false
  tableView.xDragging.rowStart.point.hasExceededDragThreshold(
    event.location, tableView.tableStyle().headerDragThreshold
  )

proc tryBeginRowReorderDrag*(tableView: TableView, event: MouseEvent): bool =
  if not tableView.shouldBeginRowReorderDrag(event):
    return false
  if tableView.selectionMode() != tsmNone and
      not tableView.selectionContains(tableView.xDragging.rowStart.row):
    tableView.selectItemAtIndex(tableView.xDragging.rowStart.row)

  let rows = tableView.normalizedReorderRows(tableView.rowReorderDragRows())
  if rows.len == 0:
    return false

  let session = tableView.beginDraggingRows(rows, {dgoMove}, DragPasteboardName)
  if session.isNil:
    return false

  let target = tableView.dropTargetForDraggingLocation(event.location)
  tableView.xTrackingItem = false
  tableView.highlightedIndex = -1
  tableView.setHighlightedColumn(nil)
  tableView.xPressedIndex = -1
  tableView.updateTableDropTarget(target)
  discard
    updateDraggingSession(session, event.location, DynamicAgent(tableView), target)
  discard
    autoscrollDraggingSession(session, event.location, DynamicAgent(tableView), target)
  true

proc updateActiveTableDrag*(tableView: TableView, event: MouseEvent): bool =
  let session = tableView.draggingSession()
  if session.isNil or session.state() != dssActive:
    return false
  let target = tableView.dropTargetForDraggingLocation(event.location)
  tableView.updateTableDropTarget(target)
  discard
    updateDraggingSession(session, event.location, DynamicAgent(tableView), target)
  discard
    autoscrollDraggingSession(session, event.location, DynamicAgent(tableView), target)
  true

proc performActiveTableDrag*(tableView: TableView, event: MouseEvent): bool =
  let session = tableView.draggingSession()
  if session.isNil or session.state() != dssActive:
    return false

  let target = tableView.dropTargetForDraggingLocation(event.location)
  tableView.updateTableDropTarget(target)
  discard
    updateDraggingSession(session, event.location, DynamicAgent(tableView), target)
  let performed =
    performDraggingOperation(session, DynamicAgent(tableView), event.location, target)
  if performed:
    session.endDraggingSession(session.selectedOperations())
  else:
    session.cancelDraggingSession()
  tableView.xTrackingItem = false
  tableView.xPressedIndex = -1
  tableView.clearRowDragState()
  true

# Nim 2.2 cannot resolve this selector beside its openArray convenience overload
# when registering the protocol implementation.
let tableColumnDragSelector = beginDraggingColumns()

protocol DefaultTableViewDraggingBehavior of TableViewDraggingProtocol:
  method beginDraggingRows(
      tableView: TableView,
      rows: seq[int],
      operations: DragOperations,
      pasteboardName: string,
  ): DraggingSession =
    var validRows: seq[int]
    for row in rows:
      if row in 0 ..< tableView.rowCount():
        validRows.add row
    if validRows.len == 0:
      return nil
    let payload = joinRowIndexes(validRows)
    var items = @[
      initDraggingItem(TablePasteboardTypeRows, initPasteboardStringItem(payload)),
      initDraggingItem(PasteboardTypeString, initPasteboardStringItem(payload)),
    ]
    let identifiers = tableView.rowIdentifiersForRows(validRows)
    if identifiers.len > 0:
      items.add initDraggingItem(
        TablePasteboardTypeRowIdentifiers,
        initPasteboardStringItem(joinIdentifiers(identifiers)),
      )
    result =
      beginDraggingSession(DynamicAgent(tableView), items, operations, pasteboardName)
    tableView.xDragging.session = result

  method tableColumnDragSelector(
      tableView: TableView,
      columns: seq[TableColumn],
      operations: DragOperations,
      pasteboardName: string,
  ): DraggingSession =
    var identifiers: seq[string]
    for column in columns:
      if not column.isNil and column.tableView() == tableView:
        identifiers.add column.identifier()
    if identifiers.len == 0:
      return nil
    let payload = joinIdentifiers(identifiers)
    result = beginDraggingSession(
      DynamicAgent(tableView),
      [
        initDraggingItem(TablePasteboardTypeColumns, initPasteboardStringItem(payload)),
        initDraggingItem(PasteboardTypeString, initPasteboardStringItem(payload)),
      ],
      operations,
      pasteboardName,
    )
    tableView.xDragging.session = result

  method reorderTableRows(
      tableView: TableView, rows: seq[int], target: DraggingDropTarget
  ): bool =
    tableView.defaultReorderRows(rows, target)

  method validateDragging(tableView: TableView, info: DraggingInfo): DragOperations =
    let
      isRowReorder = tableView.isTableRowReorderDrag(info)
      rowReorderOperation =
        if tableView.canAcceptTableRowReorder(info):
          {dgoMove}
        else:
          NoDragOperations
      proposedOperation =
        if isRowReorder: rowReorderOperation else: info.selectedOperations
    let delegate = tableView.delegate()
    if not delegate.isNil:
      let validated = delegate.trySendLocal(
        validateDropOperation(),
        (
          tableView: tableView,
          info: info,
          proposedOperation: proposedOperation,
          target: info.dropTarget,
          position: info.dropTarget.position,
        ),
      )
      if validated.isSome:
        if isRowReorder:
          return validated.get() * rowReorderOperation
        return validated.get()
      if isRowReorder:
        return rowReorderOperation
      let operation = delegate.trySendLocal(
        validateDragOperation(), (tableView: tableView, info: info)
      )
      if operation.isSome:
        if isRowReorder:
          return operation.get() * rowReorderOperation
        return operation.get()
    if isRowReorder:
      return rowReorderOperation
    info.selectedOperations

  method acceptDragging(tableView: TableView, info: DraggingInfo): bool =
    let operation = tableView.validateDragging(info)
    if operation == NoDragOperations:
      return false
    if tableView.isTableRowReorderDrag(info):
      return
        dgoMove in operation and
        tableView.reorderRows(info.tableDraggingRows(), info.dropTarget)
    let delegate = tableView.delegate()
    if not delegate.isNil:
      let acceptedDrop = delegate.trySendLocal(
        acceptDropOperation(),
        (
          tableView: tableView,
          info: info,
          operation: operation,
          target: info.dropTarget,
          position: info.dropTarget.position,
        ),
      )
      if acceptedDrop.isSome:
        return acceptedDrop.get()
      let accepted =
        delegate.trySendLocal(acceptDragOperation(), (tableView: tableView, info: info))
      if accepted.isSome:
        return accepted.get()
    true

protocol DefaultTableViewDraggingSource of DraggingSourceProtocol:
  method draggingSourceOperationMask(
      tableView: TableView, info: DraggingInfo
  ): DragOperations =
    info.allowedOperations

  method draggingSessionEnded(tableView: TableView, info: DraggingInfo) =
    if tableView.xDragging.session == info.session:
      tableView.xDragging.session = nil
      tableView.updateTableDropTarget(initDraggingDropTarget())

protocol DefaultTableViewDraggingDestination of DraggingDestinationProtocol:
  method draggingEntered(tableView: TableView, info: DraggingInfo): DragOperations =
    tableView.updateTableDropTarget(info.dropTarget)
    tableView.validateDragging(info)

  method draggingUpdated(tableView: TableView, info: DraggingInfo): DragOperations =
    tableView.updateTableDropTarget(info.dropTarget)
    tableView.validateDragging(info)

  method draggingExited(tableView: TableView, info: DraggingInfo) =
    tableView.updateTableDropTarget(initDraggingDropTarget())

  method prepareForDragOperation(tableView: TableView, info: DraggingInfo): bool =
    tableView.validateDragging(info) != NoDragOperations

  method performDragOperation(tableView: TableView, info: DraggingInfo): bool =
    tableView.acceptDragging(info)

  method concludeDragOperation(tableView: TableView, info: DraggingInfo) =
    tableView.updateTableDropTarget(initDraggingDropTarget())

  method autoscrollDraggingSession(tableView: TableView, info: DraggingInfo): bool =
    tableView.autoscrollDraggingInfo(info)

proc installTableDraggingProtocols*(tableView: TableView) =
  discard tableView.withProtocol(DefaultTableViewDraggingBehavior)
  discard tableView.withProtocol(DefaultTableViewDraggingSource)
  discard tableView.withProtocol(DefaultTableViewDraggingDestination)
