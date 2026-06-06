import merenda/nimkit

import sigils/core

let
  app = sharedApplication()
  window = newWindow("Nimkit Text Field Demo", frame = initRect(150, 150, 420, 220))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("Text Field")
  field = newTextField("Edit me")
  secondField = newTextField("Tab here")
  status = newStatusLabel("")

proc updateStatus() =
  status.text = "Values: " & field.stringValue & " / " & secondField.stringValue

proc updateStatusOnTextChange(textField: TextField, sender: DynamicAgent) {.slot.} =
  if sender == DynamicAgent(textField):
    updateStatus()

field.connect(textDidChange, field, updateStatusOnTextChange)
secondField.connect(textDidChange, secondField, updateStatusOnTextChange)

root.background = initColor(0.95, 0.96, 0.98)
layout.spacing = 10.0
layout.alignment = svaFill
layout.addArrangedSubview(title, field, secondField, status)
updateStatus()

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.makeFirstResponder(field)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
