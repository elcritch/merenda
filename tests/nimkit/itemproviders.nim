import std/[algorithm, options, unittest]
import merenda/nimkit
import merenda/nimkit/foundation/itemproviders
import merenda/nimkit/foundation/backrefs

type ContextProvider = ref object of DynamicAgent
  lastContext: pointer
  items: seq[ModelItem]
  reads: int
  indexReads: int

type SelectionOrderSpy = ref object of Agent
  events: seq[string]

proc recordSelection(spy: SelectionOrderSpy, sender: DynamicAgent, stage: string) =
  let indexes =
    if sender of TableView:
      TableView(sender).selectedIndexes()
    else:
      CollectionView(sender).selectedIndexes()
  spy.events.add stage & ":" & $indexes

proc changing(spy: SelectionOrderSpy, sender: DynamicAgent) {.slot.} =
  spy.recordSelection(sender, "will")

proc changed(spy: SelectionOrderSpy, sender: DynamicAgent) {.slot.} =
  spy.recordSelection(sender, "did")

protocol ContextProviderMethods of ItemProviderProtocol:
  method numberOfProvidedItems(source: ContextProvider, context: DynamicAgent): int =
    source.lastContext = cast[pointer](context)
    source.items.len

  method providedItemAtIndex(
      source: ContextProvider, context: DynamicAgent, index: int
  ): ModelItem =
    source.lastContext = cast[pointer](context)
    inc source.reads
    source.items[index]

  method setProvidedItemValue(
      source: ContextProvider,
      context: DynamicAgent,
      index: int,
      key: string,
      value: ObjectValue,
  ): bool =
    source.lastContext = cast[pointer](context)
    source.items[index].setValue(key, value)
    true

protocol IncompleteProviderMethods of ItemProviderProtocol:
  method numberOfProvidedItems(source: DynamicAgent, context: DynamicAgent): int =
    2

protocol IndexedProviderMethods of ItemProviderProtocol:
  method providedItemIndexForIdentifier(
      source: ContextProvider, context: DynamicAgent, identifier: string
  ): int =
    inc source.indexReads
    for index, item in source.items:
      if item.identifier == identifier:
        return index
    -1

protocol CustomMenuProjection of MenuDataSource:
  method menuItemModelAtIndex(
      source: ContextProvider, menu: Menu, index: int
  ): MenuItemModel =
    initMenuItemModel(
      identifier = source.items[index].identifier,
      title = "Custom menu",
      validates = false,
    )

proc newContextProvider(): ContextProvider =
  result = ContextProvider(
    items:
      @[
        modelItem(
          "a",
          title = "Alpha",
          objectValue = toObj("Alpha"),
          fields = [modelField("score", toObj(7))],
        ),
        modelItem("b", title = "Beta", objectValue = toObj("Beta")),
      ]
  )
  discard result.withProtocol(ContextProviderMethods)

