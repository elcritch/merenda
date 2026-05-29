import figdraw/figrender as figrender
from figdraw/fignodes import Renders
import figdraw/windowing/siwinshim as siwinshim

import ./backend as nimkitBackend
import ./rendering as nimkitRendering
import ./selectors
import ./theme
import ./types
import ./views

type Window* = ref object of Responder
  xFrame: Rect
  xTitle: string
  xContentView: View
  xFirstResponder: Responder
  xHostWindow: HostWindow
  xMouseTrackingView: View
  xVisibleRequested: bool
  xClosed: bool

proc newWindow*(frame: Rect, title: string): Window =
  result = Window(xFrame: frame, xTitle: title)
  initResponder(result)

proc newWindow*(x, y, width, height: float32, title: string): Window =
  newWindow(initRect(x, y, width, height), title)

proc frame*(window: Window): Rect =
  window.xFrame

proc title*(window: Window): string =
  window.xTitle

proc contentView*(window: Window): View =
  window.xContentView

proc makeFirstResponder*(window: Window, responder: Responder): bool

proc setContentView*(window: Window, view: View) =
  if window.xContentView == view:
    window.xMouseTrackingView = nil
    return

  let oldContent = window.xContentView
  if not oldContent.isNil:
    if not window.xFirstResponder.isNil and window.xFirstResponder of View:
      let firstResponderView = View(window.xFirstResponder)
      if oldContent.containsView(firstResponderView):
        if not window.makeFirstResponder(nil):
          window.xFirstResponder = nil
    oldContent.moveToWindowOwner(nil)
    oldContent.clearSuperviewForWindowOwner()

  if not view.isNil:
    if not view.superview.isNil:
      view.removeFromSuperview()
    view.clearSuperviewForWindowOwner()
    view.setNextResponder(window)
    view.moveToWindowOwner(window)

  window.xContentView = view
  window.xMouseTrackingView = nil

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

proc buildRenders*(window: Window, appearance: Appearance): Renders =
  nimkitRendering.buildRenders(window.xContentView, appearance)

proc buildRenders*(window: Window, theme: Theme): Renders =
  nimkitRendering.buildRenders(window.xContentView, theme)

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

proc mouseDownAt*(
  window: Window, point: Point, button = mbPrimary, clickCount = 1
): bool

proc mouseUpAt*(window: Window, point: Point, button = mbPrimary, clickCount = 1): bool

proc clickAt*(window: Window, point: Point): bool =
  if not window.mouseDownAt(point):
    return false
  window.mouseUpAt(point)

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

proc contentPoint(window: Window, windowPoint: Point): Point =
  window.xContentView.pointFromWindow(windowPoint)

proc localMouseEvent(
    target, contentView: View, contentPoint: Point, event: MouseEvent
): MouseEvent =
  MouseEvent(
    location: target.pointFromView(contentPoint, contentView),
    button: event.button,
    clickCount: event.clickCount,
  )

proc dispatchMouseButton(window: Window, event: MouseEvent, pressed: bool): bool =
  if window.xContentView.isNil:
    return false
  let contentPoint = window.contentPoint(event.location)
  var target: View
  if pressed:
    target = window.xContentView.hitTest(contentPoint)
    window.xMouseTrackingView = target
    if target.isNil:
      return false
    if target.acceptsFirstResponder():
      discard window.makeFirstResponder(target)
  else:
    target = window.xMouseTrackingView
    if target.isNil:
      target = window.xContentView.hitTest(contentPoint)
    window.xMouseTrackingView = nil
    if target.isNil:
      return false

  let localEvent = target.localMouseEvent(window.xContentView, contentPoint, event)
  if pressed:
    result = target.dispatchMouseDown(localEvent)
  else:
    result = target.dispatchMouseUp(localEvent)

proc dispatchMouseMove(window: Window, event: MouseEvent, dragging: bool): bool =
  if window.xContentView.isNil:
    return false
  let contentPoint = window.contentPoint(event.location)
  var target: View
  if dragging:
    target = window.xMouseTrackingView
    if target.isNil:
      target = window.xContentView.hitTest(contentPoint)
  else:
    target = window.xContentView.hitTest(contentPoint)
  if target.isNil:
    return false

  let localEvent = target.localMouseEvent(window.xContentView, contentPoint, event)
  if dragging:
    result = target.dispatchMouseDragged(localEvent)
  else:
    result = target.dispatchMouseMoved(localEvent)

proc mouseDownAt*(
    window: Window, point: Point, button = mbPrimary, clickCount = 1
): bool =
  window.dispatchMouseButton(
    MouseEvent(location: point, button: button, clickCount: clickCount), true
  )

proc mouseUpAt*(
    window: Window, point: Point, button = mbPrimary, clickCount = 1
): bool =
  window.dispatchMouseButton(
    MouseEvent(location: point, button: button, clickCount: clickCount), false
  )

proc mouseMovedAt*(window: Window, point: Point): bool =
  window.dispatchMouseMove(
    MouseEvent(location: point, button: mbPrimary, clickCount: 0), dragging = false
  )

proc mouseDraggedAt*(window: Window, point: Point, button = mbPrimary): bool =
  window.dispatchMouseMove(
    MouseEvent(location: point, button: button, clickCount: 0), dragging = true
  )

proc dispatchHostMouseButton(window: Window, event: MouseEvent, pressed: bool) =
  discard window.dispatchMouseButton(event, pressed)

proc dispatchHostMouseMove(window: Window, event: MouseEvent, dragging: bool) =
  discard window.dispatchMouseMove(event, dragging)

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
      onMouseMove: proc(event: MouseEvent, dragging: bool) =
        window.dispatchHostMouseMove(event, dragging),
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
