import std/[tables, times]

import figdraw/figrender as figrender
from figdraw/fignodes import Renders
import figdraw/windowing/siwinshim as siwinshim

import ./types
import ./events

type
  HostKeyEvent* = object
    event*: events.KeyEvent
    pressed*: bool
    isEscape*: bool

  HostWindowCallbacks* = object
    onClose*: proc() {.closure.}
    onResize*: proc() {.closure.}
    onMove*: proc(pos: Point) {.closure.}
    onMouseButton*: proc(event: events.MouseEvent, pressed: bool) {.closure.}
    onMouseMove*: proc(event: events.MouseEvent, dragging: bool) {.closure.}
    onScroll*: proc(event: events.ScrollEvent) {.closure.}
    onKey*: proc(event: HostKeyEvent) {.closure.}
    onTextInput*: proc(text: string) {.closure.}
    onRender*: proc() {.closure.}
    onFocusChanged*: proc(focused: bool) {.closure.}
    onPopupDone*: proc() {.closure.}

  HostWindow* = ref object
    xNativeWindow: siwinshim.Window
    xRenderer: figrender.FigRenderer[siwinshim.SiwinRenderBackend]
    xAutoScale: bool
    xCallbacks: HostWindowCallbacks
    xReady: bool
    xOwnerKey: pointer

var
  hostWindows {.threadvar.}: Table[pointer, HostWindow]
  hostWindowsReady {.threadvar.}: bool

proc ensureHostRegistry() =
  if not hostWindowsReady:
    hostWindows = initTable[pointer, HostWindow]()
    hostWindowsReady = true

proc nativeWindowKey(nativeWindow: siwinshim.Window): pointer =
  cast[pointer](nativeWindow)

proc registerHost(host: HostWindow) =
  if host.isNil or host.xNativeWindow.isNil:
    return
  ensureHostRegistry()
  host.xOwnerKey = host.xNativeWindow.nativeWindowKey
  hostWindows[host.xOwnerKey] = host

proc unregisterHost(host: HostWindow) =
  if host.isNil or host.xOwnerKey.isNil:
    return
  ensureHostRegistry()
  hostWindows.del(host.xOwnerKey)
  host.xOwnerKey = nil

proc hostForNativeWindow(
    nativeWindow: siwinshim.Window, fallbackKey: pointer
): HostWindow =
  ensureHostRegistry()
  let key = if nativeWindow.isNil: fallbackKey else: nativeWindow.nativeWindowKey
  if key.isNil or key notin hostWindows:
    return nil
  hostWindows[key]

proc toNimkitMouseButton(button: siwinshim.MouseButton): events.MouseButton =
  case button
  of siwinshim.MouseButton.left: events.mbPrimary
  of siwinshim.MouseButton.right: events.mbSecondary
  else: events.mbOther

proc toNimkitModifiers(
    modifiers: set[siwinshim.ModifierKey]
): set[events.KeyModifier] =
  if siwinshim.ModifierKey.shift in modifiers:
    result.incl events.kmShift
  if siwinshim.ModifierKey.control in modifiers:
    result.incl events.kmControl
  if siwinshim.ModifierKey.alt in modifiers:
    result.incl events.kmOption
  if siwinshim.ModifierKey.system in modifiers:
    result.incl events.kmCommand

proc toNimkitKey(key: siwinshim.Key): events.Key =
  if key.ord < ord(low(events.Key)) or key.ord > ord(high(events.Key)):
    return events.keyUnknown
  events.Key(key.ord)

proc keyText(key: siwinshim.Key): string =
  case key
  of siwinshim.Key.enter: "\n"
  of siwinshim.Key.tab: "\t"
  else: ""

proc rawInputToLogical*(rawPos: Vec2, inputSize: IVec2, logicalSize: Vec2): Vec2 =
  if inputSize.x <= 0 or inputSize.y <= 0:
    return rawPos
  if logicalSize.x <= 0.0 or logicalSize.y <= 0.0:
    return rawPos
  vec2(
    rawPos.x * logicalSize.x / inputSize.x.float32,
    rawPos.y * logicalSize.y / inputSize.y.float32,
  )

proc nativeMousePoint(window: siwinshim.Window): Point =
  # siwin mouse.pos is reported in window.size coordinates, which may lag
  # backingSize on Cocoa until resize/backing notifications are delivered.
  let pos = rawInputToLogical(window.mouse.pos, window.size(), window.logicalSize())
  initPoint(pos.x.float32, pos.y.float32)

proc nativeMousePoint(window: siwinshim.Window, rawPos: Vec2): Point =
  let pos = rawInputToLogical(rawPos, window.size(), window.logicalSize())
  initPoint(pos.x.float32, pos.y.float32)

proc nativeModifiers(window: siwinshim.Window): set[events.KeyModifier] =
  window.keyboard.modifiers.toNimkitModifiers

