import std/hashes

type NXStringStorage = ref object
  value: string

objcImpl:
  type NXString* = object of NSObject
    backingStore: NXStringStorage

  method init*(self: var NXString): NXString =
    result = callSuperAs[NXString](self, getSelector("init"))
    if result.isNil:
      return
    result.backingStore = NXStringStorage(value: "")

  method dealloc*(self: NXString) =
    clearIvarRefs(self)
    discard callSuperAs[ID](self, getSelector("dealloc"))

  method stringValue*(self: NXString): string =
    let store = self.backingStore()
    if store.isNil:
      return ""
    store.value

  method setStringValue*(self: NXString, value: string) =
    let store = self.backingStore()
    if store.isNil:
      return
    store.value = value

  method UTF8String*(self: NXString): cstring =
    objcStableCString(self.stringValue())

  method length*(self: NXString): NSUInteger =
    self.stringValue().len.NSUInteger

proc nsString*(value: sink string): NSString =
  var allocated = NXString.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NSString(value: nil)
  let store = created.backingStore()
  if not store.isNil:
    store.value = value
  result = asType[NSString](created.value)
  created.value = nil

proc toNSString*(value: string): NSString {.inline.} =
  nsString(value)

proc stringValue*(value: NSString): string =
  if value.isNil:
    return ""
  let toUtf8 = cast[proc(self: ID, op: SEL): cstring {.cdecl, varargs.}](objc_msgSend)
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
