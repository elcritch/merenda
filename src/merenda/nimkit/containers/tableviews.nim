## Table widgets and their coordinated selection, editing, and input behavior.
## Core data and geometry live in tablecore; presentation lives in tablepresentation.
## Cell focus and editing are implemented by tablecells.

import std/[algorithm, math, options, strutils, tables, times]

from figdraw import FigIdx
import sigils/core

import ../accessibility/accessibilityprotocols
import ../drawing
import ../foundation/events
import ../app/dragging
import ../app/pasteboards
import ../app/userdefaults
import ../app/windows
import ../controls/controls
import ../containers/listbasics
import ./tablebasics
import ../containers/scrollviews
import ../foundation/objectvalues
import ../foundation/private/itemcollections
import ../foundation/selectors
import ../themes
import ../themes/themecore as themeCore
import ../text/textviews
import ../foundation/types
import ../foundation/undomanagers
from ../view/viewgeometry import setFrameFromLayout
import ../view/views

import ./tablecore
import ./tablecells
import ./tablepresentation

export tablecore, tablepresentation, tablecells

proc installTableModelProtocols(model: TableModel)
proc `dataSource=`*(tableView: TableView, dataSource: DynamicAgent)
proc `dataSource=`*(tableView: TableView, dataSource: Responder)
proc `delegate=`*(tableView: TableView, delegate: DynamicAgent)
proc `delegate=`*(tableView: TableView, delegate: Responder)
proc applySelectedIndexes(
  tableView: TableView, indexes: openArray[int], anchor: int, lead: int
)

proc selectItemAtIndex(tableView: TableView, index: int, modifiers: set[KeyModifier])
proc moveSelection(tableView: TableView, delta: int, extend = false)
proc reloadData*(tableView: TableView, updateRows: proc() {.closure.} = nil)
proc moveRow*(tableView: TableView, fromIndex, toIndex: int)
proc `selectedIndexes=`*(tableView: TableView, indexes: openArray[int])
proc `visibleRows=`*(tableView: TableView, rows: int)
proc activateItemAtIndex*(tableView: TableView, index: int)
proc updateTableDropTarget(tableView: TableView, target: DraggingDropTarget)
proc observeTableStateWindow(tableView: TableView, window: Window)

proc initTableModelFields*(
    model: TableModel,
    rows: openArray[TableRowValue] = [],
    columns: openArray[TableModelColumn] = [],
) =
  model.initTableModelStorage(rows, columns)
  model.installTableModelProtocols()

proc newTableModel*(
    rows: openArray[TableRowValue] = [], columns: openArray[TableModelColumn] = []
): TableModel =
  result = TableModel()
  result.initTableModelFields(rows, columns)

protocol TableModelTableDataSource of TableViewDataSource:
  method numberOfRows(model: TableModel, tableView: TableView): int =
    discard tableView
    model.len()

  method objectValueForCell(
      model: TableModel, tableView: TableView, row: int, column: TableColumn
  ): ObjectValue =
    discard tableView
    model.objectValueForTableModelCell(row, column)

  method textForCell(
      model: TableModel, tableView: TableView, row: int, column: TableColumn
  ): string =
    let value = model.objectValueForTableModelCell(row, column)
    Control(tableView).formatObjectValue(value, ovrTableCell)

  method setObjectValueForCell(
      model: TableModel,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: ObjectValue,
  ): bool =
    discard tableView
    model.setObjectValueForTableModelCell(row, column, value)

  method identifierForRow(model: TableModel, tableView: TableView, row: int): string =
    discard tableView
    model.rowAt(row).identifier

  method rowForIdentifier(
      model: TableModel, tableView: TableView, identifier: string
  ): int =
    discard tableView
    model.indexOfIdentifier(identifier)

protocol TableModelTableDelegate of TableViewDelegate:
  method isRowEnabled(model: TableModel, tableView: TableView, row: int): bool =
    discard tableView
    model.rowAt(row).enabled

  method parseObjectValueForCell(
      model: TableModel,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ): ObjectParseResult =
    model.parseTableModelCellValue(tableView, row, column, value)

  method sortDescriptorsDidChange(
      model: TableModel,
      tableView: TableView,
      column: TableColumn,
      direction: TableSortDirection,
  ) =
    if direction == tsdNone:
      model.sortDescriptors = []
    else:
      model.sortDescriptors =
        [initTableModelSortDescriptor(model.tableModelColumnKey(column), direction)]
    tableView.reloadData()

proc installTableModelProtocols(model: TableModel) =
  discard model.withProtocol(TableModelTableDataSource)
  discard model.withProtocol(TableModelTableDelegate)

proc `rowCount=`*(tableView: TableView, count: int) =
  let nextCount = max(count, 0)
  if tableView.xRowCount == nextCount:
    return
  tableView.xRowCount = nextCount
  tableView.reloadData()

proc `dataSource=`*(tableView: TableView, dataSource: DynamicAgent) =
  if tableView.xTableDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(TableViewDataSource)
  tableView.clearTableCellSlots()
  tableView.xTableDataSource = dataSource
  tableView.reloadData()

proc `dataSource=`*(tableView: TableView, dataSource: Responder) =
  tableView.dataSource = DynamicAgent(dataSource)

proc `delegate=`*(tableView: TableView, delegate: DynamicAgent) =
  if tableView.xTableDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(TableViewDelegate)
  tableView.clearTableCellSlots()
  tableView.xTableDelegate = delegate
  tableView.reloadData()

proc `delegate=`*(tableView: TableView, delegate: Responder) =
  tableView.delegate = DynamicAgent(delegate)

proc applySelectionForRowIdentifiers(
    tableView: TableView,
    identifiers: openArray[string],
    anchorIdentifier, leadIdentifier: string,
) =
  if identifiers.len == 0:
    return
  var rows: seq[int]
  for identifier in identifiers:
    let row = tableView.tableRowIndexForIdentifier(identifier)
    if row >= 0:
      rows.add row
  tableView.applySelectedIndexes(
    rows,
    tableView.tableRowIndexForIdentifier(anchorIdentifier),
    tableView.tableRowIndexForIdentifier(leadIdentifier),
  )

