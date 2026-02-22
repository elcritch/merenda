import std/unittest
import nutella/objc
import nutella/appkit/types

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
var objcImplClassMethodTotal = 0.cint

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

  test "objcImpl supports class methods and protocol class-method metadata":
    objcImplClassMethodTotal = 0

    objcImpl:
      type NRClassMethodProtocol =
        concept self
            method classTotal(self: typedesc[NRClassMethodProtocol]): cint
            method addClassTotal(
              self: typedesc[NRClassMethodProtocol], amount: cint
            ): cint

            method resetClassTotal(self: typedesc[NRClassMethodProtocol])
            method instanceValue(self: NRClassMethodProtocol): cint

      type NRClassMethodClass {.impl: NRClassMethodProtocol.} = object of NSObject

      method classTotal(self: typedesc[NRClassMethodClass]): cint =
        result = objcImplClassMethodTotal

      method addClassTotal(self: typedesc[NRClassMethodClass], amount: cint): cint =
        objcImplClassMethodTotal += amount
        result = objcImplClassMethodTotal

      method resetClassTotal(self: typedesc[NRClassMethodClass]) =
        objcImplClassMethodTotal = 0

      method instanceValue(self: NRClassMethodClass): cint =
        discard self
        result = 7.cint

    let proto = getProtocol(NRClassMethodProtocol)
    check(not proto.isNil)

    var foundClassTotal = false
    var foundAddClassTotal = false
    var foundResetClassTotal = false
    for desc in methodDescriptionList(proto, true, false):
      if $desc.name == "classTotal":
        foundClassTotal = true
        check(desc.types == "i@:")
      if $desc.name == "addClassTotal:":
        foundAddClassTotal = true
        check(desc.types == "i@:i")
      if $desc.name == "resetClassTotal":
        foundResetClassTotal = true
        check(desc.types == "v@:")
    check(foundClassTotal)
    check(foundAddClassTotal)
    check(foundResetClassTotal)

    var foundInstanceValue = false
    for desc in methodDescriptionList(proto, true, true):
      if $desc.name == "instanceValue":
        foundInstanceValue = true
        check(desc.types == "i@:")
    check(foundInstanceValue)

    var cls = getClass(NRClassMethodClass)
    check(not cls.isNil)
    let metaCls = getClass(cls.value)
    check(not metaCls.isNil)
    check(respondsToSelector(metaCls, selector("classTotal")))
    check(respondsToSelector(metaCls, selector("addClassTotal:")))
    check(respondsToSelector(metaCls, selector("resetClassTotal")))
    check(respondsToSelector(cls, selector("instanceValue")))

    check(NRClassMethodClass.classTotal() == 0.cint)
    check(NRClassMethodClass.addClassTotal(2.cint) == 2.cint)
    check(NRClassMethodClass.addClassTotal(5.cint) == 7.cint)
    NRClassMethodClass.resetClassTotal()
    check(NRClassMethodClass.classTotal() == 0.cint)

    var o = NRClassMethodClass.new()
    check(not o.isNil)
    check(o.instanceValue() == 7.cint)

  test "objcImpl encodes NS struct signatures":
    objcImpl:
      type NRStructProtocol =
        concept self
            method setFrame(self: NRStructProtocol, frame: NSRect)
            method frame(self: NRStructProtocol): NSRect

      type NRStructClass {.impl: NRStructProtocol.} = object of NSObject

      method setFrame(self: NRStructClass, frame: NSRect) =
        discard self
        discard frame

      method frame(self: NRStructClass): NSRect =
        discard self
        result = nsRect(1.0, 2.0, 3.0, 4.0)

    let proto = getProtocol(NRStructProtocol)
    check(not proto.isNil)

    var foundSetFrame = false
    var foundFrame = false
    for desc in methodDescriptionList(proto, true, true):
      if $desc.name == "setFrame:":
        foundSetFrame = true
        check(desc.types == "v@:{NSRect={NSPoint=ff}{NSSize=ff}}")
      if $desc.name == "frame":
        foundFrame = true
        check(desc.types == "{NSRect={NSPoint=ff}{NSSize=ff}}@:")
    check(foundSetFrame)
    check(foundFrame)

  test "objcImpl models optional protocol methods and properties":
    objcImpl:
      type NROptionalProto =
        concept self
            method requiredPing(self: NROptionalProto)
            method optionalPing(self: NROptionalProto) {.optional.}
            method requiredName(
              self: NROptionalProto
            ): NSObject {.property: "requiredName".}

            method optionalTitle(
              self: NROptionalProto
            ): NSObject {.property: "optionalTitle", optional.}

            method classCount(
              self: typedesc[NROptionalProto]
            ): cint {.property: "classCount".}

            method classLabel(
              self: typedesc[NROptionalProto]
            ): NSObject {.property: "classLabel", optional, readonly.}

      type NROptionalClass {.impl: NROptionalProto.} = object of NSObject

      method requiredPing(self: NROptionalClass) =
        discard self

      method requiredName(self: NROptionalClass): NSObject =
        discard self
        result = NSObject(value: nil)

      method classCount(self: typedesc[NROptionalClass]): cint =
        1.cint

    let proto = getProtocol(NROptionalProto)
    check(not proto.isNil)

    var foundRequiredPing = false
    var foundOptionalPing = false
    var foundRequiredNameGetter = false
    var foundOptionalTitleGetter = false
    var foundClassCountGetter = false
    var foundClassLabelGetter = false
    for desc in methodDescriptionList(proto, true, true):
      if $desc.name == "requiredPing":
        foundRequiredPing = true
      if $desc.name == "requiredName":
        foundRequiredNameGetter = true
    for desc in methodDescriptionList(proto, false, true):
      if $desc.name == "optionalPing":
        foundOptionalPing = true
      if $desc.name == "optionalTitle":
        foundOptionalTitleGetter = true
    for desc in methodDescriptionList(proto, true, false):
      if $desc.name == "classCount":
        foundClassCountGetter = true
    for desc in methodDescriptionList(proto, false, false):
      if $desc.name == "classLabel":
        foundClassLabelGetter = true
    check(foundRequiredPing)
    check(foundOptionalPing)
    check(foundRequiredNameGetter)
    check(foundOptionalTitleGetter)
    check(foundClassCountGetter)
    check(foundClassLabelGetter)
