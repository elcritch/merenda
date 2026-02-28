import ./core

const NimIvarRefPrefix* = "nimIvarRef_"

type NimIvarRefCleanupProc = proc(value: pointer) {.cdecl, raises: [].}
type NimIvarValueCleanupProc = proc(obj: IDPtr, ivarName: string) {.raises: [].}
type NimIvarValueInitProc = proc(obj: IDPtr, ivarName: string) {.raises: [].}
type NimIvarRefPayload = object
  value: pointer
  cleanup: NimIvarRefCleanupProc

type NimIvarRegistryIvar = object
  ivarName: string
  isRef: bool
  valueCleanup: NimIvarValueCleanupProc
  valueInit: NimIvarValueInitProc

type NimIvarRegistryEntry = object
  className: string
  ivars: seq[NimIvarRegistryIvar]

var nimIvarRegistry {.global.}: seq[NimIvarRegistryEntry]

proc nimIvarRefCleanup[T: ref](value: pointer) {.cdecl, raises: [].} =
  let r = cast[T](value)
  if r != nil:
    GC_unref(r)

proc nimIvarValueCleanup[T](obj: IDPtr, ivarName: string) {.raises: [].}
proc nimIvarValueInit[T](obj: IDPtr, ivarName: string) {.raises: [].}
proc setIvarValueRaw[T](obj: IDPtr, ivarName: string, value: T) {.raises: [].}

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

proc registerIvar(
    cls: ObjcClass,
    ivarName: string,
    isRef: bool,
    valueCleanup: NimIvarValueCleanupProc = nil,
    valueInit: NimIvarValueInitProc = nil,
) =
  let clsName = getName(cls)
  if clsName.len == 0 or ivarName.len == 0:
    return

  for i in 0 ..< nimIvarRegistry.len:
    if nimIvarRegistry[i].className == clsName:
      for j in 0 ..< nimIvarRegistry[i].ivars.len:
        if nimIvarRegistry[i].ivars[j].ivarName == ivarName:
          if isRef:
            nimIvarRegistry[i].ivars[j].isRef = true
          if valueCleanup != nil:
            nimIvarRegistry[i].ivars[j].valueCleanup = valueCleanup
          if valueInit != nil:
            nimIvarRegistry[i].ivars[j].valueInit = valueInit
          return
      nimIvarRegistry[i].ivars.add(
        NimIvarRegistryIvar(
          ivarName: ivarName,
          isRef: isRef,
          valueCleanup: valueCleanup,
          valueInit: valueInit,
        )
      )
      return

  nimIvarRegistry.add(
    NimIvarRegistryEntry(
      className: clsName,
      ivars:
        @[
          NimIvarRegistryIvar(
            ivarName: ivarName,
            isRef: isRef,
            valueCleanup: valueCleanup,
            valueInit: valueInit,
          )
        ],
    )
  )

proc addRefIvar*(cls: ObjcClass, ivarName: string): bool =
  if cls.isNil or ivarName.len == 0:
    return false

  if cast[pointer](getIvar(cls, ivarName)) != nil:
    registerIvar(cls, ivarName, isRef = true)
    return true

  const ptrAlign =
    when sizeof(pointer) == 8:
      3
    elif sizeof(pointer) == 4:
      2
    else:
      1

  if addIvar(cls, ivarName, sizeof(pointer), ptrAlign, "^v"):
    registerIvar(cls, ivarName, isRef = true)
    return true

  if cast[pointer](getIvar(cls, ivarName)) != nil:
    registerIvar(cls, ivarName, isRef = true)
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

  let valueCleanup = nimIvarValueCleanup[T]
  let valueInit = nimIvarValueInit[T]
  if cast[pointer](getIvar(cls, ivarName)) != nil:
    registerIvar(
      cls, ivarName, isRef = false, valueCleanup = valueCleanup, valueInit = valueInit
    )
    return true

  if addIvar(cls, ivarName, sizeof(T), ivarValueAlignExp(T), "^v"):
    registerIvar(
      cls, ivarName, isRef = false, valueCleanup = valueCleanup, valueInit = valueInit
    )
    return true

  if cast[pointer](getIvar(cls, ivarName)) != nil:
    registerIvar(
      cls, ivarName, isRef = false, valueCleanup = valueCleanup, valueInit = valueInit
    )
    return true

  false

