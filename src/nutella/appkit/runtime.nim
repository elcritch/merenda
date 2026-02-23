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
  result = ns(dst)

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

  method tryToPerform*(
      self: NXResponder, action: SEL, sender {.kw("with").}: NSObject
  ): bool =
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

  method initWithFrame*(
      self: var NXView,
      x: cfloat,
      y {.kw("y").}: cfloat,
      width {.kw("width").}: cfloat,
      height {.kw("height").}: cfloat,
  ): NXView =
    result = self.init()
    if result.isNil:
      return
    result.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))

  method setFrame*(
      self: NXView,
      x: cfloat,
      y {.kw("y").}: cfloat,
      width {.kw("width").}: cfloat,
      height {.kw("height").}: cfloat,
  ) =
    self.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))

  method setBackgroundColor(
      self: NXView,
      r: cfloat,
      g {.kw("green").}: cfloat,
      b {.kw("blue").}: cfloat,
      a {.kw("alpha").}: cfloat,
  ) =
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
    @ns""

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
    self.setStringValue(ns($value))

  method setIntegerValue*(self: NXControl, value: int) =
    self.setIntValue(value.cint)

  method setFloatValue*(self: NXControl, value: cfloat) =
    if self.isNil:
      return
    self.setStringValue(ns($value))

  method setDoubleValue*(self: NXControl, value: cdouble) =
    if self.isNil:
      return
    self.setStringValue(ns($value))

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
  type NXCell* = object of NSObject
    controlViewId: ID
    cellType {.set: setType, get: `type`.}: int
    stateValue {.get: state.}: int
    mixedAllowed: bool
    cellEnabled {.set: setEnabled, get: isEnabled.}: bool
    cellEditable {.set: setEditable, get: isEditable.}: bool
    cellSelectable {.set: setSelectable, get: isSelectable.}: bool
    cellScrollable {.set: setScrollable, get: isScrollable.}: bool
    cellBordered {.set: setBordered, get: isBordered.}: bool
    cellBezeled {.set: setBezeled, get: isBezeled.}: bool
    cellContinuous {.set: setContinuous, get: isContinuous.}: bool
    cellHighlighted {.set: setHighlighted, get: isHighlighted.}: bool
    cellRefusesFirstResponder {.
      set: setRefusesFirstResponder, get: refusesFirstResponder
    .}: bool
    align {.set: setAlignment, get: alignment.}: NSTextAlignment
    titleId: ID
    objectValueId: ID
    representedObjectId: ID

  method init*(self: var NXCell): NXCell =
    result = asType[NXCell](callSuperIdFrom(NXCell, self, getSelector("init")))
    if result.isNil:
      return
    result.controlViewId = nil
    result.cellType = 1
    result.stateValue = NSOffState
    result.mixedAllowed = false
    result.cellEnabled = true
    result.cellEditable = false
    result.cellSelectable = false
    result.cellScrollable = false
    result.cellBordered = false
    result.cellBezeled = false
    result.cellContinuous = false
    result.cellHighlighted = false
    result.cellRefusesFirstResponder = false
    result.align = NSNaturalTextAlignment
    result.titleId = retainId(@ns"".value)
    result.objectValueId = retainId(@ns"".value)
    result.representedObjectId = nil

  method initTextCell*(self: var NXCell, value: NSString): NXCell =
    result = self.init()
    if result.isNil:
      return
    result.titleId = replacedOwnedId(result.titleId, value.value)
    result.objectValueId = replacedOwnedId(result.objectValueId, value.value)

  method controlView*(self: NXCell): NXView =
    if self.controlViewId.isNil:
      return NXView(value: nil)
    ownFromId[NXView](self.controlViewId)

  method setControlView*(self: NXCell, view: NXView) =
    self.controlViewId = replacedOwnedId(self.controlViewId, view.value)

  method target*(self: NXCell): NSObject =
    discard self
    NSObject(value: nil)

  method action*(self: NXCell): SEL =
    discard self
    nil

  method tag*(self: NXCell): int =
    discard self
    0

  method setTarget*(self: NXCell, target: NSObject) =
    discard self
    discard target

  method setAction*(self: NXCell, action: SEL) =
    discard self
    discard action

  method setTag*(self: NXCell, tag: int) =
    discard self
    discard tag

  method setState*(self: NXCell, value: int) =
    self.stateValue = normalizeButtonState(value, self.mixedAllowed)

  method nextState*(self: NXCell): int =
    if self.mixedAllowed:
      case self.stateValue
      of NSOffState: NSOnState
      of NSOnState: NSMixedState
      else: NSOffState
    else:
      if self.stateValue == NSOnState: NSOffState else: NSOnState

  method setNextState*(self: NXCell) =
    self.stateValue = self.nextState()

  method allowsMixedState*(self: NXCell): bool =
    self.mixedAllowed

  method setAllowsMixedState*(self: NXCell, allow: bool) =
    self.mixedAllowed = allow
    self.stateValue = normalizeButtonState(self.stateValue, allow)

  method title*(self: NXCell): NSString =
    if self.titleId.isNil:
      return @ns""
    ownFromId[NSString](self.titleId)

  method setTitle*(self: NXCell, value: NSString) =
    self.titleId = replacedOwnedId(self.titleId, value.value)
    self.objectValueId = replacedOwnedId(self.objectValueId, value.value)

  method objectValue*(self: NXCell): NSObject =
    if self.objectValueId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.objectValueId)

  method setObjectValue*(self: NXCell, value: NSObject) =
    self.objectValueId = replacedOwnedId(self.objectValueId, value.value)
    if value.value.isNil:
      self.titleId = replacedOwnedId(self.titleId, @ns"".value)
    else:
      let asString = asType[NSString](value.value)
      self.titleId = replacedOwnedId(self.titleId, asString.value)

  method stringValue*(self: NXCell): NSString =
    self.title()

  method setStringValue*(self: NXCell, value: NSString) =
    self.setTitle(value)

  method intValue*(self: NXCell): cint =
    try:
      parseInt($self.stringValue()).cint
    except ValueError:
      0.cint

  method integerValue*(self: NXCell): int =
    self.intValue().int

  method floatValue*(self: NXCell): cfloat =
    try:
      parseFloat($self.stringValue()).cfloat
    except ValueError:
      0.0

  method doubleValue*(self: NXCell): cdouble =
    try:
      parseFloat($self.stringValue()).cdouble
    except ValueError:
      0.0

  method setIntValue*(self: NXCell, value: cint) =
    self.setStringValue(ns($value))

  method setIntegerValue*(self: NXCell, value: int) =
    self.setStringValue(ns($value))

  method setFloatValue*(self: NXCell, value: cfloat) =
    self.setStringValue(ns($value))

  method setDoubleValue*(self: NXCell, value: cdouble) =
    self.setStringValue(ns($value))

  method representedObject*(self: NXCell): NSObject =
    if self.representedObjectId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.representedObjectId)

  method setRepresentedObject*(self: NXCell, value: NSObject) =
    self.representedObjectId = replacedOwnedId(self.representedObjectId, value.value)

  method takeStringValueFrom*(self: NXCell, sender: NXCell) =
    if sender.isNil:
      return
    self.setStringValue(sender.stringValue())

  method takeIntValueFrom*(self: NXCell, sender: NXCell) =
    if sender.isNil:
      return
    self.setIntValue(sender.intValue())

  method takeIntegerValueFrom*(self: NXCell, sender: NXCell) =
    if sender.isNil:
      return
    self.setIntegerValue(sender.integerValue())

  method takeFloatValueFrom*(self: NXCell, sender: NXCell) =
    if sender.isNil:
      return
    self.setFloatValue(sender.floatValue())

  method takeDoubleValueFrom*(self: NXCell, sender: NXCell) =
    if sender.isNil:
      return
    self.setDoubleValue(sender.doubleValue())

  method dealloc(self: NXCell) {.used.} =
    self.controlViewId = replacedOwnedId(self.controlViewId, nil)
    self.titleId = replacedOwnedId(self.titleId, nil)
    self.objectValueId = replacedOwnedId(self.objectValueId, nil)
    self.representedObjectId = replacedOwnedId(self.representedObjectId, nil)
    clearIvarRefs(self)
    discard callSuperIdFrom(NXCell, self, getSelector("dealloc"))

