import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow(140, 140, 400, 260, "Nimkit Radio Demo")
  root = newView(0, 0, 400, 260)
  title = newTextField(28, 24, 260, 32, "Radio Buttons")
  status = newTextField(28, 64, 300, 30, "")
  small = newRadioButton(28, 116, 220, 28, "Small")
  medium = newRadioButton(28, 152, 220, 28, "Medium")
  large = newRadioButton(28, 188, 220, 28, "Large")
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
  root.addSubview(radio)

root.addSubview(title)
root.addSubview(status)
updateStatus()
window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
