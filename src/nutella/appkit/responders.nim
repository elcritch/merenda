import ./runtime
import ./events

objcImpl:
  type NSResponder* = object of NSObject
    nextResp: NSResponder

  method init*(self: var NSResponder): NSResponder =
    result =
      asTypeRaw[NSResponder](callSuperIdFrom(NSResponder, self, getSelector("init")))
    if result.isNil:
      return
    result.nextResp = NSResponder(value: nil)

  method nextResponder*(self: NSResponder): NSResponder =
    if self.nextResp.isNil:
      return NSResponder(value: nil)
    retain(self.nextResp)

  method setNextResponder*(self: NSResponder, next: NSResponder) =
    if self.isNil:
      return
    self.nextResp = retain(next)

  method acceptsFirstResponder*(self: NSResponder): bool =
    false

  method becomeFirstResponder*(self: NSResponder): bool =
    true

  method resignFirstResponder*(self: NSResponder): bool =
    true

  method tryToPerform*(
      self: NSResponder, action: SEL, sender {.kw("with").}: NSObject
  ): bool =
    if self.isNil:
      return false
    var current = self
    var hopCount = 0
    while not current.isNil and hopCount < 4096:
      if performResponderSelector(current, action, sender):
        return true
      current = current.nextResponder()
      inc hopCount
    false

  method doCommandBySelector*(self: NSResponder, action: SEL) =
    let next = self.nextResponder()
    if not next.isNil and next.tryToPerform(action, self):
      return
    self.noResponderFor(action)

  method noResponderFor*(self: NSResponder, action: SEL) =
    discard

  method mouseDown*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseDown(event)
      return
    self.noResponderFor(getSelector("mouseDown:"))

  method mouseUp*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseUp(event)
      return
    self.noResponderFor(getSelector("mouseUp:"))

  method rightMouseDown*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.rightMouseDown(event)
      return
    self.noResponderFor(getSelector("rightMouseDown:"))

  method rightMouseUp*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.rightMouseUp(event)
      return
    self.noResponderFor(getSelector("rightMouseUp:"))

  method mouseMoved*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseMoved(event)
      return
    self.noResponderFor(getSelector("mouseMoved:"))

  method mouseDragged*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseDragged(event)
      return
    self.noResponderFor(getSelector("mouseDragged:"))

  method rightMouseDragged*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.rightMouseDragged(event)
      return
    self.noResponderFor(getSelector("rightMouseDragged:"))

  method mouseEntered*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseEntered(event)
      return
    self.noResponderFor(getSelector("mouseEntered:"))

  method mouseExited*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseExited(event)
      return
    self.noResponderFor(getSelector("mouseExited:"))

  method keyDown*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.keyDown(event)
      return
    self.noResponderFor(getSelector("keyDown:"))

  method keyUp*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.keyUp(event)
      return
    self.noResponderFor(getSelector("keyUp:"))

  method flagsChanged*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.flagsChanged(event)
      return
    self.noResponderFor(getSelector("flagsChanged:"))

  method scrollWheel*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.scrollWheel(event)
      return
    self.noResponderFor(getSelector("scrollWheel:"))

  method dealloc(self: NSResponder) {.used.} =
    self.nextResp = NSResponder(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSResponder, self, getSelector("dealloc"))
