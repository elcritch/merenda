import std/unittest
import merenda/objc
import merenda/objc/ivar

var fooBarPingCount = 0
var hiddenPingCount = 0
var simpleCounter = 0.cint
var crossPayloadClass = ""
var crossPayloadRetainInMethod = 0
var ivarCounterStateDestroyedCount = 0
var ivarCounterStateDestroyedCount2 = 0
var plainFieldPingCount = 0
var lateMethodBasePingCount = 0
var lateMethodExtraPingCount = 0
var lateMethodClassMethodTotal = 0.cint
var predeclFooBarPingCount = 0

type PredeclFooBar* = object of NSObject

objcImpl:
  type FooBarProtocol* =
    concept self
        method ping*(self: FooBarProtocol)

objcImpl:
  type PredeclFooBarProtocol* =
    concept self
        method ping*(self: PredeclFooBarProtocol)

objcImpl:
  type FooBar* {.impl: FooBarProtocol.} = object of NSObject

  method ping*(self: FooBar) =
    inc fooBarPingCount

objcImpl:
  type PredeclFooBar* {.impl: PredeclFooBarProtocol.} = object of NSObject

  method ping*(self: PredeclFooBar) =
    inc predeclFooBarPingCount

objcImpl:
  type SimpleCounterProtocol =
    concept self
        method bump(self: SimpleCounterProtocol): cint

  type SimpleCounterClass {.impl: SimpleCounterProtocol.} = object of NSObject

  method bump(self: SimpleCounterClass): cint =
    inc simpleCounter
    result = simpleCounter

objcImpl:
  type LateMethodClass = object of NSObject

  method basePing(self: LateMethodClass): cint =
    inc lateMethodBasePingCount
    lateMethodBasePingCount.cint

objcImpl:
  method extraPing(self: LateMethodClass): cint =
    inc lateMethodExtraPingCount
    lateMethodExtraPingCount.cint

  method addToTotal(self: typedesc[LateMethodClass], amount: cint): cint =
    lateMethodClassMethodTotal += amount
    result = lateMethodClassMethodTotal

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
    result = asTypeRaw[HiddenCtorClass](super(v, init))
    v.value = nil

  method ping(self: HiddenCtorClass) =
    inc hiddenPingCount

objcImpl:
  type PlainFieldClass = object of NSObject
    counter: int
    label: string
    enabled: bool

  proc initWithValues*(
      self: var PlainFieldClass, start: cint, text: string, enabled: bool
  ) =
    self = super(PlainFieldClass, self, init)
    self.counter = start.int
    self.label = text
    self.enabled = enabled

  method bumpAndPing(self: PlainFieldClass, amount: cint): cint =
    self.counter = self.counter + amount.int
    inc plainFieldPingCount
    self.counter.cint

  method dealloc(self: PlainFieldClass) {.used.} =
    self.label = ""
    superDealloc(self)

