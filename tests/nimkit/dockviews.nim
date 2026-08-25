import std/unittest

import merenda/nimkit

suite "nimkit dock views":
  test "panels split around targets and collapse empty branches":
    let
      dockView = newDockView(frame = rect(0, 0, 480, 320))
      first = newDockPanel(newView())
      second = newDockPanel(newView())
      third = newDockPanel(newView())

    check dockView.addPanel(first)
    check dockView.splitPanel(first, second, dpRight)
    check dockView.len == 2
    check dockView.rootView() of SplitView
    check SplitView(dockView.rootView()).splitAxis == laHorizontal
    check SplitView(dockView.rootView()).panes() == @[View(first), View(second)]

    check dockView.splitPanel(first, third, dpBottom)
    check dockView.len == 3
    check first.superview() of SplitView
    check SplitView(first.superview()).splitAxis == laVertical
    check SplitView(first.superview()).panes() == @[View(first), View(third)]

    check dockView.removePanel(third)
    check dockView.len == 2
    check first.superview() == dockView.rootView()
    check SplitView(dockView.rootView()).panes() == @[View(first), View(second)]

  test "drop targets follow center and nearest edge zones":
    let
      dockView = newDockView(frame = rect(0, 0, 400, 300))
      panel = newDockPanel(newView())
    check dockView.addPanel(panel)
    dockView.layoutSubtreeIfNeeded()

    let
      center = dockView.dropTargetAtPoint(initPoint(200, 150))
      left = dockView.dropTargetAtPoint(initPoint(10, 150))
      right = dockView.dropTargetAtPoint(initPoint(390, 150))
      top = dockView.dropTargetAtPoint(initPoint(200, 10))
      bottom = dockView.dropTargetAtPoint(initPoint(200, 290))
    check center.position == dpCenter
    check left.position == dpLeft
    check right.position == dpRight
    check top.position == dpTop
    check bottom.position == dpBottom
    check left.rect.size.width == 200.0'f32
    check bottom.rect.size.height == 150.0'f32

    dockView.dropTarget = right
    check dockView.dropTarget().panel == panel
    check dockView.dropTarget().position == dpRight
    dockView.clearDropTarget()
    check not dockView.dropTarget().valid()
