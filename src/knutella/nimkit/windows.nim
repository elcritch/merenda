import std/[options, times]

import figdraw/figrender as figrender
from figdraw/fignodes import Renders
import figdraw/windowing/siwinshim as siwinshim

import ./backend as nimkitBackend
import ./keybindings
import ./rendering as nimkitRendering
import ./selectors
import ./theme
import ./types
import ./views

type Window* = ref object of Responder
  xFrame: Rect
  xTitle: string
  xContentView: View
  xAppearance: Appearance
  xHasAppearance: bool
  xInheritedAppearance: Appearance
  xHasInheritedAppearance: bool
  xFirstResponder: Responder
  xKeyBindings: KeyBindingTable
  xHostWindow: HostWindow
  xMouseCaptureView: View
  xMouseActiveView: View
  xMouseHoverView: View
  xMouseClickCount: int
  xLastClickPoint: Point
  xLastClickButton: types.MouseButton
  xLastClickView: View
  xLastClickCount: int
  xLastClickTime: float
  xHasLastClick: bool
  xVisibleRequested: bool
  xClosed: bool

type EventDispatchResult = object
  handled: bool
  responder: Responder

const ClickSlop = 4.0'f32
const ClickInterval = 0.5

proc newWindow*(frame: Rect, title: string): Window =
  result = Window(xFrame: frame, xTitle: title, xKeyBindings: initDefaultKeyBindings())
  initResponder(result)

proc newWindow*(x, y, width, height: float32, title: string): Window =
  newWindow(initRect(x, y, width, height), title)

proc frame*(window: Window): Rect =
  window.xFrame

proc title*(window: Window): string =
  window.xTitle

proc contentView*(window: Window): View =
  window.xContentView

proc keyBindings*(window: Window): KeyBindingTable =
  if window.isNil:
    return KeyBindingTable()
  window.xKeyBindings

proc setKeyBindings*(window: Window, bindings: KeyBindingTable) =
  if window.isNil:
    return
  window.xKeyBindings = bindings

proc setKeyBindingProfile*(window: Window, profile: KeyBindingProfile) =
  if window.isNil:
    return
  window.xKeyBindings = initDefaultKeyBindings(profile)

proc addKeyBinding*(window: Window, stroke: KeyStroke, selector: CommandSelector) =
  if window.isNil:
    return
  window.xKeyBindings.add(stroke, selector)

proc removeKeyBinding*(window: Window, stroke: KeyStroke): bool {.discardable.} =
  if window.isNil:
    return false
  window.xKeyBindings.remove(stroke)

proc clearKeyBindings*(window: Window) =
  if window.isNil:
    return
  window.xKeyBindings.clear()

proc bindKey*(
    window: Window, text: string, modifiers: set[KeyModifier], selector: CommandSelector
) =
  if window.isNil:
    return
  window.xKeyBindings.bindKey(text, modifiers, selector)

proc bindKey*(
    window: Window,
    key: types.Key,
    modifiers: set[KeyModifier],
    selector: CommandSelector,
) =
  if window.isNil:
    return
  window.xKeyBindings.bindKey(key, modifiers, selector)

proc bindKey*(
    window: Window, keyCode: int, modifiers: set[KeyModifier], selector: CommandSelector
) =
  if window.isNil:
    return
  window.xKeyBindings.bindKey(keyCode, modifiers, selector)

proc bindShortcut*(
    window: Window,
    text: string,
    modifiers: set[ShortcutModifier],
    selector: CommandSelector,
) =
  if window.isNil:
    return
  window.xKeyBindings.bindShortcut(text, modifiers, selector)

proc bindShortcut*(
    window: Window,
    key: types.Key,
    modifiers: set[ShortcutModifier],
    selector: CommandSelector,
) =
  if window.isNil:
    return
  window.xKeyBindings.bindShortcut(key, modifiers, selector)

proc bindShortcuts*(
    window: Window,
    text: string,
    modifiers: set[ShortcutModifier],
    selector: CommandSelector,
) =
  window.bindShortcut(text, modifiers, selector)

proc bindShortcuts*(
    window: Window,
    key: types.Key,
    modifiers: set[ShortcutModifier],
    selector: CommandSelector,
) =
  window.bindShortcut(key, modifiers, selector)

proc makeFirstResponder*(window: Window, responder: Responder): bool
proc effectiveAppearance*(window: Window): Appearance
proc dispatchKeyEventInChain(
  window: Window, target: Responder, event: types.KeyEvent
): EventDispatchResult

proc propagateAppearance(window: Window) =
  if window.isNil or window.xContentView.isNil:
    return
  window.xContentView.setInheritedAppearance(window.effectiveAppearance())

