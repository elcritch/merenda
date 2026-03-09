when not declared(getAssociatedRef):
  import ./assoc

objcImpl:
  type NXArrayIndexedReading {.structural.} =
    concept self
        method count(self: NXArrayIndexedReading): NSUInteger
        method objectAtIndex(self: NXArrayIndexedReading, index: NSUInteger): NSObject

objcImpl:
  type NXArraySelectorPerformer {.structural.} =
    concept self
        method performSelector(self: NXArraySelectorPerformer, selector: SEL): NSObject

proc nxArrayAppendObjectsFromArray(
    target: var seq[NSObject], source: NSArray[NSObject]
) =
  if source.isNil:
    return
  let sourceWrapper = source.NSObject.asWrapper(NXArrayIndexedReading)
  if sourceWrapper.isNil:
    return
  let total = sourceWrapper.count().int
  for i in 0 ..< total:
    target.add(sourceWrapper.objectAtIndex(i.NSUInteger))

proc selectorFromNSString(selectorName: NSString): SEL =
  if selectorName.isNil:
    return nil
  let selectorText = $selectorName
  if selectorText.len == 0:
    return nil
  sel_registerName(selectorText.cstring)

objcImpl:
  type NXArray* {.impl: NSCopying.} = object of NSObject
    xData: seq[NSObject]

  method init*(self: var NXArray): NXArray =
    result = callSuperAs[NXArray](self, getSelector("init"))
    if result.isNil:
      return
    initIvarFields(result)
    result.xData = @[]

  method dealloc*(self: NXArray) =
    self.xData = @[]
    destroyIvarFields(self)
    discard callSuperAs[IDPtr](self, getSelector("dealloc"))

  method count*(self: NXArray): NSUInteger =
    if self.isNil:
      return 0
    self.xData().len.NSUInteger

  method objectAtIndex*(self: NXArray, index: NSUInteger): NSObject =
    if self.isNil:
      raise newException(IndexDefect, "index out of bounds in NSArray")
    self.xData()[index]

