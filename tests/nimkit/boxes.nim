import std/[unicode, unittest]

import figdraw

import sigils/core
import sigils/selectors

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes

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

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add(rune.toUTF8())

type BoxDemoLayoutFixture = object
  window: Window
  root: View
  layout: StackView
  status: Label
  serverField: TextField
  portField: TextField
  modeChoice: ComboBox
  syncCheck: Button
  notificationsCheck: Button
  connectionBox: Box
  summaryBox: Box
  splitBox: Box
  splitSeparator: Box

type NamedBoxDemoFrame = object
  name: string
  frame: nimkitTypes.Rect

proc boxDemoStack(): StackView =
  result = newStackView(laVertical)
  result.spacing = 10.0
  result.alignment = svaFill
  result.distribution = svdNatural

proc boxDemoFieldRow(labelText: string, control: View): StackView =
  result = newStackView(laHorizontal)
  result.spacing = 12.0
  result.alignment = svaCenter
  result.distribution = svdFill
  control.setHuggingPriority(LayoutPriorityLow, laHorizontal)
  result.addArrangedSubview(newFormLabel(labelText), control)

proc boxDemoGroupBox(title: string, content: View): Box =
  result = newGroupBox(title)
  result.contentView = content

proc boxDemoUntitledBox(content: View): Box =
  result = newBox()
  result.contentView = content

proc updateBoxDemoStatus(fixture: BoxDemoLayoutFixture) =
  fixture.status.text =
    "Mode: " & fixture.modeChoice.stringValue & " / Sync: " &
    (if fixture.syncCheck.state == bsOn: "on" else: "off") & " / Notifications: " &
    (if fixture.notificationsCheck.state == bsOn: "on" else: "off")

proc newBoxDemoLayoutFixture(): BoxDemoLayoutFixture =
  const DemoWindowWidth = 640.0'f32
  let
    title = newTitleLabel("Box Widget")
    connectionContent = boxDemoStack()
    connectionButtonRow = newStackView(laHorizontal)
    summaryContent = boxDemoStack()
    splitContent = newStackView(laHorizontal)
    inspectorContent = boxDemoStack()
    previewContent = boxDemoStack()
    applyButton = newButton("Apply")
    resetButton = newButton("Reset")

  result.window =
    newWindow("NimKit Box Demo", frame = rect(0, 0, DemoWindowWidth, 360.0))
  result.root = newView()
  result.layout = newStackView(laVertical)
  result.status = newStatusLabel(
    "Group boxes expose grouped content; separator boxes expose separator accessibility."
  )
  result.serverField = newTextField("merenda.local")
  result.portField = newTextField("443")
  result.modeChoice = newComboBox(["Automatic", "Manual", "Offline"])
  result.syncCheck = newCheckBox("Sync changes")
  result.notificationsCheck = newCheckBox("Show notifications")
  result.connectionBox = boxDemoGroupBox("Connection", connectionContent)
  result.summaryBox = boxDemoUntitledBox(summaryContent)
  result.splitSeparator = newVerticalSeparator()
  result.splitBox = boxDemoGroupBox("Vertical Separator", splitContent)

  result.layout.spacing = 14.0
  result.layout.alignment = svaFill
  result.layout.distribution = svdNatural

  connectionButtonRow.spacing = 8.0
  connectionButtonRow.alignment = svaCenter
  connectionButtonRow.distribution = svdFill
  connectionButtonRow.addFlexibleSpacer()
  connectionButtonRow.addArrangedSubview(resetButton, applyButton)

  connectionContent.addArrangedSubview(
    boxDemoFieldRow("Server", result.serverField),
    boxDemoFieldRow("Port", result.portField),
    boxDemoFieldRow("Mode", result.modeChoice),
    newHorizontalSeparator(),
    result.syncCheck,
    result.notificationsCheck,
    connectionButtonRow,
  )

  summaryContent.addArrangedSubview(
    newHeadingLabel("Untitled Group Box"),
    newStatusLabel("This box uses the same content-hosting path without a title band."),
    newHorizontalSeparator(),
    newStatusLabel(
      "The separator above is a Box with the separator accessibility role."
    ),
  )

  inspectorContent.addArrangedSubview(
    newHeadingLabel("Inspector"),
    newStatusLabel("Left content is hosted by a stack view inside the group box."),
    newButton("Reveal"),
  )

  previewContent.addArrangedSubview(
    newHeadingLabel("Preview"),
    newStatusLabel("The vertical rule is a separator Box arranged between panes."),
    newButton("Refresh"),
  )

  splitContent.spacing = 14.0
  splitContent.alignment = svaFill
  splitContent.distribution = svdFill
  inspectorContent.setHuggingPriority(LayoutPriorityLow, laHorizontal)
  previewContent.setHuggingPriority(LayoutPriorityLow, laHorizontal)
  result.splitSeparator.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
  result.splitSeparator.setCompressionPriority(LayoutPriorityRequired, laHorizontal)
  splitContent.addArrangedSubview(
    inspectorContent, result.splitSeparator, previewContent
  )

  result.modeChoice.selectItemAtIndex(0)
  result.syncCheck.state = bsOn
  result.notificationsCheck.state = bsOff

  result.layout.addArrangedSubview(
    title, result.status, result.connectionBox, result.summaryBox, result.splitBox
  )
  result.root.addSubview(result.layout)
  result.layout.pinEdges(
    toGuide = result.root.contentLayoutGuide(insets(22.0, 24.0, 0.0, 24.0)),
    edges = {leLeft, leTop, leRight},
  )
  result.updateBoxDemoStatus()
  result.window.setContentView(result.root)
  discard result.window.makeFirstResponder(result.serverField)
  discard result.window.buildRenders()

