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

type
  NSButtonCallbackProc = proc(sender: ID)

  NSViewStateRef = ref object
    frame: NSRect
    backgroundColor: NSColor
    hidden: bool
    superview: ID
    tag: int
    subviews: seq[ID]

  NSControlStateRef = ref object
    enabled: bool
    alignment: NSTextAlignment

  NSTextFieldStateRef = ref object
    stringValue: string
    textColor: NSColor
    backgroundColor: NSColor
    drawsBackground: bool

  NSButtonStateRef = ref object
    title: string
    state: int
    allowsMixedState: bool
    onClick: NSButtonCallbackProc

  NSWindowStateRef = ref object
    frame: NSRect
    title: string
    contentView: ID
    nativeWindow: siwinshim.Window
    renderer: figrender.FigRenderer[siwinshim.SiwinRenderBackend]
    autoScale: bool
    nativeReady: bool
    visibleRequested: bool
    closed: bool

  NSApplicationStateRef = ref object
    windows: seq[ID]
    running: bool

proc defaultViewState(): NSViewStateRef =
  NSViewStateRef(
    frame: nsRect(0, 0, 100, 100),
    backgroundColor: nsColor(0.86, 0.90, 0.96, 1.0),
    hidden: false,
    superview: nil,
    tag: 0,
    subviews: @[],
  )

proc defaultControlState(): NSControlStateRef =
  NSControlStateRef(enabled: true, alignment: NSNaturalTextAlignment)

proc defaultTextFieldState(): NSTextFieldStateRef =
  NSTextFieldStateRef(
    stringValue: "",
    textColor: nsColor(0.08, 0.08, 0.08, 1.0),
    backgroundColor: nsColor(0.98, 0.99, 1.0, 1.0),
    drawsBackground: true,
  )

proc defaultButtonState(): NSButtonStateRef =
  NSButtonStateRef(
    title: "Button", state: NSOffState, allowsMixedState: false, onClick: nil
  )

proc defaultWindowState(): NSWindowStateRef =
  NSWindowStateRef(
    frame: nsRect(100, 100, 640, 420),
    title: "Nutella Window",
    contentView: nil,
    nativeWindow: nil,
    renderer: nil,
    autoScale: true,
    nativeReady: false,
    visibleRequested: false,
    closed: false,
  )

proc defaultApplicationState(): NSApplicationStateRef =
  NSApplicationStateRef(windows: @[], running: false)

proc toFigColor(c: NSColor): Color {.inline.} =
  color(c.r, c.g, c.b, c.a)

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

proc replaceOwnedId(slot: var ID, next: ID) =
  if slot == next:
    return
  let old = slot
  slot = retainId(next)
  releaseId(old)

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
proc detachSubviews(st: NSViewStateRef)

proc runApplicationFrames(app: NSObject, maxFrames: int): int

objcImpl:
  type NXResponder = object of NSObject

objcImpl:
  type NXView = object of NXResponder
    viewStateRef: NSViewStateRef

  method init*(self: var NXView): NXView =
    result = asType[NXView](callSuperIdFrom(NXView, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.viewStateRef = defaultViewState()

  method initWithFrame*(self: var NXView, x, y, width, height: cfloat): NXView =
    result = self.init()
    if result.isNil:
      return
    let st = result.viewStateRef()
    st.frame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))

  method setFrame*(self: NXView, x, y, width, height: cfloat) =
    let st = self.viewStateRef()
    st.frame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))

  method setBackgroundColor*(self: NXView, r, g, b, a: cfloat) =
    let st = self.viewStateRef()
    st.backgroundColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setHidden*(self: NXView, hidden: bool) =
    let st = self.viewStateRef()
    st.hidden = hidden

  method dealloc(self: NXView) {.used.} =
    let st = self.viewStateRef()
    detachSubviews(st)
    clearIvarRefs(self)
    discard callSuperIdFrom(NXView, self, getSelector("dealloc"))

