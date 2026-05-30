import std/hashes

objcImpl:
  type NXString* {.impl: NSCopying.} = object of NSObject
    text: string

  method init*(self: var NXString): NXString =
    result = callSuperAs[NXString](self, getSelector("init"))
    if result.isNil:
      return

  method dealloc*(self: NXString) =
    destroyIvarFields(self)
    discard callSuperAs[IDPtr](self, getSelector("dealloc"))

  method stringValue*(self: NXString): string =
    self.text()

  method setStringValue*(self: NXString, value: string) =
    self.text = value

  method UTF8String*(self: NXString): cstring =
    objcStableCString(self.stringValue())

  method length*(self: NXString): NSUInteger =
    self.stringValue().len.NSUInteger

  method hash*(self: NXString): NSUInteger =
    hash(self.stringValue()).NSUInteger

  method isEqual*(self: NXString, other: NSObject): bool =
    if self.value == other.value:
      return true
    if other.isNil or not other.respondsToSelector("UTF8String"):
      return false
    let toUtf8 =
      cast[proc(obj: IDPtr, op: SEL): cstring {.cdecl, varargs.}](objc_msgSend)
    let utf8 = toUtf8(other.value, sel_registerName("UTF8String"))
    if utf8.isNil:
      return false
    self.stringValue() == $utf8

  method copyWithZone*(self: NXString, zone: pointer): NSObject =
    retain(self).NSObject

proc nsString*(value: sink string): NSString =
  var allocated = NXString.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NSString(value: nil)
  created.text = value
  result = asTypeRaw[NSString](move(created.value))

proc toNSString*(value: string): NSString {.inline.} =
  nsString(value)

proc stringValue*(value: NSString): string =
  if value.isNil:
    return ""
  let toUtf8 =
    cast[proc(self: IDPtr, op: SEL): cstring {.cdecl, varargs.}](objc_msgSend)
  let utf8 = toUtf8(value.value, sel_registerName("UTF8String"))
  if utf8.isNil:
    return ""
  $utf8

proc toString*(value: NSString): string {.inline.} =
  stringValue(value)

proc len*(value: NSString): int {.inline.} =
  stringValue(value).len

proc isEmpty*(value: NSString): bool {.inline.} =
  value.len == 0

proc hash*(value: NSString): Hash {.inline.} =
  hash(stringValue(value))

proc `==`*(a, b: NSString): bool {.inline.} =
  if a.value == b.value:
    return true
  stringValue(a) == stringValue(b)

proc `&`*(a, b: NSString): NSString {.inline.} =
  nsString(stringValue(a) & stringValue(b))

proc `$`*(value: NSString): string {.inline.} =
  stringValue(value)
