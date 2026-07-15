import std/[math, options, os, tables, times]

when defined(useNativeDynlib):
  import figdraw/dynlib as figrender
  from figdraw/dynlib import Renders
  import figdraw/dynlib as siwinshim
else:
  import figdraw as figrender
  from figdraw import Renders
  import figdraw/windowing/siwinshim as siwinshim
import sigils/core

import ../accessibility/accessibility
import ./backend as nimkitBackend
import ./animations
import ../responder/keybindings
import ../drawing/rendering as nimkitRendering
import ../foundation/events
import ../foundation/notifications
import ../text/fieldeditors
from ../text/textviews import
  TextView, editable, insertionPointBlinkPeriod, insertionPointVisible,
  isInsertableText, `insertionPointVisible=`
import ../foundation/selectors
import ../themes
import ../foundation/types
import ../foundation/undomanagers
import ../view/views

type
  WindowStyleMask* = enum
    wsmTitled
    wsmClosable
    wsmMiniaturizable
    wsmResizable
    wsmUtilityWindow
    wsmDocModalWindow
    wsmNonactivatingPanel

  WindowLevel* = enum
    wlNormal
    wlFloating
    wlModalPanel
    wlMainMenu
    wlStatus

  Panel* = Window

  AlertStyle* = enum
    asInformational
    asWarning
    asCritical

  Alert* = ref object of Responder
    messageText*: string
    informativeText*: string
    style*: AlertStyle
    buttons*: seq[string]
    buttonResponses*: seq[int]
    buttonViews*: seq[View]
    accessoryView*: View
    contentView*: View
    response*: int
    responseHandler*: proc(response: int) {.closure.}
    window*: Window

  OpenPanel* = ref object of Responder
    window*: Window
    directoryUrl*: string
    message*: string
    prompt*: string
    allowedFileTypes*: seq[string]
    selectedUrls*: seq[string]
    allowsMultipleSelection*: bool
    canChooseFiles*: bool
    canChooseDirectories*: bool
    accessoryView*: View
    contentView*: View
    urlField*: View
    buttonViews*: seq[View]
    response*: int
    responseHandler*: proc(response: int) {.closure.}

  SavePanel* = ref object of Responder
    window*: Window
    directoryUrl*: string
    message*: string
    prompt*: string
    nameFieldStringValue*: string
    allowedFileTypes*: seq[string]
    accessoryView*: View
    contentView*: View
    nameField*: View
    buttonViews*: seq[View]
    response*: int
    responseHandler*: proc(response: int) {.closure.}

  DismissReason* = enum
    tdrProgrammatic
    tdrOutsideClick
    tdrEscape
    tdrFocusChange
    tdrOwnerClosed
    tdrNativeDone

  TransientDismissHandler* = proc(reason: DismissReason) {.closure.}

  Window* = ref object of Responder
    xFrame: Rect
    xTitle: string
    xStyleMask: set[WindowStyleMask]
    xLevel: WindowLevel
    xDelegate: DynamicAgent
    xContentView: View
    xAppearance: Appearance
    xHasAppearance: bool
    xInheritedAppearance: Appearance
    xHasInheritedAppearance: bool
    xPopupPresentation: PopupPresentation
    xFirstResponder: Responder
    xFieldEditor: FieldEditor
    xInitialFirstResponder: View
    xFutureFirstResponder: Responder
    xAutorecalculatesKeyViewLoop: bool
    xIsKeyWindow: bool
    xIsMainWindow: bool
    xMiniaturized: bool
    xZoomed: bool
    xMinSize: Size
    xContentMinSize: Size
    xAutomaticContentMinSize: Size
    xAutomaticallyAdjustsContentMinSize: bool
    xAutomaticContentMinSizeNeedsUpdate: bool
    xUpdatingAutomaticContentMinSize: bool
    xMaxSize: Size
    xResizeIncrements: Size
    xFrameAutosaveName: string
    xKeyBindings: KeyBindingTable
    xHostWindow: HostWindow
    xThreadRenderer: ThreadRendererClient
    xThreadHost: ThreadHostClient
    xAnimationScheduler: AnimationScheduler
    xAnimationClock: AnimationSchedulerClock
    xInsertionPointBlinkAnimation: Animation
    xInsertionPointBlinkTarget: TextView
    xOwnerWindow: Window
    xAuxiliaryWindows: seq[Window]
    xSheet: Window
    xSheetParent: Window
    xIsPopup: bool
    xPopupPlacement: siwinshim.PopupPlacement
    xOnPopupDone: proc() {.closure.}
    xTransientSession: TransientSession
    xLastTransientDismissReason: DismissReason
    xMouseCaptureView: View
    xMouseActiveView: View
    xMouseHoverView: View
    xMousePolicyStopResponder: Responder
    xMouseTrackingEvent: MouseEvent
    xHasMouseTrackingEvent: bool
    xMomentumScrollTarget: View
    xMomentumScrollContentPoint: Point
    xMouseClickCount: int
    xLastClickPoint: Point
    xLastClickButton: events.MouseButton
    xLastClickView: View
    xLastClickCount: int
    xLastClickTime: float
    xHasLastClick: bool
    xVisibleRequested: bool
    xClosed: bool
    xUndoManager: UndoManager

  TransientSession = object
    active: bool
    ownerResponder: Responder
    transientWindow: Window
    restoreWindow: Window
    restoreResponder: Responder
    onDismiss: TransientDismissHandler

type EventDispatchResult = object
  handled: bool
  responder: Responder

type CaretBlinkAnimation = ref object of Animation
  textView: TextView

var
  savedWindowFrames: Table[string, Rect]
  savedWindowFramesReady: bool

protocol WindowLifecycleProtocol {.selectorScope: protocol.}:
  method shouldSetContentView*(v: View): bool {.optional.}

protocol WindowLifecycleEvents:
  proc willSetContentView*(w: Window, v: View) {.signal.}
  proc didSetContentView*(w: Window, oldView: View) {.signal.}
  proc willClose*(w: Window) {.signal.}
  proc didClose*(w: Window) {.signal.}

protocol WindowFocusProtocol {.selectorScope: protocol.}:
  method shouldMakeFirstResponder*(r: Responder): bool {.optional.}

protocol WindowFocusEvents:
  proc didChangeFirstResponder*(w: Window, previous: Responder) {.signal.}
  proc didBecomeKeyWindow*(w: Window) {.signal.}
  proc didResignKeyWindow*(w: Window) {.signal.}
  proc didBecomeMainWindow*(w: Window) {.signal.}
  proc didResignMainWindow*(w: Window) {.signal.}

protocol WindowDelegateProtocol:
  method windowShouldClose*(w: Window): bool {.optional.}
  method windowWillClose*(w: Window) {.optional.}
  method windowDidClose*(w: Window) {.optional.}
  method windowDidBecomeKey*(w: Window) {.optional.}
  method windowDidResignKey*(w: Window) {.optional.}
  method windowDidBecomeMain*(w: Window) {.optional.}
  method windowDidResignMain*(w: Window) {.optional.}
  method windowWillBeginSheet*(sheet: Window) {.optional.}
  method windowDidEndSheet*(sheet: Window) {.optional.}

protocol WindowAppearanceEvents:
  proc didChangeEffectiveAppearance*(w: Window, appearance: Appearance) {.signal.}

protocol WindowPopupProtocol {.selectorScope: protocol.}:
  method shouldDismiss*(reason: DismissReason): bool {.optional.}

protocol WindowPopupEvents:
  proc didDismissTransientSession*(w: Window, reason: DismissReason) {.signal.}
  proc didChangePopupPresentation*(w: Window, present: PopupPresentation) {.signal.}

const ClickSlop = 4.0'f32
const ClickInterval = 0.5
const WindowDidOrderFrontSelector = "_nimkitWindowDidOrderFront"
const WindowDidOrderBackSelector = "_nimkitWindowDidOrderBack"
const WindowDidOrderOutSelector = "_nimkitWindowDidOrderOut"
const WindowDidCloseSelector = "_nimkitWindowDidClose"

proc ensureWindowFrameStore() =
  if not savedWindowFramesReady:
    savedWindowFrames = initTable[string, Rect]()
    savedWindowFramesReady = true

func defaultWindowFrame*(): Rect =
  rect(100.0'f32, 100.0'f32, 640.0'f32, 480.0'f32)

func nativePopupWindowsSupported*(): bool =
  when defined(android) or defined(emscripten) or defined(js) or defined(wasm):
    false
  else:
    true

func platformDefaultPopupPresentation*(): PopupPresentation =
  when defined(nimkitInlinePopups) or defined(emscripten) or defined(js) or defined(
    wasm
  ):
    result = ppInline
  else:
    result = ppAutomatic

proc makeFirstResponder*(window: Window, responder: Responder): bool
proc makeFirstResponder*(window: Window, responder: Responder, focusVisible: bool): bool
proc fieldEditor*(window: Window): FieldEditor
proc fieldEditorClient*(window: Window): Responder
proc initialFirstResponder*(window: Window): View
proc setInitialFirstResponder*(window: Window, view: View)
proc autorecalculatesKeyViewLoop*(window: Window): bool
proc setAutorecalculatesKeyViewLoop*(window: Window, value: bool)
proc recalculateKeyViewLoop*(window: Window)
proc selectKeyViewFollowingView*(window: Window, view: View): bool {.discardable.}
proc selectKeyViewPrecedingView*(window: Window, view: View): bool {.discardable.}
proc effectiveAppearance*(window: Window): Appearance
proc effectivePopupPresentation*(window: Window): PopupPresentation
proc close*(window: Window)
proc releaseThreadRenderer(window: Window, waitForRelease: bool)
proc setKeyWindow*(window: Window, value: bool)
proc setMainWindow*(window: Window, value: bool)
proc postWindowNotification(window: Window, kind: NotificationKind)
proc postWindowAppearanceNotification(window: Window)
proc canClose*(window: Window): bool
proc canMiniaturize*(window: Window): bool
proc canZoom*(window: Window): bool
proc validateWindowCommand*(window: Window, selector: ActionSelector): Option[bool]
proc undoManagerFor*(window: Window): UndoManager
proc setUndoManager*(window: Window, undoManager: UndoManager)
proc miniaturize*(window: Window)
proc deminiaturize*(window: Window)
proc zoom*(window: Window)
proc endSheet*(window: Window, sheet: Window = nil)
proc closeAuxiliaryWindows(window: Window, notifyDone = true)
proc hasActiveTransientSession*(window: Window): bool
proc beginTransientSession*(
  window: Window,
  owner: Responder,
  transientWindow: Window = nil,
  restoreResponder: Responder = nil,
  onDismiss: TransientDismissHandler = nil,
  restoreCurrentResponderIfNil = true,
)

