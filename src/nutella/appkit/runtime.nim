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

proc stripMnemonicMarkers(value: NSString): NSString =
  let src = $value
  var i = 0
  var dst = newStringOfCap(src.len)
  while i < src.len:
    if src[i] != '&':
      dst.add(src[i])
      inc i
      continue
    if i + 1 >= src.len:
      inc i
      continue
    if src[i + 1] == '&':
      dst.add('&')
      i += 2
      continue
    dst.add(src[i + 1])
    i += 2
  result = nsString(dst)

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

proc isViewDescendantOf(viewId: ID, ancestorId: ID): bool

proc performResponderSelector(target: NSObject, action: SEL, sender: NSObject): bool =
  if target.isNil or cast[pointer](action).isNil:
    return false
  let cls = getClass(target.value)
  if cls.isNil or not cls.respondsToSelector(action):
    return false
  let meth = cls.getInstanceMethod(action)
  if cast[pointer](meth) == nil:
    return false
  case meth.getNumberOfArguments()
  of 2:
    discard cast[proc(self: ID, op: SEL): ID {.cdecl, varargs.}](objc_msgSend)(
      target.value, action
    )
    true
  of 3:
    discard cast[proc(self: ID, op: SEL, value: ID): ID {.cdecl, varargs.}](objc_msgSend)(
      target.value, action, sender.value
    )
    true
  else:
    false

objcImpl:
  type NXResponder* = object of NSObject
    nextResp: ID

  method init*(self: var NXResponder): NXResponder =
    result =
      asType[NXResponder](callSuperIdFrom(NXResponder, self, getSelector("init")))
    if result.isNil:
      return
    result.nextResp = nil

  method nextResponder*(self: NXResponder): NXResponder =
    if self.nextResp.isNil:
      return NXResponder(value: nil)
    ownFromId[NXResponder](self.nextResp)

  method setNextResponder*(self: NXResponder, next: NXResponder) =
    if self.isNil:
      return
    self.nextResp = replacedOwnedId(self.nextResp, next.value)

  method acceptsFirstResponder*(self: NXResponder): bool =
    discard self
    false

  method becomeFirstResponder*(self: NXResponder): bool =
    discard self
    true

  method resignFirstResponder*(self: NXResponder): bool =
    discard self
    true

  method tryToPerform*(self: NXResponder, action: SEL, sender: NSObject): bool =
    if self.isNil:
      return false
    var current = self
    var hopCount = 0
    while not current.isNil and hopCount < 4096:
      if performResponderSelector(current, action, sender):
        return true
      current = current.nextResponder()
      inc hopCount
    false

  method doCommandBySelector*(self: NXResponder, action: SEL) =
    let next = self.nextResponder()
    if not next.isNil and next.tryToPerform(action, self):
      return
    self.noResponderFor(action)

  method noResponderFor*(self: NXResponder, action: SEL) =
    discard self
    discard action

  method dealloc(self: NXResponder) {.used.} =
    self.nextResp = replacedOwnedId(self.nextResp, nil)
    clearIvarRefs(self)
    discard callSuperIdFrom(NXResponder, self, getSelector("dealloc"))

objcImpl:
  type NXView* = object of NXResponder
    viewFrame: NSRect
    viewBackgroundColor: NSColor
    viewHidden: bool
    postsFrameChanged {.
      set: setPostsFrameChangedNotifications, get: postsFrameChangedNotifications
    .}: bool
    postsBoundsChanged {.
      set: setPostsBoundsChangedNotifications, get: postsBoundsChangedNotifications
    .}: bool
    autoResizeSubs {.set: setAutoresizesSubviews, get: autoresizesSubviews.}: bool
    autoResizeMask {.set: setAutoresizingMask, get: autoresizingMask.}: int
    alpha {.set: setAlphaValue, get: alphaValue.}: cfloat
    viewSuperview: ID
    viewTag: int
    viewSubviews: seq[ID]

  method init*(self: var NXView): NXView =
    result = asType[NXView](callSuperIdFrom(NXView, self, getSelector("init")))
    if result.isNil:
      return
    result.viewFrame = nsRect(0, 0, 100, 100)
    result.viewBackgroundColor = nsColor(0.86, 0.90, 0.96, 1.0)
    result.viewHidden = false
    result.postsFrameChanged = false
    result.postsBoundsChanged = false
    result.autoResizeSubs = true
    result.autoResizeMask = 0
    result.alpha = 1.0
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

  method setBackgroundColor(self: NXView, r, g, b, a: cfloat) =
    self.viewBackgroundColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setHidden(self: NXView, hidden: bool) =
    self.viewHidden = hidden

  method dealloc(self: NXView) {.used.} =
    detachSubviews(self)
    clearIvarRefs(self)
    discard callSuperIdFrom(NXView, self, getSelector("dealloc"))

