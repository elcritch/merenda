import ./runtime

objcImpl:

  type NSResponder* = object of NSObject
    nextResp: ID

  method init*(self: var NSResponder): NSResponder =
    result =
      asType[NSResponder](callSuperIdFrom(NSResponder, self, getSelector("init")))
    if result.isNil:
      return
    result.nextResp = nil

  method nextResponder*(self: NSResponder): NSResponder =
    if self.nextResp.isNil:
      return NSResponder(value: nil)
    ownFromId[NSResponder](self.nextResp)

  method setNextResponder*(self: NSResponder, next: NSResponder) =
    if self.isNil:
      return
    self.nextResp = replacedOwnedId(self.nextResp, next.value)

  method acceptsFirstResponder*(self: NSResponder): bool =
    discard self
    false

  method becomeFirstResponder*(self: NSResponder): bool =
    discard self
    true

  method resignFirstResponder*(self: NSResponder): bool =
    discard self
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
    discard self
    discard action

  method dealloc(self: NSResponder) {.used.} =
    self.nextResp = replacedOwnedId(self.nextResp, nil)
    clearIvarRefs(self)
    discard callSuperIdFrom(NSResponder, self, getSelector("dealloc"))
