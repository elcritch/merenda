## Internal synchronous requests across table feature layers.

import sigils/selectors

protocol TableDataUpdateProtocol {.selectorScope: protocol.}:
  method reloadTableData*()

protocol TableCellLayoutProtocol {.selectorScope: protocol.}:
  method refreshEditingCellLayout*()

proc requestTableReload*(tableView: DynamicAgent) =
  if not tableView.sendLocalIfHandled(reloadTableData()):
    raise newException(UnhandledSelectorError, "missing table data update protocol")

proc requestTableEditorLayout*(tableView: DynamicAgent) =
  if not tableView.sendLocalIfHandled(refreshEditingCellLayout()):
    raise newException(UnhandledSelectorError, "missing table cell layout protocol")
