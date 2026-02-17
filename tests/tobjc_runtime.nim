import std/unittest
import darwin/objc/runtime
import darwin/foundation/nsgeometry

type
  NSNumber = ptr object of NSObject
  NSValue = ptr object of NSObject

proc valueWithRect(n: typedesc[NSValue], d: NSRect): NSValue {.objc: "valueWithRect:".}
proc valueWithPoint(
  n: typedesc[NSValue], d: NSPoint
): NSValue {.objc: "valueWithPoint:".}

proc rectValue(n: NSValue): NSRect {.objc.}
proc pointValue(n: NSValue): NSPoint {.objc.}
proc description(n: NSValue): NSString {.objc.}

proc numberWithDouble(
  n: typedesc[NSNumber], d: float
): NSNumber {.objc: "numberWithDouble:".}

proc numberWithFloat(
  n: typedesc[NSNumber], d: cfloat
): NSNumber {.objc: "numberWithFloat:".}

proc doubleValue(n: NSNumber): float {.objc: "doubleValue".}
proc floatValue(n: NSNumber): cfloat {.objc: "floatValue".}

proc UTF8String(n: NSString): cstring {.objc: "UTF8String".}

proc alloc*[T](o: typedesc[T]): T {.objc: "alloc".}

proc initWithUTF8String(
  o: NSString, str: cstring
): NSString {.objc: "initWithUTF8String:".}

proc retainCount(o: NSObject): NSUInteger {.objc: "retainCount".}

