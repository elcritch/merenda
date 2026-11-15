import std/unittest
import merenda/nimkit
import merenda/nimkit/directviews
import ../../examples/direct_collection_demo

suite "editable virtual collection demo":
  test "editing survives selection, scrolling, insertion and reorder until deletion":
    for cache in [false, true]:
      let demo = newDirectCollectionDemo(5000, cache)
      let controller = ArrayController(demo.view.dataSource())
      let window = newWindow("Virtual collection", frame = rect(0, 0, 640, 480))
      window.setContentView(demo.view)
      discard window.buildRenders()
      let row = DirectView(demo.view.itemViewAtIndex(0))
      require not row.isNil
      let stack = StackView(row.arrangedSubviews[0])
      let field = TextField(stack.arrangedSubviews[1])
      when defined(merendaIntrinsicCache):
        check field[vpCacheIntrinsicSize] == cache
      require window.makeFirstResponder(field)
      let editor = TextView(field.currentEditor)
      editor.selectedRange = initTextRange(1, 2)
      editor.setMarkedTextValue("xy", initTextRange(1, 0), initTextRange(-1, 0))
      let text = editor.stringValue
      let selection = editor.selectedRange
      demo.view.selectItemAtIndex(1)
      demo.view.scrollView.contentOffset = initPoint(0, 1500)
      discard window.buildRenders()
      check field.currentEditor == editor
      check editor.stringValue == text
      check editor.selectedRange == selection
      check demo.view.visibleItemViews.len <= demo.view.visibleItemIndexes.len + 1
      controller.insertItem(
        modelItem("new", fields = [modelField("title", toObj("New"))]), 0
      )
      demo.rows.flushBindings()
      check controller.moveItem("0", 2)
      demo.rows.flushBindings()
      check demo.view.itemViewAtIndex(2) == row
      check field.currentEditor == editor
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
