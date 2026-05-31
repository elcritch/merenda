import std/unittest

import merenda/nimkit

type FixedIntrinsicView = ref object of View
  naturalSize: Size

protocol FixedIntrinsicLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: FixedIntrinsicView): IntrinsicSize =
    initIntrinsicSize(view.naturalSize)

proc newFixedIntrinsicView(width, height: float32): FixedIntrinsicView =
  result = FixedIntrinsicView()
  initViewFields(result, initRect(0.0, 0.0, width, height))
  result.naturalSize = initSize(width, height)
  result.autoresizingMaskConstraints = false
  discard result.withProtocol(FixedIntrinsicLayout)

suite "nimkit stack views":
  test "horizontal stack intrinsic size sums widths and spacing with insets":
    let
      stack = newStackView(laHorizontal, frame = initRect(0, 0, 1, 1))
      first = newFixedIntrinsicView(40, 20)
      second = newFixedIntrinsicView(30, 32)
      third = newFixedIntrinsicView(10, 12)

    stack.spacing = 6.0
    stack.edgeInsets = initEdgeInsets(2.0, 3.0, 4.0, 5.0)
    stack.addArrangedSubview(first, second, third)

    check stack.arrangedSubviews == @[View(first), View(second), View(third)]
    check stack.intrinsicContentSize() == initIntrinsicSize(100.0, 38.0)

    stack.sizeToFit()
    stack.layoutSubtreeIfNeeded()

    check stack.frame().size == initSize(100.0, 38.0)
    check first.frame() == initRect(3.0, 2.0, 40.0, 32.0)
    check second.frame() == initRect(49.0, 2.0, 30.0, 32.0)
    check third.frame() == initRect(85.0, 2.0, 10.0, 32.0)

  test "vertical stack intrinsic size sums heights and spacing with insets":
    let
      stack = newStackView(laVertical, frame = initRect(0, 0, 1, 1))
      first = newFixedIntrinsicView(40, 20)
      second = newFixedIntrinsicView(30, 32)

    stack.spacing = 5.0
    stack.edgeInsets = initEdgeInsets(1.0, 2.0, 3.0, 4.0)
    stack.addArrangedSubview(first)
    stack.addArrangedSubview(second)

    check stack.intrinsicContentSize() == initIntrinsicSize(46.0, 61.0)

    stack.sizeToFit()
    stack.layoutSubtreeIfNeeded()

    check first.frame() == initRect(2.0, 1.0, 40.0, 20.0)
    check second.frame() == initRect(2.0, 26.0, 40.0, 32.0)

  test "cross-axis alignment can fill center and trail":
    let
      stack = newStackView(laHorizontal, frame = initRect(0, 0, 120, 50))
      fillChild = newFixedIntrinsicView(20, 10)
      centeredChild = newFixedIntrinsicView(20, 10)
      trailingChild = newFixedIntrinsicView(20, 10)

    stack.spacing = 0.0
    stack.addArrangedSubview(fillChild)
    stack.layoutSubtreeIfNeeded()
    check fillChild.frame() == initRect(0.0, 0.0, 120.0, 50.0)

    stack.removeArrangedSubview(fillChild)
    fillChild.removeFromSuperview()
    stack.alignment = svaCenter
    stack.addArrangedSubview(centeredChild)
    stack.layoutSubtreeIfNeeded()
    check centeredChild.frame() == initRect(0.0, 20.0, 120.0, 10.0)

    stack.removeArrangedSubview(centeredChild)
    centeredChild.removeFromSuperview()
    stack.alignment = svaTrailing
    stack.addArrangedSubview(trailingChild)
    stack.layoutSubtreeIfNeeded()
    check trailingChild.frame() == initRect(0.0, 40.0, 120.0, 10.0)

  test "fill equally distribution divides the main axis":
    let
      stack = newStackView(laHorizontal, frame = initRect(0, 0, 122, 24))
      first = newFixedIntrinsicView(10, 10)
      second = newFixedIntrinsicView(30, 10)

    stack.spacing = 2.0
    stack.distribution = svdFillEqually
    stack.addArrangedSubview(first)
    stack.addArrangedSubview(second)
    stack.layoutSubtreeIfNeeded()

    check first.frame() == initRect(0.0, 0.0, 60.0, 24.0)
    check second.frame() == initRect(62.0, 0.0, 60.0, 24.0)

  test "fill distribution expands lower hugging priority views first":
    let
      stack = newStackView(laHorizontal, frame = initRect(0, 0, 130, 20))
      field = newFixedIntrinsicView(40, 10)
      label = newFixedIntrinsicView(40, 10)

    stack.spacing = 10.0
    field.huggingPriority[dcol] = LayoutPriorityDefaultLow
    label.huggingPriority[dcol] = LayoutPriorityDefaultHigh
    stack.addArrangedSubview(field)
    stack.addArrangedSubview(label)
    stack.layoutSubtreeIfNeeded()

    check field.frame() == initRect(0.0, 0.0, 80.0, 20.0)
    check label.frame() == initRect(90.0, 0.0, 40.0, 20.0)

  test "arranged subview content changes invalidate stack and parent lazily":
    let
      root = newView(frame = initRect(0, 0, 300, 120))
      stack = newStackView(laHorizontal, frame = initRect(10, 10, 1, 1))
      button = newButton("Go", frame = initRect(0, 0, 20, 20))

    root.addSubview(stack)
    stack.addArrangedSubview(button)
    stack.sizeToFit()
    root.layoutSubtreeIfNeeded()
    root.setNeedsLayout(false)
    stack.setNeedsLayout(false)
    button.setNeedsLayout(false)

    let oldFrame = stack.frame()
    button.title = "A much longer title"

    check stack.frame() == oldFrame
    check root.needsLayout
    check stack.needsLayout
    check button.needsLayout

    stack.sizeToFit()
    root.layoutSubtreeIfNeeded()
    check stack.frame().size.width > oldFrame.size.width

  test "stack participates in deterministic constraint layout":
    let
      root = newView(frame = initRect(0, 0, 300, 100))
      stack = newStackView(laHorizontal, frame = initRect(0, 0, 1, 1))
      first = newFixedIntrinsicView(40, 20)
      second = newFixedIntrinsicView(30, 20)
      left = newLayoutConstraint(stack, latLeft, lrEqual, root, latLeft, constant = 20)
      right =
        newLayoutConstraint(stack, latRight, lrEqual, root, latRight, constant = -30)
      top = newLayoutConstraint(stack, latTop, lrEqual, root, latTop, constant = 10)
      height = newLayoutConstraint(stack, latHeight, constant = 40)

    stack.autoresizingMaskConstraints = false
    stack.spacing = 10.0
    root.addSubview(stack)
    stack.addArrangedSubview(first)
    stack.addArrangedSubview(second)
    activateConstraints([left, right, top, height])
    root.layoutSubtreeIfNeeded()

    check stack.frame() == initRect(20.0, 10.0, 250.0, 40.0)
    check first.frame() == initRect(0.0, 0.0, 125.0, 40.0)
    check second.frame() == initRect(135.0, 0.0, 115.0, 40.0)

  test "removing a subview removes it from arranged layout":
    let
      stack = newStackView(laHorizontal, frame = initRect(0, 0, 100, 20))
      first = newFixedIntrinsicView(20, 10)
      second = newFixedIntrinsicView(20, 10)

    stack.addArrangedSubview(first)
    stack.addArrangedSubview(second)
    first.removeFromSuperview()

    check stack.arrangedSubviews == @[View(second)]

    stack.layoutSubtreeIfNeeded()
    check second.frame() == initRect(0.0, 0.0, 100.0, 20.0)