proc isViewDescendantOf(viewId: ID, ancestorId: ID): bool =
  if viewId.isNil or ancestorId.isNil:
    return false
  var currentId = viewId
  while not currentId.isNil:
    if currentId == ancestorId:
      return true
    let current = ownFromId[NXView](currentId)
    if current.isNil:
      break
    currentId = current.viewSuperview()
  false

objcImpl:
  type NXControl* = object of NXView
    enabled {.set: setEnabled, get: isEnabled.}: bool
    editable {.set: setEditable, get: isEditable.}: bool
    selectable {.set: setSelectable, get: isSelectable.}: bool
    scrollable {.set: setScrollable, get: isScrollable.}: bool
    bordered {.set: setBordered, get: isBordered.}: bool
    bezeled {.set: setBezeled, get: isBezeled.}: bool
    continuous {.set: setContinuous, get: isContinuous.}: bool
    refusesFirstResponder {.set: setRefusesFirstResponder, get: refusesFirstResponder.}:
      bool
    align {.set: setAlignment, get: alignment.}: NSTextAlignment

  method init*(self: var NXControl): NXControl =
    result = asType[NXControl](callSuperIdFrom(NXControl, self, getSelector("init")))
    if result.isNil:
      return
    result.enabled = true
    result.editable = false
    result.selectable = false
    result.scrollable = false
    result.bordered = false
    result.bezeled = false
    result.continuous = false
    result.refusesFirstResponder = false
    result.align = NSNaturalTextAlignment

  method acceptsFirstResponder*(self: NXControl): bool =
    if self.isNil:
      return false
    self.isEnabled() and (not self.refusesFirstResponder())

  method stringValue*(self: NXControl): NSString =
    discard self
    nsString("")

  method setStringValue*(self: NXControl, value: NSString) =
    discard self
    discard value

  method intValue*(self: NXControl): cint =
    if self.isNil:
      return 0.cint
    try:
      parseInt($self.stringValue()).cint
    except ValueError:
      0.cint

  method integerValue*(self: NXControl): int =
    self.intValue().int

  method floatValue*(self: NXControl): cfloat =
    if self.isNil:
      return 0.0
    try:
      parseFloat($self.stringValue()).cfloat
    except ValueError:
      0.0

  method doubleValue*(self: NXControl): cdouble =
    if self.isNil:
      return 0.0
    try:
      parseFloat($self.stringValue()).cdouble
    except ValueError:
      0.0

  method setIntValue*(self: NXControl, value: cint) =
    if self.isNil:
      return
    self.setStringValue(nsString($value))

  method setIntegerValue*(self: NXControl, value: int) =
    self.setIntValue(value.cint)

  method setFloatValue*(self: NXControl, value: cfloat) =
    if self.isNil:
      return
    self.setStringValue(nsString($value))

  method setDoubleValue*(self: NXControl, value: cdouble) =
    if self.isNil:
      return
    self.setStringValue(nsString($value))

  method takeStringValueFrom*(self: NXControl, sender: NXControl) =
    if self.isNil or sender.isNil:
      return
    self.setStringValue(sender.stringValue())

  method takeIntValueFrom*(self: NXControl, sender: NXControl) =
    if self.isNil or sender.isNil:
      return
    self.setIntValue(sender.intValue())

  method takeIntegerValueFrom*(self: NXControl, sender: NXControl) =
    if self.isNil or sender.isNil:
      return
    self.setIntegerValue(sender.integerValue())

  method takeFloatValueFrom*(self: NXControl, sender: NXControl) =
    if self.isNil or sender.isNil:
      return
    self.setFloatValue(sender.floatValue())

  method takeDoubleValueFrom*(self: NXControl, sender: NXControl) =
    if self.isNil or sender.isNil:
      return
    self.setDoubleValue(sender.doubleValue())

  method performClick*(self: NXControl, sender: NXResponder) =
    discard self
    discard sender

