## Table state stores, column/selection persistence, and window lifecycle.

import std/[options, strutils, tables]
import sigils/core
import ../app/userdefaults
import ../app/windows
import ../foundation/selectors
import ../view/views
import ./tablecore
import ./tablepresentation
import ./tableselection
import ./tablecells

type TableViewStateStore* = ref object of DynamicAgent
  xStates: Table[string, TableViewState]

const TableViewStateDefaultsPrefix = "nimkit.table.state."

proc newTableViewStateStore*(): TableViewStateStore

proc autosaveName*(tableView: TableView): string =
  tableView.xAutosaveName

proc `autosaveName=`*(tableView: TableView, name: string) =
  if tableView.xAutosaveName == name:
    return
  tableView.xAutosaveName = name
  tableView.xHasRestoredState = false

proc stateStorage*(tableView: TableView): DynamicAgent =
  tableView.xStateStorage

proc `stateStorage=`*(tableView: TableView, storage: DynamicAgent) =
  if tableView.xStateStorage == storage:
    return
  tableView.xStateStorage = storage
  tableView.xHasRestoredState = false

proc `stateStorage=`*(tableView: TableView, storage: Responder) =
  tableView.stateStorage = DynamicAgent(storage)

proc stateScope*(tableView: TableView): TableViewStateScope =
  tableView.xStateScope

proc `stateScope=`*(tableView: TableView, scope: TableViewStateScope) =
  if tableView.xStateScope == scope:
    return
  tableView.xStateScope = scope
  tableView.xHasRestoredState = false

proc workspaceIdentifier*(tableView: TableView): string =
  tableView.xWorkspaceIdentifier

proc `workspaceIdentifier=`*(tableView: TableView, identifier: string) =
  if tableView.xWorkspaceIdentifier == identifier:
    return
  tableView.xWorkspaceIdentifier = identifier
  tableView.xHasRestoredState = false

proc registerColumnAutosaveAlias*(
    tableView: TableView, oldIdentifier, newIdentifier: string
) =
  if oldIdentifier.len == 0 or newIdentifier.len == 0:
    return
  tableView.xColumnAutosaveAliases[oldIdentifier] = newIdentifier
  tableView.xHasRestoredState = false

proc clearColumnAutosaveAliases*(tableView: TableView) =
  tableView.xColumnAutosaveAliases.clear()
  tableView.xHasRestoredState = false

proc resolveColumnAutosaveIdentifier*(
    tableView: TableView, identifier: string
): string =
  result = identifier
  var seen: seq[string]
  while result in tableView.xColumnAutosaveAliases and result notin seen:
    seen.add result
    result = tableView.xColumnAutosaveAliases[result]

proc tableViewStateScopeKey(kind, identifier: string): string =
  if identifier.len == 0:
    kind
  elif identifier.startsWith(kind & ":"):
    identifier
  else:
    kind & ":" & identifier

proc tableViewStateStoreForDefaults*(
    defaults: UserDefaults, identifier: string
): TableViewStateStore =
  let resolvedDefaults =
    if defaults.isNil:
      sharedUserDefaults()
    else:
      defaults
  let key =
    if identifier.len == 0:
      TableViewStateDefaultsPrefix & "application"
    else:
      TableViewStateDefaultsPrefix & identifier
  let existing = resolvedDefaults.objectForKey(key)
  if existing.isSome and existing.get() of TableViewStateStore:
    return TableViewStateStore(existing.get())
  result = newTableViewStateStore()
  resolvedDefaults.setObjectForKey(key, DynamicAgent(result))

proc userDefaultsTableViewStateStore*(): TableViewStateStore =
  tableViewStateStoreForDefaults(sharedUserDefaults(), "")

proc workspaceTableViewStateStore*(identifier: string): TableViewStateStore =
  if identifier.len == 0:
    return userDefaultsTableViewStateStore()
  tableViewStateStoreForDefaults(
    sharedUserDefaults(), tableViewStateScopeKey("workspace", identifier)
  )

proc documentTableViewStateStore*(identifier: string): TableViewStateStore =
  if identifier.len == 0:
    return userDefaultsTableViewStateStore()
  tableViewStateStoreForDefaults(
    sharedUserDefaults(), tableViewStateScopeKey("document", identifier)
  )

proc stateProviderForTableView(tableView: TableView): Responder =
  var responder = Responder(tableView)
  while not responder.isNil:
    if responder.trySendLocal(defaultsStore(), ()).isSome or
        responder.trySendLocal(defaultsScopeId(), ()).isSome:
      return responder
    responder = responder.nextResponder()

proc stateStorageFromProvider(provider: Responder): DynamicAgent =
  if provider.isNil:
    return nil
  let
    storage = provider.trySendLocal(defaultsStore(), ())
    identifier = provider.trySendLocal(defaultsScopeId(), ())
    scopeId =
      if identifier.isSome:
        identifier.get()
      else:
        ""
  if storage.isSome:
    let store = storage.get()
    if store of TableViewStateStore:
      return store
    if store of UserDefaults:
      return DynamicAgent(
        tableViewStateStoreForDefaults(
          UserDefaults(store), tableViewStateScopeKey("document", scopeId)
        )
      )
  if scopeId.len > 0:
    return DynamicAgent(documentTableViewStateStore(scopeId))

