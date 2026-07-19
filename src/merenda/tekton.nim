## Resource-document editing and identity-preserving previews for NimKit.

import std/os
import ./tekton/[editor, preview, valueediting, tkapp]

export editor, preview, valueediting, tkapp

when isMainModule:
  let arguments = commandLineParams()
  runTekton(
    if arguments.len > 0:
      arguments[0]
    else:
      ""
  )
