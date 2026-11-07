## Compare builds in separate fresh processes using the same Atlas dependencies:
##   nim ic -d:release --out:/tmp/textreflowmemory tests/benchmarks/textreflowmemory.nim
##   /tmp/textreflowmemory 131072
## The argument is the approximate UTF-8 source size. Heap is live malloc memory;
## peak RSS is a process-wide high-water mark, not peak live heap.

import std/[json, monotimes, os, strutils, times, unicode]
import sigils/[core, threads]
import merenda/nimkit
import merenda/nimkit/app/diagnostics
import merenda/nimkit/foundation/mainthreadwork

when defined(macosx):
  {.
    emit: """
#include <malloc/malloc.h>
#include <mach/mach.h>
static size_t text_reflow_bench_heap_bytes(void) {
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
  proc heapBytes(): int {.importc: "text_reflow_bench_heap_bytes", nodecl.}
else:
  proc heapBytes(): int =
    getOccupiedMem()

proc report(stage: string, sourceBytes, runCount, reflows: int, start: MonoTime) =
  let
    heap = heapBytes()
    usage = processResourceUsage()
  echo $(
    %*{
      "stage": stage,
      "sourceBytes": sourceBytes,
      "runCount": runCount,
      "reflows": reflows,
      "heapBytes": heap,
      "rssBytes": usage.residentBytes,
      "peakRssBytes": usage.peakResidentBytes,
      "elapsedMs": (getMonoTime() - start).inMilliseconds,
    }
  )

proc waitForLayout(manager: TextLayoutManager) =
  let deadline = getMonoTime() + initDuration(seconds = 60)
  while manager.isBackgroundLayoutPending() and getMonoTime() < deadline:
    discard drainMainThreadWork()
    discard getCurrentSigilThread().pollAll(NonBlocking)
    if manager.isBackgroundLayoutPending():
      sleep(1)
  doAssert not manager.isBackgroundLayoutPending(), "background layout timed out"
  doAssert manager.snapshotBuildThreadId() != 0, "worker did not build a snapshot"

when isMainModule:
  if paramCount() != 1:
    quit "usage: textreflowmemory approximate-source-bytes"
  let targetBytes = parseInt(paramStr(1))
  if targetBytes <= 0:
    quit "approximate-source-bytes must be positive"
  let start = getMonoTime()
  var source = newStringOfCap(targetBytes + 100)
  while source.len < targetBytes:
    source.add "Café κόσμος text for wrapped layout. ".repeat(4) & "\n"
  let
    sourceBytes = source.len
    runeCount = source.runeLen
  var
    regular = defaultTextAttributes()
    linked = defaultTextAttributes()
    runs: seq[TextAttributeRun]
  linked.link = "https://example.test/repeated"
  var index = 0
  while index < runeCount:
    let length = min(64, runeCount - index)
    runs.add TextAttributeRun(
      range: initTextRange(index, length),
      attributes: if (runs.len mod 2) == 0: regular else: linked,
    )
    index += length
  let runCount = runs.len
  let storage = newTextStorage(move source, move runs)
  report("storage", sourceBytes, runCount, 0, start)
  var manager = newTextLayoutManager(
    storage, initTextContainer(initSize(600, 200000), wraps = true)
  )
  manager.usesBackgroundLayout = true
  manager.requestBackgroundLayout(allowUncachedLayout = true)
  manager.waitForLayout()
  report("initialLayout", sourceBytes, runCount, 0, start)
  for reflow in 1 .. 10:
    manager.textContainer = initTextContainer(
      initSize(float32(450 + (reflow mod 3) * 75), 200000), wraps = true
    )
    manager.requestBackgroundLayout(allowUncachedLayout = true)
    manager.waitForLayout()
    report("widthReflow", sourceBytes, runCount, reflow, start)
  linked.fontSize = 20
  storage.setAttributes(initTextRange(0, min(64, runeCount)), linked)
  manager.requestBackgroundLayout(allowUncachedLayout = true)
  manager.waitForLayout()
  report("styleRevision", sourceBytes, runCount, 10, start)
  doAssert storage.len == runeCount
  manager = nil
  report("releasedManager", sourceBytes, runCount, 10, start)
