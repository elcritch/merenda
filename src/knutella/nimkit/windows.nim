import std/tables

import figdraw/figrender as figrender
from figdraw/fignodes import Renders
import figdraw/windowing/siwinshim as siwinshim

import ./rendering as nimkitRendering
import ./selectors
import ./types
import ./views

type Window* = ref object
  xFrame: Rect
  xTitle: string
  xContentView: View
  xFirstResponder: Responder
  xNativeWindow: siwinshim.Window
  xRenderer: figrender.FigRenderer[siwinshim.SiwinRenderBackend]
  xAutoScale: bool
  xNativeReady: bool
  xVisibleRequested: bool
  xClosed: bool

var
  nativeWindowOwners {.threadvar.}: Table[pointer, Window]
  nativeWindowOwnersReady {.threadvar.}: bool

proc ensureNativeOwnerRegistry() =
  if not nativeWindowOwnersReady:
    nativeWindowOwners = initTable[pointer, Window]()
    nativeWindowOwnersReady = true

proc nativeWindowKey(nativeWindow: siwinshim.Window): pointer =
  cast[pointer](nativeWindow)

proc registerNativeWindowOwner(window: Window) =
  if window.isNil or window.xNativeWindow.isNil:
    return
  ensureNativeOwnerRegistry()
  nativeWindowOwners[window.xNativeWindow.nativeWindowKey] = window

proc unregisterNativeWindowOwner(nativeWindow: siwinshim.Window) =
  if nativeWindow.isNil:
    return
  ensureNativeOwnerRegistry()
  nativeWindowOwners.del(nativeWindow.nativeWindowKey)

proc ownerForNativeWindow(
    nativeWindow: siwinshim.Window, fallbackKey: pointer
): Window =
  ensureNativeOwnerRegistry()
  let key = if nativeWindow.isNil: fallbackKey else: nativeWindow.nativeWindowKey
  if key.isNil or key notin nativeWindowOwners:
    return nil
  nativeWindowOwners[key]

proc newWindow*(frame: Rect, title: string): Window =
  Window(xFrame: frame, xTitle: title)

proc newWindow*(x, y, width, height: float32, title: string): Window =
  newWindow(initRect(x, y, width, height), title)

proc frame*(window: Window): Rect =
  window.xFrame

proc title*(window: Window): string =
  window.xTitle

proc contentView*(window: Window): View =
  window.xContentView

proc setContentView*(window: Window, view: View) =
  window.xContentView = view

proc setTitle*(window: Window, title: string) =
  window.xTitle = title
  if window.xNativeReady and not window.xNativeWindow.isNil:
    window.xNativeWindow.title = title

proc firstResponder*(window: Window): Responder =
  window.xFirstResponder

proc makeFirstResponder*(window: Window, responder: Responder): bool =
  if not responder.isNil and not responder.acceptsFirstResponder():
    return false
  if not window.xFirstResponder.isNil:
    if not window.xFirstResponder.resignFirstResponder():
      return false
  if not responder.isNil and not responder.becomeFirstResponder():
    return false
  window.xFirstResponder = responder
  true

proc buildRenders*(window: Window): Renders =
  nimkitRendering.buildRenders(window.xContentView)

proc nativeWindowOrNil*(window: Window): siwinshim.Window =
  if window.isNil:
    return nil
  window.xNativeWindow

proc rendererOrNil*(
    window: Window
): figrender.FigRenderer[siwinshim.SiwinRenderBackend] =
  if window.isNil:
    return nil
  window.xRenderer

proc nativeReady*(window: Window): bool =
  (not window.isNil) and window.xNativeReady

proc isClosed*(window: Window): bool =
  window.isNil or window.xClosed

proc isVisible*(window: Window): bool =
  (not window.isNil) and window.xVisibleRequested and not window.xClosed

proc makeKeyAndOrderFront*(window: Window) =
  if window.isNil:
    return
  window.xClosed = false
  window.xVisibleRequested = true
  if window.xNativeReady and not window.xNativeWindow.isNil:
    if window.xNativeWindow.visible() and not window.xNativeWindow.focused():
      window.xNativeWindow.visible = false
    window.xNativeWindow.visible = true

