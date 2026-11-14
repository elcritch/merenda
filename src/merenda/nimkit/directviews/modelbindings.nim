## Scope-owned bridges from ArrayController changes to model-backed views.
## Changes are coalesced by the scope and applied on its owning GUI thread.
import sigils/[core, selectors]
import ../app/modelcontrollers
import ../containers/collectionviews
import ../tables/tableviews
import ./bindings

proc controllerChanged(controller: ArrayController, context: int): bool =
  discard controller
  discard context
  true

proc refreshCollection(view: CollectionView, changed: bool) =
  if changed:
    view.reloadData()

proc refreshTable(view: TableView, changed: bool) =
  if changed:
    view.reloadData()

proc bindCollectionModel*(
    scope: BindingScope, id: string, view: CollectionView, controller: ArrayController
) =
  ## Replacing the same binding ID disconnects the previous controller.
  let previousSource = view.dataSource()
  if previousSource != DynamicAgent(controller):
    let previousDelegate = view.delegate()
    view.dataSource = DynamicAgent(controller)
    if previousDelegate.isNil or previousDelegate == previousSource:
      view.delegate = DynamicAgent(controller)
    if not controller.isNil:
      view.selectionMode =
        case controller.selectionController.mode
        of mselNone: csmNone
        of mselSingle: csmSingle
        of mselMultiple: csmMultiple
      view.selectedIdentifiers = controller.selectionController.selectedIdentifiers
  bindValue(
    scope, id, controller, arrayControllerDidChange, controller, 0, controllerChanged,
    view, refreshCollection,
  )

proc bindTableModel*(
    scope: BindingScope, id: string, view: TableView, controller: ArrayController
) =
  ## The controller's presentation order is queried afresh on every flush.
  let previousSource = view.dataSource()
  if previousSource != DynamicAgent(controller):
    let previousDelegate = view.delegate()
    if not controller.isNil:
      for column in controller.columns:
        if column.identifier.len > 0 and not view.containsColumn(column.identifier):
          let title = if column.title.len > 0: column.title else: column.identifier
          let tableColumn =
            if column.width > 0:
              newTableColumn(column.identifier, title, width = column.width)
            else:
              newTableColumn(column.identifier, title)
          view.addColumn(tableColumn)
    view.dataSource = DynamicAgent(controller)
    if previousDelegate.isNil or previousDelegate == previousSource:
      view.delegate = DynamicAgent(controller)
  bindValue(
    scope, id, controller, arrayControllerDidChange, controller, 0, controllerChanged,
    view, refreshTable,
  )
