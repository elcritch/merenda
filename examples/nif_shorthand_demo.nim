## The native widget and line-based stylesheet forms of the NIF preferences demo.

import std/os
import ./nif_ui_demo

when isMainModule:
  runNifUiDemo(currentSourcePath().parentDir / "nif_shorthand_demo.nif")
