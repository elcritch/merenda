import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Counter", frame = initRect(100, 100, 320, 220))
  root = newView()
  layout = newStackView(laVertical)
  label = newStatusLabel("Clicked 0 times")
  button = newButton("Click")
  clickAction = actionSelector("counterClicked")

var clicks = 0

proc onClick(sender: DynamicAgent) =
  if not sender.isNil:
    inc clicks
    label.text = "Clicked " & $clicks & " times"

button.target = newActionTarget(clickAction, onClick)
button.action = clickAction

layout.spacing = 12.0
layout.alignment = svaFill
layout.addArrangedSubview(label, button)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(44.0, 44.0, 0.0, 44.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