proc hasAppearance*(window: Window): bool =
  (not window.isNil) and window.xHasAppearance

proc appearance*(window: Window): Appearance =
  if window.isNil or not window.xHasAppearance:
    return initAppearance()
  window.xAppearance

proc effectiveAppearance*(window: Window): Appearance =
  if window.isNil:
    return initAppearance()
  if window.xHasAppearance:
    return window.xAppearance
  if window.xHasInheritedAppearance:
    return window.xInheritedAppearance
  initAppearance()

proc setAppearance*(window: Window, appearance: Appearance) =
  if window.isNil:
    return
  window.xAppearance = appearance
  window.xHasAppearance = true
  window.propagateAppearance()

proc clearAppearance*(window: Window) =
  if window.isNil or not window.xHasAppearance:
    return
  window.xAppearance = Appearance()
  window.xHasAppearance = false
  window.propagateAppearance()

proc setInheritedAppearance*(window: Window, appearance: Appearance) =
  if window.isNil:
    return
  window.xInheritedAppearance = appearance
  window.xHasInheritedAppearance = true
  if not window.xHasAppearance:
    window.propagateAppearance()

proc clearInheritedAppearance*(window: Window) =
  if window.isNil:
    return
  window.xInheritedAppearance = Appearance()
  window.xHasInheritedAppearance = false
  if not window.xHasAppearance:
    window.propagateAppearance()

proc clearMouseState(window: Window) =
  if not window.xMouseActiveView.isNil:
    window.xMouseActiveView.setActive(false)
  if not window.xMouseHoverView.isNil:
    window.xMouseHoverView.setHovered(false)
  window.xMouseCaptureView = nil
  window.xMouseActiveView = nil
  window.xMouseHoverView = nil
  window.xMouseClickCount = 0
  window.xLastClickView = nil
  window.xHasLastClick = false
  window.xLastClickCount = 0

proc setMouseActiveView(window: Window, view: View) =
  if window.xMouseActiveView == view:
    return
  if not window.xMouseActiveView.isNil:
    window.xMouseActiveView.setActive(false)
  window.xMouseActiveView = view
  if not view.isNil:
    view.setActive(true)

proc setContentView*(window: Window, view: View) =
  if window.xContentView == view:
    window.clearMouseState()
    return

  let oldContent = window.xContentView
  if not oldContent.isNil:
    window.clearMouseState()
    if not window.xFirstResponder.isNil and window.xFirstResponder of View:
      let firstResponderView = View(window.xFirstResponder)
      if oldContent.containsView(firstResponderView):
        if not window.makeFirstResponder(nil):
          window.xFirstResponder = nil
    oldContent.moveToWindowOwner(nil)
    oldContent.clearSuperviewForWindowOwner()
    oldContent.clearInheritedAppearance()

  if not view.isNil:
    if not view.superview.isNil:
      view.removeFromSuperview()
    view.clearSuperviewForWindowOwner()
    view.setNextResponder(window)
    view.moveToWindowOwner(window)
    view.setInheritedAppearance(window.effectiveAppearance())

  window.xContentView = view
  window.clearMouseState()

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
  nimkitRendering.buildRenders(window.xContentView, window.effectiveAppearance())

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
  window: Window,
  point: Point,
  button = mbPrimary,
  clickCount = 0,
  modifiers: set[KeyModifier] = {},
  timestamp = 0.0,
): bool

proc mouseUpAt*(
  window: Window,
  point: Point,
  button = mbPrimary,
  clickCount = 0,
  modifiers: set[KeyModifier] = {},
  timestamp = 0.0,
): bool

proc clickAt*(window: Window, point: Point): bool =
  if not window.mouseDownAt(point):
    return false
  window.mouseUpAt(point)

proc keyDispatchTarget(window: Window): Responder =
  if not window.xFirstResponder.isNil:
    return window.xFirstResponder
  if window.xContentView.isNil:
    return nil
  Responder(window.xContentView)

proc dispatchCommandInChain(
    target: Responder, selector: CommandSelector
): EventDispatchResult =
  if target.isNil:
    return
  let args = TryToPerformArgs(selector: selector, sender: DynamicAgent(target))
  if target.tryToPerform(args):
    result.handled = true
    result.responder = target

proc dispatchKeyCommand(
    window: Window, target: Responder, event: types.KeyEvent
): EventDispatchResult =
  let command = window.xKeyBindings.commandFor(event)
  if command.isNone:
    return
  dispatchCommandInChain(target, command.get())

