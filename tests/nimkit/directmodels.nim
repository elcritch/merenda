import std/unittest
import merenda/nimkit
import merenda/nimkit/directviews/[bindings, modelbindings]

type EditorDelegate = ref object of Responder

protocol EditorCollectionDelegate of CollectionViewDelegate:
  method viewForCollectionItem(
      delegate: EditorDelegate,
      collectionView: CollectionView,
      index: int,
      reuseIdentifier: string,
  ): View =
    discard delegate
    discard collectionView
    discard reuseIdentifier
    View(newTextField("Item " & $index))

protocol EditorTableDelegate of TableViewDelegate:
  method viewForCell(
      delegate: EditorDelegate, tableView: TableView, row: int, column: TableColumn
  ): View =
    discard delegate
    discard tableView
    discard column
    View(newTextField("Item " & $row))

protocol EditorTableConfigure of TableViewDelegate:
  method configureCellView(
      delegate: EditorDelegate,
      tableView: TableView,
      row: int,
      column: TableColumn,
      objectValue: ObjectValue,
      view: View,
  ) =
    discard delegate
    discard tableView
    discard row
    discard column
    discard objectValue
    discard view

proc newEditorDelegate(): EditorDelegate =
  result = EditorDelegate()
  initResponder(result)
  discard result.withProtocol(EditorCollectionDelegate)
  discard result.withProtocol(EditorTableDelegate)
  discard result.withProtocol(EditorTableConfigure)

type
  LegacyCellDelegate = ref object of Responder
  ConfiguredCellDelegate = ref object of Responder

protocol LegacyCellViews of TableViewDelegate:
  method viewForCell(
      delegate: LegacyCellDelegate, tableView: TableView, row: int, column: TableColumn
  ): View =
    discard delegate
    View(newTextField(tableView.tableCellText(row, column)))

protocol ConfiguredCellViews of TableViewDelegate:
  method viewForCell(
      delegate: ConfiguredCellDelegate,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ): View =
    discard delegate
    View(newTextField(tableView.tableCellText(row, column)))

  method configureCellView(
      delegate: ConfiguredCellDelegate,
      tableView: TableView,
      row: int,
      column: TableColumn,
      objectValue: ObjectValue,
      view: View,
  ) =
    discard delegate
    discard tableView
    discard row
    discard column
    TextField(view).stringValue = objectValue.requireString()

