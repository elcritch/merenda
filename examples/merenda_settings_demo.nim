## A standalone presentation of Merenda's built-in settings panel.

import merenda/nimkit
import merenda/nimkit/app/settings

let app = sharedApplication()
let settingsWindow = newMerendaSettingsWindow(
  proc(appearance: Appearance) =
    app.setAppearance(appearance)
)

app.runWindow(
  settingsWindow.window, settingsWindow.contentView(), settingsWindow.firstResponder()
)