objcImpl:
  type CustomAccessorClass = object of NSObject
    payload {.get: payloadValue, set: setPayloadValue.}: string

  proc initWithPayload(self: var CustomAccessorClass, value: string) =
    self = super(CustomAccessorClass, self, init)
    self.payload = value

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

  test "fooBarTopLevelExample protocol":
    block fooBarTopLevelExample:
      fooBarPingCount = 0

      let proto = getProtocol(FooBarProtocol)
      let protoFromPrototype = getProtocol(FooBarProtocolPrototype)
      doAssert(not proto.isNil)
      doAssert(not protoFromPrototype.isNil)
      doAssert(proto.isEqual(protoFromPrototype))

      var o = FooBar.new()
      let retainBefore = retainCount(o).int

      let op: FooBarProtocol = asProto[FooBarProtocol](o)
      doAssert(not op.isNil)
      doAssert(retainCount(o).int == retainBefore + 1)
      doAssert(getClassName(op) == "FooBar")

      op.ping()
      doAssert(fooBarPingCount == 1)

      release(o)

  test "asProto returns nil for non-conforming object":
    var o = SimpleCounterClass.new()
    let p = asProto[FooBarProtocol](o)
    doAssert(p.isNil)

  test "objcImpl supports predeclared NSObject class":
    predeclFooBarPingCount = 0

    let proto = getProtocol(PredeclFooBarProtocol)
    check(not proto.isNil)

    var o = PredeclFooBar.new()
    check(not o.isNil)
    check(getClassName(o) == "PredeclFooBar")

    o.ping()
    check(predeclFooBarPingCount == 1)

  test "simple counter example":
    simpleCounter = 0

    let proto = getProtocol(SimpleCounterProtocol)
    check(not proto.isNil)

    var o = SimpleCounterClass.new()
    check(not o.isNil)
    check(getClassName(o) == "SimpleCounterClass")

    check(o.bump() == 1.cint)
    check(o.bump() == 2.cint)

  test "objcImpl can extend a class in a later block":
    lateMethodBasePingCount = 0
    lateMethodExtraPingCount = 0
    lateMethodClassMethodTotal = 0

    var o = LateMethodClass.new()
    check(not o.isNil)
    check(getClassName(o) == "LateMethodClass")
    check(respondsToSelector(getClass(LateMethodClass), selector("extraPing")))

    check(o.basePing() == 1.cint)
    check(o.extraPing() == 1.cint)
    check(o.extraPing() == 2.cint)
    check(LateMethodClass.addToTotal(2.cint) == 2.cint)
    check(LateMethodClass.addToTotal(5.cint) == 7.cint)

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
    type IvarCounterStateRef = ref object
      total: int
      lastAmount: int

    proc `=destroy`(o: var typeof(IvarCounterStateRef()[])) =
      inc ivarCounterStateDestroyedCount

    objcImpl:
      type IvarCounterClass = object of NSObject
        counter: IvarCounterStateRef

      proc new(
        t: typedesc[IvarCounterClass]
      ): IvarCounterClass {.
        error: "Use IvarCounterClass.alloc().initWithMultiplier(...)"
      .}

      proc init(
        t: typedesc[IvarCounterClass]
      ): IvarCounterClass {.
        error: "Use IvarCounterClass.alloc().initWithMultiplier(...)"
      .}

      proc init(
        v: var IvarCounterClass
      ): IvarCounterClass {.error: "Use initWithMultiplier(...)".}

      proc initWithMultiplier(self: var IvarCounterClass, lastAmount: cint) =
        self = super(IvarCounterClass, self, init)
        self.counter = IvarCounterStateRef(total: 0, lastAmount: lastAmount)

      method bump(self: IvarCounterClass, amount: cint): cint =
        let st = self.counter
        st.total += amount.int
        st.lastAmount = amount.int
        result = (st.total).cint

      method current(self: IvarCounterClass): cint =
        let st = self.counter
        (st.total).cint

      method lastAmount(self: IvarCounterClass): cint =
        let st = self.counter
        st.lastAmount.cint

      method dealloc(self: IvarCounterClass) {.used.} =
        destroyIvarFields(self)
        superDealloc(self)

    ivarCounterStateDestroyedCount = 0
    doAssert not compiles(IvarCounterClass.new())
    doAssert not compiles(IvarCounterClass.init())
    doAssert not compiles(
      block:
        var x = IvarCounterClass.alloc()
        discard x.init()
    )

    var c = IvarCounterClass.alloc()
    c.initWithMultiplier(1.cint)
    check(not c.isNil)
    check(getClassName(c) == "IvarCounterClass")
    check(c.current() == 0.cint)
    check(c.lastAmount() == 1.cint)

    check(c.bump(2.cint) == 2.cint)
    check(c.lastAmount() == 2.cint)
    check(c.bump(3.cint) == 5.cint)
    check(c.lastAmount() == 3.cint)
    check(c.current() == 5.cint)

    block:
      let st = c.counter()
      check(st != nil)
      check(st.total == 5)
      check(st.lastAmount == 3)
    check(ivarCounterStateDestroyedCount == 0)

    release(c)
    check(c.isNil)
    check(ivarCounterStateDestroyedCount == 1)

  test "objcImpl class using ivar-backed state":
    type IvarCounterState = object
      total: int
      lastAmount: int

    proc `=destroy`(o: var IvarCounterState) =
      echo "IvarCounterState: ", repr(o)
      inc ivarCounterStateDestroyedCount2

    objcImpl:
      type IvarCounterClass2 = object of NSObject
        counter: IvarCounterState

      proc init(
        v: var IvarCounterClass2
      ): IvarCounterClass2 {.error: "Use initWithMultiplier(...)".}

      proc initWithMultiplier(self: var IvarCounterClass2, lastAmount: cint) =
        self = super(IvarCounterClass2, self, init)
        self.counter = IvarCounterState(total: 0, lastAmount: lastAmount)

      method bump(self: IvarCounterClass2, amount: cint): cint =
        self.counter.total += amount.int
        self.counter.lastAmount = amount.int
        result = (self.counter.total).cint

      method current(self: IvarCounterClass2): cint =
        let st = self.counter
        (st.total).cint

      method lastAmount(self: IvarCounterClass2): cint =
        let st = self.counter
        st.lastAmount.cint

      method dealloc(self: IvarCounterClass2) {.used.} =
        destroyIvarFields(self)
        superDealloc(self)

    ivarCounterStateDestroyedCount2 = 0
    doAssert not compiles(
      block:
        var x = IvarCounterClass2.alloc()
        discard x.init()
    )

    check(ivarCounterStateDestroyedCount2 == 0)

    var c = IvarCounterClass2.alloc()
    c.initWithMultiplier(1.cint)
    check(not c.isNil)
    check(getClassName(c) == "IvarCounterClass2")
    check(c.current() == 0.cint)
    check(c.lastAmount() == 1.cint)

    check(c.bump(2.cint) == 2.cint)
    check(c.lastAmount() == 2.cint)
    check(c.bump(3.cint) == 5.cint)
    check(c.lastAmount() == 3.cint)
    check(c.current() == 5.cint)

    check(ivarCounterStateDestroyedCount2 == 1)

    block:
      let st = c.counter()
      check(st.total == 5)
      check(st.lastAmount == 3)
    check(ivarCounterStateDestroyedCount2 == 2)

    release(c)
    check(c.isNil)
    check(ivarCounterStateDestroyedCount2 == 3)

  test "objcImpl class supports direct value ivar fields":
    plainFieldPingCount = 0
    var o = PlainFieldClass.alloc()
    o.initWithValues(3.cint, "hello", true)
    check(not o.isNil)
    check(o.counter() == 3)
    check(o.label() == "hello")
    check(o.enabled())

    o.counter = 10
    o.label = "updated"
    o.enabled = false
    check(o.counter() == 10)
    check(o.label() == "updated")
    check(not o.enabled())

    check(o.bumpAndPing(5.cint) == 15.cint)
    check(o.counter() == 15)
    check(plainFieldPingCount == 1)

  test "objcImpl field pragmas can add named getters/setters":
    var o = CustomAccessorClass.alloc()
    o.initWithPayload("hello")
    check(not o.isNil)

    check(o.payload() == "hello")
    check(o.payloadValue() == "hello")

    o.setPayloadValue("updated")
    check(o.payload() == "updated")
    o.payload = "final"
    check(o.payloadValue() == "final")

  test "objcImpl field pragma accessors are registered as ObjC methods":
    var o = CustomAccessorClass.alloc()
    o.initWithPayload("hello")
    check(not o.isNil)

    let cls = getClass(CustomAccessorClass)
    let getterSel = selector("payloadValue")
    let setterSel = selector("setPayloadValue:")
    check(respondsToSelector(cls, getterSel))
    check(respondsToSelector(cls, setterSel))

    let sendGet =
      cast[proc(self: IDPtr, op: SEL): cstring {.cdecl, varargs.}](objc_msgSend)
    let sendSet = cast[proc(self: IDPtr, op: SEL, value: cstring): void {.
      cdecl, varargs
    .}](objc_msgSend)

    sendSet(o.value, setterSel, "fromObjc".cstring)
    check(o.payload() == "fromObjc")
    check($sendGet(o.value, getterSel) == "fromObjc")
