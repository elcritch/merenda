import std/unittest

import merenda/nimkit

suite "nimkit constraints":
  test "layout constraints store Cocoa-shaped relation data":
    let
      view = newView(0, 0, 100, 80)
      peer = newView(10, 10, 40, 20)
      constraint = newLayoutConstraint(
        view,
        latWidth,
        lrGreaterThanOrEqual,
        peer,
        latHeight,
        multiplier = 2.0'f32,
        constant = 8.0'f32,
        priority = LayoutPriorityDefaultHigh,
      )

    check constraint.firstItem == view
    check constraint.firstAttribute == latWidth
    check constraint.relation == lrGreaterThanOrEqual
    check constraint.secondItem == peer
    check constraint.secondAttribute == latHeight
    check constraint.multiplier == 2.0'f32
    check constraint.constant == 8.0'f32
    check constraint.priority == LayoutPriorityDefaultHigh
    check not constraint.isActive
    check constraint.owningView.isNil
    check ord(latLeft) == 1
    check LayoutAttributeBaseline == latLastBaseline
    check ord(lrLessThanOrEqual) == -1

  test "unary constraints activate on their first item":
    let
      view = newView(0, 0, 100, 80)
      width = newLayoutConstraint(view, latWidth, constant = 120.0'f32)

    view.layoutSubtreeIfNeeded()
    check view.constraints.len == 0

    width.setActive(true)

    check width.isActive
    check width.owningView == view
    check view.constraints == @[width]
    check view.needsUpdateConstraints
    check view.needsLayout

    view.addConstraint(width)
    check view.constraints == @[width]

    width.setActive(false)
    check not width.isActive
    check width.owningView.isNil
    check view.constraints.len == 0

  test "two-item constraints activate on the nearest common view":
    let
      root = newView(0, 0, 240, 120)
      left = newView(0, 0, 80, 40)
      right = newView(100, 0, 80, 40)

    root.addSubview(left)
    root.addSubview(right)
    root.layoutSubtreeIfNeeded()

    let spacing =
      newLayoutConstraint(left, latRight, lrEqual, right, latLeft, constant = -12.0'f32)

    activateConstraints([spacing])

    check spacing.isActive
    check spacing.owningView == root
    check root.constraints == @[spacing]
    check left.constraints.len == 0
    check right.constraints.len == 0

    deactivateConstraints([spacing])
    check not spacing.isActive
    check spacing.owningView.isNil
    check root.constraints.len == 0

  test "active constraint changes invalidate owning view lifecycle":
    let
      root = newView(0, 0, 240, 120)
      child = newView(20, 20, 80, 40)
      width = newLayoutConstraint(child, latWidth, constant = 80.0'f32)

    root.addSubview(child)
    root.layoutSubtreeIfNeeded()
    child.setNeedsUpdateConstraints()
    child.updateConstraintsForSubtreeIfNeeded()
    child.setNeedsLayout(false)

    child.addConstraint(width)
    child.updateConstraintsForSubtreeIfNeeded()
    child.setNeedsLayout(false)

    width.setConstant(120.0'f32)
    check child.needsUpdateConstraints
    check child.needsLayout

    child.updateConstraintsForSubtreeIfNeeded()
    child.setNeedsLayout(false)

    width.setPriority(LayoutPriorityDefaultLow)
    check width.priority == LayoutPriorityDefaultLow
    check child.needsUpdateConstraints
    check child.needsLayout

  test "layout item geometry exposes alignment rect and baseline hooks":
    let view = newView(10, 20, 100, 50)

    check view.alignmentRectInsets == initEdgeInsets(0.0)
    check view.alignmentRect == view.frame()
    check view.alignmentRectForFrame(view.frame()) == view.frame()
    check view.frameForAlignmentRect(view.alignmentRect()) == view.frame()
    check view.baselineOffsetFromBottom == 0.0'f32
    check view.firstBaselineOffsetFromTop == 0.0'f32

    view.setAlignmentRectInsets(initEdgeInsets(2.0, 4.0, 6.0, 8.0))
    view.setBaselineOffsetFromBottom(7.0'f32)
    view.setFirstBaselineOffsetFromTop(9.0'f32)

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

    view.setFrameFromAlignmentRect(initRect(20, 30, 60, 30))
    check view.frame() == initRect(16, 28, 72, 38)
    check view.alignmentRect() == initRect(20, 30, 60, 30)

  test "layout item geometry invalidation follows frame and priority changes":
    let
      root = newView(0, 0, 240, 120)
      left = newView(0, 0, 80, 40)
      right = newView(100, 0, 80, 40)
      spacing = newLayoutConstraint(left, latRight, lrEqual, right, latLeft)

    root.addSubview(left)
    root.addSubview(right)
    activateConstraints([spacing])
    root.layoutSubtreeIfNeeded()
    check not root.needsUpdateConstraints
    check not left.needsUpdateConstraints
    check not root.needsLayout
    check not left.needsLayout

    left.setFrame(initRect(4, 5, 90, 44))
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
    left.setContentHuggingPriority(LayoutPriorityDefaultHigh, laHorizontal)
    check left.needsUpdateConstraints
    check root.needsUpdateConstraints

    root.layoutSubtreeIfNeeded()
    left.setContentCompressionResistancePriority(LayoutPriorityRequired, laVertical)
    check left.needsUpdateConstraints
    check root.needsUpdateConstraints

    root.layoutSubtreeIfNeeded()
    left.setAlignmentRectInsets(initEdgeInsets(1.0))
    check left.needsUpdateConstraints
    check root.needsUpdateConstraints

    root.layoutSubtreeIfNeeded()
    left.setBaselineOffsetFromBottom(4.0'f32)
    check left.needsUpdateConstraints
    check root.needsUpdateConstraints

    root.layoutSubtreeIfNeeded()
    left.setFirstBaselineOffsetFromTop(3.0'f32)
    check left.needsUpdateConstraints
    check root.needsUpdateConstraints

  test "layout item geometry invalidation follows hierarchy changes":
    let
      root = newView(0, 0, 240, 120)
      child = newView(20, 20, 80, 40)

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

  test "explicit storage can move constraints between views":
    let
      firstOwner = newView(0, 0, 100, 80)
      secondOwner = newView(0, 0, 100, 80)
      child = newView(0, 0, 40, 20)
      width = newLayoutConstraint(child, latWidth, constant = 40.0'f32)

    firstOwner.addConstraint(width)
    check width.isActive
    check width.owningView == firstOwner
    check firstOwner.constraints == @[width]

    secondOwner.addConstraint(width)
    check width.isActive
    check width.owningView == secondOwner
    check firstOwner.constraints.len == 0
    check secondOwner.constraints == @[width]
