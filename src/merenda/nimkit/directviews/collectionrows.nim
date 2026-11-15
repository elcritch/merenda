## Experimental CollectionView adapter for DirectView rows.
## Row builders must use the model identifier as their durable edit context.
import sigils/[core, selectors]
import ../accessibility/accessibilityprotocols
import ../app/[modelcontrollers, windows]
import ../containers/collectionviews
import ../foundation/selectors
import ../foundation/sourcedispatch
when defined(merendaRowLayoutBoundaries):
  import ../view/viewbase
import ../text/fieldeditors
import ./[bindings, runtime]

type
  CollectionRowBuilder* =
    proc(row: DirectView, controller: ArrayController, identifier: string) {.closure.}

  CollectionRows* = ref object of Responder
    controller: ArrayController
    collection: BackRef[CollectionView]
    scope: BindingScope
    build: CollectionRowBuilder
    closed: bool

proc activeEditor(view: View): FieldEditor =
  let owner = view.window()
  if owner of Window:
    let responder = Window(owner).firstResponder()
    if responder of FieldEditor:
      let editor = FieldEditor(responder)
      let client = editor.client()
      if client of View and view.containsView(View(client)):
        result = editor

proc modelChanged(controller: ArrayController, context: int): bool =
  discard controller
  discard context
  true

proc retireMissingRows(rows: CollectionRows, sender: DynamicAgent) {.slot.} =
  discard sender
  let collection = rows.collection{}
  if not rows.closed and not collection.isNil and
      collection.delegate() == DynamicAgent(rows):
    collection.retireMissingCollectionItems()

proc refreshRows(rows: CollectionRows, changed: bool) =
  let collection = rows.collection{}
  if changed and not rows.closed and not collection.isNil and
      collection.delegate() == DynamicAgent(rows):
    collection.reloadData()

proc readSelection(controller: SelectionController, context: int): seq[string] =
  discard context
  controller.selectedIdentifiers()

proc refreshSelection(rows: CollectionRows, identifiers: seq[string]) =
  let collection = rows.collection{}
  if not rows.closed and not collection.isNil and
      collection.delegate() == DynamicAgent(rows) and
      collection.selectedIdentifiers() != identifiers:
    collection.selectedIdentifiers = identifiers

protocol DirectCollectionRowsDelegate of CollectionViewDelegate:
  method viewForCollectionItem(
      rows: CollectionRows,
      collectionView: CollectionView,
      index: int,
      reuseIdentifier: string,
  ): View =
    discard rows
    discard index
    while true:
      result = collectionView.dequeueReusableItemView(reuseIdentifier)
      if result.isNil or result of DirectView:
        break
    if result.isNil:
      result = newDirectView()
    when defined(merendaRowLayoutBoundaries):
      result.xPrivProps.incl vipExperimentalRowLayoutBoundary

  method configureCollectionItemView(
      rows: CollectionRows,
      collectionView: CollectionView,
      index: int,
      identifier: string,
      objectValue: ObjectValue,
      view: View,
  ) =
    discard collectionView
    discard index
    discard objectValue
    if not rows.closed and view of DirectView:
      rows.build(DirectView(view), rows.controller, identifier)

  method retainCollectionItemView(
      rows: CollectionRows,
      collectionView: CollectionView,
      index: int,
      identifier: string,
      view: View,
  ): bool =
    discard rows
    discard collectionView
    discard index
    discard identifier
    not view.activeEditor().isNil

  method didEndDisplayingCollectionItemView(
      rows: CollectionRows,
      collectionView: CollectionView,
      index: int,
      identifier: string,
      view: View,
      reason: CollectionEndDisplayReason,
  ) =
    discard rows
    discard collectionView
    discard index
    discard identifier
    let editor = view.activeEditor()
    if view of DirectView:
      DirectView(view).retireEffects()
    if not editor.isNil and reason != cedViewport:
      discard editor.cancelEditing()
      let owner = view.window()
      if owner of Window and Window(owner).firstResponder() == editor:
        discard Window(owner).makeFirstResponder(nil)
    if view of DirectView:
      DirectView(view).clear()
      view.accessibilityLabel = ""

  method didSelectCollectionItem(
      rows: CollectionRows,
      collectionView: CollectionView,
      index: int,
      identifier: string,
  ) =
    discard index
    discard identifier
    if not rows.closed and not rows.controller.isNil:
      rows.controller.selectionController.setSelectedIdentifiers(
        collectionView.selectedIdentifiers()
      )

proc newCollectionRows*(
    collection: CollectionView, controller: ArrayController, build: CollectionRowBuilder
): CollectionRows =
  ## The collection owns the adapter as its delegate. Call close before replacing it.
  if collection.isNil or controller.isNil or build.isNil:
    raise
      newException(ValueError, "collection, controller and row builder are required")
  result =
    CollectionRows(controller: controller, scope: newBindingScope(), build: build)
  initResponder(result)
  result.collection.target = collection
  discard result.withProtocol(DirectCollectionRowsDelegate)
  collection.delegate = DynamicAgent(nil)
  collection.dataSource = controller
  collection.delegate = result
  collection.selectionMode =
    case controller.selectionController.mode
    of mselNone: csmNone
    of mselSingle: csmSingle
    of mselMultiple: csmMultiple
  collection.selectedIdentifiers = controller.selectionController.selectedIdentifiers
  controller.connect(arrayControllerDidChange, result, retireMissingRows)
  bindValue(
    result.scope,
    "model",
    controller,
    arrayControllerDidChange,
    controller,
    0,
    modelChanged,
    result,
    refreshRows,
    initialApply = false,
  )
  bindValue(
    result.scope,
    "selection",
    controller.selectionController,
    selectionControllerDidChange,
    controller.selectionController,
    0,
    readSelection,
    result,
    refreshSelection,
    initialApply = false,
  )

proc flushBindings*(rows: CollectionRows) =
  ## Flush coalesced model changes on the GUI thread.
  if not rows.isNil and not rows.closed:
    rows.scope.flushBindings()

proc close*(rows: CollectionRows) =
  ## Retire mounted rows and disconnect the model observation.
  if not rows.isNil and not rows.closed:
    rows.closed = true
    let controller = rows.controller
    if sourceDispatchActive(Agent(controller)):
      discard deferSourceWork(
        Agent(controller),
        proc() =
          controller.disconnect(arrayControllerDidChange, rows, retireMissingRows),
      )
    else:
      controller.disconnect(arrayControllerDidChange, rows, retireMissingRows)
    rows.scope.dispose()
    let collection = rows.collection{}
    if not collection.isNil and collection.delegate() == DynamicAgent(rows):
      collection.delegate = DynamicAgent(nil)
      if collection.dataSource() == DynamicAgent(controller):
        collection.dataSource = DynamicAgent(nil)
    rows.collection.clear()
    rows.build = nil
    rows.controller = nil