proc dismissTransientSession*(
  window: Window, reason: DismissReason
): bool {.discardable.}

proc endTransientSession*(
  window: Window, reason = tdrProgrammatic
): bool {.discardable.}

proc nativeContentScale*(window: Window): float32
proc useThreadRenderer*(window: Window, renderer: ThreadRendererClient)
proc newPopupWindow*(
  owner: Window, anchorFrame: Rect, popupSize: Size, title = "Popup"
): Window

proc needsDisplayUpdate*(window: Window): bool
proc requestNativeDisplayUpdate*(window: Window)
proc requestNativeDisplayUpdateIfNeeded*(window: Window): bool {.discardable.}
proc animationScheduler*(window: Window): AnimationScheduler
proc animationClock*(window: Window): AnimationSchedulerClock
proc startAnimationClock*(window: Window)
proc stopAnimationClock*(window: Window)
proc startAnimation*(window: Window, animation: Animation): bool {.discardable.}
proc stopAnimation*(
  window: Window, animation: Animation, finished = false
): bool {.discardable.}

proc drainAnimations*(window: Window): int {.discardable.}
proc updateInsertionPointBlink(window: Window)

proc setPopupDoneHandler*(window: Window, handler: proc() {.closure.})
proc refreshAutomaticContentMinSize(window: Window)
proc syncNativeSizeLimits(window: Window)
proc dispatchKeyEventInChain(
  window: Window, target: Responder, event: events.KeyEvent, selector: KeyEventSelector
): EventDispatchResult

proc keyViewCommandStartView(window: Window, sender: DynamicAgent): View

protocol DefaultWindowKeyViewCommands of KeyViewCommandProtocol:
  method insertTab(window: Window, args: ActionArgs) =
    let start = window.keyViewCommandStartView(args.sender)
    discard window.selectKeyViewFollowingView(start)

  method insertBacktab(window: Window, args: ActionArgs) =
    let start = window.keyViewCommandStartView(args.sender)
    discard window.selectKeyViewPrecedingView(start)

  method selectNextKeyView(window: Window, args: ActionArgs) =
    let start = window.keyViewCommandStartView(args.sender)
    discard window.selectKeyViewFollowingView(start)

  method selectPreviousKeyView(window: Window, args: ActionArgs) =
    let start = window.keyViewCommandStartView(args.sender)
    discard window.selectKeyViewPrecedingView(start)

protocol DefaultWindowCommands of MenuCommandProtocol:
  method performClose(window: Window, args: ActionArgs) =
    if window.canClose():
      window.close()

  method performMiniaturize(window: Window, args: ActionArgs) =
    window.miniaturize()

  method performZoom(window: Window, args: ActionArgs) =
    window.zoom()

protocol DefaultWindowUndoManagerProvider of UndoManagerProvider:
  method undoManager(window: Window): Option[UndoManager] =
    some(window.undoManagerFor())

protocol DefaultWindowValidations of UserInterfaceValidations:
  method validateUserInterfaceItem(window: Window, args: ValidationArgs): bool =
    let validation = window.validateWindowCommand(args.action)
    if validation.isSome:
      return validation.get()
    args.action.name.len > 0 and window.respondsTo(args.action.name)

protocol CaretBlinkAnimationProtocol of AnimationProtocol:
  method updateCurrentTime(animation: CaretBlinkAnimation, currentTime: Duration) =
    discard currentTime
    if animation.textView.isNil:
      return
    let visible = animation.progress{} < 0.5'f32
    if animation.textView.insertionPointVisible() != visible:
      animation.textView.insertionPointVisible = visible

proc newWindow*(title = "KNutella Window", frame: Rect = defaultWindowFrame()): Window =
  let resolvedFrame = frame.resolveAutoRect(defaultWindowFrame())
  result = Window(
    xFrame: resolvedFrame,
    xTitle: title,
    xStyleMask: {wsmTitled, wsmClosable, wsmMiniaturizable, wsmResizable},
    xLevel: wlNormal,
    xMinSize: initSize(1.0'f32, 1.0'f32),
    xMaxSize: initSize(float32.high, float32.high),
    xResizeIncrements: initSize(1.0'f32, 1.0'f32),
    xAutorecalculatesKeyViewLoop: true,
    xKeyBindings: initDefaultKeyBindings(),
  )
  initResponder(result)
  discard result.withProtocol(DefaultWindowKeyViewCommands)
  discard result.withProtocol(DefaultWindowCommands)
  discard result.withProtocol(DefaultWindowUndoManagerProvider)
  discard result.withProtocol(DefaultWindowValidations)

proc newPanel*(title = "Panel", frame: Rect = defaultWindowFrame()): Panel =
  result = newWindow(title, frame)
  result.xLevel = wlFloating
  result.xStyleMask = {wsmTitled, wsmClosable, wsmUtilityWindow}

proc newAlert*(
    messageText: string,
    informativeText = "",
    style = asInformational,
    buttons: openArray[string] = ["OK"],
): Alert =
  result = Alert(
    messageText: messageText,
    informativeText: informativeText,
    style: style,
    window: newPanel(messageText, rect(100, 100, 360, 160)),
  )
  initResponder(result)
  for index, button in buttons:
    result.buttons.add button
    result.buttonResponses.add(
      if index == 0:
        1
      else:
        index + 1
    )

proc newOpenPanel*(): OpenPanel =
  result = OpenPanel(
    window: newPanel("Open", rect(100, 100, 520, 360)),
    prompt: "Open",
    canChooseFiles: true,
  )
  initResponder(result)

proc newSavePanel*(): SavePanel =
  result = SavePanel(window: newPanel("Save", rect(100, 100, 520, 280)), prompt: "Save")
  initResponder(result)

proc popupPixels(value: float32, scale: float32, minimum: int32): int32 {.inline.} =
  max((value * scale).round().int32, minimum)

proc popupPlacement(
    anchorFrame: Rect, popupSize: Size, scale: float32
): siwinshim.PopupPlacement =
  siwinshim.PopupPlacement(
    anchorRectPos: siwinshim.ivec2(
      popupPixels(anchorFrame.origin.x, scale, 0),
      popupPixels(anchorFrame.origin.y, scale, 0),
    ),
    anchorRectSize: siwinshim.ivec2(
      popupPixels(anchorFrame.size.width, scale, 1),
      popupPixels(anchorFrame.size.height, scale, 1),
    ),
    size: siwinshim.ivec2(
      popupPixels(popupSize.width, scale, 1), popupPixels(popupSize.height, scale, 1)
    ),
    anchor: siwinshim.Edge.bottomLeft,
    gravity: siwinshim.Edge.topLeft,
    offset: siwinshim.ivec2(0, 0),
    constraintAdjustment: {
      siwinshim.PopupConstraintAdjustment.pcaFlipY,
      siwinshim.PopupConstraintAdjustment.pcaSlideX,
      siwinshim.PopupConstraintAdjustment.pcaResizeY,
    },
    reactive: true,
  )

proc frame*(window: Window): Rect =
  window.xFrame

func componentMaximum(a, b: Size): Size =
  initSize(max(a.width, b.width), max(a.height, b.height))

func normalizedMinimumSize(size: Size): Size =
  initSize(max(size.width, 0.0'f32), max(size.height, 0.0'f32))

proc contentMinSize*(window: Window): Size =
  window.refreshAutomaticContentMinSize()
  window.xContentMinSize.componentMaximum(window.xAutomaticContentMinSize)

proc effectiveMinimumSize(window: Window): Size =
  window.xMinSize.componentMaximum(window.contentMinSize())

proc effectiveMaximumSize(window: Window): Size =
  window.xMaxSize.componentMaximum(window.effectiveMinimumSize())

proc boundedWindowSize(window: Window, size: Size): Size =
  let
    minimum = window.effectiveMinimumSize()
    maximum = window.effectiveMaximumSize()
  initSize(
    min(max(size.width, minimum.width), maximum.width),
    min(max(size.height, minimum.height), maximum.height),
  )

proc setFrame*(window: Window, frame: Rect) =
  let boundedFrame = rect(frame.origin, window.boundedWindowSize(frame.size))
  if window.xFrame == boundedFrame:
    return
  window.xFrame = boundedFrame
  if not window.xContentView.isNil:
    window.xContentView.setFrame(
      rect(0.0, 0.0, boundedFrame.size.width, boundedFrame.size.height)
    )
  if not window.xHostWindow.isNil:
    window.xHostWindow.setLogicalSize(boundedFrame.size)
    window.xHostWindow.updatePresentationTarget()
    window.requestNativeDisplayUpdate()

proc `frame=`*(window: Window, frame: Rect) =
  window.setFrame(frame)

proc title*(window: Window): string =
  window.xTitle

proc styleMask*(window: Window): set[WindowStyleMask] =
  window.xStyleMask

proc `styleMask=`*(window: Window, mask: set[WindowStyleMask]) =
  window.xStyleMask = mask

proc level*(window: Window): WindowLevel =
  window.xLevel

proc `level=`*(window: Window, level: WindowLevel) =
  window.xLevel = level

proc delegate*(window: Window): DynamicAgent =
  window.xDelegate

proc `delegate=`*(window: Window, delegate: DynamicAgent) =
  window.xDelegate = delegate

proc `delegate=`*(window: Window, delegate: Responder) =
  window.delegate = DynamicAgent(delegate)

proc undoManagerFor*(window: Window): UndoManager =
  if window.xUndoManager.isNil:
    window.xUndoManager = newUndoManager()
  window.xUndoManager

proc setUndoManager*(window: Window, undoManager: UndoManager) =
  window.xUndoManager = undoManager

proc `undoManager=`*(window: Window, undoManager: UndoManager) =
  window.setUndoManager(undoManager)

proc contentView*(window: Window): View =
  window.xContentView

proc isKeyWindow*(window: Window): bool =
  window.xIsKeyWindow

proc isMainWindow*(window: Window): bool =
  window.xIsMainWindow

proc isMiniaturized*(window: Window): bool =
  window.xMiniaturized

proc isZoomed*(window: Window): bool =
  window.xZoomed

