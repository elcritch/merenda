import std/[tables, unittest]
import nutella/objc

suite "foundation stdlib-backed core types":
  test "NSString supports Nim string semantics":
    let empty = nsString("")
    let comma = nsString(", ")
    let helloWorld = nsString("Hello, World")
    let helloLookup = nsString("Hello")
    check(empty.isEmpty)
    check(empty.len == 0)

    let hello = nsString("Hello")
    let world = nsString("World")
    let combined = hello & comma & world
    check(not hello.isEmpty)
    check(hello.len == 5)
    check($hello == "Hello")
    check(combined == helloWorld)

    var lookup = initTable[NSString, int]()
    lookup[hello] = 1
    check(lookup.hasKey(helloLookup))
    check(lookup[helloLookup] == 1)

  test "NSDictionary supports set/get/update/remove":
    var dict = nsDictionary[NSString, int]()
    check(dict.isEmpty)

    dict[nsString("one")] = 1
    dict[nsString("two")] = 2
    check(dict.len == 2)
    check(dict.hasKey(nsString("one")))
    check(dict[nsString("two")] == 2)
    check(dict.getOrDefault(nsString("missing"), -1) == -1)

    dict.del(nsString("one"))
    check(not dict.hasKey(nsString("one")))
    check(dict.len == 1)

    dict.clear()
    check(dict.isEmpty)

  test "NSDictionary literal constructor, equality, and iteration":
    let dictA = nsDictionary([("alpha", 1), ("beta", 2), ("gamma", 3)])
    let dictB = nsDictionary([("gamma", 3), ("beta", 2), ("alpha", 1)])
    check(dictA == dictB)

    var total = 0
    for _, value in dictA.pairs:
      total += value
    check(total == 6)

    let asTable = dictA.toTable()
    check(asTable.len == 3)
    check(asTable["alpha"] == 1)

  test "NSDictionary supports NSObject keys and values":
    var dict = nsDictionary[NSObject, NSObject]()
    let keyString = nsString("object-key")
    let valueString = nsString("object-value")
    let keyObj = retain(asType[NSObject](keyString))
    let valueObj = retain(asType[NSObject](valueString))
    dict[keyObj] = valueObj

    check(dict.len == 1)
    check(dict.hasKey(keyObj))
    let fetched = dict[keyObj]
    check(fetched == valueObj)

  test "@ns boxes NSString and NSInteger":
    let stringObj = @ns"boxed-string"
    let expected = @ns"boxed-string"
    check(stringObj == expected)

    let intObj = ns(42)
    check(intObj.integerValue() == 42)
