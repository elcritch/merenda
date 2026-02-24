# Key-Value Coding (KVC) — automatic, registration-free.
#
# valueForKey / setValueForKey dispatch entirely through the ObjC runtime:
# 1. For getters, try selectors in order: `key`, `isKey`, `getKey`.
# 2. For setters, try the selector `setKey:`.
# 3. Return types (and setter argument types) are read from the method's type
#    encoding at runtime; values are boxed/unboxed accordingly.
#
# Classes only need to define ObjC methods that follow the standard
# KVC naming convention — no registration step is required.

proc kvcTypeCode(enc: string): string =
  ## Strip ObjC type qualifiers and return the canonical leading type code.
  if enc.len == 0:
    return ""
  var i = 0
  while i < enc.len and enc[i] in {'r', 'n', 'N', 'o', 'O', 'R', 'V'}:
    inc i
  if i >= enc.len:
    return ""
  $enc[i]

proc kvcRetainedNSObject(id: ID): NSObject =
  asRetainedType[NSObject](id)

proc kvcTakeNSObject[T: NSObject](obj: T): NSObject {.inline.} =
  var tmp = obj
  result = asType[NSObject](move(tmp.value))

proc kvcSetterSelName(key: string): string =
  result = "set"
  if key.len > 0:
    result.add(key[0].toUpperAscii())
    if key.len > 1:
      result.add(key[1 ..^ 1])
  result.add(':')

proc kvcFindGetter(cls: ObjcClass, key: string): tuple[sel: SEL, m: Method] =
  ## Return the first matching getter method from: key / isKey / getKey.
  let cap =
    if key.len > 0:
      ($key[0].toUpperAscii()) & (if key.len > 1: key[1 ..^ 1] else: "")
    else:
      ""
  for name in [key, "is" & cap, "get" & cap]:
    let sel = sel_registerName(name.cstring)
    if respondsToSelector(cls, sel):
      let m = getInstanceMethod(cls, sel)
      if cast[pointer](m) != nil:
        return (sel: sel, m: m)
  result.sel = nil
  result.m = Method(nil)

proc kvcBoxValue(obj: ID, sel: SEL, enc: string): NSObject =
  ## Call `sel` on `obj` and box the return value according to `enc`.
  let t = kvcTypeCode(enc)
  case t
  of "@", "#":
    kvcRetainedNSObject(objc_msgSend(obj, sel))
  of "*":
    let send = cast[proc(self: ID, op: SEL): cstring {.cdecl, varargs.}](objc_msgSend)
    let s = send(obj, sel)
    if s.isNil:
      NSObject(value: nil)
    else:
      kvcTakeNSObject(nsString($s))
  of "i", "s":
    let send = cast[proc(self: ID, op: SEL): cint {.cdecl, varargs.}](objc_msgSend)
    kvcTakeNSObject(nsInteger(send(obj, sel).int))
  of "l":
    let send = cast[proc(self: ID, op: SEL): clong {.cdecl, varargs.}](objc_msgSend)
    kvcTakeNSObject(nsInteger(send(obj, sel).int))
  of "q":
    let send = cast[proc(self: ID, op: SEL): int64 {.cdecl, varargs.}](objc_msgSend)
    kvcTakeNSObject(nsInteger(send(obj, sel).int))
  of "I", "S":
    let send = cast[proc(self: ID, op: SEL): cuint {.cdecl, varargs.}](objc_msgSend)
    kvcTakeNSObject(nsInteger(send(obj, sel).int))
  of "L":
    let send = cast[proc(self: ID, op: SEL): culong {.cdecl, varargs.}](objc_msgSend)
    kvcTakeNSObject(nsInteger(send(obj, sel).int))
  of "Q":
    let send = cast[proc(self: ID, op: SEL): uint64 {.cdecl, varargs.}](objc_msgSend)
    kvcTakeNSObject(nsInteger(send(obj, sel).int))
  of "f":
    let send = cast[proc(self: ID, op: SEL): cfloat {.cdecl, varargs.}](objc_msgSend)
    kvcTakeNSObject(nsFloat(send(obj, sel)))
  of "d":
    let send = cast[proc(self: ID, op: SEL): cdouble {.cdecl, varargs.}](objc_msgSend)
    kvcTakeNSObject(nsFloat(send(obj, sel)))
  of "B", "c", "C":
    let send = cast[proc(self: ID, op: SEL): uint8 {.cdecl, varargs.}](objc_msgSend)
    kvcTakeNSObject(nsInteger(send(obj, sel).int))
  else:
    NSObject(value: nil)

