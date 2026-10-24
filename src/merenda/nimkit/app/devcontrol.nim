## GUI-thread adapter for the optional development-control protocol.
when not defined(merenda.devControl):
  {.
    error:
      "Compile applications with -d:merenda.devControl to enable development control"
  .}

import std/[base64, json, monotimes, os, strutils, times]
import ../devcontrol/[protocol, transport]
import ../foundation/[events, types]
import ../themes
import ./[backend, windows]

export protocol, transport

type
  DevControlOptions* = object
    socketPath*: string

  DevWindowProvider* = proc(): seq[Window] {.closure.}
  DevModalPredicate* = proc(window: Window): bool {.closure.}
  DevAppearanceProvider* = proc(): Appearance {.closure.}
  DevAppearanceHandler* = proc(appearance: Appearance) {.closure.}

  DevWindowEntry = object
    id: string
    window: Window

  DevCapture = ref object
    window: Window
    complete: DevCompletion
    requestId: string
    deadline: MonoTime
    finished: bool

  DevController* = ref object
    server: DevServer
    windows: DevWindowProvider
    blocked: DevModalPredicate
    entries: seq[DevWindowEntry]
    nextWindow: uint64
    captures: seq[DevCapture]
    appearance: DevAppearanceProvider
    applyAppearance: DevAppearanceHandler
    cssFile: string
    cssBase: Appearance

proc appendWindows(windows: var seq[Window], window: Window) =
  if window.isNil or window.isClosed or window in windows:
    return
  windows.add window
  for auxiliary in window.auxiliaryWindows():
    appendWindows(windows, auxiliary)

proc refreshWindows(controller: DevController): seq[Window] =
  for window in controller.windows():
    result.appendWindows(window)
  for window in result:
    var found = false
    for entry in controller.entries:
      if entry.window == window:
        found = true
        break
    if not found:
      inc controller.nextWindow
      controller.entries.add DevWindowEntry(
        id: "w" & $controller.nextWindow, window: window
      )
  var index = 0
  while index < controller.entries.len:
    if controller.entries[index].window notin result:
      controller.entries.delete(index)
    else:
      inc index

proc keyModifiers(request: DevRequest): set[KeyModifier] =
  for modifier in request.modifiers:
    case modifier
    of "shift":
      result.incl kmShift
    of "control":
      result.incl kmControl
    of "option":
      result.incl kmOption
    of "command":
      result.incl kmCommand
    else:
      discard # Protocol validation rejects unknown values.

proc loadTheme(controller: DevController, request: DevRequest): DevResponse =
  if controller.appearance.isNil or controller.applyAppearance.isNil:
    return devFailure(request.id, "unsupported", "Theme loading is unavailable")
  let path = if request.command == dcThemeLoad: request.file else: controller.cssFile
  if path.len == 0:
    return
      devFailure(request.id, "theme_not_loaded", "Load a CSS file before reloading")
  if not path.isAbsolute():
    return devFailure(request.id, "invalid_request", "CSS file path must be absolute")
  let base =
    if controller.cssFile.len == 0:
      controller.appearance()
    else:
      controller.cssBase
  try:
    let loaded = loadCssTheme(path, base.theme)
    if loaded.diagnostics.len > 0:
      var message: string
      for diagnostic in loaded.diagnostics:
        if message.len > 0:
          message.add "\n"
        message.add "line " & $diagnostic.line & ":" & $diagnostic.column & ": " &
          diagnostic.message
      return devFailure(request.id, "invalid_css", message)
    controller.applyAppearance(initAppearance(loaded.theme))
    controller.cssFile = path
    controller.cssBase = base
    devSuccess(request.id, %*{"file": path, "applied": true})
  except IOError, OSError:
    devFailure(request.id, "theme_load_failed", getCurrentExceptionMsg())

