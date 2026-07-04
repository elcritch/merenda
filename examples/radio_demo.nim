import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Radio Demo", frame = rect(140, 140, 400, 260))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("Radio Buttons")
  status = newStatusLabel("")
  small = newRadioButton("Small")
  medium = newRadioButton("Medium")
  large = newRadioButton("Large")
  changedAction = actionSelector("radioChanged")

proc selectedSize(): string =
  if small.state == bsOn:
    "Small"
  elif medium.state == bsOn:
    "Medium"
  elif large.state == bsOn:
    "Large"
  else:
    "None"

proc updateStatus() =
  status.text = "Selected size: " & selectedSize()

proc onChanged(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

let target = newActionTarget(changedAction, onChanged)
medium.state = bsOn

for radio in [small, medium, large]:
  radio.target = target
  radio.action = changedAction

layout.spacing = 10.0
layout.alignment = svaFill
layout.addArrangedSubview(title, status, small, medium, large)
updateStatus()

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

app.runWindow(window, root)
