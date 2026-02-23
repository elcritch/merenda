import std/strutils
import ./runtime

import ./views

export views

objcImpl:
  type NSControl* = object of NSView
    enabled {.set: setEnabled, get: isEnabled.}: bool
    continuous {.set: setContinuous, get: isContinuous.}: bool
    refusesFirstResponder {.set: setRefusesFirstResponder, get: refusesFirstResponder.}:
      bool
    alignment {.set: setAlignment, get: alignment.}: NSTextAlignment

  method init*(self: var NSControl): NSControl =
    result = asType[NSControl](callSuperIdFrom(NSControl, self, @selector("init")))

    if result.isNil:
      return
    result.enabled = true
    result.continuous = false
    result.refusesFirstResponder = false
    result.alignment = NSNaturalTextAlignment

  method acceptsFirstResponder*(self: NSControl): bool =
    if self.isNil:
      return false
    self.isEnabled() and (not self.refusesFirstResponder())

  method stringValue*(self: NSControl): NSString =
    discard self
    @ns""

  method setStringValue*(self: NSControl, value: NSString) =
    discard self
    discard value

  method intValue*(self: NSControl): cint =
    if self.isNil:
      return 0.cint
    try:
      parseInt($self.stringValue()).cint
    except ValueError:
      0.cint

  method integerValue*(self: NSControl): int =
    self.intValue().int

  method floatValue*(self: NSControl): cfloat =
    if self.isNil:
      return 0.0
    try:
      parseFloat($self.stringValue()).cfloat
    except ValueError:
      0.0

  method doubleValue*(self: NSControl): cdouble =
    if self.isNil:
      return 0.0
    try:
      parseFloat($self.stringValue()).cdouble
    except ValueError:
      0.0

  method setIntValue*(self: NSControl, value: cint) =
    if self.isNil:
      return
    self.setStringValue(ns($value))

  method setIntegerValue*(self: NSControl, value: int) =
    self.setIntValue(value.cint)

  method setFloatValue*(self: NSControl, value: cfloat) =
    if self.isNil:
      return
    self.setStringValue(ns($value))

  method setDoubleValue*(self: NSControl, value: cdouble) =
    if self.isNil:
      return
    self.setStringValue(ns($value))

  method takeStringValueFrom*(self: NSControl, sender: NSControl) =
    if self.isNil or sender.isNil:
      return
    self.setStringValue(sender.stringValue())

  method takeIntValueFrom*(self: NSControl, sender: NSControl) =
    if self.isNil or sender.isNil:
      return
    self.setIntValue(sender.intValue())

  method takeIntegerValueFrom*(self: NSControl, sender: NSControl) =
    if self.isNil or sender.isNil:
      return
    self.setIntegerValue(sender.integerValue())

  method takeFloatValueFrom*(self: NSControl, sender: NSControl) =
    if self.isNil or sender.isNil:
      return
    self.setFloatValue(sender.floatValue())

  method takeDoubleValueFrom*(self: NSControl, sender: NSControl) =
    if self.isNil or sender.isNil:
      return
    self.setDoubleValue(sender.doubleValue())

  method performClick*(self: NSControl, sender: NSResponder) =
    discard self
    discard sender

proc new*(t: typedesc[NSControl]): NSControl =
  var allocated = NSControl.alloc()
  result = allocated.init()
  allocated.value = nil

proc setStringValue*(control: NSControl, value: string) =
  control.setStringValue(ns(value))