proc kvcSendValue(obj: ID, sel: SEL, argEnc: string, value: NSObject) =
  ## Call the setter `sel` on `obj`, unboxing `value` according to `argEnc`.
  let t = kvcTypeCode(argEnc)
  case t
  of "@", "#":
    let send = cast[proc(self: ID, op: SEL, a: ID) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, value.value)
  of "*":
    let cstr = objcStableCString(stringValue(asType[NSString](value.value)))
    let send =
      cast[proc(self: ID, op: SEL, a: cstring) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, cstr)
  of "i", "s":
    let intVal = unboxNSObject[NSInteger](value)
    let send = cast[proc(self: ID, op: SEL, a: cint) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, intVal.cint)
  of "l":
    let intVal = unboxNSObject[NSInteger](value)
    let send = cast[proc(self: ID, op: SEL, a: clong) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, intVal.clong)
  of "q":
    let intVal = unboxNSObject[NSInteger](value)
    let send = cast[proc(self: ID, op: SEL, a: int64) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, intVal.int64)
  of "I", "S":
    let intVal = unboxNSObject[NSUInteger](value)
    let send = cast[proc(self: ID, op: SEL, a: cuint) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, intVal.cuint)
  of "L":
    let intVal = unboxNSObject[NSUInteger](value)
    let send = cast[proc(self: ID, op: SEL, a: culong) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, intVal.culong)
  of "Q":
    let intVal = unboxNSObject[NSUInteger](value)
    let send = cast[proc(self: ID, op: SEL, a: uint64) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, intVal.uint64)
  of "f":
    let floatVal = unboxNSObject[cfloat](value)
    let send = cast[proc(self: ID, op: SEL, a: cfloat) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, floatVal)
  of "d":
    let floatVal = unboxNSObject[cdouble](value)
    let send =
      cast[proc(self: ID, op: SEL, a: cdouble) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, floatVal)
  of "B":
    let intVal = unboxNSObject[NSInteger](value)
    let send = cast[proc(self: ID, op: SEL, a: bool) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, intVal != 0)
  of "c":
    let intVal = unboxNSObject[NSInteger](value)
    let send = cast[proc(self: ID, op: SEL, a: int8) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, intVal.int8)
  of "C":
    let intVal = unboxNSObject[NSUInteger](value)
    let send = cast[proc(self: ID, op: SEL, a: uint8) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, intVal.uint8)
  else:
    # Unknown type — fall back to treating the value as an object.
    let send = cast[proc(self: ID, op: SEL, a: ID) {.cdecl, varargs.}](objc_msgSend)
    send(obj, sel, value.value)

# ---------------------------------------------------------------------------
# Key-Value Observing (KVO) baseline
# ---------------------------------------------------------------------------

type
  NSKeyValueObservingOption* = enum
    nsKVOOptionNew
    nsKVOOptionOld
    nsKVOOptionInitial
    nsKVOOptionPrior

  NSKeyValueObservingOptions* = set[NSKeyValueObservingOption]

  KVOObservation = object
    observer: NSObject
    keyPath: string
    options: NSKeyValueObservingOptions
    context: pointer

  KVOObservationRef = ref object
    entries: seq[KVOObservation]

  KVOPendingChange = object
    keyPath: string
    oldValue: NSObject

  KVOPendingChangeRef = ref object
    entries: seq[KVOPendingChange]

proc kvoSettingKey(): NSString {.inline.} =
  nsString("kind")