proc minSize*(window: Window): Size =
  window.xMinSize

proc `minSize=`*(window: Window, size: Size) =
  window.xMinSize = size.normalizedMinimumSize()
  window.syncNativeSizeLimits()
  window.setFrame(window.xFrame)

proc `contentMinSize=`*(window: Window, size: Size) =
  window.xContentMinSize = size.normalizedMinimumSize()
  window.syncNativeSizeLimits()
  window.setFrame(window.xFrame)

proc automaticallyAdjustsContentMinSize*(window: Window): bool =
  window.xAutomaticallyAdjustsContentMinSize

proc `automaticallyAdjustsContentMinSize=`*(window: Window, value: bool) =
  if window.xAutomaticallyAdjustsContentMinSize == value:
    return
  window.xAutomaticallyAdjustsContentMinSize = value
  window.xAutomaticContentMinSizeNeedsUpdate = true
  window.refreshAutomaticContentMinSize()

proc maxSize*(window: Window): Size =
  window.xMaxSize

proc `maxSize=`*(window: Window, size: Size) =
  window.xMaxSize = size
  window.syncNativeSizeLimits()
  window.setFrame(window.xFrame)

proc resizeIncrements*(window: Window): Size =
  window.xResizeIncrements

proc `resizeIncrements=`*(window: Window, size: Size) =
  window.xResizeIncrements = size

proc frameAutosaveName*(window: Window): string =
  window.xFrameAutosaveName

proc savedFrameForName*(name: string): Option[Rect] =
  if name.len == 0:
    return none(Rect)
  ensureWindowFrameStore()
  if name in savedWindowFrames:
    return some(savedWindowFrames[name])
  none(Rect)

proc saveFrameUsingName*(window: Window, name: string): bool {.discardable.} =
  if name.len == 0:
    return false
  ensureWindowFrameStore()
  savedWindowFrames[name] = window.frame()
  true

proc saveFrameUsingName*(window: Window): bool {.discardable.} =
  window.saveFrameUsingName(window.xFrameAutosaveName)

proc setFrameUsingName*(window: Window, name: string): bool {.discardable.} =
  if name.len == 0:
    return false
  window.xFrameAutosaveName = name
  let saved = savedFrameForName(name)
  if saved.isSome:
    window.frame = saved.get()
    return true
  false

proc removeSavedFrameForName*(name: string): bool {.discardable.} =
  if name.len == 0:
    return false
  ensureWindowFrameStore()
  if name notin savedWindowFrames:
    return false
  savedWindowFrames.del(name)
  true

proc `frameAutosaveName=`*(window: Window, name: string) =
  discard window.setFrameUsingName(name)

proc keyBindings*(window: Window): KeyBindingTable =
  window.xKeyBindings

proc setKeyBindings*(window: Window, bindings: KeyBindingTable) =
  window.xKeyBindings = bindings

proc setKeyBindingProfile*(window: Window, profile: KeyBindingProfile) =
  window.xKeyBindings = initDefaultKeyBindings(profile)

proc addKeyBinding*(window: Window, stroke: KeyStroke, selector: CommandSelector) =
  window.xKeyBindings.add(stroke, selector)

proc removeKeyBinding*(window: Window, stroke: KeyStroke): bool {.discardable.} =
  window.xKeyBindings.remove(stroke)

proc clearKeyBindings*(window: Window) =
  window.xKeyBindings.clear()

proc bindKey*(
    window: Window, text: string, modifiers: set[KeyModifier], selector: CommandSelector
) =
  window.xKeyBindings.bindKey(text, modifiers, selector)

proc bindKey*(
    window: Window,
    key: events.Key,
    modifiers: set[KeyModifier],
    selector: CommandSelector,
) =
  window.xKeyBindings.bindKey(key, modifiers, selector)

proc bindKey*(
    window: Window, keyCode: int, modifiers: set[KeyModifier], selector: CommandSelector
) =
  window.xKeyBindings.bindKey(keyCode, modifiers, selector)

proc bindShortcut*(
    window: Window,
    text: string,
    modifiers: set[ShortcutModifier],
    selector: CommandSelector,
) =
  window.xKeyBindings.bindShortcut(text, modifiers, selector)

proc bindShortcut*(
    window: Window,
    key: events.Key,
    modifiers: set[ShortcutModifier],
    selector: CommandSelector,
) =
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
    key: events.Key,
    modifiers: set[ShortcutModifier],
    selector: CommandSelector,
) =
  window.bindShortcut(key, modifiers, selector)

proc propagateAppearance(window: Window) =
  if window.xContentView.isNil:
    return
  window.xContentView.setInheritedAppearance(window.effectiveAppearance())

proc shouldSetContentView(window: Window, view: View): bool =
  window.trySendLocal(shouldSetContentView(), view).get(true)

proc shouldMakeFirstResponder(window: Window, responder: Responder): bool =
  window.trySendLocal(shouldMakeFirstResponder(), responder).get(true)

proc shouldDismissTransientSession(window: Window, reason: DismissReason): bool =
  window.trySendLocal(shouldDismiss(), reason).get(true)

proc hasAppearance*(window: Window): bool =
  window.xHasAppearance

proc appearance*(window: Window): Appearance =
  if not window.xHasAppearance:
    return initAppearance()
  window.xAppearance

proc effectiveAppearance*(window: Window): Appearance =
  if window.xHasAppearance:
    return window.xAppearance
  if window.xHasInheritedAppearance:
    return window.xInheritedAppearance
  initAppearance()

proc popupPresentation*(window: Window): PopupPresentation =
  window.xPopupPresentation

proc effectivePopupPresentation*(window: Window): PopupPresentation =
  if window.xPopupPresentation == ppAutomatic:
    return platformDefaultPopupPresentation()
  window.xPopupPresentation

proc setPopupPresentation*(window: Window, presentation: PopupPresentation) =
  if window.xPopupPresentation == presentation:
    return
  window.xPopupPresentation = presentation
  emit window.didChangePopupPresentation(window.xPopupPresentation)
  if window.hasActiveTransientSession():
    discard window.dismissTransientSession(tdrProgrammatic)
  else:
    window.closeAuxiliaryWindows()
  if not window.xContentView.isNil:
    window.xContentView.setNeedsDisplay(true)

proc setAppearance*(window: Window, appearance: Appearance) =
  window.xAppearance = appearance
  window.xHasAppearance = true
  window.propagateAppearance()
  emit window.didChangeEffectiveAppearance(window.effectiveAppearance())
  window.postWindowAppearanceNotification()

proc clearAppearance*(window: Window) =
  if not window.xHasAppearance:
    return
  window.xAppearance = Appearance()
  window.xHasAppearance = false
  window.propagateAppearance()
  emit window.didChangeEffectiveAppearance(window.effectiveAppearance())
  window.postWindowAppearanceNotification()

proc setInheritedAppearance*(window: Window, appearance: Appearance) =
  window.xInheritedAppearance = appearance
  window.xHasInheritedAppearance = true
  if not window.xHasAppearance:
    window.propagateAppearance()
    emit window.didChangeEffectiveAppearance(window.effectiveAppearance())
    window.postWindowAppearanceNotification()

proc clearInheritedAppearance*(window: Window) =
  window.xInheritedAppearance = Appearance()
  window.xHasInheritedAppearance = false
  if not window.xHasAppearance:
    window.propagateAppearance()
    emit window.didChangeEffectiveAppearance(window.effectiveAppearance())
    window.postWindowAppearanceNotification()

proc clearMouseState(window: Window) =
  if not window.xMouseActiveView.isNil:
    window.xMouseActiveView.active = false
  if not window.xMouseHoverView.isNil:
    window.xMouseHoverView.hovered = false
  window.xMouseCaptureView = nil
  window.xMouseActiveView = nil
  window.xMouseHoverView = nil
  window.xMouseTrackingEvent = MouseEvent()
  window.xHasMouseTrackingEvent = false
  window.xMouseClickCount = 0
  window.xLastClickView = nil
  window.xHasLastClick = false
  window.xLastClickCount = 0

proc setMouseActiveView(window: Window, view: View) =
  if window.xMouseActiveView == view:
    return
  if not window.xMouseActiveView.isNil:
    window.xMouseActiveView.active = false
  window.xMouseActiveView = view
  if not view.isNil:
    view.active = true

proc syncNativeSizeLimits(window: Window) =
  if not window.xHostWindow.isNil:
    window.xHostWindow.setMinimumSize(window.effectiveMinimumSize())
    window.xHostWindow.setMaximumSize(window.effectiveMaximumSize())

proc refreshAutomaticContentMinSize(window: Window) =
  if not window.xAutomaticContentMinSizeNeedsUpdate or
      window.xUpdatingAutomaticContentMinSize:
    return
  window.xAutomaticContentMinSizeNeedsUpdate = false
  window.xUpdatingAutomaticContentMinSize = true
  defer:
    window.xUpdatingAutomaticContentMinSize = false
  let nextSize =
    if window.xAutomaticallyAdjustsContentMinSize and not window.xContentView.isNil:
      window.xContentView.fittingSize()
    else:
      initSize()
  if window.xAutomaticContentMinSize == nextSize:
    return
  window.xAutomaticContentMinSize = nextSize
  window.syncNativeSizeLimits()
  window.setFrame(window.xFrame)

protocol WindowContentLayoutSlots of ViewLayoutInputEvents:
  proc handleWindowContentLayoutChange(
      window: Window, reason: LayoutInvalidationReason
  ) {.slotFor: layoutInputChanged.} =
    if window.xAutomaticallyAdjustsContentMinSize and
        reason in {
          lirSubviews, lirHierarchy, lirDescendantIntrinsic, lirHidden, lirConstraints,
          lirIntrinsic, lirAppearanceMetrics, lirContainerMetrics,
        }:
      window.xAutomaticContentMinSizeNeedsUpdate = true