proc dispatch(controller: DevController, request: DevRequest, complete: DevCompletion) =
  discard controller.refreshWindows()
  case request.command
  of dcInfo:
    complete(
      devSuccess(
        request.id,
        %*{
          "pid": getCurrentProcessId(),
          "protocolVersion": DevProtocolVersion,
          "capabilities": [
            "windows", "screenshot", "pointer", "key", "text", "theme-load",
            "theme-reload",
          ],
          "background": backgroundLaunchRequested(),
          "nonactivatingPresentation": defined(macosx) or defined(windows),
        },
      )
    )
    return
  of dcThemeLoad, dcThemeReload:
    complete(controller.loadTheme(request))
    return
  of dcWindows:
    var items = newJArray()
    for entry in controller.entries:
      let window = entry.window
      let frame = window.frame()
      items.add %*{
        "id": entry.id,
        "title": window.title(),
        "width": frame.size.width,
        "height": frame.size.height,
        "scale": window.nativeContentScale(),
        "visible": window.isVisible,
        "nativeReady": window.nativeReady,
        "key": window.isKeyWindow,
        "blocked": controller.blocked(window),
      }
    complete(devSuccess(request.id, %*{"windows": items}))
    return
  else:
    discard
  var window: Window
  for entry in controller.entries:
    if entry.id == request.window:
      window = entry.window
      break
  if window.isNil:
    complete(
      devFailure(
        request.id, "window_not_found", "Window is unavailable: " & request.window
      )
    )
    return
  if not window.nativeReady or not window.isVisible or window.isMiniaturized:
    complete(
      devFailure(request.id, "window_not_ready", "Window has no visible render surface")
    )
    return
  if request.command != dcScreenshot and controller.blocked(window):
    complete(
      devFailure(request.id, "window_blocked", "Window is blocked by a modal session")
    )
    return
  if request.command == dcScreenshot:
    let size = window.frame().size
    if size.width.float64 * size.height.float64 * window.nativeContentScale().float64 *
        window.nativeContentScale().float64 > 8_000_000:
      complete(
        devFailure(request.id, "capture_failed", "Capture exceeds 8 million pixels")
      )
      return
    if controller.captures.len >= 4:
      complete(devFailure(request.id, "busy", "Capture queue is full"))
      return
    let pending = DevCapture(
      window: window,
      complete: complete,
      requestId: request.id,
      deadline: getMonoTime() + initDuration(seconds = 10),
    )
    controller.captures.add pending
    let accepted = window.requestScreenshot(
      proc(capture: RenderCapture) =
        if pending.finished:
          return
        pending.finished = true
        if capture.error.len > 0 or capture.png.len == 0:
          complete(devFailure(request.id, "capture_failed", capture.error))
        else:
          complete(
            devSuccess(
              request.id,
              %*{
                "mimeType": "image/png",
                "width": capture.width,
                "height": capture.height,
                "scale": capture.scale,
                "renderId": capture.renderId,
                "data": encode(capture.png),
              },
            )
          )
    )
    if not accepted:
      pending.finished = true
      complete(devFailure(request.id, "busy", "Window already has a pending capture"))
    return
  let modifiers = request.keyModifiers()
  var handled = false
  case request.command
  of dcText:
    handled = window.dispatchTextInput(request.text)
  of dcKey:
    var key = keyUnknown
    for candidate in Key:
      if ($candidate)[3 .. ^1].toLowerAscii() == request.key.toLowerAscii():
        key = candidate
        break
    if key == keyUnknown:
      complete(devFailure(request.id, "invalid_request", "Unknown key: " & request.key))
      return
    let event = KeyEvent(key: key, keyCode: key.ord, modifiers: modifiers)
    handled =
      if request.action == "down":
        window.dispatchKeyDown(event)
      else:
        window.dispatchKeyUp(event)
  of dcPointer:
    let point = initPoint(request.x, request.y)
    let button =
      case request.button
      of "secondary": mbSecondary
      of "other": mbOther
      else: mbPrimary
    case request.action
    of "move":
      handled = window.mouseMovedAt(point, modifiers)
    of "drag":
      handled = window.mouseDraggedAt(point, button, modifiers)
    of "down":
      handled = window.mouseDownAt(point, button, 1, modifiers)
    of "up":
      handled = window.mouseUpAt(point, button, 1, modifiers)
    of "click":
      let down = window.mouseDownAt(point, button, 1, modifiers)
      let up = window.mouseUpAt(point, button, 1, modifiers)
      handled = down or up
    of "scroll":
      handled = window.scrollWheelAt(point, request.deltaX, request.deltaY, modifiers)
    else:
      discard
  else:
    discard
  complete(devSuccess(request.id, %*{"handled": handled}))

proc close*(controller: DevController) =
  if controller.isNil:
    return
  controller.server.close()
  for capture in controller.captures.mitems:
    if not capture.finished:
      capture.window.cancelScreenshot()
    capture.finished = true
  controller.captures.setLen(0)
  controller.entries.setLen(0)
  controller.windows = nil
  controller.blocked = nil
  controller.appearance = nil
  controller.applyAppearance = nil

proc newDevController*(
    options: DevControlOptions,
    windows: DevWindowProvider,
    blocked: DevModalPredicate,
    appearance: DevAppearanceProvider = nil,
    applyAppearance: DevAppearanceHandler = nil,
): DevController =
  let path =
    if options.socketPath.len > 0:
      options.socketPath
    else:
      devSocketPath(getCurrentProcessId().Positive)
  let controller = DevController(
    windows: windows,
    blocked: blocked,
    appearance: appearance,
    applyAppearance: applyAppearance,
  )
  controller.server = startDevServer(
    path,
    proc(request: DevRequest, complete: DevCompletion) =
      try:
        controller.dispatch(request, complete)
      except CatchableError as error:
        complete(devFailure(request.id, "internal_error", error.msg)),
  )
  controller

proc poll*(controller: DevController) =
  if controller.isNil:
    return
  controller.server.poll()
  let now = getMonoTime()
  for capture in controller.captures.mitems:
    if not capture.finished and (capture.window.isClosed or now >= capture.deadline):
      capture.finished = true
      capture.window.cancelScreenshot()
      capture.complete(
        devFailure(
          capture.requestId, "capture_failed", "Capture target closed or timed out"
        )
      )
  var index = 0
  while index < controller.captures.len:
    if controller.captures[index].finished:
      controller.captures.delete(index)
    else:
      inc index
