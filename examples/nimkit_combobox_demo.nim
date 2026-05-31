import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit ComboBox Demo", frame = initRect(160, 160, 420, 240))
  root = newView()
  layout = newStackView(laVertical)
  form = newFormView()
  title = newTextField("Combo Box")
  status = newTextField("")
  priority = newComboBox(["Low", "Medium", "High"])
  color = newComboBox(["Red", "Green", "Blue"])
  priorityLabel = newTextField("Priority")
  colorLabel = newTextField("Color")
  changedAction = actionSelector("comboChanged")

proc updateStatus() =
  status.text = "Priority: " & priority.stringValue & " / Color: " & color.stringValue

proc onChanged(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

let target = newActionTarget(changedAction, onChanged)

root.background = initColor(0.95, 0.96, 0.98)
title.textColor = initColor(0.13, 0.20, 0.34)
status.textColor = initColor(0.12, 0.28, 0.20)

for label in [title, status, priorityLabel, colorLabel]:
  label.editable = false
  label.selectable = false

priority.selectedIndex = 1
color.selectedIndex = 0

for combo in [priority, color]:
  combo.target = target
  combo.action = changedAction

layout.spacing = 10.0
layout.alignment = svaFill
form.edgeInsets = initEdgeInsets(0.0)
form.columnSpacing = 12.0
form.rowSpacing = 10.0
form.minFieldWidth = 180.0
form.addRow(priorityLabel, priority)
form.addRow(colorLabel, color)
layout.addArrangedSubview(title, status, form)
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
