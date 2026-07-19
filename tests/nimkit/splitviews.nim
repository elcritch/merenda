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

    splitView.addPane(left)
    splitView.addPane(right)
    splitView.layoutSubtreeIfNeeded()

    check left.frame() == rect(0.0, 0.0, 150.0, 120.0)
    check splitView.dividerRect(0) == rect(150.0, 0.0, 6.0, 120.0)
    check right.frame() == rect(156.0, 0.0, 150.0, 120.0)
    check splitView.cursorRects().len == 1
    check splitView.cursorRects()[0].cursor == "resize-left-right"

  test "vertical split view uses vertical axis and natural size":
    let
      splitView = newSplitView(laVertical, rect(0.0, 0.0, 200.0, 206.0))
      top = newFixedIntrinsicView(80.0, 40.0)
      bottom = newFixedIntrinsicView(90.0, 50.0)

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

  test "dragging divider uses mouse-down size snapshot":
    let
      splitView = newSplitView(laHorizontal, rect(0.0, 0.0, 306.0, 100.0))
      left = newFixedIntrinsicView(80.0, 40.0)
      right = newFixedIntrinsicView(90.0, 40.0)

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

  test "split view renders themed dividers":
    let
      splitView = newSplitView(laHorizontal, rect(0.0, 0.0, 306.0, 100.0))
      left = newFixedIntrinsicView(80.0, 40.0)
      right = newFixedIntrinsicView(90.0, 40.0)

    splitView.addPane(left)
    splitView.addPane(right)
    splitView.layoutSubtreeIfNeeded()

    let list = buildRenders(splitView)[DefaultDrawLevel]
    var rectangleCount = 0
    for node in list.nodes:
      if node.kind == nkRectangle:
        inc rectangleCount
    check rectangleCount >= 2