objcImpl:
  method initWithArray*(self: var NXArray, other: NXArray): NXArray =
    result = self.init()
    if result.isNil:
      return
    var data: seq[NSObject] = @[]
    for i in 0 ..< other.NXArray.count():
      data.add(other.objectAtIndex(i.NSUInteger))
    result.xData = data

  method initWithCapacity*(self: var NXArray, capacity: NSUInteger): NXArray =
    result = self.init()
    if result.isNil:
      return
    result.xData = newSeqOfCap[NSObject](capacity.int)

  method firstObject*(self: NXArray): NSObject =
    if self.isNil:
      return
    let data = self.xData()
    if data.len == 0:
      return
    self.xData()[0]

  method lastObject*(self: NXArray): NSObject =
    if self.isNil:
      return
    let data = self.xData()
    if data.len == 0:
      return
    self.xData()[^1]

  method containsObject*(self: NXArray, value: NSObject): bool =
    self.indexOfObject(value) != high(NSUInteger)

  method indexOfObject*(self: NXArray, value: NSObject): NSUInteger =
    if self.isNil:
      return high(NSUInteger)
    let data = self.xData()
    for i, candidate in data.pairs:
      if candidate.isEqual(value):
        return i.NSUInteger
    high(NSUInteger)

  method arrayByAddingObject*(self: NXArray, value: NSObject): NXArray =
    var allocated = NXArray.alloc()
    var created = allocated.init()
    allocated.value = nil
    if created.isNil:
      return
    var data =
      if self.isNil:
        @[]
      else:
        self.xData()
    data.add(boxNSObject(value))
    created.xData = data
    created

  method arrayByAddingObjectsFromArray*(
      self: NXArray, other: NSArray[NSObject]
  ): NXArray =
    var allocated = NXArray.alloc()
    var created = allocated.init()
    allocated.value = nil
    if created.isNil:
      return
    var data =
      if self.isNil:
        @[]
      else:
        self.xData()
    nxArrayAppendObjectsFromArray(data, other)
    created.xData = data
    created

  method addObject*(self: NXArray, value: NSObject) =
    if self.isNil:
      return
    var data = self.xData()
    data.add(boxNSObject(value))
    self.xData = data

  method addObjectsFromArray*(self: NXArray, other: NSArray[NSObject]) =
    if self.isNil:
      return
    var data = self.xData()
    nxArrayAppendObjectsFromArray(data, other)
    self.xData = data

  method insertObject*(
      self: NXArray, value: NSObject, index {.kw("atIndex").}: NSUInteger
  ) =
    if self.isNil:
      return
    var data = self.xData()
    let idx = index.int
    if idx < 0 or idx > data.len:
      raise newException(IndexDefect, "index out of bounds in NSMutableArray")
    data.insert(boxNSObject(value), idx)
    self.xData = data

  method replaceObjectAtIndex*(
      self: NXArray, index: NSUInteger, value {.kw("withObject").}: NSObject
  ) =
    if self.isNil:
      return
    var data = self.xData()
    let idx = index.int
    data[idx] = boxNSObject(value)
    self.xData = data

  method removeObjectAtIndex*(self: NXArray, index: NSUInteger) =
    if self.isNil:
      return
    var data = self.xData()
    let idx = index.int
    data.delete(idx)
    self.xData = data

  method removeLastObject*(self: NXArray) =
    if self.isNil:
      return
    var data = self.xData()
    if data.len == 0:
      return
    data.setLen(data.len - 1)
    self.xData = data

  method removeAllObjects*(self: NXArray) =
    if self.isNil:
      return
    self.xData = @[]

  method setArray*(self: NXArray, other: NSArray[NSObject]) =
    if self.isNil:
      return
    var data: seq[NSObject] = @[]
    nxArrayAppendObjectsFromArray(data, other)
    self.xData = data

  method makeObjectsPerformSelector*(self: NXArray, selector: SEL) =
    if self.isNil or cast[pointer](selector).isNil:
      return
    let data = self.xData()
    for value in data.items:
      if value.isNil:
        continue
      let performer = value.asWrapper(NXArraySelectorPerformer)
      if performer.isNil:
        continue
      discard performer.performSelector(selector)

  method copyWithZone*(self: NXArray, zone: pointer): NSObject =
    if self.isNil:
      return
    var allocated = NXArray.alloc()
    var copied = init(allocated)
    allocated.value = nil
    if copied.isNil:
      return
    copied.xData = self.xData()
    asTypeRaw[NSObject](move(copied.value))

  method mutableCopyWithZone*(self: NXArray, zone: pointer): NSObject =
    if self.isNil:
      return
    var allocated = NXArray.alloc()
    var copied = allocated.init()
    allocated.value = nil
    if copied.isNil:
      return
    copied.xData = self.xData()
    asTypeRaw[NSObject](move(copied.value))

  method isEqual*(self: NXArray, other: NSObject): bool =
    if self.value == other.value:
      return true
    if self.isNil or other.isNil:
      return false
    let otherArray = other.asWrapper(NXArrayIndexedReading)
    if otherArray.isNil:
      return false

    let selfData = self.xData()
    let selfCount = selfData.len
    if otherArray.count().int != selfCount:
      return false

    for i in 0 ..< selfCount:
      let lhs = selfData[i]
      let rhs = otherArray.objectAtIndex(i.NSUInteger)
      if not lhs.isEqual(rhs):
        return false
    true

proc nsArray*[T](): NSArray[T] =
  var allocated = NXArray.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NSArray[T](value: nil)
  NSArray[T](created.NSObject)

proc nsMutableArray*[T](): NSMutableArray[T] =
  var allocated = NXArray.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NSMutableArray[T](value: nil)
  NSMutableArray[T](created.NSObject)

proc init*[T](n: typedesc[NSArray[T]]): NSArray[T] {.inline.} =
  nsArray[T]()

proc new*[T](n: typedesc[NSArray[T]]): NSArray[T] {.inline.} =
  nsArray[T]()

proc array*[T](n: typedesc[NSArray[T]]): NSArray[T] {.inline.} =
  nsArray[T]()

proc arrayWithObject*[T](n: typedesc[NSArray[T]], value: T): NSArray[T] =
  result = nsArray[T]()
  if result.isNil:
    return
  let obj = NXArray(result)
  obj.addObject(boxNSObject(value))

proc arrayWithArray*[T](n: typedesc[NSArray[T]], other: NSArray[T]): NSArray[T] =
  result = nsArray[T]()
  if result.isNil:
    return
  let obj = NXArray(result)
  obj.setArray(NSArray[NSObject](other.NSObject))

proc init*[T](n: typedesc[NSMutableArray[T]]): NSMutableArray[T] {.inline.} =
  nsMutableArray[T]()

proc new*[T](n: typedesc[NSMutableArray[T]]): NSMutableArray[T] {.inline.} =
  nsMutableArray[T]()

proc mutableArray*[T](n: typedesc[NSMutableArray[T]]): NSMutableArray[T] {.inline.} =
  nsMutableArray[T]()

proc array*[T](n: typedesc[NSMutableArray[T]]): NSMutableArray[T] {.inline.} =
  nsMutableArray[T]()

