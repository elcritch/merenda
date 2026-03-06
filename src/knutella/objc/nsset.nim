import std/[hashes, tables]

const NSIndexNotFound* = high(NSUInteger)

proc nxSetObjcIsEqualIds(lhs, rhs: IDPtr): bool {.inline.} =
  if lhs == rhs:
    return true
  if lhs.isNil or rhs.isNil:
    return false
  let isEqualSend = cast[proc(self: IDPtr, op: SEL, other: IDPtr): bool {.
    cdecl, varargs
  .}](objc_msgSend)
  isEqualSend(lhs, sel_registerName("isEqual:"), rhs)

proc nxSetObjcHashId(value: IDPtr): Hash {.inline.} =
  if value.isNil:
    return 0.Hash
  let hashSend =
    cast[proc(self: IDPtr, op: SEL): NSUInteger {.cdecl, varargs.}](objc_msgSend)
  hashSend(value, sel_registerName("hash")).hash

proc nxSetRetainId(id: IDPtr): IDPtr {.inline.} =
  if id.isNil:
    return nil
  let retainSend =
    cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs.}](objc_msgSend)
  retainSend(id, sel_registerName("retain"))

proc nxSetReleaseId(id: IDPtr) {.inline.} =
  if id.isNil:
    return
  let releaseSend =
    cast[proc(self: IDPtr, op: SEL): void {.cdecl, varargs.}](objc_msgSend)
  releaseSend(id, sel_registerName("release"))

proc nxSetRetainedAs[T: NSObject](id: IDPtr): T {.inline.} =
  if id.isNil:
    return T(value: nil)
  asTypeRaw[T](nxSetRetainId(id))

proc nxSetReleaseSetEntries(data: var Table[Hash, seq[IDPtr]]) =
  for bucket in data.values:
    for value in bucket:
      nxSetReleaseId(value)
  data.clear()

proc nxSetEntryCount(data: Table[Hash, seq[IDPtr]]): int =
  for bucket in data.values:
    result += bucket.len

proc nxSetFindEquivalentSetValue(
    data: Table[Hash, seq[IDPtr]], value: IDPtr, matchedValue: var IDPtr
): bool =
  if value.isNil:
    matchedValue = nil
    return false
  let hashed = nxSetObjcHashId(value)
  if not data.hasKey(hashed):
    matchedValue = nil
    return false
  for candidate in data[hashed]:
    if nxSetObjcIsEqualIds(candidate, value):
      matchedValue = candidate
      return true
  matchedValue = nil
  false

proc nxSetInsertSetValue(data: var Table[Hash, seq[IDPtr]], value: IDPtr): bool =
  if value.isNil:
    return false
  var matchedValue: IDPtr
  if nxSetFindEquivalentSetValue(data, value, matchedValue):
    return false
  let hashed = nxSetObjcHashId(value)
  if not data.hasKey(hashed):
    data[hashed] = @[]
  data[hashed].add(nxSetRetainId(value))
  true

proc nxSetRemoveSetValue(data: var Table[Hash, seq[IDPtr]], value: IDPtr): bool =
  if value.isNil:
    return false
  let hashed = nxSetObjcHashId(value)
  if not data.hasKey(hashed):
    return false
  var bucket = data[hashed]
  for i in 0 ..< bucket.len:
    if nxSetObjcIsEqualIds(bucket[i], value):
      nxSetReleaseId(bucket[i])
      bucket.delete(i)
      if bucket.len == 0:
        data.del(hashed)
      else:
        data[hashed] = bucket
      return true
  false

proc nxIndexSetLowerBound(data: openArray[NSUInteger], index: NSUInteger): int =
  var lo = 0
  var hi = data.len
  while lo < hi:
    let mid = lo + (hi - lo) div 2
    if data[mid] < index:
      lo = mid + 1
    else:
      hi = mid
  lo

proc nxIndexSetContains(data: openArray[NSUInteger], index: NSUInteger): bool =
  let position = nxIndexSetLowerBound(data, index)
  position < data.len and data[position] == index

