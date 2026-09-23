## macOS diagnostic MonoText grid allocation benchmark.
## Run from an Atlas-configured worktree with:
## nim c -r -d:release -d:nimAllocStats --mm:arc --threads:on tests/benchmarks/monotextmemory.nim
## Add -d:baselineMonoText when compiling against the parent revision.

import celina/core/buffer as celinaBuffer
import terminex
import merenda/nimkit/text/monotextviews

{.
  emit:
    """
#include <malloc/malloc.h>
#include <mach/mach.h>

static size_t mono_bench_heap_bytes(void) {
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

static size_t mono_bench_rss_bytes(void) {
  mach_task_basic_info_data_t info;
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                (task_info_t)&info, &count) != KERN_SUCCESS)
    return 0;
  return info.resident_size;
}
"""
.}

proc heapBytes(): int {.importc: "mono_bench_heap_bytes", nodecl.}
proc rssBytes(): int {.importc: "mono_bench_rss_bytes", nodecl.}

const
  Rows = 250
  Columns = 320

type Source = ref object
  rows: seq[seq[string]]

proc fillGrid(view: MonoTextView, source: Source) =
  when defined(baselineMonoText):
    var cells = newSeq[MonoTextCell](Rows * Columns)
    for row in 0 ..< Rows:
      for column in 0 ..< Columns:
        cells[row * Columns + column] = initMonoTextCell(source.rows[row][column])
    view.replaceGrid(Rows, Columns, cells)
  else:
    let style = initMonoTextCellStyle()
    let provider: MonoTextRowProvider = proc(
        row: int, builder: var MonoTextRowBuilder
    ) =
      for column in 0 ..< Columns:
        builder.addCell(source.rows[row][column], style)
    view.replaceGrid(Rows, Columns, provider)

proc report(label: string, view: MonoTextView, source: Source) =
  let
    beforeAlloc = getAllocStats()
    beforeHeap = heapBytes()
    beforeRss = rssBytes()
  view.fillGrid(source)
  let
    afterAlloc = getAllocStats()
    afterHeap = heapBytes()
    afterRss = rssBytes()
  echo label,
    " alloc=",
    $(afterAlloc - beforeAlloc),
    " heapDelta=",
    afterHeap - beforeHeap,
    " rssDelta=",
    afterRss - beforeRss

when isMainModule:
  let beforeSource = heapBytes()
  let beforeSourceRss = rssBytes()
  let source = Source(rows: newSeq[seq[string]](Rows))
  for row in 0 ..< Rows:
    source.rows[row] = newSeq[string](Columns)
    for column in 0 ..< Columns:
      source.rows[row][column] = $(char(ord('a') + column mod 26))
  let afterSource = heapBytes()
  let afterSourceRss = rssBytes()
  let view = newMonoTextViewer()
  let afterView = heapBytes()
  let afterViewRss = rssBytes()
  echo "upstreamHeap=",
    afterSource - beforeSource, " upstreamRss=", afterSourceRss - beforeSourceRss
  echo "viewSetupHeap=", afterView - afterSource
  report("initial", view, source)
  source.rows[Rows div 2][0] = "Z"
  report("changed", view, source)
  report("unchanged", view, source)
  echo "viewportHeap=",
    heapBytes() - afterView, " viewportRss=", rssBytes() - afterViewRss

  let beforeEditorBuffer = heapBytes()
  var editorBuffer = celinaBuffer.newBuffer(Columns, Rows)
  for row in 0 ..< Rows:
    for column in 0 ..< Columns:
      editorBuffer[column, row] = celinaBuffer.cell(source.rows[row][column])
  echo "celinaEditorBufferHeap=", heapBytes() - beforeEditorBuffer
  doAssert editorBuffer[0, 0].symbol == source.rows[0][0]

  let beforeTerminalScreen = heapBytes()
  var
    terminalScreen = initTerminalScreen(Columns, Rows)
    terminalParser = initTerminalParser()
  for row in 0 ..< Rows:
    var line = newStringOfCap(Columns)
    for column in 0 ..< Columns:
      line.add source.rows[row][column]
    terminalParser.feed(terminalScreen, line)
    if row + 1 < Rows:
      terminalParser.feed(terminalScreen, "\r\n")
  echo "terminalScreenHeap=", heapBytes() - beforeTerminalScreen
  doAssert terminalScreen.cellAt(0, 0).text == source.rows[0][0]