proc indexesInRange(selectionRange: Slice[int]): seq[int] =
  if selectionRange.b < selectionRange.a:
    return @[]
  for index in selectionRange.a .. selectionRange.b:
    result.add index

proc syncSelectedIndex(tableView: TableView) =
  tableView.xRowSelection.index =
    tableView.firstSelectedIndex(tableView.xRowSelection.indexes)

proc normalizeSelection(tableView: TableView, indexes: openArray[int]): seq[int] =
  if tableView.xRowSelection.mode == tsmNone or tableView.len() == 0:
    return @[]
  for index in indexes:
    if tableView.rowSelectable(index):
      result.add index
  result.sort()
  var writeIndex = 0
  for index in result:
    if writeIndex == 0 or result[writeIndex - 1] != index:
      result[writeIndex] = index
      inc writeIndex
  result.setLen(writeIndex)
  if tableView.xRowSelection.mode == tsmSingle and result.len > 1:
    result.setLen(1)

proc normalizeSelectionAnchor(tableView: TableView, anchor: int): int =
  if tableView.rowSelectable(anchor): anchor else: tableView.xRowSelection.index

proc syncSelectionCursor(tableView: TableView) =
  if tableView.xRowSelection.indexes.len == 0:
    tableView.xRowSelection.anchor = -1
    tableView.xRowSelection.lead = -1
    return
  if tableView.xRowSelection.mode == tsmSingle:
    tableView.xRowSelection.anchor = tableView.xRowSelection.index
    tableView.xRowSelection.lead = tableView.xRowSelection.index
    return
  if not tableView.rowSelectable(tableView.xRowSelection.anchor):
    tableView.xRowSelection.anchor = tableView.xRowSelection.index
  if not tableView.rowSelectable(tableView.xRowSelection.lead):
    tableView.xRowSelection.lead = tableView.xRowSelection.index

proc firstSelectableIndex(tableView: TableView): int =
  for index in 0 ..< tableView.len():
    if tableView.rowSelectable(index):
      return index
  -1

proc lastSelectableIndex(tableView: TableView): int =
  for countdown in 0 ..< tableView.len():
    let index = tableView.len() - countdown - 1
    if tableView.rowSelectable(index):
      return index
  -1

proc nextSelectableIndex(tableView: TableView, index, delta: int): int =
  if delta == 0 or tableView.len() == 0:
    return -1
  let step = if delta < 0: -1 else: 1
  var current = index
  while current >= 0 and current < tableView.len():
    if tableView.rowSelectable(current):
      return current
    current += step
  -1

proc applySelectedIndexes(
    tableView: TableView, indexes: openArray[int], anchor: int, lead: int
) =
  let nextIndexes = tableView.normalizeSelection(indexes)
  let
    nextSelected = tableView.firstSelectedIndex(nextIndexes)
    nextAnchor =
      if nextIndexes.len == 0:
        -1
      elif tableView.rowSelectable(anchor):
        anchor
      else:
        nextSelected
    nextLead =
      if nextIndexes.len == 0:
        -1
      elif tableView.rowSelectable(lead):
        lead
      else:
        nextSelected
    selectionChanged = tableView.xRowSelection.indexes != nextIndexes
  if not selectionChanged:
    tableView.xRowSelection.anchor = nextAnchor
    tableView.xRowSelection.lead = nextLead
    if nextIndexes.len == 0:
      tableView.clearFocusedColumn()
    if nextLead >= 0:
      tableView.scrollItemToVisible(nextLead)
    return
  let beforeIndexes = tableView.xRowSelection.indexes
  tableView.findUndoManager().registerSelectionChange(
    proc(indexes: seq[int]) =
      tableView.selectedIndexes = indexes,
    beforeIndexes,
    "Change Selection",
  )
  emit tableView.selectionIsChanging(DynamicAgent(tableView))
  tableView.xRowSelection.indexes = nextIndexes
  tableView.syncSelectedIndex()
  tableView.xRowSelection.anchor = nextAnchor
  tableView.xRowSelection.lead = nextLead
  if nextIndexes.len == 0:
    tableView.clearFocusedColumn()
  if nextLead >= 0:
    tableView.scrollItemToVisible(nextLead)
  tableView.invalidateTableRows()
  emit tableView.selectionDidChange(DynamicAgent(tableView))
  tableView.postAccessibilityNotification(anSelectionChanged)
  if nextSelected >= 0:
    let delegate = tableView.delegate()
    if not delegate.isNil:
      discard delegate.sendLocalIfHandled(
        didSelectTableRow(), (tableView: tableView, row: nextSelected)
      )

proc selectItemAtIndex(tableView: TableView, index: int) =
  if tableView.xRowSelection.mode == tsmNone:
    return
  let boundedIndex = if index < 0 or index >= tableView.len(): -1 else: index
  if boundedIndex >= 0 and not tableView.rowSelectable(boundedIndex):
    return
  if tableView.xRowSelection.index == boundedIndex and
      tableView.xRowSelection.indexes.len <= 1:
    if boundedIndex >= 0:
      tableView.scrollItemToVisible(boundedIndex)
    return
  if boundedIndex < 0:
    tableView.selectedIndexes = @[]
  else:
    tableView.applySelectedIndexes([boundedIndex], boundedIndex, boundedIndex)

proc rangeSelectionIndexes(anchor, lead: int): seq[int] =
  if anchor < 0 or lead < 0:
    return @[]
  let
    firstIndex = min(anchor, lead)
    lastIndex = max(anchor, lead)
  for index in firstIndex .. lastIndex:
    result.add index

proc extendSelectionToIndex(tableView: TableView, index: int) =
  if tableView.xRowSelection.mode != tsmExtended:
    tableView.selectItemAtIndex(index)
    return
  let boundedIndex = if tableView.validTableIndex(index): index else: -1
  if boundedIndex < 0 or not tableView.rowSelectable(boundedIndex):
    return
  let anchor = tableView.normalizeSelectionAnchor(tableView.xRowSelection.anchor)
  tableView.applySelectedIndexes(
    rangeSelectionIndexes(anchor, boundedIndex), anchor, boundedIndex
  )