proc trackedBoxDemoFrames(fixture: BoxDemoLayoutFixture): seq[NamedBoxDemoFrame] =
  @[
    NamedBoxDemoFrame(name: "layout", frame: fixture.layout.frame),
    NamedBoxDemoFrame(name: "status", frame: fixture.status.frame),
    NamedBoxDemoFrame(name: "connectionBox", frame: fixture.connectionBox.frame),
    NamedBoxDemoFrame(
      name: "connectionContent", frame: fixture.connectionBox.contentView().frame
    ),
    NamedBoxDemoFrame(name: "serverField", frame: fixture.serverField.frame),
    NamedBoxDemoFrame(name: "portField", frame: fixture.portField.frame),
    NamedBoxDemoFrame(name: "modeChoice", frame: fixture.modeChoice.frame),
    NamedBoxDemoFrame(name: "syncCheck", frame: fixture.syncCheck.frame),
    NamedBoxDemoFrame(
      name: "notificationsCheck", frame: fixture.notificationsCheck.frame
    ),
    NamedBoxDemoFrame(name: "summaryBox", frame: fixture.summaryBox.frame),
    NamedBoxDemoFrame(
      name: "summaryContent", frame: fixture.summaryBox.contentView().frame
    ),
    NamedBoxDemoFrame(name: "splitBox", frame: fixture.splitBox.frame),
    NamedBoxDemoFrame(name: "splitContent", frame: fixture.splitBox.contentView().frame),
    NamedBoxDemoFrame(name: "splitSeparator", frame: fixture.splitSeparator.frame),
  ]

proc clickView(window: Window, view: View): bool =
  let point = view.pointToWindow(initPoint(8.0, 8.0))
  window.clickAt(point)

suite "nimkit boxes":
  test "box protocol exposes selector-backed properties":
    let box = newBox("Original")

    check box.conformsTo(BoxProtocol)
    check box.boxTitle == "Original"
    check box.title == "Original"

    let swizzledTitle: DynamicMethod = proc(
        self: DynamicAgent, invocation: var Invocation
    ) =
      check Box(self) == box
      invocation.setResult("Swizzled")

    box.replaceMethod(boxTitle(), swizzledTitle)
    check box.boxTitle == "Swizzled"
    check box.title == "Swizzled"

  test "group boxes compute intrinsic size from title content and theme metrics":
    var appearance = initAppearance()
    appearance[srBox, StylePadding] = insets(10.0, 12.0, 14.0, 16.0)
    appearance[srBox, StyleTitleHeight] = 20.0
    appearance[srBox, StyleTitleGap] = 5.0
    appearance[srBox, StyleBorderWidth] = 2.0
    appearance[srBox, StyleTextInsets] = insets(0.0, 6.0)

    let
      box = newBox("Options", frame = rect(0.0, 0.0, 200.0, 120.0))
      content = newFixedIntrinsicView(80.0, 30.0)

    box.appearance = appearance
    box.contentView = content

    let intrinsic = box.intrinsicContentSize()
    check intrinsic.hasWidth()
    check intrinsic.height == 83.0

    box.layoutSubtreeIfNeeded()
    check box.contentRect() == rect(14.0, 37.0, 168.0, 67.0)
    check content.frame() == box.contentRect()

  test "content subviews are hosted inside the content view":
    let
      box = newBox("Host", frame = rect(0.0, 0.0, 160.0, 90.0))
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
      box = newBox("Network", frame = rect(0.0, 0.0, 180.0, 90.0))
      separator = newSeparatorBox(laVertical, frame = rect(0.0, 0.0, 12.0, 80.0))
      root = newView(frame = rect(0.0, 0.0, 220.0, 120.0))
      fillColor = color(0.91, 0.93, 0.96, 1.0)
      borderColor = color(0.21, 0.29, 0.37, 1.0)

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

  test "box demo layout stays stable while typing and clicking checkboxes":
    let fixture = newBoxDemoLayoutFixture()
    let baseline = fixture.trackedBoxDemoFrames()

    for ch in ["x", "y", "z"]:
      check fixture.window.dispatchKeyDown(
        KeyEvent(text: ch, key: keyX, keyCode: keyX.ord)
      )
      discard fixture.window.buildRenders()
      let frames = fixture.trackedBoxDemoFrames()
      for index, item in frames:
        check item == baseline[index]

    check fixture.window.clickView(fixture.syncCheck)
    discard fixture.window.buildRenders()
    var frames = fixture.trackedBoxDemoFrames()
    for index, item in frames:
      check item == baseline[index]

    check fixture.window.clickView(fixture.notificationsCheck)
    discard fixture.window.buildRenders()
    frames = fixture.trackedBoxDemoFrames()
    for index, item in frames:
      check item == baseline[index]
