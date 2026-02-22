import std/tables
import ./assoc

type
  ObjcMarshalKind = enum
    omkObjc
    omkNim

  ObjcMarshaledNimBase = ref object of RootObj
  ObjcMarshaledNimValue[T] = ref object of ObjcMarshaledNimBase
    value: T

  ObjcMarshaledEqProc = proc(a, b: ObjcMarshaledNimBase): bool {.nimcall.}

  ObjcMarshaled* = object
    kind: ObjcMarshalKind
    hashCode: Hash
    objId: ID
    nim: ObjcMarshaledNimBase
    eqProc: ObjcMarshaledEqProc

  NXDictionaryData = ref object
    data: Table[ObjcMarshaled, ObjcMarshaled]

proc objcHashValue(id: ID): Hash {.inline.} =
  if id.isNil:
    return 0
  let hashSend =
    cast[proc(self: ID, op: SEL): NSUInteger {.cdecl, varargs.}](objc_msgSend)
  hashSend(id, sel_registerName("hash")).Hash

proc retainObjcId(id: ID): ID {.inline, raises: [].} =
  if id.isNil:
    return nil
  objc_msgSend(id, sel_registerName("retain"))

proc releaseObjcId(id: ID) {.inline, raises: [].} =
  if id.isNil:
    return
  discard objc_msgSend(id, sel_registerName("release"))

proc objcIsEqualIds(lhs, rhs: ID): bool {.inline.} =
  if lhs == rhs:
    return true
  if lhs.isNil or rhs.isNil:
    return false
  let isEqualSend =
    cast[proc(self: ID, op: SEL, other: ID): bool {.cdecl, varargs.}](objc_msgSend)
  isEqualSend(lhs, sel_registerName("isEqual:"), rhs)

proc hash*(value: NSObject): Hash {.inline.} =
  objcHashValue(value.value)

proc `==`*(a, b: NSObject): bool {.inline.} =
  objcIsEqualIds(a.value, b.value)

proc sameEqProc(a, b: ObjcMarshaledEqProc): bool {.inline.} =
  cast[pointer](a) == cast[pointer](b)

proc hash*(value: ObjcMarshaled): Hash {.inline.} =
  value.hashCode

proc `==`*(a, b: ObjcMarshaled): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of omkObjc:
    objcIsEqualIds(a.objId, b.objId)
  of omkNim:
    if a.nim.isNil or b.nim.isNil:
      return a.nim.isNil and b.nim.isNil
    if not sameEqProc(a.eqProc, b.eqProc):
      return false
    if a.eqProc.isNil:
      return false
    a.eqProc(a.nim, b.nim)

proc `=destroy`(value: var ObjcMarshaled) =
  releaseObjcId(value.objId)
  value.objId = nil
  value.nim = nil
  value.eqProc = nil
  value.hashCode = 0

proc `=copy`(dest: var ObjcMarshaled, src: ObjcMarshaled) =
  if cast[pointer](addr dest) == cast[pointer](unsafeAddr(src)):
    return
  `=destroy`(dest)
  dest.kind = src.kind
  dest.hashCode = src.hashCode
  dest.objId = retainObjcId(src.objId)
  dest.nim = src.nim
  dest.eqProc = src.eqProc

proc `=sink`(dest: var ObjcMarshaled, src: ObjcMarshaled) =
  `=destroy`(dest)
  dest.kind = src.kind
  dest.hashCode = src.hashCode
  dest.objId = src.objId
  dest.nim = src.nim
  dest.eqProc = src.eqProc

proc marshalObjcValue(value: NSObject): ObjcMarshaled {.inline.} =
  ObjcMarshaled(
    kind: omkObjc,
    hashCode: objcHashValue(value.value),
    objId: retainObjcId(value.value),
    nim: nil,
    eqProc: nil,
  )

proc nimBoxEq[T](a, b: ObjcMarshaledNimBase): bool =
  ObjcMarshaledNimValue[T](a).value == ObjcMarshaledNimValue[T](b).value

proc marshalKey[K](value: K): ObjcMarshaled =
  when compiles(hash(value)) and compiles(value == value):
    var box: ObjcMarshaledNimValue[K]
    new(box)
    box.value = value
    ObjcMarshaled(
      kind: omkNim, hashCode: hash(value), objId: nil, nim: box, eqProc: nimBoxEq[K]
    )
  elif K is NSObject:
    marshalObjcValue(asType[NSObject](value))
  else:
    {.fatal: "NSDictionary key type requires hash/== or NSObject compatibility".}

proc marshalValue[V](value: V): ObjcMarshaled =
  when compiles(value == value):
    var box: ObjcMarshaledNimValue[V]
    new(box)
    box.value = value
    ObjcMarshaled(kind: omkNim, hashCode: 0, objId: nil, nim: box, eqProc: nimBoxEq[V])
  elif V is NSObject:
    marshalObjcValue(asType[NSObject](value))
  else:
    {.fatal: "NSDictionary value type requires == or NSObject compatibility".}

proc retainedAs[T: NSObject](id: ID): T {.inline.} =
  if id.isNil:
    return T(value: nil)
  let retainSend = cast[proc(self: ID, op: SEL): ID {.cdecl, varargs.}](objc_msgSend)
  asType[T](retainSend(id, sel_registerName("retain")))

