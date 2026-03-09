import std/[tables, unittest]
import knutella/objc

objcImpl:
  type NamePragmaStringValue {.structural.} =
    concept self
        method strings(self: NamePragmaStringValue): NSString {.name: "string".}

objcImpl:
  type NamePragmaStringBox = object of NSObject

  method asString(self: NamePragmaStringBox): NSString {.name: "string".} =
    @ns"name pragma"

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
    let keyObj = retain(asTypeRaw[NSObject](keyString))
    let valueObj = retain(asTypeRaw[NSObject](valueString))
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

    let retainBefore = retainCount(intObj)
    check(retainCount(intObj) == 1)
    var copied = intObj.copyWithZone(nil)
    check(not copied.isNil)
    check(copied.value == intObj.value)
    check(retainCount(intObj) == 2)
    check(unboxNSObject[int](copied) == 42)
    if not copied.isNil:
      release(copied)

  test "structural protocols support asWrapper":
    let boxedInt = @ns(42)
    check(boxedInt.isWrapper(IntValue))
    let intLike = boxedInt.asWrapper(IntValue)
    check(not intLike.isNil)
    if not intLike.isNil:
      check(intLike.intValue() == 42)

    let plainObject = NSObject.new()
    check(not plainObject.isWrapper(IntValue))
    let forcedIntLike = plainObject.castWrapper(IntValue)
    check(not forcedIntLike.isNil)
    let notIntLike = plainObject.asWrapper(IntValue)
    check(notIntLike.isNil)

  test "structural name pragma remaps base selector":
    let box = NamePragmaStringBox.new()
    check(box.isWrapper(NamePragmaStringValue))
    let wrapped = box.asWrapper(NamePragmaStringValue)
    check(not wrapped.isNil)
    if not wrapped.isNil:
      check($wrapped.strings() == "name pragma")

  test "@ns boxes and unboxes float and bool":
    let floatObj = @ns(3.25)
    check(abs(unboxNSObject[cdouble](floatObj) - 3.25) < 0.0000001)
    check(unboxNSObject[cfloat](floatObj) > 3.24'f32)

    let trueObj = @ns(true)
    let falseObj = @ns(false)
    check(unboxNSObject[bool](trueObj) == true)
    check(unboxNSObject[bool](falseObj) == false)
    check(unboxNSObject[NSInteger](trueObj) == 1)

  test "NSArray supports Cocoa-style lookup and copy operations":
    var values = nsArray([1, 2, 3])
    check(values.count() == 3.NSUInteger)
    check(values.len == 3)
    check(values.objectAtIndex(0.NSUInteger) == 1)
    check(values[2] == 3)
    check(values.firstObject() == 1)
    check(values.lastObject() == 3)
    check(values.containsObject(2))
    check(values.indexOfObject(2) == 1.NSUInteger)

    var addedOne = values.arrayByAddingObject(4)
    check(values.toSeq() == @[1, 2, 3])
    check(addedOne.toSeq() == @[1, 2, 3, 4])

    var addedMany = values.arrayByAddingObjectsFromArray(nsArray([5, 6]))
    check(addedMany.toSeq() == @[1, 2, 3, 5, 6])
    values = NSArray[int](value: nil)
    addedOne = NSArray[int](value: nil)
    addedMany = NSArray[int](value: nil)

  test "NSMutableArray supports Cocoa and Nim-style mutating operations":
    var values = nsMutableArray([1, 2, 3])
    check(values.len == 3)
    values.addObject(4)
    values.insertObject(99, 1.NSUInteger)
    check(values.toSeq() == @[1, 99, 2, 3, 4])

    values.replaceObjectAtIndex(1.NSUInteger, 10)
    values.removeObjectAtIndex(0.NSUInteger)
    check(values.toSeq() == @[10, 2, 3, 4])

    values.removeLastObject()
    check(values.toSeq() == @[10, 2, 3])

    values.add(11)
    values.insert(0, 8)
    values[1] = 9
    values.del(2)
    check(values.toSeq() == @[8, 9, 3, 11])

    values.setArray(nsArray([42, 43]))
    check(values.toSeq() == @[42, 43])

    values.clear()
    check(values.isEmpty)
    values = NSMutableArray[int](value: nil)

  test "NSArray var wrappers delegate mutation via NSMutableArray":
    var values = nsArray([1, 2, 3])
    values.add(4)
    values.insert(1, 99)
    values[1] = 10
    values.del(0)
    check(values.toSeq() == @[10, 2, 3, 4])
    values.clear()
    check(values.isEmpty)
    values = NSArray[int](value: nil)

  test "NSArray supports makeObjectsPerformSelector":
    let words = nsArray([@ns"one", @ns"two"])
    words.makeObjectsPerformSelector(@ns"description")
    check(words.len == 2)

  test "NSSet supports stdlib-style operations":
    var values = nsSet([@ns"a", @ns"b", @ns"a"])
    check(values.len == 2)
    check(values.contains(@ns"a"))
    check(values.contains(@ns"b"))

    values.incl(@ns"c")
    check(values.len == 3)
    check(values.contains(@ns"c"))

    values.excl(@ns"b")
    check(values.len == 2)
    check(not values.contains(@ns"b"))

    var asSeq = values.toSeq()
    check(asSeq.len == 2)
    check(values == nsSet([@ns"c", @ns"a"]))

    values.clear()
    check(values.isEmpty)

  test "NSIndexSet supports stdlib-style operations":
    var indexes = nsIndexSet([3.NSUInteger, 1.NSUInteger, 3.NSUInteger, 0.NSUInteger])
    check(indexes.len == 3)
    check(indexes.contains(0.NSUInteger))
    check(indexes.contains(1.NSUInteger))
    check(indexes.contains(3.NSUInteger))
    check(indexes.firstIndex() == 0.NSUInteger)
    check(indexes.lastIndex() == 3.NSUInteger)
    check(indexes.toSeq() == @[0.NSUInteger, 1.NSUInteger, 3.NSUInteger])
    var iterated: seq[NSUInteger] = @[]
    for value in indexes.items:
      iterated.add(value)
    check(iterated == @[0.NSUInteger, 1.NSUInteger, 3.NSUInteger])
    check(indexes.indexGreaterThanIndex(0.NSUInteger) == 1.NSUInteger)
    check(indexes.indexGreaterThanOrEqualToIndex(1.NSUInteger) == 1.NSUInteger)
    check(indexes.indexLessThanIndex(1.NSUInteger) == 0.NSUInteger)
    check(indexes.indexLessThanOrEqualToIndex(1.NSUInteger) == 1.NSUInteger)

    indexes.incl(2.NSUInteger)
    check(indexes.toSeq() == @[0.NSUInteger, 1.NSUInteger, 2.NSUInteger, 3.NSUInteger])
    check(indexes.indexGreaterThanIndex(2.NSUInteger) == 3.NSUInteger)
    check(indexes.indexGreaterThanOrEqualToIndex(2.NSUInteger) == 2.NSUInteger)
    check(indexes.indexLessThanIndex(2.NSUInteger) == 1.NSUInteger)
    check(indexes.indexLessThanOrEqualToIndex(2.NSUInteger) == 2.NSUInteger)

    indexes.excl(0.NSUInteger)
    check(indexes.toSeq() == @[1.NSUInteger, 2.NSUInteger, 3.NSUInteger])
    check(indexes == nsIndexSet([3.NSUInteger, 2.NSUInteger, 1.NSUInteger]))
    check(indexes.containsIndexes(nsIndexSet([1.NSUInteger, 3.NSUInteger])))
    check(not indexes.containsIndexes(nsIndexSet([0.NSUInteger, 3.NSUInteger])))

    let single = NSIndexSet.indexSetWithIndex(42.NSUInteger)
    check(single.len == 1)
    check(single.contains(42.NSUInteger))

    let copied = NSIndexSet.indexSetWithIndexSet(indexes)
    check(copied == indexes)
    check(copied.toSeq() == @[1.NSUInteger, 2.NSUInteger, 3.NSUInteger])

    indexes.clear()
    check(indexes.isEmpty)

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
