import std/[macros, strutils]
import ./objcImpl

objcImpl:
  type NSValue* {.impl: NSCopying.} = object of NSObject

  method isEqualToValue*(self: NSValue, other: NSValue): bool =
    self.value == other.value

  method copyWithZone*(self: NSValue, zone: pointer): NSObject =
    if self.isNil:
      return NSObject(value: nil)
    return NSObject(value: self.value)

objcImpl:
  type NXInteger* {.impl: NSCopying.} = object of NSValue
    num: int

  method init*(self: var NXInteger): NXInteger =
    result = callSuperAs[NXInteger](self, getSelector("init"))
    if result.isNil:
      return

  method dealloc*(self: NXInteger) =
    destroyIvarFields(self)
    discard callSuperAs[IDPtr](self, getSelector("dealloc"))

  method integerValue*(self: NXInteger): NSInteger =
    self.num().NSInteger

  method intValue*(self: NXInteger): cint =
    self.num().cint

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
    let toInt =
      cast[proc(obj: IDPtr, op: SEL): NSInteger {.cdecl, varargs.}](objc_msgSend)
    let value = toInt(other.value, sel_registerName("integerValue"))
    self.integerValue() == value

objcImpl:
  type NXDouble* {.impl: NSCopying.} = object of NSValue
    num: cdouble

  method init*(self: var NXDouble): NXDouble =
    result = callSuperAs[NXDouble](self, getSelector("init"))
    if result.isNil:
      return

  method dealloc*(self: NXDouble) =
    destroyIvarFields(self)
    discard callSuperAs[IDPtr](self, getSelector("dealloc"))

  method doubleValue*(self: NXDouble): cdouble =
    self.num()

  method intValue*(self: NXDouble): cint =
    self.num().cint

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
        cast[proc(obj: IDPtr, op: SEL): cdouble {.cdecl, varargs.}](objc_msgSend)
      let value = toDouble(other.value, sel_registerName("doubleValue"))
      return self.doubleValue() == value
    if other.respondsToSelector("integerValue"):
      let toInt =
        cast[proc(obj: IDPtr, op: SEL): NSInteger {.cdecl, varargs.}](objc_msgSend)
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
  result = asTypeRaw[NXInteger](move(created.value))

proc nsFloat*[T: SomeFloat](value: T): NXDouble =
  var allocated = NXDouble.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NXDouble(value: nil)
  created.setDoubleValue(value.cdouble)
  result = asTypeRaw[NXDouble](move(created.value))

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
    retain(value.value)
  elif T is string:
    let boxed = ns(value)
    retain(boxed.value)
  elif T is cstring:
    let boxed = ns(value)
    retain(boxed.value)
  elif T is SomeInteger:
    let boxed = ns(value)
    retain(boxed.value)
  elif T is SomeFloat:
    let boxed = ns(value)
    retain(boxed.value)
  elif T is bool:
    let boxed = ns(value)
    retain(boxed.value)
  else:
    {.
      fatal:
        "@ns boxing supports NSObject, string/cstring, integer, float, and bool values"
    .}

proc unboxNSObject*[T](value: NSObject): T {.inline.} =
  when T is NSObject:
    if value.isNil:
      return T(value: nil)
    retain(T(value: value.value))
  elif T is string:
    if value.isNil:
      return ""
    let toUtf8 =
      cast[proc(self: IDPtr, op: SEL): cstring {.cdecl, varargs.}](objc_msgSend)
    let utf8 = toUtf8(value.value, sel_registerName("UTF8String"))
    if utf8.isNil:
      return ""
    $utf8
  elif T is SomeInteger:
    if value.isNil:
      return T(0)
    if not value.respondsToSelector("integerValue"):
      return T(0)
    let toInt =
      cast[proc(obj: IDPtr, op: SEL): NSInteger {.cdecl, varargs.}](objc_msgSend)
    T(toInt(value.value, sel_registerName("integerValue")))
  elif T is SomeFloat:
    if value.isNil:
      return T(0.0)
    if value.respondsToSelector("doubleValue"):
      let toDouble =
        cast[proc(obj: IDPtr, op: SEL): cdouble {.cdecl, varargs.}](objc_msgSend)
      return T(toDouble(value.value, sel_registerName("doubleValue")))
    if value.respondsToSelector("floatValue"):
      let toFloat =
        cast[proc(obj: IDPtr, op: SEL): cfloat {.cdecl, varargs.}](objc_msgSend)
      return T(toFloat(value.value, sel_registerName("floatValue")))
    if value.respondsToSelector("integerValue"):
      let toInt =
        cast[proc(obj: IDPtr, op: SEL): NSInteger {.cdecl, varargs.}](objc_msgSend)
      return T(toInt(value.value, sel_registerName("integerValue")).cdouble)
    T(0.0)
  elif T is bool:
    if value.isNil:
      return false
    if value.respondsToSelector("boolValue"):
      let toBool =
        cast[proc(obj: IDPtr, op: SEL): bool {.cdecl, varargs.}](objc_msgSend)
      return toBool(value.value, sel_registerName("boolValue"))
    if value.respondsToSelector("integerValue"):
      let toInt =
        cast[proc(obj: IDPtr, op: SEL): NSInteger {.cdecl, varargs.}](objc_msgSend)
      return toInt(value.value, sel_registerName("integerValue")) != 0
    false
  else:
    {.
      fatal: "@ns unboxing supports NSObject, string, integer, float, and bool values"
    .}
