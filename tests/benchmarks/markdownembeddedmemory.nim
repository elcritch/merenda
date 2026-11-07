## Matched Markdown embedded-source and viewport probe. Run each sample in a
## fresh process, with the same harness and dependencies for both revisions.
## Heap is live malloc-zone bytes; peak RSS is the process high-water mark.
import std/[json, monotimes, os, strutils, times]
import merenda/nimkit
import merenda/nimkit/app/diagnostics
import merenda/nimkit/foundation/mainthreadwork

when defined(macosx):
  {.
    emit: """
#include <malloc/malloc.h>
#include <mach/mach.h>
static size_t embedded_bench_heap_bytes(void) {
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
  proc heapBytes(): int {.importc: "embedded_bench_heap_bytes", nodecl.}
else:
  proc heapBytes(): int =
    getOccupiedMem()

proc codeViews(view: MarkdownView): seq[ScrollView] =
  for child in view.textView().subviews():
    if child of ScrollView:
      let scroll = ScrollView(child)
      if scroll.documentView() of TextView and
          scroll.documentView().accessibilityLabel() == "Markdown code block":
        result.add scroll

proc settle(view: MarkdownView) =
  let deadline = getMonoTime() + initDuration(seconds = 60)
  var pending = true
  while pending and getMonoTime() < deadline:
    discard view.pollMarkdownParsing()
    view.layoutSubtreeIfNeeded()
    pending = view.isMarkdownRendering() or view.isMarkdownLayoutPending()
    for child in view.textView().subviews():
      if child of ScrollView:
        let document = ScrollView(child).documentView()
        if document of TextView and
            TextView(document).layoutManager().isBackgroundLayoutPending():
          pending = true
    if pending:
      sleep(1)
  doAssert not pending, "embedded layout or eviction did not settle"

proc sourceFor(count: int): string =
  let
    code = "let value = \"" & repeat("unicode αβ data ", 45) & "\""
    row = "| " & repeat("linked [value](https://example.test) ", 12) & " | right |"
  # Keep one overflowing child at the initial viewport, then exercise the same
  # wide code and tables through nested quote mappings throughout the document.
  result = "```nim\n" & code & "\n```\n\n"
  for index in 0 ..< count:
    result.add "## Section " & $index & "\n\n> > ```nim\n> > " & code &
      "\n> > let next = " & $index & "\n> > ```\n\n> " & row & "\n> | --- | --- |\n> " &
      row & "\n\n"

proc report(stage: string, sourceBytes, runes, childCount: int, start: MonoTime) =
  let usage = processResourceUsage()
  echo $(
    %*{
      "stage": stage,
      "sourceBytes": sourceBytes,
      "renderedRunes": runes,
      "codeViews": childCount,
      "heapBytes": heapBytes(),
      "rssBytes": usage.residentBytes,
      "peakRssBytes": usage.peakResidentBytes,
      "elapsedMs": (getMonoTime() - start).inMilliseconds,
    }
  )

when isMainModule:
  let count =
    if paramCount() == 0:
      50
    else:
      parseInt(paramStr(1))
  if count < 2:
    quit "count must be at least two"
  let
    start = getMonoTime()
    source = sourceFor(count)
  report("source", source.len, 0, 0, start)
  var view =
    newMarkdownView(source, frame = rect(0, 0, 260, 180), syntaxHighlighter = nil)
  if not view.waitForMarkdownParsing(60_000) or not view.waitForMarkdownLayout(60_000):
    quit "Markdown rendering timed out"
  discard view.buildRenders()
  view.layoutSubtreeIfNeeded()
  view.settle()
  doAssert view.textStorage().stringValue().contains("unicode αβ data")
  let runes = view.textStorage().len
  var originalStorage: pointer
  var originalOffset: float32
  block:
    let scrolls = view.codeViews()
    doAssert scrolls.len > 0
    let child = TextView(scrolls[0].documentView())
    originalStorage = cast[pointer](child.textStorage())
    child.selectedRange = initTextRange(6, 5)
    scrolls[0].contentOffset = initPoint(scrolls[0].maximumContentOffset().x, 0)
    originalOffset = scrolls[0].contentOffset().x
    doAssert originalOffset > 0
  report("firstRender", source.len, runes, view.codeViews().len, start)
  doAssert view.scrollView().maximumContentOffset().y > 0
  view.scrollView().contentOffset =
    initPoint(0, view.scrollView().maximumContentOffset().y)
  discard drainMainThreadWork()
  view.textView().setNeedsLayout()
  discard view.buildRenders()
  view.layoutSubtreeIfNeeded()
  view.settle()
  report("offscreen", source.len, runes, view.codeViews().len, start)
  view.scrollView().contentOffset = initPoint(0, 0)
  discard drainMainThreadWork()
  view.textView().setNeedsLayout()
  discard view.buildRenders()
  view.layoutSubtreeIfNeeded()
  view.settle()
  block:
    let scrolls = view.codeViews()
    doAssert scrolls.len > 0
    let child = TextView(scrolls[0].documentView())
    doAssert cast[pointer](child.textStorage()) == originalStorage
    doAssert child.selectedRange() == initTextRange(6, 5)
    doAssert abs(scrolls[0].contentOffset().x - originalOffset) < 0.01'f32
  report("restored", source.len, runes, view.codeViews().len, start)
  view = nil
  report("released", source.len, 0, 0, start)