proc arrayWithCapacity*[T](
    n: typedesc[NSMutableArray[T]], capacity: NSUInteger
): NSMutableArray[T] =
  var allocated = NXArray.alloc()
  var created = allocated.initWithCapacity(capacity)
  allocated.value = nil
  if created.isNil:
    return NSMutableArray[T](value: nil)
  NSMutableArray[T](created.NSObject)

proc arrayWithArray*[T](
    n: typedesc[NSMutableArray[T]], other: NSArray[T]
): NSMutableArray[T] =
  result = nsMutableArray[T]()
  if result.isNil:
    return
  let obj = NXArray(result.NSObject)
  obj.setArray(NSArray[NSObject](other.NSObject))

proc nsMutableArray*[T](values: openArray[T]): NSMutableArray[T] =
  result = nsMutableArray[T]()
  if result.isNil:
    return
  let obj = NXArray(result.NSObject)
  for value in values:
    obj.addObject(boxNSObject(value))

proc nsArray*[T](values: openArray[T]): NSArray[T] =
  result = nsArray[T]()
  if result.isNil:
    return
  let obj = NXArray(result)
  for value in values:
    obj.addObject(boxNSObject(value))

proc nsArrayObjects*(values: openArray[NSObject]): NSArray[NSObject] {.inline.} =
  nsArray(values)

proc nsMutableArrayObjects*(
    values: openArray[NSObject]
): NSMutableArray[NSObject] {.inline.} =
  nsMutableArray(values)

proc copy*[T](arr: NSArray[T]): NSArray[T] =
  if arr.isNil:
    return
  let obj = NXArray(arr.NSObject)
  var copied = obj.copyWithZone(nil)
  if copied.isNil:
    return
  NSArray[T](copied)

proc mutableCopy*[T](arr: NSArray[T]): NSMutableArray[T] =
  if arr.isNil:
    return
  let obj = NXArray(arr.NSObject)
  var copied = obj.mutableCopyWithZone(nil)
  if copied.isNil:
    return
  NSMutableArray[T](copied)

proc copy*[T](arr: NSMutableArray[T]): NSArray[T] =
  copy(NSArray[T](arr))

proc mutableCopy*[T](arr: NSMutableArray[T]): NSMutableArray[T] =
  mutableCopy(NSArray[T](arr))

proc makeObjectsPerformSelector*[T](arr: NSArray[T], selector: SEL) =
  if arr.isNil or selector.isNil:
    return
  let obj = NXArray(arr.NSObject)
  obj.makeObjectsPerformSelector(selector)

proc makeObjectsPerformSelector*[T](arr: NSArray[T], selectorName: NSString) =
  arr.makeObjectsPerformSelector(selectorFromNSString(selectorName))

proc count*[T](arr: NSArray[T]): NSUInteger {.inline.} =
  if arr.isNil:
    return 0
  let obj = NXArray(arr.NSObject)
  obj.count()

proc len*[T](arr: NSArray[T]): int {.inline.} =
  arr.count().int

proc isEmpty*[T](arr: NSArray[T]): bool {.inline.} =
  arr.len == 0

proc objectAtIndex*[T](arr: NSArray[T], index: NSUInteger): T =
  if arr.isNil:
    raise newException(IndexDefect, "index out of bounds in NSArray")
  let obj = NXArray(arr.NSObject)
  unboxNSObject[T](obj.objectAtIndex(index))

proc objectAtIndex*[T](arr: NSArray[T], index: int): T =
  if index < 0:
    raise newException(IndexDefect, "index out of bounds in NSArray")
  arr.objectAtIndex(index.NSUInteger)

proc `[]`*[T](arr: NSArray[T], index: int): T {.inline.} =
  arr.objectAtIndex(index)

proc firstObject*[T](arr: NSArray[T]): T =
  if arr.isNil:
    return unboxNSObject[T](NSObject(value: nil))
  let obj = NXArray(arr.NSObject)
  unboxNSObject[T](obj.firstObject())

proc lastObject*[T](arr: NSArray[T]): T =
  if arr.isNil:
    return unboxNSObject[T](NSObject(value: nil))
  let obj = NXArray(arr.NSObject)
  unboxNSObject[T](obj.lastObject())

proc containsObject*[T](arr: NSArray[T], value: T): bool =
  if arr.isNil:
    return false
  let obj = NXArray(arr.NSObject)
  obj.containsObject(boxNSObject(value))

proc contains*[T](arr: NSArray[T], value: T): bool {.inline.} =
  arr.containsObject(value)

