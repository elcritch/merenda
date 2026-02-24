import std/strutils
import ./runtime
import ./views

objcImpl:
  type NSCell* = object of NSObject
    controlViewId: ID
    cellType {.set: setType, get: `type`.}: int
    stateValue {.get: state.}: int
    mixedAllowed: bool

    enabled {.get: isEnabled.}: bool
    editable {.get: isEditable.}: bool
    selectable {.get: isSelectable.}: bool

    bordered {.get: isBordered.}: bool
    bezeled {.get: isBezeled.}: bool

    scrollable {.get: isScrollable.}: bool
    continuous {.get: isContinuous.}: bool
    highlighted {.get: isHighlighted.}: bool

    cellRefusesFirstResponder {.
      set: setRefusesFirstResponder, get: refusesFirstResponder
    .}: bool
    alignment: NSTextAlignment
    titleId: ID
    objectValueId: ID
    representedObjectId: ID

  method init*(self: var NSCell): NSCell =
    result = asType[NSCell](callSuperIdFrom(NSCell, self, getSelector("init")))
    if result.isNil:
      return
    result.controlViewId = nil
    result.cellType = 1
    result.stateValue = NSOffState
    result.mixedAllowed = false
    result.enabled = true
    result.editable = false
    result.selectable = false
    result.scrollable = false
    result.bordered = false
    result.bezeled = false
    result.continuous = false
    result.highlighted = false
    result.cellRefusesFirstResponder = false
    result.alignment = NSNaturalTextAlignment
    result.titleId = retainId(@ns"".value)
    result.objectValueId = retainId(@ns"".value)
    result.representedObjectId = nil

  method initTextCell*(self: var NSCell, value: NSString): NSCell =
    result = self.init()
    if result.isNil:
      return
    result.titleId = replacedOwnedId(result.titleId, value.value)
    result.objectValueId = replacedOwnedId(result.objectValueId, value.value)

  method controlView*(self: NSCell): NSView =
    if self.controlViewId.isNil:
      return NSView(value: nil)
    ownFromId[NSView](self.controlViewId)

  method setControlView*(self: NSCell, view: NSView) =
    self.controlViewId = replacedOwnedId(self.controlViewId, view.value)

  method target*(self: NSCell): NSObject =
    discard self
    NSObject(value: nil)

  method action*(self: NSCell): SEL =
    discard self
    nil

  method tag*(self: NSCell): int =
    discard self
    0

  method setTarget*(self: NSCell, target: NSObject) =
    discard self
    discard target

  method setAction*(self: NSCell, action: SEL) =
    discard self
    discard action

  method setTag*(self: NSCell, tag: int) =
    discard self
    discard tag

  method setState*(self: NSCell, value: int) =
    self.stateValue = normalizeButtonState(value, self.mixedAllowed)

  method nextState*(self: NSCell): int =
    if self.mixedAllowed:
      case self.stateValue
      of NSOffState: NSOnState
      of NSOnState: NSMixedState
      else: NSOffState
    else:
      if self.stateValue == NSOnState: NSOffState else: NSOnState

  method setNextState*(self: NSCell) =
    self.stateValue = self.nextState()

  method allowsMixedState*(self: NSCell): bool =
    self.mixedAllowed

  method setAllowsMixedState*(self: NSCell, allow: bool) =
    self.mixedAllowed = allow
    self.stateValue = normalizeButtonState(self.stateValue, allow)

  method title*(self: NSCell): NSString =
    if self.titleId.isNil:
      return @ns""
    ownFromId[NSString](self.titleId)

  method setTitle*(self: NSCell, value: NSString) =
    self.titleId = replacedOwnedId(self.titleId, value.value)
    self.objectValueId = replacedOwnedId(self.objectValueId, value.value)

  method objectValue*(self: NSCell): NSObject =
    if self.objectValueId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.objectValueId)

  method setObjectValue*(self: NSCell, value: NSObject) =
    self.objectValueId = replacedOwnedId(self.objectValueId, value.value)
    if value.value.isNil:
      self.titleId = replacedOwnedId(self.titleId, @ns"".value)
    else:
      let asString = asType[NSString](value.value)
      self.titleId = replacedOwnedId(self.titleId, asString.value)

  method stringValue*(self: NSCell): NSString =
    self.title()

  method setStringValue*(self: NSCell, value: NSString) =
    self.setTitle(value)

  method intValue*(self: NSCell): cint =
    try:
      parseInt($self.stringValue()).cint
    except ValueError:
      0.cint

  method integerValue*(self: NSCell): int =
    self.intValue().int

  method floatValue*(self: NSCell): cfloat =
    try:
      parseFloat($self.stringValue()).cfloat
    except ValueError:
      0.0

  method doubleValue*(self: NSCell): cdouble =
    try:
      parseFloat($self.stringValue()).cdouble
    except ValueError:
      0.0

  method setIntValue*(self: NSCell, value: cint) =
    self.setStringValue(ns($value))

  method setIntegerValue*(self: NSCell, value: int) =
    self.setStringValue(ns($value))

  method setFloatValue*(self: NSCell, value: cfloat) =
    self.setStringValue(ns($value))

  method setDoubleValue*(self: NSCell, value: cdouble) =
    self.setStringValue(ns($value))

  method representedObject*(self: NSCell): NSObject =
    if self.representedObjectId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.representedObjectId)

  method setRepresentedObject*(self: NSCell, value: NSObject) =
    self.representedObjectId = replacedOwnedId(self.representedObjectId, value.value)

  method takeStringValueFrom*(self: NSCell, sender: NSCell) =
    if sender.isNil:
      return
    self.setStringValue(sender.stringValue())

  method takeIntValueFrom*(self: NSCell, sender: NSCell) =
    if sender.isNil:
      return
    self.setIntValue(sender.intValue())

  method takeIntegerValueFrom*(self: NSCell, sender: NSCell) =
    if sender.isNil:
      return
    self.setIntegerValue(sender.integerValue())

  method takeFloatValueFrom*(self: NSCell, sender: NSCell) =
    if sender.isNil:
      return
    self.setFloatValue(sender.floatValue())

  method takeDoubleValueFrom*(self: NSCell, sender: NSCell) =
    if sender.isNil:
      return
    self.setDoubleValue(sender.doubleValue())

  method dealloc(self: NSCell) {.used.} =
    self.controlViewId = replacedOwnedId(self.controlViewId, nil)
    self.titleId = replacedOwnedId(self.titleId, nil)
    self.objectValueId = replacedOwnedId(self.objectValueId, nil)
    self.representedObjectId = replacedOwnedId(self.representedObjectId, nil)
    clearIvarRefs(self)
    discard callSuperIdFrom(NSCell, self, getSelector("dealloc"))

