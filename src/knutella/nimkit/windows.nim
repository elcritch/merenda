import figdraw/figrender as figrender
from figdraw/fignodes import Renders
import figdraw/windowing/siwinshim as siwinshim

import ./backend as nimkitBackend
import ./rendering as nimkitRendering
import ./selectors
import ./types
import ./views

type Window* = ref object
  xFrame: Rect
  xTitle: string
  xContentView: View
  xFirstResponder: Responder
  xHostWindow: HostWindow
  xVisibleRequested: bool
  xClosed: bool

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
  window.xHostWindow.setTitle(title)

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
  window.xHostWindow.nativeWindowOrNil()

proc rendererOrNil*(
    window: Window
): figrender.FigRenderer[siwinshim.SiwinRenderBackend] =
  if window.isNil:
    return nil
  window.xHostWindow.rendererOrNil()

proc nativeReady*(window: Window): bool =
  (not window.isNil) and window.xHostWindow.isReady

proc isClosed*(window: Window): bool =
  window.isNil or window.xClosed

proc isVisible*(window: Window): bool =
  (not window.isNil) and window.xVisibleRequested and not window.xClosed

proc makeKeyAndOrderFront*(window: Window) =
  if window.isNil:
    return
  window.xClosed = false
  window.xVisibleRequested = true
  window.xHostWindow.setVisible(true)

proc orderFront*(window: Window) =
  window.makeKeyAndOrderFront()

proc orderOut*(window: Window) =
  if window.isNil:
    return
  window.xVisibleRequested = false
  window.xHostWindow.setVisible(false)

proc close*(window: Window) =
  if window.isNil:
    return
  window.xClosed = true
  window.xVisibleRequested = false
  window.xHostWindow.close()
  window.xHostWindow = nil

proc clickAt*(window: Window, point: Point): bool =
  if window.xContentView.isNil:
    return false
  window.xContentView.clickAt(point)

proc dispatchKeyDown*(window: Window, event: types.KeyEvent): bool =
  if not window.xFirstResponder.isNil:
    if window.xFirstResponder.sendIfHandled(keyDown(), event):
      return true
  if window.xContentView.isNil:
    return false
  window.xContentView.dispatchKeyDown(event)

proc syncNativeGeometry(window: Window): Size =
  result = window.xHostWindow.logicalSize(window.xFrame.size)
  window.xFrame.size = result
  if not window.xContentView.isNil:
    window.xContentView.setFrame(initRect(0.0, 0.0, result.width, result.height))

proc renderNativeWindow*(window: Window) =
  if window.isNil or not window.nativeReady:
    return

  let logicalSize = window.syncNativeGeometry()
  var renders = window.buildRenders()
  window.xHostWindow.render(renders, logicalSize)

proc dispatchHostMouseButton(window: Window, event: MouseEvent, pressed: bool) =
  if window.xContentView.isNil:
    return
  let hit = window.xContentView.hitTest(event.location)
  if hit.isNil:
    return
  if hit.acceptsFirstResponder():
    discard window.makeFirstResponder(hit)
  if pressed:
    discard hit.dispatchMouseDown(event)
  else:
    discard hit.dispatchMouseUp(event)

proc dispatchHostKey(window: Window, event: HostKeyEvent) =
  if event.pressed and event.isEscape:
    window.close()
    return
  if event.pressed:
    discard window.dispatchKeyDown(event.event)

proc dispatchHostTextInput(window: Window, text: string) =
  if text.len > 0:
    discard window.dispatchKeyDown(types.KeyEvent(text: text, keyCode: 0))

proc markHostClosed(window: Window) =
  if window.isNil:
    return
  window.xClosed = true
  window.xVisibleRequested = false

proc ensureNativeWindow*(window: Window) =
  if window.isNil:
    return
  if window.xHostWindow.isReady:
    return

  window.xHostWindow = createHostWindow(
    window.xFrame,
    window.xTitle,
    HostWindowCallbacks(
      onClose: proc() =
        window.markHostClosed(),
      onResize: proc() =
        discard window.syncNativeGeometry(),
      onMove: proc(pos: Point) =
        window.xFrame.origin = pos,
      onMouseButton: proc(event: MouseEvent, pressed: bool) =
        window.dispatchHostMouseButton(event, pressed),
      onKey: proc(event: HostKeyEvent) =
        window.dispatchHostKey(event),
      onTextInput: proc(text: string) =
        window.dispatchHostTextInput(text),
      onRender: proc() =
        window.renderNativeWindow(),
    ),
  )
  if window.xVisibleRequested:
    window.xHostWindow.setVisible(true)

proc pumpNativeWindowFrame*(window: Window) =
  if window.isNil or not window.xVisibleRequested or window.xClosed:
    return
  window.ensureNativeWindow()
  if window.xHostWindow.isReady:
    window.xHostWindow.pump()

proc rawInputToLogical*(
    rawPos: siwinshim.Vec2, inputSize: siwinshim.IVec2, logicalSize: siwinshim.Vec2
): siwinshim.Vec2 =
  nimkitBackend.rawInputToLogical(rawPos, inputSize, logicalSize)
