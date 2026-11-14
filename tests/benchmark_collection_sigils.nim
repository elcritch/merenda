## Snapshot publication + binding getter/queue cost; no widgets, layout or previews.
import std/[monotimes, times, strformat, os]
import sigils/[core, reactive]
import merenda/nimkit/responder/responders
import merenda/nimkit/app/collectionsigils
import merenda/nimkit/viewbindings
import merenda/nimkit/foundation/mainthreadwork

type
  Row = object
    id, value: int

  Model = ref object of Responder
    flat: Sigil[seq[Row]]
    keyed: CollectionSigil[int, Row]
    reads: int

  Target = ref object of Responder
    value: int

proc key(row: Row): int =
  row.id

proc readFlat(model: Model, id: int): int =
  inc model.reads
  for row in model.flat{}:
    if row.id == id:
      return row.value

proc readKeyed(model: Model, id: int): int =
  inc model.reads
  model.keyed[id].value

proc apply(target: Target, value: int) =
  target.value = value

proc run(csv: File, count: int, keyed: bool) =
  var rows: seq[Row]
  for id in 0 ..< count:
    rows.add Row(id: id)
  let model = Model(flat: newSigil(rows), keyed: newCollectionSigil(rows, key))
  let target = Target()
  var scopes: seq[BindingScope]
  for id in 0 ..< count:
    let scope = newBindingScope()
    scopes.add scope
    if keyed:
      scope.bindSigilValue(
        "value", model.keyed.item(id), model, id, readKeyed, target, apply
      )
    else:
      scope.bindSigilValue("value", model.flat, model, id, readFlat, target, apply)
  var value = 0
  proc update() =
    inc value
    var next =
      if keyed:
        model.keyed{}
      else:
        model.flat{}
    next[0].value = value
    if keyed:
      model.keyed <- next
    else:
      model.flat <- next
    discard drainMainThreadWork()

  for i in 0 ..< 5:
    update()
  let name = if keyed: "collection" else: "flat_sigil"
  const Iterations = 20
  for sample in 1 .. 5:
    model.reads = 0
    let start = getMonoTime()
    for i in 0 ..< Iterations:
      update()
    let elapsed = (getMonoTime() - start).inNanoseconds.float / 1000 / Iterations
    let reads = model.reads div Iterations
    doAssert reads == (if keyed: 1 else: count)
    csv.writeLine(&"{count},{name},{sample},{Iterations},{elapsed:.6f},{reads}")
  for scope in scopes:
    scope.dispose()

proc main() =
  let csv = open(
    if paramCount() == 0:
      "/tmp/collection-sigils.csv"
    else:
      paramStr(1),
    fmWrite,
  )
  defer:
    csv.close()
  csv.writeLine("rows,case,sample,iterations,us_per_op,getter_calls_per_op")
  for count in [3, 100, 1000]:
    run(csv, count, false)
    run(csv, count, true)

main()
