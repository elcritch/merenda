import knutella/nimkit

import sigils/selectors

proc stateName(state: ButtonState): string =
  case state
  of bsOn: "On"
  of bsMixed: "Mixed"
  of bsOff: "Off"

let
  app = sharedApplication()
  window = newWindow(120, 120, 720, 360, "KNutella Nimkit Hello")
  root = newView(0, 0, 720, 360)
  title = newTextField(28, 28, 520, 48, "Hello from KNutella/nimkit")
  subtitle = newTextField(
    28, 86, 620, 36, "Pure Nim responder/action dispatch with plain widget state"
  )
  status = newTextField(28, 132, 420, 30, "Button state: Off (click to cycle)")
  button = newButton(28, 172, 220, 44, "Cycle State (Off)")
  action = actionSelector("cycleState")

proc updateStatus() =
  let label = stateName(button.state)
  status.setStringValue("Button state: " & label & " (click to cycle)")
  button.setTitle("Cycle State (" & label & ")")

proc onCycle(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

root.setBackgroundColor(initColor(0.95, 0.96, 0.98))
title.setAlignment(taCenter)
title.setTextColor(initColor(0.13, 0.20, 0.34))
subtitle.setTextColor(initColor(0.20, 0.24, 0.31))
status.setTextColor(initColor(0.12, 0.28, 0.20))

for label in [title, subtitle, status]:
  label.setEditable(false)
  label.setSelectable(false)

button.setButtonType(btToggle)
button.setAllowsMixedState(true)
button.setTarget(newActionTarget(action, onCycle))
button.setAction(action)

root.addSubview(title)
root.addSubview(subtitle)
root.addSubview(status)
root.addSubview(button)
window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
