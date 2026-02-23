import ./runtime

type NSButtonCallbackProc = proc(sender: ID)

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

proc new*(t: typedesc[NSButton]): NSButton =
  when false:
    discard t
  var allocated = NSButton.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