proc addFieldIvar*[T](cls: ObjcClass, ivarName: string): bool =
  when T is ref:
    addRefIvar(cls, ivarName)
  else:
    addValueIvar[T](cls, ivarName)

proc getIvarValuePtrRaw[T](obj: IDPtr, ivarName: string): ptr T {.inline, raises: [].} =
  if obj == nil or ivarName.len == 0:
    return nil
  var cls = getClass(obj)
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
  let slotAddr = cast[uint](obj) + cast[uint](getOffset(iv))
  cast[ptr T](slotAddr)

proc getIvarValuePtr[T](obj: NSObject, ivarName: string): ptr T {.inline, raises: [].} =
  getIvarValuePtrRaw[T](obj.value, ivarName)

proc nimIvarValueCleanup[T](obj: IDPtr, ivarName: string) {.raises: [].} =
  if obj == nil or ivarName.len == 0:
    return

  let p = getIvarValuePtrRaw[T](obj, ivarName)
  if p.isNil:
    return

  try:
    `=destroy`(p[])
  except Exception:
    discard
  #zeroMem(cast[pointer](p), sizeof(T))

proc nimIvarValueInit[T](obj: IDPtr, ivarName: string) {.raises: [].} =
  if obj == nil or ivarName.len == 0:
    return
  setIvarValueRaw[T](obj, ivarName, default(T))

proc getIvarValue*[T](obj: NSObject, ivarName: string): T {.raises: [].} =
  let p = getIvarValuePtr[T](obj, ivarName)
  if p.isNil:
    return default(T)
  when T is NSObject:
    let slot = cast[ptr IDPtr](p)
    let id = slot[]
    if id.isNil:
      return T(value: nil)
    discard objc_msgSend(id, sel_registerName("retain"))
    asTypeRaw[T](id)
  else:
    p[]

proc setIvarValueRaw[T](obj: IDPtr, ivarName: string, value: T) {.raises: [].} =
  let p = getIvarValuePtrRaw[T](obj, ivarName)
  if p.isNil:
    return
  when T is NSObject:
    let slot = cast[ptr IDPtr](p)
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

proc setIvarValue*[T](obj: NSObject, ivarName: string, value: T) {.raises: [].} =
  setIvarValueRaw[T](obj.value, ivarName, value)

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

proc clearIvarRefRaw(obj: IDPtr, ivarName: string) {.raises: [].} =
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

proc clearIvarRef*(obj: IDPtr, ivarName: string) {.inline, raises: [].} =
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

proc getIvarRefPtr*[T: ref](obj: NSObject, ivarName: string): ptr T {.raises: [].} =
  if obj.isNil or ivarName.len == 0:
    return nil

  var rawPayload: pointer
  discard getInstanceVariable(obj.value, ivarName, rawPayload)
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

proc clearIvarRefsRaw(obj: IDPtr) {.raises: [].} =
  if obj == nil:
    return

  var cls = getClass(obj)
  while not cls.isNil:
    let clsName = getName(cls)
    for entry in nimIvarRegistry:
      if entry.className == clsName:
        for ivar in entry.ivars:
          if ivar.isRef:
            clearIvarRefRaw(obj, ivar.ivarName)
          elif ivar.valueCleanup != nil:
            ivar.valueCleanup(obj, ivar.ivarName)
        break
    cls = getSuperclass(cls)

proc initIvarFieldsRaw(obj: IDPtr, initNimRefs: bool) {.raises: [].} =
  if obj == nil:
    return

  var cls = getClass(obj)
  while not cls.isNil:
    let clsName = getName(cls)
    for entry in nimIvarRegistry:
      if entry.className == clsName:
        for ivar in entry.ivars:
          if ivar.isRef and initNimRefs:
            clearIvarRefRaw(obj, ivar.ivarName)
          elif ivar.valueInit != nil:
            ivar.valueInit(obj, ivar.ivarName)
        break
    cls = getSuperclass(cls)

proc destroyIvarFields*(obj: IDPtr) {.inline, raises: [].} =
  clearIvarRefsRaw(obj)

proc destroyIvarFields*(obj: NSObject) {.inline, raises: [].} =
  clearIvarRefsRaw(obj.value)

proc initIvarFields*(obj: IDPtr, initNimRefs = true) {.inline, raises: [].} =
  initIvarFieldsRaw(obj, initNimRefs)

proc initIvarFields*(obj: NSObject, initNimRefs = true) {.inline, raises: [].} =
  initIvarFieldsRaw(obj.value, initNimRefs)
