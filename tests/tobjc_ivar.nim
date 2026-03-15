import std/unittest
import knutella/objc/core
import knutella/objc/ivar

type IvarStateObj = object
  value: int

type IvarStateRef = ref IvarStateObj

var ivarStateDestroyedCount = 0
var ivarPingCount = 0

proc `=destroy`(o: var IvarStateObj) =
  inc ivarStateDestroyedCount

proc ivarOwnerPing(self: IDPtr, cmd: SEL) {.cdecl, raises: [].} =
  inc ivarPingCount

proc ivarOwnerDealloc(self: IDPtr, cmd: SEL) {.cdecl, raises: [].} =
  destroyIvarFields(self)
  {.cast(raises: []).}:
    callSuperVoid(self, selector("dealloc"))

proc ensureIvarOwnerClass(): ObjcClass =
  const
    ClassName = "NimIvarRefOwnerTest"
    NamedIvarName = "nimNamedStateRef"
    ValueIvarName = "nimValueState"

  result = getClass(ClassName)
  if result.isNil:
    addClass(ClassName, "NSObject", result):
      doAssert addRefIvar(result, NamedIvarName)
      doAssert addRefIvar[IvarStateRef](result)
      doAssert addValueIvar[int](result, ValueIvarName)
      discard addMethod(result, selector("ping"), cast[IMP](ivarOwnerPing), "v@:")
      discard addMethod(result, selector("dealloc"), cast[IMP](ivarOwnerDealloc), "v@:")

suite "objc ivar Nim ref storage":
  test "set/get/clear by explicit ivar name":
    ivarStateDestroyedCount = 0

    let cls = ensureIvarOwnerClass()
    check(not cls.isNil)

    var o = asTypeRaw[NSObject](new(cls))
    check(not o.isNil)

    var state = IvarStateRef(value: 123)
    setIvarRef[IvarStateRef](o, "nimNamedStateRef", state)
    state = nil

    block:
      let loaded = getIvarRef[IvarStateRef](o, "nimNamedStateRef")
      check(loaded != nil)
      check(loaded.value == 123)
    check(ivarStateDestroyedCount == 0)

    clearIvarRef(o, "nimNamedStateRef")
    check(getIvarRef[IvarStateRef](o, "nimNamedStateRef") == nil)
    check(ivarStateDestroyedCount == 1)

  test "typed helper overloads work":
    ivarStateDestroyedCount = 0

    let cls = ensureIvarOwnerClass()
    var o = asTypeRaw[NSObject](new(cls))
    check(not o.isNil)

    var state = IvarStateRef(value: 77)
    setIvarRef(o, state)
    state = nil

    block:
      let loaded = o.getIvarRef(IvarStateRef)
      check(loaded != nil)
      check(loaded.value == 77)
    check(ivarStateDestroyedCount == 0)

    clearIvarRef[IvarStateRef](o)
    check(o.getIvarRef(IvarStateRef) == nil)
    check(ivarStateDestroyedCount == 1)

  test "destroyIvarFields in dealloc releases all registered ivar refs":
    ivarStateDestroyedCount = 0
    ivarPingCount = 0

    let cls = ensureIvarOwnerClass()
    var o = asTypeRaw[NSObject](new(cls))
    check(not o.isNil)

    var namedState = IvarStateRef(value: 41)
    var typedState = IvarStateRef(value: 42)
    setIvarRef[IvarStateRef](o, "nimNamedStateRef", namedState)
    setIvarRef(o, typedState)
    namedState = nil
    typedState = nil

    discard objc_msgSend(o.value, selector("ping"))
    check(ivarPingCount == 1)

    release(o)
    check(o.isNil)
    check(ivarStateDestroyedCount == 2)

  test "initIvarFields clears refs and resets value ivars":
    ivarStateDestroyedCount = 0

    let cls = ensureIvarOwnerClass()
    var o = asTypeRaw[NSObject](new(cls))
    check(not o.isNil)

    var namedState = IvarStateRef(value: 91)
    setIvarRef[IvarStateRef](o, "nimNamedStateRef", namedState)
    setIvarValue[int](o, "nimValueState", 123)
    namedState = nil

    check(getIvarRef[IvarStateRef](o, "nimNamedStateRef") != nil)
    check(getIvarValue[int](o, "nimValueState") == 123)

    initIvarFields(o)
    check(getIvarRef[IvarStateRef](o, "nimNamedStateRef") == nil)
    check(getIvarValue[int](o, "nimValueState") == 0)
    check(ivarStateDestroyedCount == 1)

  test "initIvarFields can skip Nim ref initialization":
    ivarStateDestroyedCount = 0

    let cls = ensureIvarOwnerClass()
    var o = asTypeRaw[NSObject](new(cls))
    check(not o.isNil)

    var namedState = IvarStateRef(value: 201)
    setIvarRef[IvarStateRef](o, "nimNamedStateRef", namedState)
    setIvarValue[int](o, "nimValueState", 456)
    namedState = nil

    initIvarFields(o, false)
    check(getIvarRef[IvarStateRef](o, "nimNamedStateRef") != nil)
    check(getIvarValue[int](o, "nimValueState") == 0)
    check(ivarStateDestroyedCount == 0)

    clearIvarRef(o, "nimNamedStateRef")
    check(ivarStateDestroyedCount == 1)
