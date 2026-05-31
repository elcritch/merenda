import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Button Demo", frame = initRect(100, 100, 360, 220))
  root = newView(frame = initRect(0, 0, 360, 220))
  label = newTextField("Ready", frame = initRect(24, 24, 220, 32))
  button = newButton("Click", frame = initRect(24, 72, 140, 40))
  action = actionSelector("buttonClicked")

proc onClicked(sender: DynamicAgent) =
  if not sender.isNil:
    label.setStringValue("Clicked")

let target = newActionTarget(action, onClicked)

label.setEditable(false)
label.setSelectable(false)
button.setTarget(target)
button.setAction(action)
root.addSubview(label)
root.addSubview(button)
window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
