import ../runtime

objcImpl:

  type NXResponder* = object of NSObject
    nextResp: ID

  method init*(self: var NXResponder): NXResponder =
    result =
      asType[NXResponder](callSuperIdFrom(NXResponder, self, getSelector("init")))
    if result.isNil:
      return
    result.nextResp = nil

  method nextResponder*(self: NXResponder): NXResponder =
    if self.nextResp.isNil:
      return NXResponder(value: nil)
    ownFromId[NXResponder](self.nextResp)

  method setNextResponder*(self: NXResponder, next: NXResponder) =
    if self.isNil:
      return
    self.nextResp = replacedOwnedId(self.nextResp, next.value)

  method acceptsFirstResponder*(self: NXResponder): bool =
    discard self
    false

  method becomeFirstResponder*(self: NXResponder): bool =
    discard self
    true

  method resignFirstResponder*(self: NXResponder): bool =
    discard self
    true

  method tryToPerform*(
      self: NXResponder, action: SEL, sender {.kw("with").}: NSObject
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

  method doCommandBySelector*(self: NXResponder, action: SEL) =
    let next = self.nextResponder()
    if not next.isNil and next.tryToPerform(action, self):
      return
    self.noResponderFor(action)

  method noResponderFor*(self: NXResponder, action: SEL) =
    discard self
    discard action

  method dealloc(self: NXResponder) {.used.} =
    self.nextResp = replacedOwnedId(self.nextResp, nil)
    clearIvarRefs(self)
    discard callSuperIdFrom(NXResponder, self, getSelector("dealloc"))
