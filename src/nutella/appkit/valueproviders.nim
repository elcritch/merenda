import ./runtime

type
  NSObjectValueProvider* =
    concept sender
        sender.objectValue() is NSObject

  NSStringValueProvider* =
    concept sender
        sender.stringValue() is NSString

  NSIntValueProvider* =
    concept sender
        sender.intValue() is cint

  NSIntegerValueProvider* =
    concept sender
        sender.integerValue() is int

  NSFloatValueProvider* =
    concept sender
        sender.floatValue() is float32

  NSDoubleValueProvider* =
    concept sender
        sender.doubleValue() is float
