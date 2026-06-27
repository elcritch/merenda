import std/strutils

import merenda/nimkit

import sigils/core
import sigils/selectors

proc stateName(state: ButtonState): string =
  case state
  of bsOff: "Off"
  of bsOn: "On"
  of bsMixed: "Mixed"

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
  switchRow = newStackView(laHorizontal)

  title = newTitleLabel("Nimkit Controls")
  summary = newStatusLabel("")

  inputTitle = newHeadingLabel("Text Fields")
  nameField = newTextField("Ada")
  noteField = newTextField("Building UI")

  actionTitle = newHeadingLabel("Buttons")
  pushButton = newButton("Push")
  toggleButton = newButton("Toggle Off")
  actionCountLabel = newStatusLabel("Push count: 0")

  choiceTitle = newHeadingLabel("Choices")
  downloads = newCheckBox("Enable downloads")
  notifications = newCheckBox("Show notifications")
  sync = newCheckBox("Sync over cellular")

  sizeTitle = newHeadingLabel("Radio Buttons")
  small = newRadioButton("Small")
  medium = newRadioButton("Medium")
  large = newRadioButton("Large")

  popupTitle = newHeadingLabel("Combo Boxes")
  priority = newComboBox(["Low", "Medium", "High"])
  color = newComboBox(["Red", "Green", "Blue"])
  sliderTitle = newHeadingLabel("Slider")
  volumeSlider = newSlider(0.0, 100.0, 42.0)
  volumeLabel = newStatusLabel("")
  stepperTitle = newHeadingLabel("Stepper")
  countRow = newStackView(laHorizontal)
  countField = newTextField("")
  countStepper = newStepper(0.0, 12.0, 2.0, increment = 1.0)
  switchTitle = newHeadingLabel("Switch Button")
  powerSwitch = newSwitchButton(true)
  powerSwitchLabel = newStatusLabel("")

  pushAction = actionSelector("showcasePush")
  toggleAction = actionSelector("showcaseToggle")
  choiceAction = actionSelector("showcaseChoiceChanged")
  radioAction = actionSelector("showcaseRadioChanged")
  comboAction = actionSelector("showcaseComboChanged")
  stepperAction = actionSelector("showcaseStepperChanged")
  contextToggleAction = actionSelector("showcaseContextToggleButton")
  contextDownloadsAction = actionSelector("showcaseContextToggleDownloads")
  resetAction = actionSelector("showcaseResetControls")

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
  summary.text =
    nameField.stringValue & " / " & noteField.stringValue & " / Toggle: " &
    toggleButton.state.stateName & " / Downloads: " & downloads.state.stateName &
    " / Size: " & selectedSize() & " / Priority: " & priority.stringValue & " / Color: " &
    color.stringValue & " / Volume: " & $int(volumeSlider.value) & " / Count: " &
    countStepper.formattedValue & " / Power: " & powerSwitch.state.stateName

proc updateToggleTitle() =
  toggleButton.title = "Toggle " & toggleButton.state.stateName

proc updateVolumeLabel(slider: Slider) {.slot.} =
  volumeLabel.text = "Volume: " & $int(slider.value)

proc updateSliderSummary(slider: Slider, sender: DynamicAgent) {.slot.} =
  updateSummary()

proc syncCountField() =
  countField.text = countStepper.formattedValue

proc parseCountField() =
  try:
    countStepper.value = parseFloat(countField.stringValue).float32
    syncCountField()
  except ValueError:
    discard
  updateSummary()

proc onStepperChanged(sender: DynamicAgent) =
  if sender == DynamicAgent(countStepper):
    syncCountField()
    updateSummary()

proc updatePowerSwitchLabel(switchButton: SwitchButton) {.slot.} =
  powerSwitchLabel.text = "Power: " & switchButton.state.stateName

proc updatePowerSwitchSummary(
    switchButton: SwitchButton, sender: DynamicAgent
) {.slot.} =
  updateSummary()

proc onTextDidChange(field: TextField, sender: DynamicAgent) {.slot.} =
  if sender == DynamicAgent(field):
    if field == countField:
      parseCountField()
    else:
      updateSummary()

proc onPush(sender: DynamicAgent) =
  if not sender.isNil:
    inc pushCount
    actionCountLabel.text = "Push count: " & $pushCount
    updateSummary()

proc onToggle(sender: DynamicAgent) =
  if not sender.isNil:
    updateToggleTitle()
    updateSummary()

proc onChoiceChanged(sender: DynamicAgent) =
  if not sender.isNil:
    updateSummary()

proc cycleToggleButton(sender: DynamicAgent) =
  discard sender
  case toggleButton.state
  of bsOff:
    toggleButton.state = bsOn
  of bsOn:
    toggleButton.state = bsMixed
  of bsMixed:
    toggleButton.state = bsOff
  updateToggleTitle()
  updateSummary()

proc toggleDownloads(sender: DynamicAgent) =
  discard sender
  downloads.state = if downloads.state == bsOn: bsOff else: bsOn
  updateSummary()

