import merenda/nimkit

let
  app = sharedApplication()
  window = newWindow("Nimkit Text Field Demo", frame = initRect(150, 150, 420, 220))
  root = newView(frame = initRect(0, 0, 420, 220))
  title = newTextField("Text Field", frame = initRect(28, 24, 300, 28))
  field = newTextField("Edit me", frame = initRect(28, 70, 260, 30))
  secondField = newTextField("Tab here", frame = initRect(28, 108, 260, 30))
  status = newTextField("", frame = initRect(28, 152, 340, 24))

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
root.addSubview(title)
root.addSubview(field)
root.addSubview(secondField)
root.addSubview(status)
updateStatus()
window.setContentView(root)
discard window.makeFirstResponder(field)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
