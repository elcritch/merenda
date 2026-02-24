import std/strutils
import ./runtime

import ./views
import ./controllers
import ./cells

export views, controllers

objcImpl:
  type NSControl* = object of NSView
    xxCell: ID
    xxCurrentEditor: NSText
    refusesFirstResponder {.set: setRefusesFirstResponder, get: refusesFirstResponder.}:
      bool
    alignment {.set: setAlignment, get: alignment.}: NSTextAlignment

  method init*(self: var NSControl): NSControl =
    result = asType[NSControl](callSuperIdFrom(NSControl, self, @selector("init")))

    if result.isNil:
      return
    result.xxCell = nil
    result.xxCurrentEditor = NSText(value: nil)
    var defaultCell = NSCell.new()
    result.xxCell = replacedOwnedId(result.xxCell, defaultCell.value)
    let cell = ownFromId[NSCell](result.xxCell)
    if not cell.isNil:
      cell.setControlView(asType[NSView](result))
      cell.setContinuous(false)
    defaultCell.value = nil
    result.refusesFirstResponder = false
    result.alignment = NSNaturalTextAlignment

  method cell*(self: NSControl): ID =
    if self.isNil:
      return nil
    if self.xxCell.isNil:
      var defaultCell = NSCell.new()
      self.xxCell = replacedOwnedId(self.xxCell, defaultCell.value)
      if not self.xxCell.isNil:
        let controlCell = ownFromId[NSCell](self.xxCell)
        controlCell.setControlView(asType[NSView](self))
        controlCell.setContinuous(false)
      defaultCell.value = nil
    self.xxCell

  method setCell*(self: NSControl, cell: NSCell) =
    if self.isNil:
      return
    self.xxCell = replacedOwnedId(self.xxCell, cell.value)
    let bound = ownFromId[NSCell](self.xxCell)
    if not bound.isNil:
      bound.setControlView(asType[NSView](self))

  method isEnabled*(self: NSControl): bool =
    if self.isNil:
      return true
    let controlCell = ownFromId[NSCell](self.cell())
    if controlCell.isNil:
      return true
    controlCell.isEnabled()

  method setEnabled*(self: NSControl, flag: bool) =
    if self.isNil:
      return
    let controlCell = ownFromId[NSCell](self.cell())
    if controlCell.isNil:
      return
    controlCell.setEnabled(flag)

  method isContinuous*(self: NSControl): bool =
    if self.isNil:
      return false
    let controlCell = ownFromId[NSCell](self.cell())
    if controlCell.isNil:
      return false
    controlCell.isContinuous()

  method setContinuous*(self: NSControl, flag: bool) =
    if self.isNil:
      return
    let controlCell = ownFromId[NSCell](self.cell())
    if controlCell.isNil:
      return
    controlCell.setContinuous(flag)

  method currentEditor*(self: NSControl): NSText =
    if self.isNil:
      return NSText(value: nil)
    self.xxCurrentEditor

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

  method floatValue*(self: NSControl): float32 =
    if self.isNil:
      return 0.0
    try:
      parseFloat($self.stringValue()).float32
    except ValueError:
      0.0

  method doubleValue*(self: NSControl): float =
    if self.isNil:
      return 0.0
    try:
      parseFloat($self.stringValue()).float
    except ValueError:
      0.0

  method setIntValue*(self: NSControl, value: cint) =
    if self.isNil:
      return
    self.setStringValue(ns($value))

  method setIntegerValue*(self: NSControl, value: int) =
    self.setIntValue(value.cint)

  method setFloatValue*(self: NSControl, value: float32) =
    if self.isNil:
      return
    self.setStringValue(ns($value))

  method setDoubleValue*(self: NSControl, value: float) =
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

  method dealloc(self: NSControl) {.used.} =
    self.xxCell = replacedOwnedId(self.xxCell, nil)
    self.xxCurrentEditor = NSText(value: nil)
    clearIvarRefs(self)
    discard callSuperIdFrom(NSControl, self, getSelector("dealloc"))

proc new*(t: typedesc[NSControl]): NSControl =
  var allocated = NSControl.alloc()
  result = initOwned(move(allocated))

proc setStringValue*(control: NSControl, value: string) =
  control.setStringValue(ns(value))
