## Measure Markdown structure retention before queued rendering starts.
## Poll only Sigils, not NimKit main-thread rendering work, to keep the
## checkpoint independent of glyph layout and highlighting. Build matched
## versions from Atlas-configured worktrees and run each in a fresh process.
import std/[json, monotimes, os, strutils, times]
import sigils/threads
import merenda/nimkit
import merenda/nimkit/app/diagnostics

when defined(macosx):
  {.
    emit: """
#include <malloc/malloc.h>
#include <mach/mach.h>
static size_t markdown_key_heap_bytes(void) {
  vm_address_t *zones = NULL;
  unsigned count = 0;
  if (malloc_get_all_zones(mach_task_self(), NULL, &zones, &count) != KERN_SUCCESS)
    return 0;
  size_t total = 0;
  for (unsigned i = 0; i < count; ++i) {
    malloc_statistics_t stats;
    malloc_zone_statistics((malloc_zone_t *)zones[i], &stats);
    total += stats.size_in_use;
  }
  return total;
}
"""
  .}
  proc heapBytes(): int {.importc: "markdown_key_heap_bytes", nodecl.}
else:
  proc heapBytes(): int =
    getOccupiedMem()

proc makeSource(blockCount, repeatCount: int): string =
  for index in 0 ..< blockCount:
    result.add "```nim\n# unique " & $index & "\n"
    result.add "let value = 123456789\n".repeat(repeatCount)
    result.add "```\n\n"

when isMainModule:
  let
    blockCount =
      if paramCount() > 0:
        parseInt(paramStr(1))
      else:
        16
    repeatCount =
      if paramCount() > 1:
        parseInt(paramStr(2))
      else:
        8192
  if blockCount <= 0 or repeatCount <= 0:
    quit "block and repeat counts must be positive"
  let
    started = getMonoTime()
    source = makeSource(blockCount, repeatCount)
    beforeHeap = heapBytes()
    view = newMarkdownView(source)
    deadline = getMonoTime() + initDuration(seconds = 60)
  while view.markdownParseWorkerThreadId() < 0 and getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    if view.markdownParseWorkerThreadId() < 0:
      sleep(1)
  doAssert view.markdownParseWorkerThreadId() >= 0, "Markdown structure timed out"
  doAssert view.markdownParseError().len == 0, view.markdownParseError()
  doAssert view.isMarkdownRendering(), "expected rendering to remain queued"
  doAssert view.markdownRenderChunkCount() == 0, "render work ran before checkpoint"
  let
    heap = heapBytes()
    usage = processResourceUsage()
  echo $(
    %*{
      "stage": "structureApplied",
      "sourceBytes": source.len,
      "blocks": blockCount,
      "lineRepeats": repeatCount,
      "renderChunks": view.markdownRenderChunkCount(),
      "heapBeforeView": beforeHeap,
      "heapBytes": heap,
      "rssBytes": usage.residentBytes,
      "peakRssBytes": usage.peakResidentBytes,
      "elapsedMs": (getMonoTime() - started).inMilliseconds,
    }
  )
  stdout.flushFile()
  if paramCount() > 2 and paramStr(3) == "pause":
    discard stdin.readLine()
  doAssert view.isMarkdownRendering() and source.len > 0
