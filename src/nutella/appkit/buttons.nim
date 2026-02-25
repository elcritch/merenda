import ./runtime

import ./controls

export controls

type NSButtonCallbackProc = proc(sender: IDPtr)

objcImpl:
  type NSButton* = object of NSControl
    title {.set: setTitle.}: NSString
    alternateTitle {.set: setAlternateTitle.}: NSString
    keyEquivalent {.set: setKeyEquivalent.}: NSString

    bordered {.get: isBordered.}: bool
    bezeled {.get: isBezeled.}: bool
    bezelStyle {.set: setBezelStyle.}: int # NSBezelStyle

    stateValue {.get: state.}: int
    mixedAllowed {.get: allowsMixedState.}: bool
    transparent {.set: setTransparent, get: isTransparent.}: bool
    keyEquivalentModifierMask {.set: setKeyEquivalentModifierMask.}: int
      # NSEventModifierFlags

    imagePos {.set: setImagePosition, get: imagePosition.}: int

    showBorderInside {.
      set: setShowsBorderOnlyWhileMouseInside, get: showsBorderOnlyWhileMouseInside
    .}: bool
    periodicDelaySec: float32
    periodicIntervalSec: float32
    onClick: NSButtonCallbackProc

  method init*(self: var NSButton): NSButton =
    result = asType[NSButton](callSuperIdFrom(NSButton, self, getSelector("init")))
    if result.isNil:
      return
    result.setEnabled(true)
    result.setAlignment(NSNaturalTextAlignment)
    result.title = @ns"Button"
    result.stateValue = NSOffState
    result.mixedAllowed = false
    result.bordered = true
    result.bezeled = true
    result.transparent = false
    result.keyEquivalent = @ns""
    result.keyEquivalentModifierMask = 0
    result.imagePos = 0
    result.bezelStyle = 0
    result.alternateTitle = @ns""
    result.showBorderInside = false
    result.periodicDelaySec = 0.0
    result.periodicIntervalSec = 0.0
    result.onClick = nil

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

  method floatValue*(self: NSButton): float32 =
    self.state().float32

  method doubleValue*(self: NSButton): float =
    self.state().float

  method setIntValue*(self: NSButton, value: cint) =
    self.setState(value)

  method setIntegerValue*(self: NSButton, value: int) =
    self.setState(value.cint)

  method setFloatValue*(self: NSButton, value: float32) =
    self.setState(value.int.cint)

  method setDoubleValue*(self: NSButton, value: float) =
    self.setState(value.int.cint)

  method performClick*(self: NSButton, sender: NSResponder) =
    if not self.isEnabled():
      return
    self.setNextState()
    let cb = self.onClick()
    if cb.isNil:
      return
    cb(self.value)

  method setPeriodicDelay*(
      self: NSButton, delay: float32, interval {.kw("interval").}: float32
  ) =
    self.periodicDelaySec = max(delay, 0.0)
    self.periodicIntervalSec = max(interval, 0.0)

  method periodicDelay*(self: NSButton): float32 =
    self.periodicDelaySec

  method periodicInterval*(self: NSButton): float32 =
    self.periodicIntervalSec

  method setButtonType*(self: NSButton, value: cint) =
    discard

  method setTitleWithMnemonic*(self: NSButton, value: NSString) =
    self.setTitle(stripMnemonicMarkers(value))

  method dealloc(self: NSButton) {.used.} =
    self.onClick = nil
    discard callSuperIdFrom(NSButton, self, getSelector("dealloc"))

proc new*(t: typedesc[NSButton]): NSButton =
  var allocated = NSButton.alloc()
  result = initOwned(move(allocated))

proc setTitle*(button: NSButton, value: string) =
  button.setTitle(ns(value))

proc setOnClick*(button: NSButton, cb: proc(sender: NSButton)) =
  if cb.isNil:
    button.onClick = nil
  else:
    button.onClick = proc(sender: IDPtr) =
      cb(ownFromId[NSButton](sender))

proc click*(button: NSButton) =
  if not button.isEnabled():
    return
  if button.allowsMixedState():
    case button.state()
    of NSOffState:
      button.setState(NSOnState)
    of NSOnState:
      button.setState(NSMixedState)
    else:
      button.setState(NSOffState)
  else:
    if button.state() == NSOnState:
      button.setState(NSOffState)
    else:
      button.setState(NSOnState)
  let cb = button.onClick()
  if not cb.isNil:
    cb(button.value)

proc getPeriodicDelay*(button: NSButton, delay: var float32, interval: var float32) =
  if button.isNil:
    delay = 0.0
    interval = 0.0
    return
  delay = button.periodicDelay()
  interval = button.periodicInterval()
