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
  window = newWindow(140, 140, 760, 500, "Nimkit Controls Showcase")
  root = newView(0, 0, 760, 500)

  title = newTextField(24, 22, 420, 34, "Nimkit Controls")
  summary = newTextField(24, 448, 710, 28, "")

  inputTitle = newTextField(24, 78, 240, 26, "Text Fields")
  nameField = newTextField(24, 116, 250, 30, "Ada")
  noteField = newTextField(24, 154, 250, 30, "Building UI")

  actionTitle = newTextField(24, 216, 240, 26, "Buttons")
  pushButton = newButton(24, 254, 118, 36, "Push")
  toggleButton = newButton(156, 254, 118, 36, "Toggle Off")
  actionCountLabel = newTextField(24, 306, 250, 26, "Push count: 0")

  choiceTitle = newTextField(326, 78, 260, 26, "Choices")
  downloads = newCheckBox(326, 116, 250, 26, "Enable downloads")
  notifications = newCheckBox(326, 150, 250, 26, "Show notifications")
  sync = newCheckBox(326, 184, 250, 26, "Sync over cellular")

  sizeTitle = newTextField(326, 238, 260, 26, "Radio Buttons")
  small = newRadioButton(326, 276, 150, 26, "Small")
  medium = newRadioButton(326, 310, 150, 26, "Medium")
  large = newRadioButton(326, 344, 150, 26, "Large")

  popupTitle = newTextField(560, 78, 150, 26, "Combo Boxes")
  priority = newComboBox(560, 116, 150, 28, ["Low", "Medium", "High"])
  color = newComboBox(560, 154, 150, 28, ["Red", "Green", "Blue"])

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

for view in [
  title, inputTitle, nameField, noteField, actionTitle, pushButton, toggleButton,
  actionCountLabel, choiceTitle, downloads, notifications, sync, sizeTitle, small,
  medium, large, popupTitle, priority, color, summary,
]:
  root.addSubview(view)

updateToggleTitle()
updateSummary()
window.setContentView(root)
discard window.makeFirstResponder(nameField)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
