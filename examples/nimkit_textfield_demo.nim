import knutella/nimkit

let
  app = sharedApplication()
  window = newWindow(150, 150, 420, 180, "Nimkit Text Field Demo")
  root = newView(0, 0, 420, 180)
  title = newTextField(28, 24, 300, 28, "Text Field")
  field = newTextField(28, 70, 260, 30, "Edit me")
  status = newTextField(28, 112, 340, 24, "")

proc updateStatus() =
  status.setStringValue("Value: " & field.stringValue)

proc onTextDidChange(sender: DynamicAgent) =
  if sender == DynamicAgent(field):
    updateStatus()

title.setEditable(false)
title.setSelectable(false)
status.setEditable(false)
status.setSelectable(false)
title.setTextColor(initColor(0.13, 0.20, 0.34))
status.setTextColor(initColor(0.12, 0.28, 0.20))
field.setDelegate(newActionTarget(textDidChange(), onTextDidChange))

root.setBackgroundColor(initColor(0.95, 0.96, 0.98))
root.addSubview(title)
root.addSubview(field)
root.addSubview(status)
updateStatus()
window.setContentView(root)
discard window.makeFirstResponder(field)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
