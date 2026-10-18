import std/[algorithm, random, unittest]

import merenda/nimkit/foundation/private/itemcollections

type
  CollectionItem = object
    identifier: string
    hidden: bool
    value: int

  CopyProbe = object
    value: int

  ProbedItem = object
    identifier: string
    hidden: bool
    payload: CopyProbe

var payloadCopies: int

proc `=copy`(dest: var CopyProbe, source: CopyProbe) =
  inc payloadCopies
  dest.value = source.value

proc verifyIndexes(
    collection: var ItemCollection[CollectionItem], sourceLookups = true
) =
  let items = collection.items
  check collection.len == items.len
  let filter = proc(item: CollectionItem): bool =
    item.value mod 3 != 0
  collection.arrange(
    filter,
    proc(left, right: int): int =
      cmp(items[right].value, items[left].value),
  )
  var expected: seq[int]
  for index, item in collection:
    if not item.hidden and filter(item):
      expected.add index
  expected.sort(
    proc(left, right: int): int =
      cmp(items[right].value, items[left].value)
  )
  check collection.arrangedIndexes == expected
  for identifier in ["", "a", "b", "c", "missing"]:
    var
      sourceIndex = -1
      arrangedIndex = -1
    for index, item in collection:
      if item.identifier == identifier:
        sourceIndex = index
        break
    for index, source in expected:
      if collection.items[source].identifier == identifier:
        arrangedIndex = index
        break
    if sourceLookups:
      check collection.sourceIndexOfIdentifier(identifier) == sourceIndex
    check collection.arrangedIndexOfIdentifier(identifier) == arrangedIndex

