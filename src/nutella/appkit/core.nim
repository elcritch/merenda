import std/[math, os, strutils, unicode]
import pkg/chroma
import pkg/vmath

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as figrender
import figdraw/windowing/siwinshim as siwinshim

import ../objc
import ../objc/ivar
import ./types

type NSButtonCallbackProc = proc(sender: ID)

proc toFigColor(c: NSColor): Color {.inline.} =
  color(c.r, c.g, c.b, c.a)

proc toFigRgba(c: NSColor): ColorRGBA {.inline.} =
  rgba(c.toFigColor())

proc solidFill(c: NSColor): Fill {.inline.} =
  fill(c.toFigRgba())

var appkitTypefaceId {.threadvar.}: TypefaceId
var appkitFontReady {.threadvar.}: bool
var appkitFontUnavailable {.threadvar.}: bool

proc appkitFontCandidates(): seq[string] =
  result = @["Ubuntu.ttf", "HackNerdFont-Regular.ttf"]
  let dir = figDataDir()
  if not dirExists(dir):
    return
  for kind, path in walkDir(dir):
    if kind != pcFile:
      continue
    let (_, name, ext) = splitFile(path)
    let lowerExt = ext.toLowerAscii()
    if lowerExt notin [".ttf", ".otf"]:
      continue
    let fileName = name & ext
    if fileName notin result:
      result.add(fileName)

proc ensureAppKitFont(): bool =
  if appkitFontReady:
    return true
  if appkitFontUnavailable:
    return false
  for candidate in appkitFontCandidates():
    try:
      appkitTypefaceId = loadTypeface(candidate)
      appkitFontReady = true
      return true
    except Exception:
      discard
  appkitFontUnavailable = true
  false

proc appkitFont(size: float32): FigFont {.inline.} =
  appkitTypefaceId.fontWithSize(size)

proc uniformCorners(radius: float32): array[DirectionCorners, float32] {.inline.} =
  [radius, radius, radius, radius]

proc clampWindowSize(v: float32): int32 {.inline.} =
  if v < 1.0: 1 else: v.round.int32

proc toFontHorizontal(alignment: NSTextAlignment): FontHorizontal {.inline.} =
  case alignment
  of NSRightTextAlignment: FontHorizontal.Right
  of NSCenterTextAlignment: FontHorizontal.Center
  else: FontHorizontal.Left

proc normalizeButtonState(value: int, allowsMixedState: bool): int {.inline.} =
  if value == NSMixedState and allowsMixedState:
    return NSMixedState
  if value == NSOnState:
    return NSOnState
  NSOffState

proc ownFromId[T: NSObject](id: ID): T =
  if id.isNil:
    return T(value: nil)
  var borrowed = asType[T](id)
  result = retain(borrowed)
  borrowed.value = nil

proc retainId(id: ID): ID =
  if id.isNil:
    return nil
  var borrowed = asType[NSObject](id)
  var owned = retain(borrowed)
  borrowed.value = nil
  result = owned.value
  owned.value = nil

proc releaseId(id: ID) =
  if id.isNil:
    return
  var owned = asType[NSObject](id)
  discard owned

proc replacedOwnedId(slot: ID, next: ID): ID =
  if slot == next:
    return slot
  result = retainId(next)
  releaseId(slot)

proc clearOwnedIds(ids: var seq[ID]) =
  for id in ids:
    releaseId(id)
  ids.setLen(0)

proc removeOwnedIdAt(ids: var seq[ID], idx: int) =
  let old = ids[idx]
  ids.del(idx)
  releaseId(old)

template callSuperIdFrom(currentType: typedesc, obj: NSObject, op: SEL): ID =
  block:
    var superObj =
      ObjcSuper(receiver: obj.value, superClass: getClass(currentType).getSuperclass())
    cast[proc(superObj: var ObjcSuper, selParam: SEL): ID {.cdecl, varargs.}](objc_msgSendSuper)(
      superObj, op
    )

proc clearSuperviewRef(viewId: ID)
proc detachSubviews(view: NSObject)

proc runApplicationFrames(app: NSObject, maxFrames: int): int

objcImpl:
  type NXResponder* = object of NSObject

objcImpl:
  type NXView* = object of NXResponder
    viewFrame: NSRect
    viewBackgroundColor: NSColor
    viewHidden: bool
    viewSuperview: ID
    viewTag: int
    viewSubviews: seq[ID]

  method init*(self: var NXView): NXView =
    result = asType[NXView](callSuperIdFrom(NXView, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.viewFrame = nsRect(0, 0, 100, 100)
    result.viewBackgroundColor = nsColor(0.86, 0.90, 0.96, 1.0)
    result.viewHidden = false
    result.viewSuperview = nil
    result.viewTag = 0
    result.viewSubviews = @[]

  method initWithFrame*(self: var NXView, x, y, width, height: cfloat): NXView =
    result = self.init()
    if result.isNil:
      return
    result.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))

  method setFrame*(self: NXView, x, y, width, height: cfloat) =
    self.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))

  method setBackgroundColor*(self: NXView, r, g, b, a: cfloat) =
    self.viewBackgroundColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setHidden*(self: NXView, hidden: bool) =
    self.viewHidden = hidden

  method dealloc(self: NXView) {.used.} =
    detachSubviews(self)
    clearIvarRefs(self)
    discard callSuperIdFrom(NXView, self, getSelector("dealloc"))