proc kvoNewKey(): NSString {.inline.} =
  nsString("new")

proc kvoOldKey(): NSString {.inline.} =
  nsString("old")

proc kvoPriorKey(): NSString {.inline.} =
  nsString("notificationIsPrior")

proc valueForKey*(obj: NSObject, key: string): NSObject

proc kvoCurrentValue(obj: NSObject, keyPath: string): NSObject {.inline.} =
  valueForKey(obj, keyPath)

proc kvoObservationState(obj: NSObject): KVOObservationRef =
  if obj.isNil:
    return nil
  var state = getAssociatedRef[KVOObservationRef](obj, KVOObservationRef)
  if state.isNil:
    state = KVOObservationRef(entries: @[])
    setAssociatedRef(obj, state)
  state

proc kvoPendingState(obj: NSObject): KVOPendingChangeRef =
  if obj.isNil:
    return nil
  var state = getAssociatedRef[KVOPendingChangeRef](obj, KVOPendingChangeRef)
  if state.isNil:
    state = KVOPendingChangeRef(entries: @[])
    setAssociatedRef(obj, state)
  state

proc kvoIndexOfObserver(
    state: KVOObservationRef, observer: NSObject, keyPath: string, context: pointer
): int =
  if state.isNil:
    return -1
  for i, item in state.entries:
    if item.observer.value == observer.value and item.keyPath == keyPath and
        item.context == context:
      return i
  -1

proc kvoFindPending(state: KVOPendingChangeRef, keyPath: string): int =
  if state.isNil:
    return -1
  for i in countdown(state.entries.high, 0):
    if state.entries[i].keyPath == keyPath:
      return i
  -1

proc kvoMakeChangeDictionary(
    options: NSKeyValueObservingOptions,
    oldValue: NSObject,
    hasOldValue: bool,
    newValue: NSObject,
    hasNewValue: bool,
    prior: bool,
): NSDictionary[NSString, NSObject] =
  result = nsDictionary[NSString, NSObject]()
  result[kvoSettingKey()] = boxNSObject("setting")
  if prior:
    result[kvoPriorKey()] = boxNSObject(true)
  if nsKVOOptionOld in options and hasOldValue:
    result[kvoOldKey()] = oldValue
  if nsKVOOptionNew in options and hasNewValue:
    result[kvoNewKey()] = newValue

proc kvoNotifyObserver(
    observer: NSObject,
    keyPath: string,
    obj: NSObject,
    change: NSDictionary[NSString, NSObject],
    context: pointer,
) =
  if observer.isNil:
    return
  var sel: SEL = nil
  if observer.respondsToSelector("observeValueForKeyPath:ofObject:change:context:"):
    sel = sel_registerName("observeValueForKeyPath:ofObject:change:context:")
  else:
    return
  let send = cast[proc(
    self: ID, op: SEL, keyPath: ID, observed: ID, change: ID, context: pointer
  ) {.cdecl, varargs.}](objc_msgSend)
  var keyPathObj = nsString(keyPath)
  send(observer.value, sel, keyPathObj.value, obj.value, change.value, context)

proc addObserver*(
    obj: NSObject,
    observer: NSObject,
    keyPath {.kw("forKeyPath").}: string,
    options {.kw("options").}: NSKeyValueObservingOptions = {},
    context {.kw("context").}: pointer = nil,
) =
  if obj.isNil or observer.isNil or keyPath.len == 0:
    return
  let state = kvoObservationState(obj)
  let idx = kvoIndexOfObserver(state, observer, keyPath, context)
  if idx >= 0:
    state.entries[idx].options = options
  else:
    state.entries.add(
      KVOObservation(
        observer: observer, keyPath: keyPath, options: options, context: context
      )
    )

  if nsKVOOptionInitial in options:
    let current = kvoCurrentValue(obj, keyPath)
    let change = kvoMakeChangeDictionary(
      options, NSObject(value: nil), false, current, true, prior = false
    )
    kvoNotifyObserver(observer, keyPath, obj, change, context)