proc resolveTableViewStateStorage(tableView: TableView): DynamicAgent =
  if not tableView.xStateStorage.isNil:
    return tableView.xStateStorage
  case tableView.xStateScope
  of tvssApplication:
    DynamicAgent(userDefaultsTableViewStateStore())
  of tvssWorkspace:
    DynamicAgent(workspaceTableViewStateStore(tableView.xWorkspaceIdentifier))
  of tvssDocument:
    let storage = stateStorageFromProvider(tableView.stateProviderForTableView())
    if storage.isNil:
      DynamicAgent(userDefaultsTableViewStateStore())
    else:
      storage
  of tvssAutomatic:
    if tableView.xWorkspaceIdentifier.len > 0:
      DynamicAgent(workspaceTableViewStateStore(tableView.xWorkspaceIdentifier))
    else:
      let storage = stateStorageFromProvider(tableView.stateProviderForTableView())
      if storage.isNil:
        DynamicAgent(userDefaultsTableViewStateStore())
      else:
        storage

proc saveStateToStorage*(tableView: TableView, storage: DynamicAgent) =
  if storage.isNil or tableView.autosaveName().len == 0:
    return
  discard storage.sendLocalIfHandled(
    saveTableViewState(),
    (name: tableView.autosaveName(), state: tableView.captureState()),
  )

proc restoreStateFromStorage*(tableView: TableView, storage: DynamicAgent) =
  if storage.isNil or tableView.autosaveName().len == 0:
    return
  let name = tableView.autosaveName()
  let hasState = storage.trySendLocal(hasTableViewState(), name)
  if hasState.isSome and not hasState.get():
    return
  let state = storage.trySendLocal(loadTableViewState(), name)
  if state.isSome:
    tableView.restoreState(state.get())

proc saveAutosavedState*(tableView: TableView) =
  tableView.saveStateToStorage(tableView.resolveTableViewStateStorage())

proc restoreAutosavedState*(tableView: TableView) =
  tableView.restoreStateFromStorage(tableView.resolveTableViewStateStorage())

proc restoreStateIfNeeded*(tableView: TableView) =
  if tableView.xHasRestoredState:
    return
  tableView.restoreAutosavedState()
  tableView.xHasRestoredState = true

protocol TableViewStateStoreBehavior of TableViewStateStorageProtocol:
  ## Keeps named table snapshots in an in-memory store.
  method saveTableViewState(
      store: TableViewStateStore, name: string, state: TableViewState
  ) = ## Stores a table snapshot under its autosave name.
    if name.len == 0:
      return
    store.xStates[name] = state

  method loadTableViewState(store: TableViewStateStore, name: string): TableViewState =
    ## Loads a named snapshot, returning empty state when absent.
    if name.len == 0:
      return initTableViewState()
    store.xStates.getOrDefault(name, initTableViewState())

  method hasTableViewState(store: TableViewStateStore, name: string): bool =
    ## Reports whether a named snapshot exists.
    name in store.xStates

proc newTableViewStateStore*(): TableViewStateStore =
  result = TableViewStateStore()
  result.xStates = initTable[string, TableViewState]()
  discard result.withProtocol(TableViewStateStoreBehavior)

proc hasState*(store: TableViewStateStore, name: string): bool =
  name in store.xStates

proc state*(store: TableViewStateStore, name: string): TableViewState =
  store.xStates.getOrDefault(name, initTableViewState())

protocol DefaultTableViewPersistenceBehavior of TableViewPersistenceProtocol:
  ## Restores column order, width, visibility, and sorting by identifier.
  method columnAutosaveRecords(tableView: TableView): seq[TableColumnAutosaveRecord] =
    ## Captures column order, widths, visibility, and sort directions.
    for column in tableView.xColumns:
      result.add TableColumnAutosaveRecord(
        identifier: column.identifier(),
        width: column.xWidth.preferred,
        hidden: column.hidden(),
        sortDirection: column.sortDirection(),
      )

  method restoreColumnAutosaveRecords(
      tableView: TableView, records: seq[TableColumnAutosaveRecord]
  ) = ## Restores known columns by identity and retains unlisted columns.
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
  ## Restores table configuration and selection using stable identities.
  method captureState(tableView: TableView): TableViewState =
    ## Captures column configuration and selected row and column identities.
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
    ## Restores column configuration and selection from a snapshot.
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
  ## Saves table state when the observed window closes.
  proc willClose(tableView: TableView) {.slot.} =
    ## Saves autosaved state before the observed window closes.
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
  ## Saves and restores table state as window ownership changes.
  proc saveTableStateBeforeWindowChange(
      tableView: TableView, window: Responder
  ) {.slotFor: viewWillMoveToWindow.} =
    ## Saves state and removes observation of the previous window.
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
    ## Observes the new window and restores autosaved state once.
    let currentWindow =
      if tableView.window() of Window:
        Window(tableView.window())
      else:
        nil
    tableView.observeTableStateWindow(currentWindow)
    if not currentWindow.isNil:
      tableView.restoreStateIfNeeded()

proc installTableStateProtocols*(tableView: TableView) =
  discard tableView.withProtocol(DefaultTableViewPersistenceBehavior)
  discard tableView.withProtocol(DefaultTableViewStateBehavior)
  discard tableView.withProtocol(TableViewStateViewLifecycleSlots)
  tableView.observeProtocol(tableView, TableViewStateViewLifecycleSlots)
