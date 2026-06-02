import merenda/nimkit

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

proc onTextDidChange(sender: DynamicAgent) =
  if sender == DynamicAgent(field) or sender == DynamicAgent(secondField):
    updateStatus()

field.delegate = newActionTarget(textDidChange(), onTextDidChange)
secondField.delegate = newActionTarget(textDidChange(), onTextDidChange)

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