proc removeObserver*(
    obj: NSObject,
    observer: NSObject,
    keyPath {.kw("forKeyPath").}: string,
    context {.kw("context").}: pointer = nil,
) =
  if obj.isNil or observer.isNil or keyPath.len == 0:
    return
  let state = getAssociatedRef[KVOObservationRef](obj, KVOObservationRef)
  if state.isNil:
    return
  let idx = kvoIndexOfObserver(state, observer, keyPath, context)
  if idx >= 0:
    state.entries.del(idx)

proc willChangeValueForKey*(obj: NSObject, keyPath {.kw("key").}: string) =
  if obj.isNil or keyPath.len == 0:
    return
  let state = getAssociatedRef[KVOObservationRef](obj, KVOObservationRef)
  if state.isNil or state.entries.len == 0:
    return

  var oldValue = NSObject(value: nil)
  var hasOldSnapshot = false

  for item in state.entries:
    if item.keyPath != keyPath:
      continue
    if (nsKVOOptionOld in item.options or nsKVOOptionPrior in item.options) and
        not hasOldSnapshot:
      oldValue = kvoCurrentValue(obj, keyPath)
      hasOldSnapshot = true

    if nsKVOOptionPrior in item.options:
      let change = kvoMakeChangeDictionary(
        item.options,
        oldValue,
        hasOldSnapshot,
        NSObject(value: nil),
        false,
        prior = true,
      )
      kvoNotifyObserver(item.observer, keyPath, obj, change, item.context)

  if hasOldSnapshot:
    let pending = kvoPendingState(obj)
    pending.entries.add(KVOPendingChange(keyPath: keyPath, oldValue: oldValue))

proc didChangeValueForKey*(obj: NSObject, keyPath {.kw("key").}: string) =
  if obj.isNil or keyPath.len == 0:
    return
  let state = getAssociatedRef[KVOObservationRef](obj, KVOObservationRef)
  if state.isNil or state.entries.len == 0:
    return

  var oldValue = NSObject(value: nil)
  var hasOldValue = false
  let pending = getAssociatedRef[KVOPendingChangeRef](obj, KVOPendingChangeRef)
  let pendingIdx = kvoFindPending(pending, keyPath)
  if pendingIdx >= 0:
    oldValue = pending.entries[pendingIdx].oldValue
    hasOldValue = true
    pending.entries.del(pendingIdx)

  var newValue = NSObject(value: nil)
  var hasNewValue = false

  for item in state.entries:
    if item.keyPath != keyPath:
      continue

    if nsKVOOptionNew in item.options and not hasNewValue:
      newValue = kvoCurrentValue(obj, keyPath)
      hasNewValue = true

    let change = kvoMakeChangeDictionary(
      item.options, oldValue, hasOldValue, newValue, hasNewValue, prior = false
    )
    kvoNotifyObserver(item.observer, keyPath, obj, change, item.context)

proc willChangeValueForKey*(obj: NSObject, keyPath {.kw("key").}: NSString) {.inline.} =
  willChangeValueForKey(obj, stringValue(keyPath))

proc didChangeValueForKey*(obj: NSObject, keyPath {.kw("key").}: NSString) {.inline.} =
  didChangeValueForKey(obj, stringValue(keyPath))

proc addObserver*(
    obj: NSObject,
    observer: NSObject,
    keyPath {.kw("forKeyPath").}: NSString,
    options {.kw("options").}: NSKeyValueObservingOptions = {},
    context {.kw("context").}: pointer = nil,
) {.inline.} =
  addObserver(obj, observer, stringValue(keyPath), options, context)

proc removeObserver*(
    obj: NSObject,
    observer: NSObject,
    keyPath {.kw("forKeyPath").}: NSString,
    context {.kw("context").}: pointer = nil,
) {.inline.} =
  removeObserver(obj, observer, stringValue(keyPath), context)