proc resetControls(sender: DynamicAgent) =
  discard sender
  nameField.stringValue = "Ada"
  noteField.stringValue = "Building UI"
  pushCount = 0
  actionCountLabel.text = "Push count: 0"
  toggleButton.state = bsOff
  downloads.state = bsOff
  notifications.state = bsOff
  sync.state = bsMixed
  small.state = bsOff
  medium.state = bsOn
  large.state = bsOff
  priority.selectedIndex = 1
  color.selectedIndex = 0
  volumeSlider.value = 42.0
  countStepper.value = 2.0
  powerSwitch.state = bsOn
  updateToggleTitle()
  updateVolumeLabel(volumeSlider)
  syncCountField()
  updatePowerSwitchLabel(powerSwitch)
  updateSummary()

let
  contextMenu = newMenu("Controls Context")
  contextPushItem = newMenuItem("Push", pushAction)
  contextToggleItem = newMenuItem("Cycle Toggle", contextToggleAction)
  contextDownloadsItem = newMenuItem("Toggle Downloads", contextDownloadsAction)
  contextResetItem = newMenuItem("Reset Controls", resetAction)

contextPushItem.target = newActionTarget(pushAction, onPush)
contextToggleItem.target = newActionTarget(contextToggleAction, cycleToggleButton)
contextDownloadsItem.target = newActionTarget(contextDownloadsAction, toggleDownloads)
contextResetItem.target = newActionTarget(resetAction, resetControls)
discard contextMenu.addItem(contextPushItem)
discard contextMenu.addItem(contextToggleItem)
discard contextMenu.addItem(contextDownloadsItem)
discard contextMenu.addSeparator()
discard contextMenu.addItem(contextResetItem)

for field in [nameField, noteField, countField]:
  field.connect(textDidChange, field, onTextDidChange)

pushButton.target = newActionTarget(pushAction, onPush)
pushButton.action = pushAction

toggleButton.buttonType = btToggle
toggleButton.allowsMixedState = true
toggleButton.reservedTitles = ["Toggle Off", "Toggle On", "Toggle Mixed"]
toggleButton.target = newActionTarget(toggleAction, onToggle)
toggleButton.action = toggleAction

sync.allowsMixedState = true
sync.state = bsMixed

let choiceTarget = newActionTarget(choiceAction, onChoiceChanged)
for checkbox in [downloads, notifications, sync]:
  checkbox.target = choiceTarget
  checkbox.action = choiceAction

medium.state = bsOn

let radioTarget = newActionTarget(radioAction, onChoiceChanged)
for radio in [small, medium, large]:
  radio.target = radioTarget
  radio.action = radioAction

priority.selectedIndex = 1
color.selectedIndex = 0

let comboTarget = newActionTarget(comboAction, onChoiceChanged)
for combo in [priority, color]:
  combo.target = comboTarget
  combo.action = comboAction

volumeSlider.stepValue = 1.0
volumeSlider.connect(actionDidSend, volumeSlider, updateSliderSummary)
volumeSlider.connect(
  actionDidSend, volumeSlider, updateVolumeLabel, acceptVoidSlot = true
)

countStepper.valueFormatter = proc(value: float32): string =
  $int(value)
countStepper.target = newActionTarget(stepperAction, onStepperChanged)
countStepper.action = stepperAction

powerSwitch.connect(actionDidSend, powerSwitch, updatePowerSwitchSummary)
powerSwitch.connect(
  actionDidSend, powerSwitch, updatePowerSwitchLabel, acceptVoidSlot = true
)

layout.spacing = 16.0
layout.alignment = svaFill

bodyRow.spacing = 28.0
bodyRow.alignment = svaFill
bodyRow.distribution = svdFill

for column in [inputColumn, choiceColumn, popupColumn]:
  column.spacing = 10.0
  column.alignment = svaFill

popupColumn.distribution = svdNatural

switchRow.spacing = 10.0
switchRow.alignment = svaCenter
switchRow.distribution = svdNatural

countRow.spacing = 6.0
countRow.alignment = svaCenter
countField.setHuggingPriority(LayoutPriorityLow, laHorizontal)
countStepper.setHuggingPriority(LayoutPriorityRequired, laHorizontal)

buttonRow.spacing = 8.0
buttonRow.alignment = svaFill
buttonRow.distribution = svdFillEqually

buttonRow.addArrangedSubview(pushButton, toggleButton)
countRow.addArrangedSubview(countField, countStepper)
inputColumn.addArrangedSubview(
  inputTitle, nameField, noteField, actionTitle, buttonRow, actionCountLabel
)
inputColumn.addFlexibleSpacer()
choiceColumn.addArrangedSubview(
  choiceTitle, downloads, notifications, sync, sizeTitle, small, medium, large
)
choiceColumn.addFlexibleSpacer()
popupColumn.addArrangedSubview(
  popupTitle, priority, color, sliderTitle, volumeSlider, volumeLabel, stepperTitle,
  countRow, switchTitle, switchRow,
)
switchRow.addArrangedSubview(powerSwitch, powerSwitchLabel)
bodyRow.addArrangedSubview(inputColumn, choiceColumn, popupColumn)
layout.addArrangedSubview(title, bodyRow, summary)

root.addSubview(layout)
root.menu = contextMenu
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(22.0, 24.0, 0.0, 24.0)),
  edges = {leLeft, leTop, leRight},
)

updateToggleTitle()
updateVolumeLabel(volumeSlider)
syncCountField()
updatePowerSwitchLabel(powerSwitch)
updateSummary()
window.setContentView(root)
discard window.makeFirstResponder(nameField)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
