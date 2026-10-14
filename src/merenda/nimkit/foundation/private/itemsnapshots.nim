## Common ownership and identity projection for typed presentation snapshots.

import std/options
import ./itemreconciliation

type ItemSnapshot*[T] = object
  models*: seq[T]
  active*: bool

proc replace*[T](snapshot: var ItemSnapshot[T], models: openArray[T]) =
  snapshot.models = @models
  snapshot.active = true

proc sourceIndex*[T](snapshot: ItemSnapshot[T], identifier: string): int =
  if identifier.len > 0:
    for index, model in snapshot.models:
      if model.identifier == identifier:
        return index
  -1

proc visibleSourceIndex*[T](snapshot: ItemSnapshot[T], visibleIndex: int): int =
  if visibleIndex >= 0:
    var current = 0
    for index, model in snapshot.models:
      if not model.hidden:
        if current == visibleIndex:
          return index
        inc current
  -1

proc visibleIndex*[T](snapshot: ItemSnapshot[T], sourceIndex: int): int =
  if sourceIndex in 0 ..< snapshot.models.len and not snapshot.models[sourceIndex].hidden:
    result = 0
    for index in 0 ..< sourceIndex:
      if not snapshot.models[index].hidden:
        inc result
  else:
    result = -1

proc visibleIndexForIdentifier*[T](snapshot: ItemSnapshot[T], identifier: string): int =
  snapshot.visibleIndex(snapshot.sourceIndex(identifier))

proc visibleCount*[T](snapshot: ItemSnapshot[T]): int =
  for model in snapshot.models:
    if not model.hidden:
      inc result

proc readSnapshot*[T](
    count: Option[int], readItem: proc(index: int): Option[T] {.closure.}
): Option[seq[T]] =
  if count.isNone:
    return
  var models: seq[T]
  for index in 0 ..< count.get():
    let model = readItem(index)
    if model.isSome:
      models.add model.get()
  some(models)

proc reconcilePresentations*[M, V](
    snapshot: ItemSnapshot[M],
    previous: seq[V],
    identify: proc(item: V): string {.closure.},
    create: proc(model: M): V {.closure.},
    apply: proc(item: V, model: M) {.closure.},
    retire: proc(item: V) {.closure.},
): seq[V] =
  var visible: seq[M]
  for model in snapshot.models:
    if not model.hidden:
      visible.add model
  reconcileItems(
    previous,
    visible,
    identify,
    proc(model: M): string =
      model.identifier,
    create,
    proc(item: var V, model: M) =
      apply(item, model),
    retire,
  )