objcImpl:
  type NXActionCell* = object of NXCell
    actionControlViewId: ID
    actionTargetId: ID
    actionSelector: SEL
    actionTagValue {.set: setTag, get: tag.}: int

  method init*(self: var NXActionCell): NXActionCell =
    result =
      asType[NXActionCell](callSuperIdFrom(NXActionCell, self, getSelector("init")))
    if result.isNil:
      return
    result.actionControlViewId = nil
    result.actionTargetId = nil
    result.actionSelector = nil
    result.actionTagValue = 0

  method controlView*(self: NXActionCell): NXView =
    if self.actionControlViewId.isNil:
      return NXView(value: nil)
    ownFromId[NXView](self.actionControlViewId)

  method setControlView*(self: NXActionCell, view: NXView) =
    self.actionControlViewId = replacedOwnedId(self.actionControlViewId, view.value)

  method target*(self: NXActionCell): NSObject =
    if self.actionTargetId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.actionTargetId)

  method action*(self: NXActionCell): SEL =
    self.actionSelector

  method setTarget*(self: NXActionCell, target: NSObject) =
    self.actionTargetId = replacedOwnedId(self.actionTargetId, target.value)

  method setAction*(self: NXActionCell, action: SEL) =
    self.actionSelector = action

  method dealloc(self: NXActionCell) {.used.} =
    self.actionControlViewId = replacedOwnedId(self.actionControlViewId, nil)
    self.actionTargetId = replacedOwnedId(self.actionTargetId, nil)
    discard callSuperIdFrom(NXActionCell, self, getSelector("dealloc"))