proc orderFront*(window: Window) =
  window.makeKeyAndOrderFront()

proc orderOut*(window: Window) =
  if window.isNil:
    return
  window.xVisibleRequested = false
  if window.xNativeReady and not window.xNativeWindow.isNil:
    window.xNativeWindow.visible = false

proc close*(window: Window) =
  if window.isNil:
    return
  window.xClosed = true
  window.xVisibleRequested = false
  let nativeWindow = window.xNativeWindow
  if window.xNativeReady and not window.xNativeWindow.isNil:
    siwinshim.close(window.xNativeWindow)
  unregisterNativeWindowOwner(nativeWindow)
  window.xNativeReady = false
  window.xNativeWindow = nil
  window.xRenderer = nil

proc clickAt*(window: Window, point: Point): bool =
  if window.xContentView.isNil:
    return false
  window.xContentView.clickAt(point)

proc dispatchKeyDown*(window: Window, event: types.KeyEvent): bool =
  if not window.xFirstResponder.isNil:
    var value: EmptyArgs
    if window.xFirstResponder.perform(
      keyDownSelector(), KeyEventArgs(event: event), value
    ):
      return true
  if window.xContentView.isNil:
    return false
  window.xContentView.dispatchKeyDown(event)

proc syncNativeGeometry(window: Window): Vec2 =
  let nativeWindow = window.xNativeWindow
  result = nativeWindow.logicalSize()
  if result.x <= 0.0'f32 or result.y <= 0.0'f32:
    result = vec2(
      max(window.xFrame.size.width, 1.0'f32), max(window.xFrame.size.height, 1.0'f32)
    )

  window.xFrame.size = initSize(result.x, result.y)
  if not window.xContentView.isNil:
    window.xContentView.setFrame(initRect(0.0, 0.0, result.x, result.y))

proc renderNativeWindow*(window: Window) =
  if window.isNil or not window.xNativeReady:
    return
  let nativeWindow = window.xNativeWindow
  let renderer = window.xRenderer
  if nativeWindow.isNil or renderer.isNil or not nativeWindow.opened():
    return

  let logicalSize = window.syncNativeGeometry()
  var renders = window.buildRenders()
  renderer.beginFrame()
  renderer.renderFrame(renders, logicalSize)
  renderer.endFrame()

proc toNimkitMouseButton(button: siwinshim.MouseButton): types.MouseButton =
  case button
  of siwinshim.MouseButton.left: mbPrimary
  of siwinshim.MouseButton.right: mbSecondary
  else: mbOther

proc toNimkitModifiers(modifiers: set[siwinshim.ModifierKey]): set[types.KeyModifier] =
  if siwinshim.ModifierKey.shift in modifiers:
    result.incl kmShift
  if siwinshim.ModifierKey.control in modifiers:
    result.incl kmControl
  if siwinshim.ModifierKey.alt in modifiers:
    result.incl kmOption
  if siwinshim.ModifierKey.system in modifiers:
    result.incl kmCommand

proc keyText(key: siwinshim.Key): string =
  case key
  of siwinshim.Key.space: " "
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

proc dispatchNativeMouseButton(window: Window, event: siwinshim.MouseButtonEvent) =
  if window.xContentView.isNil:
    return
  let nativeWindow = if event.window.isNil: window.xNativeWindow else: event.window
  if nativeWindow.isNil:
    return
  let point = nativeMousePoint(nativeWindow)
  let hit = window.xContentView.hitTest(point)
  if hit.isNil:
    return
  if hit.acceptsFirstResponder():
    discard window.makeFirstResponder(hit)
  let mouseEvent =
    MouseEvent(location: point, button: event.button.toNimkitMouseButton, clickCount: 1)
  if event.pressed:
    discard hit.dispatchMouseDown(mouseEvent)
  else:
    discard hit.dispatchMouseUp(mouseEvent)

proc dispatchNativeKey(window: Window, event: siwinshim.KeyEvent) =
  if event.pressed and event.key == siwinshim.Key.escape:
    window.close()
    return
  if not event.pressed:
    return
  discard window.dispatchKeyDown(
    types.KeyEvent(
      text: event.key.keyText,
      keyCode: event.key.ord,
      modifiers: event.modifiers.toNimkitModifiers,
    )
  )