proc nxIndexSetInsert(data: var seq[NSUInteger], index: NSUInteger): bool =
  let position = nxIndexSetLowerBound(data, index)
  if position < data.len and data[position] == index:
    return false
  data.insert(index, position)
  true

proc nxIndexSetRemove(data: var seq[NSUInteger], index: NSUInteger): bool =
  let position = nxIndexSetLowerBound(data, index)
  if position >= data.len or data[position] != index:
    return false
  data.delete(position)
  true

proc nxIndexSetGreaterThan(data: openArray[NSUInteger], index: NSUInteger): NSUInteger =
  let position = nxIndexSetLowerBound(data, index)
  if position >= data.len:
    return NSIndexNotFound
  if data[position] > index:
    return data[position]
  if position + 1 < data.len:
    return data[position + 1]
  NSIndexNotFound

proc nxIndexSetGreaterThanOrEqual(
    data: openArray[NSUInteger], index: NSUInteger
): NSUInteger =
  let position = nxIndexSetLowerBound(data, index)
  if position >= data.len:
    return NSIndexNotFound
  data[position]

proc nxIndexSetLessThan(data: openArray[NSUInteger], index: NSUInteger): NSUInteger =
  if index == 0 or data.len == 0:
    return NSIndexNotFound
  let position = nxIndexSetLowerBound(data, index)
  if position >= data.len:
    return data[^1]
  if data[position] == index:
    if position == 0:
      return NSIndexNotFound
    return data[position - 1]
  if position == 0:
    return NSIndexNotFound
  data[position - 1]

proc nxIndexSetLessThanOrEqual(
    data: openArray[NSUInteger], index: NSUInteger
): NSUInteger =
  if data.len == 0:
    return NSIndexNotFound
  let position = nxIndexSetLowerBound(data, index)
  if position < data.len and data[position] == index:
    return data[position]
  if position == 0:
    return NSIndexNotFound
  data[position - 1]

objcImpl:
  type NXSet* {.impl: NSCopying.} = object of NSObject
    countCache: int
    data: Table[Hash, seq[IDPtr]]

  method init*(self: var NXSet): NXSet =
    result = callSuperAs[NXSet](self, getSelector("init"))
    if result.isNil:
      return
    result.countCache = 0
    result.data = initTable[Hash, seq[IDPtr]]()

  method dealloc*(self: NXSet) =
    var data = self.data()
    nxSetReleaseSetEntries(data)
    self.data = data
    destroyIvarFields(self)
    discard callSuperAs[IDPtr](self, getSelector("dealloc"))

  method copyWithZone*(self: NXSet, zone: pointer): NSObject =
    if self.isNil:
      return NSObject(value: nil)
    NSObject(value: self.value)

  method count*(self: NXSet): NSUInteger =
    if self.countCache() <= 0:
      return 0
    self.countCache().NSUInteger

  method containsObject*(self: NXSet, value: NSObject): bool =
    if self.isNil or value.isNil:
      return false
    let data = self.data()
    var matchedValue: IDPtr
    nxSetFindEquivalentSetValue(data, value.value, matchedValue)

  method member*(self: NXSet, value: NSObject): NSObject =
    if self.isNil or value.isNil:
      return NSObject(value: nil)
    let data = self.data()
    var matchedValue: IDPtr
    if not nxSetFindEquivalentSetValue(data, value.value, matchedValue):
      return NSObject(value: nil)
    nxSetRetainedAs[NSObject](matchedValue)

  method anyObject*(self: NXSet): NSObject =
    if self.isNil:
      return NSObject(value: nil)
    let data = self.data()
    for bucket in data.values:
      if bucket.len > 0:
        return nxSetRetainedAs[NSObject](bucket[0])
    NSObject(value: nil)

  method allObjects*(self: NXSet): NSArray[NSObject] =
    if self.isNil:
      return nsArrayObjects([])
    var values: seq[NSObject] = @[]
    let data = self.data()
    for bucket in data.values:
      for value in bucket:
        values.add(nxSetRetainedAs[NSObject](value))
    nsArrayObjects(values)

  method removeAllObjects*(self: NXSet) =
    if self.isNil:
      return
    var data = self.data()
    nxSetReleaseSetEntries(data)
    self.data = data
    self.countCache = 0

  method isEqual*(self: NXSet, other: NSObject): bool =
    if self.value == other.value:
      return true
    if self.isNil or other.isNil:
      return false
    if not other.respondsToSelector("count") or
        not other.respondsToSelector("containsObject:"):
      return false

    let countSend =
      cast[proc(obj: IDPtr, op: SEL): NSUInteger {.cdecl, varargs.}](objc_msgSend)
    let containsSend = cast[proc(obj: IDPtr, op: SEL, value: IDPtr): bool {.
      cdecl, varargs
    .}](objc_msgSend)

    if countSend(other.value, sel_registerName("count")) != self.count():
      return false

    let data = self.data()
    for bucket in data.values:
      for value in bucket:
        if not containsSend(other.value, sel_registerName("containsObject:"), value):
          return false
    true

