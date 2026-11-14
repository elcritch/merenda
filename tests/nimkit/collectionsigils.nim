import std/[options, unittest]
import sigils/[core, reactive]
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
    value: Option[Row]

proc key(row: Row): int =
  row.id

proc record(watcher: Watcher, value: Option[Row]) =
  inc watcher.writes
  watcher.value = value

suite "keyed collection Sigils":
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

  test "snapshots cannot mutate storage and duplicate IDs fail before publication":
    let rows = newCollectionSigil(@[Row(id: 1, text: "one")], key)
    let item = rows.item(1)
    let order = rows.order
    var copy = rows{}
    copy[0].text = "local"
    check rows[1].text == "one"
    expect ValueError:
      rows <- @[Row(id: 1, text: "a"), Row(id: 1, text: "b")]
    check rows[1].text == "one"
    check item{}.get.text == "one"
    check order{} == @[1]
    expect KeyError:
      discard rows[8]
    expect ValueError:
      rows[1] = Row(id: 2)
    check rows.get(8).isNone

  test "missing identities survive removal and reinsertion without leaked observations":
    var rows = newCollectionSigil(@[Row(id: 1, text: "one")], key)
    var weakRows: BackRef[CollectionSigil[int, Row]]
    weakRows.target = rows
    var item = rows.item(1)
    var weakItem: BackRef[CollectionValue[Option[Row]]]
    weakItem.target = item
    rows <- @[]
    check item{}.isNone
    rows <- @[Row(id: 1, text: "again")]
    check item{}.get.text == "again"
    rows = nil
    check not weakRows.isNil
    item = nil
    check weakRows.isNil
    check weakItem.isNil

  test "all projections are committed before synchronous observers run":
    let rows = newCollectionSigil(@[Row(id: 1, text: "one")], key)
    let order = rows.order
    let first = rows.item(1)
    let derived = computedNow[string]:
      discard order{}
      rows[1].text & first{}.get.text
    rows <- @[Row(id: 2, text: "two"), Row(id: 1, text: "new")]
    check derived{} == "newnew"

  test "thousands of subscribed rows do not run unrelated getters":
    var initial: seq[Row]
    for id in 0 ..< 1000:
      initial.add Row(id: id, text: $id)
    let rows = newCollectionSigil(initial, key)
    let scope = newBindingScope()
    defer:
      scope.dispose()
    var watchers: seq[Watcher]
    for id in 0 ..< 1000:
      let watcher = Watcher()
      watchers.add watcher
      scope.bindValue($id, rows.item(id), watcher, record)
    rows[500] = Row(id: 500, text: "changed")
    discard drainMainThreadWork()
    var writes = 0
    for watcher in watchers:
      writes += watcher.writes
    check writes == 1001
    check watchers[500].value.get.text == "changed"
