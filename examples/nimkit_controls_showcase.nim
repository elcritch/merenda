import merenda/nimkit

import sigils/selectors

proc stateName(state: ButtonState): string =
  case state
  of bsOff: "Off"
  of bsOn: "On"
  of bsMixed: "Mixed"

proc configureLabel(label: TextField, color: Color) =
  label.setEditable(false)
  label.setSelectable(false)
  label.setTextColor(color)

proc configureHeader(label: TextField) =
  label.configureLabel(initColor(0.10, 0.18, 0.32))
  label.setStyleClasses(["showcase-header"])

proc showcaseAppearance(): Appearance =
  result = initAppearance()
  let
    titleStyle = initStyleSelector(srTextField, classes = @["showcase-title"])
    headerStyle = initStyleSelector(srTextField, classes = @["showcase-header"])
    statusStyle = initStyleSelector(srTextField, classes = @["showcase-status"])

  result[titleStyle, StyleFill] = initColor(0.88, 0.92, 0.98)
  result[titleStyle, StyleBorderColor] = initColor(0.62, 0.70, 0.84)
  result[titleStyle, StyleBorderWidth] = 1.0
  result[titleStyle, StyleCornerRadius] = 6.0
  result[titleStyle, StyleTextColor] = initColor(0.09, 0.14, 0.26)
  result[titleStyle, StyleTextInsets] = initEdgeInsets(0.0, 12.0)

  result[headerStyle, StyleFill] = initColor(0.82, 0.88, 0.96)
  result[headerStyle, StyleBorderColor] = initColor(0.82, 0.88, 0.96)
  result[headerStyle, StyleBorderWidth] = 0.0
  result[headerStyle, StyleCornerRadius] = 5.0
  result[headerStyle, StyleTextColor] = initColor(0.10, 0.18, 0.32)
  result[headerStyle, StyleTextInsets] = initEdgeInsets(0.0, 10.0)

  result[statusStyle, StyleFill] = initColor(0.90, 0.96, 0.92)
  result[statusStyle, StyleBorderColor] = initColor(0.68, 0.82, 0.72)
  result[statusStyle, StyleBorderWidth] = 1.0
  result[statusStyle, StyleCornerRadius] = 6.0
  result[statusStyle, StyleTextColor] = initColor(0.09, 0.27, 0.18)
  result[statusStyle, StyleTextInsets] = initEdgeInsets(0.0, 10.0)

let
  app = sharedApplication()
  window = newWindow("Nimkit Controls Showcase", frame = initRect(140, 140, 760, 500))
  root = newView()

  layout = newStackView(laVertical)
  bodyRow = newStackView(laHorizontal)
  inputColumn = newStackView(laVertical)
  buttonRow = newStackView(laHorizontal)
  choiceColumn = newStackView(laVertical)
  popupColumn = newStackView(laVertical)

  title = newTextField("Nimkit Controls")
  summary = newTextField("")

  inputTitle = newTextField("Text Fields")
  nameField = newTextField("Ada")
  noteField = newTextField("Building UI")

  actionTitle = newTextField("Buttons")
  pushButton = newButton("Push")
  toggleButton = newButton("Toggle Off")
  actionCountLabel = newTextField("Push count: 0")

  choiceTitle = newTextField("Choices")
  downloads = newCheckBox("Enable downloads")
  notifications = newCheckBox("Show notifications")
  sync = newCheckBox("Sync over cellular")

  sizeTitle = newTextField("Radio Buttons")
  small = newRadioButton("Small")
  medium = newRadioButton("Medium")
  large = newRadioButton("Large")

  popupTitle = newTextField("Combo Boxes")
  priority = newComboBox(["Low", "Medium", "High"])
  color = newComboBox(["Red", "Green", "Blue"])

  pushAction = actionSelector("showcasePush")
  toggleAction = actionSelector("showcaseToggle")
  choiceAction = actionSelector("showcaseChoiceChanged")
  radioAction = actionSelector("showcaseRadioChanged")
  comboAction = actionSelector("showcaseComboChanged")

var pushCount = 0

proc selectedSize(): string =
  if small.state == bsOn:
    "Small"
  elif medium.state == bsOn:
    "Medium"
  elif large.state == bsOn:
    "Large"
  else:
    "None"

proc updateSummary() =
  summary.setStringValue(
    nameField.stringValue & " / " & noteField.stringValue & " / Toggle: " &
      toggleButton.state.stateName & " / Downloads: " & downloads.state.stateName &
      " / Size: " & selectedSize() & " / Priority: " & priority.stringValue &
      " / Color: " & color.stringValue
  )

proc updateToggleTitle() =
  toggleButton.setTitle("Toggle " & toggleButton.state.stateName)

