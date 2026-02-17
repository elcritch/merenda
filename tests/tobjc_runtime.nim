import std/unittest
import nutella/objc

type DestroyProbeObject = object of NSObject
type RuntimeOwnedSubtype = object of NSObject
type RuntimePayloadObject = object of NSObject

var destroyProbeTriggered = false
var objcImplPingCount = 0
var objcImplAccum = 0.cint
var objcImplPayloadClass = ""
var objcImplPayloadRetainInMethod = 0
var objcImplSuperDeallocCount = 0

proc `=destroy`(o: var DestroyProbeObject) =
  destroyProbeTriggered = true

proc passThroughMove(o: sink NSObject): NSObject =
  o

proc isNilProtocol(p: Protocol): bool =
  cast[pointer](p) == nil

proc ensureRuntimeClass(className: string, superName = "NSObject"): ObjcClass =
  result = getClass(className)
  if result.isNil:
    addClass(className, superName, result):
      discard

suite "objc runtime ownership fundamentals":
  test "typedesc new works for NSObject":
    var o = NSObject.new()
    check(not o.isNil)
    check(getClassName(o) == "NSObject")

  test "typedesc new works for runtime NSObject subtype":
    let subClassName = $RuntimeOwnedSubtype
    discard ensureRuntimeClass(subClassName)
    var s = RuntimeOwnedSubtype.new()
    check(not s.isNil)
    check(getClassName(s) == subClassName)

  test "alloc/init runtime NSObject subtype":
    let subClassName = $RuntimeOwnedSubtype
    discard ensureRuntimeClass(subClassName)
    var allocated = RuntimeOwnedSubtype.alloc()
    check(not allocated.isNil)
    let retainBeforeInit = retainCount(allocated).int
    var s = allocated.init()
    check(allocated.isNil)
    check(not s.isNil)
    check(getClassName(s) == subClassName)
    check(retainCount(s).int == retainBeforeInit)

  test "retain and release(var) are balanced":
    var o = NSObject.new()
    check(not o.isNil)

    let baseCount = retainCount(o).int
    var extra = retain(o)
    check(extra == o)
    let afterRetain = retainCount(o).int
    check(afterRetain > baseCount)

    release(extra)
    check(extra.isNil)
    check(retainCount(o).int == afterRetain - 1)

    release(o)
    check(o.isNil)

  test "copy increments retain count":
    var o = NSObject.new()
    let baseCount = retainCount(o).int

    var alias = o
    check(alias == o)
    check(retainCount(o).int == baseCount + 1)

    release(alias)
    check(alias.isNil)
    check(retainCount(o).int == baseCount)

  test "block scope destroys copied alias":
    var o = NSObject.new()
    let baseCount = retainCount(o).int

    block:
      var alias = o
      check(alias == o)
      check(retainCount(o).int == baseCount + 1)

    check(retainCount(o).int == baseCount)

  test "block scope destroys retained temporary":
    var o = NSObject.new()
    var duringCount = 0

    block:
      var temp = retain(o)
      check(temp == o)
      duringCount = retainCount(o).int

    let afterBlock = retainCount(o).int
    check(afterBlock < duringCount)

  test "subclass destroy hook runs in block scope":
    destroyProbeTriggered = false
    block:
      var o = asType[DestroyProbeObject](NSObject.new())
      check(not o.isNil)
    check(destroyProbeTriggered)

  test "explicit move avoids retain-copy":
    var o = NSObject.new()
    let baseCount = retainCount(o).int

    block:
      var moved = move(o)
      check(o.isNil)
      check(not moved.isNil)
      check(retainCount(moved).int == baseCount)

  test "sink transfer avoids retain-copy":
    var o = NSObject.new()
    let baseCount = retainCount(o).int

    block:
      var moved = passThroughMove(move(o))
      check(o.isNil)
      check(not moved.isNil)
      check(retainCount(moved).int == baseCount)

  test "create actual Objective-C runtime subtype":
    const SubClassName = "NimRuntimeActualSubtypeOwnedTest"

    var subCls = getClass(SubClassName)
    if subCls.isNil:
      addClass(SubClassName, "NSObject", subCls):
        discard
    check(not subCls.isNil)

    block:
      var o = asType[NSObject](new(subCls))
      check(not o.isNil)
      check(getClassName(o) == SubClassName)

  test "create runtime protocol and attach to runtime class":
    const ProtoName = "NimRuntimeOwnedProtocolTest"
    const ClassName = "NimRuntimeClassWithProtocolOwnedTest"

    var proto = getProtocol(ProtoName)
    if proto.isNilProtocol:
      proto = allocateProtocol(ProtoName)
      check(not proto.isNilProtocol)
      addMethodDescription(proto, selector("nimPing"), "v@:", true, true)
      registerProtocol(proto)
      proto = getProtocol(ProtoName)

    check(not proto.isNilProtocol)

    var cls = getClass(ClassName)
    if cls.isNil:
      addClass(ClassName, "NSObject", cls):
        addProtocol(ProtoName)

    check(not cls.isNil)
    check(conformsToProtocol(cls, proto))

    var o = asType[NSObject](new(cls))
    check(not o.isNil)
    check(getClassName(o) == ClassName)

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
    check(not proto.isNilProtocol)

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

    var o = asType[NSObject](new(cls))
    check(not o.isNil)
    check(getClassName(o) == ClassName)
    let retainObjectBeforeCalls = retainCount(o).int

    let sendVoid = cast[proc(self: ID, op: SEL) {.cdecl.}](objc_msgSend)
    let sendAdd =
      cast[proc(self: ID, op: SEL, amount: cint): cint {.cdecl.}](objc_msgSend)
    let sendTakePayload =
      cast[proc(self: ID, op: SEL, payload: ID) {.cdecl.}](objc_msgSend)

    sendVoid(o, selector("nimPing"))
    check(objcImplPingCount == 1)
    check(retainCount(o).int == retainObjectBeforeCalls)

    check(sendAdd(o, selector("nimAdd:"), 2.cint) == 2.cint)
    check(sendAdd(o, selector("nimAdd:"), 3.cint) == 5.cint)
    check(retainCount(o).int == retainObjectBeforeCalls)

    var payload = RuntimePayloadObject.new()
    check(not payload.isNil)
    check(getClassName(payload) == PayloadClassName)
    let retainBefore = retainCount(payload).int
    let retainObjectBeforePayloadCall = retainCount(o).int
    sendTakePayload(o, selector("nimTakePayload:"), payload)
    check(objcImplPayloadClass == PayloadClassName)
    check(retainBefore > 0)
    check(objcImplPayloadRetainInMethod == retainBefore)
    check(retainCount(payload).int == retainBefore)
    check(retainCount(o).int == retainObjectBeforePayloadCall)

  test "callSuper helpers support typed dispatch and dealloc chaining":
    objcImplSuperDeallocCount = 0

    objcImpl:
      type NRSuperCallProtocol =
        concept self
            method nimSuperRetainCount(self: NRSuperCallProtocol): cint

      type NRSuperCallClass {.impl: NRSuperCallProtocol.} = object of NSObject

      method nimSuperRetainCount(self: NRSuperCallClass): cint =
        callSuperAs[NSUInteger](self, selector("retainCount")).cint

      method dealloc(self: NRSuperCallClass) =
        inc objcImplSuperDeallocCount
        superDealloc(self)

    let superProto = getProtocol(NRSuperCallProtocol)
    check(not superProto.isNilProtocol)

    let sendRetainCount = cast[proc(self: ID, op: SEL): cint {.cdecl.}](objc_msgSend)
    var o = NRSuperCallClass.new()
    check(not o.isNil)
    check(sendRetainCount(o, selector("nimSuperRetainCount")) == retainCount(o).cint)

    release(o)
    check(o.isNil)
    check(objcImplSuperDeallocCount == 1)
