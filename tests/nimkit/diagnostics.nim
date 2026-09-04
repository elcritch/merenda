import std/[os, unittest]

import merenda/nimkit/app/diagnostics

suite "NimKit runtime diagnostics":
  test "environment snapshot reports platform and display configuration":
    let diagnostics = runtimeEnvironmentDiagnostics()

    check diagnostics.targetOS == hostOS
    check diagnostics.targetCPU == hostCPU
    check diagnostics.osName.len > 0
    check diagnostics.architecture.len > 0
    check diagnostics.xdgSessionType == getEnv("XDG_SESSION_TYPE")
    check diagnostics.display == getEnv("DISPLAY")
    check diagnostics.waylandDisplay == getEnv("WAYLAND_DISPLAY")
    check diagnostics.figdrawBackend == getEnv("FIGDRAW_BACKEND")
    check diagnostics.forceOpenGl == getEnv("FIGDRAW_FORCE_OPENGL")
    check diagnostics.nimkitCompactUiScale == getEnv("NIMKIT_UISCALE")

    when defined(posix):
      check diagnostics.osRelease.len > 0
      check diagnostics.osVersion.len > 0
