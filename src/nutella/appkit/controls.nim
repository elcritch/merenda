import ./runtime

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

proc new*(t: typedesc[NSControl]): NSControl =
  var allocated = NSControl.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

