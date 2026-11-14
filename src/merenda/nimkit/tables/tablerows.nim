## Table reload transactions and batched row updates.

import std/tables
import sigils/core
import ../controls/controls
import ../foundation/selectors
import ../foundation/types
import ../view/views
import ./tablecore
import ./tableselection
import ./tablecells
import ./tablecoordination

proc presentedRowIdentifier(tableView: TableView, row: int): string =
  if row in 0 ..< tableView.xPresentedRowIdentifiers.len:
    tableView.xPresentedRowIdentifiers[row]
  else:
    tableView.tableRowIdentifier(row)

proc presentedRowIdentifiers(tableView: TableView, rows: openArray[int]): seq[string] =
  for row in rows:
    let identifier = tableView.presentedRowIdentifier(row)
    if identifier.len > 0:
      result.add identifier

proc capturePresentedRowIdentifiers(tableView: TableView) =
  tableView.xPresentedRowIdentifiers.setLen(0)
  for row in 0 ..< tableView.len():
    tableView.xPresentedRowIdentifiers.add tableView.tableRowIdentifier(row)

proc reconcileTableCellSlots(tableView: TableView) =
  var rows = initTable[string, int]()
  for row in 0 ..< tableView.len():
    let identifier = tableView.tableRowIdentifier(row)
    if identifier.len > 0:
      if identifier in rows:
        rows[identifier] = -1
      else:
        rows[identifier] = row
  var position = 0
  while position < tableView.xCellSlots.len:
    let slot = tableView.xCellSlots[position]
    let row = rows.getOrDefault(slot.identifier, -1)
    var keep = false
    if row >= 0:
      let delegate = tableView.delegate()
      if not delegate.isNil:
        keep = delegate.sendLocalIfHandled(
          configureCellView(),
          (
            tableView: tableView,
            row: row,
            column: slot.column,
            objectValue: tableView.queryTableCellObjectValue(row, slot.column),
            view: slot.view,
          ),
        )
    if not keep:
      tableView.recycleCellSlot(slot)
      tableView.xCellSlots.delete(position)
    else:
      tableView.xCellSlots[position].row = row
      inc position

proc reloadData*(tableView: TableView, updateRows: proc() {.closure.} = nil) =
  ## Reloads rows while preserving selection identities and the viewport anchor.
  ## `updateRows` runs once after the old state is captured, before fresh rows
  ## are queried. Use it to replace source rows or invalidate a cached row list.
  tableView.xWidthMeasurement.valid = false
  tableView.invalidateColumnWidthMeasurements()
  let
    oldOffset = tableView.listContentOffset()
    oldFirst = tableView.firstVisibleIndex()
    offsetWithinRow = oldOffset.y - tableView.rowOffset(oldFirst)
    oldFirstIdentifier = tableView.presentedRowIdentifier(oldFirst)
    selectedIdentifiers =
      tableView.presentedRowIdentifiers(tableView.xRowSelection.indexes)
    anchorIdentifier = tableView.presentedRowIdentifier(tableView.xRowSelection.anchor)
    leadIdentifier = tableView.presentedRowIdentifier(tableView.xRowSelection.lead)
    editingIdentifier =
      if tableView.xCellEditing.state.active:
        tableView.presentedRowIdentifier(tableView.xCellEditing.state.row)
      else:
        ""
  if not updateRows.isNil:
    updateRows()
  tableView.reconcileTableCellSlots()
  tableView.capturePresentedRowIdentifiers()
  tableView.invalidateRowHeightCache()
  tableView.setNeedsLayout()
  if selectedIdentifiers.len > 0:
    tableView.applySelectionForRowIdentifiers(
      selectedIdentifiers, anchorIdentifier, leadIdentifier
    )
  else:
    if tableView.xRowSelection.mode == tsmSingle and
        tableView.xRowSelection.indexes.len > 0 and tableView.len() > 0:
      tableView.xRowSelection.indexes[0] =
        min(max(tableView.xRowSelection.indexes[0], -1), tableView.len() - 1)
    if tableView.xRowSelection.mode == tsmSingle and
        tableView.xRowSelection.index >= tableView.len() and tableView.len() > 0:
      tableView.xRowSelection.index = tableView.len() - 1
    if tableView.xRowSelection.indexes.len == 0 and tableView.xRowSelection.index >= 0:
      tableView.xRowSelection.indexes.add tableView.xRowSelection.index
    tableView.xRowSelection.indexes =
      tableView.normalizeSelection(tableView.xRowSelection.indexes)
    tableView.syncSelectedIndex()
    tableView.syncSelectionCursor()

  if not tableView.rowEnabled(tableView.xHighlightedIndex):
    tableView.xHighlightedIndex = -1
  if not tableView.rowEnabled(tableView.xPressedIndex):
    tableView.xPressedIndex = -1
  if tableView.xCellEditing.state.active and editingIdentifier.len > 0:
    let editingRow = tableView.tableRowIndexForIdentifier(editingIdentifier)
    if editingRow >= 0:
      tableView.xCellEditing.state.row = editingRow
    else:
      tableView.xCellEditing.state = TableEditingState()
      Control(tableView).clearValidationError()
      tableView.clearEditingSurface()
  tableView.layoutTableContentIfNeeded()
  let restoredFirst =
    if oldFirstIdentifier.len > 0:
      let row = tableView.tableRowIndexForIdentifier(oldFirstIdentifier)
      if row >= 0: row else: oldFirst
    else:
      oldFirst
  # Preserve partially clipped rows and let the scroll view clamp to the new bounds.
  tableView.setTableContentOffset(
    initPoint(oldOffset.x, tableView.rowOffset(restoredFirst) + offsetWithinRow), false
  )
  tableView.invalidateIntrinsicContentSize()
  tableView.invalidateTableRows()
  tableView.layoutTableContentIfNeeded()