proc dispatchNativeTextInput(window: Window, event: siwinshim.TextInputEvent) =
  if event.text.len == 0:
    return
  discard window.dispatchKeyDown(types.KeyEvent(text: event.text, keyCode: 0))

proc ensureNativeWindow*(window: Window) =
  if window.isNil:
    return
  if window.xNativeReady:
    if not window.xNativeWindow.isNil and not window.xNativeWindow.closed():
      return
    window.xNativeReady = false
    window.xNativeWindow = nil
    window.xRenderer = nil

  let size = ivec2(
    max(window.xFrame.size.width, 1.0'f32).int32,
    max(window.xFrame.size.height, 1.0'f32).int32,
  )
  window.xNativeWindow = siwinshim.newSiwinWindow(
    size = size, title = window.xTitle, vsync = true, resizable = true
  )
  window.xNativeWindow.pos =
    ivec2(window.xFrame.origin.x.int32, window.xFrame.origin.y.int32)
  window.xAutoScale = window.xNativeWindow.configureUiScale()
  window.xRenderer = figrender.newFigRenderer(
    atlasSize = 1024, backendState = siwinshim.SiwinRenderBackend()
  )
  window.xRenderer.setupBackend(window.xNativeWindow)
  window.registerNativeWindowOwner()

  let ownerKey = window.xNativeWindow.nativeWindowKey
  window.xNativeWindow.eventsHandler = siwinshim.WindowEventsHandler(
    onClose: proc(event: siwinshim.CloseEvent) =
      let owner = ownerForNativeWindow(event.window, ownerKey)
      if owner.isNil:
        return
      owner.xClosed = true
      owner.xVisibleRequested = false
      unregisterNativeWindowOwner(owner.xNativeWindow)
      owner.xNativeReady = false
      owner.xNativeWindow = nil
      owner.xRenderer = nil,
    onResize: proc(event: siwinshim.ResizeEvent) =
      let window = ownerForNativeWindow(event.window, ownerKey)
      if window.isNil:
        return
      let nativeWindow = if event.window.isNil: window.xNativeWindow else: event.window
      if nativeWindow.isNil:
        return
      nativeWindow.refreshUiScale(window.xAutoScale)
      window.renderNativeWindow()
      siwinshim.presentNow(nativeWindow),
    onWindowMove: proc(event: siwinshim.WindowMoveEvent) =
      let window = ownerForNativeWindow(event.window, ownerKey)
      if window.isNil:
        return
      window.xFrame.origin = initPoint(event.pos.x.float32, event.pos.y.float32),
    onMouseButton: proc(event: siwinshim.MouseButtonEvent) =
      let window = ownerForNativeWindow(event.window, ownerKey)
      if window.isNil:
        return
      window.dispatchNativeMouseButton(event),
    onRender: proc(event: siwinshim.RenderEvent) =
      let window = ownerForNativeWindow(event.window, ownerKey)
      if window.isNil:
        return
      window.renderNativeWindow(),
    onKey: proc(event: siwinshim.KeyEvent) =
      let window = ownerForNativeWindow(event.window, ownerKey)
      if window.isNil:
        return
      window.dispatchNativeKey(event),
    onTextInput: proc(event: siwinshim.TextInputEvent) =
      let window = ownerForNativeWindow(event.window, ownerKey)
      if window.isNil:
        return
      window.dispatchNativeTextInput(event),
  )

  window.xNativeWindow.firstStep()
  window.xNativeWindow.refreshUiScale(window.xAutoScale)
  window.xNativeReady = true
  if window.xVisibleRequested:
    window.xNativeWindow.visible = true

proc pumpNativeWindowFrame*(window: Window) =
  if window.isNil or not window.xVisibleRequested or window.xClosed:
    return
  window.ensureNativeWindow()
  let nativeWindow = window.xNativeWindow
  if nativeWindow.isNil or not nativeWindow.opened():
    return
  nativeWindow.redraw()
  nativeWindow.step()
  if nativeWindow.closed():
    window.xClosed = true
    window.xVisibleRequested = false