objcImpl:
  type NSActionCell* = object of NSCell
    actionControlViewId: ID
    actionTargetId: ID
    actionSelector: SEL
    actionTagValue {.set: setTag, get: tag.}: int

  method init*(self: var NSActionCell): NSActionCell =
    result =
      asType[NSActionCell](callSuperIdFrom(NSActionCell, self, getSelector("init")))
    if result.isNil:
      return
    result.actionControlViewId = nil
    result.actionTargetId = nil
    result.actionSelector = nil
    result.actionTagValue = 0

  method controlView*(self: NSActionCell): NSView =
    if self.actionControlViewId.isNil:
      return NSView(value: nil)
    ownFromId[NSView](self.actionControlViewId)

  method setControlView*(self: NSActionCell, view: NSView) =
    self.actionControlViewId = replacedOwnedId(self.actionControlViewId, view.value)

  method target*(self: NSActionCell): NSObject =
    if self.actionTargetId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.actionTargetId)

  method action*(self: NSActionCell): SEL =
    self.actionSelector

  method setTarget*(self: NSActionCell, target: NSObject) =
    self.actionTargetId = replacedOwnedId(self.actionTargetId, target.value)

  method setAction*(self: NSActionCell, action: SEL) =
    self.actionSelector = action

  method dealloc(self: NSActionCell) {.used.} =
    self.actionControlViewId = replacedOwnedId(self.actionControlViewId, nil)
    self.actionTargetId = replacedOwnedId(self.actionTargetId, nil)
    discard callSuperIdFrom(NSActionCell, self, getSelector("dealloc"))

