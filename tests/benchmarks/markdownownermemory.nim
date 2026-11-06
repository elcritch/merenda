## Measure two Markdown view structures before queued rendering starts.
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
    first = newMarkdownView()
    second = newMarkdownView()
  doAssert first.waitForMarkdownParsing(60_000)
  doAssert second.waitForMarkdownParsing(60_000)
  let
    source = makeSource(blockCount, repeatCount)
    beforeHeap = heapBytes()
    started = getMonoTime()
  when defined(sharedMarkdownOwner):
    let owner = newMarkdownDocumentOwner(source)
    doAssert first.adoptMarkdownDocument(owner)
    doAssert second.adoptMarkdownDocument(owner)
  else:
    first.markdown = source
    second.markdown = source
  let deadline = getMonoTime() + initDuration(seconds = 60)
  while (not first.isMarkdownRendering() or not second.isMarkdownRendering()) and
      getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    if not first.isMarkdownRendering() or not second.isMarkdownRendering():
      sleep(1)
  doAssert first.markdownParseWorkerThreadId() >= 0 and
    second.markdownParseWorkerThreadId() >= 0, "Markdown structure timed out"
  doAssert first.markdownParseError().len == 0 and second.markdownParseError().len == 0
  doAssert first.isMarkdownRendering() and second.isMarkdownRendering(),
    "expected rendering to remain queued"
  doAssert first.markdownRenderChunkCount() == 0 and
    second.markdownRenderChunkCount() == 0
  let
    heap = heapBytes()
    usage = processResourceUsage()
  echo $(
    %*{
      "stage": "twoStructuresApplied",
      "variant": (when defined(sharedMarkdownOwner): "shared" else: "standalone"),
      "sourceBytes": source.len,
      "blocks": blockCount,
      "lineRepeats": repeatCount,
      "views": 2,
      "heapWithEmptyViewsAndSource": beforeHeap,
      "heapBytes": heap,
      "rssBytes": usage.residentBytes,
      "peakRssBytes": usage.peakResidentBytes,
      "elapsedMs": (getMonoTime() - started).inMilliseconds,
    }
  )
  stdout.flushFile()
  if paramCount() > 2 and paramStr(3) == "pause":
    discard stdin.readLine()
  doAssert first.isMarkdownRendering() and second.isMarkdownRendering() and
    source.len > 0