proc indexOfObject*[T](arr: NSArray[T], value: T): NSUInteger =
  if arr.isNil:
    return high(NSUInteger)
  let obj = NXArray(arr.NSObject)
  obj.indexOfObject(boxNSObject(value))

proc arrayByAddingObject*[T](arr: NSArray[T], value: T): NSArray[T] =
  var source = arr
  if source.isNil:
    source = nsArray[T]()
  let obj = NXArray(source.NSObject)
  var added = obj.arrayByAddingObject(boxNSObject(value))
  if added.isNil:
    return
  NSArray[T](added.NSObject)

proc arrayByAddingObjectsFromArray*[T](arr: NSArray[T], other: NSArray[T]): NSArray[T] =
  var source = arr
  if source.isNil:
    source = nsArray[T]()
  let obj = NXArray(source.NSObject)
  var added = obj.arrayByAddingObjectsFromArray(NSArray[NSObject](other.NSObject))
  if added.isNil:
    return
  NSArray[T](added.NSObject)

proc addObject*[T](arr: NSMutableArray[T], value: T) =
  if arr.isNil:
    return
  let obj = NXArray(arr)
  obj.addObject(boxNSObject(value))

proc addObjectsFromArray*[T](arr: NSMutableArray[T], other: NSArray[T]) =
  if arr.isNil:
    return
  let obj = NXArray(arr)
  obj.addObjectsFromArray(NSArray[NSObject](other.NSObject))

proc insertObject*[T](arr: NSMutableArray[T], value: T, index: NSUInteger) =
  if arr.isNil:
    return
  let obj = NXArray(arr)
  obj.insertObject(boxNSObject(value), index)

proc insert*[T](arr: NSMutableArray[T], index: int, value: T) {.inline.} =
  if index < 0:
    raise newException(IndexDefect, "index out of bounds in NSMutableArray")
  arr.insertObject(value, index.NSUInteger)

proc replaceObjectAtIndex*[T](arr: NSMutableArray[T], index: NSUInteger, value: T) =
  if arr.isNil:
    return
  let obj = NXArray(arr)
  obj.replaceObjectAtIndex(index, boxNSObject(value))

proc `[]=`*[T](arr: NSMutableArray[T], index: int, value: T) {.inline.} =
  if index < 0:
    raise newException(IndexDefect, "index out of bounds in NSMutableArray")
  arr.replaceObjectAtIndex(index.NSUInteger, value)

proc removeObjectAtIndex*[T](arr: var NSMutableArray[T], index: NSUInteger) =
  if arr.isNil:
    return
  let obj = NXArray(arr.NSObject)
  obj.removeObjectAtIndex(index)

proc del*[T](arr: NSMutableArray[T], index: int) {.inline.} =
  if index < 0:
    raise newException(IndexDefect, "index out of bounds in NSMutableArray")
  arr.removeObjectAtIndex(index.NSUInteger)

proc removeLastObject*[T](arr: NSMutableArray[T]) =
  if arr.isNil:
    return
  let obj = NXArray(arr)
  obj.removeLastObject()

proc removeAllObjects*[T](arr: NSMutableArray[T]) =
  if arr.isNil:
    return
  let obj = NXArray(arr)
  obj.removeAllObjects()

proc clear*[T](arr: var NSMutableArray[T]) {.inline.} =
  arr.removeAllObjects()

proc setArray*[T](arr: var NSMutableArray[T], other: NSArray[T]) =
  if arr.isNil:
    return
  let obj = NXArray(arr)
  obj.setArray(NSArray[NSObject](other.NSObject))

proc add*[T](arr: NSMutableArray[T], value: T) {.inline.} =
  arr.addObject(value)

proc toSeq*[T](arr: NSArray[T]): seq[T] =
  if arr.isNil:
    return @[]
  let total = arr.len
  result = newSeqOfCap[T](total)
  for i in 0 ..< total:
    result.add(arr.objectAtIndex(i.NSUInteger))

iterator items*[T](arr: NSArray[T]): T =
  let total = arr.len
  for i in 0 ..< total:
    yield arr.objectAtIndex(i.NSUInteger)

iterator pairs*[T](arr: NSArray[T]): tuple[index: int, value: T] =
  let total = arr.len
  for i in 0 ..< total:
    yield (i, arr.objectAtIndex(i.NSUInteger))

proc `==`*[T](a, b: NSArray[T]): bool =
  if a.value == b.value:
    return true
  if a.isNil or b.isNil:
    return false
  if a.len != b.len:
    return false
  for i in 0 ..< a.len:
    if a.objectAtIndex(i.NSUInteger) != b.objectAtIndex(i.NSUInteger):
      return false
  true
