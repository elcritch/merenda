include "../../examples/direct_views_demo.nim"
include ./taskdemochecks
taskDemoChecks("direct MVC demo", newTaskController)

when defined(merendaIntrinsicCache):
  suite "direct demo measurement reuse":
    test "existing and inserted controls opt in and invalidate on edit":
      let controller = newTaskController()
      let field = TextField(controller.findDemoView("title-1"))
      check field[vpCacheIntrinsicSize]
      check controller.findDemoView("remove-1")[vpCacheIntrinsicSize]
      discard field.resolvedIntrinsicContentSize()
      controller.editTitle(1, "A considerably longer task title for measurement")
      discard drainMainThreadWork()
      let after = field.resolvedIntrinsicContentSize()
      check field.stringValue == "A considerably longer task title for measurement"
      field[vpCacheIntrinsicSize] = false
      check after == field.resolvedIntrinsicContentSize()
      controller.insertTask()
      discard drainMainThreadWork()
      let inserted = TextField(controller.findDemoView("title-4"))
      require not inserted.isNil
      check inserted[vpCacheIntrinsicSize]
      check controller.findDemoView("remove-4")[vpCacheIntrinsicSize]
      controller.setView(nil)
