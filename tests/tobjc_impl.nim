import std/unittest
import nutella/objc

type RuntimePayloadObject = object of NSObject
type RuntimeNimValuePayload = object
  left: cint
  right: cint

type RuntimeNimRefPayload = ref object
  label: string
  count: int

var objcImplPingCount = 0
var objcImplAccum = 0.cint
var objcImplPayloadClass = ""
var objcImplPayloadRetainInMethod = 0
var objcImplStringPayloadSeen = ""
var objcImplValuePayloadTotalSeen = 0.cint
var objcImplRefPayloadLabelSeen = ""
var objcImplRefPayloadCountSeen = 0
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

  test "objcImpl passes Nim string, value object, and ref object params":
    objcImplStringPayloadSeen = ""
    objcImplValuePayloadTotalSeen = 0
    objcImplRefPayloadLabelSeen = ""
    objcImplRefPayloadCountSeen = 0

    objcImpl:
      type NRNimPayloadProtocol =
        concept self
            method nimTakeString(self: NRNimPayloadProtocol, payload: string): cint
            method nimTakeValue(
              self: NRNimPayloadProtocol, payload: RuntimeNimValuePayload
            ): cint

            method nimTakeRef(
              self: NRNimPayloadProtocol, payload: RuntimeNimRefPayload
            ): cint

      type NRNimPayloadClass {.impl: NRNimPayloadProtocol.} = object of NSObject

      method nimTakeString(self: NRNimPayloadClass, payload: string): cint =
        discard self
        objcImplStringPayloadSeen = payload
        result = payload.len.cint

      method nimTakeValue(
          self: NRNimPayloadClass, payload: RuntimeNimValuePayload
      ): cint =
        discard self
        objcImplValuePayloadTotalSeen = payload.left + payload.right
        result = objcImplValuePayloadTotalSeen

      method nimTakeRef(self: NRNimPayloadClass, payload: RuntimeNimRefPayload): cint =
        discard self
        if payload.isNil:
          objcImplRefPayloadLabelSeen = ""
          objcImplRefPayloadCountSeen = -1
          return -1
        objcImplRefPayloadLabelSeen = payload.label
        objcImplRefPayloadCountSeen = payload.count
        payload.count.inc
        result = payload.count.cint

    let proto = getProtocol(NRNimPayloadProtocol)
    check(not proto.isNil)

    var foundTakeString = false
    var foundTakeValue = false
    var foundTakeRef = false
    for desc in methodDescriptionList(proto, true, true):
      if $desc.name == "nimTakeString:":
        foundTakeString = true
        check(desc.types == "i@:*")
      if $desc.name == "nimTakeValue:":
        foundTakeValue = true
      if $desc.name == "nimTakeRef:":
        foundTakeRef = true
    check(foundTakeString)
    check(foundTakeValue)
    check(foundTakeRef)

    var o = NRNimPayloadClass.new()
    check(not o.isNil)

    let stringPayload = "hello from Nim string"
    check(o.nimTakeString(stringPayload) == stringPayload.len.cint)
    check(objcImplStringPayloadSeen == stringPayload)

    let valuePayload = RuntimeNimValuePayload(left: 2.cint, right: 5.cint)
    check(o.nimTakeValue(valuePayload) == 7.cint)
    check(objcImplValuePayloadTotalSeen == 7.cint)
    check(valuePayload.left == 2.cint)
    check(valuePayload.right == 5.cint)

    let refPayload = RuntimeNimRefPayload(label: "ref payload", count: 3)
    check(o.nimTakeRef(refPayload) == 4.cint)
    check(objcImplRefPayloadLabelSeen == "ref payload")
    check(objcImplRefPayloadCountSeen == 3)
    check(refPayload.count == 4)

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
