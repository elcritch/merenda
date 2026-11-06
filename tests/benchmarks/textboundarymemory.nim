## Compare the old indexed path and streaming string queries in fresh processes:
##   nim ic -d:release --out:/tmp/textboundarymemory tests/benchmarks/textboundarymemory.nim
##   /tmp/textboundarymemory indexed 33554432
##   /tmp/textboundarymemory streaming 33554432
## RSS peak is process-wide; heap is live malloc-zone memory at each checkpoint.

import std/[json, os, strutils]
import merenda/nimkit/app/diagnostics
import merenda/nimkit/text/textruneutils
import merenda/nimkit/text/texttypes

when defined(macosx):
  {.
    emit: """
#include <malloc/malloc.h>
#include <mach/mach.h>
static size_t boundary_bench_heap_bytes(void) {
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
  proc heapBytes(): int {.importc: "boundary_bench_heap_bytes", nodecl.}
else:
  proc heapBytes(): int =
    getOccupiedMem()

proc report(mode, stage: string, sourceBytes: int, checksum: int) =
  let usage = processResourceUsage()
  echo $(
    %*{
      "mode": mode,
      "stage": stage,
      "sourceBytes": sourceBytes,
      "checksum": checksum,
      "heapBytes": heapBytes(),
      "rssBytes": usage.residentBytes,
      "peakRssBytes": usage.peakResidentBytes,
    }
  )

when isMainModule:
  if paramCount() != 2 or paramStr(1) notin ["indexed", "streaming"]:
    quit "usage: textboundarymemory indexed|streaming source-bytes"
  let
    mode = paramStr(1)
    count = parseInt(paramStr(2))
  if count <= 0:
    quit "source-bytes must be positive"
  var source = newStringOfCap(count + 100)
  while source.len < count:
    source.add "alpha café βeta 0123  "
  report(mode, "source", source.len, 0)
  let position = count div 2
  var checksum = 0
  if mode == "indexed":
    checksum += utf8RunesForText(source).previousWordBoundary(position)
    checksum += utf8RunesForText(source).nextWordBoundary(position)
    let range = utf8RunesForText(source).wordRangeAt(position)
    checksum += int(range.location) + int(range.length)
  else:
    checksum += source.previousWordBoundary(position)
    checksum += source.nextWordBoundary(position)
    let range = source.wordRangeAt(position)
    checksum += int(range.location) + int(range.length)
  report(mode, "queriesFinished", source.len, checksum)
