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
  when false:
    discard t
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

proc getIvarRef*[T: ref](obj: NSObject, t: typedesc[T]): T {.inline, raises: [].} =
  when false:
    discard t
  getIvarRef[T](obj, ivarRefName[T]())

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
