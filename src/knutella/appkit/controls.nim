import std/strutils
import ./runtime

import ./views
import ./controllers
import ./cells

export views, controllers

objcImpl:
  type NSControl* = object of NSView
    xCell: NSCell
    xCurrentEditor: NSText
    xTarget {.set: setTarget, get: target.}: ID
    xAction {.set: setAction, get: action.}: SEL
    refusesFirstResponder {.set: setRefusesFirstResponder, get: refusesFirstResponder.}:
      bool
    alignment {.set: setAlignment, get: alignment.}: NSTextAlignment

  method init*(self: var NSControl): NSControl =
    result = asTypeRaw[NSControl](
      cast[proc(
        self: IDPtr, op: SEL, x: float32, y: float32, width: float32, height: float32
      ): IDPtr {.cdecl, varargs.}](objc_msgSend)(
        self.value, getSelector("initWithFrame:y:width:height:"), 0.0, 0.0, 1.0, 1.0
      )
    )

  method initWithFrame*(
      self: var NSControl,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ): NSControl =
    var superObj =
      ObjcSuper(receiver: self.value, superClass: getClass(NSControl).getSuperclass())
    result = asTypeRaw[NSControl](
      cast[proc(
        superObj: var ObjcSuper,
        op: SEL,
        x: float32,
        y: float32,
        width: float32,
        height: float32,
      ): IDPtr {.cdecl, varargs.}](objc_msgSendSuper)(
        superObj,
        getSelector("initWithFrame:y:width:height:"),
        x.float32,
        y.float32,
        max(width.float32, 0.0),
        max(height.float32, 0.0),
      )
    )
    if result.isNil:
      return
    result.xCell = NSCell(value: nil)
    result.xCurrentEditor = NSText(value: nil)
    #var defaultCell = NSCell.new()
    result.xCell = NSCell.new()
    #defaultCell.value = nil
    let cell = result.xCell
    if not cell.isNil:
      cell.setControlView(result.NSView)
      cell.setContinuous(false)
    result.xTarget.value = nil
    result.xAction = nil
    result.refusesFirstResponder = false
    result.alignment = NSNaturalTextAlignment

  method cell*(self: NSControl): NSCell =
    if self.isNil:
      return NSCell(value: nil)
    if self.xCell.isNil:
      var defaultCell = NSCell.new()
      self.xCell = move(defaultCell)
      if not self.xCell.isNil:
        let controlCell = self.xCell
        controlCell.setControlView(self.NSView)
        controlCell.setContinuous(false)
    self.xCell

  method setCell*(self: NSControl, cell: NSCell) =
    if self.isNil:
      return
    self.xCell = ownFromId[NSCell](cell.value)
    let bound = self.xCell
    if not bound.isNil:
      bound.setControlView(self.NSView)

  method isEnabled*(self: NSControl): bool =
    if self.isNil:
      return true
    let controlCell = self.cell()
    if controlCell.isNil:
      return true
    controlCell.isEnabled()

  method setEnabled*(self: NSControl, flag: bool) =
    if self.isNil:
      return
    let controlCell = self.cell()
    if controlCell.isNil:
      return
    controlCell.setEnabled(flag)

  method isContinuous*(self: NSControl): bool =
    if self.isNil:
      return false
    let controlCell = self.cell()
    if controlCell.isNil:
      return false
    controlCell.isContinuous()

  method setContinuous*(self: NSControl, flag: bool) =
    if self.isNil:
      return
    let controlCell = self.cell()
    if controlCell.isNil:
      return
    controlCell.setContinuous(flag)

  method currentEditor*(self: NSControl): NSText =
    if self.isNil:
      return NSText(value: nil)
    self.xCurrentEditor

  method acceptsFirstResponder*(self: NSControl): bool =
    if self.isNil:
      return false
    self.isEnabled() and (not self.refusesFirstResponder())

  method stringValue*(self: NSControl): NSString =
    @ns""

  method setStringValue*(self: NSControl, value: NSString) =
    discard

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

  method drawCell*(self: NSControl, cell: NSCell) =
    if self.xCell == cell:
      self.xCell.setControlView(self.NSView)
      self.xCell.drawWithFrame(self.xBounds, self.NSView)

  method drawCellInside*(self: NSControl, cell: NSCell) =
    if self.xCell == cell:
      self.xCell.drawInteriorWithFrame(self.xBounds, self.NSView)

  method updateCell*(self: NSControl, cell: NSCell) =
    if self.xCell == cell:
      self.setNeedsDisplay(true)

  method updateCellInside*(self: NSControl, cell: NSCell) =
    if self.xCell == cell:
      self.updateCell(cell)

  method drawRect*(self: NSControl, rect: NSRect) =
    self.xCell.setControlView(self.NSView)
    self.xCell.drawWithFrame(self.xBounds, self.NSView)

  method performClick*(self: NSControl, sender: NSResponder) =
    discard

  method sendAction*(self: NSControl, action: SEL, target {.kw("to").}: ID): bool =
    if not target.isNil:
      return performResponderSelector(target.NSObject, action, self.NSObject)
    self.NSResponder.tryToPerform(action, self.NSObject)

  method dealloc(self: NSControl) {.used.} =
    self.xCell = NSCell(value: nil)
    self.xCurrentEditor = NSText(value: nil)
    self.xTarget.value = nil
    self.xAction = nil
    destroyIvarFields(self)
    discard callSuperIdFrom(NSControl, self, getSelector("dealloc"))

proc new*(t: typedesc[NSControl]): NSControl =
  var allocated = NSControl.alloc()
  result = initOwned(move(allocated))

proc setFrame*[T: SomeNumber](self: NSControl, x, y, width, height: T) =
  self.NSView.setFrame(nsRect(x.float32, y.float32, width.float32, height.float32))

proc setStringValue*(control: NSControl, value: string) =
  control.setStringValue(ns(value))
