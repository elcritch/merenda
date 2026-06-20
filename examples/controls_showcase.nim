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
  summary.text =
    nameField.stringValue & " / " & noteField.stringValue & " / Toggle: " &
    toggleButton.state.stateName & " / Downloads: " & downloads.state.stateName &
    " / Size: " & selectedSize() & " / Priority: " & priority.stringValue & " / Color: " &
    color.stringValue & " / Volume: " & $int(volumeSlider.value)

proc updateToggleTitle() =
  toggleButton.title = "Toggle " & toggleButton.state.stateName

proc updateVolumeLabel(slider: Slider) {.slot.} =
  volumeLabel.text = "Volume: " & $int(slider.value)

proc updateSliderSummary(slider: Slider, sender: DynamicAgent) {.slot.} =
  updateSummary()

proc onTextDidChange(field: TextField, sender: DynamicAgent) {.slot.} =
  if sender == DynamicAgent(field):
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

root.background = initColor(0.95, 0.96, 0.98)

for field in [nameField, noteField]:
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
volumeSlider.connect(actionDidSend, volumeSlider, updateVolumeLabel, acceptVoidSlot = true)

layout.spacing = 16.0
layout.alignment = svaFill

bodyRow.spacing = 28.0
bodyRow.alignment = svaFill
bodyRow.distribution = svdFill

for column in [inputColumn, choiceColumn, popupColumn]:
  column.spacing = 10.0
  column.alignment = svaFill

popupColumn.distribution = svdNatural

buttonRow.spacing = 8.0
buttonRow.alignment = svaFill
buttonRow.distribution = svdFillEqually

buttonRow.addArrangedSubview(pushButton, toggleButton)
inputColumn.addArrangedSubview(
  inputTitle, nameField, noteField, actionTitle, buttonRow, actionCountLabel
)
inputColumn.addFlexibleSpacer()
choiceColumn.addArrangedSubview(
  choiceTitle, downloads, notifications, sync, sizeTitle, small, medium, large
)
choiceColumn.addFlexibleSpacer()
popupColumn.addArrangedSubview(
  popupTitle, priority, color, sliderTitle, volumeSlider, volumeLabel
)
bodyRow.addArrangedSubview(inputColumn, choiceColumn, popupColumn)
layout.addArrangedSubview(title, bodyRow, summary)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(22.0, 24.0, 0.0, 24.0)),
  edges = {leLeft, leTop, leRight},
)

updateToggleTitle()
updateVolumeLabel(volumeSlider)
updateSummary()
window.setContentView(root)
discard window.makeFirstResponder(nameField)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