proc kvoOptionsFromMask(mask: NSUInteger): NSKeyValueObservingOptions {.inline.} =
  result = {}
  if (mask and 1.NSUInteger) != 0:
    result.incl(nsKVOOptionNew)
  if (mask and 2.NSUInteger) != 0:
    result.incl(nsKVOOptionOld)
  if (mask and 4.NSUInteger) != 0:
    result.incl(nsKVOOptionInitial)
  if (mask and 8.NSUInteger) != 0:
    result.incl(nsKVOOptionPrior)

proc kvoKeyPathFromId(keyPath: ID): string =
  if keyPath.isNil:
    return ""
  let toUtf8 = cast[proc(self: ID, op: SEL): cstring {.cdecl, varargs.}](objc_msgSend)
  let utf8 = toUtf8(keyPath, sel_registerName("UTF8String"))
  if utf8.isNil:
    return ""
  var converted = ""
  {.cast(raises: []).}:
    converted = $utf8
  converted

proc kvoObjcAddObserver(
    self: ID, cmd: SEL, observer: ID, keyPath: ID, options: NSUInteger, context: pointer
) {.cdecl.} =
  if self.isNil:
    return
  let keyPathString = kvoKeyPathFromId(keyPath)
  addObserver(
    asType[NSObject](self),
    asType[NSObject](observer),
    keyPathString,
    kvoOptionsFromMask(options),
    context,
  )

proc kvoObjcRemoveObserverWithContext(
    self: ID, cmd: SEL, observer: ID, keyPath: ID, context: pointer
) {.cdecl.} =
  if self.isNil:
    return
  let keyPathString = kvoKeyPathFromId(keyPath)
  removeObserver(
    asType[NSObject](self), asType[NSObject](observer), keyPathString, context
  )

proc kvoObjcRemoveObserver(self: ID, cmd: SEL, observer: ID, keyPath: ID) {.cdecl.} =
  if self.isNil:
    return
  let keyPathString = kvoKeyPathFromId(keyPath)
  removeObserver(asType[NSObject](self), asType[NSObject](observer), keyPathString)

proc kvoObjcWillChange(self: ID, cmd: SEL, keyPath: ID) {.cdecl.} =
  if self.isNil:
    return
  let keyPathString = kvoKeyPathFromId(keyPath)
  willChangeValueForKey(asType[NSObject](self), keyPathString)

proc kvoObjcDidChange(self: ID, cmd: SEL, keyPath: ID) {.cdecl.} =
  if self.isNil:
    return
  let keyPathString = kvoKeyPathFromId(keyPath)
  didChangeValueForKey(asType[NSObject](self), keyPathString)

block:
  let nsObjectClass = getClass("NSObject")
  if not nsObjectClass.isNil:
    discard addMethod(
      nsObjectClass,
      selector("addObserver:forKeyPath:options:context:"),
      cast[IMP](kvoObjcAddObserver),
      "v@:@@Q^v",
    )
    discard addMethod(
      nsObjectClass,
      selector("removeObserver:forKeyPath:context:"),
      cast[IMP](kvoObjcRemoveObserverWithContext),
      "v@:@@^v",
    )
    discard addMethod(
      nsObjectClass,
      selector("removeObserver:forKeyPath:"),
      cast[IMP](kvoObjcRemoveObserver),
      "v@:@@",
    )
    discard addMethod(
      nsObjectClass,
      selector("willChangeValueForKey:"),
      cast[IMP](kvoObjcWillChange),
      "v@:@",
    )
    discard addMethod(
      nsObjectClass,
      selector("didChangeValueForKey:"),
      cast[IMP](kvoObjcDidChange),
      "v@:@",
    )

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc valueForKey*(obj: NSObject, key: string): NSObject =
  ## Return the KVC value for `key` on `obj`.
  ##
  ## Dispatches to the first matching ObjC method named `key`, `isKey`, or
  ## `getKey`.  The return type encoding is inspected at runtime; primitive
  ## returns are boxed into NXString / NXInteger as appropriate.
  ##
  ## Returns a nil NSObject when no matching getter is found, or when `obj` or
  ## `key` is nil/empty.
  if obj.isNil or key.len == 0:
    return NSObject(value: nil)
  let cls = getClass(obj.value)
  if cls.isNil:
    return NSObject(value: nil)
  let (sel, m) = kvcFindGetter(cls, key)
  if cast[pointer](m) == nil:
    return NSObject(value: nil)
  let enc = getReturnType(m)
  kvcBoxValue(obj.value, sel, enc)

