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
  title = newTitleLabel("Checkboxes")
  status = newStatusLabel("")
  downloads = newCheckBox("Enable downloads")
  notifications = newCheckBox("Show notifications")
  sync = newCheckBox("Sync over cellular")
  changedAction = actionSelector("checkboxChanged")

proc updateStatus() =
  status.text =
    "Downloads: " & downloads.state.stateName & "   Notifications: " &
    notifications.state.stateName & "   Sync: " & sync.state.stateName

proc onChanged(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

let target = newActionTarget(changedAction, onChanged)
sync.allowsMixedState = true
sync.state = bsMixed

for checkbox in [downloads, notifications, sync]:
  checkbox.target = target
  checkbox.action = changedAction

layout.spacing = 10.0
layout.alignment = svaFill
layout.addArrangedSubview(title, status, downloads, notifications, sync)
updateStatus()

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
