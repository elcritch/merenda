import knutella/nimkit

import sigils/selectors

proc stateName(state: ButtonState): string =
  case state
  of bsOff: "Off"
  of bsOn: "On"
  of bsMixed: "Mixed"

let
  app = sharedApplication()
  window = newWindow(120, 120, 440, 280, "Nimkit Checkbox Demo")
  root = newView(0, 0, 440, 280)
  title = newTextField(28, 24, 280, 32, "Checkboxes")
  status = newTextField(28, 64, 360, 30, "")
  downloads = newCheckBox(28, 116, 260, 28, "Enable downloads")
  notifications = newCheckBox(28, 152, 260, 28, "Show notifications")
  sync = newCheckBox(28, 188, 280, 28, "Sync over cellular")
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

for checkbox in [downloads, notifications, sync]:
  checkbox.setTarget(target)
  checkbox.setAction(changedAction)
  root.addSubview(checkbox)

root.addSubview(title)
root.addSubview(status)
updateStatus()
window.setContentView(root)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
