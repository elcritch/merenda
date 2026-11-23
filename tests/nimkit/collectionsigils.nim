import std/unittest
import sigils/reactive
import merenda/nimkit/app/collectionsigils
import merenda/nimkit/responder/responders
import merenda/nimkit/directviews/bindings
import merenda/nimkit/foundation/mainthreadwork

type
  Row = object
    id: int
    text: string

  Watcher = ref object of Responder
    writes: int
    value: Opt[Row]

proc key(row: Row): int =
  row.id

proc record(watcher: Watcher, value: Opt[Row]) =
  inc watcher.writes
  watcher.value = value

suite "NimKit bindings to keyed collections":
  test "item changes notify only that identity and preserve structural projections":
    let rows =
      newCollectionSigil(@[Row(id: 1, text: "one"), Row(id: 2, text: "two")], key)
    let order = rows.order
    let first = rows.item(1)
    let second = rows.item(2)
    check rows.item(1) == first
    let scope = newBindingScope()
    defer:
      scope.dispose()
    let a = Watcher()
    let b = Watcher()
    scope.bindValue("a", first, a, record)
    scope.bindValue("b", second, b, record)
    let structural = computedNow[seq[int]]:
      order{}
    rows[1] = Row(id: 1, text: "edited")
    discard drainMainThreadWork()
    check a.writes == 2
    check b.writes == 1
    check a.value.get.text == "edited"
    check structural{} == @[1, 2]
    rows <- @[rows[2], rows[1]]
    discard drainMainThreadWork()
    check structural{} == @[2, 1]
    check a.writes == 2
    check b.writes == 1

  test "a binding retains a temporary projection through removal and reinsertion":
    let rows = newCollectionSigil(@[Row(id: 1, text: "one")], key)
    let scope = newBindingScope()
    defer:
      scope.dispose()
    let watcher = Watcher()
    scope.bindValue("row", rows.item(1), watcher, record)
    check watcher.value.get.text == "one"

    rows <- @[]
    discard drainMainThreadWork()
    check watcher.value.isNone
    rows <- @[Row(id: 1, text: "again")]
    discard drainMainThreadWork()
    check watcher.value.get.text == "again"

    scope.dispose()
    rows <- @[]
    discard drainMainThreadWork()
    check watcher.writes == 3
