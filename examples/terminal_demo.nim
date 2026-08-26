import std/os

import merenda/nimkit

let
  app = sharedApplication()
  window = newWindow("Terminal", frame = rect(140, 100, 900, 600))
  terminal =
    newTerminalView(initTerminalSpawnOptions(workingDirectory = getCurrentDir()))

terminal.fontSize = 14.0'f32
terminal.accessibilityLabel = "Terminal"

app.runWindow(window, terminal, terminal)
