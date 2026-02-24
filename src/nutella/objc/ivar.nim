import ./core

const NimIvarRefPrefix* = "nimIvarRef_"

type NimIvarRefCleanupProc = proc(value: pointer) {.cdecl, raises: [].}
type NimIvarRefPayload = object
  value: pointer
  cleanup: NimIvarRefCleanupProc

type NimIvarRegistryEntry = object
  className: string
  ivarNames: seq[string]

var nimIvarRegistry {.global.}: seq[NimIvarRegistryEntry]

proc nimIvarRefCleanup[T: ref](value: pointer) {.cdecl, raises: [].} =
  let r = cast[T](value)
  if r != nil:
    GC_unref(r)

proc sanitizeIvarToken(token: string): string =
  result = newStringOfCap(token.len)
  for ch in token:
    if (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or ch == '_':
      result.add(ch)
    else:
      result.add('_')

template ivarRefName*[T: ref](): string =
  NimIvarRefPrefix & sanitizeIvarToken($T)

template ivarRefName*[T: ref](t: typedesc[T]): string =
  ivarRefName[T]()

proc registerIvarName(cls: ObjcClass, ivarName: string) =
  let clsName = getName(cls)
  if clsName.len == 0 or ivarName.len == 0:
    return

  for i in 0 ..< nimIvarRegistry.len:
    if nimIvarRegistry[i].className == clsName:
      if ivarName notin nimIvarRegistry[i].ivarNames:
        nimIvarRegistry[i].ivarNames.add(ivarName)
      return

  nimIvarRegistry.add(NimIvarRegistryEntry(className: clsName, ivarNames: @[ivarName]))

proc addRefIvar*(cls: ObjcClass, ivarName: string): bool =
  if cls.isNil or ivarName.len == 0:
    return false

  if cast[pointer](getIvar(cls, ivarName)) != nil:
    registerIvarName(cls, ivarName)
    return true

  const ptrAlign =
    when sizeof(pointer) == 8:
      3
    elif sizeof(pointer) == 4:
      2
    else:
      1

  if addIvar(cls, ivarName, sizeof(pointer), ptrAlign, "^v"):
    registerIvarName(cls, ivarName)
    return true

  if cast[pointer](getIvar(cls, ivarName)) != nil:
    registerIvarName(cls, ivarName)
    return true

  false

proc addRefIvar*[T: ref](cls: ObjcClass): bool =
  addRefIvar(cls, ivarRefName[T]())

template ivarValueAlignExp(T: typedesc): int =
  when alignof(T) <= 1:
    0
  elif alignof(T) <= 2:
    1
  elif alignof(T) <= 4:
    2
  elif alignof(T) <= 8:
    3
  elif alignof(T) <= 16:
    4
  elif alignof(T) <= 32:
    5
  else:
    0

proc addValueIvar*[T](cls: ObjcClass, ivarName: string): bool =
  if cls.isNil or ivarName.len == 0:
    return false

  if cast[pointer](getIvar(cls, ivarName)) != nil:
    return true

  if addIvar(cls, ivarName, sizeof(T), ivarValueAlignExp(T), "^v"):
    return true

  cast[pointer](getIvar(cls, ivarName)) != nil

proc addFieldIvar*[T](cls: ObjcClass, ivarName: string): bool =
  when T is ref:
    addRefIvar(cls, ivarName)
  else:
    addValueIvar[T](cls, ivarName)

proc getIvarValuePtr[T](obj: NSObject, ivarName: string): ptr T {.inline, raises: [].} =
  if obj.isNil or ivarName.len == 0:
    return nil
  var cls = getClass(obj.value)
  if cls.isNil:
    return nil
  var iv = default(Ivar)
  while not cls.isNil:
    iv = getIvar(cls, ivarName)
    if cast[pointer](iv) != nil:
      break
    cls = getSuperclass(cls)
  if cast[pointer](iv) == nil:
    return nil
  let slotAddr = cast[uint](obj.value) + cast[uint](getOffset(iv))
  cast[ptr T](slotAddr)

proc getIvarValue*[T](obj: NSObject, ivarName: string): T {.raises: [].} =
  let p = getIvarValuePtr[T](obj, ivarName)
  if p.isNil:
    return default(T)
  when T is NSObject:
    let slot = cast[ptr ID](p)
    let id = slot[]
    if id.isNil:
      return T(value: nil)
    discard objc_msgSend(id, sel_registerName("retain"))
    asType[T](id)
  else:
    p[]

proc setIvarValue*[T](obj: NSObject, ivarName: string, value: T) {.raises: [].} =
  let p = getIvarValuePtr[T](obj, ivarName)
  if p.isNil:
    return
  when T is NSObject:
    let slot = cast[ptr ID](p)
    let next = value.value
    let prev = slot[]
    if prev == next:
      return
    if not next.isNil:
      discard objc_msgSend(next, sel_registerName("retain"))
    slot[] = next
    if not prev.isNil:
      discard objc_msgSend(prev, sel_registerName("release"))
  else:
    p[] = value

proc getIvarField*[T](obj: NSObject, ivarName: string): T {.inline, raises: [].} =
  when T is ref:
    getIvarRef[T](obj, ivarName)
  else:
    getIvarValue[T](obj, ivarName)

proc setIvarField*[T](
    obj: NSObject, ivarName: string, value: T
) {.inline, raises: [].} =
  when T is ref:
    setIvarRef[T](obj, ivarName, value)
  else:
    setIvarValue[T](obj, ivarName, value)

proc clearIvarRefRaw(obj: ID, ivarName: string) {.raises: [].} =
  if obj == nil or ivarName.len == 0:
    return

  var rawPayload: pointer
  discard getInstanceVariable(obj, ivarName, rawPayload)
  if rawPayload != nil:
    let payload = cast[ptr NimIvarRefPayload](rawPayload)
    if payload.cleanup != nil and payload.value != nil:
      payload.cleanup(payload.value)
    deallocShared(payload)
    discard setInstanceVariable(obj, ivarName, nil)

proc clearIvarRef*(obj: ID, ivarName: string) {.inline, raises: [].} =
  clearIvarRefRaw(obj, ivarName)

proc clearIvarRef*(obj: NSObject, ivarName: string) {.inline, raises: [].} =
  clearIvarRefRaw(obj.value, ivarName)

proc clearIvarRef*[T: ref](obj: NSObject) {.inline, raises: [].} =
  clearIvarRef(obj, ivarRefName[T]())

proc setIvarRef*[T: ref](obj: NSObject, ivarName: string, value: T) {.raises: [].} =
  if obj.isNil or ivarName.len == 0:
    return

  clearIvarRefRaw(obj.value, ivarName)
  if value == nil:
    return

  let payload = cast[ptr NimIvarRefPayload](allocShared0(sizeof(NimIvarRefPayload)))
  if payload == nil:
    return

  payload.value = cast[pointer](value)
  payload.cleanup = nimIvarRefCleanup[T]
  GC_ref(value)

  let iv = setInstanceVariable(obj.value, ivarName, cast[pointer](payload))
  when defined(nutellaIvarDebug):
    if ivarName == "counter":
      echo "setIvarRef(", ivarName, ") obj=", cast[uint](obj.value), " payload=", cast[
          uint](payload), " iv=", cast[uint](iv), " value=", cast[uint](cast[pointer](value))
  if cast[pointer](iv) == nil:
    if payload.cleanup != nil and payload.value != nil:
      payload.cleanup(payload.value)
    deallocShared(payload)

proc setIvarRef*[T: ref](obj: NSObject, value: T) {.inline, raises: [].} =
  setIvarRef(obj, ivarRefName[T](), value)

proc getIvarRef*[T: ref](obj: NSObject, ivarName: string): T {.raises: [].} =
  if obj.isNil or ivarName.len == 0:
    return nil

  var rawPayload: pointer
  discard getInstanceVariable(obj.value, ivarName, rawPayload)
  if rawPayload == nil:
    return nil

  let payload = cast[ptr NimIvarRefPayload](rawPayload)
  cast[T](payload.value)

proc getIvarRefPtr*[T: ref](obj: NSObject, ivarName: string): ptr T {.raises: [].} =
  if obj.isNil or ivarName.len == 0:
    return nil

  var rawPayload: pointer
  discard getInstanceVariable(obj.value, ivarName, rawPayload)
  when defined(nutellaIvarDebug):
    if ivarName == "counter":
      echo "getIvarRefPtr(", ivarName, ") obj=", cast[uint](obj.value), " raw=", cast[
          uint](rawPayload)
  if rawPayload == nil:
    return nil

  let payload = cast[ptr NimIvarRefPayload](rawPayload)
  cast[ptr T](payload.value.addr)

proc getIvarRef*[T: ref](obj: NSObject, t: typedesc[T]): T {.inline, raises: [].} =
  getIvarRef[T](obj, ivarRefName[T]())

proc getIvarFieldVar*[T](obj: NSObject, ivarName: string): var T {.inline.} =
  when T is ref:
    let p = getIvarRefPtr[T](obj, ivarName)
    doAssert not p.isNil
    p[]
  else:
    let p = getIvarValuePtr[T](obj, ivarName)
    doAssert not p.isNil
    p[]

proc clearIvarRefsRaw(obj: ID) {.raises: [].} =
  if obj == nil:
    return

  var cls = getClass(obj)
  while not cls.isNil:
    let clsName = getName(cls)
    for entry in nimIvarRegistry:
      if entry.className == clsName:
        for ivarName in entry.ivarNames:
          clearIvarRefRaw(obj, ivarName)
        break
    cls = getSuperclass(cls)

proc clearIvarRefs*(obj: ID) {.inline, raises: [].} =
  clearIvarRefsRaw(obj)

proc clearIvarRefs*(obj: NSObject) {.inline, raises: [].} =
  clearIvarRefsRaw(obj.value)
