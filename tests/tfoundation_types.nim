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
    var dict = nsDictionary[NSString, NSObject]()
    check(dict.isEmpty)

    dict[@ns"one"] = boxNSObject(1)
    dict[@ns"two"] = boxNSObject(2)
    check(dict.len == 2)
    check(dict.hasKey(@ns"one"))
    check(unboxNSObject[int](dict[@ns"two"]) == 2)
    check(not dict.hasKey(@ns"missing"))

    dict.del(@ns"one")
    check(not dict.hasKey(@ns"one"))
    check(dict.len == 1)

    dict.clear()
    check(dict.isEmpty)

  test "NSDictionary equality and iteration":
    var dictA = nsDictionary[NSString, NSObject]()
    dictA[@ns"alpha"] = boxNSObject(1)
    dictA[@ns"beta"] = boxNSObject(2)
    dictA[@ns"gamma"] = boxNSObject(3)

    var dictB = nsDictionary[NSString, NSObject]()
    dictB[@ns"gamma"] = boxNSObject(3)
    dictB[@ns"beta"] = boxNSObject(2)
    dictB[@ns"alpha"] = boxNSObject(1)

    check(dictA == dictB)

    var total = 0
    for _, value in dictA.pairs:
      total += unboxNSObject[int](value)
    check(total == 6)

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
    check(intObj.intValue() == 42.cint)
    check(intObj.integerValue() == 42)

  test "boxed numbers conform to NSCopying via NSValue":
    let proto = getProtocol(NSCopying)
    let protoFromPrototype = getProtocol(NSCopyingPrototype)
    check(not proto.isNil)
    check(not protoFromPrototype.isNil)
    check(proto.isEqual(protoFromPrototype))
    check(getClass(NXInteger).conformsToProtocol(proto))
    check(getClass(NXDouble).conformsToProtocol(proto))

    var intObj = @ns(42)
    var protoObj = asProto[NSCopying](intObj)
    check(not protoObj.isNil)
    if not protoObj.isNil:
      release(protoObj)

    let retainBefore = retainCount(intObj).int
    var copied = intObj.copyWithZone(nil)
    check(not copied.isNil)
    check(copied.value == intObj.value)
    check(retainCount(intObj).int == retainBefore + 1)
    check(unboxNSObject[int](copied) == 42)
    if not copied.isNil:
      release(copied)

  test "@ns boxes and unboxes float and bool":
    let floatObj = @ns(3.25)
    check(abs(unboxNSObject[cdouble](floatObj) - 3.25) < 0.0000001)
    check(unboxNSObject[cfloat](floatObj) > 3.24'f32)

    let trueObj = @ns(true)
    let falseObj = @ns(false)
    check(unboxNSObject[bool](trueObj) == true)
    check(unboxNSObject[bool](falseObj) == false)
    check(unboxNSObject[NSInteger](trueObj) == 1)

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
