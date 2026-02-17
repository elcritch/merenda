import std/unittest
import nutella/objc

var fooBarPingCount = 0
var hiddenPingCount = 0

objcImpl:
  type FooBarProtocol =
    concept self
        method ping(self: FooBarProtocol)

  type FooBar = object of NSObject
  implements FooBar:
    FooBarProtocol

  method ping(self: FooBar) =
    inc fooBarPingCount

objcImpl:
  type HiddenCtorProtocol =
    concept self
        method ping(self: HiddenCtorProtocol)

  type HiddenCtorClass = object of NSObject
  implements HiddenCtorClass:
    HiddenCtorProtocol

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
      doAssert(cast[pointer](proto) != nil)

      var o = FooBar.new()
      doAssert(not o.isNil)
      doAssert(getClassName(o) == "FooBar")

      let sendPing = cast[proc(self: ID, op: SEL) {.cdecl.}](objc_msgSend)
      sendPing(o, selector("ping"))
      doAssert(fooBarPingCount == 1)

  test "constructor-unavailable overloads inside objcImpl":
    hiddenPingCount = 0
    let proto = getProtocol(HiddenCtorProtocol)
    check(cast[pointer](proto) != nil)

    var allocated = HiddenCtorClass.alloc()
    check(not allocated.isNil)
    var o = allocated.initAllowed()
    check(allocated.isNil)
    check(not o.isNil)
    check(getClassName(o) == "HiddenCtorClass")

    let sendPing = cast[proc(self: ID, op: SEL) {.cdecl.}](objc_msgSend)
    sendPing(o, selector("ping"))
    check(hiddenPingCount == 1)
