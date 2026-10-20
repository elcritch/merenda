## Table-model construction, data-source/delegate adapters, binding, and reordering.

import ../app/dragging
import ../controls/controls
import ../foundation/objectvalues
import ../foundation/selectors
from ../foundation/private/itemcollections import itemColumnIdentifier, itemColumnTitle
import ./tablecore
import ./tablepresentation
import ./tableselection
import ./tablerows

proc installTableModelProtocols(model: TableModel)

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

proc reorderTableModelRows*(
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