objcImpl:
  type NXButtonCell* = object of NXActionCell
    buttonTitleId: ID
    alternateTitleId: ID
    transparent {.set: setTransparent, get: isTransparent.}: bool
    keyEqId: ID
    imagePos {.set: setImagePosition, get: imagePosition.}: int
    highlightsByMask {.set: setHighlightsBy, get: highlightsBy.}: int
    showsStateByMask {.set: setShowsStateBy, get: showsStateBy.}: int
    imageDimsDisabled {.set: setImageDimsWhenDisabled, get: imageDimsWhenDisabled.}:
      bool
    keyEqMods {.set: setKeyEquivalentModifierMask, get: keyEquivalentModifierMask.}: int
    bezel {.set: setBezelStyle, get: bezelStyle.}: int
    showBorderInside {.
      set: setShowsBorderOnlyWhileMouseInside, get: showsBorderOnlyWhileMouseInside
    .}: bool
    gradient {.set: setGradientType, get: gradientType.}: int
    imageScale {.set: setImageScaling, get: imageScaling.}: int
    bgColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    periodicDelaySec: cfloat
    periodicIntervalSec: cfloat

  method init*(self: var NXButtonCell): NXButtonCell =
    result =
      asType[NXButtonCell](callSuperIdFrom(NXButtonCell, self, getSelector("init")))
    if result.isNil:
      return
    result.buttonTitleId = retainId(@ns"Button".value)
    result.alternateTitleId = retainId(@ns"".value)
    result.transparent = false
    result.keyEqId = retainId(@ns"".value)
    result.imagePos = 0
    result.highlightsByMask = 0
    result.showsStateByMask = 0
    result.imageDimsDisabled = true
    result.keyEqMods = 0
    result.bezel = 0
    result.showBorderInside = false
    result.gradient = 0
    result.imageScale = 0
    result.bgColor = nsColor(0.0, 0.0, 0.0, 0.0)
    result.periodicDelaySec = 0.0
    result.periodicIntervalSec = 0.0

  method title*(self: NXButtonCell): NSString =
    if self.buttonTitleId.isNil:
      return @ns""
    ownFromId[NSString](self.buttonTitleId)

  method setTitle*(self: NXButtonCell, value: NSString) =
    self.buttonTitleId = replacedOwnedId(self.buttonTitleId, value.value)
    self.objectValueId = replacedOwnedId(self.objectValueId, value.value)

  method alternateTitle*(self: NXButtonCell): NSString =
    if self.alternateTitleId.isNil:
      return @ns""
    ownFromId[NSString](self.alternateTitleId)

  method setAlternateTitle*(self: NXButtonCell, value: NSString) =
    self.alternateTitleId = replacedOwnedId(self.alternateTitleId, value.value)

  method keyEquivalent*(self: NXButtonCell): NSString =
    if self.keyEqId.isNil:
      return @ns""
    ownFromId[NSString](self.keyEqId)

  method setKeyEquivalent*(self: NXButtonCell, value: NSString) =
    self.keyEqId = replacedOwnedId(self.keyEqId, value.value)

  method setButtonType*(self: NXButtonCell, buttonType: cint) =
    discard self
    discard buttonType

  method setPeriodicDelay*(
      self: NXButtonCell, delay: cfloat, interval {.kw("interval").}: cfloat
  ) =
    self.periodicDelaySec = max(delay, 0.0)
    self.periodicIntervalSec = max(interval, 0.0)

  method getPeriodicDelay*(
      self: NXButtonCell, delay: ptr cfloat, interval {.kw("interval").}: ptr cfloat
  ) =
    if not delay.isNil:
      delay[] = self.periodicDelaySec
    if not interval.isNil:
      interval[] = self.periodicIntervalSec

  method setState*(self: NXButtonCell, value: int) =
    self.stateValue = normalizeButtonState(value, self.mixedAllowed)

  method stringValue*(self: NXButtonCell): NSString =
    self.title()

  method setStringValue*(self: NXButtonCell, value: NSString) =
    self.setTitle(value)

  method intValue*(self: NXButtonCell): cint =
    self.state().cint

  method integerValue*(self: NXButtonCell): int =
    self.state()

  method floatValue*(self: NXButtonCell): cfloat =
    self.state().cfloat

  method doubleValue*(self: NXButtonCell): cdouble =
    self.state().cdouble

  method setIntValue*(self: NXButtonCell, value: cint) =
    self.setState(value.int)

  method setIntegerValue*(self: NXButtonCell, value: int) =
    self.setState(value)

  method setFloatValue*(self: NXButtonCell, value: cfloat) =
    self.setState(value.int)

  method setDoubleValue*(self: NXButtonCell, value: cdouble) =
    self.setState(value.int)

  method performClick*(self: NXButtonCell, sender: NSObject) =
    discard sender
    if self.isNil or not self.isEnabled():
      return
    if self.allowsMixedState():
      case self.state()
      of NSOffState:
        self.setState(NSOnState)
      of NSOnState:
        self.setState(NSMixedState)
      else:
        self.setState(NSOffState)
    else:
      if self.state() == NSOnState:
        self.setState(NSOffState)
      else:
        self.setState(NSOnState)
    let target = self.target()
    let action = self.action()
    if target.isNil or cast[pointer](action).isNil:
      return
    discard performResponderSelector(target, action, asType[NSObject](self.value))

  method dealloc(self: NXButtonCell) {.used.} =
    self.buttonTitleId = replacedOwnedId(self.buttonTitleId, nil)
    self.alternateTitleId = replacedOwnedId(self.alternateTitleId, nil)
    self.keyEqId = replacedOwnedId(self.keyEqId, nil)
    discard callSuperIdFrom(NXButtonCell, self, getSelector("dealloc"))

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
    result.strValueId = retainId(@ns"".value)
    result.txtColor = nsColor(0.08, 0.08, 0.08, 1.0)
    result.bgColor = nsColor(0.98, 0.99, 1.0, 1.0)
    result.drawsBg = true
    result.prevTxt = nil
    result.nextTxt = nil

  method setTextColor*(
      self: NXTextField,
      r: cfloat,
      g {.kw("green").}: cfloat,
      b {.kw("blue").}: cfloat,
      a {.kw("alpha").}: cfloat,
  ) =
    self.txtColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setBackgroundColor*(
      self: NXTextField,
      r: cfloat,
      g {.kw("green").}: cfloat,
      b {.kw("blue").}: cfloat,
      a {.kw("alpha").}: cfloat,
  ) =
    self.bgColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method stringValue*(self: NXTextField): NSString =
    if self.strValueId.isNil:
      return @ns""
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
    result.titleId = retainId(@ns"Button".value)
    result.stateValue = NSOffState
    result.mixedAllowed = false
    result.bordered = true
    result.bezeled = true
    result.transparent = false
    result.keyEqId = retainId(@ns"".value)
    result.keyEqMods = 0
    result.imagePos = 0
    result.bezel = 0
    result.altTitleId = retainId(@ns"".value)
    result.showBorderInside = false
    result.periodicDelaySec = 0.0
    result.periodicIntervalSec = 0.0
    result.onClick = nil

  method title*(self: NXButton): NSString =
    if self.titleId.isNil:
      return @ns""
    ownFromId[NSString](self.titleId)

  method setTitle*(self: NXButton, value: NSString) =
    self.titleId = replacedOwnedId(self.titleId, value.value)

  method keyEquivalent*(self: NXButton): NSString =
    if self.keyEqId.isNil:
      return @ns""
    ownFromId[NSString](self.keyEqId)

  method setKeyEquivalent*(self: NXButton, value: NSString) =
    self.keyEqId = replacedOwnedId(self.keyEqId, value.value)

  method alternateTitle*(self: NXButton): NSString =
    if self.altTitleId.isNil:
      return @ns""
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

  method setPeriodicDelay*(
      self: NXButton, delay: cfloat, interval {.kw("interval").}: cfloat
  ) =
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
  type NXSecureTextField* = object of NXTextField
    echosBullets {.set: setEchosBullets, get: echosBullets.}: bool

  method init*(self: var NXSecureTextField): NXSecureTextField =
    result = asType[NXSecureTextField](
      callSuperIdFrom(NXSecureTextField, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.echosBullets = true

objcImpl:
  type NXSearchField* = object of NXTextField
    recentSearchesId: ID
    recentsAutosaveNameId: ID

  method init*(self: var NXSearchField): NXSearchField =
    result =
      asType[NXSearchField](callSuperIdFrom(NXSearchField, self, getSelector("init")))
    if result.isNil:
      return
    result.recentSearchesId = retainId(nsArray[NSString]().value)
    result.recentsAutosaveNameId = retainId(@ns"".value)

  method recentSearches*(self: NXSearchField): NSArray[NSString] =
    if self.recentSearchesId.isNil:
      return nsArray[NSString]()
    ownFromId[NSArray[NSString]](self.recentSearchesId)

  method setRecentSearches*(self: NXSearchField, searches: NSArray[NSString]) =
    self.recentSearchesId = replacedOwnedId(self.recentSearchesId, searches.value)

  method recentsAutosaveName*(self: NXSearchField): NSString =
    if self.recentsAutosaveNameId.isNil:
      return @ns""
    ownFromId[NSString](self.recentsAutosaveNameId)

  method setRecentsAutosaveName*(self: NXSearchField, name: NSString) =
    self.recentsAutosaveNameId = replacedOwnedId(self.recentsAutosaveNameId, name.value)

  method dealloc(self: NXSearchField) {.used.} =
    self.recentSearchesId = replacedOwnedId(self.recentSearchesId, nil)
    self.recentsAutosaveNameId = replacedOwnedId(self.recentsAutosaveNameId, nil)
    discard callSuperIdFrom(NXSearchField, self, getSelector("dealloc"))

objcImpl:
  type NXClipView* = object of NXView
    clipBackgroundColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    clipDocumentCursorId: ID
    clipDocumentViewId: ID
    clipDocumentRect: NSRect
    clipDrawsBackground {.set: setDrawsBackground, get: drawsBackground.}: bool
    clipCopiesOnScroll {.set: setCopiesOnScroll, get: copiesOnScroll.}: bool
    clipScrollOrigin: NSPoint

  method init*(self: var NXClipView): NXClipView =
    result = asType[NXClipView](callSuperIdFrom(NXClipView, self, getSelector("init")))
    if result.isNil:
      return
    result.clipBackgroundColor = nsColor(1.0, 1.0, 1.0, 1.0)
    result.clipDocumentCursorId = nil
    result.clipDocumentViewId = nil
    result.clipDocumentRect = nsRect(0, 0, 0, 0)
    result.clipDrawsBackground = true
    result.clipCopiesOnScroll = false
    result.clipScrollOrigin = nsPoint(0, 0)

  method documentCursor*(self: NXClipView): NSObject =
    if self.clipDocumentCursorId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.clipDocumentCursorId)

  method setDocumentCursor*(self: NXClipView, value: NSObject) =
    self.clipDocumentCursorId = replacedOwnedId(self.clipDocumentCursorId, value.value)

  method documentView*(self: NXClipView): NXView =
    if self.clipDocumentViewId.isNil:
      return NXView(value: nil)
    ownFromId[NXView](self.clipDocumentViewId)

  method setDocumentView*(self: NXClipView, view: NXView) =
    if self.isNil:
      return
    if self.clipDocumentViewId == view.value:
      return

    if not self.clipDocumentViewId.isNil:
      clearSuperviewRef(self.clipDocumentViewId)
      var children = self.viewSubviews()
      for i, candidate in children:
        if candidate == self.clipDocumentViewId:
          children.del(i)
          self.viewSubviews = children
          releaseId(candidate)
          break

    if view.isNil:
      self.clipDocumentViewId = replacedOwnedId(self.clipDocumentViewId, nil)
      self.clipDocumentRect = nsRect(0, 0, 0, 0)
      self.clipScrollOrigin = nsPoint(0, 0)
      return

    let parentId = view.viewSuperview()
    if not parentId.isNil:
      var parent = ownFromId[NXView](parentId)
      if not parent.isNil:
        var siblings = parent.viewSubviews()
        for i, candidate in siblings:
          if candidate == view.value:
            siblings.del(i)
            parent.viewSubviews = siblings
            releaseId(candidate)
            break
      view.viewSuperview = nil

    var children = self.viewSubviews()
    if view.value notin children:
      children.add(retainId(view.value))
      self.viewSubviews = children
    view.viewSuperview = self.value
    view.setNextResponder(asType[NXResponder](self))
    self.clipDocumentViewId = replacedOwnedId(self.clipDocumentViewId, view.value)
    self.clipDocumentRect = view.viewFrame()
    self.clipScrollOrigin = self.constrainScrollPoint(self.clipScrollOrigin)

  method documentRect*(self: NXClipView): NSRect =
    if self.clipDocumentViewId.isNil:
      return nsRect(0, 0, 0, 0)
    let doc = self.documentView()
    if doc.isNil:
      return nsRect(0, 0, 0, 0)
    let frame = doc.viewFrame()
    self.clipDocumentRect =
      nsRect(0, 0, max(frame.size.width, 0.0), max(frame.size.height, 0.0))
    self.clipDocumentRect

  method documentVisibleRect*(self: NXClipView): NSRect =
    let constrained = self.constrainScrollPoint(self.clipScrollOrigin)
    let clipSize = self.viewFrame().size
    let docRect = self.documentRect()
    nsRect(
      constrained.x,
      constrained.y,
      min(clipSize.width, docRect.size.width),
      min(clipSize.height, docRect.size.height),
    )

  method constrainScrollPoint*(self: NXClipView, point: NSPoint): NSPoint =
    let docRect = self.documentRect()
    let clipSize = self.viewFrame().size
    let maxX = max(docRect.size.width - clipSize.width, 0.0)
    let maxY = max(docRect.size.height - clipSize.height, 0.0)
    result = nsPoint(clamp(point.x, 0.0, maxX), clamp(point.y, 0.0, maxY))

  method viewBoundsChanged*(self: NXClipView, note: NSObject) =
    discard self
    discard note

  method viewFrameChanged*(self: NXClipView, note: NSObject) =
    discard self
    discard note

  method autoscroll*(self: NXClipView, event: NSObject): bool =
    discard self
    discard event
    false

  method scrollToPoint*(self: NXClipView, point: NSPoint) =
    self.clipScrollOrigin = self.constrainScrollPoint(point)

  method dealloc(self: NXClipView) {.used.} =
    self.clipDocumentCursorId = replacedOwnedId(self.clipDocumentCursorId, nil)
    self.clipDocumentViewId = replacedOwnedId(self.clipDocumentViewId, nil)
    discard callSuperIdFrom(NXClipView, self, getSelector("dealloc"))

objcImpl:
  type NXCollectionView* = object of NXView
    contentId: ID
    itemPrototypeId: ID
    selectable {.set: setSelectable, get: isSelectable.}: bool
    minItem {.set: setMinItemSize, get: minItemSize.}: NSSize
    maxItem {.set: setMaxItemSize, get: maxItemSize.}: NSSize
    maxRows {.set: setMaxNumberOfRows, get: maxNumberOfRows.}: int
    maxCols {.set: setMaxNumberOfColumns, get: maxNumberOfColumns.}: int
    backgroundColorsId: ID
    allowsMulti {.set: setAllowsMultipleSelection, get: allowsMultipleSelection.}: bool
    selectionIndexesId: ID

  method init*(self: var NXCollectionView): NXCollectionView =
    result = asType[NXCollectionView](
      callSuperIdFrom(NXCollectionView, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.contentId = retainId(nsArray[NSObject]().value)
    result.itemPrototypeId = nil
    result.selectable = true
    result.minItem = nsSize(120, 120)
    result.maxItem = nsSize(120, 120)
    result.maxRows = 0
    result.maxCols = 0
    result.backgroundColorsId = retainId(nsArray[NSObject]().value)
    result.allowsMulti = false
    result.selectionIndexesId = nil

  method content*(self: NXCollectionView): NSArray[NSObject] =
    if self.contentId.isNil:
      return nsArray[NSObject]()
    ownFromId[NSArray[NSObject]](self.contentId)

  method setContent*(self: NXCollectionView, value: NSArray[NSObject]) =
    self.contentId = replacedOwnedId(self.contentId, value.value)

  method itemPrototype*(self: NXCollectionView): NSObject =
    if self.itemPrototypeId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.itemPrototypeId)

  method setItemPrototype*(self: NXCollectionView, value: NSObject) =
    self.itemPrototypeId = replacedOwnedId(self.itemPrototypeId, value.value)

  method backgroundColors*(self: NXCollectionView): NSArray[NSObject] =
    if self.backgroundColorsId.isNil:
      return nsArray[NSObject]()
    ownFromId[NSArray[NSObject]](self.backgroundColorsId)

  method setBackgroundColors*(self: NXCollectionView, value: NSArray[NSObject]) =
    self.backgroundColorsId = replacedOwnedId(self.backgroundColorsId, value.value)

  method selectionIndexes*(self: NXCollectionView): NSObject =
    if self.selectionIndexesId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.selectionIndexesId)

  method setSelectionIndexes*(self: NXCollectionView, value: NSObject) =
    self.selectionIndexesId = replacedOwnedId(self.selectionIndexesId, value.value)

  method isFirstResponder*(self: NXCollectionView): bool =
    false

  method newItemForRepresentedObject*(
      self: NXCollectionView, representedObject {.kw("object").}: NSObject
  ): NSObject =
    discard representedObject
    if self.itemPrototypeId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.itemPrototypeId)

  method dealloc(self: NXCollectionView) {.used.} =
    self.contentId = replacedOwnedId(self.contentId, nil)
    self.itemPrototypeId = replacedOwnedId(self.itemPrototypeId, nil)
    self.backgroundColorsId = replacedOwnedId(self.backgroundColorsId, nil)
    self.selectionIndexesId = replacedOwnedId(self.selectionIndexesId, nil)
    discard callSuperIdFrom(NXCollectionView, self, getSelector("dealloc"))