proc toggleSelectionAtIndex(tableView: TableView, index: int) =
  if tableView.xRowSelection.mode notin {tsmMultiple, tsmExtended}:
    tableView.selectItemAtIndex(index)
    return
  if not tableView.rowSelectable(index):
    return
  var nextIndexes: seq[int]
  if tableView.selectionContains(index):
    for selectedIndex in tableView.xRowSelection.indexes:
      if selectedIndex != index:
        nextIndexes.add selectedIndex
  else:
    nextIndexes = tableView.xRowSelection.indexes
    nextIndexes.add index
  tableView.applySelectedIndexes(nextIndexes, index, index)

proc usesDiscontiguousSelection(modifiers: set[KeyModifier]): bool =
  kmCommand in modifiers or kmControl in modifiers

proc selectItemAtIndex(tableView: TableView, index: int, modifiers: set[KeyModifier]) =
  if tableView.xRowSelection.mode == tsmNone:
    return
  if kmShift in modifiers and tableView.xRowSelection.mode == tsmExtended:
    tableView.extendSelectionToIndex(index)
  elif modifiers.usesDiscontiguousSelection() and
      tableView.xRowSelection.mode in {tsmMultiple, tsmExtended}:
    tableView.toggleSelectionAtIndex(index)
  else:
    tableView.selectItemAtIndex(index)

proc sendTableActivation(tableView: TableView, index: int) =
  if not tableView.rowEnabled(index):
    return
  tableView.tableRowDidActivate(index)
  emit tableView.rowWasActivated(DynamicAgent(tableView))
  discard tableView.sendAction()

proc activateItemAtIndex(
    tableView: TableView, index: int, modifiers: set[KeyModifier]
) =
  if not tableView.rowEnabled(index):
    return
  if tableView.selectionMode() != tsmNone:
    if not tableView.rowSelectable(index):
      return
    tableView.selectItemAtIndex(index, modifiers)
  tableView.sendTableActivation(index)

proc typeSelectStartIndex(tableView: TableView): int =
  if tableView.selectionLeadIndex() >= 0:
    tableView.selectionLeadIndex() + 1
  elif tableView.selectedIndex() >= 0:
    tableView.selectedIndex() + 1
  else:
    tableView.firstVisibleIndex()

proc rowTextMatchesPrefix(
    tableView: TableView, index: int, normalizedPrefix: string
): bool =
  let source = tableView.dataSource()
  if not source.isNil:
    let searchText = source.trySendLocal(
      normalizedSearchTextForRow(), (tableView: tableView, row: index)
    )
    if searchText.isSome:
      return searchText.get().startsWith(normalizedPrefix)
  tableView.rowTextForSummary(index).toLowerAscii().startsWith(normalizedPrefix)

proc firstRowMatchingText(tableView: TableView, text: string): int =
  if text.len == 0 or tableView.len() == 0:
    return -1
  let
    normalized = text.toLowerAscii()
    start = max(tableView.typeSelectStartIndex(), 0)
  for offset in 0 ..< tableView.len():
    let index = (start + offset) mod tableView.len()
    if tableView.rowSelectable(index) and
        tableView.rowTextMatchesPrefix(index, normalized):
      return index
  -1

proc selectItemMatchingText(tableView: TableView, text: string): bool =
  if tableView.selectionMode() == tsmNone:
    return false
  let index = tableView.firstRowMatchingText(text)
  if index < 0:
    return false
  tableView.selectItemAtIndex(index)
  true

proc isTypeSelectEvent(event: KeyEvent): bool =
  event.text.len > 0 and event.text notin [" ", "\n", "\r", "\t"] and
    event.modifiers * {kmControl, kmOption, kmCommand} == {}

proc handleTypeSelect(tableView: TableView, event: KeyEvent): bool =
  if not event.isTypeSelectEvent():
    return false
  let now = epochTime()
  if now - tableView.xTypeSelection.lastInputTime > TableTypeSelectTimeout:
    tableView.xTypeSelection.buffer = ""
  tableView.xTypeSelection.lastInputTime = now
  tableView.xTypeSelection.buffer.add event.text
  if tableView.selectItemMatchingText(tableView.xTypeSelection.buffer):
    return true
  if event.text != tableView.xTypeSelection.buffer:
    tableView.xTypeSelection.buffer = event.text
    return tableView.selectItemMatchingText(tableView.xTypeSelection.buffer)
  false

proc selectCellAtIndex(
    tableView: TableView, index: int, column: TableColumn, modifiers: set[KeyModifier]
) =
  if tableView.xRowSelection.mode == tsmNone:
    return
  if index notin 0 ..< tableView.len() or not tableView.rowSelectable(index):
    return

  let
    previousSelectedIndexes = tableView.xRowSelection.indexes
    previousSelectedColumns = tableView.xSelectedColumns
  tableView.selectItemAtIndex(index, modifiers)
  if column.isNil or not tableView.shouldSelectCell(index, column):
    return

  discard tableView.setFocusedCellColumn(index, column, notifySelection = false)
  tableView.xClickedRow = index
  tableView.xClickedColumn = column
  tableView.needsDisplay = true
  if tvoColumnSelection in tableView.xOptions and
      previousSelectedColumns != tableView.xSelectedColumns and
      previousSelectedIndexes == tableView.xRowSelection.indexes:
    emit tableView.selectionDidChange(DynamicAgent(tableView))
    tableView.postAccessibilityNotification(anSelectionChanged)

proc activateCellAtIndex(
    tableView: TableView, index: int, column: TableColumn, modifiers: set[KeyModifier]
) =
  if not tableView.rowEnabled(index):
    return
  if tableView.selectionMode() != tsmNone:
    if not tableView.rowSelectable(index):
      return
    tableView.selectCellAtIndex(index, column, modifiers)
  tableView.sendTableActivation(index)

