## A standalone presentation of Merenda's built-in settings panel.

import merenda/nimkit
import merenda/nimkit/app/settings

let app = sharedApplication()
let settingsWindow = newMerendaSettingsWindow(
  proc(appearance: Appearance) =
    app.setAppearance(appearance),
  invertScrolling = app.invertScrolling(),
  invertScrollingHandler = proc(inverted: bool) =
    app.invertScrolling = inverted,
  initialUiScale = app.uiScale(),
  uiScaleHandler = proc(scale: float32) =
    app.uiScale = scale,
)

app.runWindow(
  settingsWindow.window, settingsWindow.contentView(), settingsWindow.firstResponder()
)
