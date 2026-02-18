import std/unittest
import nutella/objc
import nutella/objc/ivar

var fooBarPingCount = 0
var hiddenPingCount = 0
var simpleCounter = 0.cint
var crossPayloadClass = ""
var crossPayloadRetainInMethod = 0
var ivarCounterStateDestroyedCount = 0

type IvarCounterStateObj = object
  total: int

type IvarCounterStateRef = ref IvarCounterStateObj

proc `=destroy`(o: var IvarCounterStateObj) =
  discard o
  inc ivarCounterStateDestroyedCount

objcImpl:
  type FooBarProtocol =
    concept self
        method ping(self: FooBarProtocol)

  type FooBar {.impl: FooBarProtocol.} = object of NSObject

  method ping(self: FooBar) =
    inc fooBarPingCount

objcImpl:
  type SimpleCounterProtocol =
    concept self
        method bump(self: SimpleCounterProtocol): cint

  type SimpleCounterClass {.impl: SimpleCounterProtocol.} = object of NSObject

  method bump(self: SimpleCounterClass): cint =
    inc simpleCounter
    result = simpleCounter

objcImpl:
  type SharedPayloadProtocol =
    concept self
        method payloadValue(self: SharedPayloadProtocol): cint

  type SharedPayload {.impl: SharedPayloadProtocol.} = object of NSObject

  method payloadValue(self: SharedPayload): cint =
    7.cint

objcImpl:
  type PayloadReceiverProtocol =
    concept self
        method takePayload(self: PayloadReceiverProtocol, payload: SharedPayload): cint

  type PayloadReceiver {.impl: PayloadReceiverProtocol.} = object of NSObject

  method takePayload(self: PayloadReceiver, payload: SharedPayload): cint =
    crossPayloadClass = getClassName(payload)
    crossPayloadRetainInMethod = retainCount(payload).int
    result = payload.payloadValue()

objcImpl:
  type HiddenCtorProtocol =
    concept self
        method ping(self: HiddenCtorProtocol)

  type HiddenCtorClass {.impl: HiddenCtorProtocol.} = object of NSObject

  proc new*(
    t: typedesc[HiddenCtorClass]
  ): HiddenCtorClass {.
    error: "HiddenCtorClass error; use HiddenCtorClass.alloc().initAllowed()"
  .}

  proc init*(
    t: typedesc[HiddenCtorClass]
  ): HiddenCtorClass {.error: "Use HiddenCtorClass.alloc().initAllowed()".}

  proc init*(v: var HiddenCtorClass): HiddenCtorClass {.error: "Use initAllowed()".}

  proc initAllowed*(v: var HiddenCtorClass): HiddenCtorClass =
    result = asType[HiddenCtorClass](objc_msgSend(v.value, selector("init")))
    v.value = nil

  method ping(self: HiddenCtorClass) =
    inc hiddenPingCount

proc ensureIvarCounterBackingClass() =
  const ClassName = "IvarCounterClass"
  var cls = getClass(ClassName)
  if cls.isNil:
    addClass(ClassName, "NSObject", cls):
      doAssert addRefIvar[IvarCounterStateRef](cls)

ensureIvarCounterBackingClass()

objcImpl:
  type IvarCounterProtocol =
    concept self
        method bump(self: IvarCounterProtocol, amount: cint): cint
        method current(self: IvarCounterProtocol): cint

  type IvarCounterClass {.impl: IvarCounterProtocol.} = object of NSObject

  method bump(self: IvarCounterClass, amount: cint): cint =
    var st = self.getIvarRef(IvarCounterStateRef)
    if st == nil:
      st = IvarCounterStateRef(total: 0)
      self.setIvarRef(st)
    st.total += amount.int
    result = st.total.cint

  method current(self: IvarCounterClass): cint =
    let st = self.getIvarRef(IvarCounterStateRef)
    if st == nil:
      return 0.cint
    st.total.cint

  method dealloc(self: IvarCounterClass) {.used.} =
    clearIvarRefs(self)
    superDealloc(self)

suite "objcImpl examples":
  test "test inits":
    doAssert not compiles(HiddenCtorClass.new())
    doAssert not compiles(HiddenCtorClass.init())
    doAssert not compiles(
      block:
        var o = HiddenCtorClass.alloc()
        discard o.init()
    )

  test "fooBarTopLevelExample":
    block fooBarTopLevelExample:
      fooBarPingCount = 0

      let proto = getProtocol(FooBarProtocol)
      doAssert(not proto.isNil)

      var o = FooBar.new()
      doAssert(not o.isNil)
      doAssert(getClassName(o) == "FooBar")

      o.ping()
      doAssert(fooBarPingCount == 1)

  test "simple counter example":
    simpleCounter = 0

    let proto = getProtocol(SimpleCounterProtocol)
    check(not proto.isNil)

    var o = SimpleCounterClass.new()
    check(not o.isNil)
    check(getClassName(o) == "SimpleCounterClass")

    check(o.bump() == 1.cint)
    check(o.bump() == 2.cint)

  test "pass typed objcImpl class arg to another objcImpl class":
    crossPayloadClass = ""
    crossPayloadRetainInMethod = 0

    let payloadProto = getProtocol(SharedPayloadProtocol)
    let receiverProto = getProtocol(PayloadReceiverProtocol)
    check(not payloadProto.isNil)
    check(not receiverProto.isNil)

    var receiver = PayloadReceiver.new()
    var payload = SharedPayload.new()
    check(not receiver.isNil)
    check(not payload.isNil)

    let retainBefore = retainCount(payload).int
    let value = receiver.takePayload(payload)
    check(value == 7.cint)
    check(crossPayloadClass == "SharedPayload")
    check(crossPayloadRetainInMethod == retainBefore)
    check(retainCount(payload).int == retainBefore)

  test "constructor-unavailable overloads inside objcImpl":
    hiddenPingCount = 0
    let proto = getProtocol(HiddenCtorProtocol)
    check(not proto.isNil)

    var allocated = HiddenCtorClass.alloc()
    check(not allocated.isNil)
    var o = allocated.initAllowed()
    check(allocated.isNil)
    check(not o.isNil)
    check(getClassName(o) == "HiddenCtorClass")

    o.ping()
    check(hiddenPingCount == 1)

  test "objcImpl class using ivar-backed state":
    ivarCounterStateDestroyedCount = 0

    let proto = getProtocol(IvarCounterProtocol)
    check(not proto.isNil)

    var c = IvarCounterClass.new()
    check(not c.isNil)
    check(getClassName(c) == "IvarCounterClass")
    check(c.current() == 0.cint)

    check(c.bump(2.cint) == 2.cint)
    check(c.bump(3.cint) == 5.cint)
    check(c.current() == 5.cint)
    check(c.getIvarRef(IvarCounterStateRef) != nil)
    check(ivarCounterStateDestroyedCount == 0)

    release(c)
    check(c.isNil)
    check(ivarCounterStateDestroyedCount == 1)
