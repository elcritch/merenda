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
  else:
    {.fatal: "@ns boxing supports NSObject, string/cstring, and integer values".}

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
  else:
    {.fatal: "@ns unboxing supports NSObject, string, and integer values".}
