import std/strutils

import merenda/nimkit

import sigils/core
import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Stepper Demo", frame = rect(160, 150, 480, 260))
  root = newView()
  layout = newStackView(laVertical)
  form = newFormView()
  title = newTitleLabel("Stepper")
  status = newStatusLabel("")
  quantityField = newTextField("")
  quantityStepper = newStepper(0.0, 24.0, 3.0, increment = 1.0)
  temperatureField = newTextField("")
  temperatureStepper = newStepper(-10.0, 40.0, 18.0, increment = 0.5)
  fieldAction = actionSelector("stepperFieldCommitted")
  stepperAction = actionSelector("stepperChanged")

proc fieldStepperRow(field: TextField, stepper: Stepper): StackView =
  result = newStackView(laHorizontal)
  result.spacing = 6.0
  result.alignment = svaCenter
  field.setHuggingPriority(LayoutPriorityLow, laHorizontal)
  stepper.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
  result.addArrangedSubview(field, stepper)

proc updateStatus() =
  status.text =
    "Quantity: " & quantityStepper.formattedValue & " / Temperature: " &
    temperatureStepper.formattedValue

proc syncField(field: TextField, stepper: Stepper) =
  field.text = stepper.formattedValue

proc syncFields() =
  syncField(quantityField, quantityStepper)
  syncField(temperatureField, temperatureStepper)
  updateStatus()

proc numericText(value: string): string =
  result = value.strip()
  if result.endsWith(" C"):
    result.setLen(result.len - 2)
    result = result.strip()

proc parseField(field: TextField, stepper: Stepper) =
  try:
    stepper.value = parseFloat(field.stringValue.numericText()).float32
    syncField(field, stepper)
    updateStatus()
  except ValueError:
    status.text = "Invalid number: " & field.stringValue

proc onStepperChanged(sender: DynamicAgent) =
  if sender == DynamicAgent(quantityStepper):
    syncField(quantityField, quantityStepper)
  elif sender == DynamicAgent(temperatureStepper):
    syncField(temperatureField, temperatureStepper)
  updateStatus()

proc onFieldCommitted(sender: DynamicAgent) =
  if sender == DynamicAgent(quantityField):
    parseField(quantityField, quantityStepper)
  elif sender == DynamicAgent(temperatureField):
    parseField(temperatureField, temperatureStepper)

proc onTextDidChange(field: TextField, sender: DynamicAgent) {.slot.} =
  if sender == DynamicAgent(field):
    if field == quantityField:
      parseField(quantityField, quantityStepper)
    elif field == temperatureField:
      parseField(temperatureField, temperatureStepper)

quantityStepper.valueFormatter = proc(value: float32): string =
  $int(value)

temperatureStepper.valueFormatter = proc(value: float32): string =
  formatFloat(value, ffDecimal, 1) & " C"
temperatureStepper.wraps = true

quantityStepper.target = newActionTarget(stepperAction, onStepperChanged)
quantityStepper.action = stepperAction
temperatureStepper.target = quantityStepper.target
temperatureStepper.action = stepperAction

quantityField.target = newActionTarget(fieldAction, onFieldCommitted)
quantityField.action = fieldAction
temperatureField.target = quantityField.target
temperatureField.action = fieldAction

quantityField.connect(textDidChange, quantityField, onTextDidChange)
temperatureField.connect(textDidChange, temperatureField, onTextDidChange)

form.edgeInsets = insets(0.0)
form.spacing[dcol] = 12.0
form.spacing[drow] = 10.0
form.minFieldWidth = 180.0
form.addRow(newFormLabel("Quantity"), fieldStepperRow(quantityField, quantityStepper))
form.addRow(
  newFormLabel("Temperature"), fieldStepperRow(temperatureField, temperatureStepper)
)

layout.spacing = 12.0
layout.alignment = svaFill
layout.addArrangedSubview(title, status, form)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

syncFields()
window.setContentView(root)
discard window.makeFirstResponder(quantityField)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
