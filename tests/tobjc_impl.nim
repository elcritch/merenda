import std/unittest
import nutella/objc

type RuntimePayloadObject = object of NSObject

var objcImplPingCount = 0
var objcImplAccum = 0.cint
var objcImplPayloadClass = ""
var objcImplPayloadRetainInMethod = 0
var objcImplSuperDeallocCount = 0
var objcImplClassOnlyPingCount = 0

proc ensureRuntimeClass(className: string, superName = "NSObject"): ObjcClass =
  result = getClass(className)
  if result.isNil:
    addClass(className, superName, result):
      discard

suite "objcImpl runtime generation":
  test "template to create protocol and class":
    const ClassName = "NRClassWithProtocolTest"
    const PayloadClassName = $RuntimePayloadObject

    objcImplPingCount = 0
    objcImplAccum = 0
    objcImplPayloadClass = ""
    objcImplPayloadRetainInMethod = 0
    discard ensureRuntimeClass(PayloadClassName)

    objcImpl:
      type NRProtocolTest =
        concept self
            method nimPing(self: NRProtocolTest)
            method nimAdd(self: NRProtocolTest, amount: cint): cint
            method nimTakePayload(self: NRProtocolTest, payload: NSObject)

      type NRClassWithProtocolTest {.impl: NRProtocolTest.} = object of NSObject

      method nimPing(self: NRClassWithProtocolTest) =
        inc objcImplPingCount

      method nimAdd(self: NRClassWithProtocolTest, amount: cint): cint =
        objcImplAccum += amount
        result = objcImplAccum

      method nimTakePayload(self: NRClassWithProtocolTest, payload: NSObject) =
        objcImplPayloadClass = getClassName(payload)
        objcImplPayloadRetainInMethod = retainCount(payload).int

    var proto = getProtocol(NRProtocolTest)
    check(not proto.isNil)

    var foundNimPing = false
    var foundNimAdd = false
    var foundNimTakePayload = false
    for desc in methodDescriptionList(proto, true, true):
      if $desc.name == "nimPing":
        foundNimPing = true
        check(desc.types == "v@:")
      if $desc.name == "nimAdd:":
        foundNimAdd = true
        check(desc.types == "i@:i")
      if $desc.name == "nimTakePayload:":
        foundNimTakePayload = true
        check(desc.types == "v@:@")
    check(foundNimPing)
    check(foundNimAdd)
    check(foundNimTakePayload)

    var cls = getClass(NRClassWithProtocolTest)
    check(not cls.isNil)
    check(conformsToProtocol(cls, proto))
    check(respondsToSelector(cls, selector("nimPing")))
    check(respondsToSelector(cls, selector("nimAdd:")))
    check(respondsToSelector(cls, selector("nimTakePayload:")))

    var oNew = NRClassWithProtocolTest.new()
    check(not oNew.isNil)
    check(getClassName(oNew) == ClassName)

    var oAllocated = NRClassWithProtocolTest.alloc()
    check(not oAllocated.isNil)
    let retainAllocated = retainCount(oAllocated).int
    var oFromAllocInit = oAllocated.init()
    check(oAllocated.isNil)
    check(not oFromAllocInit.isNil)
    check(getClassName(oFromAllocInit) == ClassName)
    check(retainCount(oFromAllocInit).int == retainAllocated)

    var oInit = NRClassWithProtocolTest.init()
    check(not oInit.isNil)
    check(getClassName(oInit) == ClassName)

    let retainObjectBeforeCalls = retainCount(oNew).int

    oNew.nimPing()
    check(objcImplPingCount == 1)
    check(retainCount(oNew).int == retainObjectBeforeCalls)

    check(oNew.nimAdd(2.cint) == 2.cint)
    check(oNew.nimAdd(3.cint) == 5.cint)
    check(retainCount(oNew).int == retainObjectBeforeCalls)

    var payload = RuntimePayloadObject.new()
    check(not payload.isNil)
    check(getClassName(payload) == PayloadClassName)
    let retainBefore = retainCount(payload).int
    let retainObjectBeforePayloadCall = retainCount(oNew).int
    oNew.nimTakePayload(payload)
    check(objcImplPayloadClass == PayloadClassName)
    check(retainBefore > 0)
    check(objcImplPayloadRetainInMethod == retainBefore)
    check(retainCount(payload).int == retainBefore)
    check(retainCount(oNew).int == retainObjectBeforePayloadCall)

  test "callSuper helpers support typed dispatch and dealloc chaining":
    objcImplSuperDeallocCount = 0

    objcImpl:
      type NRSuperCallProtocol =
        concept self
            method nimSuperRetainCount(self: NRSuperCallProtocol): cint
            method nimSuperRespondsToRetainCount(self: NRSuperCallProtocol): bool

      type NRSuperCallClass {.impl: NRSuperCallProtocol.} = object of NSObject

      method nimSuperRetainCount(self: NRSuperCallClass): cint =
        super(NSUInteger, self, retainCount).cint

      method nimSuperRespondsToRetainCount(self: NRSuperCallClass): bool =
        super(bool, self, respondsToSelector(selector("retainCount")))

      method dealloc(self: NRSuperCallClass) {.used.} =
        inc objcImplSuperDeallocCount
        superDealloc(self)

    let superProto = getProtocol(NRSuperCallProtocol)
    check(not superProto.isNil)

    var o = NRSuperCallClass.new()
    check(not o.isNil)
    check(o.nimSuperRetainCount() == retainCount(o).cint)
    check(o.nimSuperRespondsToRetainCount())

    release(o)
    check(o.isNil)
    check(objcImplSuperDeallocCount == 1)

  test "protocol-only objcImpl creates runtime protocol":
    objcImpl:
      type NRProtoOnly =
        concept self
            method protoOnlyPing(self: NRProtoOnly)
            method protoOnlyAdd(self: NRProtoOnly, amount: cint): cint

    let proto = getProtocol(NRProtoOnly)
    check(not proto.isNil)

    var foundPing = false
    var foundAdd = false
    for desc in methodDescriptionList(proto, true, true):
      if $desc.name == "protoOnlyPing":
        foundPing = true
        check(desc.types == "v@:")
      if $desc.name == "protoOnlyAdd:":
        foundAdd = true
        check(desc.types == "i@:i")
    check(foundPing)
    check(foundAdd)

  test "class-only objcImpl creates class and methods":
    objcImplClassOnlyPingCount = 0

    objcImpl:
      type NRClassOnly = object of NSObject

      method classOnlyPing(self: NRClassOnly) =
        discard self
        inc objcImplClassOnlyPingCount

    var cls = getClass(NRClassOnly)
    check(not cls.isNil)
    check(respondsToSelector(cls, selector("classOnlyPing")))

    var o = NRClassOnly.new()
    check(not o.isNil)
    o.classOnlyPing()
    check(objcImplClassOnlyPingCount == 1)
