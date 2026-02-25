import ./runtime

objcImpl:
  type NSObjectValueProvider* =
    concept self
        method objectValue*(self: NSObjectValueProvider): NSObject

objcImpl:
  type NSStringValueProvider* =
    concept self
        method stringValue*(self: NSStringValueProvider): NSString

objcImpl:
  type NSIntValueProvider* =
    concept self
        method intValue*(self: NSIntValueProvider): cint

objcImpl:
  type NSIntegerValueProvider* =
    concept self
        method integerValue*(self: NSIntegerValueProvider): int

objcImpl:
  type NSFloatValueProvider* =
    concept self
        method floatValue*(self: NSFloatValueProvider): float32

objcImpl:
  type NSDoubleValueProvider* =
    concept self
        method doubleValue*(self: NSDoubleValueProvider): float
