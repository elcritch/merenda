import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Button Demo", frame = initRect(100, 100, 360, 220))
  root = newView()
  layout = newStackView(laVertical)
  label = newTextField("Ready")
  button = newButton("Click")
  action = actionSelector("buttonClicked")

proc onClicked(sender: DynamicAgent) =
  if not sender.isNil:
    label.setStringValue("Clicked")

let target = newActionTarget(action, onClicked)

label.setEditable(false)
label.setSelectable(false)
button.setTarget(target)
button.setAction(action)

layout.setSpacing(12.0)
layout.setAlignment(svaFill)
layout.addArrangedSubview(label)
layout.addArrangedSubview(button)

root.addSubview(layout)
activateConstraints(
  [
    newLayoutConstraint(layout, latLeft, lrEqual, root, latLeft, constant = 24.0),
    newLayoutConstraint(layout, latTop, lrEqual, root, latTop, constant = 24.0),
    newLayoutConstraint(layout, latRight, lrEqual, root, latRight, constant = -24.0),
  ]
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
