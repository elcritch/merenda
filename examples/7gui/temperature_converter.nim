import std/strutils

import merenda/nimkit

import sigils/core

let
  TextColor = color(0.08, 0.09, 0.11, 1.0)
  ErrorColor = color(0.82, 0.08, 0.08, 1.0)

let
  app = sharedApplication()
  window = newWindow("7GUIs Temperature Converter", frame = rect(140, 140, 420, 190))
  root = newView()
  layout = newStackView(laVertical)
  form = newFormView()
  title = newTitleLabel("Temperature Converter")
  celsiusField = newTextField("")
  fahrenheitField = newTextField("")

var updating = false

func formatTemperature(value: float): string =
  result = value.formatFloat(ffDecimal, 2)
  while result.len > 0 and result[^1] == '0':
    result.setLen(result.len - 1)
  if result.endsWith("."):
    result.setLen(result.len - 1)

proc parseNumber(text: string): tuple[ok: bool, value: float] =
  try:
    result = (true, text.strip().parseFloat())
  except ValueError:
    result = (false, 0.0)

proc updateFromCelsius(textField: TextField, sender: DynamicAgent) {.slot.} =
  if updating or sender != DynamicAgent(celsiusField):
    return
  let parsed = celsiusField.stringValue.parseNumber()
  celsiusField.textColor = if parsed.ok: TextColor else: ErrorColor
  if not parsed.ok:
    return

  updating = true
  fahrenheitField.text = formatTemperature(parsed.value * 9.0 / 5.0 + 32.0)
  fahrenheitField.textColor = TextColor
  updating = false

proc updateFromFahrenheit(textField: TextField, sender: DynamicAgent) {.slot.} =
  if updating or sender != DynamicAgent(fahrenheitField):
    return
  let parsed = fahrenheitField.stringValue.parseNumber()
  fahrenheitField.textColor = if parsed.ok: TextColor else: ErrorColor
  if not parsed.ok:
    return

  updating = true
  celsiusField.text = formatTemperature((parsed.value - 32.0) * 5.0 / 9.0)
  celsiusField.textColor = TextColor
  updating = false

celsiusField.connect(textDidChange, celsiusField, updateFromCelsius)
fahrenheitField.connect(textDidChange, fahrenheitField, updateFromFahrenheit)

form.edgeInsets = insets(0.0)
form.spacing[dcol] = 12.0
form.spacing[drow] = 10.0
form.minFieldWidth = 180.0
form.addRow(newFormLabel("Celsius"), celsiusField)
form.addRow(newFormLabel("Fahrenheit"), fahrenheitField)

layout.spacing = 14.0
layout.alignment = svaFill
layout.addArrangedSubview(title, form)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

app.runWindow(window, root, celsiusField)
