import std/tables

type NXDictionaryStorageBase = ref object of RootObj
type NXDictionaryStorage[K, V] = ref object of NXDictionaryStorageBase
  data: Table[K, V]

objcImpl:
  type NXDictionary* = object of NSObject
    backingStore: NXDictionaryStorageBase
    countCache: int

  method init*(self: var NXDictionary): NXDictionary =
    result = callSuperAs[NXDictionary](self, getSelector("init"))
    if result.isNil:
      return
    result.backingStore = nil
    result.countCache = 0

  method dealloc*(self: NXDictionary) =
    clearIvarRefs(self)
    discard callSuperAs[ID](self, getSelector("dealloc"))

  method count*(self: NXDictionary): NSUInteger =
    if self.countCache() <= 0:
      return 0
    self.countCache().NSUInteger

  method removeAllObjects*(self: NXDictionary) =
    self.backingStore = nil
    self.countCache = 0

proc storageForRead[K, V](dict: NSDictionary[K, V]): NXDictionaryStorage[K, V] =
  if dict.value.isNil:
    return nil
  var obj = asType[NXDictionary](dict.value)
  let base = obj.backingStore()
  obj.value = nil
  if base.isNil:
    return nil
  if base of NXDictionaryStorage[K, V]:
    return NXDictionaryStorage[K, V](base)
  nil

proc storageForWrite[K, V](dict: NSDictionary[K, V]): NXDictionaryStorage[K, V] =
  if dict.value.isNil:
    return nil
  var obj = asType[NXDictionary](dict.value)
  let base = obj.backingStore()
  obj.value = nil
  if base.isNil:
    return nil
  if base of NXDictionaryStorage[K, V]:
    return NXDictionaryStorage[K, V](base)
  nil

proc initStorage[K, V](dict: NSDictionary[K, V]) {.inline.} =
  if dict.value.isNil:
    return
  var obj = asType[NXDictionary](dict.value)
  obj.backingStore = NXDictionaryStorage[K, V](data: initTable[K, V]())
  obj.countCache = 0
  obj.value = nil

proc syncCount[K, V](dict: NSDictionary[K, V], count: int) {.inline.} =
  if dict.value.isNil:
    return
  var obj = asType[NXDictionary](dict.value)
  obj.countCache = count
  obj.value = nil

proc nsDictionary*[K, V](): NSDictionary[K, V] =
  var allocated = NXDictionary.alloc()
  var created = allocated.init()
  allocated.value = nil
  if created.isNil:
    return NSDictionary[K, V](value: nil)
  result = asType[NSDictionary[K, V]](created.value)
  created.value = nil
  initStorage(result)

proc init*[K, V](n: typedesc[NSDictionary[K, V]]): NSDictionary[K, V] {.inline.} =
  when false:
    discard n
  nsDictionary[K, V]()

proc new*[K, V](n: typedesc[NSDictionary[K, V]]): NSDictionary[K, V] {.inline.} =
  when false:
    discard n
  nsDictionary[K, V]()

proc nsDictionary*[K, V](pairs: openArray[(K, V)]): NSDictionary[K, V] =
  result = nsDictionary[K, V]()
  for (key, value) in pairs:
    result[key] = value

proc len*[K, V](dict: NSDictionary[K, V]): int {.inline.} =
  let store = storageForRead(dict)
  if store.isNil:
    return 0
  store.data.len

proc isEmpty*[K, V](dict: NSDictionary[K, V]): bool {.inline.} =
  dict.len == 0

proc hasKey*[K, V](dict: NSDictionary[K, V], key: K): bool {.inline.} =
  let store = storageForRead(dict)
  if store.isNil:
    return false
  store.data.hasKey(key)

proc containsKey*[K, V](dict: NSDictionary[K, V], key: K): bool {.inline.} =
  dict.hasKey(key)

proc `[]`*[K, V](dict: NSDictionary[K, V], key: K): V =
  let store = storageForRead(dict)
  if store.isNil or not store.data.hasKey(key):
    raise newException(KeyError, "key not found in NSDictionary")
  store.data[key]

proc `[]=`*[K, V](dict: var NSDictionary[K, V], key: K, value: V) {.inline.} =
  let store = storageForWrite(dict)
  if store.isNil:
    return
  store.data[key] = value
  syncCount(dict, store.data.len)

proc getOrDefault*[K, V](
    dict: NSDictionary[K, V], key: K, defaultValue: V
): V {.inline.} =
  let store = storageForRead(dict)
  if store.isNil:
    return defaultValue
  store.data.getOrDefault(key, defaultValue)

proc del*[K, V](dict: var NSDictionary[K, V], key: K) {.inline.} =
  let store = storageForWrite(dict)
  if store.isNil:
    return
  if store.data.hasKey(key):
    store.data.del(key)
  syncCount(dict, store.data.len)

proc clear*[K, V](dict: var NSDictionary[K, V]) {.inline.} =
  let store = storageForWrite(dict)
  if store.isNil:
    return
  store.data.clear()
  syncCount(dict, 0)

proc toTable*[K, V](dict: NSDictionary[K, V]): Table[K, V] {.inline.} =
  let store = storageForRead(dict)
  if store.isNil:
    return initTable[K, V]()
  store.data

iterator keys*[K, V](dict: NSDictionary[K, V]): K =
  let snapshot = dict.toTable()
  for key in snapshot.keys:
    yield key

iterator values*[K, V](dict: NSDictionary[K, V]): V =
  let snapshot = dict.toTable()
  for value in snapshot.values:
    yield value

iterator pairs*[K, V](dict: NSDictionary[K, V]): tuple[key: K, value: V] =
  let snapshot = dict.toTable()
  for key, value in snapshot.pairs:
    yield (key, value)

proc `==`*[K, V](a, b: NSDictionary[K, V]): bool =
  let aTable = a.toTable()
  let bTable = b.toTable()
  if aTable.len != bTable.len:
    return false
  for key, value in aTable.pairs:
    if not bTable.hasKey(key):
      return false
    if bTable[key] != value:
      return false
  true
