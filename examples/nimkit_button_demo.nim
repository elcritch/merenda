import knutella/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow(100, 100, 360, 220, "Nimkit Button Demo")
  root = newView(0, 0, 360, 220)
  label = newTextField(24, 24, 220, 32, "Ready")
  button = newButton(24, 72, 140, 40, "Click")
  action = actionSelector("buttonClicked")

proc onClicked(sender: DynamicAgent) =
  if not sender.isNil:
    label.setStringValue("Clicked")

let target = newActionTarget(action, onClicked)

button.setTarget(target)
button.setAction(action)
root.addSubview(label)
root.addSubview(button)
window.setContentView(root)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
