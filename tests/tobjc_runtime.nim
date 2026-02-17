import std/unittest
import nutella/objc

proc UTF8String*(n: NSString): cstring {.objc: "UTF8String".}
proc initWithUTF8String*(
  o: NSString, str: cstring
): NSString {.objc: "initWithUTF8String:".}

type DestroyProbeObject = object of NSObject

var destroyProbeTriggered = false

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
    const ProtoName = "NRProtocolTest"
    const ClassName = "NRClassWithProtocolTest"

    objcImpl:
      type NRProtocolTest =
        concept self
          method nimPing(self: NRProtocolTest)

      type NRClassWithProtocolTest = object of NRProtocolTest

      method nimPing(self: NRClassWithProtocolTest) =
        echo "PING!"

    var proto = getProtocol(ProtoName)
    check(not proto.isNilProtocol)

    var foundNimPing = false
    for desc in methodDescriptionList(proto, true, true):
      if $desc.name == "nimPing":
        foundNimPing = true
        check(desc.types == "v@:")
    check(foundNimPing)

    var cls = getClass(ClassName)
    check(not cls.isNil)
    check(conformsToProtocol(cls, proto))

    var o = asType[NSObject](new(cls))
    check(not o.isNil)
    check(getClassName(o) == ClassName)
