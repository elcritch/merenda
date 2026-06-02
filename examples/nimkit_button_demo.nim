import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Button Demo", frame = initRect(100, 100, 360, 220))
  root = newView()
  layout = newStackView(laVertical)
  label = newStatusLabel("Ready")
  button = newButton("Click")
  action = actionSelector("buttonClicked")

proc onClicked(sender: DynamicAgent) =
  if not sender.isNil:
    label.text = "Clicked"

let target = newActionTarget(action, onClicked)

button.target = target
button.action = action

layout.spacing = 12.0
layout.alignment = svaFill
layout.addArrangedSubview(label, button)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 24.0, 0.0, 24.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
