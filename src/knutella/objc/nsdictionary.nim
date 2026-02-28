import std/tables

proc objcIsEqualIds(lhs, rhs: IDPtr): bool {.inline.} =
  if lhs == rhs:
    return true
  if lhs.isNil or rhs.isNil:
    return false
  let isEqualSend =
    cast[proc(self: IDPtr, op: SEL, other: IDPtr): bool {.cdecl, varargs.}](objc_msgSend)
  isEqualSend(lhs, sel_registerName("isEqual:"), rhs)

proc retainId(id: IDPtr): IDPtr {.inline.} =
  if id.isNil:
    return nil
  let retainSend = cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs.}](objc_msgSend)
  retainSend(id, sel_registerName("retain"))

proc releaseId(id: IDPtr) {.inline.} =
  if id.isNil:
    return
  let releaseSend = cast[proc(self: IDPtr, op: SEL): void {.cdecl, varargs.}](objc_msgSend)
  releaseSend(id, sel_registerName("release"))

proc retainedAs[T: NSObject](id: IDPtr): T {.inline.} =
  if id.isNil:
    return T(value: nil)
  asTypeRaw[T](retainId(id))

proc findEquivalentKey(data: Table[IDPtr, IDPtr], key: IDPtr, matchedKey: var IDPtr): bool =
  for storedKey in data.keys:
    if objcIsEqualIds(storedKey, key):
      matchedKey = storedKey
      return true
  matchedKey = nil
  false

proc releaseTableEntries(data: var Table[IDPtr, IDPtr]) =
  for key, value in data.pairs:
    releaseId(key)
    releaseId(value)
  data.clear()

objcImpl:
  type NXDictionary* = object of NSObject
    countCache: int
    data: Table[IDPtr, IDPtr]

  method init*(self: var NXDictionary): NXDictionary =
    result = callSuperAs[NXDictionary](self, getSelector("init"))
    if result.isNil:
      return
    result.countCache = 0
    result.data = initTable[IDPtr, IDPtr]()

  method dealloc*(self: NXDictionary) =
    var data = self.data()
    releaseTableEntries(data)
    self.data = data
    destroyIvarFields(self)
    discard callSuperAs[IDPtr](self, getSelector("dealloc"))

  method count*(self: NXDictionary): NSUInteger =
    if self.countCache() <= 0:
      return 0
    self.countCache().NSUInteger

  method removeAllObjects*(self: NXDictionary) =
    if self.isNil:
      return
    var data = self.data()
    releaseTableEntries(data)
    self.data = data
    self.countCache = 0

proc nsDictionary*[K: NSObject, V: NSObject](): NSDictionary[K, V] =
  var allocated = NXDictionary.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NSDictionary[K, V](value: nil)
  result = asTypeRaw[NSDictionary[K, V]](move(created.value))

proc init*[K: NSObject, V: NSObject](
    n: typedesc[NSDictionary[K, V]]
): NSDictionary[K, V] {.inline.} =
  nsDictionary[K, V]()

proc new*[K: NSObject, V: NSObject](
    n: typedesc[NSDictionary[K, V]]
): NSDictionary[K, V] {.inline.} =
  nsDictionary[K, V]()

proc len*[K: NSObject, V: NSObject](dict: NSDictionary[K, V]): int {.inline.} =
  if dict.value.isNil:
    return 0
  let obj = asRetainedType[NXDictionary](dict)
  result = obj.data().len

proc isEmpty*[K: NSObject, V: NSObject](dict: NSDictionary[K, V]): bool {.inline.} =
  dict.len == 0

proc hasKey*[K: NSObject, V: NSObject](dict: NSDictionary[K, V], key: K): bool =
  if dict.value.isNil or key.value.isNil:
    return false
  let obj = asRetainedType[NXDictionary](dict)
  let data = obj.data()
  var storedKey: IDPtr
  result = findEquivalentKey(data, key.value, storedKey)

proc `[]`*[K: NSObject, V: NSObject](dict: NSDictionary[K, V], key: K): V =
  if dict.value.isNil or key.value.isNil:
    raise newException(KeyError, "key not found in NSDictionary")
  let obj = asRetainedType[NXDictionary](dict)
  let data = obj.data()
  var storedKey: IDPtr
  if not findEquivalentKey(data, key.value, storedKey):
    raise newException(KeyError, "key not found in NSDictionary")
  let storedValue = data[storedKey]
  retainedAs[V](storedValue)

proc `[]=`*[K: NSObject, V: NSObject](dict: var NSDictionary[K, V], key: K, value: V) =
  if dict.value.isNil:
    return
  if key.value.isNil:
    raise newException(ValueError, "NSDictionary key cannot be nil")
  let obj = asRetainedType[NXDictionary](dict)
  var data = obj.data()
  var storedKey: IDPtr
  if findEquivalentKey(data, key.value, storedKey):
    let oldValue = data[storedKey]
    if oldValue != value.value:
      releaseId(oldValue)
      data[storedKey] = retainId(value.value)
  else:
    let retainedKey = retainId(key.value)
    let retainedValue = retainId(value.value)
    data[retainedKey] = retainedValue
  obj.data = data
  obj.countCache = data.len

proc del*[K: NSObject, V: NSObject](dict: var NSDictionary[K, V], key: K) {.inline.} =
  if dict.value.isNil or key.value.isNil:
    return
  let obj = asRetainedType[NXDictionary](dict)
  var data = obj.data()
  var storedKey: IDPtr
  if findEquivalentKey(data, key.value, storedKey):
    let storedValue = data[storedKey]
    releaseId(storedKey)
    releaseId(storedValue)
    data.del(storedKey)
  obj.data = data
  obj.countCache = data.len

proc clear*[K: NSObject, V: NSObject](dict: var NSDictionary[K, V]) {.inline.} =
  if dict.value.isNil:
    return
  let obj = asRetainedType[NXDictionary](dict)
  var data = obj.data()
  releaseTableEntries(data)
  obj.data = data
  obj.countCache = 0

iterator keys*[K: NSObject, V: NSObject](dict: NSDictionary[K, V]): K =
  if not dict.value.isNil:
    let obj = asRetainedType[NXDictionary](dict)
    let data = obj.data()
    for storedKey in data.keys:
      yield retainedAs[K](storedKey)

iterator values*[K: NSObject, V: NSObject](dict: NSDictionary[K, V]): V =
  if not dict.value.isNil:
    let obj = asRetainedType[NXDictionary](dict)
    let data = obj.data()
    for storedValue in data.values:
      yield retainedAs[V](storedValue)

iterator pairs*[K: NSObject, V: NSObject](
    dict: NSDictionary[K, V]
): tuple[key: K, value: V] =
  if not dict.value.isNil:
    let obj = asRetainedType[NXDictionary](dict)
    let data = obj.data()
    for storedKey, storedValue in data.pairs:
      yield (retainedAs[K](storedKey), retainedAs[V](storedValue))

proc `==`*[K: NSObject, V: NSObject](a, b: NSDictionary[K, V]): bool =
  let aLen = a.len
  let bLen = b.len
  if aLen != bLen:
    return false
  if aLen == 0:
    return true

  let aObj = asRetainedType[NXDictionary](a)
  let bObj = asRetainedType[NXDictionary](b)
  let aData = aObj.data()
  let bData = bObj.data()

  for aKey, aValue in aData.pairs:
    var bKey: IDPtr
    if not findEquivalentKey(bData, aKey, bKey):
      return false
    if not objcIsEqualIds(aValue, bData[bKey]):
      return false
  true
