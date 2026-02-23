import ./runtime

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

proc new*(t: typedesc[NSCell]): NSCell =
  var allocated = NSCell.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSActionCell]): NSActionCell =
  var allocated = NSActionCell.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSButtonCell]): NSButtonCell =
  var allocated = NSButtonCell.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