objcImpl:
  type NXTextField* = object of NXControl
    strValueId: ID
    txtColor {.set: setTextColor, get: textColor.}: NSColor
    bgColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    drawsBg {.set: setDrawsBackground, get: drawsBackground.}: bool
    prevTxt: ID
    nextTxt: ID

  method init*(self: var NXTextField): NXTextField =
    result =
      asType[NXTextField](callSuperIdFrom(NXTextField, self, getSelector("init")))
    if result.isNil:
      return
    result.enabled = true
    result.editable = true
    result.selectable = true
    result.scrollable = true
    result.bordered = true
    result.bezeled = true
    result.align = NSNaturalTextAlignment
    result.strValueId = retainId(nsString("").value)
    result.txtColor = nsColor(0.08, 0.08, 0.08, 1.0)
    result.bgColor = nsColor(0.98, 0.99, 1.0, 1.0)
    result.drawsBg = true
    result.prevTxt = nil
    result.nextTxt = nil

  method setTextColor*(self: NXTextField, r, g, b, a: cfloat) =
    self.txtColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setBackgroundColor*(self: NXTextField, r, g, b, a: cfloat) =
    self.bgColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method stringValue*(self: NXTextField): NSString =
    if self.strValueId.isNil:
      return nsString("")
    ownFromId[NSString](self.strValueId)

  method setStringValue*(self: NXTextField, value: NSString) =
    let next = value.value
    if self.strValueId == next:
      return
    self.strValueId = replacedOwnedId(self.strValueId, next)

  method previousText*(self: NXTextField): NXTextField =
    if self.prevTxt.isNil:
      return NXTextField(value: nil)
    ownFromId[NXTextField](self.prevTxt)

  method nextText*(self: NXTextField): NXTextField =
    if self.nextTxt.isNil:
      return NXTextField(value: nil)
    ownFromId[NXTextField](self.nextTxt)

  method setPreviousText*(self: NXTextField, text: NXTextField) =
    self.prevTxt = replacedOwnedId(self.prevTxt, text.value)

  method setNextText*(self: NXTextField, text: NXTextField) =
    self.nextTxt = replacedOwnedId(self.nextTxt, text.value)

  method selectText*(self: NXTextField, sender: NXResponder) =
    discard self
    discard sender

  method setTitleWithMnemonic*(self: NXTextField, value: NSString) =
    self.setStringValue(stripMnemonicMarkers(value))

  method dealloc(self: NXTextField) {.used.} =
    self.prevTxt = replacedOwnedId(self.prevTxt, nil)
    self.nextTxt = replacedOwnedId(self.nextTxt, nil)
    self.strValueId = replacedOwnedId(self.strValueId, nil)
    discard callSuperIdFrom(NXTextField, self, getSelector("dealloc"))