suite "NimKit shared item collections":
  test "visible identity queries defer hidden source identities":
    var items: seq[CollectionItem]
    for index in 0 ..< 10000:
      items.add CollectionItem(identifier: $index, hidden: index != 0)
    var collection = initItemCollection(items)
    let before = getAllocStats()
    collection.arrange(nil)
    check collection.arrangedIndexOfIdentifier("0") == 0
    let allocations = getAllocStats() - before
    when defined(nimAllocStats):
      for name, count in fieldPairs(allocations):
        when name == "allocCount":
          check count < 32
    check collection.arrangedIndexOfIdentifier("9999") == -1
    check collection.sourceIndexOfIdentifier("9999") == 9999
    check collection.arrangedIndexOfIdentifier("0") == 0
    check collection.arrangedIndexOfIdentifier("9999") == -1

  test "partial identity indexes survive structural mutations and source fill":
    var collection = initItemCollection(
      [
        CollectionItem(identifier: "a", hidden: true, value: 5),
        CollectionItem(identifier: "a", value: 4),
        CollectionItem(identifier: "b", value: 2),
        CollectionItem(identifier: "", value: 7),
      ],
      indexEmptyIdentifiers = true,
    )
    collection.verifyIndexes(sourceLookups = false)
    collection.add CollectionItem(identifier: "c", value: 8)
    collection.verifyIndexes(sourceLookups = false)
    discard collection.insert(CollectionItem(identifier: "b", value: 10), 0)
    collection.verifyIndexes(sourceLookups = false)
    collection.delete(3)
    collection.verifyIndexes(sourceLookups = false)
    discard collection.moveItem(0, 4)
    collection.verifyIndexes(sourceLookups = false)
    # The hidden first source duplicate must win when source positions are filled.
    check collection.arrangedIndexOfIdentifier("a") >= 0
    check collection.sourceIndexOfIdentifier("a") == 0
    collection.verifyIndexes()

  test "arranged generations reject identities from earlier filters":
    var collection = initItemCollection(
      [CollectionItem(identifier: "a"), CollectionItem(identifier: "b")]
    )
    collection.arrange(nil)
    check collection.arrangedIndexOfIdentifier("a") == 0
    check collection.arrangedIndexOfIdentifier("b") == 1
    for identifier in ["a", "b", "a", "missing"]:
      collection.invalidate()
      collection.arrange(
        proc(item: CollectionItem): bool =
          item.identifier == identifier
      )
      check collection.arrangedIndexOfIdentifier("a") ==
        (if identifier == "a": 0 else: -1)
      check collection.arrangedIndexOfIdentifier("b") ==
        (if identifier == "b": 0 else: -1)
    check collection.sourceIndexOfIdentifier("a") == 0
    check collection.sourceIndexOfIdentifier("b") == 1
    check collection.arrangedIndexOfIdentifier("a") == -1
    check collection.arrangedIndexOfIdentifier("b") == -1

  test "identity indexes and arrangements borrow item payloads":
    var items: seq[ProbedItem]
    for index in 0 ..< 128:
      items.add ProbedItem(identifier: $index, payload: CopyProbe(value: index))
    var collection = initItemCollection(items)
    payloadCopies = 0
    check collection.len == 128
    check collection[0].payload.value == 0
    check collection[127].payload.value == 127
    check collection.sourceIndexOfIdentifier("127") == 127
    collection.arrange(nil)
    check collection.arrangedIndexOfIdentifier("127") == 127
    check payloadCopies == 0

    var sum = 0
    for item in collection:
      sum += item.payload.value
    check sum == 8128
    for index, item in collection:
      check item.payload.value == index

    collection.invalidate()
    collection.arrange(
      nil,
      proc(left, right: int): int =
        cmp(right, left),
    )
    sum = 0
    for sourceIndex in collection.arrangedIndexes:
      sum += collection[sourceIndex].payload.value
    check sum == 8128
    for index, sourceIndex in collection.arrangedIndexes:
      check collection[sourceIndex].payload.value == 127 - index
    check payloadCopies == 0

    for index in 128 ..< 256:
      collection.add ProbedItem(identifier: $index, payload: CopyProbe(value: index))
      check collection.sourceIndexOfIdentifier($index) == index
    # Appending may copy the new item, but must never copy existing payloads
    # while rebuilding an identity table.
    check payloadCopies <= 256

  test "arrangement refreshes reuse storage and retry failed predicates":
    var collection = initItemCollection(
      [CollectionItem(identifier: "a"), CollectionItem(identifier: "b")]
    )
    collection.arrange(nil)
    let storage = addr collection.arrangedIndexes[0]
    check collection.arrangedIndexOfIdentifier("b") == 1
    for iteration in 0 ..< 10:
      collection.invalidate()
      collection.arrange(nil)
      check addr(collection.arrangedIndexes[0]) == storage
      check collection.arrangedIndexOfIdentifier("b") == 1

    collection.invalidate()
    expect ValueError:
      collection.arrange(
        proc(item: CollectionItem): bool =
          if item.identifier == "b":
            raise newException(ValueError, "retry")
          true
      )
    check not collection.arrangementValid
    collection.arrange(nil)
    check collection.arrangedIndexes == @[0, 1]
    check collection.arrangedIndexOfIdentifier("b") == 1

    collection.invalidate()
    expect ValueError:
      collection.arrange(
        nil,
        proc(left, right: int): int =
          raise newException(ValueError, "retry sort"),
      )
    check not collection.arrangementValid
    collection.arrange(nil)
    check collection.arrangedIndexes == @[0, 1]
    check collection.arrangedIndexOfIdentifier("b") == 1

  test "source and arranged indexes preserve first duplicate identities":
    var collection = initItemCollection(
      [
        CollectionItem(identifier: "a", hidden: true, value: 5),
        CollectionItem(identifier: "a", value: 4),
        CollectionItem(identifier: "b", value: 2),
        CollectionItem(identifier: "", value: 1),
        CollectionItem(identifier: "", value: 7),
      ],
      indexEmptyIdentifiers = true,
    )
    collection.verifyIndexes()
    check collection[0].hidden
    check collection[0].value == 5
    discard collection.moveItem(0, 4)
    collection.verifyIndexes()
    discard collection.moveItem(4, 0)
    collection.verifyIndexes()
    collection.delete(0)
    collection.verifyIndexes()
    discard collection.insert(CollectionItem(identifier: "a", value: 8), 0)
    collection.verifyIndexes()
    collection.delete(3)
    collection.verifyIndexes()
    collection.add CollectionItem(identifier: "a", value: 10)
    collection.verifyIndexes()

  test "identity indexes follow deterministic mixed mutations":
    var
      collection = initItemCollection[CollectionItem](indexEmptyIdentifiers = true)
      rng = initRand(164)
    for iteration in 0 ..< 300:
      let item = CollectionItem(
        identifier: ["", "a", "b", "c"][rng.rand(3)],
        hidden: rng.rand(3) == 0,
        value: iteration,
      )
      case rng.rand(4)
      of 0:
        collection.replaceItems([item])
      of 1:
        collection.add item
      of 2:
        discard collection.insert(item, rng.rand(collection.len + 4) - 2)
      of 3:
        if collection.len > 0:
          collection.delete(rng.rand(collection.items.high))
      else:
        if collection.len > 0:
          discard collection.moveItem(
            rng.rand(collection.items.high), rng.rand(collection.len + 4) - 2
          )
      collection.verifyIndexes()

  test "empty identifiers remain excluded for table collections":
    var collection = initItemCollection(
      [CollectionItem(identifier: ""), CollectionItem(identifier: "a")]
    )
    collection.arrange(nil)
    check collection.sourceIndexOfIdentifier("") == -1
    check collection.arrangedIndexOfIdentifier("") == -1
    check collection.sourceIndexOfIdentifier("a") == 1
    collection.delete(0)
    discard collection.insert(CollectionItem(identifier: ""), 0)
    check collection.sourceIndexOfIdentifier("") == -1
    check collection.sourceIndexOfIdentifier("a") == 1