objcImpl:
  type NSButtonCell* = object of NSActionCell
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

  method init*(self: var NSButtonCell): NSButtonCell =
    result =
      asType[NSButtonCell](callSuperIdFrom(NSButtonCell, self, getSelector("init")))
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

  method title*(self: NSButtonCell): NSString =
    if self.buttonTitleId.isNil:
      return @ns""
    ownFromId[NSString](self.buttonTitleId)

  method setTitle*(self: NSButtonCell, value: NSString) =
    self.buttonTitleId = replacedOwnedId(self.buttonTitleId, value.value)
    self.objectValueId = replacedOwnedId(self.objectValueId, value.value)

  method alternateTitle*(self: NSButtonCell): NSString =
    if self.alternateTitleId.isNil:
      return @ns""
    ownFromId[NSString](self.alternateTitleId)

  method setAlternateTitle*(self: NSButtonCell, value: NSString) =
    self.alternateTitleId = replacedOwnedId(self.alternateTitleId, value.value)

  method keyEquivalent*(self: NSButtonCell): NSString =
    if self.keyEqId.isNil:
      return @ns""
    ownFromId[NSString](self.keyEqId)

  method setKeyEquivalent*(self: NSButtonCell, value: NSString) =
    self.keyEqId = replacedOwnedId(self.keyEqId, value.value)

  method setButtonType*(self: NSButtonCell, buttonType: cint) =
    discard self
    discard buttonType

  method setPeriodicDelay*(
      self: NSButtonCell, delay: cfloat, interval {.kw("interval").}: cfloat
  ) =
    self.periodicDelaySec = max(delay, 0.0)
    self.periodicIntervalSec = max(interval, 0.0)

  method getPeriodicDelay*(
      self: NSButtonCell, delay: ptr cfloat, interval {.kw("interval").}: ptr cfloat
  ) =
    if not delay.isNil:
      delay[] = self.periodicDelaySec
    if not interval.isNil:
      interval[] = self.periodicIntervalSec

  method setState*(self: NSButtonCell, value: int) =
    self.stateValue = normalizeButtonState(value, self.mixedAllowed)

  method stringValue*(self: NSButtonCell): NSString =
    self.title()

  method setStringValue*(self: NSButtonCell, value: NSString) =
    self.setTitle(value)

  method intValue*(self: NSButtonCell): cint =
    self.state().cint

  method integerValue*(self: NSButtonCell): int =
    self.state()

  method floatValue*(self: NSButtonCell): cfloat =
    self.state().cfloat

  method doubleValue*(self: NSButtonCell): cdouble =
    self.state().cdouble

  method setIntValue*(self: NSButtonCell, value: cint) =
    self.setState(value.int)

  method setIntegerValue*(self: NSButtonCell, value: int) =
    self.setState(value)

  method setFloatValue*(self: NSButtonCell, value: cfloat) =
    self.setState(value.int)

  method setDoubleValue*(self: NSButtonCell, value: cdouble) =
    self.setState(value.int)

  method performClick*(self: NSButtonCell, sender: NSObject) =
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

  method dealloc(self: NSButtonCell) {.used.} =
    self.buttonTitleId = replacedOwnedId(self.buttonTitleId, nil)
    self.alternateTitleId = replacedOwnedId(self.alternateTitleId, nil)
    self.keyEqId = replacedOwnedId(self.keyEqId, nil)
    discard callSuperIdFrom(NSButtonCell, self, getSelector("dealloc"))

proc new*(t: typedesc[NSCell]): NSCell =
  var allocated = NSCell.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSActionCell]): NSActionCell =
  var allocated = NSActionCell.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSButtonCell]): NSButtonCell =
  var allocated = NSButtonCell.alloc()
  result = initOwned(move(allocated))
