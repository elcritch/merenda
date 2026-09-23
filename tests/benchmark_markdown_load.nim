## Time README Markdown view setup on one process and report its major phases.
## Build in each worktree with `nim c -d:release -o:/tmp/markdown-load
## tests/benchmark_markdown_load.nim`, then run the binary from that worktree.

import std/[algorithm, monotimes, os, sequtils, strformat, times]

import merenda/nimkit

const
  RepositoryReadme = currentSourcePath().parentDir.parentDir / "README.md"
  SampleCount = 4

proc unavailableMarkdownImage(url: string): ImageResource =
  discard url

type MarkdownLoadSample = object
  constructionMs: float64
  parseApplyMs: float64
  layoutMs: float64
  firstRenderMs: float64
  runeCount: int
  visualLines: int

proc sampleMarkdownLoad(source: string): MarkdownLoadSample =
  let constructionStarted = getMonoTime()
  let view = newMarkdownView(
    source, frame = rect(0, 0, 760, 540), imageLoader = unavailableMarkdownImage
  )
  let parsingStarted = getMonoTime()
  doAssert view.waitForMarkdownParsing(60_000), "README Markdown parsing timed out"
  let layoutStarted = getMonoTime()
  doAssert view.waitForMarkdownLayout(120_000), "README Markdown layout timed out"
  let renderingStarted = getMonoTime()
  discard buildRenders(view)
  let
    renderedAt = getMonoTime()
    snapshot = view.textView().layoutManager().layoutSnapshot()
  result = MarkdownLoadSample(
    constructionMs: (parsingStarted - constructionStarted).inNanoseconds.float / 1e6,
    parseApplyMs: (layoutStarted - parsingStarted).inNanoseconds.float / 1e6,
    layoutMs: (renderingStarted - layoutStarted).inNanoseconds.float / 1e6,
    firstRenderMs: (renderedAt - renderingStarted).inNanoseconds.float / 1e6,
    runeCount: view.textStorage().len,
    visualLines: snapshot.lineFragments.len,
  )

proc median(values: openArray[float64]): float64 =
  var sorted = @values
  sorted.sort()
  sorted[sorted.len div 2]

when isMainModule:
  let source = readFile(RepositoryReadme)
  var samples: seq[MarkdownLoadSample]
  for index in 0 ..< SampleCount:
    let sample = sampleMarkdownLoad(source)
    samples.add sample
    echo &"run={index + 1} constructionMs={sample.constructionMs:.1f} " &
      &"parseApplyMs={sample.parseApplyMs:.1f} layoutMs={sample.layoutMs:.1f} " &
      &"firstRenderMs={sample.firstRenderMs:.1f} runes={sample.runeCount} " &
      &"visualLines={sample.visualLines}"
  echo &"medianMs construction={median(samples.mapIt(it.constructionMs)):.1f} " &
    &"parseApply={median(samples.mapIt(it.parseApplyMs)):.1f} " &
    &"layout={median(samples.mapIt(it.layoutMs)):.1f} " &
    &"firstRender={median(samples.mapIt(it.firstRenderMs)):.1f}"