proc setContentView*(window: Window, view: View) =
  if not window.shouldSetContentView(view):
    return
  if window.xContentView == view:
    window.clearMouseState()
    window.xAutomaticContentMinSizeNeedsUpdate = true
    window.refreshAutomaticContentMinSize()
    return

  let oldContent = window.xContentView
  emit window.willSetContentView(view)
  if not oldContent.isNil:
    window.unobserveProtocol(oldContent, WindowContentLayoutSlots)
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
  if not view.isNil:
    view.setFrame(rect(0.0, 0.0, window.xFrame.size.width, window.xFrame.size.height))
    window.observeProtocol(view, WindowContentLayoutSlots)
    view.setNeedsLayout()
    view.setNeedsDisplaySubtree()
  if window.xAutorecalculatesKeyViewLoop:
    window.recalculateKeyViewLoop()
  emit window.didSetContentView(oldContent)
  window.xAutomaticContentMinSizeNeedsUpdate = true
  window.refreshAutomaticContentMinSize()
  if not window.xThreadHost.isNil or not window.xHostWindow.isNil:
    window.requestNativeDisplayUpdate()

proc setTitle*(window: Window, title: string) =
  window.xTitle = title
  if not window.xHostWindow.isNil:
    window.xHostWindow.setTitle(title)

proc `title=`*(window: Window, title: string) =
  window.setTitle(title)

proc convertPointToScreen*(window: Window, point: Point): Point =
  point.offset(window.xFrame.origin.x, window.xFrame.origin.y)

proc convertPointFromScreen*(window: Window, point: Point): Point =
  point.offset(-window.xFrame.origin.x, -window.xFrame.origin.y)

proc convertRectToScreen*(window: Window, rect: Rect): Rect =
  rect(window.convertPointToScreen(rect.origin), rect.size)

proc convertRectFromScreen*(window: Window, rect: Rect): Rect =
  rect(window.convertPointFromScreen(rect.origin), rect.size)

proc convertPointToContent*(window: Window, point: Point): Point =
  if window.xContentView.isNil:
    return point
  window.xContentView.pointFromWindow(point)

proc convertPointFromContent*(window: Window, point: Point): Point =
  if window.xContentView.isNil:
    return point
  window.xContentView.pointToWindow(point)

proc convertRectToContent*(window: Window, rect: Rect): Rect =
  if window.xContentView.isNil:
    return rect
  window.xContentView.rectFromWindow(rect)

proc convertRectFromContent*(window: Window, rect: Rect): Rect =
  if window.xContentView.isNil:
    return rect
  window.xContentView.rectToWindow(rect)

proc firstResponder*(window: Window): Responder =
  window.xFirstResponder

proc fieldEditor*(window: Window): FieldEditor =
  if window.xFieldEditor.isNil:
    window.xFieldEditor = newFieldEditor()
    window.xFieldEditor.setNextResponder(window)
  window.xFieldEditor

proc fieldEditorClient*(window: Window): Responder =
  if window.xFirstResponder of FieldEditor:
    return FieldEditor(window.xFirstResponder).client()
  if not window.xFieldEditor.isNil:
    return window.xFieldEditor.client()

proc insertionPointBlinkTarget(window: Window): TextView =
  if window.xFirstResponder of TextView:
    result = TextView(window.xFirstResponder)

proc shouldBlinkInsertionPoint(textView: TextView): bool =
  textView.editable() and textView.isFocused() and
    textView.insertionPointBlinkPeriod() > 0.0'f32

proc insertionPointBlinkDuration(textView: TextView): Duration =
  let milliseconds =
    int64(max(1.0'f32, textView.insertionPointBlinkPeriod() * 2000.0'f32))
  initDuration(milliseconds = milliseconds)

proc newCaretBlinkAnimation(textView: TextView): CaretBlinkAnimation =
  result = CaretBlinkAnimation(textView: textView)
  initAnimationFields(result, textView.insertionPointBlinkDuration(), loopCount = -1)
  discard result.withProtocol(CaretBlinkAnimationProtocol)

proc stopInsertionPointBlink(window: Window) =
  let
    animation = window.xInsertionPointBlinkAnimation
    target = window.xInsertionPointBlinkTarget
  window.xInsertionPointBlinkAnimation = nil
  window.xInsertionPointBlinkTarget = nil
  if not animation.isNil:
    discard window.stopAnimation(animation)
  if not target.isNil and not target.insertionPointVisible():
    target.insertionPointVisible = true

proc updateInsertionPointBlink(window: Window) =
  let target = window.insertionPointBlinkTarget()
  if target.isNil or not target.shouldBlinkInsertionPoint():
    window.stopInsertionPointBlink()
    return

  window.stopInsertionPointBlink()
  target.insertionPointVisible = true
  let animation = newCaretBlinkAnimation(target)
  window.xInsertionPointBlinkTarget = target
  window.xInsertionPointBlinkAnimation = animation
  discard window.startAnimation(animation)

proc resolvedFirstResponder(window: Window, responder: Responder): Responder =
  if responder.isNil:
    return responder
  let defaultEditor = window.fieldEditor()
  if responder.wantsFieldEditor(defaultEditor):
    let editor = responder.fieldEditorForResponder(defaultEditor)
    if not editor.isNil:
      if editor.superview().isNil:
        editor.setNextResponder(window)
      return editor
  responder

proc setFirstResponder(window: Window, responder: Responder, focusVisible: bool): bool =
  let nextResponder = window.resolvedFirstResponder(responder)
  if window.xFirstResponder == nextResponder:
    let changingFieldEditorClient =
      nextResponder of FieldEditor and responder != nextResponder and
      FieldEditor(nextResponder).client() != responder
    if not changingFieldEditorClient:
      if not nextResponder.isNil:
        nextResponder.setFirstResponderFocusState(true, focusVisible)
      window.updateInsertionPointBlink()
      return true

  if not responder.isNil:
    if not responder.acceptsFirstResponder():
      return false
    if not responder.shouldBecomeFirstResponder():
      return false
  if not window.shouldMakeFirstResponder(responder):
    return false
  let previousResponder = window.xFirstResponder
  if not window.xFirstResponder.isNil:
    if not window.xFirstResponder.shouldResignFirstResponder():
      return false
    if not window.xFirstResponder.resignFirstResponder():
      return false
  if not responder.isNil and nextResponder of FieldEditor:
    if not FieldEditor(nextResponder).beginEditing(responder, focusVisible):
      return false
  if not nextResponder.isNil and not nextResponder.becomeFirstResponder():
    return false

  if not previousResponder.isNil:
    previousResponder.setFirstResponderFocusState(false, false)
  if not nextResponder.isNil:
    nextResponder.setFirstResponderFocusState(true, focusVisible)
  window.xFirstResponder = nextResponder
  if not previousResponder.isNil:
    previousResponder.didResignFirstResponder()
  if not nextResponder.isNil:
    nextResponder.didBecomeFirstResponder()
  if responder of View:
    View(responder).postAccessibilityNotification(anFocusedUIElementChanged)
  emit window.didChangeFirstResponder(previousResponder)
  window.updateInsertionPointBlink()
  true

proc makeFirstResponder*(window: Window, responder: Responder): bool =
  window.setFirstResponder(responder, focusVisible = true)

proc makeFirstResponder*(
    window: Window, responder: Responder, focusVisible: bool
): bool =
  window.setFirstResponder(responder, focusVisible)

proc initialFirstResponder*(window: Window): View =
  window.xInitialFirstResponder

proc setInitialFirstResponder*(window: Window, view: View) =
  window.xInitialFirstResponder = view

proc futureFirstResponder*(window: Window): Responder =
  window.xFutureFirstResponder

proc setFutureFirstResponder*(window: Window, responder: Responder) =
  window.xFutureFirstResponder = responder

proc autorecalculatesKeyViewLoop*(window: Window): bool =
  window.xAutorecalculatesKeyViewLoop

proc setAutorecalculatesKeyViewLoop*(window: Window, value: bool) =
  window.xAutorecalculatesKeyViewLoop = value

proc collectKeyViews(view: View, views: var seq[View]) =
  views.add view
  for child in view.subviews:
    child.collectKeyViews(views)

proc recalculateKeyViewLoop*(window: Window) =
  if window.xContentView.isNil:
    window.xInitialFirstResponder = nil
    return

  var views: seq[View]
  window.xContentView.collectKeyViews(views)
  for view in views:
    view.setNextKeyView(nil)
    view.setPreviousKeyView(nil)

  if views.len == 0:
    window.xInitialFirstResponder = nil
    return

  for idx, view in views:
    view.setNextKeyView(views[(idx + 1) mod views.len])

  window.xInitialFirstResponder = window.xContentView.nextValidKeyView()

proc firstKeyViewCandidate(window: Window, forward: bool): View =
  let initial = window.xInitialFirstResponder
  if not initial.isNil:
    if initial.canBecomeKeyView():
      return initial
    if forward:
      return initial.nextValidKeyView()
    return initial.previousValidKeyView()
  if window.xContentView.isNil:
    return nil
  if forward:
    window.xContentView.nextValidKeyView()
  else:
    window.xContentView.previousValidKeyView()

proc selectKeyView(window: Window, view: View): bool =
  if view.isNil:
    return false
  if not window.makeFirstResponder(view):
    return false
  discard
    view.sendLocalIfHandled(selectText(), ActionArgs(sender: DynamicAgent(window)))
  true

proc keyViewCommandStartView(window: Window, sender: DynamicAgent): View =
  if not sender.isNil and sender of View:
    return View(sender)
  if not window.xFirstResponder.isNil and window.xFirstResponder of View:
    return View(window.xFirstResponder)

proc prepareKeyViewLoop(window: Window) =
  if window.xAutorecalculatesKeyViewLoop:
    window.recalculateKeyViewLoop()

proc selectKeyViewFollowingView*(window: Window, view: View): bool {.discardable.} =
  window.prepareKeyViewLoop()
  var candidate: View
  if not view.isNil:
    candidate = view.nextValidKeyView()
  if candidate.isNil:
    candidate = window.firstKeyViewCandidate(forward = true)
  window.selectKeyView(candidate)

proc selectKeyViewPrecedingView*(window: Window, view: View): bool {.discardable.} =
  window.prepareKeyViewLoop()
  var candidate: View
  if not view.isNil:
    candidate = view.previousValidKeyView()
  if candidate.isNil:
    candidate = window.firstKeyViewCandidate(forward = false)
  window.selectKeyView(candidate)

proc selectNextKeyView*(window: Window): bool {.discardable.} =
  window.selectKeyViewFollowingView(window.keyViewCommandStartView(nil))

proc selectPreviousKeyView*(window: Window): bool {.discardable.} =
  window.selectKeyViewPrecedingView(window.keyViewCommandStartView(nil))

proc buildRenders*(window: Window): Renders =
  window.refreshAutomaticContentMinSize()
  nimkitRendering.buildRenders(window.xContentView, window.effectiveAppearance())

