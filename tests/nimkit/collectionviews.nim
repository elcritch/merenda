import std/[strutils, unittest]

import merenda/nimkit

type
  CollectionTestItem = object
    id: string
    title: string
    score: int

  CollectionSpy = ref object of Responder
    items: seq[CollectionTestItem]
    viewCalls: seq[string]
    configureCalls: seq[string]
    supplementaryCalls: seq[string]
    supplementaryReusedViews: int
    reusedViews: int
    selectedEvents: seq[string]
    activatedEvents: seq[string]
    dragRequests: seq[string]
    dropValidationCalls: seq[string]
    dropAcceptCalls: seq[string]

  CollectionSignalSpy = ref object of Agent
    selectionChanging: int
    selectionChanged: int
    updateKinds: seq[CollectionUpdateKind]

func center(rect: Rect): Point =
  initPoint(
    rect.origin.x + rect.size.width / 2.0'f32,
    rect.origin.y + rect.size.height / 2.0'f32,
  )

proc clickCollectionItem(
    window: Window,
    collectionView: CollectionView,
    index: int,
    modifiers: set[KeyModifier] = {},
): bool =
  let rect = collectionView.collectionItemRect(index)
  if rect.isEmpty:
    return false
  let point = collectionView.pointToWindow(rect.center())
  window.mouseDownAt(point, modifiers = modifiers) and
    window.mouseUpAt(point, modifiers = modifiers)

proc rememberCollectionSelectionIsChanging(
    spy: CollectionSignalSpy, sender: DynamicAgent
) {.slot.} =
  discard sender
  inc spy.selectionChanging

proc rememberCollectionSelectionDidChange(
    spy: CollectionSignalSpy, sender: DynamicAgent
) {.slot.} =
  discard sender
  inc spy.selectionChanged

proc rememberCollectionItemsDidUpdate(
    spy: CollectionSignalSpy, sender: DynamicAgent, updates: seq[CollectionUpdate]
) {.slot.} =
  discard sender
  for update in updates:
    spy.updateKinds.add update.kind

protocol CollectionSpyDataSource of CollectionViewDataSource:
  method numberOfCollectionItems(
      spy: CollectionSpy, collectionView: CollectionView
  ): int =
    discard collectionView
    spy.items.len

  method identifierForCollectionItem(
      spy: CollectionSpy, collectionView: CollectionView, index: int
  ): string =
    discard collectionView
    if index in 0 ..< spy.items.len:
      spy.items[index].id
    else:
      ""

  method indexForCollectionItemIdentifier(
      spy: CollectionSpy, collectionView: CollectionView, identifier: string
  ): int =
    discard collectionView
    for index, item in spy.items:
      if item.id == identifier:
        return index
    -1

  method objectValueForCollectionItem(
      spy: CollectionSpy, collectionView: CollectionView, index: int
  ): ObjectValue =
    discard collectionView
    if index in 0 ..< spy.items.len:
      toObj(spy.items[index].title)
    else:
      emptyObjectValue()

  method textForCollectionItem(
      spy: CollectionSpy, collectionView: CollectionView, index: int
  ): string =
    discard collectionView
    if index in 0 ..< spy.items.len:
      spy.items[index].title
    else:
      ""

protocol CollectionSpyDelegate of CollectionViewDelegate:
  method reuseIdentifierForCollectionItem(
      spy: CollectionSpy, collectionView: CollectionView, index: int
  ): string =
    discard spy
    discard collectionView
    discard index
    "tile"

  method viewForCollectionItem(
      spy: CollectionSpy,
      collectionView: CollectionView,
      index: int,
      reuseIdentifier: string,
  ): View =
    spy.viewCalls.add $index & ":" & reuseIdentifier
    result = collectionView.dequeueReusableItemView(reuseIdentifier)
    if not result.isNil:
      inc spy.reusedViews
    else:
      result = View(newCollectionItemView(reuseIdentifier))

  method configureCollectionItemView(
      spy: CollectionSpy,
      collectionView: CollectionView,
      index: int,
      identifier: string,
      objectValue: ObjectValue,
      view: View,
  ) =
    discard collectionView
    discard view
    spy.configureCalls.add $index & ":" & identifier & ":" & objectValue.requireString()

  method supplementaryViewForCollectionElement(
      spy: CollectionSpy,
      collectionView: CollectionView,
      kind: CollectionSupplementaryKind,
      identifier: string,
      reuseIdentifier: string,
  ): View =
    spy.supplementaryCalls.add $kind & ":" & identifier & ":" & reuseIdentifier
    result = collectionView.dequeueReusableSupplementaryView(kind, reuseIdentifier)
    if not result.isNil:
      inc spy.supplementaryReusedViews
    else:
      result = View(newCollectionSupplementaryView(kind, reuseIdentifier, identifier))

  method didSelectCollectionItem(
      spy: CollectionSpy, collectionView: CollectionView, index: int, identifier: string
  ) =
    discard index
    discard identifier
    spy.selectedEvents.add collectionView.selectedIdentifiers().join(",")

  method didActivateCollectionItem(
      spy: CollectionSpy, collectionView: CollectionView, index: int, identifier: string
  ) =
    discard collectionView
    discard index
    spy.activatedEvents.add identifier

  method draggingItemsForCollectionItems(
      spy: CollectionSpy,
      collectionView: CollectionView,
      identifiers: seq[string],
      pasteboardName: string,
  ): seq[DraggingItem] =
    discard collectionView
    spy.dragRequests.add pasteboardName & ":" & identifiers.join(",")
    @[
      initDraggingItem(
        CollectionPasteboardTypeItems, initPasteboardStringItem(identifiers.join("|"))
      )
    ]

  method validateCollectionDropOperation(
      spy: CollectionSpy,
      collectionView: CollectionView,
      info: DraggingInfo,
      proposedOperation: DragOperations,
      target: DraggingDropTarget,
      position: DraggingDropPosition,
  ): DragOperations =
    discard collectionView
    discard info
    spy.dropValidationCalls.add target.itemIdentifier & ":" & $position
    if proposedOperation == NoDragOperations:
      {dgoCopy}
    else:
      proposedOperation

  method acceptCollectionDropOperation(
      spy: CollectionSpy,
      collectionView: CollectionView,
      info: DraggingInfo,
      operation: DragOperations,
      target: DraggingDropTarget,
      position: DraggingDropPosition,
  ): bool =
    discard collectionView
    discard info
    spy.dropAcceptCalls.add $operation & ":" & target.itemIdentifier & ":" & $position
    true