suite "objc runtime":
  test "NSNumber and NSString values":
    let a = NSString.alloc().initWithUTF8String("This is a test!")
    let n = NSNumber.numberWithDouble(123.456)
    let nf = NSNumber.numberWithFloat(123.456)

    check(n.doubleValue > 123 and n.doubleValue < 124)
    check(nf.floatValue > 123 and nf.floatValue < 124)
    check($a.UTF8String == "This is a test!")

  test "NSValue rect roundtrip":
    let v = NSValue.valueWithRect(NSMakeRect(1, 2, 3, 4))
    check($v.description.UTF8String == "NSRect: {{1, 2}, {3, 4}}")
    check(v.rectValue == NSMakeRect(1, 2, 3, 4))

  test "NSValue point roundtrip":
    let v = NSValue.valueWithPoint(NSMakePoint(1, 2))
    check($v.description.UTF8String == "NSPoint: {1, 2}")
    check(v.pointValue == NSMakePoint(1, 2))

  test "basic runtime class and selector functions":
    let nsObjectClass = getClass("NSObject")
    check(nsObjectClass != nil)

    check(selector("init") == sel_registerName("init"))

    let allocObj = init(cast[NSObject](alloc(nsObjectClass)))
    check(allocObj != nil)

    let newObj = cast[NSObject](new(nsObjectClass))
    check(newObj != nil)

  test "retain increments and release restores count":
    let o = cast[NSObject](new(getClass("NSObject")))
    check(o != nil)

    let baseCount = retainCount(o)
    let extra = retain(o)
    check(extra != nil)
    check(extra == o)
    check(retainCount(o).int == baseCount.int + 1)

    extra.release()
    check(retainCount(o) == baseCount)

    o.release()

  test "plain assignment does not retain; explicit retain does":
    let o = cast[NSObject](new(getClass("NSObject")))
    let baseCount = retainCount(o)

    let alias = o
    check(alias == o)
    check(retainCount(o) == baseCount)

    let retainedAlias = retain(alias)
    check(retainCount(o).int == baseCount.int + 1)
    retainedAlias.release()
    check(retainCount(o) == baseCount)

    o.release()

  test "addClass registers methods":
    const BaseClassName = "NimRuntimeAddClassBase"

    var basePingCount = 0

    proc basePing(self: ID, cmd: SEL) {.cdecl.} =
      inc(basePingCount)

    proc ping(self: NSObject) {.objc.}

    var baseCls: ObjcClass
    addClass(BaseClassName, "NSObject", baseCls):
      addMethod("ping", basePing)
    check(baseCls != nil)
    check(getClass(BaseClassName) == baseCls)

    let o = cast[NSObject](new(baseCls))
    ping(o)
    check(basePingCount == 1)

  test "callSuper with explicit return type":
    const
      BaseClassName = "NimRuntimeCallSuperBase"
      SubClassName = "NimRuntimeCallSuperSub"

    var
      baseSum = 0
      subCallCount = 0
      subReceived = 0

    proc addBase(self: ID, cmd: SEL, value: cint): cint {.cdecl.} =
      baseSum += value.int
      baseSum.cint

    proc addSub(self: ID, cmd: SEL, value: cint): cint {.cdecl.} =
      inc(subCallCount)
      subReceived = value.int
      result = callSuper(cint, cast[NSObject](self), cmd, value)
      inc(result)

    proc addValue(self: NSObject, value: cint): cint {.objc: "addValue:".}

    let baseCls = allocateClassPair(getClass("NSObject"), BaseClassName, 0)
    discard addMethod(baseCls, selector("addValue:"), addBase)
    registerClassPair(baseCls)
    check(baseCls != nil)

    let subCls = allocateClassPair(baseCls, SubClassName, 0)
    discard addMethod(subCls, selector("addValue:"), addSub)
    registerClassPair(subCls)
    check(subCls != nil)

    let o = cast[NSObject](new(subCls))
    let actual = addValue(o, 10)
    check(actual == 11)
    check(baseSum == 10)
    check(subCallCount == 1)
    check(subReceived == 10)

  test "callSuper with implicit return type":
    const
      BaseClassName = "NimRuntimeCallSuperImplicitRetBase"
      SubClassName = "NimRuntimeCallSuperImplicitRetSub"

    var
      baseCallCount = 0
      subCallCount = 0
      subReceived: ID

    proc identityBase(self: ID, cmd: SEL, value: ID): ID {.cdecl.} =
      inc(baseCallCount)
      value

    proc identitySub(self: ID, cmd: SEL, value: ID): ID {.cdecl.} =
      inc(subCallCount)
      subReceived = value
      result = callSuper(cast[NSObject](self), cmd, value)

    proc identity(self: NSObject, value: NSObject): NSObject {.objc: "identity:".}

    let baseCls = allocateClassPair(getClass("NSObject"), BaseClassName, 0)
    discard addMethod(baseCls, selector("identity:"), identityBase)
    registerClassPair(baseCls)
    check(baseCls != nil)

    let subCls = allocateClassPair(baseCls, SubClassName, 0)
    discard addMethod(subCls, selector("identity:"), identitySub)
    registerClassPair(subCls)
    check(subCls != nil)

    let o = cast[NSObject](new(subCls))
    let arg = cast[NSObject](new(getClass("NSObject")))
    let actual = identity(o, arg)
    check(actual == arg)
    check(subReceived == cast[ID](arg))
    check(baseCallCount == 1)
    check(subCallCount == 1)

  test "callSuper no args with explicit return type":
    const
      BaseClassName = "NimRuntimeCallSuperNoArgsBase"
      SubClassName = "NimRuntimeCallSuperNoArgsSub"

    var
      baseCallCount = 0
      subCallCount = 0

    proc valueBase(self: ID, cmd: SEL): cint {.cdecl.} =
      inc(baseCallCount)
      41

    proc valueSub(self: ID, cmd: SEL): cint {.cdecl.} =
      inc(subCallCount)
      result = callSuper(cint, cast[NSObject](self), cmd)
      inc(result)

    proc value(self: NSObject): cint {.objc: "value".}

    let baseCls = allocateClassPair(getClass("NSObject"), BaseClassName, 0)
    discard addMethod(baseCls, selector("value"), valueBase)
    registerClassPair(baseCls)
    check(baseCls != nil)

    let subCls = allocateClassPair(baseCls, SubClassName, 0)
    discard addMethod(subCls, selector("value"), valueSub)
    registerClassPair(subCls)
    check(subCls != nil)

    let o = cast[NSObject](new(subCls))
    let actual = value(o)
    check(actual == 42)
    check(baseCallCount == 1)
    check(subCallCount == 1)

  test "callSuper no args with implicit return type":
    const
      BaseClassName = "NimRuntimeCallSuperNoArgsImplicitRetBase"
      SubClassName = "NimRuntimeCallSuperNoArgsImplicitRetSub"

    var
      baseCallCount = 0
      subCallCount = 0

    proc selfObjectBase(self: ID, cmd: SEL): ID {.cdecl, varargs.} =
      inc(baseCallCount)
      self

    proc selfObjectSub(self: ID, cmd: SEL): ID {.cdecl, varargs.} =
      inc(subCallCount)
      result = callSuper(cast[NSObject](self), cmd)

    proc selfObject(self: NSObject): NSObject {.objc: "selfObject".}

    let baseCls = allocateClassPair(getClass("NSObject"), BaseClassName, 0)
    discard addMethod(baseCls, selector("selfObject"), selfObjectBase)
    registerClassPair(baseCls)
    check(baseCls != nil)

    let subCls = allocateClassPair(baseCls, SubClassName, 0)
    discard addMethod(subCls, selector("selfObject"), selfObjectSub)
    registerClassPair(subCls)
    check(subCls != nil)

    let o = cast[NSObject](new(subCls))
    let actual = selfObject(o)
    check(cast[ID](actual) == cast[ID](o))
    check(baseCallCount == 1)
    check(subCallCount == 1)

  when not defined(arm64):
    test "callSuper with NSRect return":
      const
        BaseClassName = "NimRuntimeCallSuperStretBase"
        SubClassName = "NimRuntimeCallSuperStretSub"

      var
        baseRectCount = 0
        subRectCount = 0

      proc testRectBase(self: ID, cmd: SEL): NSRect {.cdecl.} =
        inc(baseRectCount)
        NSMakeRect(1, 2, 30, 40)

      proc testRectSub(self: ID, cmd: SEL): NSRect {.cdecl.} =
        inc(subRectCount)
        result = callSuper(NSRect, cast[NSObject](self), cmd)
        result.origin.x += 10
        result.size.width += 5

      proc testRect(self: NSObject): NSRect {.objc: "testRect".}

      var baseCls: ObjcClass
      addClass(BaseClassName, "NSObject", baseCls):
        addMethod("testRect", testRectBase)
      check(baseCls != nil)

      var subCls: ObjcClass
      addClass(SubClassName, BaseClassName, subCls):
        addMethod("testRect", testRectSub)
      check(subCls != nil)

      let o = cast[NSObject](new(subCls))
      let r = testRect(o)
      check(r == NSMakeRect(11, 2, 35, 40))
      check(baseRectCount == 1)
      check(subRectCount == 1)
