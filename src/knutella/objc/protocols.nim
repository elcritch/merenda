objcImpl:
  type NSCopying* =
    concept self
        method copyWithZone*(self: NSCopying, zone: pointer): NSObject

objcImpl:
  type IntValue* {.structural.} =
    concept self
        method intValue*(self: IntValue): int

objcImpl:
  type IntegerValue* {.structural.} =
    concept self
        method integerValue*(self: IntegerValue): int

objcImpl:
  type FloatValue* {.structural.} =
    concept self
        method floatValue*(self: FloatValue): float32

objcImpl:
  type DoubleValue* {.structural.} =
    concept self
        method doubleValue*(self: DoubleValue): float64

objcImpl:
  type StringValue* {.structural.} =
    concept self
        method strings*(self: StringValue): NSString {.name: "string".}

objcImpl:
  type DescriptionValue* {.structural.} =
    concept self
        method description*(self: DescriptionValue): NSString