proc buildRenders*(window: Window, appearance: Appearance): Renders =
  window.refreshAutomaticContentMinSize()
  nimkitRendering.buildRenders(window.xContentView, appearance)

proc buildRenders*(window: Window, theme: Theme): Renders =
  window.refreshAutomaticContentMinSize()
  nimkitRendering.buildRenders(window.xContentView, theme)

proc nativeWindowOrNil*(window: Window): siwinshim.Window =
  if window.xHostWindow.isNil:
    return nil
  window.xHostWindow.nativeWindowOrNil()

proc rendererOrNil*(
    window: Window
): figrender.FigRenderer[siwinshim.SiwinRenderBackend] =
  if not window.xThreadHost.isNil:
    return nil
  if window.xHostWindow.isNil:
    return nil
  window.xHostWindow.rendererOrNil()

proc nativeReady*(window: Window): bool =
  not window.xHostWindow.isNil and window.xHostWindow.isReady

proc nativeContentScale*(window: Window): float32 =
  if window.xHostWindow.isNil:
    return 1.0'f32
  window.xHostWindow.contentScale()

proc nativeRenderCount*(window: Window): Natural =
  if not window.xThreadHost.isNil:
    return window.xThreadHost.renderCount
  if window.xHostWindow.isNil:
    return 0
  window.xHostWindow.renderCount()

proc nativeRenderRequested*(window: Window): bool =
  if not window.xThreadHost.isNil:
    return window.xThreadHost.renderRequested
  (not window.xHostWindow.isNil) and window.xHostWindow.renderRequested()

proc needsDisplayUpdate*(window: Window): bool =
  (not window.xContentView.isNil) and window.xContentView.needsDisplayUpdateInSubtree()

proc requestNativeDisplayUpdate*(window: Window) =
  if not window.xHostWindow.isNil:
    window.xHostWindow.requestRender()

proc requestNativeDisplayUpdateIfNeeded*(window: Window): bool {.discardable.} =
  if window.needsDisplayUpdate():
    window.requestNativeDisplayUpdate()
    return true
  false

proc animationScheduler*(window: Window): AnimationScheduler =
  if window.xAnimationScheduler.isNil:
    window.xAnimationScheduler = newAnimationScheduler()
  window.xAnimationScheduler

proc animationClock*(window: Window): AnimationSchedulerClock =
  if window.xAnimationClock.isNil:
    window.xAnimationClock = newAnimationSchedulerClock()
  window.xAnimationClock

proc startAnimationClock*(window: Window) =
  let clock = window.animationClock()
  if not clock.isNil and not clock.isRunning:
    clock.start()

proc stopAnimationClock*(window: Window) =
  if window.xAnimationClock.isNil:
    return
  window.xAnimationClock.stop()

proc startAnimation*(window: Window, animation: Animation): bool {.discardable.} =
  let scheduler = window.animationScheduler()
  if scheduler.isNil:
    return false
  result = scheduler.startAnimation(animation)
  if result and scheduler.animationCount > 0:
    window.startAnimationClock()

proc stopAnimation*(
    window: Window, animation: Animation, finished = false
): bool {.discardable.} =
  if window.xAnimationScheduler.isNil:
    return false
  result = window.xAnimationScheduler.stopAnimation(animation, finished)
  if window.xAnimationScheduler.animationCount == 0:
    window.stopAnimationClock()

proc drainAnimations*(window: Window): int {.discardable.} =
  if window.xAnimationScheduler.isNil or window.xAnimationClock.isNil:
    return 0
  result = window.xAnimationScheduler.drain(window.xAnimationClock)
  if window.xAnimationScheduler.animationCount == 0:
    window.stopAnimationClock()

proc isClosed*(window: Window): bool =
  window.xClosed

proc isVisible*(window: Window): bool =
  window.xVisibleRequested and not window.xClosed and not window.xMiniaturized

proc sendWindowDelegate[A](
    window: Window, selector: Selector[A, EmptyArgs], args: sink A
) =
  if not window.xDelegate.isNil:
    discard window.xDelegate.sendLocalIfHandled(selector, ensureMove args)

proc windowNotificationPayload(window: Window): NotificationPayload =
  initWindowNotificationPayload(
    keyWindow = window.xIsKeyWindow,
    mainWindow = window.xIsMainWindow,
    visible = window.xVisibleRequested,
    closed = window.xClosed,
  )

proc postWindowNotification(window: Window, kind: NotificationKind) =
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      kind, sender = DynamicAgent(window), payload = window.windowNotificationPayload()
    )
  )

proc postWindowAppearanceNotification(window: Window) =
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      nkWindowAppearanceDidChange,
      sender = DynamicAgent(window),
      payload = initAppearanceNotificationPayload(
        atkWindow, window.effectiveAppearance(), window.xHasAppearance
      ),
    )
  )

proc notifyApplication(window: Window, selectorName: string) =
  let owner = window.nextResponder()
  if owner.isNil:
    return
  discard owner.sendLocalIfHandled(
    actionSelector(selectorName), ActionArgs(sender: DynamicAgent(window))
  )

proc setKeyWindow*(window: Window, value: bool) =
  if window.xIsKeyWindow == value:
    return
  window.xIsKeyWindow = value
  if value:
    window.sendWindowDelegate(windowDidBecomeKey(), window)
    emit window.didBecomeKeyWindow()
    window.postWindowNotification(nkWindowDidBecomeKey)
  else:
    window.sendWindowDelegate(windowDidResignKey(), window)
    emit window.didResignKeyWindow()
    window.postWindowNotification(nkWindowDidResignKey)

proc setMainWindow*(window: Window, value: bool) =
  if window.xIsMainWindow == value:
    return
  window.xIsMainWindow = value
  if value:
    window.sendWindowDelegate(windowDidBecomeMain(), window)
    emit window.didBecomeMainWindow()
    window.postWindowNotification(nkWindowDidBecomeMain)
  else:
    window.sendWindowDelegate(windowDidResignMain(), window)
    emit window.didResignMainWindow()
    window.postWindowNotification(nkWindowDidResignMain)

proc canClose*(window: Window): bool =
  not window.xClosed and wsmClosable in window.xStyleMask

proc canMiniaturize*(window: Window): bool =
  not window.xClosed and wsmMiniaturizable in window.xStyleMask and
    not window.xMiniaturized

proc canZoom*(window: Window): bool =
  not window.xClosed and wsmResizable in window.xStyleMask

proc validateWindowCommand*(window: Window, selector: ActionSelector): Option[bool] =
  if selector.name == "performClose":
    some(window.canClose())
  elif selector.name == "performMiniaturize":
    some(window.canMiniaturize())
  elif selector.name == "performZoom":
    some(window.canZoom())
  else:
    none(bool)

proc orderFrontImpl(window: Window, makeKeyMain: bool) =
  window.xClosed = false
  window.xMiniaturized = false
  window.xVisibleRequested = true
  if makeKeyMain:
    window.setKeyWindow(true)
    window.setMainWindow(true)
  if not window.xHostWindow.isNil:
    window.xHostWindow.setVisible(true)
  window.notifyApplication(WindowDidOrderFrontSelector)

proc makeKeyAndOrderFront*(window: Window) =
  window.orderFrontImpl(makeKeyMain = true)

proc orderFront*(window: Window) =
  window.orderFrontImpl(makeKeyMain = false)

proc orderBack*(window: Window) =
  if window.xClosed:
    return
  window.xMiniaturized = false
  window.xVisibleRequested = true
  if not window.xHostWindow.isNil:
    window.xHostWindow.setVisible(true)
  window.notifyApplication(WindowDidOrderBackSelector)

proc orderOut*(window: Window) =
  window.xVisibleRequested = false
  if not window.xHostWindow.isNil:
    window.xHostWindow.setVisible(false)
  window.notifyApplication(WindowDidOrderOutSelector)

proc miniaturize*(window: Window) =
  if not window.canMiniaturize():
    return
  window.xMiniaturized = true
  window.xVisibleRequested = false
  if not window.xHostWindow.isNil:
    window.xHostWindow.setVisible(false)
  window.notifyApplication(WindowDidOrderOutSelector)

proc deminiaturize*(window: Window) =
  if window.xClosed or not window.xMiniaturized:
    return
  window.orderFront()

proc zoom*(window: Window) =
  if not window.canZoom():
    return
  window.xZoomed = not window.xZoomed
  if not window.xContentView.isNil:
    window.xContentView.setNeedsDisplay(true)

proc detachAuxiliaryWindow(owner, auxiliary: Window) =
  if owner.isNil:
    return
  let idx = owner.xAuxiliaryWindows.find(auxiliary)
  if idx >= 0:
    owner.xAuxiliaryWindows.delete(idx)

proc attachAuxiliaryWindow(owner, auxiliary: Window) =
  if owner.isNil:
    return
  auxiliary.xOwnerWindow = owner
  if auxiliary notin owner.xAuxiliaryWindows:
    owner.xAuxiliaryWindows.add auxiliary

proc beginSheet*(window: Window, sheet: Window) =
  if sheet.isNil:
    return
  if not window.xSheet.isNil and window.xSheet != sheet:
    window.endSheet(window.xSheet)
  window.xSheet = sheet
  sheet.xSheetParent = window
  window.attachAuxiliaryWindow(sheet)
  window.sendWindowDelegate(windowWillBeginSheet(), sheet)
  sheet.makeKeyAndOrderFront()

proc endSheet*(window: Window, sheet: Window = nil) =
  let activeSheet = if sheet.isNil: window.xSheet else: sheet
  if activeSheet.isNil:
    return
  if window.xSheet == activeSheet:
    window.xSheet = nil
  activeSheet.xSheetParent = nil
  window.detachAuxiliaryWindow(activeSheet)
  activeSheet.orderOut()
  window.sendWindowDelegate(windowDidEndSheet(), activeSheet)

proc attachedSheet*(window: Window): Window =
  window.xSheet

proc sheetParent*(window: Window): Window =
  window.xSheetParent

proc closeAuxiliaryWindows(window: Window, notifyDone = true) =
  let auxiliaries = window.xAuxiliaryWindows
  window.xAuxiliaryWindows.setLen(0)
  for auxiliary in auxiliaries:
    if not auxiliary.isNil:
      if not notifyDone:
        auxiliary.xOnPopupDone = nil
      auxiliary.xOwnerWindow = nil
      auxiliary.close()

