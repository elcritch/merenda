objcImpl:
  type NSCopying* =
    concept self
        method copyWithZone*(self: NSCopying, zone: pointer): NSObject
