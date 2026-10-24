import std/unittest

import figdraw

import sigils/core
import sigils/selectors

import merenda/nimkit

type FixedIntrinsicView = ref object of View
  naturalSize: Size

type SplitPopupView = ref object of View

protocol SplitPopupHitTesting of ViewProtocol:
  method hitTestLevel(view: SplitPopupView, point: Point): int =
    PopupDrawLevel.int

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

  test "insertPane keeps subview order in sync with visual pane order":
    let
      splitView = newSplitView(laHorizontal, rect(0.0, 0.0, 306.0, 120.0))
      first = newView(frame = rect(0.0, 0.0, 80.0, 40.0))
      second = newView(frame = rect(0.0, 0.0, 80.0, 40.0))
      third = newView(frame = rect(0.0, 0.0, 80.0, 40.0))

    splitView.appearance = splitAppearance()
    splitView.addPane(first)
    splitView.addPane(second)
    splitView.insertPane(third, 1)
    splitView.layoutSubtreeIfNeeded()

    check splitView.panes() == @[View(first), View(third), View(second)]
    check splitView.subviews() == @[View(first), View(third), View(second)]
    check first.frame() == rect(0.0, 0.0, 98.0, 120.0)
    check third.frame() == rect(104.0, 0.0, 98.0, 120.0)
    check second.frame() == rect(208.0, 0.0, 98.0, 120.0)

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

  test "macOS thin dividers drag from either pane edge through window events":
    for theme in ["macos", "macos-dark"]:
      for axis in [laHorizontal, laVertical]:
        for offset in [-3.0'f32, 3.0'f32]:
          checkpoint(theme & " " & $axis & " " & $offset)
          let
            window = newWindow("Thin divider", frame = rect(0, 0, 400, 300))
            splitView = newSplitView(axis)
            first = newTextView("First pane")
            second = newTextView("Second pane")
          defer:
            window.close()
          splitView.addPane(first)
          splitView.addPane(second)
          window.setAppearance(initAppearance(initThemeByName(theme)))
          window.setContentView(splitView)
          splitView.layoutSubtreeIfNeeded()
          let
            divider = splitView.dividerRect(0)
            initial = splitView.positionOfDivider(0)
            local =
              if axis == laHorizontal:
                initPoint(divider.minX + divider.size.width / 2 + offset, 30)
              else:
                initPoint(30, divider.minY + divider.size.height / 2 + offset)
            start = splitView.pointToWindow(local)
            finish = splitView.pointToWindow(
              if axis == laHorizontal:
                initPoint(local.x + 30, local.y)
              else:
                initPoint(local.x, local.y + 30)
            )
            firstSize = first.frame().size
          check not divider.contains(local)
          check splitView.dividerAtPoint(local) == 0
          check splitView.hitTest(local) == splitView
          require splitView.cursorRects().len == 1
          check splitView.cursorRects()[0].rect.contains(local)
          require window.mouseDownAt(start)
          require window.mouseDraggedAt(finish)
          require window.mouseUpAt(finish)
          splitView.layoutSubtreeIfNeeded()
          check abs(splitView.positionOfDivider(0) - initial - 30) < 0.01
          if axis == laHorizontal:
            check abs(first.frame().size.width - firstSize.width - 30) < 0.01
          else:
            check abs(first.frame().size.height - firstSize.height - 30) < 0.01
          check splitView.hitTest(initPoint(20, 20)) != splitView
          let
            before = first.stringValue()
            textPoint = first.pointToWindow(initPoint(20, 20))
          require window.mouseDownAt(textPoint)
          discard window.mouseUpAt(textPoint)
          require window.dispatchTextInput("!")
          check first.stringValue().len == before.len + 1

  test "thin divider grab areas stay inside bounds and ignore hidden split views":
    let splitView = newSplitView(laHorizontal, rect(0, 0, 50, 30))
    splitView.appearance = splitAppearance(1)
    splitView.addPane(newView())
    splitView.addPane(newView())
    splitView.setPositionOfDivider(0, 0)
    splitView.layoutSubtreeIfNeeded()
    check splitView.dividerAtPoint(initPoint(-1, 15)) == -1
    check splitView.dividerAtPoint(initPoint(2, 15)) == 0
    splitView.hidden = true
    check splitView.hitTest(initPoint(2, 15)).isNil

  test "split view misses allow hit testing to continue to sibling views":
    let
      root = newView(rect(0, 0, 320, 200))
      sibling = newView(rect(0, 160, 320, 40))
      splitView = newSplitView(laHorizontal, rect(0, 0, 320, 140))
      point = initPoint(20, 180)
    splitView.appearance = splitAppearance(1)
    splitView.addPane(newView())
    splitView.addPane(newView())
    root.addSubview(sibling)
    root.addSubview(splitView)
    splitView.layoutSubtreeIfNeeded()

    check splitView.hitTest(point).isNil
    check root.hitTest(point) == sibling

  test "divider grab areas preserve popup hits and choose the nearest divider":
    let
      splitView = newSplitView(laHorizontal, rect(0, 0, 101, 50))
      first = newView()
      popup = SplitPopupView()
    splitView.appearance = splitAppearance(1)
    splitView.addPane(first)
    splitView.addPane(newView())
    splitView.layoutSubtreeIfNeeded()
    let divider = splitView.dividerRect(0)
    initViewFields(popup, rect(divider.minX - 10, 0, 20, 40))
    discard popup.withProtocol(SplitPopupHitTesting)
    first.addSubview(popup)
    check splitView.hitTest(initPoint(divider.minX - 2, 20)) == popup

    let crowded = newSplitView(laHorizontal, rect(0, 0, 5, 30))
    crowded.appearance = splitAppearance(1)
    for index in 0 .. 2:
      crowded.addPane(newView())
    crowded.layoutSubtreeIfNeeded()
    check crowded.dividerAtPoint(initPoint(1.5, 15)) == 0
    check crowded.dividerAtPoint(initPoint(3.5, 15)) == 1

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
