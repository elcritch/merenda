import std/strutils

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

proc objectFloatValue*(obj: NSObject): float32 =
  if obj.isNil:
    return 0.0

  let floatProvider = asProto[NSFloatValueProvider](obj)
  if not floatProvider.isNil:
    return floatProvider.floatValue()

  let doubleProvider = asProto[NSDoubleValueProvider](obj)
  if not doubleProvider.isNil:
    return doubleProvider.doubleValue().float32

  let stringProvider = asProto[NSStringValueProvider](obj)
  if not stringProvider.isNil:
    try:
      return parseFloat($stringProvider.stringValue()).float32
    except ValueError:
      return 0.0

  if obj.respondsToSelector("floatValue"):
    return cast[proc(self: IDPtr, op: SEL): float32 {.cdecl, varargs.}](objc_msgSend)(
      obj.value, getSelector("floatValue")
    )
  if obj.respondsToSelector("doubleValue"):
    return cast[proc(self: IDPtr, op: SEL): cdouble {.cdecl, varargs.}](objc_msgSend)(
      obj.value, getSelector("doubleValue")
    ).float32
  if obj.respondsToSelector("stringValue"):
    let text = cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs.}](objc_msgSend)(
      obj.value, getSelector("stringValue")
    )
    if not text.isNil:
      try:
        return parseFloat($ownFromId[NSString](text)).float32
      except ValueError:
        return 0.0
  0.0
