import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit ComboBox Demo", frame = initRect(160, 160, 420, 240))
  root = newView()
  layout = newStackView(laVertical)
  form = newFormView()
  title = newTitleLabel("Combo Box")
  status = newStatusLabel("")
  priority = newComboBox(["Low", "Medium", "High"])
  color = newComboBox(["Red", "Green", "Blue"])
  priorityLabel = newFormLabel("Priority")
  colorLabel = newFormLabel("Color")
  changedAction = actionSelector("comboChanged")

proc updateStatus() =
  status.text = "Priority: " & priority.stringValue & " / Color: " & color.stringValue

proc onChanged(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

let target = newActionTarget(changedAction, onChanged)

root.background = initColor(0.95, 0.96, 0.98)

priority.selectedIndex = 1
color.selectedIndex = 0

for combo in [priority, color]:
  combo.target = target
  combo.action = changedAction

layout.spacing = 10.0
layout.alignment = svaFill
form.edgeInsets = initEdgeInsets(0.0)
form.spacing[dcol] = 12.0
form.spacing[drow] = 10.0
form.minFieldWidth = 180.0
form.addRow(priorityLabel, priority)
form.addRow(colorLabel, color)
layout.addArrangedSubview(title, status, form)
updateStatus()

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