proc hasActiveTransientSession*(window: Window): bool =
  window.xTransientSession.active

proc transientDismissReason*(window: Window): DismissReason =
  window.xLastTransientDismissReason

proc transientWindow*(window: Window): Window =
  if window.xTransientSession.active:
    result = window.xTransientSession.transientWindow

proc restoreTransientFocus(window: Window, session: TransientSession) =
  let restoreWindow = if session.restoreWindow.isNil: window else: session.restoreWindow
  if restoreWindow.isNil or restoreWindow.isClosed:
    return
  if restoreWindow.isVisible:
    restoreWindow.makeKeyAndOrderFront()
  discard restoreWindow.makeFirstResponder(session.restoreResponder)

proc finishTransientSession(
    window: Window, reason: DismissReason, notifyDismiss: bool
): bool =
  if not window.xTransientSession.active:
    return false
  if reason != tdrOwnerClosed and not window.shouldDismissTransientSession(reason):
    return false

  let session = window.xTransientSession
  window.xTransientSession = TransientSession()
  window.xLastTransientDismissReason = reason
  window.closeAuxiliaryWindows(notifyDone = false)

  if notifyDismiss and not session.onDismiss.isNil:
    session.onDismiss(reason)
  emit window.didDismissTransientSession(reason)
  if reason != tdrOwnerClosed:
    window.restoreTransientFocus(session)
  if not window.xContentView.isNil:
    window.xContentView.setNeedsDisplay(true)
  true

proc beginTransientSession*(
    window: Window,
    owner: Responder,
    transientWindow: Window = nil,
    restoreResponder: Responder = nil,
    onDismiss: TransientDismissHandler = nil,
    restoreCurrentResponderIfNil = true,
) =
  if window.xTransientSession.active:
    let session = window.xTransientSession
    if session.ownerResponder != owner or session.transientWindow != transientWindow:
      discard window.dismissTransientSession(tdrProgrammatic)

  let resolvedRestore =
    if restoreCurrentResponderIfNil and restoreResponder.isNil:
      window.xFirstResponder
    else:
      restoreResponder
  if not transientWindow.isNil:
    window.attachAuxiliaryWindow(transientWindow)
  window.xTransientSession = TransientSession(
    active: true,
    ownerResponder: owner,
    transientWindow: transientWindow,
    restoreWindow: window,
    restoreResponder: resolvedRestore,
    onDismiss: onDismiss,
  )

proc dismissTransientSession*(
    window: Window, reason: DismissReason
): bool {.discardable.} =
  window.finishTransientSession(reason, notifyDismiss = true)

proc endTransientSession*(
    window: Window, reason = tdrProgrammatic
): bool {.discardable.} =
  window.finishTransientSession(reason, notifyDismiss = false)

proc close*(window: Window) =
  let shouldClose =
    if window.xDelegate.isNil:
      true
    else:
      window.xDelegate.trySendLocal(windowShouldClose(), window).get(true)
  if not shouldClose:
    return
  window.sendWindowDelegate(windowWillClose(), window)
  emit window.willClose()
  window.postWindowNotification(nkWindowWillClose)
  let notifyPopupDone =
    window.xIsPopup and not window.xClosed and not window.xOnPopupDone.isNil
  window.stopInsertionPointBlink()
  discard window.saveFrameUsingName()
  window.xClosed = true
  window.xVisibleRequested = false
  window.xMiniaturized = false
  window.xIsKeyWindow = false
  window.xIsMainWindow = false
  if window.xTransientSession.active:
    discard window.dismissTransientSession(tdrOwnerClosed)
  else:
    window.closeAuxiliaryWindows(notifyDone = false)
  if not window.xOwnerWindow.isNil:
    if window.xOwnerWindow.xSheet == window:
      window.xOwnerWindow.xSheet = nil
    window.xOwnerWindow.detachAuxiliaryWindow(window)
    window.xOwnerWindow = nil
  if not window.xSheetParent.isNil and window.xSheetParent.xSheet == window:
    window.xSheetParent.xSheet = nil
    window.xSheetParent = nil
  window.releaseThreadRenderer(waitForRelease = true)
  if not window.xHostWindow.isNil:
    window.xHostWindow.close()
    window.xHostWindow = nil
  if notifyPopupDone:
    window.xOnPopupDone()
  emit window.didClose()
  window.postWindowNotification(nkWindowDidClose)
  window.sendWindowDelegate(windowDidClose(), window)
  window.notifyApplication(WindowDidCloseSelector)

proc setPopupDoneHandler*(window: Window, handler: proc() {.closure.}) =
  window.xOnPopupDone = handler

proc newPopupWindow*(
    owner: Window, anchorFrame: Rect, popupSize: Size, title = "Popup"
): Window =
  let frame = rect(
    anchorFrame.origin.x,
    anchorFrame.origin.y + anchorFrame.size.height,
    max(popupSize.width, 1.0'f32),
    max(popupSize.height, 1.0'f32),
  )
  result = newWindow(title, frame)
  result.xIsPopup = true
  result.xPopupPlacement =
    popupPlacement(anchorFrame, popupSize, owner.nativeContentScale())
  owner.attachAuxiliaryWindow(result)
  result.xPopupPresentation = owner.popupPresentation()
  result.setInheritedAppearance(owner.effectiveAppearance())
  if not owner.xThreadRenderer.isNil:
    result.useThreadRenderer(owner.xThreadRenderer)

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
    target: Responder, selector: CommandSelector, sender: DynamicAgent
): EventDispatchResult =
  let args = TryToPerformArgs(selector: selector, sender: sender)
  var responder = target
  while not responder.isNil:
    if responder.tryToPerform(args):
      result.handled = true
      result.responder = responder
      return
    responder = responder.nextResponder()

proc dispatchActionInChain*(
    window: Window, selector: ActionSelector, sender: DynamicAgent
): EventDispatchResult =
  var target = window.keyDispatchTarget()
  if target.isNil:
    target = Responder(window)
  dispatchCommandInChain(target, selector, sender)

proc sendAction*(
    window: Window,
    selector: ActionSelector,
    sender: DynamicAgent = nil,
    target: DynamicAgent = nil,
): bool =
  if not target.isNil:
    return target.sendLocalIfHandled(selector, ActionArgs(sender: sender))
  window.dispatchActionInChain(selector, sender).handled

proc dispatchKeyCommand(
    window: Window, target: Responder, event: events.KeyEvent
): EventDispatchResult =
  let command = window.xKeyBindings.commandFor(event)
  if command.isNone:
    return
  dispatchCommandInChain(target, command.get(), DynamicAgent(target))

func shouldDispatchTextKeyDownFirst(event: events.KeyEvent): bool =
  event.modifiers - {kmShift} == {} and event.text.isInsertableText()

proc performKeyEquivalent*(window: Window, event: events.KeyEvent): bool =
  let target = window.keyDispatchTarget()
  if target.isNil:
    return false
  if target.performKeyEquivalentInChain(event):
    return true
  window.dispatchKeyCommand(target, event).handled

proc dispatchKeyDown*(window: Window, event: events.KeyEvent): bool =
  let target = window.keyDispatchTarget()
  let dispatchTextFirst = event.shouldDispatchTextKeyDownFirst()
  if not target.isNil and dispatchTextFirst:
    if window.dispatchKeyEventInChain(target, event, keyDown()).handled:
      return true
  if not target.isNil and window.performKeyEquivalent(event):
    return true
  if event.key == keyEscape:
    if not window.xOwnerWindow.isNil:
      return window.xOwnerWindow.dismissTransientSession(tdrEscape)
    if window.hasActiveTransientSession():
      return window.dismissTransientSession(tdrEscape)
  if target.isNil:
    return false
  if dispatchTextFirst:
    return false
  window.dispatchKeyEventInChain(target, event, keyDown()).handled

proc dispatchKeyUp*(window: Window, event: events.KeyEvent): bool =
  let target = window.keyDispatchTarget()
  if target.isNil:
    return false
  window.dispatchKeyEventInChain(target, event, keyUp()).handled

proc dispatchFlagsChanged*(window: Window, event: events.KeyEvent): bool =
  let target = window.keyDispatchTarget()
  if target.isNil:
    return false
  window.dispatchKeyEventInChain(target, event, flagsChanged()).handled

proc syncNativeGeometry(window: Window): Size =
  let nativeSize = window.xHostWindow.logicalSize(window.xFrame.size)
  result = window.boundedWindowSize(nativeSize)
  if nativeSize != result:
    window.xHostWindow.setLogicalSize(result)
    window.xHostWindow.updatePresentationTarget()
  if window.xFrame.size != result:
    window.xFrame.size = result
    if not window.xContentView.isNil:
      window.xContentView.setFrame(rect(0.0, 0.0, result.width, result.height))
    discard window.saveFrameUsingName()

proc renderNativeWindow*(window: Window) =
  if not window.nativeReady:
    return

  window.xHostWindow.refreshContentScale()
  let logicalSize = window.syncNativeGeometry()
  var renders = window.buildRenders()
  if not window.xThreadHost.isNil:
    var resources = nimkitRendering.renderResources(window.xContentView)
    window.xContentView.invalidateRenderCache()
    discard window.xThreadHost.submitRenders(
      ensureMove renders, logicalSize, ensureMove resources
    )
    window.xHostWindow.renderSubmitted()
  else:
    window.xHostWindow.render(renders, logicalSize)

proc contentPoint(window: Window, windowPoint: Point): Point =
  window.xContentView.pointFromWindow(windowPoint)

proc contentHitTest(window: Window, contentPoint: Point): View =
  if window.xContentView.isNil or not window.xContentView.pointInside(contentPoint):
    return nil
  window.xContentView.hitTest(contentPoint)

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
    target, contentView: View, contentPoint: Point, event: events.ScrollEvent
): events.ScrollEvent =
  result = events.ScrollEvent(
    location: target.pointFromView(contentPoint, contentView),
    deltaX: event.deltaX,
    deltaY: event.deltaY,
    phase: event.phase,
    momentumPhase: event.momentumPhase,
    modifiers: event.modifiers,
    timestamp: event.timestamp,
  )

proc localKeyEvent(
    target, contentView: View, contentPoint: Point, event: events.KeyEvent
): events.KeyEvent =
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

