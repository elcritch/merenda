import ./runtime

objcImpl:
  type NSParagraphStyle* = object of NSObject
    xLineBreakMode {.set: setLineBreakMode, get: lineBreakMode.}: NSLineBreakMode
    xAlignment {.set: setAlignment, get: alignment.}: NSTextAlignment

  method init*(self: var NSParagraphStyle): NSParagraphStyle =
    result = asTypeRaw[NSParagraphStyle](
      callSuperIdFrom(NSParagraphStyle, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.xLineBreakMode = NSLineBreakByWordWrapping
    result.xAlignment = NSNaturalTextAlignment

  method copyWithZone*(self: NSParagraphStyle, zone: pointer): NSParagraphStyle =
    retain(self)

  method mutableCopyWithZone*(
      self: NSParagraphStyle, zone: pointer
  ): NSMutableParagraphStyle =
    var allocated = NSMutableParagraphStyle.alloc()
    result = allocated.init()
    allocated.value = nil
    if result.isNil:
      return
    result.setLineBreakMode(self.lineBreakMode())
    result.setAlignment(self.alignment())

  method dealloc(self: NSParagraphStyle) {.used.} =
    discard callSuperIdFrom(NSParagraphStyle, self, getSelector("dealloc"))

objcImpl:
  type NSMutableParagraphStyle* = object of NSParagraphStyle

  method init*(self: var NSMutableParagraphStyle): NSMutableParagraphStyle =
    result = asTypeRaw[NSMutableParagraphStyle](
      callSuperIdFrom(NSMutableParagraphStyle, self, getSelector("init"))
    )

  method dealloc(self: NSMutableParagraphStyle) {.used.} =
    discard callSuperIdFrom(NSMutableParagraphStyle, self, getSelector("dealloc"))

proc defaultParagraphStyle*(t: typedesc[NSParagraphStyle]): NSParagraphStyle =
  var allocated = NSParagraphStyle.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSMutableParagraphStyle]): NSMutableParagraphStyle =
  var allocated = NSMutableParagraphStyle.alloc()
  result = initOwned(move(allocated))
