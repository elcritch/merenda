import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Radio Demo", frame = initRect(140, 140, 400, 260))
  root = newView(frame = initRect(0, 0, 400, 260))
  title = newTextField("Radio Buttons", frame = initRect(28, 24, 260, 32))
  status = newTextField("", frame = initRect(28, 64, 300, 30))
  small = newRadioButton("Small", frame = initRect(28, 116, 220, 28))
  medium = newRadioButton("Medium", frame = initRect(28, 152, 220, 28))
  large = newRadioButton("Large", frame = initRect(28, 188, 220, 28))
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