proc dispatchEventInChain[A](
    window: Window,
    target: Responder,
    contentPoint: Point,
    event: A,
    selector: Selector[A, bool],
    localize: proc(target, contentView: View, contentPoint: Point, event: A): A,
): EventDispatchResult =
  var responder = target
  while not responder.isNil:
    var localEvent = event
    if responder of View:
      localEvent = localize(View(responder), window.xContentView, contentPoint, event)
    var handled = false
    if responder.performLocal(selector, localEvent, handled) and handled:
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
    stopBefore: Responder = nil,
): EventDispatchResult =
  ## Walks the responder chain from ``target`` outward.
  ## The first responder method returning ``true`` ends dispatch.
  ## ``false`` means "not handled", so we continue to ``nextResponder``.
  var responder = Responder(target)
  while not responder.isNil and responder != stopBefore:
    var localEvent = event
    if responder of View:
      localEvent =
        localMouseEvent(View(responder), window.xContentView, contentPoint, event)
    var handled = false
    if responder.performLocal(selector, localEvent, handled) and handled:
      result.handled = true
      result.responder = responder
      return
    responder = responder.nextResponder()

proc mouseHitPolicyInChain(
    window: Window, target: View, contentPoint: Point, event: MouseEvent
): tuple[policy: CellHitPolicy, responder: Responder] =
  result.policy = chpDefault
  var responder = Responder(target)
  while not responder.isNil:
    var localEvent = event
    if responder of View:
      localEvent =
        localMouseEvent(View(responder), window.xContentView, contentPoint, event)
    let policy = responder.trySendLocal(
      mouseHitPolicy(),
      MouseHitPolicyArgs(target: DynamicAgent(target), event: localEvent),
    )
    if policy.isSome and policy.get() != chpDefault:
      result.policy = policy.get()
      result.responder = responder
      return
    responder = responder.nextResponder()

proc applyMouseHitPolicy(
    window: Window,
    responder: Responder,
    target: View,
    contentPoint: Point,
    event: MouseEvent,
): bool =
  if responder.isNil:
    return false
  var localEvent = event
  if responder of View:
    localEvent =
      localMouseEvent(View(responder), window.xContentView, contentPoint, event)
  responder.sendLocalIfHandled(
    applyMouseHitPolicy(),
    MouseHitPolicyArgs(target: DynamicAgent(target), event: localEvent),
  )

proc dispatchScrollEventInChain(
    window: Window, target: View, contentPoint: Point, event: events.ScrollEvent
): EventDispatchResult =
  var responder = Responder(target)
  while not responder.isNil:
    var localEvent = event
    if responder of View:
      localEvent =
        localScrollEvent(View(responder), window.xContentView, contentPoint, event)

    let wantsForwarded =
      responder.trySendLocal(wantsForwardedScrollEvents(), localEvent)
    if (wantsForwarded.isNone or not wantsForwarded.get()) and
        responder.sendLocalIfHandled(scrollWheel(), localEvent):
      result.handled = true
      result.responder = responder
      return
    responder = responder.nextResponder()

proc dispatchKeyEventInChain(
    window: Window,
    target: Responder,
    event: events.KeyEvent,
    selector: KeyEventSelector,
): EventDispatchResult =
  window.dispatchEventInChain(
    target, initPoint(0.0, 0.0), event, selector, localKeyEvent
  )

proc dispatchTextInputInChain(target: Responder, text: string): EventDispatchResult =
  var responder = target
  while not responder.isNil:
    if responder.sendLocalIfHandled(insertText(), text):
      result.handled = true
      result.responder = responder
      return
    responder = responder.nextResponder()

proc dispatchTextInput*(window: Window, text: string): bool =
  if text.len == 0:
    return false
  let target = window.keyDispatchTarget()
  if target.isNil:
    return false
  dispatchTextInputInChain(target, text).handled

proc updateHoverView(
    window: Window, target: View, contentPoint: Point, event: MouseEvent
): bool =
  if window.xMouseHoverView == target:
    return false

  let previous = window.xMouseHoverView
  if not previous.isNil:
    previous.hovered = false
    let localEvent = previous.localMouseEvent(window.xContentView, contentPoint, event)
    result = previous.handleMouse(mouseExited(), localEvent)

  window.xMouseHoverView = target
  if not target.isNil:
    target.hovered = true
    let localEvent = target.localMouseEvent(window.xContentView, contentPoint, event)
    result = target.handleMouse(mouseEntered(), localEvent) or result

proc responderChainContains(responder, owner: Responder): bool =
  if responder.isNil:
    return false
  var current = responder
  while not current.isNil:
    if current == owner:
      return true
    current = current.nextResponder()
  false

proc shouldDismissTransientForMouse(window: Window, target: View): bool =
  if not window.xTransientSession.active:
    return false
  let session = window.xTransientSession
  if not session.transientWindow.isNil:
    return true
  if target.isNil:
    return true
  not responderChainContains(Responder(target), session.ownerResponder)

proc dispatchMouseButton(window: Window, event: MouseEvent, pressed: bool): bool =
  if pressed and window.hasActiveTransientSession() and window.xContentView.isNil:
    discard window.dismissTransientSession(tdrOutsideClick)
    return true
  if window.xContentView.isNil:
    return false
  let contentPoint = window.contentPoint(event.location)
  var dispatchEvent = event
  var target: View
  var stopBefore: Responder
  if pressed:
    target = window.contentHitTest(contentPoint)
    if window.shouldDismissTransientForMouse(target):
      discard window.dismissTransientSession(tdrOutsideClick)
      return true
    if target.isNil:
      return false
    dispatchEvent.clickCount = window.nextClickCount(target, event)
    let hitPolicy = window.mouseHitPolicyInChain(target, contentPoint, dispatchEvent)
    case hitPolicy.policy
    of chpDefault:
      discard
    of chpIgnore:
      return true
    of chpSelectRow:
      if hitPolicy.responder of View:
        target = View(hitPolicy.responder)
    of chpTrackCell:
      window.xMousePolicyStopResponder = hitPolicy.responder
    of chpSelectAndTrack:
      discard window.applyMouseHitPolicy(
        hitPolicy.responder, target, contentPoint, dispatchEvent
      )
      window.xMousePolicyStopResponder = hitPolicy.responder
    window.xMouseCaptureView = target
    if target.acceptsFirstResponder():
      discard window.setFirstResponder(target, focusVisible = false)
  else:
    target = window.xMouseCaptureView
    if target.isNil:
      target = window.contentHitTest(contentPoint)
    window.xMouseCaptureView = nil
    stopBefore = window.xMousePolicyStopResponder
    window.xMousePolicyStopResponder = nil
    if target.isNil:
      window.setMouseActiveView(nil)
      return false
    if dispatchEvent.clickCount <= 0:
      dispatchEvent.clickCount = max(window.xMouseClickCount, 1)

  let selector =
    case event.button
    of mbPrimary:
      if pressed:
        mouseDown()
      else:
        mouseUp()
    of mbSecondary:
      if pressed:
        rightMouseDown()
      else:
        rightMouseUp()
    of mbOther:
      if pressed:
        otherMouseDown()
      else:
        otherMouseUp()

  if pressed:
    let dispatch = window.dispatchMouseEventInChain(
      target, contentPoint, dispatchEvent, selector, window.xMousePolicyStopResponder
    )
    result = dispatch.handled
    if dispatch.handled and dispatch.responder of View:
      window.setMouseActiveView(View(dispatch.responder))
      window.xMouseTrackingEvent = dispatchEvent
      window.xHasMouseTrackingEvent = true
    else:
      window.setMouseActiveView(nil)
      window.xHasMouseTrackingEvent = false
  else:
    let dispatch = window.dispatchMouseEventInChain(
      target, contentPoint, dispatchEvent, selector, stopBefore
    )
    result = dispatch.handled
    window.setMouseActiveView(nil)
    window.xMouseTrackingEvent = MouseEvent()
    window.xHasMouseTrackingEvent = false
    window.xMouseClickCount = 0

proc dispatchMouseMove(window: Window, event: MouseEvent, dragging: bool): bool =
  if window.xContentView.isNil:
    return false
  let contentPoint = window.contentPoint(event.location)
  var target: View
  if dragging:
    target = window.xMouseCaptureView
    if target.isNil:
      target = window.contentHitTest(contentPoint)
  else:
    target = window.contentHitTest(contentPoint)

  if not dragging:
    result = window.updateHoverView(target, contentPoint, event)

  if target.isNil:
    return result

  if dragging:
    let selector =
      case event.button
      of mbPrimary:
        mouseDragged()
      of mbSecondary:
        rightMouseDragged()
      of mbOther:
        otherMouseDragged()
    result = window.dispatchMouseEventInChain(
      target, contentPoint, event, selector, window.xMousePolicyStopResponder
    ).handled
    if result:
      window.xMouseTrackingEvent = event
      window.xHasMouseTrackingEvent = true
  else:
    result =
      window.dispatchMouseEventInChain(target, contentPoint, event, mouseMoved()).handled or
      result

proc dispatchHelpRequested*(window: Window, event: MouseEvent): bool =
  if window.xContentView.isNil:
    return false
  let contentPoint = window.contentPoint(event.location)
  let target = window.contentHitTest(contentPoint)
  if target.isNil:
    return false
  window.dispatchMouseEventInChain(target, contentPoint, event, helpRequested()).handled

proc dispatchCursorUpdate*(window: Window, event: MouseEvent): bool =
  if window.xContentView.isNil:
    return false
  let contentPoint = window.contentPoint(event.location)
  let target = window.contentHitTest(contentPoint)
  if target.isNil:
    return false
  window.dispatchMouseEventInChain(target, contentPoint, event, cursorUpdate()).handled

proc dispatchUpdateTrackingAreas*(window: Window, event: MouseEvent): bool =
  if window.xContentView.isNil:
    return false
  let contentPoint = window.contentPoint(event.location)
  let target = window.contentHitTest(contentPoint)
  if target.isNil:
    return false

  window.dispatchMouseEventInChain(target, contentPoint, event, updateTrackingAreas()).handled

proc dispatchScrollWheel*(window: Window, event: events.ScrollEvent): bool =
  if window.xContentView.isNil:
    return false
  var contentPoint = window.contentPoint(event.location)
  var target = window.contentHitTest(contentPoint)
  if event.momentumPhase == sepBegan:
    window.xMomentumScrollTarget = target
    window.xMomentumScrollContentPoint = contentPoint
  elif event.momentumPhase != sepNone and not window.xMomentumScrollTarget.isNil:
    target = window.xMomentumScrollTarget
    contentPoint = window.xMomentumScrollContentPoint
  elif event.momentumPhase == sepNone:
    window.xMomentumScrollTarget = nil
  if target.isNil:
    return false
  result = window.dispatchScrollEventInChain(target, contentPoint, event).handled
  if event.momentumPhase in {sepEnded, sepCancelled}:
    window.xMomentumScrollTarget = nil

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

