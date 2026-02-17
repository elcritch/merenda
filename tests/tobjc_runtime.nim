import std/unittest
import nutella/objc

proc UTF8String*(n: NSString): cstring {.objc: "UTF8String".}
proc initWithUTF8String*(
  o: NSString, str: cstring
): NSString {.objc: "initWithUTF8String:".}

type DestroyProbeObject = object of NSObject

var destroyProbeTriggered = false
var objcImplPingCount = 0
var objcImplAccum = 0.cint
var objcImplLastString = ""
var objcImplStringRetainInMethod = 0

proc `=destroy`(o: var DestroyProbeObject) =
  destroyProbeTriggered = true

proc passThroughMove(o: sink NSObject): NSObject =
  o

proc isNilProtocol(p: Protocol): bool =
  cast[pointer](p) == nil

suite "objc runtime ownership fundamentals":
  test "typedesc new works for NSObject":
    var o = NSObject.new()
    check(not o.isNil)
    check(getClassName(o) == "NSObject")

  test "typedesc new works for NSString subtype":
    var s = NSString.new()
    check(not s.isNil)
    check(getClassName(s).len > 0)

  test "alloc/init NSString roundtrip":
    var s = NSString.alloc().initWithUTF8String("This is a test!")
    check($s.UTF8String == "This is a test!")

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

    objcImplPingCount = 0
    objcImplAccum = 0
    objcImplLastString = ""
    objcImplStringRetainInMethod = 0

    objcImpl:
      type NRProtocolTest =
        concept self
            method nimPing(self: NRProtocolTest)
            method nimAdd(self: NRProtocolTest, amount: cint): cint
            method nimTakeString(self: NRProtocolTest, text: NSString)

      type NRClassWithProtocolTest = object of NSObject
      implements NRClassWithProtocolTest:
        NRProtocolTest

      method nimPing(self: NRClassWithProtocolTest) =
        echo "PING!"
        inc objcImplPingCount

      method nimAdd(self: NRClassWithProtocolTest, amount: cint): cint =
        objcImplAccum += amount
        result = objcImplAccum

      method nimTakeString(self: NRClassWithProtocolTest, text: NSString) =
        objcImplLastString = $text.UTF8String
        echo "STRING: ", objcImplLastString
        objcImplStringRetainInMethod = retainCount(text).int

    var proto = getProtocol(NRProtocolTest)
    check(not proto.isNilProtocol)

    var foundNimPing = false
    var foundNimAdd = false
    var foundNimTakeString = false
    for desc in methodDescriptionList(proto, true, true):
      if $desc.name == "nimPing":
        foundNimPing = true
        check(desc.types == "v@:")
      if $desc.name == "nimAdd:":
        foundNimAdd = true
        check(desc.types == "i@:i")
      if $desc.name == "nimTakeString:":
        foundNimTakeString = true
        check(desc.types == "v@:@")
    check(foundNimPing)
    check(foundNimAdd)
    check(foundNimTakeString)

    var cls = getClass(NRClassWithProtocolTest)
    check(not cls.isNil)
    check(conformsToProtocol(cls, proto))
    check(respondsToSelector(cls, selector("nimPing")))
    check(respondsToSelector(cls, selector("nimAdd:")))
    check(respondsToSelector(cls, selector("nimTakeString:")))

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
    let sendTakeString = cast[proc(self: ID, op: SEL, text: ID) {.cdecl.}](objc_msgSend)

    sendVoid(o, selector("nimPing"))
    check(objcImplPingCount == 1)
    check(retainCount(o).int == retainObjectBeforeCalls)

    check(sendAdd(o, selector("nimAdd:"), 2.cint) == 2.cint)
    check(sendAdd(o, selector("nimAdd:"), 3.cint) == 5.cint)
    check(retainCount(o).int == retainObjectBeforeCalls)

    var text = NSString.alloc().initWithUTF8String("objcImpl-string-arg")
    let retainBefore = retainCount(text).int
    let retainObjectBeforeStringCall = retainCount(o).int
    sendTakeString(o, selector("nimTakeString:"), text)
    check(objcImplLastString == "objcImpl-string-arg")
    check(retainBefore > 0)
    check(objcImplStringRetainInMethod == retainBefore)
    check(retainCount(text).int == retainBefore)
    check(retainCount(o).int == retainObjectBeforeStringCall)
