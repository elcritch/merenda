import std/[tables, unittest]
import nutella/objc

suite "foundation stdlib-backed core types":
  test "NSString supports Nim string semantics":
    let empty = nsString("")
    check(empty.isEmpty)
    check(empty.len == 0)

    let hello = nsString("Hello")
    let world = nsString("World")
    let combined = hello & nsString(", ") & world
    check(not hello.isEmpty)
    check(hello.len == 5)
    check($hello == "Hello")
    check(combined == nsString("Hello, World"))

    var lookup = initTable[NSString, int]()
    lookup[hello] = 1
    check(lookup.hasKey(nsString("Hello")))
    check(lookup[nsString("Hello")] == 1)

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