objcImpl:
  type NXControl* = object of NXView
    controlEnabled: bool
    controlAlignment: NSTextAlignment

  method init*(self: var NXControl): NXControl =
    result = asType[NXControl](callSuperIdFrom(NXControl, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.controlEnabled = true
    result.controlAlignment = NSNaturalTextAlignment

  method setEnabled*(self: NXControl, enabled: bool) =
    self.controlEnabled = enabled

  method isEnabled*(self: NXControl): bool =
    self.controlEnabled

  method alignment*(self: NXControl): NSTextAlignment =
    self.controlAlignment

  method setAlignment*(self: NXControl, alignment: NSTextAlignment) =
    self.controlAlignment = alignment

objcImpl:
  type NXTextField* = object of NXControl
    textFieldStringValue {.set: setStringValue, get: stringValue.}: string
    textFieldColor: NSColor
    textFieldBackgroundColor: NSColor
    textFieldDrawsBackground: bool

  method init*(self: var NXTextField): NXTextField =
    result =
      asType[NXTextField](callSuperIdFrom(NXTextField, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.controlEnabled = true
    result.controlAlignment = NSNaturalTextAlignment
    result.textFieldStringValue = ""
    result.textFieldColor = nsColor(0.08, 0.08, 0.08, 1.0)
    result.textFieldBackgroundColor = nsColor(0.98, 0.99, 1.0, 1.0)
    result.textFieldDrawsBackground = true

  method setEnabled*(self: NXTextField, enabled: bool) =
    self.controlEnabled = enabled

  method isEnabled*(self: NXTextField): bool =
    self.controlEnabled

  method alignment*(self: NXTextField): NSTextAlignment =
    self.controlAlignment

  method setAlignment*(self: NXTextField, alignment: NSTextAlignment) =
    self.controlAlignment = alignment

  method textColor*(self: NXTextField): NSColor =
    self.textFieldColor

  method backgroundColor*(self: NXTextField): NSColor =
    self.textFieldBackgroundColor

  method drawsBackground*(self: NXTextField): bool =
    self.textFieldDrawsBackground

  method setTextColor*(self: NXTextField, color: NSColor) =
    self.textFieldColor = color

  method setBackgroundColor*(self: NXTextField, color: NSColor) =
    self.textFieldBackgroundColor = color

  method setTextColor*(self: NXTextField, r, g, b, a: cfloat) =
    self.textFieldColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setBackgroundColor*(self: NXTextField, r, g, b, a: cfloat) =
    self.textFieldBackgroundColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setDrawsBackground*(self: NXTextField, value: bool) =
    self.textFieldDrawsBackground = value

  method dealloc(self: NXTextField) {.used.} =
    self.textFieldStringValue = ""
    discard callSuperIdFrom(NXTextField, self, getSelector("dealloc"))

objcImpl:
  type NXButton* = object of NXControl
    buttonTitle: string
    buttonStateValue: int
    buttonAllowsMixedState: bool
    buttonOnClick: NSButtonCallbackProc

  method init*(self: var NXButton): NXButton =
    result = asType[NXButton](callSuperIdFrom(NXButton, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.controlEnabled = true
    result.controlAlignment = NSNaturalTextAlignment
    result.buttonTitle = "Button"
    result.buttonStateValue = NSOffState
    result.buttonAllowsMixedState = false
    result.buttonOnClick = nil

  method setTitle*(self: NXButton, value: string) =
    self.buttonTitle = value

  method title*(self: NXButton): string =
    self.buttonTitle

  method setEnabled*(self: NXButton, enabled: bool) =
    self.controlEnabled = enabled

  method isEnabled*(self: NXButton): bool =
    self.controlEnabled

  method alignment*(self: NXButton): NSTextAlignment =
    self.controlAlignment

  method setAlignment*(self: NXButton, alignment: NSTextAlignment) =
    self.controlAlignment = alignment

  method setState*(self: NXButton, value: cint) =
    self.buttonStateValue = normalizeButtonState(value.int, self.buttonAllowsMixedState)

  method state*(self: NXButton): int =
    self.buttonStateValue

  method setAllowsMixedState*(self: NXButton, value: bool) =
    self.buttonAllowsMixedState = value
    self.buttonStateValue = normalizeButtonState(self.buttonStateValue, value)

  method allowsMixedState*(self: NXButton): bool =
    self.buttonAllowsMixedState

  method setNextState*(self: NXButton) =
    if self.buttonAllowsMixedState:
      case self.buttonStateValue
      of NSOffState:
        self.buttonStateValue = NSOnState
      of NSOnState:
        self.buttonStateValue = NSMixedState
      else:
        self.buttonStateValue = NSOffState
    else:
      if self.buttonStateValue == NSOnState:
        self.buttonStateValue = NSOffState
      else:
        self.buttonStateValue = NSOnState

  method performClick*(self: NXButton, sender: NSObject) =
    discard sender
    if not self.controlEnabled:
      return
    self.setNextState()
    let cb = self.buttonOnClick()
    if cb.isNil:
      return
    cb(self.value)

  method dealloc(self: NXButton) {.used.} =
    self.buttonTitle = ""
    self.buttonOnClick = nil
    discard callSuperIdFrom(NXButton, self, getSelector("dealloc"))

objcImpl:
  type NXWindow* = object of NXResponder
    windowFrame: NSRect
    windowTitle: string
    windowContentView: ID
    windowNativeWindow: siwinshim.Window
    windowRenderer: figrender.FigRenderer[siwinshim.SiwinRenderBackend]
    windowAutoScale: bool
    windowNativeReady: bool
    windowVisibleRequested: bool
    windowClosed: bool

  method init*(self: var NXWindow): NXWindow =
    result = asType[NXWindow](callSuperIdFrom(NXWindow, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.windowFrame = nsRect(100, 100, 640, 420)
    result.windowTitle = "Nutella Window"
    result.windowContentView = nil
    result.windowNativeWindow = nil
    result.windowRenderer = nil
    result.windowAutoScale = true
    result.windowNativeReady = false
    result.windowVisibleRequested = false
    result.windowClosed = false

  method initWithContentRect*(
      self: var NXWindow, x, y, width, height: cfloat
  ): NXWindow =
    result = self.init()
    if result.isNil:
      return
    result.windowFrame =
      nsRect(x.float32, y.float32, max(width.float32, 1.0), max(height.float32, 1.0))

  method setContentView*(self: NXWindow, view: NXView) =
    if self.isNil:
      return
    if not self.windowContentView.isNil and self.windowContentView != view.value:
      clearSuperviewRef(self.windowContentView)
    if not view.isNil:
      let parentId = view.viewSuperview()
      if not parentId.isNil:
        var parent = ownFromId[NXView](parentId)
        if not parent.isNil:
          var subviews = parent.viewSubviews()
          for i, candidate in subviews:
            if candidate == view.value:
              subviews.del(i)
              parent.viewSubviews = subviews
              releaseId(view.value)
              break
      view.viewSuperview = nil
    self.windowContentView = replacedOwnedId(self.windowContentView(), view.value)

  method contentView*(self: NXWindow): NXView =
    if self.windowContentView.isNil:
      return NXView(value: nil)
    result = ownFromId[NXView](self.windowContentView)

  method setTitle*(self: NXWindow, value: string) =
    self.windowTitle = value
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      self.windowNativeWindow.title = value

  method setContentSize*(self: NXWindow, width, height: cfloat) =
    var frame = self.windowFrame()
    frame.size = nsSize(max(width.float32, 1.0), max(height.float32, 1.0))
    self.windowFrame = frame
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      self.windowNativeWindow.size =
        ivec2(clampWindowSize(frame.size.width), clampWindowSize(frame.size.height))

  method setFrameOrigin*(self: NXWindow, x, y: cfloat) =
    var frame = self.windowFrame()
    frame.origin = nsPoint(x.float32, y.float32)
    self.windowFrame = frame

  method makeKeyAndOrderFront*(self: NXWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    self.windowVisibleRequested = true

  method close*(self: NXWindow) =
    self.windowClosed = true
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      siwinshim.close(self.windowNativeWindow)

  method dealloc(self: NXWindow) {.used.} =
    if self.windowNativeReady and (not self.windowNativeWindow.isNil):
      siwinshim.close(self.windowNativeWindow)
    self.windowContentView = replacedOwnedId(self.windowContentView(), nil)
    clearIvarRefs(self)
    discard callSuperIdFrom(NXWindow, self, getSelector("dealloc"))

objcImpl:
  type NXApplication* = object of NXResponder
    appWindows: seq[ID]
    appRunning: bool

  method init*(self: var NXApplication): NXApplication =
    result =
      asType[NXApplication](callSuperIdFrom(NXApplication, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.appWindows = @[]
    result.appRunning = false

  method addWindow*(self: NXApplication, window: NXWindow) =
    if self.isNil or window.isNil:
      return
    var windows = self.appWindows()
    if window.value notin windows:
      windows.add(retainId(window.value))
      self.appWindows = windows
    window.windowVisibleRequested = true

  method run*(self: NXApplication) =
    discard runApplicationFrames(self, -1)

  method stop*(self: NXApplication) =
    self.appRunning = false

  method dealloc(self: NXApplication) {.used.} =
    var windows = self.appWindows()
    clearOwnedIds(windows)
    self.appWindows = windows
    clearIvarRefs(self)
    discard callSuperIdFrom(NXApplication, self, getSelector("dealloc"))

type
  # The Objective-C runtime already provides NSResponder/NSView/NSButton/etc on macOS.
  # We keep Nutella's runtime classes namespaced (NX*) and export Cocoa-style API names via
  # aliases so objcImpl does not collide with host AppKit classes.
  NSResponder* = NXResponder
  NSView* = NXView
  NSControl* = NXControl
  NSTextField* = NXTextField
  NSButton* = NXButton
  NSWindow* = NXWindow
  NSApplication* = NXApplication

proc new*(t: typedesc[NSView]): NSView =
  when false:
    discard t
  var allocated = NSView.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSControl]): NSControl =
  when false:
    discard t
  var allocated = NSControl.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSTextField]): NSTextField =
  when false:
    discard t
  var allocated = NSTextField.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSButton]): NSButton =
  when false:
    discard t
  var allocated = NSButton.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSWindow]): NSWindow =
  when false:
    discard t
  var allocated = NSWindow.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSApplication]): NSApplication =
  when false:
    discard t
  var allocated = NSApplication.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc clearSuperviewRef(viewId: ID) =
  if viewId.isNil:
    return
  let child = ownFromId[NSView](viewId)
  if child.isNil:
    return
  child.viewSuperview = nil

proc detachSubviews(view: NSObject) =
  if view.isNil:
    return
  var v = asType[NSView](view.value)
  if v.isNil:
    return
  var children = v.viewSubviews()
  for child in children:
    clearSuperviewRef(child)
    releaseId(child)
  children.setLen(0)
  v.viewSubviews = children
  v.value = nil

proc frame*(view: NSView): NSRect =
  view.viewFrame()

proc frame*(window: NSWindow): NSRect =
  window.windowFrame()

proc frameOrigin*(view: NSView): NSPoint =
  view.frame().origin

proc frameOrigin*(window: NSWindow): NSPoint =
  window.frame().origin

proc frameSize*(view: NSView): NSSize =
  view.frame().size

proc frameSize*(window: NSWindow): NSSize =
  window.frame().size

proc title*(window: NSWindow): string =
  window.windowTitle()

proc isHidden*(view: NSView): bool =
  view.viewHidden()

proc tag*(view: NSView): int =
  view.viewTag()

proc setTag*(view: NSView, value: int) =
  view.viewTag = value

proc setBackgroundColor*(view: NSView, r, g, b: float32, a: float32 = 1.0'f32) =
  view.viewBackgroundColor = nsColor(r, g, b, a)

proc setHidden*(view: NSView, hidden: bool) =
  view.viewHidden = hidden

proc setFrame*(view: NSView, frame: NSRect) =
  view.setFrame(
    frame.origin.x.cfloat, frame.origin.y.cfloat, frame.size.width.cfloat,
    frame.size.height.cfloat,
  )

proc setFrameOrigin*(view: NSView, origin: NSPoint) =
  let f = view.frame()
  view.setFrame(nsRect(origin.x, origin.y, f.size.width, f.size.height))

proc setFrameSize*(view: NSView, size: NSSize) =
  let f = view.frame()
  view.setFrame(
    nsRect(f.origin.x, f.origin.y, max(size.width, 0.0), max(size.height, 0.0))
  )

proc setFrame*(window: NSWindow, frame: NSRect) =
  var nextFrame = nsRect(
    frame.origin.x,
    frame.origin.y,
    max(frame.size.width, 1.0),
    max(frame.size.height, 1.0),
  )
  window.windowFrame = nextFrame
  if window.windowNativeReady() and not window.windowNativeWindow().isNil:
    window.windowNativeWindow.size = ivec2(
      clampWindowSize(nextFrame.size.width), clampWindowSize(nextFrame.size.height)
    )

proc setFrameOrigin*(window: NSWindow, origin: NSPoint) =
  let f = window.frame()
  window.setFrame(nsRect(origin.x, origin.y, f.size.width, f.size.height))

proc setFrameSize*(window: NSWindow, size: NSSize) =
  let f = window.frame()
  window.setFrame(nsRect(f.origin.x, f.origin.y, size.width, size.height))

proc setContentSize*(window: NSWindow, size: NSSize) =
  window.setFrameSize(size)

proc setContentSize*(window: NSWindow, width, height: float32) =
  window.setContentSize(nsSize(width, height))

proc subviews*(view: NSView): seq[NSView] =
  let childIds = view.viewSubviews()
  result = newSeq[NSView](childIds.len)
  for i, child in childIds:
    result[i] = ownFromId[NSView](child)

proc superview*(view: NSView): NSView =
  let parentId = view.viewSuperview()
  if parentId.isNil:
    return NSView(value: nil)
  ownFromId[NSView](parentId)

proc removeSubviewById(parent: NSView, childId: ID): bool =
  if parent.isNil or childId.isNil:
    return false
  var children = parent.viewSubviews()
  for i, candidate in children:
    if candidate == childId:
      clearSuperviewRef(childId)
      children.del(i)
      parent.viewSubviews = children
      releaseId(childId)
      return true
  false

proc removeFromSuperview*(view: NSView) =
  if view.isNil:
    return
  let parentId = view.viewSuperview()
  if parentId.isNil:
    return
  view.viewSuperview = nil
  let parent = ownFromId[NSView](parentId)
  if parent.isNil:
    return
  discard removeSubviewById(parent, view.value)

proc addSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil or self.value == view.value:
    return
  let parentId = view.viewSuperview()
  if parentId == self.value:
    var children = self.viewSubviews()
    if view.value notin children:
      children.add(retainId(view.value))
      self.viewSubviews = children
    return
  if not parentId.isNil:
    view.removeFromSuperview()
  var children = self.viewSubviews()
  if view.value notin children:
    children.add(retainId(view.value))
    self.viewSubviews = children
  view.viewSuperview = self.value

proc removeSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil:
    return
  discard removeSubviewById(self, view.value)

proc viewWithTag*(view: NSView, wantedTag: int): NSView =
  if view.isNil:
    return NSView(value: nil)
  if view.viewTag() == wantedTag:
    return retain(view)
  for childId in view.viewSubviews():
    let child = ownFromId[NSView](childId)
    if child.isNil:
      continue
    let hit = child.viewWithTag(wantedTag)
    if not hit.isNil:
      return hit
  NSView(value: nil)

proc setOnClick*(button: NSButton, cb: proc(sender: NSButton)) =
  if cb.isNil:
    button.buttonOnClick = nil
  else:
    button.buttonOnClick = proc(sender: ID) =
      cb(ownFromId[NSButton](sender))

proc click*(button: NSButton) =
  if not button.controlEnabled():
    return
  if button.buttonAllowsMixedState():
    case button.buttonStateValue()
    of NSOffState:
      button.buttonStateValue = NSOnState
    of NSOnState:
      button.buttonStateValue = NSMixedState
    else:
      button.buttonStateValue = NSOffState
  else:
    if button.buttonStateValue() == NSOnState:
      button.buttonStateValue = NSOffState
    else:
      button.buttonStateValue = NSOnState
  let cb = button.buttonOnClick()
  if not cb.isNil:
    cb(button.value)

proc ensureContentView(window: NSWindow): NSView =
  let cv = window.windowContentView()
  if not cv.isNil:
    return ownFromId[NSView](cv)

  let frame = window.windowFrame()
  var rootAlloc = NSView.alloc()
  var root = rootAlloc.initWithFrame(
    0.cfloat, 0.cfloat, frame.size.width.cfloat, frame.size.height.cfloat
  )
  rootAlloc.value = nil
  window.windowContentView = replacedOwnedId(window.windowContentView(), root.value)
  result = root

proc noRenderShadows(): array[ShadowCount, RenderShadow] =
  for i in result.low .. result.high:
    result[i] = RenderShadow(
      style: NoShadow,
      blur: 0.0,
      spread: 0.0,
      x: 0.0,
      y: 0.0,
      fill: nsColor(0.0, 0.0, 0.0, 0.0).toFigColor(),
    )

proc textFieldDrawsBackground(view: NSView): bool =
  if not view.isKindOfClass(NSTextField):
    return false
  var textField = asType[NSTextField](view.value)
  result = textField.drawsBackground()
  textField.value = nil

proc buttonVisualState(view: NSView): int =
  if not view.isKindOfClass(NSButton):
    return NSOffState
  var button = asType[NSButton](view.value)
  result = button.state()
  button.value = nil

proc aquaButtonFill(state: int): Fill =
  case state
  of NSOnState:
    linear(
      nsColor(0.46, 0.64, 0.90, 1.0).toFigRgba(),
      nsColor(0.31, 0.50, 0.81, 1.0).toFigRgba(),
      nsColor(0.19, 0.34, 0.66, 1.0).toFigRgba(),
      axis = fgaY,
      midPos = 132'u8,
    )
  of NSMixedState:
    linear(
      nsColor(0.76, 0.79, 0.84, 1.0).toFigRgba(),
      nsColor(0.65, 0.69, 0.76, 1.0).toFigRgba(),
      nsColor(0.53, 0.58, 0.66, 1.0).toFigRgba(),
      axis = fgaY,
      midPos = 132'u8,
    )
  else:
    linear(
      nsColor(0.63, 0.78, 0.98, 1.0).toFigRgba(),
      nsColor(0.42, 0.65, 0.95, 1.0).toFigRgba(),
      nsColor(0.27, 0.50, 0.86, 1.0).toFigRgba(),
      axis = fgaY,
      midPos = 132'u8,
    )

proc aquaButtonStroke(state: int): Fill =
  case state
  of NSOnState:
    linear(
      nsColor(0.35, 0.50, 0.78, 1.0).toFigRgba(),
      nsColor(0.11, 0.23, 0.49, 1.0).toFigRgba(),
      axis = fgaY,
    )
  of NSMixedState:
    linear(
      nsColor(0.55, 0.60, 0.68, 1.0).toFigRgba(),
      nsColor(0.36, 0.41, 0.50, 1.0).toFigRgba(),
      axis = fgaY,
    )
  else:
    linear(
      nsColor(0.41, 0.60, 0.88, 1.0).toFigRgba(),
      nsColor(0.15, 0.33, 0.64, 1.0).toFigRgba(),
      axis = fgaY,
    )

proc viewShadows(view: NSView): array[ShadowCount, RenderShadow] =
  result = noRenderShadows()
  if view.isKindOfClass(NSButton):
    let state = buttonVisualState(view)
    let dropAlpha =
      if state == NSOnState:
        0.32
      elif state == NSMixedState:
        0.17
      else:
        0.27
    let bottomInsetAlpha =
      if state == NSOnState:
        0.22
      elif state == NSMixedState:
        0.19
      else:
        0.25
    result[0] = RenderShadow(
      style: DropShadow,
      blur: 2.8,
      spread: 0.0,
      x: 0.0,
      y: 1.2,
      fill: nsColor(0.10, 0.18, 0.35, dropAlpha).toFigColor(),
    )
    result[1] = RenderShadow(
      style: InnerShadow,
      blur: 1.2,
      spread: 0.0,
      x: 0.0,
      y: 1.0,
      fill: nsColor(1.0, 1.0, 1.0, 0.52).toFigColor(),
    )
    result[2] = RenderShadow(
      style: InnerShadow,
      blur: 1.5,
      spread: 0.0,
      x: 0.0,
      y: -1.0,
      fill: nsColor(0.03, 0.11, 0.28, bottomInsetAlpha).toFigColor(),
    )
  elif view.isKindOfClass(NSTextField):
    if not textFieldDrawsBackground(view):
      return
    result[0] = RenderShadow(
      style: InnerShadow,
      blur: 1.0,
      spread: 0.0,
      x: 0.0,
      y: 1.0,
      fill: nsColor(1.0, 1.0, 1.0, 0.45).toFigColor(),
    )
    result[1] = RenderShadow(
      style: DropShadow,
      blur: 1.0,
      spread: 0.0,
      x: 0.0,
      y: 1.0,
      fill: nsColor(0.34, 0.40, 0.52, 0.20).toFigColor(),
    )

proc viewFill(view: NSView): Fill =
  if view.isKindOfClass(NSButton):
    return aquaButtonFill(buttonVisualState(view))
  if view.isKindOfClass(NSTextField):
    var textField = asType[NSTextField](view.value)
    let drawsBackground = textField.textFieldDrawsBackground()
    let backgroundColor = textField.textFieldBackgroundColor()
    textField.value = nil
    if drawsBackground:
      return backgroundColor.solidFill()
    return nsColor(0.0, 0.0, 0.0, 0.0).solidFill()
  view.viewBackgroundColor().solidFill()

proc viewStrokeFill(view: NSView): Fill =
  if view.isKindOfClass(NSButton):
    return aquaButtonStroke(buttonVisualState(view))
  if view.isKindOfClass(NSTextField):
    if not textFieldDrawsBackground(view):
      return nsColor(0.0, 0.0, 0.0, 0.0).solidFill()
    return nsColor(0.64, 0.70, 0.80, 1.0).solidFill()
  nsColor(0.34, 0.42, 0.56, 0.28).solidFill()

proc viewCornerRadius(view: NSView): float32 =
  if view.isKindOfClass(NSButton):
    return 10.0
  if view.isKindOfClass(NSTextField):
    if not textFieldDrawsBackground(view):
      return 0.0
    return 8.0
  0.0

proc addAquaGlossOverlay(
    renders: var Renders, parentIdx: FigIdx, view: NSView, box: NSRect
) =
  if box.size.width <= 4 or box.size.height <= 4:
    return

  var glossFill = nsColor(1.0, 1.0, 1.0, 0.0).solidFill()
  var glossHeight = 0.0
  if view.isKindOfClass(NSButton):
    glossFill = linear(
      nsColor(1.0, 1.0, 1.0, 0.66).toFigRgba(),
      nsColor(1.0, 1.0, 1.0, 0.40).toFigRgba(),
      nsColor(1.0, 1.0, 1.0, 0.08).toFigRgba(),
      axis = fgaY,
      midPos = 150'u8,
    )
    glossHeight = box.size.height * 0.56
  elif view.isKindOfClass(NSTextField):
    if not textFieldDrawsBackground(view):
      return
    glossFill = linear(
      nsColor(1.0, 1.0, 1.0, 0.38).toFigRgba(),
      nsColor(1.0, 1.0, 1.0, 0.16).toFigRgba(),
      axis = fgaY,
    )
    glossHeight = box.size.height * 0.46
  else:
    return

  glossHeight = min(max(glossHeight, 6.0), box.size.height)
  let radius = viewCornerRadius(view)
  let glossBox = rect(
    box.origin.x + 1.0,
    box.origin.y + 1.0,
    max(box.size.width - 2.0, 0.0),
    max(glossHeight - 1.0, 0.0),
  )
  if glossBox.w <= 0 or glossBox.h <= 0:
    return

  discard renders.addChild(
    0.ZLevel,
    parentIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: glossBox,
      fill: glossFill,
      corners: [radius, radius, max(radius - 5.0, 0.0), max(radius - 5.0, 0.0)],
      stroke: RenderStroke(weight: 0.0, fill: nsColor(0.0, 0.0, 0.0, 0.0).toFigColor()),
    ),
  )

proc runesPrefix(layout: GlyphArrangement, maxRunes: int): string =
  var count = 0
  for rune in layout.runes:
    if count >= maxRunes:
      break
    result.add($rune)
    inc count
  if layout.runes.len > maxRunes:
    result.add("...")

proc dumpRenders(renders: Renders) =
  for z, list in renders.layers.pairs():
    echo "[appkit] layer=",
      z.int, " roots=", list.rootIds.len, " nodes=", list.nodes.len
    for i, node in list.nodes:
      let box = node.screenBox
      var line =
        "[appkit]   node[" & $i & "] kind=" & $node.kind & " parent=" & $node.parent.int &
        " children=" & $node.childCount & " box=(" & $box.x & "," & $box.y & " " & $box.w &
        "x" & $box.h & ")"
      if node.kind == nkText:
        line.add(
          " runes=" & $node.textLayout.runes.len & " preview=\"" &
            runesPrefix(node.textLayout, 40) & "\""
        )
      echo line

proc shouldDebugRenderDump(): bool =
  getEnv("NUTELLA_APPKIT_DEBUG_RENDER").strip().toLowerAscii() in
    ["1", "true", "yes", "on"]

proc textLayoutForView(
    view: NSView, box: NSRect
): tuple[ok: bool, layout: GlyphArrangement] =
  if box.size.width <= 2 or box.size.height <= 2:
    return (false, default(GlyphArrangement))
  if not ensureAppKitFont():
    return (false, default(GlyphArrangement))

  if view.isKindOfClass(NSTextField):
    var textField = asType[NSTextField](view.value)
    let textValue = textField.stringValue()
    let textColor = textField.textFieldColor()
    let textAlign = toFontHorizontal(textField.alignment())
    textField.value = nil
    if textValue.len == 0:
      return (false, default(GlyphArrangement))
    let spans = [(fs(appkitFont(18.0), textColor.toFigColor()), textValue)]
    let layout = typeset(
      rect(0, 0, box.size.width, box.size.height),
      spans,
      hAlign = textAlign,
      vAlign = FontVertical.Middle,
      minContent = false,
      wrap = true,
    )
    if shouldDebugRenderDump():
      echo "[appkit] textfield layout runes=",
        layout.runes.len, " text=\"", textValue, "\""
    return (true, layout)

  if view.isKindOfClass(NSButton):
    var button = asType[NSButton](view.value)
    let title = button.buttonTitle()
    let textAlign = toFontHorizontal(button.alignment())
    button.value = nil
    if title.len == 0:
      return (false, default(GlyphArrangement))
    let spans =
      [(fs(appkitFont(16.0), nsColor(0.98, 0.99, 1.0, 1.0).toFigColor()), title)]
    let layout = typeset(
      rect(0, 0, box.size.width, box.size.height),
      spans,
      hAlign = textAlign,
      vAlign = FontVertical.Middle,
      minContent = false,
      wrap = false,
    )
    if shouldDebugRenderDump():
      echo "[appkit] button layout runes=", layout.runes.len, " title=\"", title, "\""
    return (true, layout)

  (false, default(GlyphArrangement))

proc addViewTree(
  renders: var Renders,
  viewId: ID,
  parentIdx: FigIdx,
  hasParent: bool,
  offsetX: float32,
  offsetY: float32,
)

proc buildWindowRenders(window: NSWindow): Renders =
  let root = ensureContentView(window)
  if root.isNil:
    return nil
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.addViewTree(root.value, FigIdx(0), false, 0.0, 0.0)

proc addViewTree(
    renders: var Renders,
    viewId: ID,
    parentIdx: FigIdx,
    hasParent: bool,
    offsetX: float32,
    offsetY: float32,
) =
  if viewId.isNil:
    return
  let view = ownFromId[NSView](viewId)
  if view.isNil:
    return
  if view.viewHidden():
    return
  let frame = view.viewFrame()

  let box = nsRect(
    offsetX + frame.origin.x,
    offsetY + frame.origin.y,
    max(frame.size.width, 0.0),
    max(frame.size.height, 0.0),
  )
  if box.size.width <= 0 or box.size.height <= 0:
    return

  let fig = Fig(
    kind: nkRectangle,
    childCount: 0,
    screenBox: rect(box.origin.x, box.origin.y, box.size.width, box.size.height),
    fill: viewFill(view),
    corners: uniformCorners(viewCornerRadius(view)),
    shadows: viewShadows(view),
    stroke: RenderStroke(weight: 1.0, fill: viewStrokeFill(view)),
  )

  let idx =
    if hasParent:
      renders.addChild(0.ZLevel, parentIdx, fig)
    else:
      renders.addRoot(0.ZLevel, fig)

  addAquaGlossOverlay(renders, idx, view, box)

  let textFieldHasBackground =
    if view.isKindOfClass(NSTextField):
      textFieldDrawsBackground(view)
    else:
      false
  let textPaddingX =
    if view.isKindOfClass(NSButton):
      8.0
    elif view.isKindOfClass(NSTextField):
      (if textFieldHasBackground: 10.0 else: 0.0)
    else:
      0.0
  let textPaddingY =
    if view.isKindOfClass(NSButton):
      4.0
    elif view.isKindOfClass(NSTextField):
      (if textFieldHasBackground: 4.0 else: 0.0)
    else:
      0.0

  let textBox = nsRect(
    box.origin.x + textPaddingX,
    box.origin.y + textPaddingY,
    max(box.size.width - textPaddingX * 2, 0.0),
    max(box.size.height - textPaddingY * 2, 0.0),
  )
  let textLayout = textLayoutForView(view, textBox)
  if textLayout.ok:
    discard renders.addChild(
      0.ZLevel,
      idx,
      Fig(
        kind: nkText,
        childCount: 0,
        screenBox: rect(
          textBox.origin.x, textBox.origin.y, textBox.size.width, textBox.size.height
        ),
        fill: nsColor(0.0, 0.0, 0.0, 0.0).toFigColor(),
        textLayout: textLayout.layout,
      ),
    )

  for child in view.viewSubviews():
    renders.addViewTree(child, idx, true, box.origin.x, box.origin.y)

proc hitTestButton(
    viewId: ID, x: float32, y: float32, offsetX: float32, offsetY: float32
): ID =
  if viewId.isNil:
    return nil
  let view = ownFromId[NSView](viewId)
  if view.isNil:
    return nil
  if view.viewHidden():
    return nil
  let frameSelf = view.viewFrame()

  let frame = nsRect(
    offsetX + frameSelf.origin.x,
    offsetY + frameSelf.origin.y,
    frameSelf.size.width,
    frameSelf.size.height,
  )

  let children = view.viewSubviews()
  for i in countdown(children.high, 0):
    let child = children[i]
    let hit = hitTestButton(child, x, y, frame.origin.x, frame.origin.y)
    if not hit.isNil:
      return hit

  if view.isKindOfClass(NSButton) and frame.contains(x, y):
    return view.value
  nil

proc rawInputToLogical*(rawPos: Vec2, backingSize: IVec2, logicalSize: Vec2): Vec2 =
  ## Siwin mouse/click positions are reported in backing pixel coordinates.
  ## AppKit layout/hit-testing here is done in logical coordinates.
  if backingSize.x <= 0 or backingSize.y <= 0:
    return rawPos
  if logicalSize.x <= 0.0 or logicalSize.y <= 0.0:
    return rawPos
  vec2(
    rawPos.x * logicalSize.x / backingSize.x.float32,
    rawPos.y * logicalSize.y / backingSize.y.float32,
  )

proc logicalInputPos(window: siwinshim.Window, rawPos: Vec2): Vec2 =
  if window.isNil:
    return rawPos
  rawInputToLogical(rawPos, window.backingSize(), window.logicalSize())

proc renderWindow(window: NSWindow) =
  let nativeWindow = window.windowNativeWindow()
  let renderer = window.windowRenderer()
  if renderer.isNil or nativeWindow.isNil:
    return

  let logicalSize = nativeWindow.logicalSize()
  var frame = window.windowFrame()
  frame.size = nsSize(logicalSize.x.float32, logicalSize.y.float32)
  window.windowFrame = frame
  var renders = buildWindowRenders(window)
  if renders.isNil:
    return
  let root = ensureContentView(window)
  root.setFrame(0.cfloat, 0.cfloat, logicalSize.x.cfloat, logicalSize.y.cfloat)
  if shouldDebugRenderDump():
    dumpRenders(renders)

  renderer.beginFrame()
  renderer.renderFrame(renders, logicalSize)
  renderer.endFrame()

proc debugDumpWindowRenderTree*(window: NSWindow) =
  let renders = buildWindowRenders(window)
  if renders.isNil:
    echo "[appkit] debug dump: no render tree"
  else:
    dumpRenders(renders)

proc cleanupFailedWindowInit(window: NSWindow) =
  if not window.windowNativeWindow().isNil:
    try:
      siwinshim.close(window.windowNativeWindow())
    except Exception:
      discard
  window.windowRenderer = nil
  window.windowNativeWindow = nil
  window.windowNativeReady = false
  window.windowVisibleRequested = false
  window.windowClosed = true

proc ensureNativeWindow(window: NSWindow) =
  if window.windowNativeReady():
    return

  try:
    let frame = window.windowFrame()
    let size =
      ivec2(clampWindowSize(frame.size.width), clampWindowSize(frame.size.height))

    window.windowNativeWindow =
      siwinshim.newSiwinWindow(size = size, title = window.windowTitle(), vsync = true)
    window.windowAutoScale = window.windowNativeWindow().configureUiScale()
    window.windowRenderer = figrender.newFigRenderer(
      atlasSize = 1024, backendState = siwinshim.SiwinRenderBackend()
    )
    var renderer = window.windowRenderer()
    renderer.setupBackend(window.windowNativeWindow())
    window.windowRenderer = renderer

    window.windowNativeWindow.eventsHandler = siwinshim.WindowEventsHandler(
      onClose: proc(e: siwinshim.CloseEvent) =
        discard e
        window.windowClosed = true,
      onResize: proc(e: siwinshim.ResizeEvent) =
        var resizedFrame = window.windowFrame()
        resizedFrame.size = nsSize(e.size.x.float32, e.size.y.float32)
        window.windowFrame = resizedFrame
        let root = ensureContentView(window)
        root.setFrame(0.cfloat, 0.cfloat, e.size.x.cfloat, e.size.y.cfloat)
        window.windowNativeWindow().refreshUiScale(window.windowAutoScale())
        renderWindow(window),
      onClick: proc(e: siwinshim.ClickEvent) =
        let root = ensureContentView(window)
        let logicalPos = logicalInputPos(window.windowNativeWindow(), e.pos)
        let buttonId = hitTestButton(root.value, logicalPos.x, logicalPos.y, 0.0, 0.0)
        if not buttonId.isNil:
          let button = ownFromId[NSButton](buttonId)
          button.performClick(window)
        renderWindow(window),
      onRender: proc(e: siwinshim.RenderEvent) =
        discard e
        renderWindow(window),
      onKey: proc(e: siwinshim.KeyEvent) =
        if e.pressed and e.key == siwinshim.Key.escape:
          window.close()
      ,
    )

    window.windowNativeWindow().firstStep()
    window.windowNativeWindow().refreshUiScale(window.windowAutoScale())
    window.windowNativeReady = true
  except Exception as exc:
    cleanupFailedWindowInit(window)
    raise newException(CatchableError, "window backend init failed: " & exc.msg)

var sharedApplicationRef {.threadvar.}: NSApplication

proc sharedApplication*(t: typedesc[NSApplication]): NSApplication =
  when false:
    discard t
  if sharedApplicationRef.isNil:
    sharedApplicationRef = NSApplication.new()
  sharedApplicationRef

proc NSApp*(): NSApplication =
  NSApplication.sharedApplication()

proc addWindow*(app: NSApplication, window: NSWindow) =
  var windows = app.appWindows()
  if window.value notin windows:
    windows.add(retainId(window.value))
    app.appWindows = windows
  window.windowVisibleRequested = true

proc windows*(app: NSApplication): seq[NSWindow] =
  let appWindows = app.appWindows()
  result = newSeq[NSWindow](appWindows.len)
  for i, id in appWindows:
    result[i] = ownFromId[NSWindow](id)

proc setContentView*(window: NSWindow, view: NSView) =
  let currentContentView = window.windowContentView()
  if not currentContentView.isNil and currentContentView != view.value:
    clearSuperviewRef(currentContentView)
  if not view.isNil:
    let parentId = view.viewSuperview()
    if not parentId.isNil:
      view.removeFromSuperview()
    view.viewSuperview = nil
  window.windowContentView = replacedOwnedId(window.windowContentView(), view.value)

proc contentView*(window: NSWindow): NSView =
  let cv = window.windowContentView()
  if cv.isNil:
    return NSView(value: nil)
  ownFromId[NSView](cv)

proc makeKeyAndOrderFront*(window: NSWindow, sender: NSObject) =
  discard sender
  window.windowVisibleRequested = true

proc close*(window: NSWindow) =
  window.windowClosed = true
  if window.windowNativeReady() and not window.windowNativeWindow().isNil:
    siwinshim.close(window.windowNativeWindow())

proc run*(app: NSApplication) =
  discard runApplicationFrames(app, -1)

proc stop*(app: NSApplication) =
  app.appRunning = false

proc isRunning*(app: NSApplication): bool =
  app.appRunning()

proc runApplicationFrames(app: NSObject, maxFrames: int): int =
  let app = ownFromId[NSApplication](app.value)
  app.appRunning = true
  var windows = app.appWindows()
  while app.appRunning():
    var activeWindows = 0
    var i = 0
    while i < windows.len:
      let window = ownFromId[NSWindow](windows[i])
      if window.isNil:
        removeOwnedIdAt(windows, i)
        continue

      if window.windowClosed():
        removeOwnedIdAt(windows, i)
        continue

      try:
        ensureNativeWindow(window)
      except CatchableError:
        removeOwnedIdAt(windows, i)
        app.appWindows = windows
        raise

      if not window.windowVisibleRequested():
        inc i
        continue

      let nativeWindow = window.windowNativeWindow()
      if not nativeWindow.isNil and nativeWindow.opened:
        nativeWindow.redraw()
        nativeWindow.step()
      if (not nativeWindow.isNil) and nativeWindow.closed:
        window.windowClosed = true
        removeOwnedIdAt(windows, i)
        continue

      inc activeWindows
      inc i

    app.appWindows = windows
    inc result
    if maxFrames >= 0 and result >= maxFrames:
      break
    if activeWindows == 0:
      break
    sleep(8)
    windows = app.appWindows()

  app.appRunning = false
  app.appWindows = windows

proc runForFrames*(app: NSApplication, maxFrames: int): int =
  runApplicationFrames(app, maxFrames)

proc newWindow*(x, y, width, height: float32, title = "Nutella Window"): NSWindow =
  var wAlloc = NSWindow.alloc()
  result = wAlloc.initWithContentRect(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  wAlloc.value = nil
  result.setTitle(title)

proc newView*(x, y, width, height: float32): NSView =
  var vAlloc = NSView.alloc()
  result = vAlloc.initWithFrame(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  vAlloc.value = nil

proc newTextField*(x, y, width, height: float32, value = ""): NSTextField =
  result = NSTextField.new()
  result.setFrame(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  result.setStringValue(value)

proc newButton*(x, y, width, height: float32, title = "Button"): NSButton =
  result = NSButton.new()
  result.setFrame(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  result.buttonTitle = title
