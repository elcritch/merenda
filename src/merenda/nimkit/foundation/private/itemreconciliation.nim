## Synchronous reconciliation with explicit realization and retirement policies.

import std/tables

proc reconcileItems*[T, D, K](
    previous: seq[T],
    desired: openArray[D],
    keyOf: proc(item: T): K {.closure.},
    desiredKey: proc(item: D): K {.closure.},
    create: proc(item: D): T {.closure.},
    configure: proc(item: var T, desired: D) {.closure.},
    retire: proc(item: T) {.closure.},
    keep: proc(item: T): bool {.closure.} = nil,
): seq[T] =
  var lookup = initTable[K, int]()
  for index, item in previous:
    let key = keyOf(item)
    when K is string:
      if key.len == 0:
        continue
    if key notin lookup:
      lookup[key] = index
  var used = newSeq[bool](previous.len)
  for spec in desired:
    let index = lookup.getOrDefault(desiredKey(spec), -1)
    var item: T
    if index >= 0 and not used[index]:
      used[index] = true
      item = previous[index]
    else:
      item = create(spec)
    configure(item, spec)
    if keep.isNil or keep(item):
      result.add item
  for index, item in previous:
    if not used[index]:
      retire(item)
