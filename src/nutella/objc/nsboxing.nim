proc retainNSObjectId(value: ID): NSObject {.inline.} =
  if value.isNil:
    return NSObject(value: nil)
  let retainSend = cast[proc(self: ID, op: SEL): ID {.cdecl, varargs.}](objc_msgSend)
  NSObject(value: retainSend(value, sel_registerName("retain")))

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

  method floatValue*(self: NXInteger): cfloat =
    self.num().cfloat

  method doubleValue*(self: NXInteger): cdouble =
    self.num().cdouble

  method boolValue*(self: NXInteger): bool =
    self.num() != 0

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

objcImpl:
  type NXDouble* = object of NSObject
    num: cdouble

  method init*(self: var NXDouble): NXDouble =
    result = callSuperAs[NXDouble](self, getSelector("init"))
    if result.isNil:
      return

  method dealloc*(self: NXDouble) =
    clearIvarRefs(self)
    discard callSuperAs[ID](self, getSelector("dealloc"))

  method doubleValue*(self: NXDouble): cdouble =
    self.num()

  method floatValue*(self: NXDouble): cfloat =
    self.num().cfloat

  method integerValue*(self: NXDouble): NSInteger =
    self.num().int.NSInteger

  method boolValue*(self: NXDouble): bool =
    self.num() != 0.0

  method setDoubleValue*(self: NXDouble, value: cdouble) =
    self.num = value

  method hash*(self: NXDouble): NSUInteger =
    hash(self.num()).NSUInteger

  method isEqual*(self: NXDouble, other: NSObject): bool =
    if self.value == other.value:
      return true
    if other.isNil:
      return false
    if other.respondsToSelector("doubleValue"):
      let toDouble =
        cast[proc(obj: ID, op: SEL): cdouble {.cdecl, varargs.}](objc_msgSend)
      let value = toDouble(other.value, sel_registerName("doubleValue"))
      return self.doubleValue() == value
    if other.respondsToSelector("integerValue"):
      let toInt =
        cast[proc(obj: ID, op: SEL): NSInteger {.cdecl, varargs.}](objc_msgSend)
      let value = toInt(other.value, sel_registerName("integerValue")).cdouble
      return self.doubleValue() == value
    false

proc nsInteger*[T: SomeInteger](value: T): NXInteger =
  var allocated = NXInteger.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NXInteger(value: nil)
  created.setIntegerValue(value.NSInteger)
  result = asType[NXInteger](created.value)
  created.value = nil

proc nsFloat*[T: SomeFloat](value: T): NXDouble =
  var allocated = NXDouble.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NXDouble(value: nil)
  created.setDoubleValue(value.cdouble)
  result = asType[NXDouble](created.value)
  created.value = nil

type NSBoxingBuilder* = object

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

proc nsDispatch[T: SomeFloat](value: T): NXDouble {.inline.} =
  nsFloat(value)

proc nsDispatch(value: bool): NXInteger {.inline.} =
  nsInteger(if value: 1 else: 0)

template ns*(value: untyped): untyped =
  nsDispatch(value)

template nsBuilder(): NSBoxingBuilder =
  NSBoxingBuilder()

macro `[]`*(builder: NSBoxingBuilder, values: varargs[untyped]): untyped =
  when false:
    discard builder
  if values.len == 0:
    return quote:
      nsArray[NSObject]()
  var boxedValues = newNimNode(nnkBracket)
  for value in values:
    boxedValues.add(
      quote do:
        boxNSObject(`value`)
    )
  result = quote:
    nsArrayObjects(`boxedValues`)

proc isNsSymbol(n: NimNode): bool =
  case n.kind
  of nnkIdent, nnkSym:
    $n == "ns"
  of nnkOpenSymChoice, nnkClosedSymChoice:
    for c in n:
      if c.kind in {nnkIdent, nnkSym} and $c == "ns":
        return true
    false
  else:
    false