proc dispatchKeyDown*(window: Window, event: types.KeyEvent): bool =
  let target = window.keyDispatchTarget()
  if target.isNil:
    return false
  let commandDispatch = window.dispatchKeyCommand(target, event)
  if commandDispatch.handled:
    return true
  window.dispatchKeyEventInChain(target, event).handled

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
  result = MouseEvent(
    location: target.pointFromView(contentPoint, contentView),
    button: event.button,
    clickCount: event.clickCount,
    modifiers: event.modifiers,
    timestamp: event.timestamp,
  )

proc localScrollEvent(
    target, contentView: View, contentPoint: Point, event: types.ScrollEvent
): types.ScrollEvent =
  result = types.ScrollEvent(
    location: target.pointFromView(contentPoint, contentView),
    deltaX: event.deltaX,
    deltaY: event.deltaY,
    modifiers: event.modifiers,
    timestamp: event.timestamp,
  )

proc localKeyEvent(
    target, contentView: View, contentPoint: Point, event: types.KeyEvent
): types.KeyEvent =
  event

proc eventTimestamp(timestamp: float): float =
  if timestamp > 0.0:
    timestamp
  else:
    epochTime()

proc isRepeatClick(window: Window, target: View, event: MouseEvent, now: float): bool =
  if not window.xHasLastClick or window.xLastClickView != target or
      window.xLastClickButton != event.button:
    return false
  if now - window.xLastClickTime > ClickInterval:
    return false
  abs(window.xLastClickPoint.x - event.location.x) <= ClickSlop and
    abs(window.xLastClickPoint.y - event.location.y) <= ClickSlop

proc nextClickCount(window: Window, target: View, event: MouseEvent): int =
  let now = eventTimestamp(event.timestamp)
  if event.clickCount > 0:
    result = event.clickCount
  elif window.isRepeatClick(target, event, now):
    result = window.xLastClickCount + 1
  else:
    result = 1

  window.xLastClickPoint = event.location
  window.xLastClickButton = event.button
  window.xLastClickView = target
  window.xLastClickCount = result
  window.xLastClickTime = now
  window.xHasLastClick = true
  window.xMouseClickCount = result

proc dispatchEventInChain[A, R](
    window: Window,
    target: Responder,
    contentPoint: Point,
    event: A,
    selector: Selector[A, R],
    localize: proc(target, contentView: View, contentPoint: Point, event: A): A,
): EventDispatchResult =
  var responder = target
  while not responder.isNil:
    var localEvent = event
    if responder of View:
      localEvent = localize(View(responder), window.xContentView, contentPoint, event)
    if responder.sendLocalIfHandled(selector, localEvent):
      result.handled = true
      result.responder = responder
      return
    responder = responder.nextResponder()

proc dispatchMouseEventInChain(
    window: Window,
    target: View,
    contentPoint: Point,
    event: MouseEvent,
    selector: MouseEventSelector,
): EventDispatchResult =
  window.dispatchEventInChain(
    Responder(target), contentPoint, event, selector, localMouseEvent
  )

proc dispatchScrollEventInChain(
    window: Window, target: View, contentPoint: Point, event: types.ScrollEvent
): EventDispatchResult =
  window.dispatchEventInChain(
    Responder(target), contentPoint, event, scrollWheel(), localScrollEvent
  )

proc dispatchKeyEventInChain(
    window: Window, target: Responder, event: types.KeyEvent
): EventDispatchResult =
  window.dispatchEventInChain(
    target, initPoint(0.0, 0.0), event, keyDown(), localKeyEvent
  )

proc updateHoverView(
    window: Window, target: View, contentPoint: Point, event: MouseEvent
): bool =
  if window.xMouseHoverView == target:
    return false

  let previous = window.xMouseHoverView
  if not previous.isNil:
    previous.setHovered(false)
    let localEvent = previous.localMouseEvent(window.xContentView, contentPoint, event)
    result = previous.handleMouseExited(localEvent)

  window.xMouseHoverView = target
  if not target.isNil:
    target.setHovered(true)
    let localEvent = target.localMouseEvent(window.xContentView, contentPoint, event)
    result = target.handleMouseEntered(localEvent) or result