objcImpl:
  type NXButton* = object of NXControl
    titleId: ID
    stateValue {.get: state.}: int
    mixedAllowed {.get: allowsMixedState.}: bool
    transparent {.set: setTransparent, get: isTransparent.}: bool
    keyEqId: ID
    keyEqMods {.set: setKeyEquivalentModifierMask, get: keyEquivalentModifierMask.}: int
    imagePos {.set: setImagePosition, get: imagePosition.}: int
    bezel {.set: setBezelStyle, get: bezelStyle.}: int
    altTitleId: ID
    showBorderInside {.
      set: setShowsBorderOnlyWhileMouseInside, get: showsBorderOnlyWhileMouseInside
    .}: bool
    periodicDelaySec: cfloat
    periodicIntervalSec: cfloat
    onClick: NSButtonCallbackProc

  method init*(self: var NXButton): NXButton =
    result = asType[NXButton](callSuperIdFrom(NXButton, self, getSelector("init")))
    if result.isNil:
      return
    result.enabled = true
    result.align = NSNaturalTextAlignment
    result.titleId = retainId(nsString("Button").value)
    result.stateValue = NSOffState
    result.mixedAllowed = false
    result.bordered = true
    result.bezeled = true
    result.transparent = false
    result.keyEqId = retainId(nsString("").value)
    result.keyEqMods = 0
    result.imagePos = 0
    result.bezel = 0
    result.altTitleId = retainId(nsString("").value)
    result.showBorderInside = false
    result.periodicDelaySec = 0.0
    result.periodicIntervalSec = 0.0
    result.onClick = nil

  method title*(self: NXButton): NSString =
    if self.titleId.isNil:
      return nsString("")
    ownFromId[NSString](self.titleId)

  method setTitle*(self: NXButton, value: NSString) =
    self.titleId = replacedOwnedId(self.titleId, value.value)

  method keyEquivalent*(self: NXButton): NSString =
    if self.keyEqId.isNil:
      return nsString("")
    ownFromId[NSString](self.keyEqId)

  method setKeyEquivalent*(self: NXButton, value: NSString) =
    self.keyEqId = replacedOwnedId(self.keyEqId, value.value)

  method alternateTitle*(self: NXButton): NSString =
    if self.altTitleId.isNil:
      return nsString("")
    ownFromId[NSString](self.altTitleId)

  method setAlternateTitle*(self: NXButton, value: NSString) =
    self.altTitleId = replacedOwnedId(self.altTitleId, value.value)

  method setState*(self: NXButton, value: cint) =
    self.stateValue = normalizeButtonState(value.int, self.mixedAllowed)

  method setAllowsMixedState*(self: NXButton, value: bool) =
    self.mixedAllowed = value
    self.stateValue = normalizeButtonState(self.stateValue, value)

  method setNextState*(self: NXButton) =
    if self.mixedAllowed:
      case self.stateValue
      of NSOffState:
        self.stateValue = NSOnState
      of NSOnState:
        self.stateValue = NSMixedState
      else:
        self.stateValue = NSOffState
    else:
      if self.stateValue == NSOnState:
        self.stateValue = NSOffState
      else:
        self.stateValue = NSOnState

  method stringValue*(self: NXButton): NSString =
    self.title()

  method setStringValue*(self: NXButton, value: NSString) =
    self.setTitle(value)

  method intValue*(self: NXButton): cint =
    self.state().cint

  method integerValue*(self: NXButton): int =
    self.state()

  method floatValue*(self: NXButton): cfloat =
    self.state().cfloat

  method doubleValue*(self: NXButton): cdouble =
    self.state().cdouble

  method setIntValue*(self: NXButton, value: cint) =
    self.setState(value)

  method setIntegerValue*(self: NXButton, value: int) =
    self.setState(value.cint)

  method setFloatValue*(self: NXButton, value: cfloat) =
    self.setState(value.int.cint)

  method setDoubleValue*(self: NXButton, value: cdouble) =
    self.setState(value.int.cint)

  method performClick*(self: NXButton, sender: NXResponder) =
    discard sender
    if not self.enabled:
      return
    self.setNextState()
    let cb = self.onClick()
    if cb.isNil:
      return
    cb(self.value)

  method setPeriodicDelay*(self: NXButton, delay, interval: cfloat) =
    self.periodicDelaySec = max(delay, 0.0)
    self.periodicIntervalSec = max(interval, 0.0)

  method periodicDelay*(self: NXButton): cfloat =
    self.periodicDelaySec

  method periodicInterval*(self: NXButton): cfloat =
    self.periodicIntervalSec

  method setButtonType*(self: NXButton, value: cint) =
    discard self
    discard value

  method setTitleWithMnemonic*(self: NXButton, value: NSString) =
    self.setTitle(stripMnemonicMarkers(value))

  method dealloc(self: NXButton) {.used.} =
    self.titleId = replacedOwnedId(self.titleId, nil)
    self.keyEqId = replacedOwnedId(self.keyEqId, nil)
    self.altTitleId = replacedOwnedId(self.altTitleId, nil)
    self.onClick = nil
    discard callSuperIdFrom(NXButton, self, getSelector("dealloc"))