proc moveSelectionTo(tableView: TableView, index: int, extend = false, direction = 1) =
  if tableView.len() == 0 or tableView.selectionMode() == tsmNone:
    return
  let targetIndex = max(0, min(index, tableView.len() - 1))
  var boundedIndex = tableView.nextSelectableIndex(targetIndex, direction)
  if boundedIndex < 0 and direction > 0:
    boundedIndex = tableView.nextSelectableIndex(targetIndex, -1)
  elif boundedIndex < 0 and direction < 0:
    boundedIndex = tableView.nextSelectableIndex(targetIndex, 1)
  if boundedIndex < 0:
    return
  if extend and tableView.xRowSelection.mode == tsmExtended:
    tableView.extendSelectionToIndex(boundedIndex)
  else:
    tableView.selectItemAtIndex(boundedIndex)

proc moveSelection(tableView: TableView, delta: int, extend = false) =
  let start =
    if tableView.selectionLeadIndex() >= 0:
      tableView.selectionLeadIndex()
    elif delta > 0:
      tableView.firstVisibleIndex() - 1
    elif delta < 0:
      tableView.firstVisibleIndex() + tableView.visibleItemCount()
    else:
      tableView.firstVisibleIndex()
  tableView.moveSelectionTo(start + delta, extend, delta)

