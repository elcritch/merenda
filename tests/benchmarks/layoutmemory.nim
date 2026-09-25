## Compare retained layout and line-render memory in separate processes.
## Run each mode with an Atlas-configured worktree:
##   nim c -d:release --mm:arc -o:/tmp/layoutmemory tests/benchmarks/layoutmemory.nim
##   /tmp/layoutmemory owned
##   /tmp/layoutmemory shared

import std/[hashes, os, strutils]

import figdraw
import threading/smartptrs

when defined(macosx):
  {.
    emit:
      """
#include <malloc/malloc.h>
#include <mach/mach.h>

static size_t layout_bench_heap_bytes(void) {
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

static size_t layout_bench_rss_bytes(void) {
  mach_task_basic_info_data_t info;
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                (task_info_t)&info, &count) != KERN_SUCCESS)
    return 0;
  return info.resident_size;
}
"""
  .}
  proc heapBytes(): int {.importc: "layout_bench_heap_bytes", nodecl.}
  proc rssBytes(): int {.importc: "layout_bench_rss_bytes", nodecl.}
elif defined(linux):
  proc heapBytes(): int =
    getOccupiedMem()

  proc rssBytes(): int =
    for line in lines("/proc/self/status"):
      if line.startsWith("VmRSS:"):
        return parseInt(line.splitWhitespace()[1]) * 1024

const
  LineCount = 1200
  GlyphsPerLine = 160
  TotalGlyphs = LineCount * GlyphsPerLine

proc makeLayout(): GlyphArrangement =
  let
    source = initArrangementRunes(repeat("a", TotalGlyphs))
    font = GlyphFont(fontId: FontId(Hash(1)), lineHeight: 14)
  var
    positions = newSeq[Vec2](TotalGlyphs)
    rectangles = newSeq[Rect](TotalGlyphs)
  for index in 0 ..< TotalGlyphs:
    let
      x = (index mod GlyphsPerLine).float32 * 8
      y = (index div GlyphsPerLine).float32 * 14
    positions[index] = vec2(x, y)
    rectangles[index] = rect(x, y, 8, 14)
  result = GlyphArrangement(
    spans: @[0 .. TotalGlyphs - 1],
    fonts: @[font],
    sourceRunes: source,
    runes: source,
    positions: positions,
    selectionRects: rectangles,
    arrangedGlyphs: buildArrangedGlyphs(
      source, positions, rectangles, @[0 .. TotalGlyphs - 1], @[font]
    ),
  )
  for lineIndex in 0 ..< LineCount:
    let first = lineIndex * GlyphsPerLine
    result.lines.add first .. first + GlyphsPerLine - 1

proc ownedLine(layout: GlyphArrangement, glyphRange: Slice[int]): GlyphArrangement =
  result.lines = @[0 .. GlyphsPerLine - 1]
  result.spans = @[0 .. GlyphsPerLine - 1]
  result.fonts = layout.fonts
  result.arrangedGlyphs = layout.arrangedGlyphs[glyphRange]
  result.runes = layout.runes[glyphRange]
  result.positions = layout.positions[glyphRange]
  result.selectionRects = layout.selectionRects[glyphRange]

proc isolatedOwnedLine(line: GlyphArrangement): GlyphArrangement =
  result = line
  result.arrangedGlyphs = line.arrangedGlyphs[0 ..< line.arrangedGlyphs.len]
  result.runes = line.runes.copyUtf8Runes()
  result.positions = line.positions[0 ..< line.positions.len]
  result.selectionRects = line.selectionRects[0 ..< line.selectionRects.len]

when isMainModule:
  if paramCount() != 1 or paramStr(1) notin ["owned", "shared"]:
    quit "usage: layoutmemory owned|shared"
  let mode = paramStr(1)
  var layout = makeLayout()
  let
    setupHeap = heapBytes()
    setupRss = rssBytes()
  var
    uiLines = newSeqOfCap[GlyphArrangement](LineCount)
    replicas = newSeqOfCap[GlyphArrangement](LineCount)
  if mode == "owned":
    for lineIndex in 0 ..< LineCount:
      let first = lineIndex * GlyphsPerLine
      uiLines.add ownedLine(layout, first .. first + GlyphsPerLine - 1)
    for line in uiLines:
      replicas.add isolatedOwnedLine(line)
  else:
    let owner = shareGlyphArrangement(move layout)
    for lineIndex in 0 ..< LineCount:
      let first = lineIndex * GlyphsPerLine
      uiLines.add owner.glyphArrangementView(first .. first + GlyphsPerLine - 1)
    for lineIndex in 0 ..< LineCount:
      let first = lineIndex * GlyphsPerLine
      replicas.add owner.glyphArrangementView(first .. first + GlyphsPerLine - 1)
    doAssert owner[].positions.len == 0
  doAssert uiLines.len == LineCount
  doAssert replicas[^1].glyphCount() == GlyphsPerLine
  let
    retainedHeap = heapBytes()
    retainedRss = rssBytes()
  echo "mode=",
    mode,
    " glyphs=",
    TotalGlyphs,
    " lines=",
    LineCount,
    " heapAfterSetupKiB=",
    setupHeap div 1024,
    " heapRetainedKiB=",
    retainedHeap div 1024,
    " heapLineAndReplicaDeltaKiB=",
    (retainedHeap - setupHeap) div 1024,
    " rssAfterSetupKiB=",
    setupRss div 1024,
    " rssRetainedKiB=",
    retainedRss div 1024,
    " rssLineAndReplicaDeltaKiB=",
    (retainedRss - setupRss) div 1024
