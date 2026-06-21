import std/unittest

import merenda/nimkit

suite "nimkit view inspectors":
  test "view inspector tracks root and selected view":
    let
      root = newView()
      child = newButton("Run")
      inspector = newViewInspector(root)

    root.identifier = "root"
    child.identifier = "run"
    root.addSubview(child)

    check inspector.inspectedRoot == root
    inspector.selectView(child)
    check inspector.selectedView == child

    let otherRoot = newView()
    inspector.inspectedRoot = otherRoot
    check inspector.inspectedRoot == otherRoot
    check inspector.selectedView.isNil

    inspector.selectView(otherRoot)
    inspector.inspectedRoot = nil
    check inspector.inspectedRoot.isNil
    check inspector.selectedView.isNil

  test "view inspector panel can wrap an existing inspector":
    let
      root = newView()
      inspector = newViewInspector(root)
      panel = newViewInspectorPanel(inspector)

    check panel.inspector == inspector
    check panel.window != nil

  test "view inspector follows dynamic inspected subviews":
    let
      window = newWindow("Inspector dynamic", frame = initRect(0, 0, 180, 120))
      root = newView(frame = initRect(0, 0, 180, 120))
      child = newView("lateChild", frame = initRect(20, 20, 60, 40))
      inspector = newViewInspector(root)

    window.setContentView(root)
    root.addSubview(child)

    check window.mouseDownAt(initPoint(25, 25), timestamp = 40.0)
    check inspector.selectedView == child

    child.removeFromSuperview()
    check inspector.selectedView.isNil

  test "view inspector panel close detaches root hooks":
    let
      root = newView()
      child = newView("child")

    root.addSubview(child)

    let panel = newViewInspectorPanel(root)

    check DynamicAgent(child).methodStack(mouseDown()).len == 1
    panel.inspector.selectView(child)
    check panel.inspector.selectedView == child

    panel.window.close()

    check panel.inspector.inspectedRoot.isNil
    check panel.inspector.selectedView.isNil
    check DynamicAgent(child).methodStack(mouseDown()).len == 0
