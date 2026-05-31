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
  status.setStringValue("Selected size: " & selectedSize())

proc onChanged(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

let target = newActionTarget(changedAction, onChanged)

root.setBackgroundColor(initColor(0.95, 0.96, 0.98))
title.setTextColor(initColor(0.13, 0.20, 0.34))
status.setTextColor(initColor(0.12, 0.28, 0.20))
medium.setState(bsOn)

for label in [title, status]:
  label.setEditable(false)
  label.setSelectable(false)

for radio in [small, medium, large]:
  radio.setTarget(target)
  radio.setAction(changedAction)

layout.setSpacing(10.0)
layout.setAlignment(svaFill)
layout.addArrangedSubview(title)
layout.addArrangedSubview(status)
for radio in [small, medium, large]:
  layout.addArrangedSubview(radio)
updateStatus()

root.addSubview(layout)
activateConstraints(
  [
    newLayoutConstraint(layout, latLeft, lrEqual, root, latLeft, constant = 28.0),
    newLayoutConstraint(layout, latTop, lrEqual, root, latTop, constant = 24.0),
    newLayoutConstraint(layout, latRight, lrEqual, root, latRight, constant = -28.0),
  ]
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