proc newCollectionSpy(items: openArray[CollectionTestItem]): CollectionSpy =
  result = CollectionSpy(items: @items)
  initResponder(result)
  discard result.withProtocol(CollectionSpyDataSource)
  discard result.withProtocol(CollectionSpyDelegate)

func item(id, title: string, score: int): CollectionTestItem =
  CollectionTestItem(id: id, title: title, score: score)

proc modelItems(): seq[ModelItem] =
  @[
    initModelItem(
      "ada", objectValue = toObj("Ada"), fields = [initModelField("score", toObj(31))]
    ),
    initModelItem(
      "grace",
      objectValue = toObj("Grace"),
      fields = [initModelField("score", toObj(45))],
    ),
    initModelItem(
      "alan", objectValue = toObj("Alan"), fields = [initModelField("score", toObj(27))]
    ),
  ]

suite "nimkit collection views":
  test "collection view lays out model items and reuses item views":
    let
      collectionView = newCollectionView(frame = rect(0, 0, 260, 140))
      layout = newCollectionViewLayout(
        clkGrid,
        itemSize = initSize(60.0, 40.0),
        minimumInteritemSpacing = 5.0,
        minimumLineSpacing = 6.0,
        edgeInsets = insets(10.0),
        columnCount = 3,
      )
      source = newCollectionSpy(
        [
          item("a", "Alpha", 1),
          item("b", "Beta", 2),
          item("c", "Gamma", 3),
          item("d", "Delta", 4),
          item("e", "Epsilon", 5),
        ]
      )

    collectionView.collectionLayout = layout
    collectionView.dataSource = source
    collectionView.delegate = source
    discard buildRenders(collectionView)

    check collectionView.len == 5
    check collectionView.collectionItemRect(0) == rect(10.0, 10.0, 60.0, 40.0)
    check collectionView.collectionItemRect(4) == rect(75.0, 56.0, 60.0, 40.0)
    check collectionView.collectionItemIndexAtPoint(initPoint(20.0, 20.0)) == 0
    check collectionView.collectionItemText(2) == "Gamma"
    check collectionView.visibleItemViews().len == 5

    let firstView = CollectionItemView(collectionView.itemViewAtIndex(0))
    check firstView.text == "Alpha"
    check firstView.accessibilityLabel() == "Alpha"
    check atSelectable in firstView.accessibilityTraits()

    let header = collectionView.supplementaryView(cskHeader, "main", "header")
    check not header.isNil
    check source.supplementaryCalls == @["cskHeader:main:header"]
    check CollectionSupplementaryView(header).kind == cskHeader
    check CollectionSupplementaryView(header).reuseIdentifier == "header"
    check CollectionSupplementaryView(header).elementIdentifier == "main"
    check CollectionSupplementaryView(header).collectionView == collectionView
    check collectionView.supplementaryView(cskHeader, "main", "header") == header

    source.items.delete(0)
    collectionView.reloadData()
    discard buildRenders(collectionView)

    check collectionView.len == 4
    check source.reusedViews > 0
    check CollectionItemView(collectionView.itemViewAtIndex(0)).itemIdentifier == "b"

    let reusedHeader = collectionView.supplementaryView(cskHeader, "main", "header")
    check reusedHeader == header
    check source.supplementaryReusedViews == 1

  test "collection selection activation and keyboard navigation use user events":
    let
      window = newWindow("Collection selection", frame = rect(0, 0, 320, 180))
      root = newView(frame = rect(0, 0, 320, 180))
      collectionView = newCollectionView(frame = rect(10, 10, 280, 120))
      layout = newCollectionViewLayout(
        clkGrid,
        itemSize = initSize(70.0, 36.0),
        minimumInteritemSpacing = 6.0,
        minimumLineSpacing = 6.0,
        edgeInsets = insets(8.0),
        columnCount = 3,
      )
      source = newCollectionSpy(
        [
          item("a", "Alpha", 1),
          item("b", "Beta", 2),
          item("c", "Gamma", 3),
          item("d", "Delta", 4),
        ]
      )
      signals = CollectionSignalSpy()

    collectionView.collectionLayout = layout
    collectionView.dataSource = source
    collectionView.delegate = source
    collectionView.selectionMode = csmExtended
    collectionView.connect(
      collectionSelectionIsChanging, signals, rememberCollectionSelectionIsChanging
    )
    collectionView.connect(
      collectionSelectionDidChange, signals, rememberCollectionSelectionDidChange
    )
    root.addSubview(collectionView)
    window.setContentView(root)
    discard window.buildRenders()

    check window.clickCollectionItem(collectionView, 1)
    check window.firstResponder() == collectionView
    check collectionView.selectedIdentifiers == @["b"]
    check source.selectedEvents[^1] == "b"
    check source.activatedEvents[^1] == "b"

    check window.clickCollectionItem(collectionView, 3, {kmCommand})
    check collectionView.selectedIdentifiers == @["b", "d"]
    check signals.selectionChanging == 2
    check signals.selectionChanged == 2

    check window.dispatchKeyDown(KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord))
    check collectionView.selectedIdentifier == "c"

    check window.dispatchKeyDown(KeyEvent(key: keySpace, keyCode: keySpace.ord))
    check source.activatedEvents[^1] == "c"

  test "array controller binds collection item values and preserves selected identities":
    let
      controller = newArrayController(modelItems())
      collectionView = newCollectionView(frame = rect(0, 0, 260, 120))

    bindCollectionView(collectionView, controller)
    discard buildRenders(collectionView)

    check collectionView.len == 3
    check collectionView.collectionItemText(0) == "Ada"
    check collectionView.collectionItemIdentifier(1) == "grace"

    collectionView.selectedIndex = 0
    check controller.selectionController().selectedIdentifier == "ada"

    controller.sortDescriptors = [initModelSortDescriptor("score", msdDescending)]
    collectionView.reloadData()

    check collectionView.collectionItemIdentifier(0) == "grace"
    check collectionView.collectionItemIdentifier(1) == "ada"
    check collectionView.selectedIdentifier == "ada"
    check collectionView.selectedIndex == 1

  test "collection updates and drag drop expose model-aware item targets":
    let
      collectionView = newCollectionView(frame = rect(0, 0, 260, 120))
      layout = newCollectionViewLayout(
        clkWrapped,
        itemSize = initSize(72.0, 36.0),
        minimumInteritemSpacing = 6.0,
        minimumLineSpacing = 6.0,
        edgeInsets = insets(8.0),
      )
      source = newCollectionSpy(
        [item("a", "Alpha", 1), item("b", "Beta", 2), item("c", "Gamma", 3)]
      )
      signals = CollectionSignalSpy()

    collectionView.collectionLayout = layout
    collectionView.dataSource = source
    collectionView.delegate = source
    collectionView.selectionMode = csmMultiple
    collectionView.registerForDraggedTypes([CollectionPasteboardTypeItems])
    collectionView.connect(
      collectionItemsDidUpdate, signals, rememberCollectionItemsDidUpdate
    )
    discard buildRenders(collectionView)

    collectionView.selectedIndexes = [0, 2]
    let drag = collectionView.beginDraggingSelection({dgoCopy})
    check not drag.isNil
    check source.dragRequests == @[DragPasteboardName & ":a,c"]
    check drag.pasteboard().stringForType(CollectionPasteboardTypeItems) == "a|c"

    let
      targetPoint = collectionView.collectionItemRect(1).center()
      target = collectionView.dropTargetForDraggingLocation(targetPoint)
      info = drag.draggingInfo(targetPoint, DynamicAgent(collectionView)).withDropTarget(
          target
        )

    check target.kind == ddtItem
    check target.itemIdentifier == "b"
    check collectionView.validateDragging(info) == {dgoCopy}
    check collectionView.acceptDragging(info)
    check source.dropValidationCalls.len >= 1
    check source.dropAcceptCalls[^1].contains("b")

    source.items.add item("d", "Delta", 4)
    collectionView.insertItemsAtIndexes([3], ["d"])
    collectionView.reloadItemsAtIndexes([1], ["b"])
    collectionView.moveItem(3, 1)
    collectionView.removeItemsAtIndexes([0], ["a"])

    check signals.updateKinds == @[cukInsert, cukReload, cukMove, cukRemove]
