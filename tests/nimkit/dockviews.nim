import std/unittest

import merenda/nimkit
import ./fixtures/widgetflows

suite "nimkit dock views":
  test "split panels remain editable through resize removal and replacement":
    let
      window = newWindow("Dock workflow", frame = rect(0, 0, 640, 360))
      dock = newDockView()
      firstField = newTextField("First")
      secondField = newTextField("Second")
      first = newDockPanel(firstField)
      second = newDockPanel(secondField)
    defer:
      window.close()
    window.setContentView(dock)
    require dock.addPanel(first)
    require dock.splitPanel(first, second, dpRight)

    for size in [initSize(640, 360), initSize(940, 520), initSize(480, 320)]:
      window.frame = rect(0, 0, size.width, size.height)
      dock.layoutSubtreeIfNeeded()
      for index, field in [firstField, secondField]:
        check field.frame().size.width > 0
        check field.frame().size.height > 0
        let entered = "Pane " & $index & " at width " & $size.width
        require window.replaceText(field, entered)
        check field.text == entered
      check first.frame().maxX <= second.frame().minX
      check second.frame().maxX <= dock.bounds().maxX

    require dock.removePanel(second)
    dock.layoutSubtreeIfNeeded()
    check first.frame().size == dock.bounds().size
    require window.clickView(firstField)
    let before = firstField.text
    require window.dispatchTextInput(" still editable")
    check firstField.text != before
    let
      replacementField = newTextField("Replacement")
      replacement = newDockPanel(replacementField)
    require dock.splitPanel(first, replacement, dpBottom)
    dock.layoutSubtreeIfNeeded()
    check first.frame().maxY <= replacement.frame().minY
    check replacement.frame().maxY <= dock.bounds().maxY
    require window.replaceText(replacementField, "Replacement edited")
    check replacementField.text == "Replacement edited"

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