objcImpl:
  type NXControl = object of NXView
    controlStateRef: NSControlStateRef

  method init*(self: var NXControl): NXControl =
    result = asType[NXControl](callSuperIdFrom(NXControl, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.viewStateRef = defaultViewState()
    result.controlStateRef = defaultControlState()

  method setEnabled*(self: NXControl, enabled: bool) =
    let st = self.controlStateRef()
    st.enabled = enabled

  method setAlignment*(self: NXControl, alignment: cint) =
    let st = self.controlStateRef()
    case alignment.int
    of NSLeftTextAlignment.int:
      st.alignment = NSLeftTextAlignment
    of NSRightTextAlignment.int:
      st.alignment = NSRightTextAlignment
    of NSCenterTextAlignment.int:
      st.alignment = NSCenterTextAlignment
    of NSJustifiedTextAlignment.int:
      st.alignment = NSJustifiedTextAlignment
    else:
      st.alignment = NSNaturalTextAlignment

objcImpl:
  type NXTextField = object of NXControl
    textFieldStateRef: NSTextFieldStateRef

  method init*(self: var NXTextField): NXTextField =
    result =
      asType[NXTextField](callSuperIdFrom(NXTextField, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.viewStateRef = defaultViewState()
    result.controlStateRef = defaultControlState()
    result.textFieldStateRef = defaultTextFieldState()

  method setStringValue(self: NXTextField, value: string) =
    let st = self.textFieldStateRef()
    st.stringValue = value

  method setTextColor*(self: NXTextField, r, g, b, a: cfloat) =
    let st = self.textFieldStateRef()
    st.textColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setBackgroundColor*(self: NXTextField, r, g, b, a: cfloat) =
    let st = self.textFieldStateRef()
    st.backgroundColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setDrawsBackground*(self: NXTextField, value: bool) =
    let st = self.textFieldStateRef()
    st.drawsBackground = value

objcImpl:
  type NXButton = object of NXControl
    buttonStateRef: NSButtonStateRef

  method init*(self: var NXButton): NXButton =
    result = asType[NXButton](callSuperIdFrom(NXButton, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.viewStateRef = defaultViewState()
    result.controlStateRef = defaultControlState()
    result.buttonStateRef = defaultButtonState()

  method setTitle*(self: NXButton, value: string) =
    let st = self.buttonStateRef()
    st.title = value

  method setState*(self: NXButton, value: cint) =
    let st = self.buttonStateRef()
    st.state = normalizeButtonState(value.int, st.allowsMixedState)

  method setAllowsMixedState*(self: NXButton, value: bool) =
    let st = self.buttonStateRef()
    st.allowsMixedState = value
    st.state = normalizeButtonState(st.state, st.allowsMixedState)

  method setNextState*(self: NXButton) =
    let st = self.buttonStateRef()
    if st.allowsMixedState:
      case st.state
      of NSOffState:
        st.state = NSOnState
      of NSOnState:
        st.state = NSMixedState
      else:
        st.state = NSOffState
    else:
      if st.state == NSOnState:
        st.state = NSOffState
      else:
        st.state = NSOnState

  method performClick*(self: NXButton, sender: NSObject) =
    discard sender
    let st = self.buttonStateRef()
    let cst = self.controlStateRef()
    if not cst.enabled:
      return
    self.setNextState()
    if st.onClick.isNil:
      return
    st.onClick(self.value)

objcImpl:
  type NXWindow = object of NXResponder
    windowStateRef: NSWindowStateRef

  method init*(self: var NXWindow): NXWindow =
    result = asType[NXWindow](callSuperIdFrom(NXWindow, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.windowStateRef = defaultWindowState()

  method initWithContentRect*(
      self: var NXWindow, x, y, width, height: cfloat
  ): NXWindow =
    result = self.init()
    if result.isNil:
      return
    let st = result.windowStateRef()
    st.frame =
      nsRect(x.float32, y.float32, max(width.float32, 1.0), max(height.float32, 1.0))

  method setContentView*(self: NXWindow, view: NXView) =
    if self.isNil:
      return
    let st = self.windowStateRef()
    if not st.contentView.isNil and st.contentView != view.value:
      clearSuperviewRef(st.contentView)
    if not view.isNil:
      let vst = view.viewStateRef()
      if not vst.superview.isNil:
        var parent = ownFromId[NXView](vst.superview)
        if not parent.isNil:
          let pst = parent.viewStateRef()
          for i, candidate in pst.subviews:
            if candidate == view.value:
              pst.subviews.del(i)
              releaseId(view.value)
              break
      vst.superview = nil
    replaceOwnedId(st.contentView, view.value)

  method contentView*(self: NXWindow): NXView =
    let st = self.windowStateRef()
    if st.contentView.isNil:
      return NXView(value: nil)
    result = ownFromId[NXView](st.contentView)

  method setTitle*(self: NXWindow, value: string) =
    let st = self.windowStateRef()
    st.title = value
    if st.nativeReady and not st.nativeWindow.isNil:
      st.nativeWindow.title = value

  method setContentSize*(self: NXWindow, width, height: cfloat) =
    let st = self.windowStateRef()
    st.frame.size = nsSize(max(width.float32, 1.0), max(height.float32, 1.0))
    if st.nativeReady and not st.nativeWindow.isNil:
      st.nativeWindow.size = ivec2(
        clampWindowSize(st.frame.size.width), clampWindowSize(st.frame.size.height)
      )

  method setFrameOrigin*(self: NXWindow, x, y: cfloat) =
    let st = self.windowStateRef()
    st.frame.origin = nsPoint(x.float32, y.float32)

  method makeKeyAndOrderFront*(self: NXWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    let st = self.windowStateRef()
    st.visibleRequested = true

  method close*(self: NXWindow) =
    let st = self.windowStateRef()
    st.closed = true
    if st.nativeReady and not st.nativeWindow.isNil:
      siwinshim.close(st.nativeWindow)

  method dealloc(self: NXWindow) {.used.} =
    let st = self.windowStateRef()
    if st.nativeReady and (not st.nativeWindow.isNil):
      siwinshim.close(st.nativeWindow)
    replaceOwnedId(st.contentView, nil)
    clearIvarRefs(self)
    discard callSuperIdFrom(NXWindow, self, getSelector("dealloc"))

objcImpl:
  type NXApplication = object of NXResponder
    appStateRef: NSApplicationStateRef

  method init*(self: var NXApplication): NXApplication =
    result =
      asType[NXApplication](callSuperIdFrom(NXApplication, self, getSelector("init")))
    self.value = nil
    if result.isNil:
      return
    result.appStateRef = defaultApplicationState()

  method addWindow*(self: NXApplication, window: NXWindow) =
    if self.isNil or window.isNil:
      return
    let st = self.appStateRef()
    if window.value notin st.windows:
      st.windows.add(retainId(window.value))
    let wst = window.windowStateRef()
    wst.visibleRequested = true

  method run*(self: NXApplication) =
    discard runApplicationFrames(self, -1)

  method stop*(self: NXApplication) =
    let st = self.appStateRef()
    st.running = false

  method dealloc(self: NXApplication) {.used.} =
    let st = self.appStateRef()
    clearOwnedIds(st.windows)
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
  result.viewStateRef = defaultViewState()

proc new*(t: typedesc[NSControl]): NSControl =
  when false:
    discard t
  var allocated = NSControl.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return
  result.viewStateRef = defaultViewState()
  result.controlStateRef = defaultControlState()

proc new*(t: typedesc[NSTextField]): NSTextField =
  when false:
    discard t
  var allocated = NSTextField.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return
  result.viewStateRef = defaultViewState()
  result.controlStateRef = defaultControlState()
  result.textFieldStateRef = defaultTextFieldState()

proc new*(t: typedesc[NSButton]): NSButton =
  when false:
    discard t
  var allocated = NSButton.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return
  result.viewStateRef = defaultViewState()
  result.controlStateRef = defaultControlState()
  result.buttonStateRef = defaultButtonState()

proc new*(t: typedesc[NSWindow]): NSWindow =
  when false:
    discard t
  var allocated = NSWindow.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return
  result.windowStateRef = defaultWindowState()

proc new*(t: typedesc[NSApplication]): NSApplication =
  when false:
    discard t
  var allocated = NSApplication.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return
  result.appStateRef = defaultApplicationState()

proc clearSuperviewRef(viewId: ID) =
  if viewId.isNil:
    return
  let child = ownFromId[NSView](viewId)
  if child.isNil:
    return
  let st = child.viewStateRef()
  st.superview = nil

proc detachSubviews(st: NSViewStateRef) =
  for child in st.subviews:
    clearSuperviewRef(child)
    releaseId(child)
  st.subviews.setLen(0)

proc viewState*(view: NSView): NSViewStateRef =
  view.viewStateRef()

proc controlState*(control: NSControl): NSControlStateRef =
  control.controlStateRef()

proc textFieldState*(field: NSTextField): NSTextFieldStateRef =
  field.textFieldStateRef()

proc buttonState*(button: NSButton): NSButtonStateRef =
  button.buttonStateRef()

proc windowState*(window: NSWindow): NSWindowStateRef =
  window.windowStateRef()

proc applicationState*(app: NSApplication): NSApplicationStateRef =
  app.appStateRef()

proc frame*(view: NSView): NSRect =
  view.viewState().frame

proc frame*(window: NSWindow): NSRect =
  window.windowState().frame

proc frameOrigin*(view: NSView): NSPoint =
  view.frame().origin

proc frameOrigin*(window: NSWindow): NSPoint =
  window.frame().origin

proc frameSize*(view: NSView): NSSize =
  view.frame().size

proc frameSize*(window: NSWindow): NSSize =
  window.frame().size

proc title*(window: NSWindow): string =
  window.windowState().title

proc isHidden*(view: NSView): bool =
  view.viewState().hidden

proc tag*(view: NSView): int =
  view.viewState().tag

proc setTag*(view: NSView, value: int) =
  view.viewState().tag = value

proc setBackgroundColor*(view: NSView, r, g, b: float32, a: float32 = 1.0'f32) =
  let st = view.viewState()
  st.backgroundColor = nsColor(r, g, b, a)

proc setHidden*(view: NSView, hidden: bool) =
  view.viewState().hidden = hidden

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
  let st = window.windowState()
  st.frame = nsRect(
    frame.origin.x,
    frame.origin.y,
    max(frame.size.width, 1.0),
    max(frame.size.height, 1.0),
  )
  if st.nativeReady and not st.nativeWindow.isNil:
    st.nativeWindow.size =
      ivec2(clampWindowSize(st.frame.size.width), clampWindowSize(st.frame.size.height))

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
  let st = view.viewState()
  result = newSeq[NSView](st.subviews.len)
  for i, child in st.subviews:
    result[i] = ownFromId[NSView](child)

proc superview*(view: NSView): NSView =
  let st = view.viewState()
  if st.superview.isNil:
    return NSView(value: nil)
  ownFromId[NSView](st.superview)

proc removeSubviewById(parent: NSView, childId: ID): bool =
  if parent.isNil or childId.isNil:
    return false
  let st = parent.viewState()
  for i, candidate in st.subviews:
    if candidate == childId:
      clearSuperviewRef(childId)
      st.subviews.del(i)
      releaseId(childId)
      return true
  false

proc removeFromSuperview*(view: NSView) =
  if view.isNil:
    return
  let st = view.viewState()
  if st.superview.isNil:
    return
  let parentId = st.superview
  st.superview = nil
  let parent = ownFromId[NSView](parentId)
  if parent.isNil:
    return
  discard removeSubviewById(parent, view.value)

proc addSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil or self.value == view.value:
    return
  let vst = view.viewState()
  if vst.superview == self.value:
    let st = self.viewState()
    if view.value notin st.subviews:
      st.subviews.add(retainId(view.value))
    return
  if not vst.superview.isNil:
    view.removeFromSuperview()
  let st = self.viewState()
  if view.value notin st.subviews:
    st.subviews.add(retainId(view.value))
  vst.superview = self.value

proc removeSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil:
    return
  discard removeSubviewById(self, view.value)

proc viewWithTag*(view: NSView, wantedTag: int): NSView =
  if view.isNil:
    return NSView(value: nil)
  let st = view.viewState()
  if st.tag == wantedTag:
    return retain(view)
  for childId in st.subviews:
    let child = ownFromId[NSView](childId)
    if child.isNil:
      continue
    let hit = child.viewWithTag(wantedTag)
    if not hit.isNil:
      return hit
  NSView(value: nil)

proc stringValue*(field: NSTextField): string =
  field.textFieldState().stringValue

proc setStringValue*(field: NSTextField, value: string) =
  field.textFieldState().stringValue = value

proc textColor*(field: NSTextField): NSColor =
  field.textFieldState().textColor

proc setTextColor*(field: NSTextField, color: NSColor) =
  field.textFieldState().textColor = color

proc setTextColor*(field: NSTextField, r, g, b: float32, a: float32 = 1.0'f32) =
  field.setTextColor(nsColor(r, g, b, a))

proc backgroundColor*(field: NSTextField): NSColor =
  field.textFieldState().backgroundColor

proc setBackgroundColor*(field: NSTextField, color: NSColor) =
  field.textFieldState().backgroundColor = color

proc setBackgroundColor*(field: NSTextField, r, g, b: float32, a: float32 = 1.0'f32) =
  field.setBackgroundColor(nsColor(r, g, b, a))

proc drawsBackground*(field: NSTextField): bool =
  field.textFieldState().drawsBackground

proc setDrawsBackground*(field: NSTextField, value: bool) =
  field.textFieldState().drawsBackground = value

proc setEnabled*(control: NSControl, enabled: bool) =
  control.controlState().enabled = enabled

proc isEnabled*(control: NSControl): bool =
  control.controlState().enabled

proc alignment*(control: NSControl): NSTextAlignment =
  control.controlState().alignment

proc setAlignment*(control: NSControl, alignment: NSTextAlignment) =
  control.controlState().alignment = alignment

proc title*(button: NSButton): string =
  button.buttonState().title

proc setTitle*(button: NSButton, value: string) =
  button.buttonState().title = value

proc state*(button: NSButton): int =
  button.buttonState().state

proc setState*(button: NSButton, value: int) =
  let st = button.buttonState()
  st.state = normalizeButtonState(value, st.allowsMixedState)

proc allowsMixedState*(button: NSButton): bool =
  button.buttonState().allowsMixedState

proc setAllowsMixedState*(button: NSButton, value: bool) =
  let st = button.buttonState()
  st.allowsMixedState = value
  st.state = normalizeButtonState(st.state, value)

proc setNextState*(button: NSButton) =
  let st = button.buttonState()
  if st.allowsMixedState:
    case st.state
    of NSOffState:
      st.state = NSOnState
    of NSOnState:
      st.state = NSMixedState
    else:
      st.state = NSOffState
  else:
    if st.state == NSOnState:
      st.state = NSOffState
    else:
      st.state = NSOnState

proc setOnClick*(button: NSButton, cb: proc(sender: NSButton)) =
  let st = button.buttonState()
  if cb.isNil:
    st.onClick = nil
  else:
    st.onClick = proc(sender: ID) =
      cb(ownFromId[NSButton](sender))

proc click*(button: NSButton) =
  let st = button.buttonState()
  if not button.controlState().enabled:
    return
  if st.allowsMixedState:
    case st.state
    of NSOffState:
      st.state = NSOnState
    of NSOnState:
      st.state = NSMixedState
    else:
      st.state = NSOffState
  else:
    if st.state == NSOnState:
      st.state = NSOffState
    else:
      st.state = NSOnState
  if not st.onClick.isNil:
    st.onClick(button.value)

proc ensureContentView(window: NSWindow, st: NSWindowStateRef): NSView =
  if not st.contentView.isNil:
    return ownFromId[NSView](st.contentView)

  var rootAlloc = NSView.alloc()
  var root = rootAlloc.initWithFrame(
    0.cfloat, 0.cfloat, st.frame.size.width.cfloat, st.frame.size.height.cfloat
  )
  rootAlloc.value = nil
  replaceOwnedId(st.contentView, root.value)
  result = root

proc noRenderShadows(): array[ShadowCount, RenderShadow] =
  for i in result.low .. result.high:
    result[i] = RenderShadow(
      style: NoShadow,
      blur: 0.0,
      spread: 0.0,
      x: 0.0,
      y: 0.0,
      color: nsColor(0.0, 0.0, 0.0, 0.0).toFigColor(),
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

proc viewShadows(view: NSView): array[ShadowCount, RenderShadow] =
  result = noRenderShadows()
  if view.isKindOfClass(NSButton):
    let state = buttonVisualState(view)
    let dropAlpha =
      if state == NSOnState:
        0.38
      elif state == NSMixedState:
        0.18
      else:
        0.30
    result[0] = RenderShadow(
      style: DropShadow,
      blur: 4.0,
      spread: 0.0,
      x: 0.0,
      y: 1.0,
      color: nsColor(0.10, 0.18, 0.35, dropAlpha).toFigColor(),
    )
    result[1] = RenderShadow(
      style: InnerShadow,
      blur: 1.4,
      spread: 0.0,
      x: 0.0,
      y: 1.0,
      color: nsColor(1.0, 1.0, 1.0, 0.32).toFigColor(),
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
      color: nsColor(1.0, 1.0, 1.0, 0.45).toFigColor(),
    )
    result[1] = RenderShadow(
      style: DropShadow,
      blur: 1.0,
      spread: 0.0,
      x: 0.0,
      y: 1.0,
      color: nsColor(0.34, 0.40, 0.52, 0.20).toFigColor(),
    )

proc viewFillColor(view: NSView, st: NSViewStateRef): Color =
  if view.isKindOfClass(NSButton):
    case buttonVisualState(view)
    of NSOnState:
      return nsColor(0.20, 0.45, 0.82, 1.0).toFigColor()
    of NSMixedState:
      return nsColor(0.58, 0.62, 0.70, 1.0).toFigColor()
    else:
      return nsColor(0.30, 0.56, 0.93, 1.0).toFigColor()
  if view.isKindOfClass(NSTextField):
    var textField = asType[NSTextField](view.value)
    let tstate = textField.textFieldState()
    textField.value = nil
    if tstate.drawsBackground:
      return tstate.backgroundColor.toFigColor()
    return nsColor(0.0, 0.0, 0.0, 0.0).toFigColor()
  st.backgroundColor.toFigColor()

proc viewStrokeColor(view: NSView): Color =
  if view.isKindOfClass(NSButton):
    case buttonVisualState(view)
    of NSOnState:
      return nsColor(0.11, 0.25, 0.56, 1.0).toFigColor()
    of NSMixedState:
      return nsColor(0.44, 0.48, 0.56, 1.0).toFigColor()
    else:
      return nsColor(0.13, 0.29, 0.62, 1.0).toFigColor()
  if view.isKindOfClass(NSTextField):
    if not textFieldDrawsBackground(view):
      return nsColor(0.0, 0.0, 0.0, 0.0).toFigColor()
    return nsColor(0.64, 0.70, 0.80, 1.0).toFigColor()
  nsColor(0.34, 0.42, 0.56, 0.28).toFigColor()

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

  var glossAlpha = 0.0
  var glossHeight = 0.0
  if view.isKindOfClass(NSButton):
    glossAlpha = 0.36
    glossHeight = box.size.height * 0.56
  elif view.isKindOfClass(NSTextField):
    if not textFieldDrawsBackground(view):
      return
    glossAlpha = 0.24
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
      fill: nsColor(1.0, 1.0, 1.0, glossAlpha).toFigColor(),
      corners: [radius, radius, max(radius - 5.0, 0.0), max(radius - 5.0, 0.0)],
      stroke: RenderStroke(weight: 0.0, color: nsColor(0.0, 0.0, 0.0, 0.0).toFigColor()),
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
    let tstate = textField.textFieldState()
    let textAlign = toFontHorizontal(textField.alignment())
    textField.value = nil
    if tstate.stringValue.len == 0:
      return (false, default(GlyphArrangement))
    let spans =
      [(fs(appkitFont(18.0), tstate.textColor.toFigColor()), tstate.stringValue)]
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
        layout.runes.len, " text=\"", tstate.stringValue, "\""
    return (true, layout)

  if view.isKindOfClass(NSButton):
    var button = asType[NSButton](view.value)
    let bstate = button.buttonState()
    let textAlign = toFontHorizontal(button.alignment())
    button.value = nil
    if bstate.title.len == 0:
      return (false, default(GlyphArrangement))
    let spans =
      [(fs(appkitFont(16.0), nsColor(0.98, 0.99, 1.0, 1.0).toFigColor()), bstate.title)]
    let layout = typeset(
      rect(0, 0, box.size.width, box.size.height),
      spans,
      hAlign = textAlign,
      vAlign = FontVertical.Middle,
      minContent = false,
      wrap = false,
    )
    if shouldDebugRenderDump():
      echo "[appkit] button layout runes=",
        layout.runes.len, " title=\"", bstate.title, "\""
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

proc buildWindowRenders(window: NSWindow, st: NSWindowStateRef): Renders =
  let root = ensureContentView(window, st)
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
  let st = view.viewState()
  if st.hidden:
    return

  let box = nsRect(
    offsetX + st.frame.origin.x,
    offsetY + st.frame.origin.y,
    max(st.frame.size.width, 0.0),
    max(st.frame.size.height, 0.0),
  )
  if box.size.width <= 0 or box.size.height <= 0:
    return

  let fig = Fig(
    kind: nkRectangle,
    childCount: 0,
    screenBox: rect(box.origin.x, box.origin.y, box.size.width, box.size.height),
    fill: viewFillColor(view, st),
    corners: uniformCorners(viewCornerRadius(view)),
    shadows: viewShadows(view),
    stroke: RenderStroke(weight: 1.0, color: viewStrokeColor(view)),
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

  for child in st.subviews:
    renders.addViewTree(child, idx, true, box.origin.x, box.origin.y)

proc hitTestButton(
    viewId: ID, x: float32, y: float32, offsetX: float32, offsetY: float32
): ID =
  if viewId.isNil:
    return nil
  let view = ownFromId[NSView](viewId)
  if view.isNil:
    return nil
  let st = view.viewState()
  if st.hidden:
    return nil

  let frame = nsRect(
    offsetX + st.frame.origin.x,
    offsetY + st.frame.origin.y,
    st.frame.size.width,
    st.frame.size.height,
  )

  for i in countdown(st.subviews.high, 0):
    let child = st.subviews[i]
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

proc renderWindow(window: NSWindow, st: NSWindowStateRef) =
  if st.renderer.isNil or st.nativeWindow.isNil:
    return

  let logicalSize = st.nativeWindow.logicalSize()
  st.frame.size = nsSize(logicalSize.x.float32, logicalSize.y.float32)
  var renders = buildWindowRenders(window, st)
  if renders.isNil:
    return
  let root = ensureContentView(window, st)
  root.setFrame(0.cfloat, 0.cfloat, logicalSize.x.cfloat, logicalSize.y.cfloat)
  if shouldDebugRenderDump():
    dumpRenders(renders)

  st.renderer.beginFrame()
  st.renderer.renderFrame(renders, logicalSize)
  st.renderer.endFrame()

proc debugDumpWindowRenderTree*(window: NSWindow) =
  let st = window.windowState()
  let renders = buildWindowRenders(window, st)
  if renders.isNil:
    echo "[appkit] debug dump: no render tree"
  else:
    dumpRenders(renders)

proc cleanupFailedWindowInit(st: NSWindowStateRef) =
  if not st.nativeWindow.isNil:
    try:
      siwinshim.close(st.nativeWindow)
    except Exception:
      discard
  st.renderer = nil
  st.nativeWindow = nil
  st.nativeReady = false
  st.visibleRequested = false
  st.closed = true

proc ensureNativeWindow(window: NSWindow, st: NSWindowStateRef) =
  if st.nativeReady:
    return

  try:
    let size =
      ivec2(clampWindowSize(st.frame.size.width), clampWindowSize(st.frame.size.height))

    st.nativeWindow =
      siwinshim.newSiwinWindow(size = size, title = st.title, vsync = true)
    st.autoScale = st.nativeWindow.configureUiScale()
    st.renderer = figrender.newFigRenderer(
      atlasSize = 1024, backendState = siwinshim.SiwinRenderBackend()
    )
    st.renderer.setupBackend(st.nativeWindow)

    st.nativeWindow.eventsHandler = siwinshim.WindowEventsHandler(
      onClose: proc(e: siwinshim.CloseEvent) =
        discard e
        st.closed = true,
      onResize: proc(e: siwinshim.ResizeEvent) =
        st.frame.size = nsSize(e.size.x.float32, e.size.y.float32)
        let root = ensureContentView(window, st)
        root.setFrame(0.cfloat, 0.cfloat, e.size.x.cfloat, e.size.y.cfloat)
        st.nativeWindow.refreshUiScale(st.autoScale)
        renderWindow(window, st),
      onClick: proc(e: siwinshim.ClickEvent) =
        let root = ensureContentView(window, st)
        let logicalPos = logicalInputPos(st.nativeWindow, e.pos)
        let buttonId = hitTestButton(root.value, logicalPos.x, logicalPos.y, 0.0, 0.0)
        if not buttonId.isNil:
          let button = ownFromId[NSButton](buttonId)
          button.performClick(window)
        renderWindow(window, st),
      onRender: proc(e: siwinshim.RenderEvent) =
        discard e
        renderWindow(window, st),
      onKey: proc(e: siwinshim.KeyEvent) =
        if e.pressed and e.key == siwinshim.Key.escape:
          window.close()
      ,
    )

    st.nativeWindow.firstStep()
    st.nativeWindow.refreshUiScale(st.autoScale)
    st.nativeReady = true
  except Exception as exc:
    cleanupFailedWindowInit(st)
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
  let st = app.applicationState()
  if window.value notin st.windows:
    st.windows.add(retainId(window.value))
  window.windowState().visibleRequested = true

proc windows*(app: NSApplication): seq[NSWindow] =
  let st = app.applicationState()
  result = newSeq[NSWindow](st.windows.len)
  for i, id in st.windows:
    result[i] = ownFromId[NSWindow](id)

proc setContentView*(window: NSWindow, view: NSView) =
  let st = window.windowState()
  if not st.contentView.isNil and st.contentView != view.value:
    clearSuperviewRef(st.contentView)
  if not view.isNil:
    let vst = view.viewState()
    if not vst.superview.isNil:
      view.removeFromSuperview()
    vst.superview = nil
  replaceOwnedId(st.contentView, view.value)

proc contentView*(window: NSWindow): NSView =
  let cv = window.windowState().contentView
  if cv.isNil:
    return NSView(value: nil)
  ownFromId[NSView](cv)

proc makeKeyAndOrderFront*(window: NSWindow, sender: NSObject) =
  discard sender
  window.windowState().visibleRequested = true

proc close*(window: NSWindow) =
  let st = window.windowState()
  st.closed = true
  if st.nativeReady and not st.nativeWindow.isNil:
    siwinshim.close(st.nativeWindow)

proc run*(app: NSApplication) =
  discard runApplicationFrames(app, -1)

proc stop*(app: NSApplication) =
  app.applicationState().running = false

proc isRunning*(app: NSApplication): bool =
  app.applicationState().running

proc runApplicationFrames(app: NSObject, maxFrames: int): int =
  let app = ownFromId[NSApplication](app.value)
  let st = app.applicationState()
  st.running = true

  while st.running:
    var activeWindows = 0
    var i = 0
    while i < st.windows.len:
      let window = ownFromId[NSWindow](st.windows[i])
      if window.isNil:
        removeOwnedIdAt(st.windows, i)
        continue

      let wst = window.windowState()
      if wst.closed:
        removeOwnedIdAt(st.windows, i)
        continue

      try:
        ensureNativeWindow(window, wst)
      except CatchableError:
        removeOwnedIdAt(st.windows, i)
        raise

      if not wst.visibleRequested:
        inc i
        continue

      if not wst.nativeWindow.isNil and wst.nativeWindow.opened:
        wst.nativeWindow.redraw()
        wst.nativeWindow.step()
      if (not wst.nativeWindow.isNil) and wst.nativeWindow.closed:
        wst.closed = true
        removeOwnedIdAt(st.windows, i)
        continue

      inc activeWindows
      inc i

    inc result
    if maxFrames >= 0 and result >= maxFrames:
      break
    if activeWindows == 0:
      break
    sleep(8)

  st.running = false

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
  result.textFieldState().stringValue = value

proc newButton*(x, y, width, height: float32, title = "Button"): NSButton =
  result = NSButton.new()
  result.setFrame(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  result.buttonState().title = title
