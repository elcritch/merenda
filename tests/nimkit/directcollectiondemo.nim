import std/[strutils, unittest]
import sigils/core
import merenda/nimkit
import merenda/nimkit/app/backend
import merenda/nimkit/directviews
import ../../examples/direct_collection_demo
import ../intrinsic_collection_fixture

type ClosingObserver = ref object of Responder
  rows: CollectionRows
  calls: int

type RebindingObserver = ref object of Responder
  scope: BindingScope
  first, second: ArrayController
  field: TextField

proc readBoundTitle(controller: ArrayController, id: string): string =
  controller.valueForItem(id, "title").requireString()

proc applyBoundTitle(field: TextField, value: string) =
  field.stringValue = value

proc rebindRows(observer: RebindingObserver, sender: DynamicAgent) {.slot.} =
  for controller in [observer.second, observer.first]:
    observer.scope.bindValue(
      "title", controller, arrayControllerDidChange, controller, "0", readBoundTitle,
      observer.field, applyBoundTitle,
    )

proc closeRows(observer: ClosingObserver, sender: DynamicAgent) {.slot.} =
  inc observer.calls
  observer.rows.close()
  observer.rows.close()

suite "editable virtual collection demo":
  test "native composition ranges preserve Unicode and committed text":
    let demo = newDirectCollectionDemo(30)
    let window = newWindow("Composition", frame = rect(0, 0, 640, 480))
    window.setContentView(demo.view)
    discard window.buildRenders()
    let row = DirectView(demo.view.itemViewAtIndex(0))
    require not row.isNil
    let field = TextField(StackView(row.arrangedSubviews[0]).arrangedSubviews[1])
    require window.makeFirstResponder(field)
    let editor = TextView(field.currentEditor)
    editor.selectAllText()
    check window.dispatchTextComposition(
      HostTextComposition(text: "😀かな", selectedStart: 2, replacementStart: -1)
    )
    check editor.markedRange == initTextRange(0, 3)
    check editor.selectedRange == initTextRange(1, 0)
    check window.dispatchTextInput("漢字")
    check editor.stringValue == "漢字"
    check not editor.hasMarkedText
    check window.dispatchTextComposition(
      HostTextComposition(text: "かな", selectedStart: 2, replacementStart: -1)
    )
    check editor.hasMarkedText
    check window.dispatchTextUnmark()
    check not editor.hasMarkedText
    demo.rows.close()
    window.close()

  test "rebinding away and back during a signal leaves the new subscription live":
    let first = newArrayController(
      @[modelItem("0", fields = [modelField("title", toObj("First"))])]
    )
    let second = newArrayController(
      @[modelItem("0", fields = [modelField("title", toObj("Second"))])]
    )
    let observer = RebindingObserver(
      scope: newBindingScope(), first: first, second: second, field: newTextField()
    )
    initResponder(observer)
    first.connect(arrayControllerDidChange, observer, rebindRows)
    observer.scope.bindValue(
      "title", first, arrayControllerDidChange, first, "0", readBoundTitle,
      observer.field, applyBoundTitle,
    )
    first.setValue("0", "title", toObj("Changed"))
    first.disconnect(arrayControllerDidChange, observer, rebindRows)
    check first.subcriptions.len == 1
    check second.subcriptions.len == 0
    first.setValue("0", "title", toObj("Still connected"))
    observer.scope.flushBindings()
    check observer.field.stringValue == "Still connected"
    observer.scope.dispose()
    check first.subcriptions.len == 0

  test "teardown is safe during model and selection signals":
    for selection in [false, true]:
      let demo = newDirectCollectionDemo(30)
      let controller = ArrayController(demo.view.dataSource())
      let window = newWindow("Teardown", frame = rect(0, 0, 640, 480))
      window.setContentView(demo.view)
      discard window.buildRenders()
      let row = DirectView(demo.view.itemViewAtIndex(0))
      require not row.isNil
      let field = TextField(StackView(row.arrangedSubviews[0]).arrangedSubviews[1])
      require window.makeFirstResponder(field)
      let observer = ClosingObserver(rows: demo.rows)
      initResponder(observer)
      if selection:
        let source = controller.selectionController
        source.connect(selectionControllerDidChange, observer, closeRows)
        source.setSelectedIdentifiers(["0"])
        source.disconnect(selectionControllerDidChange, observer, closeRows)
      else:
        controller.connect(arrayControllerDidChange, observer, closeRows)
        controller.setValue("0", "title", toObj("Changed"))
        controller.disconnect(arrayControllerDidChange, observer, closeRows)
      check observer.calls == 1
      check demo.view.dataSource().isNil
      check demo.view.delegate().isNil
      check controller.subcriptions.len == 0
      check controller.selectionController.subcriptions.len == 0
      check field.currentEditor.isNil
      window.close()

  test "editing survives selection, scrolling, insertion and reorder until deletion":
    for cache in [false, true]:
      let demo = newIntrinsicCollectionFixture(5000, cache)
      let controller = ArrayController(demo.view.dataSource())
      let window = newWindow("Virtual collection", frame = rect(0, 0, 640, 480))
      window.setContentView(demo.view)
      discard window.buildRenders()
      let row = DirectView(demo.view.itemViewAtIndex(0))
      require not row.isNil
      let stack = StackView(row.arrangedSubviews[0])
      let field = TextField(stack.arrangedSubviews[1])
      check field{vpCacheIntrinsicSize} == cache
      require window.makeFirstResponder(field)
      let editor = TextView(field.currentEditor)
      editor.selectedRange = initTextRange(1, 2)
      check window.dispatchTextComposition(
        HostTextComposition(text: "かな", selectedStart: 1, replacementStart: -1)
      )
      require editor.hasMarkedText
      let text = editor.stringValue
      let selection = editor.selectedRange
      let marked = editor.markedRange
      demo.view.selectItemAtIndex(1)
      demo.view.scrollView.contentOffset = initPoint(0, 1500)
      discard window.buildRenders()
      check field.currentEditor == editor
      check editor.stringValue == text
      check editor.selectedRange == selection
      check editor.markedRange == marked
      check demo.view.visibleItemViews.len <=
        demo.view.materializationItemIndexes.len + 1
      controller.insertItem(
        modelItem("new", fields = [modelField("title", toObj("New"))]), 0
      )
      demo.rows.flushBindings()
      check controller.moveItem("0", 2)
      demo.rows.flushBindings()
      check demo.view.itemViewAtIndex(2) == row
      check field.currentEditor == editor
      check editor.hasMarkedText
      check editor.markedRange == marked
      check window.dispatchTextComposition(
        HostTextComposition(text: "漢字", selectedStart: 2, replacementStart: -1)
      )
      check editor.hasMarkedText
      check editor.stringValue.contains("漢字")
      let subscriptions = controller.subcriptions.len
      check controller.removeItem("0")
      check field.currentEditor.isNil
      check not row.containsView(field)
      check controller.subcriptions.len == subscriptions - 1
      controller.insertItem(
        modelItem("0", fields = [modelField("title", toObj("Replacement"))]), 0
      )
      demo.rows.flushBindings()
      controller.setValue("0", "title", toObj("Updated replacement"))
      demo.rows.flushBindings()
      check field.stringValue != "Updated replacement"
      demo.rows.close()
      window.close()
