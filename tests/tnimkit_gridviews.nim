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

suite "nimkit grid views":
  test "intrinsic size uses max row and column tracks with spacing and insets":
    let
      grid = newGridView(frame = initRect(0, 0, 1, 1))
      first = newFixedIntrinsicView(40, 10)
      second = newFixedIntrinsicView(60, 20)
      third = newFixedIntrinsicView(30, 30)
      fourth = newFixedIntrinsicView(20, 12)

    grid.spacing[dcol] = 5.0
    grid.spacing[drow] = 7.0
    grid.edgeInsets = initEdgeInsets(1.0, 2.0, 3.0, 4.0)
    grid.addSubview(first, row = 0, col = 0)
    grid.addSubview(second, row = 0, col = 1)
    grid.addSubview(third, row = 1, col = 0)
    grid.addSubview(fourth, row = 1, col = 1)

    check grid.gridItems.len == 4
    check grid.spacing[dcol] == 5.0
    check grid.spacing[drow] == 7.0
    check grid.intrinsicContentSize() == initIntrinsicSize(111.0, 61.0)

    grid.sizeToFit()
    grid.layoutSubtreeIfNeeded()

    check grid.frame().size == initSize(111.0, 61.0)
    check first.frame() == initRect(2.0, 1.0, 40.0, 20.0)
    check second.frame() == initRect(47.0, 1.0, 60.0, 20.0)
    check third.frame() == initRect(2.0, 28.0, 40.0, 30.0)
    check fourth.frame() == initRect(47.0, 28.0, 60.0, 30.0)

  test "spanning subviews grow affected tracks":
    let
      grid = newGridView(frame = initRect(0, 0, 1, 1))
      header = newFixedIntrinsicView(120, 20)
      left = newFixedIntrinsicView(30, 10)
      right = newFixedIntrinsicView(40, 10)

    grid.spacing[dcol] = 10.0
    grid.spacing[drow] = 5.0
    grid.addSubview(header, row = 0, col = 0, colSpan = 2)
    grid.addSubview(left, row = 1, col = 0)
    grid.addSubview(right, row = 1, col = 1)

    check grid.intrinsicContentSize() == initIntrinsicSize(120.0, 35.0)

    grid.sizeToFit()
    grid.layoutSubtreeIfNeeded()

    check header.frame() == initRect(0.0, 0.0, 120.0, 20.0)
    check left.frame() == initRect(0.0, 25.0, 50.0, 10.0)
    check right.frame() == initRect(60.0, 25.0, 60.0, 10.0)

  test "directional alignment can center and trail inside filled tracks":
    let
      grid = newGridView(frame = initRect(0, 0, 200, 80))
      first = newFixedIntrinsicView(20, 10)
      second = newFixedIntrinsicView(20, 20)

    grid.spacing[dcol] = 0.0
    grid.spacing[drow] = 0.0
    grid.alignment[dcol] = gaCenter
    grid.alignment[drow] = gaTrailing
    grid.addSubview(first, row = 0, col = 0)
    grid.addSubview(second, row = 0, col = 1)
    grid.layoutSubtreeIfNeeded()

    check grid.alignment[dcol] == gaCenter
    check grid.alignment[drow] == gaTrailing
    check first.frame() == initRect(40.0, 70.0, 20.0, 10.0)
    check second.frame() == initRect(140.0, 60.0, 20.0, 20.0)

  test "hidden grid subviews are omitted from intrinsic size and layout":
    let
      grid = newGridView(frame = initRect(0, 0, 1, 1))
      visible = newFixedIntrinsicView(40, 20)
      hidden = newFixedIntrinsicView(100, 50)

    grid.addSubview(visible, row = 0, col = 0)
    grid.addSubview(hidden, row = 0, col = 1)
    hidden.hidden = true

    check grid.intrinsicContentSize() == initIntrinsicSize(40.0, 20.0)

    grid.sizeToFit()
    grid.layoutSubtreeIfNeeded()
    check visible.frame() == initRect(0.0, 0.0, 40.0, 20.0)
    check hidden.frame() == initRect(0.0, 0.0, 100.0, 50.0)

  test "grid content changes invalidate grid and parent lazily":
    let
      root = newView(frame = initRect(0, 0, 300, 120))
      grid = newGridView(frame = initRect(10, 10, 1, 1))
      label = newTextField("Name", frame = initRect(0, 0, 1, 1))
      field = newTextField("Ada", frame = initRect(0, 0, 1, 1))

    label.editable = false
    label.selectable = false
    root.addSubview(grid)
    grid.addSubview(label, row = 0, col = 0)
    grid.addSubview(field, row = 0, col = 1)
    grid.sizeToFit()
    root.layoutSubtreeIfNeeded()
    root.needsLayout = false
    grid.needsLayout = false
    field.needsLayout = false

    let oldFrame = grid.frame()
    field.text = "A much longer field value"

    check grid.frame() == oldFrame
    check root.needsLayout
    check grid.needsLayout
    check field.needsLayout

    grid.sizeToFit()
    root.layoutSubtreeIfNeeded()
    check grid.frame().size.width > oldFrame.size.width

  test "grid participates in solver constraint layout":
    let
      root = newView(frame = initRect(0, 0, 300, 100))
      grid = newGridView(frame = initRect(0, 0, 1, 1))
      first = newFixedIntrinsicView(40, 20)
      second = newFixedIntrinsicView(30, 20)
      left = newLayoutConstraint(grid, atLeft, lrEqual, root, atLeft, constant = 20)
      right = newLayoutConstraint(grid, atRight, lrEqual, root, atRight, constant = -30)
      top = newLayoutConstraint(grid, atTop, lrEqual, root, atTop, constant = 10)
      height = newLayoutConstraint(grid, atHeight, constant = 40)

    grid.autoresizingMaskConstraints = false
    grid.spacing[dcol] = 10.0
    root.addSubview(grid)
    grid.addSubview(first, row = 0, col = 0)
    grid.addSubview(second, row = 0, col = 1)
    activateConstraints([left, right, top, height])
    root.layoutSubtreeIfNeeded()

    check grid.frame() == initRect(20.0, 10.0, 250.0, 40.0)
    check first.frame() == initRect(0.0, 0.0, 125.0, 40.0)
    check second.frame() == initRect(135.0, 0.0, 115.0, 40.0)

  test "removing a grid subview removes its placement":
    let
      grid = newGridView(frame = initRect(0, 0, 100, 20))
      first = newFixedIntrinsicView(20, 10)
      second = newFixedIntrinsicView(20, 10)

    grid.addSubview(first, row = 0, col = 0)
    grid.addSubview(second, row = 0, col = 1)
    first.removeFromSuperview()

    check grid.gridItems ==
      @[GridItem(view: View(second), row: 0, col: 1, rowSpan: 1, colSpan: 1)]

    grid.layoutSubtreeIfNeeded()
    check second.frame() == initRect(44.0, 0.0, 56.0, 20.0)
