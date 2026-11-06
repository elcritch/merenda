## Sample gap-storage retention in a fresh process:
##   nim ic -d:release --out:/tmp/textgapsourcememory tests/benchmarks/textgapsourcememory.nim
##   /tmp/textgapsourcememory 8388608 [precache]
## The optional precache mode reproduces the earlier gap-snapshot behavior.
## The explicit snapshot is a control showing the live size of a cached snapshot.
## Live malloc heap and RSS are process-wide, so repeat samples before comparing.

import std/[json, os, strutils]
import merenda/nimkit
import merenda/nimkit/app/diagnostics
import merenda/nimkit/text/textstorage
import merenda/nimkit/text/textsnapshots

when defined(macosx):
  {.
    emit: """
#include <malloc/malloc.h>
#include <mach/mach.h>
static size_t gap_source_bench_heap_bytes(void) {
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
  proc heapBytes(): int {.importc: "gap_source_bench_heap_bytes", nodecl.}
else:
  proc heapBytes(): int =
    getOccupiedMem()

proc report(stage: string, sourceBytes: int) =
  let usage = processResourceUsage()
  echo $(
    %*{
      "stage": stage,
      "sourceBytes": sourceBytes,
      "heapBytes": heapBytes(),
      "rssBytes": usage.residentBytes,
      "peakRssBytes": usage.peakResidentBytes,
    }
  )

proc createWorkerStorage(storage: TextStorage) =
  let payload = storage.textLayoutSource()
  let workerStorage = newTextLayoutStorage(payload)
  doAssert workerStorage.len == storage.len

when isMainModule:
  if paramCount() notin 1 .. 2 or (paramCount() == 2 and paramStr(2) != "precache"):
    quit "usage: textgapsourcememory approximate-source-bytes [precache]"
  let targetBytes = parseInt(paramStr(1))
  if targetBytes <= 0:
    quit "approximate-source-bytes must be positive"
  let unit = "Café κόσμος wrapped text\n"
  var source = unit.repeat((targetBytes + unit.len - 1) div unit.len)
  let sourceBytes = source.len
  let storage = newGapTextStorage(source)
  source.setLen(0)
  report("storage", sourceBytes)
  if paramCount() == 2:
    discard storage.textSnapshot()
  storage.createWorkerStorage()
  report("payloadReleased", sourceBytes)
  let snapshot = storage.textSnapshot()
  doAssert snapshot.byteLength == sourceBytes
  report("snapshotCached", sourceBytes)
