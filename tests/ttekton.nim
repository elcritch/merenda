## Tekton's shared test runner and complete public API smoke test.
import std/exitprocs
import merenda/tekton

import
  tekton/[application, editor, layout_authoring, preview, regressions, user_workflows]

when isMainModule:
  # Nim ic can otherwise exit successfully after unittest records a failure.
  if getProgramResult() != 0:
    quit(getProgramResult())
