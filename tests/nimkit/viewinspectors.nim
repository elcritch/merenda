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
      window = newWindow("Inspector dynamic", frame = rect(0, 0, 180, 120))
      root = newView(frame = rect(0, 0, 180, 120))
      child = newView("lateChild", frame = rect(20, 20, 60, 40))
      inspector = newViewInspector(root)

    window.setContentView(root)
    root.addSubview(child)

    check window.mouseDownAt(initPoint(25, 25), timestamp = 40.0)
    check inspector.selectedView == child

    child.removeFromSuperview()
    check inspector.selectedView.isNil

  test "view inspector panel close detaches root hooks":
    let
      window = newWindow("Inspected window", frame = rect(0, 0, 240, 180))
      root = newView()
      child = newView("child", frame = rect(20, 20, 100, 50))

    root.addSubview(child)
    window.setContentView(root)
    defer:
      window.close()

    let panel = newViewInspectorPanel(root)

    check window.mouseDownAt(initPoint(40, 40))
    let selected = panel.inspector.selectedView == child
    check selected
    discard window.mouseUpAt(initPoint(40, 40))

    panel.window.close()

    check panel.inspector.inspectedRoot.isNil
    check panel.inspector.selectedView.isNil
    check not window.mouseDownAt(initPoint(40, 40))
    check panel.inspector.selectedView.isNil
    discard window.mouseUpAt(initPoint(40, 40))
