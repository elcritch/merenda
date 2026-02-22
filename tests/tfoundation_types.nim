import std/[tables, unittest]
import nutella/objc

suite "foundation stdlib-backed core types":
  test "NSString supports Nim string semantics":
    let empty = @ns""
    let comma = @ns", "
    let helloWorld = @ns"Hello, World"
    let helloLookup = @ns"Hello"
    check(empty.isEmpty)
    check(empty.len == 0)

    let hello = @ns"Hello"
    let world = @ns"World"
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

    dict[@ns"one"] = 1
    dict[@ns"two"] = 2
    check(dict.len == 2)
    check(dict.hasKey(@ns"one"))
    check(dict[@ns"two"] == 2)
    check(dict.getOrDefault(@ns"missing", -1) == -1)

    dict.del(@ns"one")
    check(not dict.hasKey(@ns"one"))
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
    let keyString = @ns"object-key"
    let valueString = @ns"object-value"
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

    let intObj = @ns(42)
    check(intObj.integerValue() == 42)

  test "NSArray supports stdlib-style operations":
    var values = nsArray([1, 2, 3])
    check(values.len == 3)
    check(values[0] == 1)
    check(values[2] == 3)

    values.add(4)
    values.insert(1, 99)
    check(values.toSeq() == @[1, 99, 2, 3, 4])

    values[1] = 10
    values.del(0)
    check(values.toSeq() == @[10, 2, 3, 4])
    check(not values.isEmpty)

    values.clear()
    check(values.isEmpty)

  test "@ns[] boxes NSArray literals":
    let empty = @ns[]
    check(empty.isEmpty)

    let ints = @ns[1, 2, 3]
    check(ints.len == 3)
    check(unboxNSObject[int](ints[0]) == 1)
    check(unboxNSObject[int](ints[2]) == 3)

    let mixed = @ns["one", 2, @ns"three"]
    check(mixed.len == 3)
    check(unboxNSObject[string](mixed[0]) == "one")
    check(unboxNSObject[int](mixed[1]) == 2)
    check(unboxNSObject[string](mixed[2]) == "three")