objcImpl:
  type NXIndexSet* {.impl: NSCopying.} = object of NSObject
    xData: seq[NSUInteger]
    xCountCache: int

  method init*(self: var NXIndexSet): NXIndexSet =
    result = callSuperAs[NXIndexSet](self, getSelector("init"))
    if result.isNil:
      return
    result.xData = @[]
    result.xCountCache = 0

  method initWithIndex*(self: var NXIndexSet, index: NSUInteger): NXIndexSet =
    result = self.init()
    if result.isNil:
      return
    result.xData = @[index]
    result.xCountCache = 1

  method initWithIndexSet*(self: var NXIndexSet, other: NSIndexSet): NXIndexSet =
    result = self.init()
    if result.isNil:
      return
    if other.isNil:
      return

    if other.isKindOfClass(NXIndexSet):
      let otherObj = other as NXIndexSet
      result.xData = otherObj.xData()
      result.xCountCache = result.xData().len
      return

    if not other.respondsToSelector("firstIndex") or
        not other.respondsToSelector("indexGreaterThanIndex:"):
      return

    let firstSend =
      cast[proc(obj: IDPtr, op: SEL): NSUInteger {.cdecl, varargs.}](objc_msgSend)
    let nextSend = cast[proc(obj: IDPtr, op: SEL, index: NSUInteger): NSUInteger {.
      cdecl, varargs
    .}](objc_msgSend)

    var copied: seq[NSUInteger] = @[]
    var value = firstSend(other.value, sel_registerName("firstIndex"))
    while value != NSIndexNotFound:
      discard nxIndexSetInsert(copied, value)
      value = nextSend(other.value, sel_registerName("indexGreaterThanIndex:"), value)
    result.xData = copied
    result.xCountCache = copied.len

  method dealloc*(self: NXIndexSet) =
    self.xData = @[]
    self.xCountCache = 0
    destroyIvarFields(self)
    discard callSuperAs[IDPtr](self, getSelector("dealloc"))

  method copyWithZone*(self: NXIndexSet, zone: pointer): NSObject =
    if self.isNil:
      return NSObject(value: nil)
    NSObject(value: self.value)

  method count*(self: NXIndexSet): NSUInteger =
    self.xData().len.NSUInteger

  method containsIndex*(self: NXIndexSet, index: NSUInteger): bool =
    if self.isNil:
      return false
    nxIndexSetContains(self.xData(), index)

  method containsIndexes*(self: NXIndexSet, other: NSIndexSet): bool =
    if self.isNil or other.isNil:
      return false
    if not other.respondsToSelector("count"):
      return false

    let countSend =
      cast[proc(obj: IDPtr, op: SEL): NSUInteger {.cdecl, varargs.}](objc_msgSend)
    if countSend(other.value, sel_registerName("count")) == 0:
      return true

    if other.isKindOfClass(NXIndexSet):
      let otherObj = other as NXIndexSet
      for value in otherObj.xData():
        if not nxIndexSetContains(self.xData(), value):
          return false
      return true

    if not other.respondsToSelector("firstIndex") or
        not other.respondsToSelector("indexGreaterThanIndex:"):
      return false

    let firstSend =
      cast[proc(obj: IDPtr, op: SEL): NSUInteger {.cdecl, varargs.}](objc_msgSend)
    let nextSend = cast[proc(obj: IDPtr, op: SEL, index: NSUInteger): NSUInteger {.
      cdecl, varargs
    .}](objc_msgSend)

    var value = firstSend(other.value, sel_registerName("firstIndex"))
    while value != NSIndexNotFound:
      if not nxIndexSetContains(self.xData(), value):
        return false
      value = nextSend(other.value, sel_registerName("indexGreaterThanIndex:"), value)
    true

  method firstIndex*(self: NXIndexSet): NSUInteger =
    if self.isNil:
      return NSIndexNotFound
    let data = self.xData()
    if data.len == 0:
      return NSIndexNotFound
    data[0]

  method lastIndex*(self: NXIndexSet): NSUInteger =
    if self.isNil:
      return NSIndexNotFound
    let data = self.xData()
    if data.len == 0:
      return NSIndexNotFound
    data[^1]

  method indexGreaterThanIndex*(self: NXIndexSet, index: NSUInteger): NSUInteger =
    if self.isNil:
      return NSIndexNotFound
    nxIndexSetGreaterThan(self.xData(), index)

  method indexGreaterThanOrEqualToIndex*(
      self: NXIndexSet, index: NSUInteger
  ): NSUInteger =
    if self.isNil:
      return NSIndexNotFound
    nxIndexSetGreaterThanOrEqual(self.xData(), index)

  method indexLessThanIndex*(self: NXIndexSet, index: NSUInteger): NSUInteger =
    if self.isNil:
      return NSIndexNotFound
    nxIndexSetLessThan(self.xData(), index)

  method indexLessThanOrEqualToIndex*(self: NXIndexSet, index: NSUInteger): NSUInteger =
    if self.isNil:
      return NSIndexNotFound
    nxIndexSetLessThanOrEqual(self.xData(), index)

  method addIndex*(self: NXIndexSet, index: NSUInteger) =
    if self.isNil:
      return
    var data = self.xData()
    if nxIndexSetInsert(data, index):
      self.xData = data
      self.xCountCache = data.len

  method removeIndex*(self: NXIndexSet, index: NSUInteger) =
    if self.isNil:
      return
    var data = self.xData()
    if nxIndexSetRemove(data, index):
      self.xData = data
      self.xCountCache = data.len

  method removeAllIndexes*(self: NXIndexSet) =
    if self.isNil:
      return
    self.xData = @[]
    self.xCountCache = 0

  method isEqual*(self: NXIndexSet, other: NSObject): bool =
    if self.value == other.value:
      return true
    if self.isNil or other.isNil:
      return false
    if not other.respondsToSelector("count") or
        not other.respondsToSelector("containsIndex:"):
      return false
    if other.isKindOfClass(NXIndexSet):
      let otherObj = NSIndexSet(other) as NXIndexSet
      return self.xData() == otherObj.xData()
    let countSend =
      cast[proc(obj: IDPtr, op: SEL): NSUInteger {.cdecl, varargs.}](objc_msgSend)
    let containsSend = cast[proc(obj: IDPtr, op: SEL, index: NSUInteger): bool {.
      cdecl, varargs
    .}](objc_msgSend)
    if countSend(other.value, sel_registerName("count")) != self.count():
      return false
    for value in self.xData():
      if not containsSend(other.value, sel_registerName("containsIndex:"), value):
        return false
    true

