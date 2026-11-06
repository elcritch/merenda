## Sample the worker's oversized-line fallback in fresh processes:
##   nim ic -d:release --out:/tmp/matterlinememory tests/benchmarks/matterlinememory.nim
##   /tmp/matterlinememory 8388608
## Live malloc heap, RSS, and process high-water RSS are process-wide.

import std/[json, monotimes, os, strutils, times]
import sigils/threads
import moepkg/highlight as moeHighlight
import moepkg/syntax/matter_backend as moeMatter
import merenda/kosmo/matterworkers
import merenda/nimkit/app/diagnostics

when defined(macosx):
  {.
    emit: """
#include <malloc/malloc.h>
#include <mach/mach.h>
static size_t matter_line_bench_heap_bytes(void) {
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
  proc heapBytes(): int {.importc: "matter_line_bench_heap_bytes", nodecl.}
else:
  proc heapBytes(): int =
    getOccupiedMem()

proc report(stage: string, sourceBytes, lastColumn: int) =
  let usage = processResourceUsage()
  echo $(
    %*{
      "stage": stage,
      "sourceBytes": sourceBytes,
      "lastColumn": lastColumn,
      "heapBytes": heapBytes(),
      "rssBytes": usage.residentBytes,
      "peakRssBytes": usage.peakResidentBytes,
    }
  )

when isMainModule:
  if paramCount() != 1:
    quit "usage: matterlinememory source-bytes"
  let sourceBytes = parseInt(paramStr(1))
  if sourceBytes <= 0:
    quit "source-bytes must be positive"
  let source = newString(sourceBytes).replace('\0', 'a')
  report("source", sourceBytes, -1)
  let
    rootPath = "/kosmo/config/grammars/toy/syntaxes/plain.tmLanguage.json"
    sources = @[
      moeMatter.MatterGrammarSource(
        path: rootPath, content: """{"scopeName":"source.toy","patterns":[]}"""
      )
    ]
    fileTypes = @[
      MatterGrammarFileType(
        identifier: "toy:plain",
        languageId: "toy",
        rootPath: rootPath,
        extensions: @[".toy"],
      )
    ]
    highlighting = newMatterHighlighting(sources, fileTypes)
  let requestId = highlighting.requestMatterHighlight(
    7, 1, source, moeHighlight.SourceLanguage.langNone, "large.toy"
  )
  let deadline = getMonoTime() + initDuration(seconds = 60)
  var lastColumn = -1
  while not highlighting.matterHighlightingReady(7, requestId) and
      getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    for batch in highlighting.takeMatterHighlightResults():
      doAssert batch.errorMessage.len == 0
      for segment in batch.segments:
        lastColumn = segment.lastColumn
    if not highlighting.matterHighlightingReady(7, requestId):
      sleep(1)
  doAssert highlighting.matterHighlightingReady(7, requestId), "worker timed out"
  for batch in highlighting.takeMatterHighlightResults():
    doAssert batch.errorMessage.len == 0
    for segment in batch.segments:
      lastColumn = segment.lastColumn
  doAssert lastColumn == sourceBytes - 1
  report("completed", sourceBytes, lastColumn)
  highlighting.close()
