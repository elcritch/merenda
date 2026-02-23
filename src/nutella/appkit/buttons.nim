import ./runtime

import ./controls

export controls

type NSButtonCallbackProc = proc(sender: ID)

objcImpl:

  type NSButton* = object of NSControl
    title: NSString
    alternateTitle: NSString

    bordered {.get: isBordered.}: bool
    bezeled {.get: isBezeled.}: bool

    stateValue {.get: state.}: int
    mixedAllowed {.get: allowsMixedState.}: bool
    transparent {.set: setTransparent, get: isTransparent.}: bool
    keyEquivalentModifierMask: int # NSEventModifierFlags
    imagePos {.set: setImagePosition, get: imagePosition.}: int
    bezel {.set: setBezelStyle, get: bezelStyle.}: int
    showBorderInside {.
      set: setShowsBorderOnlyWhileMouseInside, get: showsBorderOnlyWhileMouseInside
    .}: bool
    periodicDelaySec: cfloat
    periodicIntervalSec: cfloat
    onClick: NSButtonCallbackProc

    keyEqId: ID

  method init*(self: var NSButton): NSButton =
    result = asType[NSButton](callSuperIdFrom(NSButton, self, getSelector("init")))
    if result.isNil:
      return
    result.enabled = true
    result.alignment = NSNaturalTextAlignment
    result.title = @ns"Button"
    result.stateValue = NSOffState
    result.mixedAllowed = false
    result.bordered = true
    result.bezeled = true
    result.transparent = false
    result.keyEquivalent = @ns""
    result.keyEqMods = 0
    result.imagePos = 0
    result.bezel = 0
    result.alternateTitle = retainId(@ns"".value)
    result.showBorderInside = false
    result.periodicDelaySec = 0.0
    result.periodicIntervalSec = 0.0
    result.onClick = nil

  method title*(self: NSButton): NSString =
    if self.title.isNil:
      return @ns""
    ownFromId[NSString](self.title)

  method setTitle*(self: NSButton, value: NSString) =
    self.title = replacedOwnedId(self.title, value.value)

  method keyEquivalent*(self: NSButton): NSString =
    if self.keyEqId.isNil:
      return @ns""
    ownFromId[NSString](self.keyEqId)

  method setKeyEquivalent*(self: NSButton, value: NSString) =
    self.keyEqId = replacedOwnedId(self.keyEqId, value.value)

  method alternateTitle*(self: NSButton): NSString =
    if self.alternateTitle.isNil:
      return @ns""
    ownFromId[NSString](self.alternateTitle)

  method setAlternateTitle*(self: NSButton, value: NSString) =
    self.alternateTitle = replacedOwnedId(self.alternateTitle, value.value)

  method setState*(self: NSButton, value: cint) =
    self.stateValue = normalizeButtonState(value.int, self.mixedAllowed)

  method setAllowsMixedState*(self: NSButton, value: bool) =
    self.mixedAllowed = value
    self.stateValue = normalizeButtonState(self.stateValue, value)

  method setNextState*(self: NSButton) =
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

  method stringValue*(self: NSButton): NSString =
    self.title()

  method setStringValue*(self: NSButton, value: NSString) =
    self.setTitle(value)

  method intValue*(self: NSButton): cint =
    self.state().cint

  method integerValue*(self: NSButton): int =
    self.state()

  method floatValue*(self: NSButton): cfloat =
    self.state().cfloat

  method doubleValue*(self: NSButton): cdouble =
    self.state().cdouble

  method setIntValue*(self: NSButton, value: cint) =
    self.setState(value)

  method setIntegerValue*(self: NSButton, value: int) =
    self.setState(value.cint)

  method setFloatValue*(self: NSButton, value: cfloat) =
    self.setState(value.int.cint)

  method setDoubleValue*(self: NSButton, value: cdouble) =
    self.setState(value.int.cint)

  method performClick*(self: NSButton, sender: NSResponder) =
    discard sender
    if not self.enabled:
      return
    self.setNextState()
    let cb = self.onClick()
    if cb.isNil:
      return
    cb(self.value)

  method setPeriodicDelay*(
      self: NSButton, delay: cfloat, interval {.kw("interval").}: cfloat
  ) =
    self.periodicDelaySec = max(delay, 0.0)
    self.periodicIntervalSec = max(interval, 0.0)

  method periodicDelay*(self: NSButton): cfloat =
    self.periodicDelaySec

  method periodicInterval*(self: NSButton): cfloat =
    self.periodicIntervalSec

  method setButtonType*(self: NSButton, value: cint) =
    discard self
    discard value

  method setTitleWithMnemonic*(self: NSButton, value: NSString) =
    self.setTitle(stripMnemonicMarkers(value))

  method dealloc(self: NSButton) {.used.} =
    self.title = replacedOwnedId(self.title, nil)
    self.keyEqId = replacedOwnedId(self.keyEqId, nil)
    self.alternateTitle = replacedOwnedId(self.alternateTitle, nil)
    self.onClick = nil
    discard callSuperIdFrom(NSButton, self, getSelector("dealloc"))

proc new*(t: typedesc[NSButton]): NSButton =
  var allocated = NSButton.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc setTitle*(button: NSButton, value: string) =
  button.setTitle(ns(value))

proc setOnClick*(button: NSButton, cb: proc(sender: NSButton)) =
  if cb.isNil:
    button.onClick = nil
  else:
    button.onClick = proc(sender: ID) =
      cb(ownFromId[NSButton](sender))

proc click*(button: NSButton) =
  if not button.enabled():
    return
  if button.mixedAllowed():
    case button.stateValue()
    of NSOffState:
      button.stateValue = NSOnState
    of NSOnState:
      button.stateValue = NSMixedState
    else:
      button.stateValue = NSOffState
  else:
    if button.stateValue() == NSOnState:
      button.stateValue = NSOffState
    else:
      button.stateValue = NSOnState
  let cb = button.onClick()
  if not cb.isNil:
    cb(button.value)

proc getPeriodicDelay*(button: NSButton, delay: var cfloat, interval: var cfloat) =
  if button.isNil:
    delay = 0.0
    interval = 0.0
    return
  delay = button.periodicDelay()
  interval = button.periodicInterval()

