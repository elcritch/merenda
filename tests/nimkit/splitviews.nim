import std/unittest

import figdraw

import sigils/core
import sigils/selectors

import merenda/nimkit

type FixedIntrinsicView = ref object of View
  naturalSize: Size

protocol FixedIntrinsicLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: FixedIntrinsicView): IntrinsicSize =
    initIntrinsicSize(view.naturalSize)

proc newFixedIntrinsicView(width, height: float32): FixedIntrinsicView =
  result = FixedIntrinsicView()
  initViewFields(result, rect(0.0, 0.0, width, height))
  result.naturalSize = initSize(width, height)
  result.autoresizingMaskConstraints = false
  discard result.withProtocol(FixedIntrinsicLayout)

proc splitAppearance(dividerThickness = 6.0'f32): Appearance =
  result = initAppearance()
  result[srSplitView, StyleSeparatorThickness] = dividerThickness

suite "nimkit split views":
  test "autosave name is a field-backed protocol property":
    let splitView = newSplitView()

    check splitView.conformsTo(SplitViewProtocol)
    check splitView.autosaveName() == ""
    splitView.autosaveName = "workspace"
    check splitView.autosaveName() == "workspace"

  test "split view protocol exposes selector-backed properties":
    let splitView = newSplitView(laHorizontal, rect(0.0, 0.0, 200.0, 100.0))

    check splitView.conformsTo(SplitViewProtocol)
    check splitView.splitAxis == laHorizontal

    let swizzledAxis: DynamicMethod = proc(
        self: DynamicAgent, invocation: var Invocation
    ) =
      check SplitView(self) == splitView
      invocation.setResult(laVertical)

    splitView.replaceMethod(splitAxis(), swizzledAxis)
    check splitView.splitAxis == laVertical

  test "horizontal split view lays out panes and divider cursor rects":
    let
      splitView = newSplitView(laHorizontal, rect(0.0, 0.0, 306.0, 120.0))
      left = newFixedIntrinsicView(80.0, 40.0)
      right = newFixedIntrinsicView(90.0, 50.0)

    splitView.appearance = splitAppearance()
    splitView.addPane(left)
    splitView.addPane(right)
    splitView.layoutSubtreeIfNeeded()

    check left.frame() == rect(0.0, 0.0, 150.0, 120.0)
    check splitView.dividerRect(0) == rect(150.0, 0.0, 6.0, 120.0)
    check right.frame() == rect(156.0, 0.0, 150.0, 120.0)
    check splitView.cursorRects().len == 1
    check splitView.cursorRects()[0].cursor == "resize-left-right"

  test "constraints inside a positioned second pane stay local":
    let
      splitView = newSplitView(laHorizontal, rect(0.0, 0.0, 306.0, 120.0))
      left = newFixedIntrinsicView(80.0, 40.0)
      right = newFixedIntrinsicView(90.0, 50.0)
      sidebar = newView(frame = rect(18.0, 10.0, 80.0, 40.0))
      sidebarLeft =
        newLayoutConstraint(sidebar, atLeft, lrEqual, right, atLeft, constant = 18.0)

    splitView.appearance = splitAppearance()
    splitView.addPane(left)
    splitView.addPane(right)
    splitView.layoutSubtreeIfNeeded()
    check right.frame().origin.x == 156.0'f32

    right.addSubview(sidebar)
    activate(sidebarLeft)

    splitView.layoutSubtreeIfNeeded()
    check sidebar.frame().origin.x == 18.0'f32

    splitView.layoutSubtreeIfNeeded()
    check sidebar.frame().origin.x == 18.0'f32

  test "vertical split view uses vertical axis and natural size":
    let
      splitView = newSplitView(laVertical, rect(0.0, 0.0, 200.0, 206.0))
      top = newFixedIntrinsicView(80.0, 40.0)
      bottom = newFixedIntrinsicView(90.0, 50.0)

    splitView.appearance = splitAppearance()
    splitView.addPane(top)
    splitView.addPane(bottom)
    splitView.layoutSubtreeIfNeeded()

    check top.frame() == rect(0.0, 0.0, 200.0, 100.0)
    check splitView.dividerRect(0) == rect(0.0, 100.0, 200.0, 6.0)
    check bottom.frame() == rect(0.0, 106.0, 200.0, 100.0)
    check splitView.intrinsicContentSize() == initIntrinsicSize(90.0, 96.0)
    check splitView.cursorRects()[0].cursor == "resize-up-down"

  test "divider movement honors adjacent pane min and max sizes":
    let
      splitView = newSplitView(laHorizontal, rect(0.0, 0.0, 306.0, 100.0))
      left = newFixedIntrinsicView(80.0, 40.0)
      right = newFixedIntrinsicView(90.0, 40.0)

    splitView.appearance = splitAppearance()
    splitView.addPane(left)
    splitView.addPane(right)
    splitView.setPaneSizeLimits(0, minSize = 80.0, maxSize = 210.0)
    splitView.setPaneSizeLimits(1, minSize = 90.0)

    splitView.setPositionOfDivider(0, 20.0)
    splitView.layoutSubtreeIfNeeded()
    check abs(left.frame().size.width - 80.0) < 0.001
    check right.frame().size.width == 220.0

    splitView.setPositionOfDivider(0, 260.0)
    splitView.layoutSubtreeIfNeeded()
    check left.frame().size.width == 210.0
    check right.frame().size.width == 90.0

  test "panes stay within an undersized split view":
    let
      splitView = newSplitView(laVertical, rect(0.0, 0.0, 200.0, 190.0))
      top = newFixedIntrinsicView(80.0, 24.0)
      bottom = newFixedIntrinsicView(90.0, 160.0)

    splitView.appearance = splitAppearance(8.0'f32)
    splitView.addPane(top, minSize = 24.0, maxSize = 24.0)
    splitView.addPane(bottom, minSize = 160.0)
    splitView.layoutSubtreeIfNeeded()

    check top.frame().size.height == 24.0
    check splitView.dividerRect(0).size.height == 8.0
    check bottom.frame().size.height == 158.0
    check bottom.frame().maxY == splitView.bounds().maxY

  test "dragging divider uses mouse-down size snapshot":
    let
      splitView = newSplitView(laHorizontal, rect(0.0, 0.0, 306.0, 100.0))
      left = newFixedIntrinsicView(80.0, 40.0)
      right = newFixedIntrinsicView(90.0, 40.0)

    splitView.appearance = splitAppearance()
    splitView.addPane(left)
    splitView.addPane(right)
    splitView.layoutSubtreeIfNeeded()

    check splitView.mouseDown(
      MouseEvent(button: mbPrimary, location: initPoint(153.0, 10.0))
    )
    check splitView.mouseDragged(
      MouseEvent(button: mbPrimary, location: initPoint(193.0, 10.0))
    )
    splitView.layoutSubtreeIfNeeded()
    check left.frame().size.width == 190.0
    check right.frame().size.width == 110.0

    check splitView.mouseDragged(
      MouseEvent(button: mbPrimary, location: initPoint(193.0, 10.0))
    )
    splitView.layoutSubtreeIfNeeded()
    check left.frame().size.width == 190.0
    check right.frame().size.width == 110.0
    check splitView.mouseUp(
      MouseEvent(button: mbPrimary, location: initPoint(193.0, 10.0))
    )

  test "collapsible panes are removed from layout and accessibility":
    let
      splitView = newSplitView(laHorizontal, rect(0.0, 0.0, 306.0, 100.0))
      left = newFixedIntrinsicView(80.0, 40.0)
      right = newFixedIntrinsicView(90.0, 40.0)

    left.accessibilityRole = arGroup
    right.accessibilityRole = arGroup
    splitView.addPane(left, collapsible = true)
    splitView.addPane(right)
    splitView.setPaneCollapsed(0, true)
    splitView.layoutSubtreeIfNeeded()

    check splitView.isPaneCollapsed(0)
    check left.frame().size.width == 0.0
    check right.frame() == rect(0.0, 0.0, 306.0, 100.0)
    check splitView.accessibilityChildren() == @[View(right)]

  test "split view state captures fractions and collapsed panes":
    let
      first = newSplitView(laHorizontal, rect(0.0, 0.0, 306.0, 100.0))
      a = newFixedIntrinsicView(80.0, 40.0)
      b = newFixedIntrinsicView(90.0, 40.0)
      second = newSplitView(laHorizontal, rect(0.0, 0.0, 306.0, 100.0))
      c = newFixedIntrinsicView(80.0, 40.0)
      d = newFixedIntrinsicView(90.0, 40.0)

    first.appearance = splitAppearance()
    second.appearance = splitAppearance()
    first.addPane(a, collapsible = true)
    first.addPane(b)
    first.setPositionOfDivider(0, 180.0)
    first.setPaneCollapsed(0, true)

    second.addPane(c, collapsible = true)
    second.addPane(d)
    second.restoreAutosaveString(first.autosaveString())
    second.layoutSubtreeIfNeeded()

    check second.isPaneCollapsed(0)
    second.setPaneCollapsed(0, false)
    second.layoutSubtreeIfNeeded()
    check c.frame().size.width == 180.0
    check d.frame().size.width == 120.0

  test "themed divider and grip follow layout and resizing":
    let
      splitView = newSplitView(laHorizontal, rect(0, 0, 306, 100))
      left = newFixedIntrinsicView(80, 40)
      right = newFixedIntrinsicView(90, 40)
      dividerFill = fill(color(0.12, 0.34, 0.56, 1))
      gripColor = color(0.76, 0.32, 0.11, 1)
    var appearance = initAppearance()
    appearance[srSplitView, StyleFill] = dividerFill
    appearance[srSplitView, StyleMarkColor] = gripColor
    appearance[srSplitView, StyleSeparatorThickness] = 10.0'f32
    appearance[srSplitView, StyleIndicatorSize] = 30.0'f32
    splitView.appearance = appearance
    splitView.addPane(left)
    splitView.addPane(right)

    for bounds in [rect(0, 0, 306, 100), rect(0, 0, 480, 160)]:
      splitView.frame = bounds
      let
        list = buildRenders(splitView)[DefaultDrawLevel]
        divider = splitView.dividerRect(0)
      check left.frame().maxX <= divider.minX
      check right.frame().minX >= divider.maxX
      check right.frame().maxX == splitView.bounds().maxX
      var foundDivider, foundGrip: bool
      for node in list.nodes:
        if node.kind != nkRectangle:
          continue
        if node.fill == dividerFill:
          foundDivider = true
          check node.screenBox.x == divider.minX
          check node.screenBox.w == divider.size.width
        if node.fill == fill(gripColor):
          foundGrip = true
          check node.screenBox.x >= divider.minX
          check node.screenBox.x + node.screenBox.w <= divider.maxX
          check node.screenBox.y >= divider.minY
          check node.screenBox.y + node.screenBox.h <= divider.maxY
          check abs(
            node.screenBox.y + node.screenBox.h / 2 -
              (divider.minY + divider.size.height / 2)
          ) < 0.01
      check foundDivider
      check foundGrip
