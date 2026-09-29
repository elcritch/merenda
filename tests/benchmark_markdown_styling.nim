## Measures owner-thread attribute application for streamed syntax highlighting.
## nim c -d:release -o:/tmp/markdown-styling tests/benchmark_markdown_styling.nim
## /tmp/markdown-styling
##
## Construction and tokenization are outside the timed section. Each batch uses
## 64 lines, like the Markdown worker. Quoted lines start with separate prefix
## runs so the benchmark also exercises preserving styles between token spans.

import std/[algorithm, monotimes, strformat, strutils, times, unicode]

import merenda/nimkit/foundation/types
import merenda/nimkit/text/[textstorage, texttypes]

const
  BatchLines = 64
  Samples = 5
  Line = "let item = 12 # comment\n"

proc sample(lines: int, quoted: bool): float64 =
  let
    prefix = if quoted: "│ " else: ""
    prefixLength = prefix.runeLen
    lineLength = prefixLength + Line.len
    base = defaultTextAttributes()
    quote = defaultTextAttributes(color(0.4, 0.4, 0.4))
    keyword = defaultTextAttributes(color(0.9, 0.2, 0.3))
    number = defaultTextAttributes(color(0.2, 0.7, 0.3))
    comment = defaultTextAttributes(color(0.3, 0.5, 0.8))
  var initial: seq[TextAttributeRun]
  if quoted:
    for line in 0 ..< lines:
      initial.add TextAttributeRun(
        range: initTextRange(line * lineLength, prefixLength), attributes: quote
      )
      initial.add TextAttributeRun(
        range: initTextRange(line * lineLength + prefixLength, Line.len),
        attributes: base,
      )
  let storage = newTextStorage(repeat(prefix & Line, lines), initial)
  var batches: seq[seq[TextAttributeRun]]
  for batchStart in countup(0, lines - 1, BatchLines):
    var overlays: seq[TextAttributeRun]
    for line in batchStart ..< min(batchStart + BatchLines, lines):
      let first = line * lineLength + prefixLength
      overlays.add TextAttributeRun(range: initTextRange(first, 3), attributes: keyword)
      overlays.add TextAttributeRun(
        range: initTextRange(first + 11, 2), attributes: number
      )
      overlays.add TextAttributeRun(
        range: initTextRange(first + 14, 9), attributes: comment
      )
    batches.add overlays
  let started = getMonoTime()
  for batch in batches:
    storage.overlayAttributeRanges(batch)
  result = (getMonoTime() - started).inNanoseconds.float64 / 1e6
  doAssert storage.revision.int == batches.len
  for line in [0, lines div 2, lines - 1]:
    let first = line * lineLength + prefixLength
    doAssert storage.attributesAt(first) == keyword
    doAssert storage.attributesAt(first + 11) == number
    doAssert storage.attributesAt(first + 14) == comment
    if quoted:
      doAssert storage.attributesAt(line * lineLength) == quote

when isMainModule:
  for quoted in [false, true]:
    var previous = 0.0
    for lines in [8_000, 16_000, 32_000]:
      discard sample(lines, quoted)
      var timings: seq[float64]
      for _ in 0 ..< Samples:
        timings.add sample(lines, quoted)
      timings.sort()
      let
        median = timings[Samples div 2]
        growth =
          if previous > 0:
            median / previous
          else:
            0.0
      echo &"quoted={quoted} lines={lines} batchLines={BatchLines} " &
        &"medianMs={median:.3f} usPerLine={median * 1000 / lines.float:.3f} " &
        &"doublingRatio={growth:.2f}"
      previous = median
