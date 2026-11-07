## Run each sample in a fresh process from an Atlas-configured worktree:
##   nim ic -d:release --out:/tmp/markdownmemory tests/benchmarks/markdownmemory.nim
##   /tmp/markdownmemory table view 1000
## Modes: table|prose and parse|storage|view. The count controls body rows or
## paragraphs. Heap is currently live malloc memory; peak RSS is a process-wide
## high-water mark, not a peak live-heap measurement.

import std/[json, monotimes, os, strutils, tables, times]
import markdown
import merenda/nimkit
import merenda/nimkit/app/diagnostics
import merenda/nimkit/drawing/renderscenes
import merenda/nimkit/text/markdownparsing

when defined(macosx):
  {.
    emit: """
#include <malloc/malloc.h>
#include <mach/mach.h>
static size_t markdown_bench_heap_bytes(void) {
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
  proc heapBytes(): int {.importc: "markdown_bench_heap_bytes", nodecl.}
else:
  proc heapBytes(): int =
    getOccupiedMem()

proc sourceFor(workload: string, count: int): string =
  result = "# Memory benchmark\n\n"
  if workload == "table":
    result.add "| Name | Status | Value | Description |\n"
    result.add "| :--- | :---: | ---: | :--- |\n"
    for index in 0 ..< count:
      result.add "| Row " & $index & " café | **ready** | " & $index &
        " | A short linked [description](https://example.test) with emoji 😀 |\n"
  else:
    for index in 0 ..< count:
      result.add "## Section " & $index &
        "\n\nA café 😀 paragraph with **strong text** " &
        "and a [link](https://example.test).\n\n```text\nlet value = " & $index &
        "\n```\n\n"

proc report(
    workload, mode, stage: string,
    count, sourceBytes, renderedRunes: int,
    start: MonoTime,
) =
  let
    heap = heapBytes()
    usage = processResourceUsage()
    elapsedMs = (getMonoTime() - start).inMilliseconds
  echo $(
    %*{
      "workload": workload,
      "mode": mode,
      "stage": stage,
      "count": count,
      "sourceBytes": sourceBytes,
      "renderedRunes": renderedRunes,
      "heapBytes": heap,
      "rssBytes": usage.residentBytes,
      "peakRssBytes": usage.peakResidentBytes,
      "elapsedMs": elapsedMs,
    }
  )

when isMainModule:
  if paramCount() != 3 or paramStr(1) notin ["table", "prose"] or
      paramStr(2) notin ["parse", "storage", "view"]:
    quit "usage: markdownmemory table|prose parse|storage|view count"
  let
    workload = paramStr(1)
    mode = paramStr(2)
    count = parseInt(paramStr(3))
  if count <= 0:
    quit "count must be positive"
  let start = getMonoTime()
  let source = sourceFor(workload, count)
  report(workload, mode, "source", count, source.len, 0, start)
  case mode
  of "parse":
    let root = parseMarkdownRoot(source, initGfmConfig())
    doAssert not root.isNil
    report(workload, mode, "parsed", count, source.len, 0, start)
    doAssert not root.isNil
  of "storage":
    let storage = markdownTextStorage(source, syntaxHighlighter = nil)
    let length = storage.len
    report(workload, mode, "storage", count, source.len, length, start)
    doAssert storage.len == length and length > 0
  of "view":
    var view =
      newMarkdownView(source, frame = rect(0, 0, 800, 600), syntaxHighlighter = nil)
    if not view.waitForMarkdownParsing(60_000):
      quit "Markdown parsing timed out"
    if view.markdownParseError().len > 0:
      quit view.markdownParseError()
    if not view.waitForMarkdownLayout(60_000):
      quit "Markdown layout timed out"
    let length = view.textStorage().len
    report(workload, mode, "layout", count, source.len, length, start)
    block:
      let renders = view.buildRenders()
      report(workload, mode, "firstRender", count, source.len, length, start)
      doAssert not renders.isNil and renders.layers.len > 0
    doAssert view.textStorage().len == length and length > 0
    view.frame = rect(0, 0, 500, 600)
    if not view.waitForMarkdownLayout(60_000):
      quit "Markdown resize timed out"
    let resizedLength = view.textStorage().len
    report(workload, mode, "resized", count, source.len, resizedLength, start)
    doAssert view.textStorage().len == resizedLength and resizedLength > 0
    view = nil
    report(workload, mode, "released", count, source.len, 0, start)
  else:
    discard