suite "direct model bindings":
  test "collection refresh is queued, keyed, and disconnected on rebind and disposal":
    let
      scope = newBindingScope()
      first = newArrayController(
        @[
          ModelItem(identifier: "a", title: "A", enabled: true),
          ModelItem(identifier: "b", title: "B", enabled: true),
        ]
      )
      second =
        newArrayController(@[ModelItem(identifier: "x", title: "X", enabled: true)])
      view = newCollectionView(frame = rect(0, 0, 300, 150))
    var scheduled = 0
    scope.onSchedule(
      proc() =
        inc scheduled
    )
    scope.bindCollectionModel("items", view, first)
    discard buildRenders(view)
    let original = view.itemViewAtIndex(1)
    first.insertItem(ModelItem(identifier: "c", title: "C", enabled: true), 0)
    check scheduled == 1
    scope.flushBindings()
    check view.itemViewAtIndex(2) == original
    scope.bindCollectionModel("items", view, second)
    let previous = scheduled
    first.addItem(ModelItem(identifier: "d", title: "D", enabled: true))
    check scheduled == previous
    second.addItem(ModelItem(identifier: "y", title: "Y", enabled: true))
    check scheduled == previous + 1
    scope.dispose()
    scope.flushBindings()
    second.addItem(ModelItem(identifier: "z", title: "Z", enabled: true))
    check scheduled == previous + 1

  test "table selection follows the prior presentation after controller reorder":
    let
      scope = newBindingScope()
      controller = newArrayController(
        @[
          ModelItem(identifier: "a", title: "A", enabled: true),
          ModelItem(identifier: "b", title: "B", enabled: true),
          ModelItem(identifier: "c", title: "C", enabled: true),
        ]
      )
      view = newTableView(frame = rect(0, 0, 300, 150))
    view.addColumn(newTableColumn("title", "Title"))
    scope.bindTableModel("table", view, controller)
    discard buildRenders(view)
    view.selectedIndexes = [1]
    check controller.moveItem("b", 0)
    scope.flushBindings()
    check view.selectedIndexes == @[0]
    scope.dispose()

  test "collection retains an active editor across insertion and move":
    let
      scope = newBindingScope()
      controller = newArrayController(
        @[
          ModelItem(identifier: "a", title: "A", enabled: true),
          ModelItem(identifier: "b", title: "B", enabled: true),
          ModelItem(identifier: "c", title: "C", enabled: true),
        ]
      )
      delegate = newEditorDelegate()
      view = newCollectionView(frame = rect(0, 0, 400, 200))
      window = newWindow("Collection editor", frame = rect(0, 0, 400, 200))
    view.delegate = delegate
    scope.bindCollectionModel("items", view, controller)
    window.setContentView(view)
    defer:
      scope.dispose()
      window.close()
    view.layoutSubtreeIfNeeded()
    let field = TextField(view.itemViewAtIndex(1))
    require window.makeFirstResponder(field)
    let editor = field.currentEditor
    TextView(editor).insertTextValue("EDIT")
    field.selectedRange = initTextRange(1, 2)
    let edited = field.stringValue
    controller.insertItem(ModelItem(identifier: "d", title: "D", enabled: true), 0)
    scope.flushBindings()
    check controller.moveItem("b", 0)
    scope.flushBindings()
    check view.itemViewAtIndex(0) == field
    check field.currentEditor == editor
    check window.firstResponder == editor
    check window.fieldEditorClient == field
    check field.stringValue == edited
    check field.selectedRange == initTextRange(1, 2)

  test "table retains an active hosted editor across insertion and move":
    let
      scope = newBindingScope()
      controller = newArrayController(
        @[
          ModelItem(identifier: "a", title: "A", enabled: true),
          ModelItem(identifier: "b", title: "B", enabled: true),
          ModelItem(identifier: "c", title: "C", enabled: true),
        ]
      )
      delegate = newEditorDelegate()
      view = newTableView(frame = rect(0, 0, 400, 200))
      column = newTableColumn("title", "Title")
      window = newWindow("Table editor", frame = rect(0, 0, 400, 200))
    view.addColumn(column)
    view.delegate = delegate
    scope.bindTableModel("items", view, controller)
    window.setContentView(view)
    defer:
      scope.dispose()
      window.close()
    view.layoutSubtreeIfNeeded()
    let field = TextField(view.visibleCellView(1, column))
    require window.makeFirstResponder(field)
    let editor = field.currentEditor
    TextView(editor).insertTextValue("EDIT")
    field.selectedRange = initTextRange(1, 2)
    let edited = field.stringValue
    controller.insertItem(ModelItem(identifier: "d", title: "D", enabled: true), 0)
    scope.flushBindings()
    check controller.moveItem("b", 0)
    scope.flushBindings()
    check view.visibleCellView(0, column) == field
    check field.currentEditor == editor
    check window.firstResponder == editor
    check window.fieldEditorClient == field
    check field.stringValue == edited
    check field.selectedRange == initTextRange(1, 2)

  test "table refresh reconfigures opted-in cells and rebuilds legacy cells":
    let
      scope = newBindingScope()
      controller = newArrayController(
        @[
          ModelItem(
            identifier: "a", title: "Old", objectValue: toObj("Old"), enabled: true
          )
        ]
      )
      legacy = LegacyCellDelegate()
      configured = ConfiguredCellDelegate()
      legacyView = newTableView(frame = rect(0, 0, 300, 120))
      configuredView = newTableView(frame = rect(0, 0, 300, 120))
      legacyColumn = newTableColumn("title", "Title")
      configuredColumn = newTableColumn("title", "Title")
    initResponder(legacy)
    initResponder(configured)
    discard legacy.withProtocol(LegacyCellViews)
    discard configured.withProtocol(ConfiguredCellViews)
    legacyView.addColumn(legacyColumn)
    configuredView.addColumn(configuredColumn)
    legacyView.delegate = legacy
    configuredView.delegate = configured
    scope.bindTableModel("legacy", legacyView, controller)
    scope.bindTableModel("configured", configuredView, controller)
    discard buildRenders(legacyView)
    discard buildRenders(configuredView)
    let
      oldLegacy = TextField(legacyView.visibleCellView(0, legacyColumn))
      retained = TextField(configuredView.visibleCellView(0, configuredColumn))
    check oldLegacy.stringValue == "Old"
    check retained.stringValue == "Old"
    controller.setValue("a", "title", toObj("New"))
    scope.flushBindings()
    let newLegacy = TextField(legacyView.visibleCellView(0, legacyColumn))
    check newLegacy != oldLegacy
    check newLegacy.stringValue == "New"
    check configuredView.visibleCellView(0, configuredColumn) == retained
    check retained.stringValue == "New"
    scope.dispose()