proc isNsBracketInvocation(n: NimNode): bool =
  if not isNsSymbol(n):
    return false
  let info = n.lineInfoObj
  if info.filename.len == 0 or info.line.int <= 0:
    return false
  let lines = staticRead(info.filename).splitLines()
  let lineIndex = info.line.int - 1
  if lineIndex < 0 or lineIndex >= lines.len:
    return false
  let lineText = lines[lineIndex]
  var i = info.column.int - 1
  if i < 0 or i >= lineText.len:
    return false
  if lineText[i] == '@':
    inc i
  while i < lineText.len and lineText[i].isSpaceAscii:
    inc i
  if i + 1 >= lineText.len or lineText[i] != 'n' or lineText[i + 1] != 's':
    return false
  i += 2
  while i < lineText.len and lineText[i].isSpaceAscii:
    inc i
  i < lineText.len and lineText[i] == '['

macro `@`*(value: untyped): untyped =
  ## Enables ergonomic calls like `@ns"foo"` and `@ns[]`.
  if isNsBracketInvocation(value):
    return quote:
      nsBuilder()
  value

proc boxNSObject*[T](value: T): NSObject {.inline.} =
  when T is NSObject:
    retainNSObjectId(value.value)
  elif T is string:
    let boxed = ns(value)
    retainNSObjectId(boxed.value)
  elif T is cstring:
    let boxed = ns(value)
    retainNSObjectId(boxed.value)
  elif T is SomeInteger:
    let boxed = ns(value)
    retainNSObjectId(boxed.value)
  elif T is SomeFloat:
    let boxed = ns(value)
    retainNSObjectId(boxed.value)
  elif T is bool:
    let boxed = ns(value)
    retainNSObjectId(boxed.value)
  else:
    {.
      fatal:
        "@ns boxing supports NSObject, string/cstring, integer, float, and bool values"
    .}

proc unboxNSObject*[T](value: NSObject): T {.inline.} =
  when T is NSObject:
    if value.isNil:
      return T(value: nil)
    let retainSend = cast[proc(self: ID, op: SEL): ID {.cdecl, varargs.}](objc_msgSend)
    T(value: retainSend(value.value, sel_registerName("retain")))
  elif T is string:
    if value.isNil:
      return ""
    let toUtf8 = cast[proc(self: ID, op: SEL): cstring {.cdecl, varargs.}](objc_msgSend)
    let utf8 = toUtf8(value.value, sel_registerName("UTF8String"))
    if utf8.isNil:
      return ""
    $utf8
  elif T is SomeInteger:
    if value.isNil:
      return T(0)
    if not value.respondsToSelector("integerValue"):
      return T(0)
    let toInt = cast[proc(obj: ID, op: SEL): NSInteger {.cdecl, varargs.}](objc_msgSend)
    T(toInt(value.value, sel_registerName("integerValue")))
  elif T is SomeFloat:
    if value.isNil:
      return T(0.0)
    if value.respondsToSelector("doubleValue"):
      let toDouble =
        cast[proc(obj: ID, op: SEL): cdouble {.cdecl, varargs.}](objc_msgSend)
      return T(toDouble(value.value, sel_registerName("doubleValue")))
    if value.respondsToSelector("floatValue"):
      let toFloat =
        cast[proc(obj: ID, op: SEL): cfloat {.cdecl, varargs.}](objc_msgSend)
      return T(toFloat(value.value, sel_registerName("floatValue")))
    if value.respondsToSelector("integerValue"):
      let toInt =
        cast[proc(obj: ID, op: SEL): NSInteger {.cdecl, varargs.}](objc_msgSend)
      return T(toInt(value.value, sel_registerName("integerValue")).cdouble)
    T(0.0)
  elif T is bool:
    if value.isNil:
      return false
    if value.respondsToSelector("boolValue"):
      let toBool = cast[proc(obj: ID, op: SEL): bool {.cdecl, varargs.}](objc_msgSend)
      return toBool(value.value, sel_registerName("boolValue"))
    if value.respondsToSelector("integerValue"):
      let toInt =
        cast[proc(obj: ID, op: SEL): NSInteger {.cdecl, varargs.}](objc_msgSend)
      return toInt(value.value, sel_registerName("integerValue")) != 0
    false
  else:
    {.
      fatal: "@ns unboxing supports NSObject, string, integer, float, and bool values"
    .}