proc nsSet*[T: NSObject](): NSSet[T] =
  var allocated = NXSet.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NSSet[T](value: nil)
  result = asTypeRaw[NSSet[T]](move(created.value))

proc init*[T: NSObject](t: typedesc[NSSet[T]]): NSSet[T] {.inline.} =
  nsSet[T]()

proc new*[T: NSObject](t: typedesc[NSSet[T]]): NSSet[T] {.inline.} =
  nsSet[T]()

proc nsSet*[T: NSObject](values: openArray[T]): NSSet[T] =
  var created = nsSet[T]()
  for value in values:
    created.incl(value)
  result = created

proc len*[T: NSObject](setObj: NSSet[T]): int {.inline.} =
  if setObj.value.isNil:
    return 0
  let obj = setObj as NXSet
  obj.countCache()

proc isEmpty*[T: NSObject](setObj: NSSet[T]): bool {.inline.} =
  setObj.len == 0

proc contains*[T: NSObject](setObj: NSSet[T], value: T): bool =
  if setObj.value.isNil or value.isNil:
    return false
  let obj = setObj as NXSet
  obj.containsObject(value.NSObject)

proc incl*[T: NSObject](setObj: var NSSet[T], value: T) =
  if setObj.value.isNil or value.isNil:
    return
  let obj = setObj as NXSet
  var data = obj.data()
  if nxSetInsertSetValue(data, value.value):
    obj.data = data
    obj.countCache = nxSetEntryCount(data)

