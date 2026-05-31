import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Button Counter", frame = initRect(100, 100, 300, 300))
  root = newView()
  layout = newStackView(laVertical)
  button1 = newButton("button1")
  button2 = newButton("button2")
  label1 = newTextField("button1 clicked 0 times")
  label2 = newTextField("button2 clicked 0 times")
  button1Action = actionSelector("button1Clicked")
  button2Action = actionSelector("button2Clicked")

var
  button1Clicked = 0
  button2Clicked = 0

proc onButton1(sender: DynamicAgent) =
  if not sender.isNil:
    inc button1Clicked
    label1.text = "button1 clicked " & $button1Clicked & " times"

proc onButton2(sender: DynamicAgent) =
  if not sender.isNil:
    inc button2Clicked
    label2.text = "button2 clicked " & $button2Clicked & " times"

button1.target = newActionTarget(button1Action, onButton1)
button1.action = button1Action
button2.target = newActionTarget(button2Action, onButton2)
button2.action = button2Action

for label in [label1, label2]:
  label.editable = false
  label.selectable = false

layout.spacing = 12.0
layout.alignment = svaFill
layout.addArrangedSubview(button1, button2, label1, label2)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(50.0, 50.0, 0.0, 50.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