proc flushTableRowUpdates(tableView: TableView, updates: openArray[TableRowUpdate]) =
  if updates.len == 0:
    return
  tableView.xWidthMeasurement.valid = false
  tableView.invalidateColumnWidthMeasurements()
  let
    selectedIdentifiers =
      tableView.presentedRowIdentifiers(tableView.xRowSelection.indexes)
    anchorIdentifier = tableView.presentedRowIdentifier(tableView.xRowSelection.anchor)
    leadIdentifier = tableView.presentedRowIdentifier(tableView.xRowSelection.lead)
    editingIdentifier =
      if tableView.xCellEditing.state.active:
        tableView.presentedRowIdentifier(tableView.xCellEditing.state.row)
      else:
        ""
  tableView.reconcileTableCellSlots()
  tableView.capturePresentedRowIdentifiers()
  tableView.invalidateRowHeightCache()
  tableView.setNeedsLayout()
  tableView.layoutTableContentIfNeeded()
  if selectedIdentifiers.len > 0:
    tableView.applySelectionForRowIdentifiers(
      selectedIdentifiers, anchorIdentifier, leadIdentifier
    )
  else:
    tableView.xRowSelection.indexes =
      tableView.normalizeSelection(tableView.xRowSelection.indexes)
    tableView.syncSelectedIndex()
    tableView.syncSelectionCursor()
  if tableView.xCellEditing.state.active and editingIdentifier.len > 0:
    let editingRow = tableView.tableRowIndexForIdentifier(editingIdentifier)
    if editingRow >= 0:
      tableView.xCellEditing.state.row = editingRow
  if tableView.xCellEditing.state.active and
      not tableView.validCell(
        tableView.xCellEditing.state.row, tableView.xCellEditing.state.column
      ):
    tableView.xCellEditing.state = TableEditingState()
    Control(tableView).clearValidationError()
    tableView.clearEditingSurface()
  tableView.invalidateTableWidthMeasurement()
  tableView.invalidateTableRows()
  tableView.layoutTableContentIfNeeded()
  emit tableView.tableRowsDidUpdate(DynamicAgent(tableView), @updates)

proc beginTableUpdates*(tableView: TableView) =
  inc tableView.xRowUpdates.depth

proc endTableUpdates*(tableView: TableView) =
  if tableView.xRowUpdates.depth <= 0:
    return
  dec tableView.xRowUpdates.depth
  if tableView.xRowUpdates.depth == 0 and tableView.xRowUpdates.pending.len > 0:
    let updates = tableView.xRowUpdates.pending
    tableView.xRowUpdates.pending.setLen(0)
    tableView.flushTableRowUpdates(updates)

proc applyTableRowUpdates*(tableView: TableView, updates: openArray[TableRowUpdate]) =
  if updates.len == 0:
    return
  if tableView.xRowUpdates.depth > 0:
    for update in updates:
      tableView.xRowUpdates.pending.add update
    return
  tableView.flushTableRowUpdates(updates)

proc insertRowsAtIndexes*(
    tableView: TableView, indexes: openArray[int], identifiers: openArray[string] = []
) =
  tableView.applyTableRowUpdates([initTableRowInsertUpdate(indexes, identifiers)])

proc removeRowsAtIndexes*(
    tableView: TableView, indexes: openArray[int], identifiers: openArray[string] = []
) =
  tableView.applyTableRowUpdates([initTableRowRemoveUpdate(indexes, identifiers)])

proc reloadRowsAtIndexes*(
    tableView: TableView, indexes: openArray[int], identifiers: openArray[string] = []
) =
  tableView.applyTableRowUpdates([initTableRowReloadUpdate(indexes, identifiers)])

proc moveRow*(tableView: TableView, fromIndex, toIndex: int) =
  tableView.applyTableRowUpdates([initTableRowMoveUpdate(fromIndex, toIndex)])

protocol DefaultTableDataUpdates of TableDataUpdateProtocol:
  ## Connects reload requests to row rebuilding and state preservation.
  method reloadTableData(tableView: TableView) =
    ## Reloads rows while preserving selection and viewport state.
    tableView.reloadData()

proc installTableRowUpdateProtocol*(tableView: TableView) =
  discard tableView.withProtocol(DefaultTableDataUpdates)