proc addObject*[T: NSObject](setObj: var NSSet[T], value: T) {.inline.} =
  setObj.incl(value)

proc excl*[T: NSObject](setObj: var NSSet[T], value: T) =
  if setObj.value.isNil or value.isNil:
    return
  let obj = setObj as NXSet
  var data = obj.data()
  if nxSetRemoveSetValue(data, value.value):
    obj.data = data
    obj.countCache = nxSetEntryCount(data)

proc del*[T: NSObject](setObj: var NSSet[T], value: T) {.inline.} =
  setObj.excl(value)

proc clear*[T: NSObject](setObj: var NSSet[T]) {.inline.} =
  if setObj.value.isNil:
    return
  let obj = setObj as NXSet
  obj.removeAllObjects()

proc toSeq*[T: NSObject](setObj: NSSet[T]): seq[T] =
  if setObj.value.isNil:
    return @[]
  let obj = setObj as NXSet
  let data = obj.data()
  for bucket in data.values:
    for value in bucket:
      result.add(nxSetRetainedAs[T](value))

iterator items*[T: NSObject](setObj: NSSet[T]): T =
  if not setObj.value.isNil:
    let obj = setObj as NXSet
    let data = obj.data()
    for bucket in data.values:
      for value in bucket:
        yield nxSetRetainedAs[T](value)

proc `==`*[T: NSObject](a, b: NSSet[T]): bool =
  let aLen = a.len
  let bLen = b.len
  if aLen != bLen:
    return false
  if aLen == 0:
    return true
  for value in a.items:
    if not b.contains(value):
      return false
  true

proc nsIndexSet*(): NSIndexSet =
  var allocated = NXIndexSet.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NSIndexSet(value: nil)
  result = asTypeRaw[NSIndexSet](move(created.value))

proc init*(t: typedesc[NSIndexSet]): NSIndexSet {.inline.} =
  nsIndexSet()

proc new*(t: typedesc[NSIndexSet]): NSIndexSet {.inline.} =
  nsIndexSet()

proc indexSet*(t: typedesc[NSIndexSet]): NSIndexSet {.inline.} =
  nsIndexSet()

proc nsIndexSet*(values: openArray[NSUInteger]): NSIndexSet =
  var created = nsIndexSet()
  let obj = created as NXIndexSet
  for value in values:
    obj.addIndex(value)
  result = created

proc indexSetWithIndex*(t: typedesc[NSIndexSet], index: NSUInteger): NSIndexSet =
  var allocated = NXIndexSet.alloc()
  var created = allocated.initWithIndex(index)
  allocated.value = nil
  if created.isNil:
    return NSIndexSet(value: nil)
  asTypeRaw[NSIndexSet](move(created.value))

