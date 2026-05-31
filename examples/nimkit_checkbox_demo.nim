import merenda/nimkit

import sigils/selectors

proc stateName(state: ButtonState): string =
  case state
  of bsOff: "Off"
  of bsOn: "On"
  of bsMixed: "Mixed"

let
  app = sharedApplication()
  window = newWindow("Nimkit Checkbox Demo", frame = initRect(120, 120, 440, 280))
  root = newView()
  layout = newStackView(laVertical)
  title = newTextField("Checkboxes")
  status = newTextField("")
  downloads = newCheckBox("Enable downloads")
  notifications = newCheckBox("Show notifications")
  sync = newCheckBox("Sync over cellular")
  changedAction = actionSelector("checkboxChanged")

proc updateStatus() =
  status.setStringValue(
    "Downloads: " & downloads.state.stateName & "   Notifications: " &
      notifications.state.stateName & "   Sync: " & sync.state.stateName
  )

proc onChanged(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

let target = newActionTarget(changedAction, onChanged)

root.setBackgroundColor(initColor(0.95, 0.96, 0.98))
title.setTextColor(initColor(0.13, 0.20, 0.34))
status.setTextColor(initColor(0.12, 0.28, 0.20))
sync.setAllowsMixedState(true)
sync.setState(bsMixed)

for label in [title, status]:
  label.setEditable(false)
  label.setSelectable(false)

for checkbox in [downloads, notifications, sync]:
  checkbox.setTarget(target)
  checkbox.setAction(changedAction)

layout.setSpacing(10.0)
layout.setAlignment(svaFill)
layout.addArrangedSubview(title)
layout.addArrangedSubview(status)
for checkbox in [downloads, notifications, sync]:
  layout.addArrangedSubview(checkbox)
updateStatus()

root.addSubview(layout)
activateConstraints(
  [
    newLayoutConstraint(layout, latLeft, lrEqual, root, latLeft, constant = 28.0),
    newLayoutConstraint(layout, latTop, lrEqual, root, latTop, constant = 24.0),
    newLayoutConstraint(layout, latRight, lrEqual, root, latRight, constant = -28.0),
  ]
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
