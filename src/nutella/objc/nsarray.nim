when not declared(getAssociatedRef):
  import ./assoc

type NXArrayData = ref object
  data: seq[NSObject]

objcImpl:
  type NXArray* = object of NSObject
    countCache: int

  method init*(self: var NXArray): NXArray =
    result = callSuperAs[NXArray](self, getSelector("init"))
    if result.isNil:
      return
    result.countCache = 0

  method dealloc*(self: NXArray) =
    clearIvarRefs(self)
    discard callSuperAs[ID](self, getSelector("dealloc"))

  method count*(self: NXArray): NSUInteger =
    if self.countCache() <= 0:
      return 0
    self.countCache().NSUInteger

  method removeAllObjects*(self: NXArray) =
    if self.isNil:
      return
    let store = getAssociatedRef(self, NXArrayData)
    if not store.isNil:
      store.data.setLen(0)
    self.countCache = 0

proc storageForRead[T](arr: NSArray[T]): NXArrayData =
  if arr.value.isNil:
    return nil
  let obj = asRetainedType[NXArray](arr)
  let store = getAssociatedRef(obj, NXArrayData)
  store

proc storageForWrite[T](arr: NSArray[T]): NXArrayData =
  if arr.value.isNil:
    return nil
  let obj = asRetainedType[NXArray](arr)
  let store = getAssociatedRef(obj, NXArrayData)
  store

proc initStorage[T](arr: NSArray[T]) {.inline.} =
  if arr.value.isNil:
    return
  let obj = asRetainedType[NXArray](arr)
  var store = getAssociatedRef(obj, NXArrayData)
  if store.isNil:
    new(store)
    store.data = @[]
    setAssociatedRef(obj, store)
  else:
    store.data.setLen(0)
  obj.countCache = 0

proc syncCount[T](arr: NSArray[T], count: int) {.inline.} =
  if arr.value.isNil:
    return
  let obj = asRetainedType[NXArray](arr)
  obj.countCache = count

proc nsArray*[T](): NSArray[T] =
  var allocated = NXArray.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NSArray[T](value: nil)
  result = asType[NSArray[T]](move(created.value))
  initStorage(result)

proc init*[T](n: typedesc[NSArray[T]]): NSArray[T] {.inline.} =
  nsArray[T]()

proc new*[T](n: typedesc[NSArray[T]]): NSArray[T] {.inline.} =
  nsArray[T]()

proc nsArray*[T](values: openArray[T]): NSArray[T] =
  result = nsArray[T]()
  let store = storageForWrite(result)
  if store.isNil:
    return
  store.data = newSeqOfCap[NSObject](values.len)
  for value in values:
    store.data.add(boxNSObject(value))
  syncCount(result, store.data.len)

proc nsArrayObjects*(values: openArray[NSObject]): NSArray[NSObject] {.inline.} =
  nsArray(values)

proc len*[T](arr: NSArray[T]): int {.inline.} =
  let store = storageForRead(arr)
  if store.isNil:
    return 0
  store.data.len

proc isEmpty*[T](arr: NSArray[T]): bool {.inline.} =
  arr.len == 0

proc `[]`*[T](arr: NSArray[T], index: int): T =
  let store = storageForRead(arr)
  if store.isNil or index < 0 or index >= store.data.len:
    raise newException(IndexDefect, "index out of bounds in NSArray")
  unboxNSObject[T](store.data[index])

proc `[]=`*[T](arr: var NSArray[T], index: int, value: T) {.inline.} =
  let store = storageForWrite(arr)
  if store.isNil or index < 0 or index >= store.data.len:
    raise newException(IndexDefect, "index out of bounds in NSArray")
  store.data[index] = boxNSObject(value)
  syncCount(arr, store.data.len)

proc add*[T](arr: var NSArray[T], value: T) {.inline.} =
  let store = storageForWrite(arr)
  if store.isNil:
    return
  store.data.add(boxNSObject(value))
  syncCount(arr, store.data.len)

proc addObject*[T](arr: var NSArray[T], value: T) {.inline.} =
  arr.add(value)

proc insert*[T](arr: var NSArray[T], index: int, value: T) {.inline.} =
  let store = storageForWrite(arr)
  if store.isNil or index < 0 or index > store.data.len:
    raise newException(IndexDefect, "index out of bounds in NSArray")
  store.data.insert(boxNSObject(value), index)
  syncCount(arr, store.data.len)

proc del*[T](arr: var NSArray[T], index: int) {.inline.} =
  let store = storageForWrite(arr)
  if store.isNil or index < 0 or index >= store.data.len:
    raise newException(IndexDefect, "index out of bounds in NSArray")
  store.data.delete(index)
  syncCount(arr, store.data.len)

proc clear*[T](arr: var NSArray[T]) {.inline.} =
  let store = storageForWrite(arr)
  if store.isNil:
    return
  store.data.setLen(0)
  syncCount(arr, 0)

proc toSeq*[T](arr: NSArray[T]): seq[T] =
  let store = storageForRead(arr)
  if store.isNil:
    return @[]
  result = newSeqOfCap[T](store.data.len)
  for value in store.data.items:
    result.add(unboxNSObject[T](value))

iterator items*[T](arr: NSArray[T]): T =
  let store = storageForRead(arr)
  if not store.isNil:
    for value in store.data.items:
      yield unboxNSObject[T](value)

iterator pairs*[T](arr: NSArray[T]): tuple[index: int, value: T] =
  let store = storageForRead(arr)
  if not store.isNil:
    for i, value in store.data.pairs:
      yield (i, unboxNSObject[T](value))

proc `==`*[T](a, b: NSArray[T]): bool =
  let aStore = storageForRead(a)
  let bStore = storageForRead(b)
  let aLen = if aStore.isNil: 0 else: aStore.data.len
  let bLen = if bStore.isNil: 0 else: bStore.data.len
  if aLen != bLen:
    return false
  if aLen == 0:
    return true
  for i in 0 ..< aLen:
    if unboxNSObject[T](aStore.data[i]) != unboxNSObject[T](bStore.data[i]):
      return false
  true
