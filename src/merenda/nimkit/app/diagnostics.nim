import std/os

when defined(posix):
  import std/posix_utils

import pkg/chronicles

type RuntimeEnvironmentDiagnostics* = object
  targetOS*, targetCPU*: string
  osName*, osRelease*, osVersion*, architecture*: string
  xdgSessionType*, display*, waylandDisplay*: string
  currentDesktop*, desktopSession*: string
  figdrawBackend*, forceOpenGl*, softwareOpenGl*: string
  nimkitUiScale*, nimkitCompactUiScale*, merendaUiScale*: string
  uiScale*, legacyUiScale*: string

var runtimeEnvironmentLogged {.threadvar.}: bool

proc runtimeEnvironmentDiagnostics*(): RuntimeEnvironmentDiagnostics =
  result.targetOS = hostOS
  result.targetCPU = hostCPU
  result.osName = hostOS
  result.architecture = hostCPU

  when defined(posix):
    try:
      let systemInfo = uname()
      result.osName = systemInfo.sysname
      result.osRelease = systemInfo.release
      result.osVersion = systemInfo.version
      result.architecture = systemInfo.machine
    except OSError:
      discard
  elif defined(windows):
    let windowsName = getEnv("OS")
    if windowsName.len > 0:
      result.osName = windowsName
    let windowsArchitecture = getEnv("PROCESSOR_ARCHITECTURE")
    if windowsArchitecture.len > 0:
      result.architecture = windowsArchitecture

  result.xdgSessionType = getEnv("XDG_SESSION_TYPE")
  result.display = getEnv("DISPLAY")
  result.waylandDisplay = getEnv("WAYLAND_DISPLAY")
  result.currentDesktop = getEnv("XDG_CURRENT_DESKTOP")
  result.desktopSession = getEnv("DESKTOP_SESSION")
  result.figdrawBackend = getEnv("FIGDRAW_BACKEND")
  result.forceOpenGl = getEnv("FIGDRAW_FORCE_OPENGL")
  result.softwareOpenGl = getEnv("FIGDRAW_SOFTWARE_GL")
  result.nimkitUiScale = getEnv("NIMKIT_UI_SCALE")
  result.nimkitCompactUiScale = getEnv("NIMKIT_UISCALE")
  result.merendaUiScale = getEnv("MERENDA_UISCALE")
  result.uiScale = getEnv("UISCALE")
  result.legacyUiScale = getEnv("HDI")

proc logRuntimeEnvironment*() =
  if runtimeEnvironmentLogged:
    return
  runtimeEnvironmentLogged = true

  let environment = runtimeEnvironmentDiagnostics()
  info "Merenda operating system",
    targetOS = environment.targetOS,
    targetCPU = environment.targetCPU,
    osName = environment.osName,
    osRelease = environment.osRelease,
    osVersion = environment.osVersion,
    architecture = environment.architecture
  info "Merenda runtime",
    nimVersion = NimVersion,
    threads = compileOption("threads"),
    nativeDynlib = defined(useNativeDynlib)
  info "Merenda desktop and display",
    xdgSessionType = environment.xdgSessionType,
    display = environment.display,
    waylandDisplay = environment.waylandDisplay,
    currentDesktop = environment.currentDesktop,
    desktopSession = environment.desktopSession
  info "Merenda and FigDraw environment settings",
    figdrawBackend = environment.figdrawBackend,
    forceOpenGl = environment.forceOpenGl,
    softwareOpenGl = environment.softwareOpenGl,
    nimkitUiScale = environment.nimkitUiScale,
    nimkitCompactUiScale = environment.nimkitCompactUiScale,
    merendaUiScale = environment.merendaUiScale,
    uiScale = environment.uiScale,
    legacyUiScale = environment.legacyUiScale
