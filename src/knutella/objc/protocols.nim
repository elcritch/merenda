objcImpl:
  type NSCopying* =
    concept self
        method copyWithZone*(self: NSCopying, zone: pointer): NSObject

objcImpl:
  type IntValue* {.structural.} =
    concept self
        method intValue*(self: IntValue): int