suite "nimkit item providers":
  test "one provider supplies all six presenters with the requesting view context":
    let
      source = newContextProvider()
      menu = newMenu()
      tabs = newDocumentTabs()
      matrix = newButtonMatrix([], columns = 1)
      combo = newComboBox()
      table = newTableView()
      collection = newCollectionView()
      score = newTableColumn("score")
    menu.dataSource = source
    check menu[0.Natural].title == "Alpha"
    check source.lastContext == cast[pointer](menu)
    check menu.indexOfMenuItemIdentifier("b") == 1
    tabs.dataSource = source
    check tabs[1.Natural].title == "Beta"
    check source.lastContext == cast[pointer](tabs)
    matrix.dataSource = source
    check matrix.matrixItemAtIndex(0).identifier == "a"
    check source.lastContext == cast[pointer](matrix)
    combo.dataSource = source
    check combo.itemAtIndex(1) == "Beta"
    check source.lastContext == cast[pointer](combo)
    check combo.indexOfOptionIdentifier("b") == 1
    table.addColumn(score)
    table.dataSource = source
    check table.rowCount == 2
    check table.tableCellObjectValue(0, score).requireInt() == 7
    check source.lastContext == cast[pointer](table)
    check table.dataSource
    .trySendLocal(
      setObjectValueForCell(),
      (tableView: table, row: 0, column: score, value: toObj(9)),
    )
    .get()
    check source.items[0].value("score").requireInt() == 9
    collection.dataSource = source
    check collection.collectionItemIdentifier(1) == "b"
    check collection.collectionItemText(0) == "Alpha"
    check source.lastContext == cast[pointer](collection)
    check collection.collectionItemIndexForIdentifier("b") == 1

  test "legacy projection overrides survive bridge installation and rebinding":
    let source = newContextProvider()
    discard source.withProtocol(CustomMenuProjection)
    let menu = newMenu()
    menu.dataSource = source
    check menu.len == 2
    check menu[0.Natural].title == "Custom menu"
    menu.dataSource = DynamicAgent(nil)
    menu.dataSource = source
    check menu[1.Natural].title == "Custom menu"

  test "neutral providers preserve lazy combo queries":
    let source = newContextProvider()
    for index in 2 ..< 10_000:
      source.items.add modelItem($index, objectValue = toObj($index))
    let combo = newComboBox()
    combo.dataSource = source
    source.reads = 0
    for index in 0 ..< 100:
      check combo.numberOfItems == 10_000
    check source.reads == 0
    check combo.itemAtIndex(9999) == "9999"
    check source.reads == 1

  test "snapshot reloads retain menu tab and submenu identities and detach retired items":
    let
      menu = newMenu()
      tabs = newDocumentTabs()
    menu.itemModels = [
      initMenuItemModel("a", "Alpha", children = [initMenuItemModel("child", "Child")]),
      initMenuItemModel("b", "Beta"),
    ]
    tabs.documentTabModels =
      [initDocumentTabModel("a", "Alpha"), initDocumentTabModel("b", "Beta")]
    let
      alpha = menu.menuItemWithIdentifier("a")
      beta = menu.menuItemWithIdentifier("b")
      submenu = alpha.submenu()
      child = submenu.menuItemWithIdentifier("child")
      tab = tabs.documentTabItemWithIdentifier("a")
    check tabs.selectDocumentTabWithIdentifier("a")
    menu.itemModels = [
      initMenuItemModel("b", "Updated beta"),
      initMenuItemModel(
        "a", "Updated alpha", children = [initMenuItemModel("child", "Updated child")]
      ),
    ]
    tabs.documentTabModels = [
      initDocumentTabModel("b", "Updated beta"),
      initDocumentTabModel("a", "Updated alpha", modified = true),
    ]
    check menu[0.Natural] == beta
    check menu[1.Natural] == alpha
    check alpha.title == "Updated alpha"
    check alpha.submenu() == submenu
    check submenu.menuItemWithIdentifier("child") == child
    check child.title == "Updated child"
    check tabs.documentTabItemWithIdentifier("a") == tab
    check tab.modified
    check tabs.selectedDocumentTabIdentifier == "a"
    menu.itemModels = [initMenuItemModel("a", "Alpha", hidden = true)]
    check menu.len == 0
    check alpha.nextResponder().isNil
    check beta.nextResponder().isNil

  test "matrix provider reloads preserve cells by identity across sorting and removal":
    let controller = newArrayController(
      [modelItem("a", title = "Alpha"), modelItem("b", title = "Beta")]
    )
    let matrix = newRadioMatrix([], columns = 1)
    matrix.bindMatrix(controller)
    let alpha = matrix.cellAtIndex(0)
    let beta = matrix.cellAtIndex(1)
    check matrix.selectCellAtIndex(0)
    controller.sortDescriptors = [initModelSortDescriptor("", msdDescending)]
    controller.setValue("a", "", toObj("Alpha"))
    controller.setValue("b", "", toObj("Beta"))
    matrix.reloadData()
    check matrix.cellAtIndex(0) == beta
    check matrix.cellAtIndex(1) == alpha
    check matrix.selectedItemIdentifier == "a"
    check controller.removeItem("a")
    matrix.reloadData()
    check matrix.cellAtIndex(0) == beta
    check alpha.controlView().isNil

  test "selection signals observe previous then committed state in both presenters":
    let
      provider = newContextProvider()
      table = newTableView()
      collection = newCollectionView()
      spy = SelectionOrderSpy()
    table.dataSource = provider
    collection.dataSource = provider
    table.selectedIndexes = [0]
    collection.selectedIndexes = [0]
    table.connect(selectionIsChanging, spy, changing)
    table.connect(selectionDidChange, spy, changed)
    collection.connect(collectionSelectionIsChanging, spy, changing)
    collection.connect(collectionSelectionDidChange, spy, changed)
    table.selectedIndexes = [1]
    collection.selectedIndexes = [1]
    check spy.events == @["will:@[0]", "did:@[1]", "will:@[0]", "did:@[1]"]
    table.selectedIndexes = [1]
    collection.selectedIndexes = [1]
    check spy.events.len == 4

  test "removing a submenu exports an empty children snapshot":
    let item = newMenuItem(
      initMenuItemModel(
        "parent", "Parent", children = [initMenuItemModel("child", "Child")]
      )
    )
    let submenu = item.submenu()
    require not submenu.isNil
    item.submenu = nil
    let snapshot = item.menuItemModel()
    check snapshot.children.len == 0
    check newMenuItem(snapshot).submenu().isNil

  test "downstream legacy selectors do not suppress local provider bridges":
    let source = newContextProvider()
    let downstream = newContextProvider()
    discard downstream.withProtocol(CustomMenuProjection)
    let downstreamMenu = newMenu()
    downstreamMenu.dataSource = downstream
    source.setNextResponder(downstream)
    let menu = newMenu()
    menu.dataSource = source
    check menu.len == 2
    check menu[0.Natural].title == "Alpha"
    check menu.indexOfMenuItemIdentifier("b") == 1

  test "a next responder alone does not supply a local item provider":
    let downstream = newContextProvider()
    let source = DynamicAgent()
    source.setNextResponder(downstream)
    let combo = newComboBox()
    combo.dataSource = source
    check combo.numberOfItems == 0

  test "collection selection looks up each input identity a bounded number of times":
    let source = newContextProvider()
    source.items.setLen(0)
    var identifiers: seq[string]
    for index in countdown(255, 0):
      source.items.add modelItem($index, objectValue = toObj($index))
      identifiers.add $index
    discard source.withProtocol(IndexedProviderMethods)
    let collection = newCollectionView(frame = rect(0, 0, 240, 120))
    collection.dataSource = source
    collection.selectionMode = csmExtended
    identifiers.reverse()
    source.indexReads = 0
    collection.selectedIdentifiers = identifiers
    check collection.selectedIdentifiers.len == 256
    check collection.selectedIdentifiers[0] == "255"
    check source.indexReads <= identifiers.len * 3 + 32

  test "large table selections sort deduplicate and reject invalid indexes":
    let table = newTableView()
    table.rowCount = 10_000
    table.selectionMode = tsmExtended
    var indexes: seq[int]
    for index in countdown(9999, 0):
      indexes.add index
      indexes.add index
    table.selectedIndexes = indexes
    check table.selectedIndexes.len == 10_000
    check table.selectedRanges == @[0 .. 9999]
    table.selectedIndexes = [-1, 10_000, 5, 5]
    check table.selectedIndexes == @[5]

  test "standalone menu items release removed child payloads":
    for removeSubmenu in [true, false]:
      var payload: BackRef[View]
      var item: MenuItem
      block:
        let target = newView()
        payload.target = target
        item = newMenuItem(
          initMenuItemModel(
            "parent",
            "Parent",
            children = [
              initMenuItemModel(
                "child",
                "Child",
                target = DynamicAgent(target),
                userInfo = DynamicAgent(target),
              )
            ],
          )
        )
      require not payload.isNil
      if removeSubmenu:
        item.submenu = nil
      else:
        item.submenu().removeAllItems()
      check payload.isNil
      check item.menuItemModel().children.len == 0

  test "a local provider cannot borrow its required record method from a responder":
    let downstream = newContextProvider()
    let source = DynamicAgent()
    source.setNextResponder(downstream)
    discard source.withProtocol(IncompleteProviderMethods)
    let combo = newComboBox()
    expect ProtocolConformanceError:
      combo.dataSource = source
    check combo.dataSource.isNil