proc unmarshalValue[T](value: ObjcMarshaled): T =
  when T is NSObject:
    case value.kind
    of omkObjc:
      retainedAs[T](value.objId)
    of omkNim:
      ObjcMarshaledNimValue[T](value.nim).value
  else:
    if value.kind != omkNim:
      return default(T)
    ObjcMarshaledNimValue[T](value.nim).value

objcImpl:
  type NXDictionary* = object of NSObject
    countCache: int

  method init*(self: var NXDictionary): NXDictionary =
    result = callSuperAs[NXDictionary](self, getSelector("init"))
    if result.isNil:
      return
    result.countCache = 0

  method dealloc*(self: NXDictionary) =
    clearIvarRefs(self)
    discard callSuperAs[ID](self, getSelector("dealloc"))

  method count*(self: NXDictionary): NSUInteger =
    if self.countCache() <= 0:
      return 0
    self.countCache().NSUInteger

  method removeAllObjects*(self: NXDictionary) =
    if self.isNil:
      return
    let store = getAssociatedRef(self, NXDictionaryData)
    if not store.isNil:
      store.data.clear()
    self.countCache = 0

proc storageForRead[K, V](dict: NSDictionary[K, V]): NXDictionaryData =
  if dict.value.isNil:
    return nil
  var obj = asType[NXDictionary](dict.value)
  let store = getAssociatedRef(obj, NXDictionaryData)
  obj.value = nil
  store

proc storageForWrite[K, V](dict: NSDictionary[K, V]): NXDictionaryData =
  if dict.value.isNil:
    return nil
  var obj = asType[NXDictionary](dict.value)
  let store = getAssociatedRef(obj, NXDictionaryData)
  obj.value = nil
  store

proc initStorage[K, V](dict: NSDictionary[K, V]) {.inline.} =
  if dict.value.isNil:
    return
  var obj = asType[NXDictionary](dict.value)
  var store = getAssociatedRef(obj, NXDictionaryData)
  if store.isNil:
    new(store)
    store.data = initTable[ObjcMarshaled, ObjcMarshaled]()
    setAssociatedRef(obj, store)
  else:
    store.data.clear()
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
  let marshaledKey = marshalKey(key)
  store.data.hasKey(marshaledKey)

proc containsKey*[K, V](dict: NSDictionary[K, V], key: K): bool {.inline.} =
  dict.hasKey(key)

proc `[]`*[K, V](dict: NSDictionary[K, V], key: K): V =
  let store = storageForRead(dict)
  let marshaledKey = marshalKey(key)
  if store.isNil or not store.data.hasKey(marshaledKey):
    raise newException(KeyError, "key not found in NSDictionary")
  unmarshalValue[V](store.data[marshaledKey])

proc `[]=`*[K, V](dict: var NSDictionary[K, V], key: K, value: V) {.inline.} =
  let store = storageForWrite(dict)
  if store.isNil:
    return
  let marshaledKey = marshalKey(key)
  let marshaledValue = marshalValue(value)
  store.data[marshaledKey] = marshaledValue
  syncCount(dict, store.data.len)

proc getOrDefault*[K, V](
    dict: NSDictionary[K, V], key: K, defaultValue: V
): V {.inline.} =
  let store = storageForRead(dict)
  if store.isNil:
    return defaultValue
  let marshaledKey = marshalKey(key)
  if not store.data.hasKey(marshaledKey):
    return defaultValue
  unmarshalValue[V](store.data[marshaledKey])

proc del*[K, V](dict: var NSDictionary[K, V], key: K) {.inline.} =
  let store = storageForWrite(dict)
  if store.isNil:
    return
  let marshaledKey = marshalKey(key)
  if store.data.hasKey(marshaledKey):
    store.data.del(marshaledKey)
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
  result = initTable[K, V]()
  for marshaledKey, marshaledValue in store.data.pairs:
    result[unmarshalValue[K](marshaledKey)] = unmarshalValue[V](marshaledValue)

iterator keys*[K, V](dict: NSDictionary[K, V]): K =
  let store = storageForRead(dict)
  if not store.isNil:
    for marshaledKey in store.data.keys:
      yield unmarshalValue[K](marshaledKey)

iterator values*[K, V](dict: NSDictionary[K, V]): V =
  let store = storageForRead(dict)
  if not store.isNil:
    for marshaledValue in store.data.values:
      yield unmarshalValue[V](marshaledValue)

iterator pairs*[K, V](dict: NSDictionary[K, V]): tuple[key: K, value: V] =
  let store = storageForRead(dict)
  if not store.isNil:
    for marshaledKey, marshaledValue in store.data.pairs:
      yield (unmarshalValue[K](marshaledKey), unmarshalValue[V](marshaledValue))

proc `==`*[K, V](a, b: NSDictionary[K, V]): bool =
  let aStore = storageForRead(a)
  let bStore = storageForRead(b)
  let aLen = if aStore.isNil: 0 else: aStore.data.len
  let bLen = if bStore.isNil: 0 else: bStore.data.len
  if aLen != bLen:
    return false
  if aLen == 0:
    return true
  for key, value in aStore.data.pairs:
    if not bStore.data.hasKey(key):
      return false
    if bStore.data[key] != value:
      return false
  true
