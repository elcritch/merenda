## Model collection workloads; timings are diagnostic, not CI thresholds.
## Run with `nim ic -r tests/benchmark_itemcollections.nim`.
## Add `-d:nimAllocStats` to collect allocation counts in a separate run.
import std/[monotimes, times, options]
import merenda/nimkit/app/modelcontrollers
import merenda/nimkit/tables/tableviews

var checksum: int

template measure(label: string, body: untyped) =
  block:
    let statsBefore = getAllocStats()
    let start = getMonoTime()
    body
    let elapsed = (getMonoTime() - start).inNanoseconds.float / 1_000_000.0
    let allocations = getAllocStats() - statsBefore
    echo label, " ms=", elapsed, " ", allocations

proc makeItems(count: int): seq[ModelItem] =
  for index in 0 ..< count:
    result.add modelItem("row-" & $index, objectValue = toObj(index))

proc makeRows(count: int, named: bool): seq[TableRowValue] =
  for index in 0 ..< count:
    result.add tableRow(
      if named:
        "row-" & $index
      else:
        ""
    )

proc run() =
  let items = makeItems(5000)
  block:
    let controller = newArrayController()
    measure("array_append_5000"):
      for item in items:
        controller.addItem(item)
    doAssert controller.sourceLen == items.len
  block:
    let controller = newArrayController(items)
    measure("array_cold_len_5000"):
      checksum += controller.len
    doAssert controller.indexOfIdentifier("row-4999") == 4999
    measure("array_cached_reads_1000"):
      for iteration in 0 ..< 1000:
        checksum += controller.len
        checksum += controller.itemAt(iteration mod items.len).objectValue.requireInt()
        checksum += controller.indexOfIdentifier("row-4999")
  block:
    let controller = newArrayController(items)
    measure("array_remove_last_500_of_5000"):
      for index in countdown(4999, 4500):
        doAssert controller.removeItem(items[index].identifier)
    doAssert controller.sourceLen == 4500
  let rows = makeRows(5000, true)
  block:
    let model = newTableModel()
    measure("table_append_5000"):
      for row in rows:
        model.addRow(row)
    doAssert model.sourceLen == rows.len
  block:
    let model = newTableModel(rows)
    measure("table_remove_last_500_of_5000"):
      for index in countdown(4999, 4500):
        doAssert model.removeRow(rows[index].identifier)
    doAssert model.sourceLen == 4500
  block:
    let model = newTableModel(makeRows(10000, true))
    doAssert model.indexOfIdentifier("row-9999") == 9999
    measure("table_append_unnamed_5000_after_identity_10000"):
      for iteration in 0 ..< 5000:
        model.addRow(tableRow())
    doAssert model.sourceLen == 15000
  for named in [false, true]:
    let model = newTableModel(makeRows(10000, named))
    doAssert model.len == 10000
    measure("table_rearrange_100x10000_named_" & $named):
      for iteration in 0 ..< 100:
        model.filter = model.filter
        checksum += model.len
    if named:
      doAssert model.indexOfIdentifier("row-9999") == 9999
      measure("table_rearrange_and_identity_100x10000"):
        for iteration in 0 ..< 100:
          model.filter = model.filter
          checksum += model.indexOfIdentifier("row-9999")
    measure("table_cached_row_reads_100000_named_" & $named):
      for iteration in 0 ..< 100000:
        checksum += model.getRowAt(iteration mod 10000).get().identifier.len
    measure("table_arranged_rows_100x10000_named_" & $named):
      for iteration in 0 ..< 100:
        let rows = model.arrangedRows()
        checksum += rows.len
        checksum += rows[iteration].identifier.len
  block:
    var rows: seq[TableRowValue]
    for index in 0 ..< 100000:
      rows.add tableRow("row-" & $index, hidden = index != 0)
    let model = newTableModel(rows)
    measure("table_first_identity_one_visible_of_100000"):
      doAssert model.indexOfIdentifier("row-0") == 0
    measure("table_refresh_identity_one_visible_100x100000"):
      for iteration in 0 ..< 100:
        model.filter = model.filter
        doAssert model.indexOfIdentifier("row-0") == 0
  block:
    let controller = newArrayController(makeItems(10000))
    measure("array_first_source_lookup_row0_of_10000"):
      checksum += controller.itemWithIdentifier("row-0").identifier.len
    for identifier in ["row-0", "row-5000", "row-9999"]:
      measure("array_warm_source_lookup_10000x_" & identifier):
        for iteration in 0 ..< 10000:
          checksum += controller.itemWithIdentifier(identifier).identifier.len
  block:
    let controller = newArrayController(makeItems(1000))
    controller.filter = proc(item: ModelItem): bool =
      item.objectValue.requireInt() mod 2 == 0
    controller.sortDescriptors = [initModelSortDescriptor("", msdDescending)]
    doAssert controller.itemAt(0).objectValue.requireInt() == 998
    measure("array_sorted_filtered_refresh_100x1000"):
      for iteration in 0 ..< 100:
        controller.filter = controller.filter
        checksum += controller.len
    measure("array_sorted_filtered_cached_reads_1000"):
      for iteration in 0 ..< 1000:
        checksum += controller.itemAt(iteration mod 500).objectValue.requireInt()
  block:
    var rows: seq[TableRowValue]
    for index in 0 ..< 1000:
      rows.add tableRow("row-" & $index, objectValue = toObj(index))
    let model = newTableModel(rows)
    model.filter = proc(row: TableRowValue): bool =
      row.objectValue.requireInt() mod 2 == 0
    model.sortDescriptors = [initTableModelSortDescriptor("", tsdDescending)]
    doAssert model.getRowAt(0).get().objectValue.requireInt() == 998
    measure("table_sorted_filtered_refresh_100x1000"):
      for iteration in 0 ..< 100:
        model.filter = model.filter
        checksum += model.len
    measure("table_sorted_filtered_cached_reads_100000"):
      for iteration in 0 ..< 100000:
        checksum += model.getRowAt(iteration mod 500).get().objectValue.requireInt()
  echo "checksum=", checksum

run()