proc rightMouseDownAt*(
    window: Window,
    point: Point,
    clickCount = 0,
    modifiers: set[KeyModifier] = {},
    timestamp = 0.0,
): bool =
  window.mouseDownAt(point, mbSecondary, clickCount, modifiers, timestamp)

proc rightMouseUpAt*(
    window: Window,
    point: Point,
    clickCount = 0,
    modifiers: set[KeyModifier] = {},
    timestamp = 0.0,
): bool =
  window.mouseUpAt(point, mbSecondary, clickCount, modifiers, timestamp)

proc otherMouseDownAt*(
    window: Window,
    point: Point,
    clickCount = 0,
    modifiers: set[KeyModifier] = {},
    timestamp = 0.0,
): bool =
  window.mouseDownAt(point, mbOther, clickCount, modifiers, timestamp)

proc otherMouseUpAt*(
    window: Window,
    point: Point,
    clickCount = 0,
    modifiers: set[KeyModifier] = {},
    timestamp = 0.0,
): bool =
  window.mouseUpAt(point, mbOther, clickCount, modifiers, timestamp)

proc scrollWheelAt*(
    window: Window,
    point: Point,
    deltaX = 0.0'f32,
    deltaY = 0.0'f32,
    modifiers: set[KeyModifier] = {},
    timestamp = 0.0,
): bool =
  window.dispatchScrollWheel(
    events.ScrollEvent(
      location: point,
      deltaX: deltaX,
      deltaY: deltaY,
      phase: sepChanged,
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

proc dispatchMouseTrackingTick(window: Window, timestamp = 0.0): bool =
  if window.xContentView.isNil or window.xMouseCaptureView.isNil or
      window.xMouseActiveView.isNil or not window.xHasMouseTrackingEvent:
    return false
  var event = window.xMouseTrackingEvent
  event.timestamp = eventTimestamp(timestamp)
  let contentPoint = window.contentPoint(event.location)

  window.dispatchMouseEventInChain(
    window.xMouseCaptureView,
    contentPoint,
    event,
    mouseTrackingTick(),
    window.xMousePolicyStopResponder,
  ).handled

proc mouseTrackingTickAt*(
    window: Window,
    point: Point,
    button = mbPrimary,
    modifiers: set[KeyModifier] = {},
    timestamp = 0.0,
): bool =
  if window.xMouseCaptureView.isNil:
    return false
  window.xMouseTrackingEvent = MouseEvent(
    location: point,
    button: button,
    clickCount: max(window.xMouseClickCount, 1),
    modifiers: modifiers,
    timestamp: eventTimestamp(timestamp),
  )
  window.xHasMouseTrackingEvent = true
  window.dispatchMouseTrackingTick(timestamp)

proc dispatchHostMouseButton(window: Window, event: MouseEvent, pressed: bool) =
  discard window.dispatchMouseButton(event, pressed)
  discard window.requestNativeDisplayUpdateIfNeeded()

proc dispatchHostMouseMove(window: Window, event: MouseEvent, dragging: bool) =
  discard window.dispatchMouseMove(event, dragging)
  discard window.requestNativeDisplayUpdateIfNeeded()

proc dispatchHostScroll(window: Window, event: events.ScrollEvent) =
  discard window.dispatchScrollWheel(event)
  discard window.requestNativeDisplayUpdateIfNeeded()

proc dispatchHostKey(window: Window, event: HostKeyEvent) =
  if event.pressed and event.isEscape:
    if window.dispatchKeyDown(event.event):
      discard
    elif not window.xOwnerWindow.isNil:
      discard window.xOwnerWindow.dismissTransientSession(tdrEscape)
    elif window.hasActiveTransientSession():
      discard window.dismissTransientSession(tdrEscape)
    discard window.requestNativeDisplayUpdateIfNeeded()
    return
  if event.isModifierChange:
    discard window.dispatchFlagsChanged(event.event)
  elif event.pressed:
    discard window.dispatchKeyDown(event.event)
  else:
    discard window.dispatchKeyUp(event.event)
  discard window.requestNativeDisplayUpdateIfNeeded()

proc dispatchHostTextInput(window: Window, text: string) =
  discard window.dispatchTextInput(text)
  discard window.requestNativeDisplayUpdateIfNeeded()

proc dispatchHostFocusChanged(window: Window, focused: bool) =
  if focused and not window.xIsPopup and window.hasActiveTransientSession():
    discard window.dismissTransientSession(tdrFocusChange)
  discard window.requestNativeDisplayUpdateIfNeeded()

proc markHostClosed(window: Window) =
  window.releaseThreadRenderer(waitForRelease = true)
  window.stopInsertionPointBlink()
  window.stopAnimationClock()
  window.xClosed = true
  window.xVisibleRequested = false
  window.xMiniaturized = false
  if window.xTransientSession.active:
    discard window.dismissTransientSession(tdrOwnerClosed)
  else:
    window.closeAuxiliaryWindows(notifyDone = false)
  if not window.xOwnerWindow.isNil:
    window.xOwnerWindow.detachAuxiliaryWindow(window)
    window.xOwnerWindow = nil
  window.notifyApplication(WindowDidCloseSelector)

proc useThreadRenderer*(window: Window, renderer: ThreadRendererClient) =
  if window.isNil or window.xThreadRenderer == renderer:
    return
  window.releaseThreadRenderer(waitForRelease = false)
  window.xThreadRenderer = renderer
  window.xThreadHost = nil
  for auxiliary in window.xAuxiliaryWindows:
    if not auxiliary.isNil:
      auxiliary.useThreadRenderer(renderer)

proc ensureThreadHost(window: Window) =
  if window.xThreadRenderer.isNil or window.xHostWindow.isNil or
      not window.xThreadHost.isNil:
    return
  window.xThreadHost =
    window.xHostWindow.attachThreadRenderer(window.xThreadRenderer, window.xFrame.size)

proc drainThreadHostEvents(window: Window): int =
  if window.xThreadHost.isNil:
    return
  var event: ThreadHostEvent
  while window.xThreadHost.pollEvent(event):
    inc result
    case event.kind
    of theRendered:
      window.xThreadHost.acknowledgeRender(event.renderId)
      window.xThreadHost.renderCount = event.renderCount
      window.xThreadHost.renderRequested = false
    of theRenderTargetReleased:
      window.xThreadHost.clearRenderResources()
      window.xThreadHost.acknowledgeRenderTargetRelease()

proc releaseThreadRenderer(window: Window, waitForRelease: bool) =
  let client = window.xThreadHost
  if client.isNil:
    return
  if not window.xHostWindow.isNil:
    window.xHostWindow.detachThreadRenderer(window.xThreadRenderer, client)
  while waitForRelease and client.renderTargetReleasePending() and
      not window.xThreadRenderer.isNil and window.xThreadRenderer.isRunning():
    discard window.drainThreadHostEvents()
    if client.renderTargetReleasePending():
      sleep(1)
  window.xThreadHost = nil

proc ensureNativeWindow*(window: Window) =
  if window.nativeReady:
    window.ensureThreadHost()
    return

  let callbacks = HostWindowCallbacks(
    onClose: proc() =
      window.markHostClosed(),
    onResize: proc() =
      discard window.syncNativeGeometry(),
    onMove: proc(pos: Point) =
      window.xFrame.origin = pos
      discard window.saveFrameUsingName(),
    onMouseButton: proc(event: MouseEvent, pressed: bool) =
      window.dispatchHostMouseButton(event, pressed),
    onMouseMove: proc(event: MouseEvent, dragging: bool) =
      window.dispatchHostMouseMove(event, dragging),
    onScroll: proc(event: events.ScrollEvent) =
      window.dispatchHostScroll(event),
    onKey: proc(event: HostKeyEvent) =
      window.dispatchHostKey(event),
    onTextInput: proc(text: string) =
      window.dispatchHostTextInput(text),
    onRender: proc() =
      window.renderNativeWindow(),
    onFocusChanged: proc(focused: bool) =
      window.dispatchHostFocusChanged(focused),
    onPopupDone: proc() =
      window.markHostClosed()
      if not window.xOnPopupDone.isNil:
        window.xOnPopupDone()
    ,
  )
  if window.xIsPopup:
    if window.xOwnerWindow.isNil:
      return
    window.xOwnerWindow.ensureNativeWindow()
    if not window.xOwnerWindow.nativeReady:
      return
    window.xHostWindow = createPopupHostWindow(
      window.xOwnerWindow.xHostWindow, window.xPopupPlacement, callbacks
    )
  else:
    window.xHostWindow = createHostWindow(window.xFrame, window.xTitle, callbacks)
  window.syncNativeSizeLimits()
  window.ensureThreadHost()
  if window.xVisibleRequested:
    window.xHostWindow.setVisible(true)

proc pumpNativeWindowFrame*(window: Window) =
  if window.xClosed:
    return
  if not window.xVisibleRequested:
    if not window.xHostWindow.isNil:
      window.xHostWindow.pump()
    return
  window.ensureNativeWindow()
  discard window.drainThreadHostEvents()
  if window.drainAnimations() > 0:
    discard window.requestNativeDisplayUpdateIfNeeded()
  discard window.requestNativeDisplayUpdateIfNeeded()
  if window.nativeReady:
    window.xHostWindow.pump()
  if window.dispatchMouseTrackingTick():
    discard window.requestNativeDisplayUpdateIfNeeded()
  var idx = 0
  while idx < window.xAuxiliaryWindows.len:
    let auxiliary = window.xAuxiliaryWindows[idx]
    if auxiliary.isNil or auxiliary.isClosed:
      window.xAuxiliaryWindows.delete(idx)
      continue
    if auxiliary.isVisible:
      auxiliary.pumpNativeWindowFrame()
    inc idx

proc rawInputToLogical*(
    rawPos: siwinshim.Vec2, inputSize: siwinshim.IVec2, logicalSize: siwinshim.Vec2
): siwinshim.Vec2 =
  nimkitBackend.rawInputToLogical(rawPos, inputSize, logicalSize)