objcImpl:
  type NXWindow* = object of NXResponder
    windowFrame: NSRect
    windowTitleId: ID
    windowContentView: ID
    windowFirstResponder: ID
    windowNativeWindow: siwinshim.Window
    windowRenderer: figrender.FigRenderer[siwinshim.SiwinRenderBackend]
    windowAutoScale: bool
    windowNativeReady: bool
    windowVisibleRequested: bool
    windowClosed: bool

  method init*(self: var NXWindow): NXWindow =
    result = asType[NXWindow](callSuperIdFrom(NXWindow, self, getSelector("init")))
    if result.isNil:
      return
    result.windowFrame = nsRect(100, 100, 640, 420)
    result.windowTitleId = retainId(nsString("Nutella Window").value)
    result.windowContentView = nil
    result.windowFirstResponder = nil
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

  method setContentView(self: NXWindow, view: NXView) =
    if self.isNil:
      return
    if not self.windowContentView.isNil and self.windowContentView != view.value:
      if self.windowFirstResponder == self.windowContentView or
          isViewDescendantOf(self.windowFirstResponder, self.windowContentView):
        self.windowFirstResponder = replacedOwnedId(self.windowFirstResponder, nil)
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
      view.setNextResponder(asType[NXResponder](self))
    self.windowContentView = replacedOwnedId(self.windowContentView(), view.value)

  method contentView(self: NXWindow): NXView =
    if self.windowContentView.isNil:
      return NXView(value: nil)
    result = ownFromId[NXView](self.windowContentView)

  method windowTitle*(self: NXWindow): NSString =
    if self.windowTitleId.isNil:
      return nsString("")
    ownFromId[NSString](self.windowTitleId)

  method firstResponder*(self: NXWindow): NXResponder =
    if self.windowFirstResponder.isNil:
      return NXResponder(value: nil)
    ownFromId[NXResponder](self.windowFirstResponder)

  method makeFirstResponder*(self: NXWindow, responder: NXResponder): bool =
    if self.isNil:
      return false
    var requested = responder
    if requested.isNil:
      requested = asType[NXResponder](self)
    if self.windowFirstResponder == requested.value:
      return true

    let currentId = self.windowFirstResponder()
    var current = ownFromId[NXResponder](currentId)
    if not current.isNil and not current.resignFirstResponder():
      return false

    if not requested.acceptsFirstResponder() or not requested.becomeFirstResponder():
      if not current.isNil and current.acceptsFirstResponder() and
          current.becomeFirstResponder():
        self.windowFirstResponder =
          replacedOwnedId(self.windowFirstResponder(), current.value)
      return false

    self.windowFirstResponder =
      replacedOwnedId(self.windowFirstResponder(), requested.value)
    true

  method acceptsFirstResponder*(self: NXWindow): bool =
    true

  method setTitle*(self: NXWindow, value: NSString) =
    self.windowTitleId = replacedOwnedId(self.windowTitleId, value.value)
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      self.windowNativeWindow.title = $value

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

  method makeKeyAndOrderFront(self: NXWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    self.windowVisibleRequested = true

  method orderFront*(self: NXWindow, sender: NSObject) =
    self.makeKeyAndOrderFront(sender)

  method orderOut*(self: NXWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    self.windowVisibleRequested = false

  method isVisible*(self: NXWindow): bool =
    (not self.isNil) and self.windowVisibleRequested() and (not self.windowClosed())

  method isKeyWindow*(self: NXWindow): bool =
    self.isVisible()

  method isMiniaturized*(self: NXWindow): bool =
    false

  method close(self: NXWindow) =
    self.windowClosed = true
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      siwinshim.close(self.windowNativeWindow)

  method dealloc(self: NXWindow) {.used.} =
    if self.windowNativeReady and (not self.windowNativeWindow.isNil):
      siwinshim.close(self.windowNativeWindow)
    self.windowFirstResponder = replacedOwnedId(self.windowFirstResponder(), nil)
    if not self.windowContentView.isNil:
      clearSuperviewRef(self.windowContentView)
    self.windowTitleId = replacedOwnedId(self.windowTitleId, nil)
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
    if result.isNil:
      return
    result.appWindows = @[]
    result.appRunning = false

  method addWindow(self: NXApplication, window: NXWindow) =
    if self.isNil or window.isNil:
      return
    var windows = self.appWindows()
    if window.value notin windows:
      windows.add(retainId(window.value))
      self.appWindows = windows
    window.setNextResponder(asType[NXResponder](self))
    window.windowVisibleRequested = true

  method run(self: NXApplication) =
    discard runApplicationFrames(self, -1)

  method stop(self: NXApplication) =
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
