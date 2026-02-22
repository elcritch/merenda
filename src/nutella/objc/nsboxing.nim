proc retainNSObject(value: NSObject): NSObject {.inline.} =
  if value.value.isNil:
    return NSObject(value: nil)
  let retainSend = cast[proc(self: ID, op: SEL): ID {.cdecl, varargs.}](objc_msgSend)
  NSObject(value: retainSend(value.value, sel_registerName("retain")))

objcImpl:
  type NXInteger* = object of NSObject
    num: int

  method init*(self: var NXInteger): NXInteger =
    result = callSuperAs[NXInteger](self, getSelector("init"))
    if result.isNil:
      return

  method dealloc*(self: NXInteger) =
    clearIvarRefs(self)
    discard callSuperAs[ID](self, getSelector("dealloc"))

  method integerValue*(self: NXInteger): NSInteger =
    self.num().NSInteger

  method setIntegerValue*(self: NXInteger, value: NSInteger) =
    self.num = value.int

  method hash*(self: NXInteger): NSUInteger =
    hash(self.num()).NSUInteger

  method isEqual*(self: NXInteger, other: NSObject): bool =
    if self.value == other.value:
      return true
    if other.isNil or not other.respondsToSelector("integerValue"):
      return false
    let toInt = cast[proc(obj: ID, op: SEL): NSInteger {.cdecl, varargs.}](objc_msgSend)
    let value = toInt(other.value, sel_registerName("integerValue"))
    self.integerValue() == value

proc nsInteger*[T: SomeInteger](value: T): NXInteger =
  var allocated = NXInteger.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NXInteger(value: nil)
  created.setIntegerValue(value.NSInteger)
  result = asType[NXInteger](created.value)
  created.value = nil

proc nsDispatch(value: NSString): NSString {.inline.} =
  value

proc nsDispatch(value: NSObject): NSObject {.inline.} =
  value

proc nsDispatch(value: sink string): NSString {.inline.} =
  nsString(value)

proc nsDispatch(value: cstring): NSString {.inline.} =
  if value.isNil:
    return nsString("")
  nsString($value)

proc nsDispatch[T: SomeInteger](value: T): NXInteger {.inline.} =
  nsInteger(value)

template ns*(value: untyped): untyped =
  nsDispatch(value)

template `@`*(value: untyped): untyped =
  ## Enables ergonomic calls like `@ns"foo"`.
  value

proc boxNSObject*[T](value: T): NSObject {.inline.} =
  when T is NSObject:
    retainNSObject(asType[NSObject](value))
  elif T is string:
    let boxed = ns(value)
    retainNSObject(asType[NSObject](boxed))
  elif T is cstring:
    let boxed = ns(value)
    retainNSObject(asType[NSObject](boxed))
  elif T is SomeInteger:
    let boxed = ns(value)
    retainNSObject(asType[NSObject](boxed))
  else:
    {.fatal: "@ns boxing supports NSObject, string/cstring, and integer values".}

proc unboxNSObject*[T](value: NSObject): T {.inline.} =
  when T is NSObject:
    if value.isNil:
      return T(value: nil)
    let retainSend = cast[proc(self: ID, op: SEL): ID {.cdecl, varargs.}](objc_msgSend)
    T(value: retainSend(value.value, sel_registerName("retain")))
  elif T is string:
    stringValue(asType[NSString](value))
  elif T is SomeInteger:
    if value.isNil:
      return T(0)
    if not value.respondsToSelector("integerValue"):
      return T(0)
    let toInt = cast[proc(obj: ID, op: SEL): NSInteger {.cdecl, varargs.}](objc_msgSend)
    T(toInt(value.value, sel_registerName("integerValue")))
  else:
    {.fatal: "@ns unboxing supports NSObject, string, and integer values".}
