## Compare retained range-backed storage with an ordinary detached child:
##   nim ic -d:release --out:/tmp/textrangestoragememory tests/benchmarks/textrangestoragememory.nim
##   /tmp/textrangestoragememory range 16777216
##   /tmp/textrangestoragememory copy 16777216
## Parent remains retained in both modes. The final two checkpoints distinguish
## eviction from the lifetime of a previously returned snapshot.

import std/[json, os, strutils]
import merenda/nimkit
import merenda/nimkit/app/diagnostics
import merenda/nimkit/text/textsnapshots
import merenda/nimkit/text/textstorage

when defined(macosx):
  {.
    emit: """
#include <malloc/malloc.h>
#include <mach/mach.h>
static size_t range_storage_bench_heap_bytes(void) {
  vm_address_t *zones = NULL;
  unsigned count = 0;
  if (malloc_get_all_zones(mach_task_self(), NULL, &zones, &count) != KERN_SUCCESS)
    return 0;
  size_t total = 0;
  for (unsigned index = 0; index < count; ++index) {
    malloc_statistics_t stats;
    malloc_zone_statistics((malloc_zone_t *)zones[index], &stats);
    total += stats.size_in_use;
  }
  return total;
}
"""
  .}
  proc heapBytes(): int {.importc: "range_storage_bench_heap_bytes", nodecl.}
else:
  proc heapBytes(): int =
    getOccupiedMem()

proc report(mode, stage: string, parentBytes, childBytes: int) =
  let usage = processResourceUsage()
  echo $(
    %*{
      "mode": mode,
      "stage": stage,
      "parentBytes": parentBytes,
      "childBytes": childBytes,
      "heapBytes": heapBytes(),
      "rssBytes": usage.residentBytes,
      "peakRssBytes": usage.peakResidentBytes,
    }
  )

proc parentStorage(size: int): TextStorage =
  newTextStorage("a".repeat(size))

proc childStorage(
    mode: string,
    parent: TextStorage,
    parentSnapshot: TextSnapshot,
    childRange: TextRange,
    parentBytes: int,
): TextStorage =
  var
    text = parent.substring(childRange)
    runs: TextRunBuilder
  runs.add(initTextRange(0, int(childRange.length)), defaultTextAttributes())
  var styles = newTextStorage(move text, move runs)
  report(mode, "styleFixture", parentBytes, int(childRange.length))
  if mode == "range":
    result = newTextRangeStorage(parentSnapshot, childRange, styles)
  else:
    result = move styles

when isMainModule:
  if paramCount() notin 2 .. 3 or paramStr(1) notin ["range", "copy"] or
      (paramCount() == 3 and paramStr(3) != "pause"):
    quit "usage: textrangestoragememory range|copy parent-bytes [pause]"
  let
    mode = paramStr(1)
    size = parseInt(paramStr(2))
  if size < 2:
    quit "parent-bytes must be at least 2"
  let
    parent = parentStorage(size)
    parentSnapshot = parent.textSnapshot()
    childRange = initTextRange(size div 4, size div 2)
    childSize = int(childRange.length)
  report(mode, "parent", size, childSize)
  let child = childStorage(mode, parent, parentSnapshot, childRange, size)
  report(mode, "childRetained", size, childSize)
  if paramCount() == 3:
    stdout.flushFile()
    discard stdin.readLine()
  doAssert child.len == childSize
  doAssert child.substring(initTextRange(0, 1)) == "a"
  discard child.attributesAt(0)
  when defined(merendaTests):
    if mode == "range":
      doAssert child.textRangeStorageStateForTest(parentSnapshot) == (true, false)
  report(mode, "boundedReads", size, childSize)
  var held = child.textSnapshot()
  doAssert held.byteLength == childSize
  report(mode, "materialized", size, childSize)
  child.discardTextRangeStorageMaterialization()
  doAssert held.byteLength == childSize
  report(mode, "discardHeld", size, childSize)
  held = nil
  report(mode, "discardReleased", size, childSize)
  doAssert parent.len == size
  doAssert child.len == childSize
