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
