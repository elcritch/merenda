import std/[unicode, unittest]

import figdraw/fignodes

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

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add(rune.toUTF8())

suite "nimkit boxes":
  test "group boxes compute intrinsic size from title content and theme metrics":
    var appearance = initAppearance()
    appearance[srBox, StylePadding] = initEdgeInsets(10.0, 12.0, 14.0, 16.0)
    appearance[srBox, StyleTitleHeight] = 20.0
    appearance[srBox, StyleTitleGap] = 5.0
    appearance[srBox, StyleBorderWidth] = 2.0
    appearance[srBox, StyleTextInsets] = initEdgeInsets(0.0, 6.0)

    let
      box = newBox("Options", frame = initRect(0.0, 0.0, 200.0, 120.0))
      content = newFixedIntrinsicView(80.0, 30.0)

    box.appearance = appearance
    box.contentView = content

    let intrinsic = box.intrinsicContentSize()
    check intrinsic.hasWidth()
    check intrinsic.height == 83.0

    box.layoutSubtreeIfNeeded()
    check box.contentRect() == initRect(12.0, 35.0, 172.0, 71.0)
    check content.frame() == box.contentRect()

  test "content subviews are hosted inside the content view":
    let
      box = newBox("Host", frame = initRect(0.0, 0.0, 160.0, 90.0))
      child = newFixedIntrinsicView(20.0, 10.0)

    box.addContentSubview(child)

    check not box.contentView().isNil
    check child.superview == box.contentView()
    check box.contentView().superview == box

  test "separator boxes expose one-axis intrinsic size":
    var appearance = initAppearance()
    appearance[srBox, StyleSeparatorThickness] = 3.0

    let
      horizontal = newSeparatorBox(laHorizontal)
      vertical = newSeparatorBox(laVertical)

    horizontal.appearance = appearance
    vertical.appearance = appearance

    check horizontal.intrinsicContentSize() == initIntrinsicSize(NoIntrinsicMetric, 3.0)
    check vertical.intrinsicContentSize() == initIntrinsicSize(3.0, NoIntrinsicMetric)

  test "box rendering uses theme fill border title and separator metrics":
    let
      box = newBox("Network", frame = initRect(0.0, 0.0, 180.0, 90.0))
      separator = newSeparatorBox(laVertical, frame = initRect(0.0, 0.0, 12.0, 80.0))
      root = newView(frame = initRect(0.0, 0.0, 220.0, 120.0))
      fillColor = initColor(0.91, 0.93, 0.96, 1.0)
      borderColor = initColor(0.21, 0.29, 0.37, 1.0)

    var appearance = initAppearance()
    appearance[srBox, StyleFill] = fillColor
    appearance[srBox, StyleBorderColor] = borderColor
    appearance[srBox, StyleBorderWidth] = 3.0
    appearance[srBox, StyleTitleHeight] = 20.0
    appearance[srBox, StyleTitleGap] = 4.0
    appearance[srBox, StyleSeparatorThickness] = 4.0

    root.addSubview(box)
    root.addSubview(separator)

    let list = buildRenders(root, appearance)[DefaultDrawLevel]

    var
      foundBoxBorder = false
      foundTitle = false
      foundSeparator = false

    for node in list.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == fillColor.rgba:
        foundBoxBorder = true
        check node.stroke.weight == 3.0
        check node.stroke.fill.kind == flColor
        check node.stroke.fill.color == borderColor.rgba

      if node.kind == nkText and node.renderedText() == "Network":
        foundTitle = true

      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == borderColor.rgba and node.screenBox.w == 4.0 and
          node.screenBox.h == 80.0:
        foundSeparator = true

    check foundBoxBorder
    check foundTitle
    check foundSeparator

  test "boxes expose group and separator accessibility semantics":
    let
      box = newBox("Security")
      button = newButton("Apply")
      separator = newSeparatorBox()

    box.addContentSubview(button)

    check box.isAccessibilityElement()
    check box.accessibilityRole() == arGroup
    check box.accessibilityLabel() == "Security"
    check box.accessibilityChildren() == @[View(button)]

    check separator.isAccessibilityElement()
    check separator.accessibilityRole() == arSeparator
    check separator.accessibilityChildren().len == 0