proc activeMouseButton(window: siwinshim.Window): events.MouseButton =
  if siwinshim.MouseButton.left in window.mouse.pressed:
    return events.mbPrimary
  if siwinshim.MouseButton.right in window.mouse.pressed:
    return events.mbSecondary
  if window.mouse.pressed.len > 0:
    return events.mbOther
  return events.mbPrimary

proc isReady*(host: HostWindow): bool =
  (not host.isNil) and host.xReady and not host.xNativeWindow.isNil

proc nativeWindowOrNil*(host: HostWindow): siwinshim.Window =
  host.xNativeWindow

proc rendererOrNil*(
    host: HostWindow
): figrender.FigRenderer[siwinshim.SiwinRenderBackend] =
  host.xRenderer

proc contentScale*(host: HostWindow): float32 =
  if not host.isReady:
    return 1.0'f32
  max(host.xNativeWindow.contentScale(), 1.0'f32)

proc refreshContentScale*(host: HostWindow) =
  if host.isReady:
    host.xNativeWindow.refreshUiScale(host.xAutoScale)

proc markClosed(host: HostWindow, notify: bool) =
  let callbacks = host.xCallbacks
  host.unregisterHost()
  host.xReady = false
  if notify and not callbacks.onClose.isNil:
    callbacks.onClose()

proc logicalSize*(host: HostWindow, fallback: Size): Size =
  if not host.isReady:
    return initSize(max(fallback.width, 1.0'f32), max(fallback.height, 1.0'f32))

  let nativeSize = host.xNativeWindow.logicalSize()
  if nativeSize.x <= 0.0'f32 or nativeSize.y <= 0.0'f32:
    return initSize(max(fallback.width, 1.0'f32), max(fallback.height, 1.0'f32))
  initSize(nativeSize.x, nativeSize.y)

proc setTitle*(host: HostWindow, title: string) =
  if host.isReady:
    host.xNativeWindow.title = title

proc setVisible*(host: HostWindow, visible: bool) =
  if not host.isReady:
    return
  if visible and host.xNativeWindow.visible() and not host.xNativeWindow.focused():
    host.xNativeWindow.visible = false
  host.xNativeWindow.visible = visible

proc render*(host: HostWindow, renders: var Renders, logicalSize: Size) =
  if not host.isReady or host.xRenderer.isNil or not host.xNativeWindow.opened():
    return
  host.refreshContentScale()
  let size = vec2(logicalSize.width, logicalSize.height)
  host.xRenderer.beginFrame()
  host.xRenderer.renderFrame(renders, size)
  host.xRenderer.endFrame()

proc close*(host: HostWindow) =
  let nativeWindow = host.xNativeWindow
  let shouldClose = not nativeWindow.isNil and not nativeWindow.closed()
  host.markClosed(notify = false)
  if shouldClose:
    siwinshim.close(nativeWindow)

proc dispatchMouseButton(host: HostWindow, event: siwinshim.MouseButtonEvent) =
  let nativeWindow = if event.window.isNil: host.xNativeWindow else: event.window
  if nativeWindow.isNil or host.xCallbacks.onMouseButton.isNil:
    return
  host.xCallbacks.onMouseButton(
    events.MouseEvent(
      location: nativeMousePoint(nativeWindow),
      button: event.button.toNimkitMouseButton,
      clickCount: 0,
      modifiers: nativeWindow.nativeModifiers,
      timestamp: epochTime(),
    ),
    event.pressed,
  )

proc dispatchMouseMove(host: HostWindow, event: siwinshim.MouseMoveEvent) =
  let nativeWindow = if event.window.isNil: host.xNativeWindow else: event.window
  if nativeWindow.isNil or host.xCallbacks.onMouseMove.isNil:
    return
  let dragging =
    event.kind == siwinshim.MouseMoveKind.moveWhileDragging or
    nativeWindow.mouse.pressed != {}
  host.xCallbacks.onMouseMove(
    events.MouseEvent(
      location: nativeMousePoint(nativeWindow, event.pos),
      button: nativeWindow.activeMouseButton,
      clickCount: 0,
      modifiers: nativeWindow.nativeModifiers,
      timestamp: epochTime(),
    ),
    dragging,
  )

proc dispatchScroll(host: HostWindow, event: siwinshim.ScrollEvent) =
  let nativeWindow = if event.window.isNil: host.xNativeWindow else: event.window
  if nativeWindow.isNil or host.xCallbacks.onScroll.isNil:
    return
  host.xCallbacks.onScroll(
    events.ScrollEvent(
      location: nativeMousePoint(nativeWindow),
      deltaX: event.deltaX.float32,
      deltaY: event.delta.float32,
      phase: sepChanged,
      modifiers: nativeWindow.nativeModifiers,
      timestamp: epochTime(),
    )
  )

proc dispatchKey(host: HostWindow, event: siwinshim.KeyEvent) =
  if host.xCallbacks.onKey.isNil:
    return
  host.xCallbacks.onKey(
    HostKeyEvent(
      event: events.KeyEvent(
        text: event.key.keyText,
        key: event.key.toNimkitKey,
        keyCode: event.key.ord,
        modifiers: event.modifiers.toNimkitModifiers,
      ),
      pressed: event.pressed,
      isEscape: event.key == siwinshim.Key.escape,
    )
  )

proc dispatchTextInput(host: HostWindow, event: siwinshim.TextInputEvent) =
  if event.text.len > 0 and not host.xCallbacks.onTextInput.isNil:
    host.xCallbacks.onTextInput(event.text)

proc installEventHandlers(host: HostWindow) =
  if host.isNil or host.xNativeWindow.isNil:
    return
  let ownerKey = host.xOwnerKey
  host.xNativeWindow.eventsHandler = siwinshim.WindowEventsHandler(
    onClose: proc(event: siwinshim.CloseEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.markClosed(notify = true)
    ,
    onPopupDone: proc(event: siwinshim.PopupEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      host.markClosed(notify = false)
      if not host.xCallbacks.onPopupDone.isNil:
        host.xCallbacks.onPopupDone()
    ,
    onResize: proc(event: siwinshim.ResizeEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      let nativeWindow = if event.window.isNil: host.xNativeWindow else: event.window
      if nativeWindow.isNil:
        return
      nativeWindow.refreshUiScale(host.xAutoScale)
      if not host.xCallbacks.onResize.isNil:
        host.xCallbacks.onResize()
      if not host.xCallbacks.onRender.isNil:
        host.xCallbacks.onRender()
      siwinshim.presentNow(nativeWindow),
    onWindowMove: proc(event: siwinshim.WindowMoveEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil and not host.xCallbacks.onMove.isNil:
        host.xCallbacks.onMove(initPoint(event.pos.x.float32, event.pos.y.float32))
    ,
    onMouseButton: proc(event: siwinshim.MouseButtonEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.dispatchMouseButton(event)
    ,
    onMouseMove: proc(event: siwinshim.MouseMoveEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.dispatchMouseMove(event)
    ,
    onScroll: proc(event: siwinshim.ScrollEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.dispatchScroll(event)
    ,
    onRender: proc(event: siwinshim.RenderEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil and not host.xCallbacks.onRender.isNil:
        host.xCallbacks.onRender()
    ,
    onKey: proc(event: siwinshim.KeyEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.dispatchKey(event)
    ,
    onTextInput: proc(event: siwinshim.TextInputEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.dispatchTextInput(event)
    ,
    onStateBoolChanged: proc(event: siwinshim.StateBoolChangedEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if event.kind == siwinshim.StateBoolChangedEventKind.focus and
          not host.xCallbacks.onFocusChanged.isNil:
        host.xCallbacks.onFocusChanged(event.value)
    ,
  )

proc createHostWindow*(
    frame: Rect, title: string, callbacks: HostWindowCallbacks
): HostWindow =
  let size =
    ivec2(max(frame.size.width, 1.0'f32).int32, max(frame.size.height, 1.0'f32).int32)
  result = HostWindow(xCallbacks: callbacks)
  result.xNativeWindow =
    siwinshim.newSiwinWindow(size = size, title = title, vsync = true, resizable = true)
  result.xNativeWindow.pos = ivec2(frame.origin.x.int32, frame.origin.y.int32)
  result.xAutoScale = result.xNativeWindow.configureUiScale()
  result.xRenderer = figrender.newFigRenderer(
    atlasSize = 1024, backendState = siwinshim.SiwinRenderBackend()
  )
  result.xRenderer.setupBackend(result.xNativeWindow)
  result.registerHost()
  result.installEventHandlers()

  result.xNativeWindow.firstStep()
  result.xNativeWindow.refreshUiScale(result.xAutoScale)
  result.xReady = true

proc createPopupHostWindow*(
    owner: HostWindow,
    placement: siwinshim.PopupPlacement,
    callbacks: HostWindowCallbacks,
): HostWindow =
  if not owner.isReady:
    return nil

  result = HostWindow(xCallbacks: callbacks)
  result.xNativeWindow = siwinshim.sharedSiwinGlobals().newPopupWindow(
      owner.xNativeWindow, placement, grab = true
    )
  result.xAutoScale = result.xNativeWindow.configureUiScale()
  result.xRenderer = figrender.newFigRenderer(
    atlasSize = 1024, backendState = siwinshim.SiwinRenderBackend()
  )
  result.xRenderer.setupBackend(result.xNativeWindow)
  result.registerHost()
  result.installEventHandlers()
  result.xNativeWindow.firstStep(makeVisible = true)
  result.xNativeWindow.reposition(placement)
  result.xNativeWindow.refreshUiScale(result.xAutoScale)
  result.xReady = true

proc pump*(host: HostWindow) =
  if not host.isReady:
    return
  let nativeWindow = host.xNativeWindow
  if nativeWindow.isNil or not nativeWindow.opened():
    return
  nativeWindow.redraw()
  nativeWindow.step()
  if host.isReady and nativeWindow.closed():
    host.markClosed(notify = true)
