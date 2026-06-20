import std/unittest

import sigils/core

import merenda/nimkit
import merenda/nimkit/view/viewbase

type LayoutInvalidationSpy = ref object of Agent
  reasons: seq[LayoutInvalidationReason]

proc record(spy: LayoutInvalidationSpy, reason: LayoutInvalidationReason) {.slot.} =
  spy.reasons.add reason

suite "nimkit constraints":
  test "layout constraints store Cocoa-shaped relation data":
    let
      view = newView(frame = initRect(0, 0, 100, 80))
      peer = newView(frame = initRect(10, 10, 40, 20))
      constraint = newLayoutConstraint(
        view,
        latWidth,
        lrGreaterThanOrEqual,
        peer,
        latHeight,
        multiplier = 2.0'f32,
        constant = 8.0'f32,
        priority = LayoutPriorityHigh,
      )

    check constraint.firstItem == view
    check constraint.firstAttribute == latWidth
    check constraint.relation == lrGreaterThanOrEqual
    check constraint.secondItem == peer
    check constraint.secondAttribute == latHeight
    check constraint.multiplier == 2.0'f32
    check constraint.constant == 8.0'f32
    check constraint.priority == LayoutPriorityHigh
    check not constraint.isActive
    check constraint.owningView.isNil
    check ord(latLeft) == 1
    check LayoutAttributeBaseline == latLastBaseline
    check ord(lrLessThanOrEqual) == -1

  test "layout anchors create Cocoa-shaped constraints":
    let
      root = newView(frame = initRect(0, 0, 320, 200))
      child = newView(frame = initRect(0, 0, 40, 20))
      left = child[anLeft].equalTo(root[anLeft], constant = 18.0'f32)
      centerY = child[anCenterY].equalTo(root[anCenterY])
      width = child[anWidth].equalTo(96.0'f32)
      height = child[anHeight].greaterThanOrEqualTo(
        root[anHeight], multiplier = 0.5'f32, constant = -12.0'f32
      )
      renamedTop = child[anTop].equalTo(root[anBottom], constant = 10.0'f32)
      renamedWidth = child[anWidth].equalTo(88.0'f32)
      equalLeft = cx(child[anLeft] == root[anLeft])
      equalHeight = cx(child[anHeight] == root[anHeight])
      equalWidth = cx(child[anWidth] == 72.0'f32)
      offsetTop = cx(child[anTop] == root[anBottom] + 12.0'f32)
      offsetRight = cx(child[anRight] == root[anRight] - 8.0'f32)
      emMinWidth = cx(child[anWidth] >= 20'em)
      minWidth = cx(child[anWidth] >= root[anWidth], multiplier = 0.5'f32)
      maxHeight = cx(child[anHeight] <= 42.0'f32, priority = LayoutPriorityHigh)

    check child[anLeft].item == child
    check child[anLeft].attribute == latLeft
    check child[anLeft].offset == 0.0'f32
    check left.firstItem == child
    check left.firstAttribute == latLeft
    check left.secondItem == root
    check left.secondAttribute == latLeft
    check left.constant == 18.0'f32

    check centerY.firstAttribute == latCenterY
    check centerY.secondAttribute == latCenterY
    check width.secondItem.isNil
    check width.secondAttribute == latNotAnAttribute
    check width.constant == 96.0'f32
    check renamedTop.firstAttribute == latTop
    check renamedTop.secondAttribute == latBottom
    check renamedTop.constant == 10.0'f32
    check renamedWidth.secondItem.isNil
    check renamedWidth.constant == 88.0'f32
    check equalLeft.firstAttribute == latLeft
    check equalLeft.secondAttribute == latLeft
    check equalHeight.firstAttribute == latHeight
    check equalHeight.secondAttribute == latHeight
    check equalWidth.secondItem.isNil
    check equalWidth.constant == 72.0'f32
    check offsetTop.firstAttribute == latTop
    check offsetTop.secondAttribute == latBottom
    check offsetTop.constant == 12.0'f32
    check offsetRight.firstAttribute == latRight
    check offsetRight.secondAttribute == latRight
    check offsetRight.constant == -8.0'f32
    check emMinWidth.relation == lrGreaterThanOrEqual
    check emMinWidth.secondItem.isNil
    check emMinWidth.constant == 20.0'f32 * DefaultFontSize
    check minWidth.relation == lrGreaterThanOrEqual
    check minWidth.multiplier == 0.5'f32
    check maxHeight.relation == lrLessThanOrEqual
    check maxHeight.priority == LayoutPriorityHigh
    check height.firstAttribute == latHeight
    check height.relation == lrGreaterThanOrEqual
    check height.multiplier == 0.5'f32
    check height.constant == -12.0'f32

  test "content layout guides and edge pins resolve through constraints":
    let
      root = newView(frame = initRect(0, 0, 300, 200))
      child = newView(frame = initRect(0, 0, 10, 10))
      guide = root.contentLayoutGuide(initEdgeInsets(10.0, 20.0, 30.0, 40.0))

    check guide.owningView == root
    check guide.insets == initEdgeInsets(10.0, 20.0, 30.0, 40.0)
    check guide[anLeft].offset == 20.0'f32
    check guide[anRight].offset == -40.0'f32
    check guide[anTop].offset == 10.0'f32
    check guide[anBottom].offset == -30.0'f32
    check guide[anWidth].offset == -60.0'f32
    check guide[anHeight].offset == -40.0'f32

    root.addSubview(child)
    let constraints = child.pinEdges(toGuide = guide)
    check constraints.len == 4
    for constraint in constraints:
      check constraint.active
    root.layoutSubtreeIfNeeded()

    check child.frame() == initRect(20, 10, 240, 160)
    var foundUserSummary = false
    for summary in root.constraintsAffectingLayout():
      if summary.source == lisUser:
        foundUserSummary = true
        check summary.constraints == 4
        check summary.equations == 0
    check foundUserSummary

  test "edge constraints can build an inactive subset":
    let
      root = newView(frame = initRect(0, 0, 300, 200))
      child = newView(frame = initRect(0, 0, 10, 30))

    root.addSubview(child)
    let constraints = child.edgeConstraints(
      toView = root,
      insets = initEdgeInsets(12.0, 18.0, 24.0, 30.0),
      edges = {leLeft, leTop, leRight},
    )
    check constraints.len == 3
    for constraint in constraints:
      check not constraint.active
    check root.constraints.len == 0

    activate(constraints)
    root.layoutSubtreeIfNeeded()

    check child.frame() == initRect(18, 12, 252, 30)

  test "unary constraints activate on their first item":
    let
      view = newView(frame = initRect(0, 0, 100, 80))
      width = newLayoutConstraint(view, latWidth, constant = 120.0'f32)

    view.layoutSubtreeIfNeeded()
    check view.constraints.len == 0

    width.active = true

    check width.active
    check width.owningView == view
    check view.constraints == @[width]
    check view.needsUpdateConstraints
    check view.needsLayout

    view.addConstraint(width)
    check view.constraints == @[width]

    width.active = false
    check not width.active
    check width.owningView.isNil
    check view.constraints.len == 0

  test "two-item constraints activate on the nearest common view":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      left = newView(frame = initRect(0, 0, 80, 40))
      right = newView(frame = initRect(100, 0, 80, 40))

    root.addSubview(left)
    root.addSubview(right)
    root.layoutSubtreeIfNeeded()

    let spacing =
      newLayoutConstraint(left, latRight, lrEqual, right, latLeft, constant = -12.0'f32)

    activate(spacing)

    check spacing.active
    check spacing.owningView == root
    check root.constraints == @[spacing]
    check left.constraints.len == 0
    check right.constraints.len == 0

    deactivate(spacing)
    check not spacing.active
    check spacing.owningView.isNil
    check root.constraints.len == 0

  test "active constraint changes invalidate owning view lifecycle":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      child = newView(frame = initRect(20, 20, 80, 40))
      width = newLayoutConstraint(child, latWidth, constant = 80.0'f32)

    root.addSubview(child)
    root.layoutSubtreeIfNeeded()
    child.setNeedsUpdateConstraints()
    child.updateConstraintsForSubtreeIfNeeded()
    child.needsLayout = false

    child.addConstraint(width)
    child.updateConstraintsForSubtreeIfNeeded()
    child.needsLayout = false

    width.constant = 120.0'f32
    check child.needsUpdateConstraints
    check child.needsLayout

    child.updateConstraintsForSubtreeIfNeeded()
    child.needsLayout = false

    width.priority = LayoutPriorityLow
    check width.priority == LayoutPriorityLow
    check child.needsUpdateConstraints
    check child.needsLayout

  test "autoresizing mask stores Cocoa bridge state":
    let view = newView(frame = initRect(0, 0, 100, 80))

    check view.autoresizingMask == {}
    check view.autoresizingMaskConstraints

    view.autoresizingMask = {cxMinXMargin, cxWidthSizable, cxMaxYMargin}
    check view.autoresizingMask == {cxMinXMargin, cxWidthSizable, cxMaxYMargin}
    check view.needsUpdateConstraints
    check view.needsLayout

    view.updateConstraintsForSubtreeIfNeeded()
    view.needsLayout = false
    view.autoresizingMask = view.autoresizingMask()
    check not view.needsUpdateConstraints
    check not view.needsLayout

    view.autoresizingMaskConstraints = false
    check not view.autoresizingMaskConstraints
    view.translatesAutoresizingMaskIntoConstraints = true
    check view.autoresizingMaskConstraints
    check view.translatesAutoresizingMaskIntoConstraints
    check view.needsUpdateConstraints
    check view.needsLayout

  test "autoresizing changes invalidate child and container constraints":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      child = newView(frame = initRect(20, 20, 80, 40))

    root.addSubview(child)
    root.layoutSubtreeIfNeeded()
    check not root.needsUpdateConstraints
    check not child.needsUpdateConstraints

    child.autoresizingMask = {cxWidthSizable, cxHeightSizable}
    check root.needsUpdateConstraints
    check root.needsLayout
    check child.needsUpdateConstraints
    check child.needsLayout

    root.layoutSubtreeIfNeeded()
    child.autoresizingMaskConstraints = false
    check root.needsUpdateConstraints
    check root.needsLayout
    check child.needsUpdateConstraints
    check child.needsLayout

    root.layoutSubtreeIfNeeded()
    root.setFrame(initRect(0, 0, 300, 180))
    check root.needsUpdateConstraints
    check root.needsLayout
    check not child.needsUpdateConstraints

    child.autoresizingMaskConstraints = true
    root.layoutSubtreeIfNeeded()
    root.setBounds(initRect(0, 0, 320, 200))
    check root.needsUpdateConstraints
    check root.needsLayout
    check child.needsUpdateConstraints
    check child.needsLayout

  test "autoresizing state separates reference refresh from input rebuild":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      child = newView(frame = initRect(20, 20, 80, 40))

    root.addSubview(child)
    root.layoutSubtreeIfNeeded()
    let oldSuperviewReference = child.xAutoresizingState.referenceSuperviewRect
    check child.xAutoresizingState.hasReference
    check not child.xAutoresizingState.referenceDirty
    check not child.xAutoresizingState.inputsDirty

    root.frame = initRect(0, 0, 300, 180)
    check child.xAutoresizingState.hasReference
    check child.xAutoresizingState.referenceSuperviewRect == oldSuperviewReference
    check not child.xAutoresizingState.referenceDirty
    check child.xAutoresizingState.inputsDirty

    root.layoutSubtreeIfNeeded()
    check child.xAutoresizingState.referenceSuperviewRect == root.alignmentRect()
    check not child.xAutoresizingState.referenceDirty
    check not child.xAutoresizingState.inputsDirty

    child.frame = initRect(30, 25, 90, 45)
    check child.xAutoresizingState.referenceRect == child.alignmentRect()
    check not child.xAutoresizingState.referenceDirty
    check not child.xAutoresizingState.inputsDirty

    child.autoresizingMaskConstraints = false
    check not child.xAutoresizingState.hasReference
    check not child.xAutoresizingState.referenceDirty
    check not child.xAutoresizingState.inputsDirty

  test "superview geometry observations follow moved views":
    let
      first = newView(frame = initRect(0, 0, 240, 120))
      second = newView(frame = initRect(0, 0, 240, 120))
      child = newView(frame = initRect(20, 20, 80, 40))

    first.addSubview(child)
    first.layoutSubtreeIfNeeded()
    check not child.needsUpdateConstraints

    second.addSubview(child)
    first.layoutSubtreeIfNeeded()
    second.layoutSubtreeIfNeeded()
    check not child.needsUpdateConstraints

    first.frame = initRect(0, 0, 280, 140)
    check not child.needsUpdateConstraints

    second.frame = initRect(0, 0, 300, 160)
    check child.needsUpdateConstraints
    check child.xAutoresizingState.inputsDirty

  test "generated autoresizing constraints preserve default origin and size":
    let
      root = newView(frame = initRect(0, 0, 200, 100))
      child = newView(frame = initRect(20, 10, 80, 30))

    root.addSubview(child)
    root.layoutSubtreeIfNeeded()
    root.frame = initRect(0, 0, 300, 160)
    root.layoutSubtreeIfNeeded()

    check child.frame() == initRect(20, 10, 80, 30)

  test "generated autoresizing constraints resize sizable dimensions":
    let
      root = newView(frame = initRect(0, 0, 200, 100))
      child = newView(frame = initRect(20, 10, 80, 30))

    root.addSubview(child)
    child.autoresizingMask = {cxWidthSizable, cxHeightSizable}
    root.layoutSubtreeIfNeeded()
    root.frame = initRect(0, 0, 300, 160)
    root.layoutSubtreeIfNeeded()

    check child.frame() == initRect(20, 10, 180, 90)

  test "generated autoresizing constraints move flexible minimum margins":
    let
      root = newView(frame = initRect(0, 0, 200, 100))
      child = newView(frame = initRect(20, 10, 80, 30))

    root.addSubview(child)
    child.autoresizingMask = {cxMinXMargin, cxMinYMargin}
    root.layoutSubtreeIfNeeded()
    root.frame = initRect(0, 0, 300, 160)
    root.layoutSubtreeIfNeeded()

    check child.frame() == initRect(120, 70, 80, 30)

  test "explicit constraints take precedence over autoresizing masks":
    let
      root = newView(frame = initRect(0, 0, 200, 100))
      child = newView(frame = initRect(20, 10, 80, 30))
      width = newLayoutConstraint(child, latWidth, constant = 50.0)

    root.addSubview(child)
    child.autoresizingMask = {cxWidthSizable}
    activate(width)
    root.layoutSubtreeIfNeeded()
    root.frame = initRect(0, 0, 300, 100)
    root.layoutSubtreeIfNeeded()

    check child.frame().size.width == 50.0'f32

  test "solver applies constant sizes":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      child = newView(frame = initRect(10, 12, 20, 10))
      width = newLayoutConstraint(child, latWidth, constant = 96.0'f32)
      height = newLayoutConstraint(child, latHeight, constant = 28.0'f32)

    root.addSubview(child)
    activate(width, height)
    root.layoutSubtreeIfNeeded()

    check child.frame() == initRect(10, 12, 96, 28)
    check not child.needsUpdateConstraints
    check not child.needsLayout

  test "solver applies superview edge pins":
    let
      root = newView(frame = initRect(0, 0, 300, 200))
      child = newView(frame = initRect(0, 0, 20, 10))
      left =
        newLayoutConstraint(child, latLeft, lrEqual, root, latLeft, constant = 20.0)
      top = newLayoutConstraint(child, latTop, lrEqual, root, latTop, constant = 15.0)
      right =
        newLayoutConstraint(child, latRight, lrEqual, root, latRight, constant = -30.0)
      bottom = newLayoutConstraint(
        child, latBottom, lrEqual, root, latBottom, constant = -25.0
      )

    root.addSubview(child)
    activate(left, top, right, bottom)
    root.layoutSubtreeIfNeeded()

    check child.frame() == initRect(20, 15, 250, 160)

  test "solver applies superview centers":
    let
      root = newView(frame = initRect(0, 0, 300, 200))
      child = newView(frame = initRect(0, 0, 10, 10))
      width = newLayoutConstraint(child, latWidth, constant = 50.0)
      height = newLayoutConstraint(child, latHeight, constant = 20.0)
      centerX = newLayoutConstraint(child, latCenterX, lrEqual, root, latCenterX)
      centerY = newLayoutConstraint(child, latCenterY, lrEqual, root, latCenterY)

    root.addSubview(child)
    activate(width, height, centerX, centerY)
    root.layoutSubtreeIfNeeded()

    check child.frame() == initRect(125, 90, 50, 20)

  test "solver keeps subtree root geometry fixed":
    let
      root = newView(frame = initRect(0, 0, 100, 80))
      child = newView(frame = initRect(0, 0, 20, 10))
      left = newLayoutConstraint(child, latLeft, lrEqual, root, latLeft)
      right = newLayoutConstraint(child, latRight, lrEqual, root, latRight)
      width = newLayoutConstraint(child, latWidth, constant = 160.0)

    root.addSubview(child)
    activate(left, right, width)
    root.layoutSubtreeIfNeeded()

    check root.frame() == initRect(0, 0, 100, 80)
    check child.frame() == initRect(0, 0, 100, 10)

  test "translates false lets intrinsic size participate in layout":
    let
      root = newView(frame = initRect(0, 0, 300, 120))
      button = newButton("Intrinsic", frame = initRect(10, 10, 1, 1))

    root.addSubview(button)
    button.autoresizingMaskConstraints = false
    root.layoutSubtreeIfNeeded()

    let natural = button.intrinsicContentSize().resolveIntrinsicSize(initSize(0, 0))
    check button.frame().origin == initPoint(10, 10)
    check button.frame().size == natural

  test "constraint participants use intrinsic size with autoresizing enabled":
    let
      root = newView(frame = initRect(0, 0, 300, 120))
      button = newButton("Intrinsic", frame = initRect(1, 1, 1, 1))
      left =
        newLayoutConstraint(button, latLeft, lrEqual, root, latLeft, constant = 10.0)
      top = newLayoutConstraint(button, latTop, lrEqual, root, latTop, constant = 12.0)

    root.addSubview(button)
    check button.autoresizingMaskConstraints
    activate(left, top)
    root.layoutSubtreeIfNeeded()

    let natural = button.intrinsicContentSize().resolveIntrinsicSize(initSize(0, 0))
    check button.frame().origin == initPoint(10, 12)
    check button.frame().size == natural

  test "subtree solver ignores constraints that reference outside views":
    let
      root = newView(frame = initRect(0, 0, 100, 80))
      child = newView(frame = initRect(10, 10, 20, 10))
      external = newView(frame = initRect(200, 0, 80, 40))
      outside = newLayoutConstraint(child, latRight, lrEqual, external, latLeft)

    root.addSubview(child)
    child.addConstraint(outside)
    root.layoutSubtreeIfNeeded()

    check child.frame() == initRect(10, 10, 20, 10)
    check external.frame() == initRect(200, 0, 80, 40)

  test "solver applies sibling constraints":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      left = newView(frame = initRect(0, 0, 80, 40))
      right = newView(frame = initRect(100, 0, 80, 40))
      rightPin =
        newLayoutConstraint(right, latLeft, lrEqual, root, latLeft, constant = 100.0)
      spacing = newLayoutConstraint(left, latRight, lrEqual, right, latLeft)

    root.addSubview(left)
    root.addSubview(right)
    activate(rightPin, spacing)
    root.layoutSubtreeIfNeeded()

    check left.frame().maxX == right.frame().minX
    check left.frame().size == initSize(80, 40)
    check right.frame() == initRect(100, 0, 80, 40)

  test "solver honors stronger soft constraints":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      child = newView(frame = initRect(0, 0, 40, 20))
      low = newLayoutConstraint(
        child, latWidth, lrEqual, nil, constant = 160.0, priority = LayoutPriorityLow
      )
      high = newLayoutConstraint(
        child, latWidth, lrEqual, nil, constant = 90.0, priority = LayoutPriorityHigh
      )

    root.addSubview(child)
    activate(low, high)
    root.layoutSubtreeIfNeeded()

    check child.frame().size == initSize(90, 20)

  test "layout item geometry exposes alignment rect and baseline hooks":
    let view = newView(frame = initRect(10, 20, 100, 50))

    check view.alignmentInsets == initEdgeInsets(0.0)
    check view.alignmentRect == view.frame()
    check view.alignmentRectForFrame(view.frame()) == view.frame()
    check view.frameForAlignmentRect(view.alignmentRect()) == view.frame()
    check view.lastBaselineOffset == 0.0'f32
    check view.firstBaselineOffset == 0.0'f32

    view.alignmentInsets = initEdgeInsets(2.0, 4.0, 6.0, 8.0)
    view.lastBaselineOffset = 7.0'f32
    view.firstBaselineOffset = 9.0'f32

    let alignmentRect = view.alignmentRect()
    check alignmentRect == initRect(14, 22, 88, 42)
    check view.frameForAlignmentRect(alignmentRect) == view.frame()
    check view.layoutValue(latLeft) == 14.0'f32
    check view.layoutValue(latLeading) == 14.0'f32
    check view.layoutValue(latRight) == 102.0'f32
    check view.layoutValue(latTrailing) == 102.0'f32
    check view.layoutValue(latTop) == 22.0'f32
    check view.layoutValue(latBottom) == 64.0'f32
    check view.layoutValue(latWidth) == 88.0'f32
    check view.layoutValue(latHeight) == 42.0'f32
    check view.layoutValue(latCenterX) == 58.0'f32
    check view.layoutValue(latCenterY) == 43.0'f32
    check view.layoutValue(latFirstBaseline) == 31.0'f32
    check view.layoutValue(latLastBaseline) == 57.0'f32
    check view.layoutValue(latNotAnAttribute) == 0.0'f32

    view.alignmentRect = initRect(20, 30, 60, 30)
    check view.frame() == initRect(16, 28, 72, 38)
    check view.alignmentRect() == initRect(20, 30, 60, 30)

  test "layout item geometry invalidation follows frame and priority changes":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      left = newView(frame = initRect(0, 0, 80, 40))
      right = newView(frame = initRect(100, 0, 80, 40))
      spacing = newLayoutConstraint(left, latRight, lrEqual, right, latLeft)

    root.addSubview(left)
    root.addSubview(right)
    activate(spacing)
    root.layoutSubtreeIfNeeded()
    check not root.needsUpdateConstraints
    check not left.needsUpdateConstraints
    check not root.needsLayout
    check not left.needsLayout

    left.frame = initRect(4, 5, 90, 44)
    check left.needsUpdateConstraints
    check left.needsLayout
    check root.needsUpdateConstraints
    check root.needsLayout

    root.layoutSubtreeIfNeeded()
    check not root.needsUpdateConstraints
    check not left.needsUpdateConstraints
    check not root.needsLayout
    check not left.needsLayout

    left.invalidateIntrinsicContentSize()
    check left.needsUpdateConstraints
    check left.needsLayout
    check root.needsUpdateConstraints
    check root.needsLayout

    root.layoutSubtreeIfNeeded()
    left.huggingPriority[dcol] = LayoutPriorityHigh
    check left.needsUpdateConstraints
    check root.needsUpdateConstraints

    root.layoutSubtreeIfNeeded()
    left.compressionPriority[drow] = LayoutPriorityRequired
    check left.needsUpdateConstraints
    check root.needsUpdateConstraints

    root.layoutSubtreeIfNeeded()
    left.alignmentInsets = initEdgeInsets(1.0)
    check left.needsUpdateConstraints
    check root.needsUpdateConstraints

    root.layoutSubtreeIfNeeded()
    left.lastBaselineOffset = 4.0'f32
    check left.needsUpdateConstraints
    check root.needsUpdateConstraints

    root.layoutSubtreeIfNeeded()
    left.firstBaselineOffset = 3.0'f32
    check left.needsUpdateConstraints
    check root.needsUpdateConstraints

  test "layout item geometry invalidation follows hierarchy changes":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      child = newView(frame = initRect(20, 20, 80, 40))

    root.layoutSubtreeIfNeeded()
    root.addSubview(child)
    check root.needsUpdateConstraints
    check root.needsLayout
    check child.needsUpdateConstraints
    check child.needsLayout

    root.layoutSubtreeIfNeeded()
    child.removeFromSuperview()
    check root.needsUpdateConstraints
    check root.needsLayout
    check child.needsUpdateConstraints
    check child.needsLayout

  test "layout invalidation signal bus notifies subscribers and dirty sources":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      spy = LayoutInvalidationSpy()

    root.connect(layoutInputChanged, spy, record)
    root.layoutSubtreeIfNeeded()

    root.frame = initRect(0, 0, 260, 120)
    check spy.reasons.len == 1
    check spy.reasons[0] == lirFrame
    check lisAutoresizingMask in root.layoutInputDirtySources()
    check root.needsUpdateConstraints
    check root.needsLayout

    root.layoutSubtreeIfNeeded()
    root.invalidateIntrinsicContentSize()
    check spy.reasons[^1] == lirIntrinsic
    check lisIntrinsic in root.layoutInputDirtySources()

  test "layout invalidation signal bus aggregates descendant dirty sources":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      child = newView(frame = initRect(20, 10, 80, 30))

    root.addSubview(child)
    root.layoutSubtreeIfNeeded()

    child.frame = initRect(24, 14, 90, 34)
    check lisAutoresizingMask in root.xLayoutInputCache.aggregateDirtySources
    check not root.xLayoutInputCache.aggregateStructureDirty

    root.layoutSubtreeIfNeeded()
    child.invalidateIntrinsicContentSize()
    check lisIntrinsic in root.xLayoutInputCache.aggregateDirtySources
    check not root.xLayoutInputCache.aggregateStructureDirty

    root.layoutSubtreeIfNeeded()
    root.addSubview(newView(frame = initRect(0, 0, 10, 10)))
    check lisContainer in root.xLayoutInputCache.aggregateDirtySources
    check root.xLayoutInputCache.aggregateStructureDirty

  test "generated layout summary exposes internal autoresizing equations":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      child = newView(frame = initRect(20, 10, 80, 30))

    child.autoresizingMask = {cxWidthSizable, cxHeightSizable}
    root.addSubview(child)
    root.layoutSubtreeIfNeeded()

    var found = false
    for summary in root.generatedLayoutSummary():
      if summary.source == lisAutoresizingMask:
        found = true
        check summary.constraints == 0
        check summary.equations == 4
        check summary.terms == 10
    check found

  test "generated layout summary exposes intrinsic equations":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      button = newButton("Intrinsic", frame = initRect(10, 10, 1, 1))

    button.autoresizingMaskConstraints = false
    root.addSubview(button)
    root.layoutSubtreeIfNeeded()

    var found = false
    for summary in root.generatedLayoutSummary():
      if summary.source == lisIntrinsic:
        found = true
        check summary.constraints == 0
        check summary.equations == 4
        check summary.terms == 4
    check found

  test "generated layout cache rebuilds dirty source buckets":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      autoresized = newView(frame = initRect(20, 10, 80, 30))
      button = newButton("Intrinsic", frame = initRect(10, 60, 1, 1))

    autoresized.autoresizingMask = {cxWidthSizable}
    button.autoresizingMaskConstraints = false
    root.addSubview(autoresized, button)
    root.layoutSubtreeIfNeeded()

    let
      initialSolveGeneration = root.layoutInputGeneration()
      initialAutoresizingGeneration =
        root.xLayoutInputCache.sourceGenerations[lisAutoresizingMask]
      initialIntrinsicGeneration =
        root.xLayoutInputCache.sourceGenerations[lisIntrinsic]

    check initialSolveGeneration == 1
    check initialAutoresizingGeneration > 0
    check initialIntrinsicGeneration > 0

    root.frame = initRect(0, 0, 300, 120)
    root.layoutSubtreeIfNeeded()

    let
      resizedAutoresizingGeneration =
        root.xLayoutInputCache.sourceGenerations[lisAutoresizingMask]
      resizedIntrinsicGeneration =
        root.xLayoutInputCache.sourceGenerations[lisIntrinsic]

    check root.layoutInputGeneration() == initialSolveGeneration + 1
    check resizedAutoresizingGeneration == initialAutoresizingGeneration + 1
    check resizedIntrinsicGeneration == initialIntrinsicGeneration

    button.invalidateIntrinsicContentSize()
    root.layoutSubtreeIfNeeded()

    check root.xLayoutInputCache.sourceGenerations[lisAutoresizingMask] ==
      resizedAutoresizingGeneration
    check root.xLayoutInputCache.sourceGenerations[lisIntrinsic] ==
      resizedIntrinsicGeneration + 1

  test "container metric invalidation rebuilds intrinsic source bucket":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      stack = newStackView(frame = initRect(10, 10, 120, 40))
      button = newButton("Stack", frame = initRect(0, 0, 1, 1))

    stack.autoresizingMaskConstraints = false
    stack.addArrangedSubview(button)
    root.addSubview(stack)
    root.layoutSubtreeIfNeeded()

    let
      initialAutoresizingGeneration =
        root.xLayoutInputCache.sourceGenerations[lisAutoresizingMask]
      initialIntrinsicGeneration =
        root.xLayoutInputCache.sourceGenerations[lisIntrinsic]
      initialContainerGeneration =
        root.xLayoutInputCache.sourceGenerations[lisContainer]

    stack.spacing = stack.spacing + 6.0'f32

    check lisIntrinsic in stack.layoutInputDirtySources()
    check lisIntrinsic in root.xLayoutInputCache.aggregateDirtySources
    check not root.xLayoutInputCache.aggregateStructureDirty

    root.layoutSubtreeIfNeeded()

    check root.xLayoutInputCache.sourceGenerations[lisAutoresizingMask] ==
      initialAutoresizingGeneration
    check root.xLayoutInputCache.sourceGenerations[lisIntrinsic] ==
      initialIntrinsicGeneration + 1
    check root.xLayoutInputCache.sourceGenerations[lisContainer] ==
      initialContainerGeneration

  test "generated layout cache rebuilds all source buckets for structural changes":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      autoresized = newView(frame = initRect(20, 10, 80, 30))
      button = newButton("Intrinsic", frame = initRect(10, 60, 1, 1))

    autoresized.autoresizingMask = {cxWidthSizable}
    button.autoresizingMaskConstraints = false
    root.addSubview(autoresized, button)
    root.layoutSubtreeIfNeeded()

    let
      initialAutoresizingGeneration =
        root.xLayoutInputCache.sourceGenerations[lisAutoresizingMask]
      initialIntrinsicGeneration =
        root.xLayoutInputCache.sourceGenerations[lisIntrinsic]
      initialContainerGeneration =
        root.xLayoutInputCache.sourceGenerations[lisContainer]

    root.addSubview(newView(frame = initRect(0, 0, 10, 10)))
    root.layoutSubtreeIfNeeded()

    check root.xLayoutInputCache.sourceGenerations[lisAutoresizingMask] ==
      initialAutoresizingGeneration + 1
    check root.xLayoutInputCache.sourceGenerations[lisIntrinsic] ==
      initialIntrinsicGeneration + 1
    check root.xLayoutInputCache.sourceGenerations[lisContainer] ==
      initialContainerGeneration + 1

  test "generated layout cache rebuilds all source buckets for user constraints":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      autoresized = newView(frame = initRect(20, 10, 80, 30))
      button = newButton("Intrinsic", frame = initRect(10, 60, 1, 1))

    autoresized.autoresizingMask = {cxWidthSizable}
    button.autoresizingMaskConstraints = false
    root.addSubview(autoresized, button)
    root.layoutSubtreeIfNeeded()

    let
      initialAutoresizingGeneration =
        root.xLayoutInputCache.sourceGenerations[lisAutoresizingMask]
      initialIntrinsicGeneration =
        root.xLayoutInputCache.sourceGenerations[lisIntrinsic]
      initialContainerGeneration =
        root.xLayoutInputCache.sourceGenerations[lisContainer]

    activate(autoresized[anWidth].equalTo(90.0'f32))
    root.layoutSubtreeIfNeeded()

    check root.xLayoutInputCache.sourceGenerations[lisAutoresizingMask] ==
      initialAutoresizingGeneration + 1
    check root.xLayoutInputCache.sourceGenerations[lisIntrinsic] ==
      initialIntrinsicGeneration + 1
    check root.xLayoutInputCache.sourceGenerations[lisContainer] ==
      initialContainerGeneration + 1

  test "display invalidation does not rebuild generated source buckets":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      autoresized = newView(frame = initRect(20, 10, 80, 30))
      button = newButton("Intrinsic", frame = initRect(10, 60, 1, 1))

    autoresized.autoresizingMask = {cxWidthSizable}
    button.autoresizingMaskConstraints = false
    root.addSubview(autoresized, button)
    root.layoutSubtreeIfNeeded()

    let
      initialAutoresizingGeneration =
        root.xLayoutInputCache.sourceGenerations[lisAutoresizingMask]
      initialIntrinsicGeneration =
        root.xLayoutInputCache.sourceGenerations[lisIntrinsic]
      initialContainerGeneration =
        root.xLayoutInputCache.sourceGenerations[lisContainer]

    root.setNeedsDisplay(true)
    root.layoutSubtreeIfNeeded()

    check root.xLayoutInputCache.sourceGenerations[lisAutoresizingMask] ==
      initialAutoresizingGeneration
    check root.xLayoutInputCache.sourceGenerations[lisIntrinsic] ==
      initialIntrinsicGeneration
    check root.xLayoutInputCache.sourceGenerations[lisContainer] ==
      initialContainerGeneration

  test "explicit storage can move constraints between views":
    let
      firstOwner = newView(frame = initRect(0, 0, 100, 80))
      secondOwner = newView(frame = initRect(0, 0, 100, 80))
      child = newView(frame = initRect(0, 0, 40, 20))
      width = newLayoutConstraint(child, latWidth, constant = 40.0'f32)
      height = newLayoutConstraint(child, latHeight, constant = 20.0'f32)

    firstOwner.addConstraints(width, height)
    check width.active
    check height.active
    check width.owningView == firstOwner
    check height.owningView == firstOwner
    check firstOwner.constraints == @[width, height]

    secondOwner.addConstraints(width, height)
    check width.active
    check height.active
    check width.owningView == secondOwner
    check height.owningView == secondOwner
    check firstOwner.constraints.len == 0
    check secondOwner.constraints == @[width, height]

    secondOwner.removeConstraints(width, height)
    check not width.active
    check not height.active
    check secondOwner.constraints.len == 0
