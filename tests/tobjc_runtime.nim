import std/unittest
import nutella/objc

proc UTF8String*(n: NSString): cstring {.objc: "UTF8String".}
proc initWithUTF8String*(
  o: NSString, str: cstring
): NSString {.objc: "initWithUTF8String:".}

suite "objc runtime ownership fundamentals":
  test "alloc/init NSString roundtrip":
    var s = NSString.alloc().initWithUTF8String("This is a test!")
    check($s.UTF8String == "This is a test!")
    release(s)
    check(s == nil)

  test "retain and release(var) are balanced":
    var o = cast[NSObject](new(getClass("NSObject")))
    check(o != nil)

    let baseCount = retainCount(o).int
    var extra = retain(o)
    check(extra == o)
    let afterRetain = retainCount(o).int
    check(afterRetain > baseCount)

    release(extra)
    check(extra == nil)
    check(retainCount(o).int == afterRetain - 1)

    release(o)
    check(o == nil)

  test "copy increments retain count":
    var o = cast[NSObject](new(getClass("NSObject")))
    let baseCount = retainCount(o).int

    var alias = o
    check(alias == o)
    check(retainCount(o).int == baseCount + 1)

    release(alias)
    check(alias == nil)
    check(retainCount(o).int == baseCount)

    release(o)
    check(o == nil)
