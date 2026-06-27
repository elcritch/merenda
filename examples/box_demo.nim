import merenda/nimkit

import sigils/selectors

const DemoWindowWidth = 640.0'f32

proc boxStack(): StackView =
  result = newStackView(laVertical)
  result.spacing = 10.0
  result.alignment = svaFill
  result.distribution = svdNatural

proc fieldRow(labelText: string, control: View): StackView =
  result = newStackView(laHorizontal)
  result.spacing = 12.0
  result.alignment = svaCenter
  result.distribution = svdFill
  control.setHuggingPriority(LayoutPriorityLow, laHorizontal)
  result.addArrangedSubview(newFormLabel(labelText), control)

proc groupBox(title: string, content: View): Box =
  result = newGroupBox(title)
  result.contentView = content

proc untitledBox(content: View): Box =
  result = newBox()
  result.contentView = content

let
  app = sharedApplication()
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("Box Widget")
  status = newStatusLabel(
    "Group boxes expose grouped content; separator boxes expose separator accessibility."
  )

  serverField = newTextField("merenda.local")
  portField = newTextField("443")
  modeChoice = newComboBox(["Automatic", "Manual", "Offline"])
  syncCheck = newCheckBox("Sync changes")
  notificationsCheck = newCheckBox("Show notifications")
  applyButton = newButton("Apply")
  resetButton = newButton("Reset")
  applyAction = actionSelector("boxDemoApply")
  resetAction = actionSelector("boxDemoReset")

  connectionContent = boxStack()
  connectionButtonRow = newStackView(laHorizontal)
  connectionBox = groupBox("Connection", connectionContent)

  summaryContent = boxStack()
  summaryBox = untitledBox(summaryContent)

  splitContent = newStackView(laHorizontal)
  inspectorContent = boxStack()
  previewContent = boxStack()
  splitSeparator = newVerticalSeparator()
  splitBox = groupBox("Vertical Separator", splitContent)

proc updateStatus(sender: DynamicAgent) =
  discard sender
  status.text =
    "Mode: " & modeChoice.stringValue & " / Sync: " &
    (if syncCheck.state == bsOn: "on" else: "off") & " / Notifications: " &
    (if notificationsCheck.state == bsOn: "on" else: "off")

proc resetDemo(sender: DynamicAgent) =
  discard sender
  serverField.stringValue = "merenda.local"
  portField.stringValue = "443"
  modeChoice.selectItemAtIndex(0)
  syncCheck.state = bsOn
  notificationsCheck.state = bsOff
  updateStatus(nil)

layout.spacing = 14.0
layout.alignment = svaFill
layout.distribution = svdNatural

connectionButtonRow.spacing = 8.0
connectionButtonRow.alignment = svaCenter
connectionButtonRow.distribution = svdFill
connectionButtonRow.addFlexibleSpacer()
connectionButtonRow.addArrangedSubview(resetButton, applyButton)

connectionContent.addArrangedSubview(
  fieldRow("Server", serverField),
  fieldRow("Port", portField),
  fieldRow("Mode", modeChoice),
  newHorizontalSeparator(),
  syncCheck,
  notificationsCheck,
  connectionButtonRow,
)

summaryContent.addArrangedSubview(
  newHeadingLabel("Untitled Group Box"),
  newStatusLabel("This box uses the same content-hosting path without a title band."),
  newHorizontalSeparator(),
  newStatusLabel("The separator above is a Box with the separator accessibility role."),
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
splitSeparator.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
splitSeparator.setCompressionPriority(LayoutPriorityRequired, laHorizontal)
splitContent.addArrangedSubview(inspectorContent, splitSeparator, previewContent)

modeChoice.selectItemAtIndex(0)
syncCheck.state = bsOn
notificationsCheck.state = bsOff

applyButton.target = newActionTarget(applyAction, updateStatus)
applyButton.action = applyAction
resetButton.target = newActionTarget(resetAction, resetDemo)
resetButton.action = resetAction

layout.addArrangedSubview(title, status, connectionBox, summaryBox, splitBox)
root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(22.0, 24.0, 0.0, 24.0)),
  edges = {leLeft, leTop, leRight},
)

let
  minimumWindowHeight =
    layout
    .resolvedIntrinsicContentSize()
    .resolveIntrinsicSize(initSize(DemoWindowWidth, 0.0)).height + 50
  window = newWindow(
    "NimKit Box Demo", frame = initRect(150, 130, DemoWindowWidth, minimumWindowHeight)
  )

window.minSize = initSize(DemoWindowWidth, minimumWindowHeight)
updateStatus(nil)
window.setContentView(root)
discard window.makeFirstResponder(serverField)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
