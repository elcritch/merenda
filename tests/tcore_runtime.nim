import std/unittest
import nutella/objc

type DestroyProbeObject = object of NSObject
type RuntimeOwnedSubtype = object of NSObject

var destroyProbeTriggered = false

proc `=destroy`(o: var DestroyProbeObject) =
  destroyProbeTriggered = true

proc passThroughMove(o: sink NSObject): NSObject =
  o

proc ensureRuntimeClass(className: string, superName = "NSObject"): ObjcClass =
  result = getClass(className)
  if result.isNil:
    addClass(className, superName, result):
      discard

suite "objc core runtime ownership fundamentals":
  test "isKindOfClass works with typedesc and ObjcClass args":
    var obj = NSObject.new()
    check(obj.isKindOfClass(NSObject))
    let nsObjectClass = getClass("NSObject")
    check(not nsObjectClass.isNil)
    check(obj.isKindOfClass(asTypeRaw[ObjcClass](nsObjectClass)))

    let subClassName = $RuntimeOwnedSubtype
    discard ensureRuntimeClass(subClassName)
    var sub = RuntimeOwnedSubtype.new()
    check(sub.isKindOfClass(RuntimeOwnedSubtype))
    check(sub.isKindOfClass(NSObject))
    check(sub.isKindOfClass(asTypeRaw[ObjcClass](getClass(subClassName))))

    obj.value = nil
    sub.value = nil

  test "typedesc new works for NSObject":
    var o = NSObject.new()
    check(not o.isNil)
    let expectedClassName =
      when NutellaUseCustomNxObjectRoot: "NXObject" else: "NSObject"
    check(getClassName(o) == expectedClassName)

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

  test "asRetainedType creates retained typed wrappers":
    var o = NSObject.new()
    let baseCount = retainCount(o).int

    var retainedFromObj = asRetainedType[NSObject](o)
    check(retainedFromObj == o)
    check(retainCount(o).int == baseCount + 1)

    release(retainedFromObj)
    check(retainedFromObj.isNil)
    check(retainCount(o).int == baseCount)

    let oId: IDPtr = o
    var retainedFromId = asRetainedType[NSObject](oId)
    check(retainedFromId == o)
    check(retainCount(o).int == baseCount + 1)

    release(retainedFromId)
    check(retainedFromId.isNil)
    check(retainCount(o).int == baseCount)

    let nilFromObj = asRetainedType[NSObject](NSObject(value: nil))
    let nilFromId = asRetainedType[NSObject](cast[IDPtr](nil))
    check(nilFromObj.isNil)
    check(nilFromId.isNil)

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
      var o = asTypeRaw[DestroyProbeObject](NSObject.new())
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
      var o = asTypeRaw[NSObject](new(subCls))
      check(not o.isNil)
      check(getClassName(o) == SubClassName)

  test "create runtime protocol and attach to runtime class":
    const ProtoName = "NimRuntimeOwnedProtocolTest"
    const ClassName = "NimRuntimeClassWithProtocolOwnedTest"

    var proto = getProtocol(ProtoName)
    if proto.isNil:
      proto = allocateProtocol(ProtoName)
      check(not proto.isNil)
      addMethodDescription(proto, selector("nimPing"), "v@:", true, true)
      registerProtocol(proto)
      proto = getProtocol(ProtoName)

    check(not proto.isNil)

    var cls = getClass(ClassName)
    if cls.isNil:
      addClass(ClassName, "NSObject", cls):
        addProtocol(ProtoName)

    check(not cls.isNil)
    check(conformsToProtocol(cls, proto))

    var o = asTypeRaw[NSObject](new(cls))
    check(not o.isNil)
    check(getClassName(o) == ClassName)