proc onTextDidChange(sender: DynamicAgent) =
  if sender == DynamicAgent(nameField) or sender == DynamicAgent(noteField):
    updateSummary()

proc onPush(sender: DynamicAgent) =
  if not sender.isNil:
    inc pushCount
    actionCountLabel.setStringValue("Push count: " & $pushCount)
    updateSummary()

proc onToggle(sender: DynamicAgent) =
  if not sender.isNil:
    updateToggleTitle()
    updateSummary()

proc onChoiceChanged(sender: DynamicAgent) =
  if not sender.isNil:
    updateSummary()

root.setBackgroundColor(initColor(0.95, 0.96, 0.98))
title.setAlignment(taCenter)
title.setStyleClasses(["showcase-title"])
root.setAppearance(showcaseAppearance())

title.configureLabel(initColor(0.09, 0.14, 0.26))
for label in [inputTitle, actionTitle, choiceTitle, sizeTitle, popupTitle]:
  label.configureHeader()

for label in [summary, actionCountLabel]:
  label.configureLabel(initColor(0.14, 0.18, 0.28))

summary.setStyleClasses(["showcase-status"])
summary.setTextColor(initColor(0.10, 0.28, 0.20))
actionCountLabel.setTextColor(initColor(0.10, 0.28, 0.20))

for field in [nameField, noteField]:
  field.setDelegate(newActionTarget(textDidChange(), onTextDidChange))

pushButton.setTarget(newActionTarget(pushAction, onPush))
pushButton.setAction(pushAction)

toggleButton.setButtonType(btToggle)
toggleButton.setAllowsMixedState(true)
toggleButton.setTarget(newActionTarget(toggleAction, onToggle))
toggleButton.setAction(toggleAction)

sync.setAllowsMixedState(true)
sync.setState(bsMixed)

let choiceTarget = newActionTarget(choiceAction, onChoiceChanged)
for checkbox in [downloads, notifications, sync]:
  checkbox.setTarget(choiceTarget)
  checkbox.setAction(choiceAction)

medium.setState(bsOn)

let radioTarget = newActionTarget(radioAction, onChoiceChanged)
for radio in [small, medium, large]:
  radio.setTarget(radioTarget)
  radio.setAction(radioAction)

priority.selectItemAtIndex(1)
color.selectItemAtIndex(0)

let comboTarget = newActionTarget(comboAction, onChoiceChanged)
for combo in [priority, color]:
  combo.setTarget(comboTarget)
  combo.setAction(comboAction)

layout.setSpacing(16.0)
layout.setAlignment(svaFill)

bodyRow.setSpacing(28.0)
bodyRow.setAlignment(svaFill)
bodyRow.setDistribution(svdFill)

for column in [inputColumn, choiceColumn, popupColumn]:
  column.setSpacing(10.0)
  column.setAlignment(svaFill)

buttonRow.setSpacing(8.0)
buttonRow.setAlignment(svaFill)
buttonRow.setDistribution(svdFillEqually)

buttonRow.addArrangedSubview(pushButton)
buttonRow.addArrangedSubview(toggleButton)

inputColumn.addArrangedSubview(inputTitle)
inputColumn.addArrangedSubview(nameField)
inputColumn.addArrangedSubview(noteField)
inputColumn.addArrangedSubview(actionTitle)
inputColumn.addArrangedSubview(buttonRow)
inputColumn.addArrangedSubview(actionCountLabel)

choiceColumn.addArrangedSubview(choiceTitle)
choiceColumn.addArrangedSubview(downloads)
choiceColumn.addArrangedSubview(notifications)
choiceColumn.addArrangedSubview(sync)
choiceColumn.addArrangedSubview(sizeTitle)
choiceColumn.addArrangedSubview(small)
choiceColumn.addArrangedSubview(medium)
choiceColumn.addArrangedSubview(large)

popupColumn.addArrangedSubview(popupTitle)
popupColumn.addArrangedSubview(priority)
popupColumn.addArrangedSubview(color)

bodyRow.addArrangedSubview(inputColumn)
bodyRow.addArrangedSubview(choiceColumn)
bodyRow.addArrangedSubview(popupColumn)

layout.addArrangedSubview(title)
layout.addArrangedSubview(bodyRow)
layout.addArrangedSubview(summary)

root.addSubview(layout)
activateConstraints(
  [
    newLayoutConstraint(layout, latLeft, lrEqual, root, latLeft, constant = 24.0),
    newLayoutConstraint(layout, latTop, lrEqual, root, latTop, constant = 22.0),
    newLayoutConstraint(layout, latRight, lrEqual, root, latRight, constant = -24.0),
  ]
)

updateToggleTitle()
updateSummary()
window.setContentView(root)
discard window.makeFirstResponder(nameField)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