proc indexSetWithIndexSet*(t: typedesc[NSIndexSet], other: NSIndexSet): NSIndexSet =
  var allocated = NXIndexSet.alloc()
  var created = allocated.initWithIndexSet(other)
  allocated.value = nil
  if created.isNil:
    return NSIndexSet(value: nil)
  asTypeRaw[NSIndexSet](move(created.value))

proc len*(indexSet: NSIndexSet): int {.inline.} =
  if indexSet.value.isNil:
    return 0
  let obj = indexSet as NXIndexSet
  obj.xCountCache()

proc isEmpty*(indexSet: NSIndexSet): bool {.inline.} =
  indexSet.len == 0

proc contains*(indexSet: NSIndexSet, index: NSUInteger): bool =
  if indexSet.value.isNil:
    return false
  let obj = indexSet as NXIndexSet
  obj.containsIndex(index)

proc containsIndexes*(indexSet: NSIndexSet, other: NSIndexSet): bool =
  if indexSet.value.isNil:
    return false
  let obj = indexSet as NXIndexSet
  obj.containsIndexes(other)

proc firstIndex*(indexSet: NSIndexSet): NSUInteger =
  if indexSet.value.isNil:
    return NSIndexNotFound
  let obj = indexSet as NXIndexSet
  obj.firstIndex()

proc lastIndex*(indexSet: NSIndexSet): NSUInteger =
  if indexSet.value.isNil:
    return NSIndexNotFound
  let obj = indexSet as NXIndexSet
  obj.lastIndex()

proc indexGreaterThanIndex*(indexSet: NSIndexSet, index: NSUInteger): NSUInteger =
  if indexSet.value.isNil:
    return NSIndexNotFound
  let obj = indexSet as NXIndexSet
  obj.indexGreaterThanIndex(index)

proc indexGreaterThanOrEqualToIndex*(
    indexSet: NSIndexSet, index: NSUInteger
): NSUInteger =
  if indexSet.value.isNil:
    return NSIndexNotFound
  let obj = indexSet as NXIndexSet
  obj.indexGreaterThanOrEqualToIndex(index)

proc indexLessThanIndex*(indexSet: NSIndexSet, index: NSUInteger): NSUInteger =
  if indexSet.value.isNil:
    return NSIndexNotFound
  let obj = indexSet as NXIndexSet
  obj.indexLessThanIndex(index)

proc indexLessThanOrEqualToIndex*(indexSet: NSIndexSet, index: NSUInteger): NSUInteger =
  if indexSet.value.isNil:
    return NSIndexNotFound
  let obj = indexSet as NXIndexSet
  obj.indexLessThanOrEqualToIndex(index)

proc incl*(indexSet: var NSIndexSet, index: NSUInteger) =
  if indexSet.value.isNil:
    return
  let obj = indexSet as NXIndexSet
  obj.addIndex(index)

proc excl*(indexSet: var NSIndexSet, index: NSUInteger) =
  if indexSet.value.isNil:
    return
  let obj = indexSet as NXIndexSet
  obj.removeIndex(index)

proc clear*(indexSet: var NSIndexSet) =
  if indexSet.value.isNil:
    return
  let obj = indexSet as NXIndexSet
  obj.removeAllIndexes()

proc toSeq*(indexSet: NSIndexSet): seq[NSUInteger] =
  if indexSet.value.isNil:
    return @[]
  let obj = indexSet as NXIndexSet
  obj.xData()

iterator items*(indexSet: NSIndexSet): NSUInteger =
  let values = indexSet.toSeq()
  for value in values:
    yield value

proc `==`*(a, b: NSIndexSet): bool =
  if a.len != b.len:
    return false
  if a.isEmpty:
    return true
  for value in a.items:
    if not b.contains(value):
      return false
  true