proc pageSelection(tableView: TableView, deltaPages: int, extend = false) =
  let delta = deltaPages * max(tableView.visibleItemCount(), 1)
  if delta == 0:
    return
  let start =
    if tableView.selectionLeadIndex() >= 0:
      tableView.selectionLeadIndex()
    elif delta > 0:
      tableView.firstVisibleIndex() - 1
    else:
      tableView.firstVisibleIndex() + tableView.visibleItemCount()
  let target = start + delta
  tableView.moveSelectionTo(target, extend, delta)
  let scrollView = tableView.xScrollView
  if target >= tableView.len():
    let
      currentOffset = scrollView.contentOffset()
      maximumOffset = scrollView.maximumContentOffset()
    tableView.setTableContentOffset(initPoint(currentOffset.x, maximumOffset.y), true)
  elif target < 0:
    let currentOffset = scrollView.contentOffset()
    tableView.setTableContentOffset(initPoint(currentOffset.x, 0.0'f32), true)

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

proc `rowHeight=`*(tableView: TableView, height: float32) =
  let normalized = height.normalizedRowHeight()
  let previousHeight = tableView.rowHeight()
  tableView.xRowSizing.hasExplicitHeight = true
  if tableView.xRowSizing.height == normalized and previousHeight == normalized:
    return
  tableView.xRowSizing.height = normalized
  tableView.xScrollView.lineScroll = normalized
  tableView.xRowHeightMeasurement.valid = false
  tableView.reloadData()

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
    oldFirstIdentifier = tableView.tableRowIdentifier(oldFirst)
    selectedIdentifiers =
      tableView.rowIdentifiersForRows(tableView.xRowSelection.indexes)
    anchorIdentifier = tableView.tableRowIdentifier(tableView.xRowSelection.anchor)
    leadIdentifier = tableView.tableRowIdentifier(tableView.xRowSelection.lead)
    editingIdentifier =
      if tableView.xCellEditing.state.active:
        tableView.tableRowIdentifier(tableView.xCellEditing.state.row)
      else:
        ""
  if not updateRows.isNil:
    updateRows()
  tableView.clearTableCellSlots()
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
      tableView.rowIdentifiersForRows(tableView.xRowSelection.indexes)
    anchorIdentifier = tableView.tableRowIdentifier(tableView.xRowSelection.anchor)
    leadIdentifier = tableView.tableRowIdentifier(tableView.xRowSelection.lead)
    editingIdentifier =
      if tableView.xCellEditing.state.active:
        tableView.tableRowIdentifier(tableView.xCellEditing.state.row)
      else:
        ""
  tableView.clearTableCellSlots()
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

proc `selectedIndexes=`*(tableView: TableView, indexes: openArray[int]) =
  let nextIndexes = tableView.normalizeSelection(indexes)
  tableView.applySelectedIndexes(
    nextIndexes,
    tableView.firstSelectedIndex(nextIndexes),
    tableView.firstSelectedIndex(nextIndexes),
  )

proc `selectedRange=`*(tableView: TableView, selectionRange: Slice[int]) =
  let indexes = selectionRange.indexesInRange()
  tableView.selectedIndexes = indexes

proc `selectionMode=`*(tableView: TableView, mode: TableSelectionMode) =
  if tableView.xRowSelection.mode == mode:
    return
  tableView.xRowSelection.mode = mode
  if mode == tsmNone:
    tableView.xRowSelection.clear()
    tableView.clearFocusedColumn()
  elif mode == tsmSingle and tableView.xRowSelection.indexes.len > 1:
    tableView.xRowSelection.indexes.setLen(1)
    tableView.xRowSelection.index = tableView.xRowSelection.indexes[0]
    tableView.xRowSelection.anchor = tableView.xRowSelection.index
    tableView.xRowSelection.lead = tableView.xRowSelection.index
  tableView.reloadData()

proc `visibleRows=`*(tableView: TableView, rows: int) =
  let normalized = max(rows, 1)
  if tableView.xRowSizing.visibleRows == normalized:
    return
  tableView.xRowSizing.visibleRows = normalized
  tableView.reloadData()

proc `allowsRowReordering=`*(tableView: TableView, value: bool) =
  if (tvoRowReordering in tableView.xOptions) == value:
    return
  tableView.xOptions[tvoRowReordering] = value
  if not value:
    tableView.xDragging.rowStart.row = -1
    tableView.updateTableDropTarget(initDraggingDropTarget())

proc `selectedIndex=`*(tableView: TableView, index: int) =
  if index < 0:
    tableView.selectedIndexes = @[]
  else:
    tableView.selectItemAtIndex(index)

proc activateItemAtIndex*(tableView: TableView, index: int) =
  tableView.activateItemAtIndex(index, {})

proc `allowsColumnSelection=`*(tableView: TableView, value: bool) =
  if (tvoColumnSelection in tableView.xOptions) == value:
    return
  tableView.xOptions[tvoColumnSelection] = value
  if not value:
    tableView.xSelectedColumns.setLen(0)
    tableView.clearPointerColumnHighlight()
  tableView.needsDisplay = true

proc `selectedColumns=`*(tableView: TableView, columns: openArray[TableColumn]) =
  tableView.setSelectedColumns(@columns)

proc updateTableDropTarget(tableView: TableView, target: DraggingDropTarget) =
  if tableView.xDragging.dropTarget == target:
    return
  tableView.xDragging.dropTarget = target
  tableView.invalidateTableRows()

proc reorderTableModelRows(
    tableView: TableView,
    model: TableModel,
    rows: openArray[int],
    target: DraggingDropTarget,
): bool =
  if not model.canReorderTableModelRows():
    return false
  let normalizedRows = tableView.normalizedReorderRows(rows)
  if not tableView.canReorderRows(normalizedRows, target):
    return false

  let
    insertionIndex = tableView.insertionIndexForDropTarget(target)
    adjustedIndex = adjustedReorderInsertionIndex(normalizedRows, insertionIndex)
    selectedIdentifiers =
      tableView.rowIdentifiersForRows(tableView.xRowSelection.indexes)
    anchorIdentifier = tableView.tableRowIdentifier(tableView.xRowSelection.anchor)
    leadIdentifier = tableView.tableRowIdentifier(tableView.xRowSelection.lead)

  var
    nextRows = model.rows()
    movingRows: seq[TableRowValue]
  for row in normalizedRows:
    movingRows.add nextRows[row]
  for index in countdown(normalizedRows.high, 0):
    nextRows.delete(normalizedRows[index])
  for index, row in movingRows:
    nextRows.insert(row, adjustedIndex + index)

  model.rows = nextRows
  tableView.xRowSelection.clear()
  tableView.reloadData()
  if selectedIdentifiers.len > 0:
    tableView.applySelectionForRowIdentifiers(
      selectedIdentifiers, anchorIdentifier, leadIdentifier
    )
  else:
    var nextSelection: seq[int]
    for index in 0 ..< movingRows.len:
      nextSelection.add adjustedIndex + index
    tableView.selectedIndexes = nextSelection
  true

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

proc bindTableModel*(tableView: TableView, model: TableModel) =
  if model.isNil:
    tableView.dataSource = DynamicAgent(nil)
    tableView.delegate = DynamicAgent(nil)
    return
  model.installTableModelProtocols()
  for modelColumn in model.columns():
    let identifier = modelColumn.itemColumnIdentifier()
    if identifier.len > 0:
      var column = tableView.columnWithIdentifier(identifier)
      if column.isNil:
        column = newTableColumn(
          identifier, modelColumn.itemColumnTitle(), width = modelColumn.width
        )
        tableView.addColumn(column)
      else:
        column.title = modelColumn.itemColumnTitle()
        if modelColumn.width > 0.0'f32:
          column.width = modelColumn.width
      column.hidden = modelColumn.hidden
  tableView.dataSource = DynamicAgent(model)
  tableView.delegate = DynamicAgent(model)
  tableView.reloadData()

func hasExceededDragThreshold(startPoint, location: Point, threshold: float32): bool =
  max(abs(location.x - startPoint.x), abs(location.y - startPoint.y)) >= threshold

proc clearRowDragState(tableView: TableView) =
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

proc tryBeginRowReorderDrag(tableView: TableView, event: MouseEvent): bool =
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

proc updateActiveTableDrag(tableView: TableView, event: MouseEvent): bool =
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

proc performActiveTableDrag(tableView: TableView, event: MouseEvent): bool =
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

proc updateHighlightedCellAtPoint(tableView: TableView, point: Point): int =
  result = tableView.rowItemIndexAtPoint(point)
  if tvoPointerRowHighlights in tableView.xOptions:
    tableView.highlightedIndex = result
  else:
    tableView.clearPointerRowHighlight()
  if tvoPointerColumnHighlights in tableView.xOptions and result >= 0:
    tableView.setHighlightedColumn(tableView.tableColumnAtPoint(point))
  else:
    tableView.setHighlightedColumn(nil)

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

protocol DefaultTableViewMouseHitPolicy of MouseHitPolicyProtocol:
  method mouseHitPolicy(tableView: TableView, args: MouseHitPolicyArgs): CellHitPolicy =
    if not tableView.isEnabled() or args.event.button != mbPrimary:
      return chpDefault
    let row = tableView.rowItemIndexAtPoint(args.event.location)
    if row < 0:
      return chpDefault
    let
      target =
        if args.target of View:
          View(args.target)
        else:
          nil
      column = tableView.tableColumnAtPoint(args.event.location)
    tableView.tableCellHitPolicy(row, column, target, args.event)

  method applyMouseHitPolicy(tableView: TableView, args: MouseHitPolicyArgs): bool =
    if not tableView.isEnabled() or args.event.button != mbPrimary:
      return false
    let
      row = tableView.rowItemIndexAtPoint(args.event.location)
      column = tableView.tableColumnAtPoint(args.event.location)
    if row < 0:
      return false
    let owner = tableView.window()
    if owner of Window:
      discard Window(owner).makeFirstResponder(tableView, focusVisible = false)
    tableView.selectCell(row, column)
    if tvoPointerRowHighlights in tableView.xOptions:
      tableView.highlightedIndex = row
    else:
      tableView.clearPointerRowHighlight()
    if tvoPointerColumnHighlights in tableView.xOptions:
      tableView.setHighlightedColumn(column)
    else:
      tableView.clearPointerColumnHighlight()
    tableView.xPressedIndex = row
    tableView.invalidateTableRows()
    true

protocol DefaultTableViewColumnBehavior of TableViewColumnProtocol:
  method columnAtPoint(tableView: TableView, point: Point): TableColumn =
    var x = 0.0'f32
    for column in tableView.columns:
      if not column.hidden():
        let nextX = x + column.width()
        if point.x >= x and point.x < nextX:
          return column
        x = nextX

  method headerHitTest(tableView: TableView, point: Point): TableHeaderHit =
    result = TableHeaderHit(columnIndex: -1, row: -1, part: thpNone)
    let resizeHandleWidth = tableView.tableStyle().headerResizeHandleWidth
    let rowHeaderRect = tableView.tableRowHeaderCornerRect()
    if rowHeaderRect.contains(point):
      result.rect = rowHeaderRect
      if point.x >= rowHeaderRect.maxX - resizeHandleWidth:
        result.part = thpRowHeaderResizeHandle
      else:
        result.part = thpRowHeader
      return
    let rowHeaderBodyRect = tableView.tableRowHeaderRect()
    if rowHeaderBodyRect.contains(point):
      let contentView = tableView.contentView()
      let rows = contentView.visibleContentRows()
      for row in rows.first ..< rows.last:
        let handleRect = tableView.tableRowHeaderResizeHandleRect(row)
        if handleRect.contains(point):
          result.row = row
          result.rect = tableView.tableRowHeaderCellRect(row)
          result.part = thpRowHeaderRowResizeHandle
          return
      return
    if not tableView.tableHeaderRect().contains(point):
      return
    for index, column in tableView.xColumns:
      let rect = tableView.tableHeaderColumnRect(column)
      if not rect.isEmpty and column.resizePolicy() == tcrResizable:
        let handleRect = rect(
          rect.maxX - resizeHandleWidth,
          rect.origin.y,
          resizeHandleWidth * 2.0'f32,
          rect.size.height,
        )
        if handleRect.contains(point):
          result.column = column
          result.columnIndex = index
          result.part = thpResizeHandle
          result.rect = rect
          return
    for index, column in tableView.xColumns:
      let rect = tableView.tableHeaderColumnRect(column)
      if rect.contains(point):
        result.column = column
        result.columnIndex = index
        result.rect = rect
        result.part = thpColumn
        return

  method resizeColumn(tableView: TableView, column: TableColumn, width: float32) =
    if column.isNil or column.tableView() != tableView:
      return
    if column.resizePolicy() == tcrFixed:
      return
    column.xWidth.userResized = true
    column.width = width
    if tableView.xCellEditing.state.active and
        tableView.xCellEditing.state.column == column:
      tableView.clearEditingSurface()
      let editor = Control(tableView).currentEditor()
      if not editor.isNil:
        tableView.installFieldEditorOnSurface(editor)
    tableView.syncHeaderTrackingAreas()
    tableView.setNeedsLayout()
    tableView.needsDisplay = true

  method moveColumn(tableView: TableView, fromIndex, toIndex: int) =
    if fromIndex notin 0 ..< tableView.xColumns.len:
      return
    let boundedTo = max(0, min(toIndex, tableView.xColumns.len - 1))
    if fromIndex == boundedTo:
      return
    let column = tableView.xColumns[fromIndex]
    tableView.findUndoManager().registerCollectionMove(
      proc(fromIndex, toIndex: int) =
        tableView.moveColumn(fromIndex, toIndex),
      fromIndex,
      boundedTo,
      "Move Column",
    )
    tableView.xColumns.delete(fromIndex)
    tableView.xColumns.insert(column, boundedTo)
    tableView.noteColumnsChanged()

  method requestSort(
      tableView: TableView, column: TableColumn, direction: TableSortDirection
  ) =
    if column.isNil or column.tableView() != tableView:
      return
    let
      selectedIdentifiers =
        tableView.rowIdentifiersForRows(tableView.xRowSelection.indexes)
      anchorIdentifier = tableView.tableRowIdentifier(tableView.xRowSelection.anchor)
      leadIdentifier = tableView.tableRowIdentifier(tableView.xRowSelection.lead)
    for current in tableView.xColumns.mitems:
      if current != column and current.xSortDirection != tsdNone:
        current.xSortDirection = tsdNone
    column.sortDirection = direction
    let delegate = tableView.delegate()
    if not delegate.isNil:
      discard delegate.sendLocalIfHandled(
        sortDescriptorsDidChange(),
        (tableView: tableView, column: column, direction: direction),
      )
    tableView.applySelectionForRowIdentifiers(
      selectedIdentifiers, anchorIdentifier, leadIdentifier
    )

  method headerMouseDown(tableView: TableView, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    let hit = tableView.tableHeaderHitTest(event.location)
    if hit.part == thpNone:
      return false
    tableView.xHeaderTracking = TableHeaderTracking(
      part: hit.part,
      column: hit.column,
      columnIndex: hit.columnIndex,
      row: hit.row,
      startPoint: event.location,
      insertionIndex: -1,
    )
    tableView.xPressedColumn = hit.column
    tableView.xHeaderTracking.startSize.width =
      if hit.part == thpRowHeaderResizeHandle:
        tableView.rowHeaderWidth()
      elif hit.part == thpRowHeaderRowResizeHandle:
        0.0'f32
      elif hit.column.isNil:
        0.0'f32
      else:
        hit.column.width()
    tableView.xHeaderTracking.startSize.height =
      if hit.part == thpRowHeaderRowResizeHandle:
        tableView.rowHeightForRow(hit.row)
      else:
        0.0'f32
    tableView.needsDisplay = true
    true

  method headerMouseDragged(tableView: TableView, event: MouseEvent): bool =
    if not tableView.xHeaderTracking.isActive():
      return false
    let
      startPoint = tableView.xHeaderTracking.startPoint
      startSize = tableView.xHeaderTracking.startSize
    case tableView.xHeaderTracking.part
    of thpRowHeaderResizeHandle:
      tableView.rowHeaderWidth = startSize.width + event.location.x - startPoint.x
    of thpRowHeaderRowResizeHandle:
      tableView.applyRowHeightResize(
        tableView.xHeaderTracking.row,
        startSize.height + event.location.y - startPoint.y,
      )
    of thpRowHeader:
      discard
    of thpResizeHandle:
      if tableView.xHeaderTracking.column.isNil:
        return false
      tableView.resizeColumn(
        tableView.xHeaderTracking.column,
        startSize.width + event.location.x - startPoint.x,
      )
    of thpColumn:
      if tableView.xHeaderTracking.column.isNil:
        return false
      if abs(event.location.x - startPoint.x) >
          tableView.tableStyle().headerDragThreshold:
        tableView.xHeaderTracking.draggingColumn = true
      if tableView.xHeaderTracking.draggingColumn:
        if not tableView.autoscrollHeaderColumnDrag(event.location):
          tableView.setHeaderDragInsertion(
            tableView.headerInsertionIndexAtPoint(event.location)
          )
        tableView.needsDisplay = true
    of thpNone:
      discard
    true

  method headerMouseUp(tableView: TableView, event: MouseEvent): bool =
    if not tableView.xHeaderTracking.isActive():
      return false
    let
      hit = tableView.tableHeaderHitTest(event.location)
      clickedColumn = tableView.xHeaderTracking.column
      clickedPart = tableView.xHeaderTracking.part
      fromIndex = tableView.xHeaderTracking.columnIndex
      moved =
        tableView.xHeaderTracking.draggingColumn or (
          clickedPart == thpColumn and
          abs(event.location.x - tableView.xHeaderTracking.startPoint.x) >
          tableView.tableStyle().headerDragThreshold
        )
      insertionIndex = tableView.xHeaderTracking.insertionIndex
    tableView.xHeaderTracking.clear()
    tableView.xPressedColumn = nil
    if clickedPart == thpColumn and not clickedColumn.isNil:
      if moved:
        let targetIndex =
          if insertionIndex < 0:
            tableView.headerInsertionIndexAtPoint(event.location)
          else:
            insertionIndex
        if targetIndex >= 0:
          var toIndex = targetIndex
          if fromIndex < targetIndex:
            dec toIndex
          toIndex = max(0, min(toIndex, tableView.xColumns.len - 1))
          tableView.moveColumn(fromIndex, toIndex)
      elif hit.column == clickedColumn:
        let nextDirection =
          if clickedColumn.sortDirection() == tsdAscending:
            tsdDescending
          else:
            tsdAscending
        tableView.requestSort(clickedColumn, nextDirection)
    tableView.needsDisplay = true
    true

  method headerMouseMoved(tableView: TableView, event: MouseEvent): bool =
    let column = tableView.tableHeaderHitTest(event.location).column
    if tableView.xHoveredColumn == column:
      return column != nil
    tableView.xHoveredColumn = column
    tableView.needsDisplay = true
    column != nil

protocol DefaultTableViewSelectionBehavior of TableViewSelectionProtocol:
  method shouldSelectCell(tableView: TableView, row: int, column: TableColumn): bool =
    tableView.validCell(row, column)

  method selectCell(tableView: TableView, row: int, column: TableColumn) =
    if not tableView.shouldSelectCell(row, column):
      return
    let previousSelectedIndexes = tableView.xRowSelection.indexes
    let previousSelectedColumns = tableView.xSelectedColumns
    tableView.selectedIndex = row
    discard tableView.setFocusedCellColumn(row, column, notifySelection = false)
    tableView.xClickedRow = row
    tableView.xClickedColumn = column
    tableView.needsDisplay = true
    if tvoColumnSelection in tableView.xOptions and
        previousSelectedColumns != tableView.xSelectedColumns and
        previousSelectedIndexes == tableView.xRowSelection.indexes:
      emit tableView.selectionDidChange(DynamicAgent(tableView))
      tableView.postAccessibilityNotification(anSelectionChanged)

  method setSelectedColumns(tableView: TableView, columns: seq[TableColumn]) =
    if tvoColumnSelection notin tableView.xOptions:
      return
    var next: seq[TableColumn]
    for column in columns:
      if not column.isNil and column.tableView() == tableView:
        var seen = false
        for existing in next:
          if existing == column:
            seen = true
        if not seen:
          next.add column
    if tableView.xSelectedColumns == next:
      return
    tableView.xSelectedColumns = next
    let row = tableView.selectionLeadIndex()
    if next.len > 0 and row >= 0 and not next[0].hidden() and
        tableView.shouldSelectCell(row, next[0]):
      tableView.xFocusedColumn = next[0]
    else:
      tableView.clearFocusedColumn()
    tableView.needsDisplay = true
    emit tableView.selectionDidChange(DynamicAgent(tableView))
    tableView.postAccessibilityNotification(anSelectionChanged)

  method selectionPersistenceString(tableView: TableView): string =
    let selectedIdentifiers =
      tableView.rowIdentifiersForRows(tableView.selectedIndexes())
    if selectedIdentifiers.len > 0:
      return TableSelectionIdentityPrefix & joinIdentifiers(selectedIdentifiers)
    var first = true
    for row in tableView.selectedIndexes():
      if not first:
        result.add ","
      result.add $row
      first = false

  method restoreSelectionPersistenceString(tableView: TableView, value: string) =
    if value.startsWith(TableSelectionIdentityPrefix):
      let payload =
        if value.len > TableSelectionIdentityPrefix.len:
          value[TableSelectionIdentityPrefix.len .. ^1]
        else:
          ""
      let identifiers = parseIdentifiers(payload)
      if identifiers.len == 0:
        tableView.selectedIndexes = []
      else:
        tableView.applySelectionForRowIdentifiers(identifiers, "", "")
      return
    var rows: seq[int]
    var token = ""
    for ch in value:
      if ch == ',':
        if token.len > 0:
          try:
            rows.add parseInt(token)
          except ValueError:
            discard
        token.setLen(0)
      else:
        token.add ch
    if token.len > 0:
      try:
        rows.add parseInt(token)
      except ValueError:
        discard
    tableView.selectedIndexes = rows

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

protocol DefaultTableViewPersistenceBehavior of TableViewPersistenceProtocol:
  method columnAutosaveRecords(tableView: TableView): seq[TableColumnAutosaveRecord] =
    for column in tableView.xColumns:
      result.add TableColumnAutosaveRecord(
        identifier: column.identifier(),
        width: column.xWidth.preferred,
        hidden: column.hidden(),
        sortDirection: column.sortDirection(),
      )

  method restoreColumnAutosaveRecords(
      tableView: TableView, records: seq[TableColumnAutosaveRecord]
  ) =
    var ordered: seq[TableColumn]
    var restored: seq[TableColumn]
    for record in records:
      let resolvedIdentifier =
        tableView.resolveColumnAutosaveIdentifier(record.identifier)
      let column = tableView.columnWithIdentifier(resolvedIdentifier)
      if not column.isNil and column notin restored:
        column.xWidth.preferred = record.width.normalizedWidth(column.xWidth)
        column.xWidth.resolved = column.xWidth.preferred
        column.xHidden = record.hidden
        column.xSortDirection = record.sortDirection
        ordered.add column
        restored.add column
    for column in tableView.xColumns:
      var seen = false
      for existing in ordered:
        if existing == column:
          seen = true
      if not seen:
        ordered.add column
    tableView.xColumns = ordered
    tableView.noteColumnsChanged()

protocol DefaultTableViewStateBehavior of TableViewStateProtocol:
  method captureState(tableView: TableView): TableViewState =
    var selectedColumns: seq[string]
    for column in tableView.selectedColumns():
      if not column.isNil:
        selectedColumns.add column.identifier()
    let selectedRowIdentifiers =
      tableView.rowIdentifiersForRows(tableView.selectedIndexes())
    initTableViewState(
      tableView.columnAutosaveRecords(),
      tableView.selectedIndexes(),
      selectedColumns,
      selectedRowIdentifiers = selectedRowIdentifiers,
    )

  method restoreState(tableView: TableView, state: TableViewState) =
    tableView.restoreColumnAutosaveRecords(state.columns)
    if state.selectedRowIdentifiers.len > 0:
      var hasRestoredRow = false
      for identifier in state.selectedRowIdentifiers:
        if tableView.tableRowIndexForIdentifier(identifier) >= 0:
          hasRestoredRow = true
          break
      if hasRestoredRow:
        tableView.applySelectionForRowIdentifiers(state.selectedRowIdentifiers, "", "")
      else:
        tableView.selectedIndexes = state.selectedRows
    else:
      tableView.selectedIndexes = state.selectedRows
    if tableView.allowsColumnSelection():
      var columns: seq[TableColumn]
      for identifier in state.selectedColumns:
        let column = tableView.columnWithIdentifier(
          tableView.resolveColumnAutosaveIdentifier(identifier)
        )
        if not column.isNil:
          columns.add column
      tableView.selectedColumns = columns

protocol TableViewStateWindowLifecycleSlots of WindowLifecycleEvents:
  proc willClose(tableView: TableView) {.slot.} =
    tableView.saveAutosavedState()

proc unobserveTableStateWindow(tableView: TableView) =
  if tableView.xObservedStateWindow.isNil:
    return
  tableView.unobserveProtocol(
    tableView.xObservedStateWindow, TableViewStateWindowLifecycleSlots
  )
  tableView.xObservedStateWindow = nil

proc observeTableStateWindow(tableView: TableView, window: Window) =
  if tableView.xObservedStateWindow == window:
    return
  tableView.unobserveTableStateWindow()
  if window.isNil:
    return
  tableView.observeProtocol(window, TableViewStateWindowLifecycleSlots)
  tableView.xObservedStateWindow = window

protocol TableViewStateViewLifecycleSlots of ViewLifecycleProtocol:
  proc saveTableStateBeforeWindowChange(
      tableView: TableView, window: Responder
  ) {.slotFor: viewWillMoveToWindow.} =
    let currentWindow =
      if tableView.window() of Window:
        Window(tableView.window())
      else:
        nil
    if not currentWindow.isNil and DynamicAgent(currentWindow) != DynamicAgent(window):
      tableView.saveAutosavedState()
      tableView.unobserveTableStateWindow()
      tableView.xHasRestoredState = false

  proc restoreTableStateAfterWindowChange(
      tableView: TableView
  ) {.slotFor: viewDidMoveToWindow.} =
    let currentWindow =
      if tableView.window() of Window:
        Window(tableView.window())
      else:
        nil
    tableView.observeTableStateWindow(currentWindow)
    if not currentWindow.isNil:
      tableView.restoreStateIfNeeded()

proc initTableViewFields*(tableView: TableView, frame: Rect = AutoRect) =
  initControlFields(tableView, frame)
  let style = tableView.tableStyle()
  tableView.xRowSizing.height = style.rowHeight
  tableView.xHeaderSettings.height = style.headerHeight
  tableView.xScrollView = initTableScrollView(tableView)
  tableView.xContentView = initTableContentView(tableView)
  tableView.xScrollView.documentView = tableView.xContentView
  tableView.xScrollView.clipView().connect(
    geometryDidChange, tableView, tableViewportGeometryChanged
  )
  tableView.acceptsFirstResponder = true
  tableView.clipsToBounds = true
  tableView.addSubview(tableView.xScrollView)
  tableView.syncTableScrollChrome()
  tableView.syncHeaderTrackingAreas()
  tableView.installTableLayoutProtocol()
  discard tableView.withProtocol(DefaultTableViewColumnBehavior)
  discard tableView.withProtocol(DefaultTableViewSelectionBehavior)
  tableView.installTableCellEditingProtocols()
  discard tableView.withProtocol(DefaultTableViewEvents)
  discard tableView.withProtocol(DefaultTableViewMouseHitPolicy)
  discard tableView.withProtocol(DefaultTableViewDraggingBehavior)
  discard tableView.withProtocol(DefaultTableViewDraggingSource)
  discard tableView.withProtocol(DefaultTableViewDraggingDestination)
  discard tableView.withProtocol(DefaultTableViewPersistenceBehavior)
  discard tableView.withProtocol(DefaultTableViewStateBehavior)
  discard tableView.withProtocol(TableViewStateViewLifecycleSlots)
  tableView.observeProtocol(tableView, TableViewStateViewLifecycleSlots)
  tableView.installTableDrawingProtocols()
  tableView.applyInitialFrame(frame)

proc newTableView*(frame: Rect = AutoRect): TableView =
  result = TableView()
  initTableViewFields(result, frame)
