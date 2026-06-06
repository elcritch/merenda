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
  title = newTitleLabel("Hello from KNutella/nimkit")
  subtitle = newLabel("Pure Nim responder/action dispatch with plain widget state")
  status = newStatusLabel("Button state: Off (click to cycle)")
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

button.buttonType = btToggle
button.allowsMixedState = true
button.target = newActionTarget(action, onCycle)
button.action = action

layout.spacing = 12.0
layout.alignment = svaFill
layout.addArrangedSubview(title, subtitle, status, button)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(28.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
