import std/unittest

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes

type SelectionSpyView = ref object of View
  consumesMouseDown: bool

var selectionEvents: seq[string]

protocol SelectionSpyEvents of ResponderEventProtocol:
  method mouseDown(view: SelectionSpyView, event: MouseEvent): bool =
    discard event
    selectionEvents.add("original:" & view.identifier)
    view.consumesMouseDown

proc newSelectionSpyView(
    identifier: string, frame: nimkitTypes.Rect, consumesMouseDown: bool
): SelectionSpyView =
  result = SelectionSpyView(consumesMouseDown: consumesMouseDown)
  initViewFields(result, frame)
  result.identifier = identifier
  discard result.withProtocol(SelectionSpyEvents)

suite "nimkit view selection":
  test "view selection wraps mouseDown after the original handler":
    let
      window = newWindow("Selection wrapper", frame = rect(0, 0, 120, 100))
      root = newView(frame = rect(0, 0, 120, 100))
      child = newSelectionSpyView("child", rect(10, 10, 60, 40), true)

    root.addSubview(child)
    window.setContentView(root)

    var selected: View
    var selection = installViewSelection(
      root,
      proc(view: View, event: MouseEvent) =
        discard event
        selectionEvents.add("select:" & view.identifier)
        selected = view,
    )

    check selection.installed
    check selection.root == root

    selectionEvents.setLen(0)
    check window.mouseDownAt(initPoint(15, 15), timestamp = 10.0)
    check selected == child
    check selectionEvents == @["original:child", "select:child"]

    check selection.uninstall()
    check not selection.installed
    selected = nil
    selectionEvents.setLen(0)
    check window.mouseDownAt(initPoint(15, 15), timestamp = 11.0)
    check selected.isNil
    check selectionEvents == @["original:child"]

  test "view selection consumes otherwise unhandled child clicks":
    let
      window = newWindow("Selection consumes", frame = rect(0, 0, 160, 120))
      root = newView(frame = rect(0, 0, 160, 120))
      parent = newSelectionSpyView("parent", rect(10, 10, 120, 80), true)
      child = newView("child", frame = rect(20, 15, 40, 30))

    parent.addSubview(child)
    root.addSubview(parent)
    window.setContentView(root)

    var selected: View
    var selection = installViewSelection(
      root,
      proc(view: View, event: MouseEvent) =
        discard event
        selectionEvents.add("select:" & view.identifier)
        selected = view,
    )

    selectionEvents.setLen(0)
    check window.mouseDownAt(initPoint(35, 30), timestamp = 20.0)
    check selected == child
    check selectionEvents == @["select:child"]

    check selection.uninstall()
    selectionEvents.setLen(0)
    selected = nil

    check window.mouseDownAt(initPoint(35, 30), timestamp = 21.0)
    check selected.isNil
    check selectionEvents == @["original:parent"]

  test "view selection follows subviews added and removed after install":
    let
      window = newWindow("Dynamic selection", frame = rect(0, 0, 180, 120))
      root = newView(frame = rect(0, 0, 180, 120))
      container = newView("container", frame = rect(10, 10, 120, 80))
      child = newView("child", frame = rect(20, 15, 40, 30))

    window.setContentView(root)

    var
      selected: View
      removed: View
    var selection = installViewSelection(
      root,
      proc(view: View, event: MouseEvent) =
        discard event
        selected = view,
      removalHandler = proc(view: View) =
        removed = view,
    )

    root.addSubview(container)

    container.addSubview(child)
    check window.mouseDownAt(initPoint(35, 30), timestamp = 25.0)
    check selected == child

    container.removeFromSuperview()
    check removed == container
    selected = nil
    let detachedWindow = newWindow("Uninspected", frame = rect(0, 0, 180, 120))
    defer:
      detachedWindow.close()
    detachedWindow.setContentView(container)
    let point = child.pointToWindow(initPoint(5, 5))
    check not detachedWindow.mouseDownAt(point)
    discard detachedWindow.mouseUpAt(point)
    check selected.isNil

    detachedWindow.setContentView(nil)
    root.addSubview(container)
    check window.mouseDownAt(child.pointToWindow(initPoint(5, 5)), timestamp = 26.0)
    let selectedAgain = selected == child
    check selectedAgain

    check selection.uninstall()

  test "view inspector can select inspected views from mouseDown":
    let
      window = newWindow("Inspector selection", frame = rect(0, 0, 160, 120))
      root = newView(frame = rect(0, 0, 160, 120))
      child = newView("child", frame = rect(20, 20, 50, 35))

    root.addSubview(child)
    window.setContentView(root)

    let inspector = newViewInspector(root)

    check inspector.selectsViewsOnMouseDown
    check window.mouseDownAt(initPoint(25, 25), timestamp = 30.0)
    check inspector.selectedView == child
