import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow(160, 160, 420, 240, "Nimkit ComboBox Demo")
  root = newView(0, 0, 420, 240)
  title = newTextField(28, 24, 280, 28, "Combo Box")
  status = newTextField(28, 68, 340, 24, "")
  priority = newComboBox(28, 116, 180, 28, ["Low", "Medium", "High"])
  color = newComboBox(28, 154, 180, 28, ["Red", "Green", "Blue"])
  changedAction = actionSelector("comboChanged")

proc updateStatus() =
  status.setStringValue(
    "Priority: " & priority.stringValue & " / Color: " & color.stringValue
  )

proc onChanged(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

let target = newActionTarget(changedAction, onChanged)

root.setBackgroundColor(initColor(0.95, 0.96, 0.98))
title.setTextColor(initColor(0.13, 0.20, 0.34))
status.setTextColor(initColor(0.12, 0.28, 0.20))

for label in [title, status]:
  label.setEditable(false)
  label.setSelectable(false)

priority.selectItemAtIndex(1)
color.selectItemAtIndex(0)

for combo in [priority, color]:
  combo.setTarget(target)
  combo.setAction(changedAction)
  root.addSubview(combo)

root.addSubview(title)
root.addSubview(status)
updateStatus()
window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
