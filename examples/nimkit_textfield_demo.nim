import merenda/nimkit

let
  app = sharedApplication()
  window = newWindow("Nimkit Text Field Demo", frame = initRect(150, 150, 420, 220))
  root = newView()
  layout = newStackView(laVertical)
  title = newTextField("Text Field")
  field = newTextField("Edit me")
  secondField = newTextField("Tab here")
  status = newTextField("")

proc updateStatus() =
  status.setStringValue(
    "Values: " & field.stringValue & " / " & secondField.stringValue
  )

proc onTextDidChange(sender: DynamicAgent) =
  if sender == DynamicAgent(field) or sender == DynamicAgent(secondField):
    updateStatus()

title.setEditable(false)
title.setSelectable(false)
status.setEditable(false)
status.setSelectable(false)
title.setTextColor(initColor(0.13, 0.20, 0.34))
status.setTextColor(initColor(0.12, 0.28, 0.20))
field.setDelegate(newActionTarget(textDidChange(), onTextDidChange))
secondField.setDelegate(newActionTarget(textDidChange(), onTextDidChange))

root.setBackgroundColor(initColor(0.95, 0.96, 0.98))
layout.setSpacing(10.0)
layout.setAlignment(svaFill)
layout.addArrangedSubview(title)
layout.addArrangedSubview(field)
layout.addArrangedSubview(secondField)
layout.addArrangedSubview(status)
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
discard window.makeFirstResponder(field)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