proc setValueForKey*(obj: NSObject, value: NSObject, key: string) =
  ## Set the KVC value for `key` on `obj`.
  ##
  ## Dispatches to the ObjC method named `setKey:`.  The argument type encoding
  ## is inspected at runtime; `value` is unboxed from NXString / NXInteger
  ## before being passed to the method.
  ##
  ## Does nothing when no matching setter is found, or when `obj` or `key` is
  ## nil/empty.
  if obj.isNil or key.len == 0:
    return
  let cls = getClass(obj.value)
  if cls.isNil:
    return
  let setterName = kvcSetterSelName(key)
  let sel = sel_registerName(setterName.cstring)
  if not respondsToSelector(cls, sel):
    return
  let m = getInstanceMethod(cls, sel)
  if cast[pointer](m) == nil:
    return
  willChangeValueForKey(obj, key)
  # Argument index 0 = self, 1 = selector, 2 = first explicit argument.
  let argEnc = getArgumentType(m, 2)
  kvcSendValue(obj.value, sel, argEnc, value)
  didChangeValueForKey(obj, key)

proc valueForKeyPath*(obj: NSObject, keyPath: string): NSObject =
  ## Traverse `keyPath` (dot-separated keys) starting from `obj`.
  ## Returns nil if any intermediate value is nil or a key is not found.
  if obj.isNil or keyPath.len == 0:
    return NSObject(value: nil)
  var current = obj
  for key in keyPath.split('.'):
    if key.len == 0 or current.isNil:
      return NSObject(value: nil)
    current = valueForKey(current, key)
  current

proc setValueForKeyPath*(obj: NSObject, value: NSObject, keyPath: string) =
  ## Set `value` at the property named by the last component of `keyPath`,
  ## traversing intermediate objects for all earlier components.
  if obj.isNil or keyPath.len == 0:
    return
  let dot = keyPath.rfind('.')
  if dot < 0:
    setValueForKey(obj, value, keyPath)
    return
  let parentPath = keyPath[0 ..< dot]
  let lastKey = keyPath[dot + 1 ..^ 1]
  let parent = valueForKeyPath(obj, parentPath)
  if not parent.isNil:
    setValueForKey(parent, value, lastKey)

proc dictionaryWithValuesForKeys*(
    obj: NSObject, keys: openArray[string]
): NSDictionary[NSString, NSObject] =
  ## Return a dictionary mapping each key to `valueForKey(obj, key)`.
  result = nsDictionary[NSString, NSObject]()
  for key in keys:
    result[nsString(key)] = valueForKey(obj, key)

proc setValuesForKeysWithDictionary*(
    obj: NSObject, dict: NSDictionary[NSString, NSObject]
) =
  ## Apply each (key, value) pair in `dict` via `setValueForKey`.
  for key, val in dict.pairs:
    setValueForKey(obj, val, stringValue(key))

# -- NSString key overloads --

proc valueForKey*(obj: NSObject, key: NSString): NSObject {.inline.} =
  valueForKey(obj, stringValue(key))

proc setValueForKey*(obj: NSObject, value: NSObject, key: NSString) {.inline.} =
  setValueForKey(obj, value, stringValue(key))

proc valueForKeyPath*(obj: NSObject, keyPath: NSString): NSObject {.inline.} =
  valueForKeyPath(obj, stringValue(keyPath))

proc setValueForKeyPath*(obj: NSObject, value: NSObject, keyPath: NSString) {.inline.} =
  setValueForKeyPath(obj, value, stringValue(keyPath))
