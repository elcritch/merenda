import merenda/nimkit

import sigils/selectors

proc stateName(state: ButtonState): string =
  case state
  of bsOn: "On"
  of bsMixed: "Mixed"
  of bsOff: "Off"

let
  app = sharedApplication()
  window = newWindow("KNutella Nimkit Hello", frame = initRect(120, 120, 720, 360))
  root = newView()
  layout = newStackView(laVertical)
  title = newTextField("Hello from KNutella/nimkit")
  subtitle = newTextField("Pure Nim responder/action dispatch with plain widget state")
  status = newTextField("Button state: Off (click to cycle)")
  button = newButton("Cycle State (Off)")
  action = actionSelector("cycleState")

proc updateStatus() =
  let label = stateName(button.state)
  status.text = "Button state: " & label & " (click to cycle)"
  button.title = "Cycle State (" & label & ")"

proc onCycle(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

root.background = initColor(0.95, 0.96, 0.98)
title.alignment = taCenter
title.textColor = initColor(0.13, 0.20, 0.34)
subtitle.textColor = initColor(0.20, 0.24, 0.31)
status.textColor = initColor(0.12, 0.28, 0.20)

for label in [title, subtitle, status]:
  label.editable = false
  label.selectable = false

button.buttonType = btToggle
button.allowsMixedState = true
button.target = newActionTarget(action, onCycle)
button.action = action

layout.spacing = 12.0
layout.alignment = svaFill
layout.addArrangedSubview(title, subtitle, status, button)

root.addSubview(layout)
activateConstraints(
  layout.pinEdges(
    toGuide = root.contentLayoutGuide(initEdgeInsets(28.0, 28.0, 0.0, 28.0)),
    edges = {leLeft, leTop, leRight},
  )
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