objcImpl:
  type NXBox* = object of NXView
    boxType {.set: setBoxType, get: boxType.}: int
    borderType {.set: setBorderType, get: borderType.}: int
    titlePosition {.set: setTitlePosition, get: titlePosition.}: int
    transparent {.set: setTransparent, get: isTransparent.}: bool
    contentMargins {.set: setContentViewMargins, get: contentViewMargins.}: NSSize
    titleId: ID
    boxContentView: ID

  method init*(self: var NXBox): NXBox =
    result = asType[NXBox](callSuperIdFrom(NXBox, self, getSelector("init")))
    if result.isNil:
      return
    result.boxType = 0
    result.borderType = 1
    result.titlePosition = 1
    result.transparent = true
    result.contentMargins = nsSize(0, 0)
    result.titleId = retainId(@ns"".value)
    result.boxContentView = nil

    var contentAlloc = NXView.alloc()
    var content = contentAlloc.initWithFrame(
      0.cfloat,
      0.cfloat,
      result.viewFrame().size.width.cfloat,
      result.viewFrame().size.height.cfloat,
    )
    contentAlloc.value = nil
    if not content.isNil:
      var children = result.viewSubviews()
      children.add(retainId(content.value))
      result.viewSubviews = children
      content.viewSuperview = result.value
      content.setNextResponder(asType[NXResponder](result))
      result.boxContentView = replacedOwnedId(result.boxContentView, content.value)
    content.value = nil

  method title*(self: NXBox): NSString =
    if self.titleId.isNil:
      return @ns""
    ownFromId[NSString](self.titleId)

  method setTitle*(self: NXBox, value: NSString) =
    self.titleId = replacedOwnedId(self.titleId, value.value)

  method setTitleWithMnemonic*(self: NXBox, value: NSString) =
    self.setTitle(stripMnemonicMarkers(value))

  method contentView*(self: NXBox): NXView =
    if self.boxContentView.isNil:
      return NXView(value: nil)
    ownFromId[NXView](self.boxContentView)

  method setContentView*(self: NXBox, view: NXView) =
    if self.isNil:
      return
    if self.boxContentView == view.value:
      return

    if not self.boxContentView.isNil:
      clearSuperviewRef(self.boxContentView)
      var children = self.viewSubviews()
      for i, candidate in children:
        if candidate == self.boxContentView:
          children.del(i)
          self.viewSubviews = children
          releaseId(candidate)
          break

    if view.isNil:
      self.boxContentView = replacedOwnedId(self.boxContentView, nil)
      return

    let parentId = view.viewSuperview()
    if not parentId.isNil:
      var parent = ownFromId[NXView](parentId)
      if not parent.isNil:
        var siblings = parent.viewSubviews()
        for i, candidate in siblings:
          if candidate == view.value:
            siblings.del(i)
            parent.viewSubviews = siblings
            releaseId(candidate)
            break
      view.viewSuperview = nil

    var children = self.viewSubviews()
    if view.value notin children:
      children.add(retainId(view.value))
      self.viewSubviews = children
    view.viewSuperview = self.value
    view.setNextResponder(asType[NXResponder](self))
    self.boxContentView = replacedOwnedId(self.boxContentView, view.value)

  method setFrame*(
      self: NXBox,
      x: cfloat,
      y {.kw("y").}: cfloat,
      width {.kw("width").}: cfloat,
      height {.kw("height").}: cfloat,
  ) =
    self.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))
    let content = self.contentView()
    if not content.isNil:
      content.setFrame(
        0.cfloat,
        0.cfloat,
        self.viewFrame().size.width.cfloat,
        self.viewFrame().size.height.cfloat,
      )

  method dealloc(self: NXBox) {.used.} =
    self.titleId = replacedOwnedId(self.titleId, nil)
    self.boxContentView = replacedOwnedId(self.boxContentView, nil)
    discard callSuperIdFrom(NXBox, self, getSelector("dealloc"))

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
    result.windowTitleId = retainId(@ns"Nutella Window".value)
    result.windowContentView = nil
    result.windowFirstResponder = nil
    result.windowNativeWindow = nil
    result.windowRenderer = nil
    result.windowAutoScale = true
    result.windowNativeReady = false
    result.windowVisibleRequested = false
    result.windowClosed = false

  method initWithContentRect*(
      self: var NXWindow,
      x: cfloat,
      y {.kw("y").}: cfloat,
      width {.kw("width").}: cfloat,
      height {.kw("height").}: cfloat,
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
      return @ns""
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

  method setContentSize*(
      self: NXWindow, width: cfloat, height {.kw("height").}: cfloat
  ) =
    var frame = self.windowFrame()
    frame.size = nsSize(max(width.float32, 1.0), max(height.float32, 1.0))
    self.windowFrame = frame
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      self.windowNativeWindow.size =
        ivec2(clampWindowSize(frame.size.width), clampWindowSize(frame.size.height))

  method setFrameOrigin*(self: NXWindow, x: cfloat, y {.kw("y").}: cfloat) =
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
  type NXPanel* = object of NXWindow
    worksWhenModal {.set: setWorksWhenModal, get: worksWhenModal.}: bool
    becomesKeyOnlyIfNeeded {.
      set: setBecomesKeyOnlyIfNeeded, get: becomesKeyOnlyIfNeeded
    .}: bool
    floatingPanel {.set: setFloatingPanel, get: isFloatingPanel.}: bool

  method init*(self: var NXPanel): NXPanel =
    result = asType[NXPanel](callSuperIdFrom(NXPanel, self, getSelector("init")))
    if result.isNil:
      return
    result.worksWhenModal = false
    result.becomesKeyOnlyIfNeeded = false
    result.floatingPanel = false

  method canBecomeMainWindow*(self: NXPanel): bool =
    discard self
    false

objcImpl:
  type NXAlert* = object of NSObject
    delegateId: ID
    style {.set: setAlertStyle, get: alertStyle.}: int
    iconId: ID
    messageTextId: ID
    informativeTextId: ID
    accessoryViewId: ID
    showsHelpFlag {.set: setShowsHelp, get: showsHelp.}: bool
    showsSuppression: bool
    helpAnchorId: ID
    alertButtonsId: ID
    suppressionButtonId: ID
    alertWindowId: ID
    needsLayout: bool
    sheetDelegateId: ID
    sheetDidEnd: SEL

  method init*(self: var NXAlert): NXAlert =
    result = asType[NXAlert](callSuperIdFrom(NXAlert, self, getSelector("init")))
    if result.isNil:
      return
    result.delegateId = nil
    result.style = NSWarningAlertStyle
    result.iconId = nil
    result.messageTextId = retainId(@ns"".value)
    result.informativeTextId = retainId(@ns"".value)
    result.accessoryViewId = nil
    result.showsHelpFlag = false
    result.showsSuppression = false
    result.helpAnchorId = retainId(@ns"".value)
    result.alertButtonsId = retainId(nsArray[NXButton]().value)
    result.suppressionButtonId = nil
    result.alertWindowId = nil
    result.needsLayout = true
    result.sheetDelegateId = nil
    result.sheetDidEnd = nil

  proc alertWithError*(t: typedesc[NXAlert], err {.kw("error").}: NSObject): NXAlert =
    when false:
      discard t
    result = NXAlert.new()
    if result.isNil:
      return
    if err.isNil:
      result.setMessageText(@ns"Error")
      result.setInformativeText(@ns"Unknown error")
    else:
      result.setMessageText(@ns"Error")
      result.setInformativeText(ns($err))

  proc alertWithMessageText*(
      t: typedesc[NXAlert],
      messageText: NSString,
      defaultButton {.kw("defaultButton").}: NSString,
      alternateButton {.kw("alternateButton").}: NSString,
      otherButton {.kw("otherButton").}: NSString,
      informativeText {.kw("informativeTextWithFormat").}: NSString,
  ): NXAlert =
    when false:
      discard t
    result = NXAlert.new()
    if result.isNil:
      return
    result.setMessageText(messageText)
    result.setInformativeText(informativeText)
    if $defaultButton != "":
      discard result.addButtonWithTitle(defaultButton)
    if $alternateButton != "":
      discard result.addButtonWithTitle(alternateButton)
    if $otherButton != "":
      discard result.addButtonWithTitle(otherButton)

  method delegate*(self: NXAlert): NSObject =
    if self.delegateId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.delegateId)

  method setDelegate*(self: NXAlert, value: NSObject) =
    self.delegateId = replacedOwnedId(self.delegateId, value.value)

  method icon*(self: NXAlert): NSObject =
    if self.iconId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.iconId)

  method setIcon*(self: NXAlert, value: NSObject) =
    self.iconId = replacedOwnedId(self.iconId, value.value)

  method messageText*(self: NXAlert): NSString =
    if self.messageTextId.isNil:
      return @ns""
    ownFromId[NSString](self.messageTextId)

  method setMessageText*(self: NXAlert, value: NSString) =
    self.messageTextId = replacedOwnedId(self.messageTextId, value.value)
    self.needsLayout = true

  method informativeText*(self: NXAlert): NSString =
    if self.informativeTextId.isNil:
      return @ns""
    ownFromId[NSString](self.informativeTextId)

  method setInformativeText*(self: NXAlert, value: NSString) =
    self.informativeTextId = replacedOwnedId(self.informativeTextId, value.value)
    self.needsLayout = true

  method accessoryView*(self: NXAlert): NXView =
    if self.accessoryViewId.isNil:
      return NXView(value: nil)
    ownFromId[NXView](self.accessoryViewId)

  method setAccessoryView*(self: NXAlert, value: NXView) =
    self.accessoryViewId = replacedOwnedId(self.accessoryViewId, value.value)
    self.needsLayout = true

  method helpAnchor*(self: NXAlert): NSString =
    if self.helpAnchorId.isNil:
      return @ns""
    ownFromId[NSString](self.helpAnchorId)

  method setHelpAnchor*(self: NXAlert, value: NSString) =
    self.helpAnchorId = replacedOwnedId(self.helpAnchorId, value.value)

  method suppressionButton*(self: NXAlert): NXButton =
    if self.suppressionButtonId.isNil:
      return NXButton(value: nil)
    ownFromId[NXButton](self.suppressionButtonId)

  method showsSuppressionButton*(self: NXAlert): bool =
    self.showsSuppression

  method setShowsSuppressionButton*(self: NXAlert, value: bool) =
    self.showsSuppression = value
    if value and self.suppressionButtonId.isNil:
      var button = NXButton.new()
      button.setTitle(@ns"Do not show again")
      self.suppressionButtonId = replacedOwnedId(self.suppressionButtonId, button.value)

  method buttons*(self: NXAlert): NSArray[NXButton] =
    if self.alertButtonsId.isNil:
      return nsArray[NXButton]()
    ownFromId[NSArray[NXButton]](self.alertButtonsId)

  method addButtonWithTitle*(self: NXAlert, title: NSString): NXButton =
    result = NXButton.new()
    if result.isNil:
      return
    result.setTitle(title)
    var buttons = self.buttons()
    buttons.add(result)
    self.alertButtonsId = replacedOwnedId(self.alertButtonsId, buttons.value)
    self.needsLayout = true

  method window*(self: NXAlert): NXWindow =
    if self.alertWindowId.isNil:
      return NXWindow(value: nil)
    ownFromId[NXWindow](self.alertWindowId)

  method layout*(self: NXAlert) =
    self.needsLayout = false

  method beginSheetModalForWindow*(
      self: NXAlert,
      window: NXWindow,
      modalDelegate {.kw("modalDelegate").}: NSObject,
      didEndSelector {.kw("didEndSelector").}: SEL,
      contextInfo {.kw("contextInfo").}: pointer,
  ) =
    discard contextInfo
    self.alertWindowId = replacedOwnedId(self.alertWindowId, window.value)
    self.sheetDelegateId = replacedOwnedId(self.sheetDelegateId, modalDelegate.value)
    self.sheetDidEnd = didEndSelector

  method runModal*(self: NXAlert): int =
    let count = self.buttons().len
    if count <= 1:
      return NSAlertFirstButtonReturn
    if count == 2:
      return NSAlertSecondButtonReturn
    NSAlertThirdButtonReturn

  method dealloc(self: NXAlert) {.used.} =
    self.delegateId = replacedOwnedId(self.delegateId, nil)
    self.iconId = replacedOwnedId(self.iconId, nil)
    self.messageTextId = replacedOwnedId(self.messageTextId, nil)
    self.informativeTextId = replacedOwnedId(self.informativeTextId, nil)
    self.accessoryViewId = replacedOwnedId(self.accessoryViewId, nil)
    self.helpAnchorId = replacedOwnedId(self.helpAnchorId, nil)
    self.suppressionButtonId = replacedOwnedId(self.suppressionButtonId, nil)
    self.alertButtonsId = replacedOwnedId(self.alertButtonsId, nil)
    self.alertWindowId = replacedOwnedId(self.alertWindowId, nil)
    self.sheetDelegateId = replacedOwnedId(self.sheetDelegateId, nil)
    discard callSuperIdFrom(NXAlert, self, getSelector("dealloc"))

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
  NSCell* = NXCell
  NSActionCell* = NXActionCell
  NSButtonCell* = NXButtonCell
  NSTextField* = NXTextField
  NSSecureTextField* = NXSecureTextField
  NSSearchField* = NXSearchField
  NSClipView* = NXClipView
  NSCollectionView* = NXCollectionView
  NSButton* = NXButton
  NSBox* = NXBox
  NSWindow* = NXWindow
  NSPanel* = NXPanel
  NSAlert* = NXAlert
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

proc new*(t: typedesc[NSCell]): NSCell =
  when false:
    discard t
  var allocated = NSCell.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSActionCell]): NSActionCell =
  when false:
    discard t
  var allocated = NSActionCell.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSButtonCell]): NSButtonCell =
  when false:
    discard t
  var allocated = NSButtonCell.alloc()
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

proc new*(t: typedesc[NSSecureTextField]): NSSecureTextField =
  when false:
    discard t
  var allocated = NSSecureTextField.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSSearchField]): NSSearchField =
  when false:
    discard t
  var allocated = NSSearchField.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSClipView]): NSClipView =
  when false:
    discard t
  var allocated = NSClipView.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSCollectionView]): NSCollectionView =
  when false:
    discard t
  var allocated = NSCollectionView.alloc()
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

proc new*(t: typedesc[NSBox]): NSBox =
  when false:
    discard t
  var allocated = NSBox.alloc()
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

proc new*(t: typedesc[NSPanel]): NSPanel =
  when false:
    discard t
  var allocated = NSPanel.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSAlert]): NSAlert =
  when false:
    discard t
  var allocated = NSAlert.alloc()
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
