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
  framework = newComboBox(
    [
      "NimKit", "Merenda", "FigDraw", "Kiwiberry", "Sigils", "Siwin", "Pixie", "Chroma",
      "Atlas",
    ]
  )
  priorityLabel = newFormLabel("Priority")
  colorLabel = newFormLabel("Color")
  frameworkLabel = newFormLabel("Framework")
  changedAction = actionSelector("comboChanged")

proc updateStatus() =
  status.text =
    "Priority: " & priority.stringValue & " / Color: " & color.stringValue &
    " / Framework: " & framework.stringValue

proc onChanged(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

let target = newActionTarget(changedAction, onChanged)

priority.selectedIndex = 1
color.selectedIndex = 0
framework.selectedIndex = 3
framework.maxVisibleItems = 4

for combo in [priority, color, framework]:
  combo.target = target
  combo.action = changedAction

layout.spacing = 10.0
layout.alignment = svaFill
form.edgeInsets = insets(0.0)
form.spacing[dcol] = 12.0
form.spacing[drow] = 10.0
form.minFieldWidth = 180.0
form.addRow(priorityLabel, priority)
form.addRow(colorLabel, color)
form.addRow(frameworkLabel, framework)
layout.addArrangedSubview(title, status, form)
updateStatus()

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
