import ./core

const NimAssociatedRefBoxClassName = "NimAssociatedRefBox"
const NimAssociatedRefPayloadIvarName = "nimAssociatedRefPayload"

type NimAssociatedRefCleanupProc = proc(value: pointer) {.cdecl, raises: [].}
type NimAssociatedRefPayload = object
  value: pointer
  cleanup: NimAssociatedRefCleanupProc

proc nimAssociatedRefCleanup[T: ref](value: pointer) {.cdecl, raises: [].} =
  let r = cast[T](value)
  if r != nil:
    GC_unref(r)

proc nimAssociatedRefBoxDealloc(self: IDPtr, cmd: SEL) {.cdecl, raises: [].}

proc associatedRefBoxClass(): ObjcClass =
  var cls {.global.}: ObjcClass
  if cls.isNil:
    cls = getClass(NimAssociatedRefBoxClassName)
    if cls.isNil:
      cls = allocateClassPair(getClass("NSObject"), NimAssociatedRefBoxClassName, 0)
      if not cls.isNil:
        const ptrAlign =
          when sizeof(pointer) == 8:
            3
          elif sizeof(pointer) == 4:
            2
          else:
            1
        discard
          addIvar(cls, NimAssociatedRefPayloadIvarName, sizeof(pointer), ptrAlign, "^v")
        discard addMethod(
          cls, sel_registerName("dealloc"), cast[IMP](nimAssociatedRefBoxDealloc), "v@:"
        )
        registerClassPair(cls)
        cls = getClass(NimAssociatedRefBoxClassName)
  cls

template associatedRefKey*[T: ref](): pointer =
  cast[pointer](sel_registerName(("nim.assoc.ref." & $T).cstring))

template associatedRefKey*[T: ref](t: typedesc[T]): pointer =
  associatedRefKey[T]()

proc clearAssociatedRef*(obj: NSObject, key: pointer) {.inline, raises: [].} =
  if obj.isNil:
    return
  setAssociatedObject(obj.value, key, nil, OBJC_ASSOCIATION_ASSIGN)

proc clearAssociatedRef*[T: ref](obj: NSObject) {.inline, raises: [].} =
  clearAssociatedRef(obj, associatedRefKey[T]())

proc setAssociatedRef*[T: ref](
    obj: NSObject,
    key: pointer,
    value: T,
    policy: objc_AssociationPolicy = OBJC_ASSOCIATION_RETAIN_NONATOMIC,
) {.raises: [].} =
  if obj.isNil:
    return
  clearAssociatedRef(obj, key)
  if value == nil:
    return

  let payload =
    cast[ptr NimAssociatedRefPayload](allocShared0(sizeof(NimAssociatedRefPayload)))
  if payload == nil:
    return
  payload.value = cast[pointer](value)
  payload.cleanup = nimAssociatedRefCleanup[T]
  GC_ref(value)

  let boxCls = associatedRefBoxClass()
  if boxCls.isNil:
    payload.cleanup(payload.value)
    deallocShared(payload)
    return

  let box = objc_msgSend(boxCls, sel_registerName("new"))
  if box == nil:
    payload.cleanup(payload.value)
    deallocShared(payload)
    return

  discard
    setInstanceVariable(box, NimAssociatedRefPayloadIvarName, cast[pointer](payload))
  setAssociatedObject(obj.value, key, box, policy)
  discard objc_msgSend(box, sel_registerName("release"))

proc setAssociatedRef*[T: ref](
    obj: NSObject,
    value: T,
    policy: objc_AssociationPolicy = OBJC_ASSOCIATION_RETAIN_NONATOMIC,
) {.inline, raises: [].} =
  setAssociatedRef(obj, associatedRefKey[T](), value, policy)

proc getAssociatedRef*[T: ref](obj: NSObject, key: pointer): T {.raises: [].} =
  if obj.isNil:
    return nil
  let box = getAssociatedObject(obj.value, key)
  if box == nil:
    return nil
  var rawPayload: pointer
  discard getInstanceVariable(box, NimAssociatedRefPayloadIvarName, rawPayload)
  if rawPayload == nil:
    return nil
  let payload = cast[ptr NimAssociatedRefPayload](rawPayload)
  cast[T](payload.value)

proc getAssociatedRef*[T: ref](
    obj: NSObject, t: typedesc[T]
): T {.inline, raises: [].} =
  getAssociatedRef[T](obj, associatedRefKey[T]())

proc nimAssociatedRefBoxDealloc(self: IDPtr, cmd: SEL) {.cdecl, raises: [].} =
  var rawPayload: pointer
  discard getInstanceVariable(self, NimAssociatedRefPayloadIvarName, rawPayload)
  if rawPayload != nil:
    let payload = cast[ptr NimAssociatedRefPayload](rawPayload)
    if payload.cleanup != nil and payload.value != nil:
      payload.cleanup(payload.value)
    deallocShared(payload)
    discard setInstanceVariable(self, NimAssociatedRefPayloadIvarName, nil)

  {.cast(raises: []).}:
    callSuperVoid(self, sel_registerName("dealloc"))
