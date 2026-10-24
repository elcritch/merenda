## Internal synchronous requests across table feature layers.

import sigils/selectors

protocol TableDataUpdateProtocol {.selectorScope: protocol.}:
  ## Routes reload requests to the row-update layer.
  method reloadTableData*()
    ## Reloads rows while preserving selection and viewport state.

protocol TableCellLayoutProtocol {.selectorScope: protocol.}:
  ## Routes editor-layout updates to the cell-editing layer.
  method refreshEditingCellLayout*() ## Reattaches the active editor to its current cell.

proc requestTableReload*(tableView: DynamicAgent) =
  if not tableView.sendLocalIfHandled(reloadTableData()):
    raise newException(UnhandledSelectorError, "missing table data update protocol")

proc requestTableEditorLayout*(tableView: DynamicAgent) =
  if not tableView.sendLocalIfHandled(refreshEditingCellLayout()):
    raise newException(UnhandledSelectorError, "missing table cell layout protocol")
