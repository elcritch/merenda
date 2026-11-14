## Keyed, observable value collections for GUI-thread models.
## Snapshots and items are plain values. Only observed projections allocate
## reactive objects; projections cannot be written independently of the collection.
import std/[options, tables]
import sigils/[core, reactive]
import ../responder/responders

type
  CollectionSource* = ref object of Responder

  CollectionValue*[T] = ref object of CollectionSource
    value: T
    owner: CollectionSource

  CollectionSigil*[K, T] = ref object of CollectionSource
    values: seq[T]
    positions: Table[K, int]
    keys: seq[K]
    keyOf: proc(value: T): K {.nimcall.}
    orderRef: BackRef[CollectionValue[seq[K]]]
    itemRefs: Table[K, BackRef[CollectionValue[Option[T]]]]
    publishing: bool

proc change*(source: CollectionSource, attrs: set[SigilAttributes]) {.signal.}

proc snapshot*[K, T](source: CollectionSigil[K, T]): seq[T] =
  ## Return a value snapshot. Reference-bearing items retain their normal Nim
  ## aliasing semantics: publish replacements rather than mutating shared refs.
  source.values

proc snapshot*[T](source: CollectionValue[T]): T =
  source.value

template `{}`*(source: CollectionSource): untyped =
  ## Participate in Sigils' scoped read tracking, like Sigil[T].
  block:
    let input = source
    when enableSigilBinding[^1]:
      mixin getInternalSigilIdent
      input.connect(change, getInternalSigilIdent(), recompute)
    input.snapshot()

proc len*[K, T](source: CollectionSigil[K, T]): int =
  source.values.len

proc contains*[K, T](source: CollectionSigil[K, T], key: K): bool =
  source.positions.hasKey(key)

proc `[]`*[K, T](source: CollectionSigil[K, T], key: K): T =
  ## Required lookup by stable key, not sequence position. Raises KeyError.
  source.values[source.positions[key]]

proc get*[K, T](source: CollectionSigil[K, T], key: K): Option[T] =
  let index = source.positions.getOrDefault(key, -1)
  if index >= 0:
    result = some(source.values[index])

iterator items*[K, T](source: CollectionSigil[K, T]): T =
  for value in source.values:
    yield value

iterator pairs*[K, T](source: CollectionSigil[K, T]): (K, T) =
  for i, value in source.values:
    yield (source.keys[i], value)

proc order*[K, T](source: CollectionSigil[K, T]): CollectionValue[seq[K]] =
  ## Observe membership/order without waking on item-only changes.
  result = source.orderRef{}
  if result.isNil:
    result = CollectionValue[seq[K]](value: source.keys, owner: source)
    source.orderRef.set(result, result.xBackRefs)

proc item*[K, T](source: CollectionSigil[K, T], key: K): CollectionValue[Option[T]] =
  ## Observe one identity. Removal publishes none; reinsertion publishes some.
  ## Observations retain the source, which holds only zeroing weak links back.
  result = source.itemRefs.getOrDefault(key){}
  if result.isNil:
    result = CollectionValue[Option[T]](value: source.get(key), owner: source)
    var link: BackRef[CollectionValue[Option[T]]]
    link.set(result, result.xBackRefs)
    source.itemRefs[key] = link

proc setValue*[K, T](source: CollectionSigil[K, T], values: seq[T]) =
  ## Validate and index the entire snapshot before mutation. Publish one whole
  ## change, optionally one order change, and only changed observed items.
  ## All reads see the new state before any callback. Recursive writes are rejected.
  if source.publishing:
    raise newException(ValueError, "cannot publish a collection recursively")
  var positions = initTable[K, int]()
  var keys: seq[K]
  for i, value in values:
    let key = source.keyOf(value)
    if positions.hasKey(key):
      raise newException(ValueError, "duplicate collection identity: " & $key)
    positions[key] = i
    keys.add key
  if source.values == values:
    return
  let order = source.orderRef{}
  let moved = keys != source.keys
  var changed: seq[tuple[observed: CollectionValue[Option[T]], value: Option[T]]]
  var expired: seq[K]
  for key, link in source.itemRefs:
    let observed = link{}
    if observed.isNil:
      expired.add key
    else:
      let index = positions.getOrDefault(key, -1)
      let next =
        if index < 0:
          none(T)
        else:
          some(values[index])
      if observed.value != next:
        # Stage changed observations; update their values after comparison succeeds.
        changed.add (observed, next)
  source.values = values
  source.positions = positions
  source.keys = keys
  for key in expired:
    source.itemRefs.del(key)
  if not order.isNil:
    order.value = keys
  for item in changed:
    item.observed.value = item.value
  source.publishing = true
  defer:
    source.publishing = false
  if moved and not order.isNil:
    emit order.change({Changed})
  for item in changed:
    emit item.observed.change({Changed})
  emit source.change({Changed})

proc `<-`*[K, T](source: CollectionSigil[K, T], values: seq[T]) =
  source.setValue(values)

proc newCollectionSigil*[K, T](
    values: seq[T], keyOf: proc(value: T): K {.nimcall.}
): CollectionSigil[K, T] =
  if keyOf.isNil:
    raise newException(ValueError, "collection key getter cannot be nil")
  result = CollectionSigil[K, T](keyOf: keyOf)
  result.setValue(values)

proc `[]=`*[K, T](source: CollectionSigil[K, T], key: K, value: T) =
  ## Replace an existing item without changing its identity; publish once.
  if source.keyOf(value) != key:
    raise newException(ValueError, "replacement must preserve collection identity")
  var next = source.snapshot()
  next[source.positions[key]] = value
  source.setValue(next)
