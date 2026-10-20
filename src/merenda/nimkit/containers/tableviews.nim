## Table widget construction and public feature exports.
## Mouse/keyboard input is implemented by tableinput.
## Feature modules own data/geometry, presentation, row selection, cell editing,
## row updates, model adapters, state persistence, and dragging.

import sigils/core
import ../controls/controls
import ../foundation/selectors
import ../foundation/types
import ../view/views
import ./scrollviews
import ./tablecore
import ./tablepresentation
import ./tableselection
import ./tablecells
import ./tablerows
import ./tablemodels
import ./tablestate
import ./tabledragging
import ./tableinput

export tablecore, tablepresentation, tablecells, tablestate
export
  tableselection.`selectedIndexes=`, tableselection.`selectedRange=`,
  tableselection.`selectionMode=`, tableselection.`selectedIndex=`,
  tableselection.activateItemAtIndex
export
  tablerows.reloadData, tablerows.beginTableUpdates, tablerows.endTableUpdates,
  tablerows.applyTableRowUpdates, tablerows.insertRowsAtIndexes,
  tablerows.removeRowsAtIndexes, tablerows.reloadRowsAtIndexes, tablerows.moveRow
export
  tablemodels.initTableModelFields, tablemodels.newTableModel,
  tablemodels.bindTableModel
export tabledragging.`allowsRowReordering=`, tabledragging.reorderRows
export
  tableinput.defaultTableViewMouseDown, tableinput.defaultTableViewMouseDragged,
  tableinput.defaultTableViewMouseUp, tableinput.defaultTableViewKeyDown

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
  tableView.installTableRowUpdateProtocol()
  tableView.installTableLayoutProtocol()
  tableView.installTableColumnProtocol()
  tableView.installTableCellSelectionProtocol()
  tableView.installTableCellEditingProtocols()
  tableView.installTableInputProtocol()
  tableView.installTableMouseHitPolicy()
  tableView.installTableDraggingProtocols()
  tableView.installTableStateProtocols()
  tableView.installTableDrawingProtocols()
  tableView.applyInitialFrame(frame)

proc newTableView*(frame: Rect = AutoRect): TableView =
  result = TableView()
  initTableViewFields(result, frame)
