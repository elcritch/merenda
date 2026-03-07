import ./runtime

import ./views
import ./controllers
import ./cells

export views, controllers

objcImpl:
  type NSControl* = object of NSView
    xCell: NSCell
    xCurrentEditor: NSText
    xTag {.set: setTag, get: tag.}: int

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
    self.xCell = cell
    let bound = self.xCell
    if not bound.isNil:
      bound.setControlView(self.NSView)
      bound.setContinuous(false)

  method selectedCell*(self: NSControl): NSCell =
    self.cell()

  method target*(self: NSControl): ID =
    self.cell().target()

  method action*(self: NSControl): SEL =
    self.cell().action()

  method setTarget*(self: NSControl, target: ID) =
    self.cell().setTarget(target)

  method setAction*(self: NSControl, action: SEL) =
    self.cell().setAction(action)

  method font*(self: NSControl): NSFont =
    self.cell().font()

  method setFont*(self: NSControl, font: NSFont) =
    self.cell().setFont(font)
    self.setNeedsDisplay(true)

  method image*(self: NSControl): NSImage =
    self.cell().image()

  method setImage*(self: NSControl, image: NSImage) =
    self.cell().setImage(image)
    self.setNeedsDisplay(true)

  method alignment*(self: NSControl): NSTextAlignment =
    self.cell().alignment()

  method setAlignment*(self: NSControl, alignment: NSTextAlignment) =
    self.cell().setAlignment(alignment)
    self.setNeedsDisplay(true)

  method isEnabled*(self: NSControl): bool =
    self.cell().isEnabled()

  method isEditable*(self: NSControl): bool =
    self.cell().isEditable()

  method isSelectable*(self: NSControl): bool =
    self.cell().isSelectable()

  method isScrollable*(self: NSControl): bool =
    self.cell().isScrollable()

  method isBordered*(self: NSControl): bool =
    self.cell().isBordered()

  method isBezeled*(self: NSControl): bool =
    self.cell().isBezeled()

  method setEnabled*(self: NSControl, flag: bool) =
    self.cell().setEnabled(flag)
    self.setNeedsDisplay(true)

  method setEditable*(self: NSControl, flag: bool) =
    self.cell().setEditable(flag)

  method setSelectable*(self: NSControl, flag: bool) =
    self.cell().setSelectable(flag)

  method setScrollable*(self: NSControl, flag: bool) =
    self.cell().setScrollable(flag)

  method setBordered*(self: NSControl, flag: bool) =
    self.cell().setBordered(flag)
    self.setNeedsDisplay(true)

  method setBezeled*(self: NSControl, flag: bool) =
    self.cell().setBezeled(flag)
    self.setNeedsDisplay(true)

  method isContinuous*(self: NSControl): bool =
    self.cell().isContinuous()

  method setContinuous*(self: NSControl, flag: bool) =
    self.cell().setContinuous(flag)

  method refusesFirstResponder*(self: NSControl): bool =
    self.cell().refusesFirstResponder()

  method setRefusesFirstResponder*(self: NSControl, flag: bool) =
    self.cell().setRefusesFirstResponder(flag)

  method formatter*(self: NSControl): NSFormatter =
    self.cell().formatter()

  method setFormatter*(self: NSControl, formatter: NSFormatter) =
    self.cell().setFormatter(formatter)
    self.setNeedsDisplay(true)

  method objectValue*(self: NSControl): NSObject =
    self.selectedCell().objectValue()

  method setObjectValue*(self: NSControl, value: NSObject) =
    self.selectedCell().setObjectValue(value)
    self.setNeedsDisplay(true)

  method currentEditor*(self: NSControl): NSText =
    if self.isNil:
      return NSText(value: nil)
    self.xCurrentEditor

  method acceptsFirstResponder*(self: NSControl): bool =
    self.isEnabled() and (not self.refusesFirstResponder())

  method stringValue*(self: NSControl): NSString =
    self.selectedCell().stringValue()

  method setStringValue*(self: NSControl, value: NSString) =
    let selected = self.selectedCell()
    if selected.respondsToSelector("setTitle:"):
      cast[proc(self: IDPtr, op: SEL, title: IDPtr) {.cdecl, varargs.}](objc_msgSend)(
        selected.value, getSelector("setTitle:"), value.value
      )
    else:
      selected.setStringValue(value)
    self.setNeedsDisplay(true)

  method intValue*(self: NSControl): cint =
    self.selectedCell().intValue()

  method integerValue*(self: NSControl): int =
    self.selectedCell().integerValue()

  method floatValue*(self: NSControl): float32 =
    self.selectedCell().floatValue()

  method doubleValue*(self: NSControl): float =
    self.selectedCell().doubleValue()

  method attributedStringValue*(self: NSControl): NSAttributedString =
    self.selectedCell().attributedStringValue()

  method setIntValue*(self: NSControl, value: cint) =
    self.selectedCell().setIntValue(value)
    self.setNeedsDisplay(true)

  method setIntegerValue*(self: NSControl, value: int) =
    self.selectedCell().setIntegerValue(value)
    self.setNeedsDisplay(true)

  method setFloatValue*(self: NSControl, value: float32) =
    self.selectedCell().setFloatValue(value)
    self.setNeedsDisplay(true)

  method setDoubleValue*(self: NSControl, value: float) =
    self.selectedCell().setDoubleValue(value)
    self.setNeedsDisplay(true)

  method setAttributedStringValue*(self: NSControl, value: NSAttributedString) =
    self.selectedCell().setAttributedStringValue(value)
    self.setNeedsDisplay(true)

  method selectedTag*(self: NSControl): int =
    self.selectedCell().tag()

  method setFloatingPointFormat*(
      self: NSControl, fpp: bool, left {.kw("left").}: uint, right {.kw("right").}: uint
  ) =
    self.cell().setFloatingPointFormat(fpp, left = left, right = right)

  method takeObjectValueFrom*(self: NSControl, sender: NSControl) =
    self.selectedCell().takeObjectValueFrom(sender.cell())
    self.setNeedsDisplay(true)

  method takeStringValueFrom*(self: NSControl, sender: NSControl) =
    self.selectedCell().takeStringValueFrom(sender.cell())
    self.setNeedsDisplay(true)

  method takeIntValueFrom*(self: NSControl, sender: NSControl) =
    self.selectedCell().takeIntValueFrom(sender.cell())
    self.setNeedsDisplay(true)

  method takeIntegerValueFrom*(self: NSControl, sender: NSControl) =
    self.selectedCell().takeIntegerValueFrom(sender.cell())
    self.setNeedsDisplay(true)

  method takeFloatValueFrom*(self: NSControl, sender: NSControl) =
    self.selectedCell().takeFloatValueFrom(sender.cell())
    self.setNeedsDisplay(true)

  method takeDoubleValueFrom*(self: NSControl, sender: NSControl) =
    self.selectedCell().takeDoubleValueFrom(sender.cell())
    self.setNeedsDisplay(true)

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

  method mouseDown*(self: NSControl, event: NSEvent) =
    if self.isNil or event.isNil or not self.isEnabled():
      return
    let controlCell = self.cell()
    if controlCell.isNil:
      return
    let frame = self.bounds()
    controlCell.highlight(true, frame, self.NSView)
    self.setNeedsDisplay(true)

    let tracked = controlCell.trackMouse(event, frame, self.NSView, untilMouseUp = true)

    controlCell.highlight(false, frame, self.NSView)
    self.setNeedsDisplay(true)
    if not tracked:
      return

    if controlCell.respondsToSelector("performClick:"):
      cast[proc(self: IDPtr, op: SEL, sender: IDPtr) {.cdecl, varargs.}](objc_msgSend)(
        controlCell.value, getSelector("performClick:"), self.value
      )
    else:
      discard self.sendAction(self.action(), self.target())

  method performClick*(self: NSControl, sender: NSResponder) =
    discard sender
    discard self.sendAction(self.action(), self.target())

  method sendAction*(self: NSControl, action: SEL, target {.kw("to").}: ID): bool =
    if not target.isNil:
      return performResponderSelector(target.NSObject, action, self.NSObject)
    self.NSResponder.tryToPerform(action, self.NSObject)

  method dealloc(self: NSControl) {.used.} =
    self.xCell = NSCell(value: nil)
    self.xCurrentEditor = NSText(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSControl, self, getSelector("dealloc"))

proc new*(t: typedesc[NSControl]): NSControl =
  var allocated = NSControl.alloc()
  result = initOwned(move(allocated))

proc setFrame*[T: SomeNumber](self: NSControl, x, y, width, height: T) =
  self.NSView.setFrame(nsRect(x.float32, y.float32, width.float32, height.float32))

proc setStringValue*(control: NSControl, value: string) =
  control.setStringValue(ns(value))
