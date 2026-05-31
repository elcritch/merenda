import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Radio Demo", frame = initRect(140, 140, 400, 260))
  root = newView()
  layout = newStackView(laVertical)
  title = newTextField("Radio Buttons")
  status = newTextField("")
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

root.background = initColor(0.95, 0.96, 0.98)
title.textColor = initColor(0.13, 0.20, 0.34)
status.textColor = initColor(0.12, 0.28, 0.20)
medium.state = bsOn

for label in [title, status]:
  label.editable = false
  label.selectable = false

for radio in [small, medium, large]:
  radio.target = target
  radio.action = changedAction

layout.spacing = 10.0
layout.alignment = svaFill
layout.addArrangedSubview(title, status, small, medium, large)
updateStatus()

root.addSubview(layout)
activateConstraints(
  layout.pinEdges(
    toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 28.0, 0.0, 28.0)),
    edges = {leLeft, leTop, leRight},
  )
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