proc dispatchMouseButton(window: Window, event: MouseEvent, pressed: bool): bool =
  if window.xContentView.isNil:
    return false
  let contentPoint = window.contentPoint(event.location)
  var dispatchEvent = event
  var target: View
  if pressed:
    target = window.xContentView.hitTest(contentPoint)
    window.xMouseCaptureView = target
    if target.isNil:
      return false
    dispatchEvent.clickCount = window.nextClickCount(target, event)
    if target.acceptsFirstResponder():
      discard window.makeFirstResponder(target)
  else:
    target = window.xMouseCaptureView
    if target.isNil:
      target = window.xContentView.hitTest(contentPoint)
    window.xMouseCaptureView = nil
    if target.isNil:
      window.setMouseActiveView(nil)
      return false
    if dispatchEvent.clickCount <= 0:
      dispatchEvent.clickCount = max(window.xMouseClickCount, 1)

  if pressed:
    let dispatch =
      window.dispatchMouseEventInChain(target, contentPoint, dispatchEvent, mouseDown())
    result = dispatch.handled
    if dispatch.handled and dispatch.responder of View:
      window.setMouseActiveView(View(dispatch.responder))
    else:
      window.setMouseActiveView(nil)
  else:
    let dispatch =
      window.dispatchMouseEventInChain(target, contentPoint, dispatchEvent, mouseUp())
    result = dispatch.handled
    window.setMouseActiveView(nil)
    window.xMouseClickCount = 0

proc dispatchMouseMove(window: Window, event: MouseEvent, dragging: bool): bool =
  if window.xContentView.isNil:
    return false
  let contentPoint = window.contentPoint(event.location)
  var target: View
  if dragging:
    target = window.xMouseCaptureView
    if target.isNil:
      target = window.xContentView.hitTest(contentPoint)
  else:
    target = window.xContentView.hitTest(contentPoint)

  if not dragging:
    result = window.updateHoverView(target, contentPoint, event)

  if target.isNil:
    return result

  if dragging:
    result = window.dispatchMouseEventInChain(
      target, contentPoint, event, mouseDragged()
    ).handled
  else:
    result =
      window.dispatchMouseEventInChain(target, contentPoint, event, mouseMoved()).handled or
      result

proc dispatchScrollWheel*(window: Window, event: types.ScrollEvent): bool =
  if window.xContentView.isNil:
    return false
  let contentPoint = window.contentPoint(event.location)
  let target = window.xContentView.hitTest(contentPoint)
  if target.isNil:
    return false
  window.dispatchScrollEventInChain(target, contentPoint, event).handled

proc mouseDownAt*(
    window: Window,
    point: Point,
    button = mbPrimary,
    clickCount = 0,
    modifiers: set[KeyModifier] = {},
    timestamp = 0.0,
): bool =
  window.dispatchMouseButton(
    MouseEvent(
      location: point,
      button: button,
      clickCount: clickCount,
      modifiers: modifiers,
      timestamp: eventTimestamp(timestamp),
    ),
    true,
  )

proc mouseUpAt*(
    window: Window,
    point: Point,
    button = mbPrimary,
    clickCount = 0,
    modifiers: set[KeyModifier] = {},
    timestamp = 0.0,
): bool =
  window.dispatchMouseButton(
    MouseEvent(
      location: point,
      button: button,
      clickCount: clickCount,
      modifiers: modifiers,
      timestamp: eventTimestamp(timestamp),
    ),
    false,
  )

proc scrollWheelAt*(
    window: Window,
    point: Point,
    deltaX = 0.0'f32,
    deltaY = 0.0'f32,
    modifiers: set[KeyModifier] = {},
    timestamp = 0.0,
): bool =
  window.dispatchScrollWheel(
    types.ScrollEvent(
      location: point,
      deltaX: deltaX,
      deltaY: deltaY,
      modifiers: modifiers,
      timestamp: eventTimestamp(timestamp),
    )
  )

proc mouseMovedAt*(
    window: Window, point: Point, modifiers: set[KeyModifier] = {}, timestamp = 0.0
): bool =
  window.dispatchMouseMove(
    MouseEvent(
      location: point,
      button: mbPrimary,
      clickCount: 0,
      modifiers: modifiers,
      timestamp: eventTimestamp(timestamp),
    ),
    dragging = false,
  )

proc mouseDraggedAt*(
    window: Window,
    point: Point,
    button = mbPrimary,
    modifiers: set[KeyModifier] = {},
    timestamp = 0.0,
): bool =
  window.dispatchMouseMove(
    MouseEvent(
      location: point,
      button: button,
      clickCount: 0,
      modifiers: modifiers,
      timestamp: eventTimestamp(timestamp),
    ),
    dragging = true,
  )

proc dispatchHostMouseButton(window: Window, event: MouseEvent, pressed: bool) =
  discard window.dispatchMouseButton(event, pressed)

proc dispatchHostMouseMove(window: Window, event: MouseEvent, dragging: bool) =
  discard window.dispatchMouseMove(event, dragging)

proc dispatchHostScroll(window: Window, event: types.ScrollEvent) =
  discard window.dispatchScrollWheel(event)

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
      onScroll: proc(event: types.ScrollEvent) =
        window.dispatchHostScroll(event),
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
