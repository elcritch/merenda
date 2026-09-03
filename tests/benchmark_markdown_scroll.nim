## Profiles CPU-side README scrolling through the dedicated-renderer handoff.
##
## Run the base revision without a define, and the fragment-native revision with:
##
##   atlas-run tests tests/benchmark_markdown_scroll.nim -- -d:release
##   atlas-run tests tests/benchmark_markdown_scroll.nim -- \
##     -d:release -d:fragmentNativeProfile
##
## This diagnostic excludes GPU execution. It measures scroll invalidation, view
## rendering/reconciliation, bounded-channel transfer, renderer-side scene
## application, direct fragment-edge traversal, and acknowledgement.

import std/[algorithm, monotimes, os, strformat, times]

import figdraw

import merenda/nimkit
import merenda/nimkit/app/backend as nimkitBackend
when defined(fragmentNativeProfile):
  import merenda/nimkit/drawing/renderscenes as retainedScenes

const
  RepositoryRoot = currentSourcePath().parentDir.parentDir
  RepositoryReadme = RepositoryRoot / "README.md"
  WarmupFrames = 20
  ProfileFrames = 240

proc unavailableMarkdownImage(url: string): ImageResource =
  discard url

proc percentile(samples: seq[float], fraction: float): float =
  var ordered = samples
  ordered.sort()
  ordered[min((ordered.len.float * fraction).int, ordered.high)]

proc scrollPosition(frame: int, maximum: float32): float32 =
  let
    cycleLength = ProfileFrames div 2
    position = frame mod cycleLength
    fraction = position.float32 / max(cycleLength - 1, 1).float32
  if (frame div cycleLength) mod 2 == 0:
    maximum * fraction
  else:
    maximum * (1.0'f32 - fraction)

proc countTraversalNodes(renders: Renders, cursor: RenderCursor): Natural =
  result = 1
  for child in renders.children(cursor):
    result += renders.countTraversalNodes(child)

proc traversalNodeCount(renders: Renders): Natural =
  for level, _ in renders.pairs():
    for root in renders.roots(level):
      result += renders.countTraversalNodes(root)

let
  source = readFile(RepositoryReadme)
  viewer = newMarkdownView(
    source, frame = rect(0, 0, 760, 540), imageLoader = unavailableMarkdownImage
  )
doAssert viewer.waitForMarkdownParsing(), "README parsing should complete"
discard viewer.buildRenders()
doAssert viewer.waitForMarkdownLayout(), "README layout should complete"
discard viewer.buildRenders()

let
  scrollView = viewer.scrollView()
  maximumY = scrollView.maximumContentOffset().y
  logicalSize = initSize(760.0, 540.0)
  runtime = nimkitBackend.newThreadRenderer()
  host = nimkitBackend.newThreadHostClient(runtime.client)
doAssert maximumY > 0.0'f32, "README should exceed the Markdown viewport"

var
  checksum: uint64
  capturedViews: uint64
  traversedNodes: uint64
  prepareMilliseconds: seq[float]
  transferMilliseconds: seq[float]
  applyMilliseconds: seq[float]
  traversalMilliseconds: seq[float]
when defined(fragmentNativeProfile):
  var replica = retainedScenes.newRenderSceneReplica()
  let retainedScene = viewer.buildRenderScene()
  var documentCaptureBaseline: uint64

proc renderScrollFrame(frame: int) =
  scrollView.contentOffset = initPoint(0.0, scrollPosition(frame, maximumY))
  let prepareStarted = getMonoTime()
  when defined(fragmentNativeProfile):
    let scene = viewer.buildRenderScene()
    prepareMilliseconds.add(
      (getMonoTime() - prepareStarted).inNanoseconds.float / 1_000_000.0
    )
    let transferStarted = getMonoTime()
    doAssert host.submitRenderScene(scene, logicalSize)
    var snapshot: nimkitBackend.ThreadRenderSnapshot
    doAssert host.channels.pollLatestRender(snapshot)
    transferMilliseconds.add(
      (getMonoTime() - transferStarted).inNanoseconds.float / 1_000_000.0
    )
    let applyStarted = getMonoTime()
    var update = move snapshot.sceneUpdate
    if retainedScenes.fullSnapshot(update):
      replica = retainedScenes.newRenderSceneReplica()
    retainedScenes.apply(replica, update)
    checksum += retainedScenes.viewCount(update).uint64
    capturedViews += retainedScenes.capturedViewCount(update).uint64
    host.acknowledgeRender(snapshot.renderId)
    applyMilliseconds.add(
      (getMonoTime() - applyStarted).inNanoseconds.float / 1_000_000.0
    )
    let traversalStarted = getMonoTime()
    traversedNodes += retainedScenes.traversalNodeCount(replica).uint64
    traversalMilliseconds.add(
      (getMonoTime() - traversalStarted).inNanoseconds.float / 1_000_000.0
    )
  else:
    var renders = viewer.buildRenders()
    prepareMilliseconds.add(
      (getMonoTime() - prepareStarted).inNanoseconds.float / 1_000_000.0
    )
    checksum += renders.len(DefaultDrawLevel).uint64
    let traversalStarted = getMonoTime()
    traversedNodes += renders.traversalNodeCount().uint64
    traversalMilliseconds.add(
      (getMonoTime() - traversalStarted).inNanoseconds.float / 1_000_000.0
    )
    let transferStarted = getMonoTime()
    doAssert host.submitRenders(ensureMove renders, logicalSize)
    var snapshot: nimkitBackend.ThreadRenderSnapshot
    doAssert host.channels.pollLatestRender(snapshot)
    transferMilliseconds.add(
      (getMonoTime() - transferStarted).inNanoseconds.float / 1_000_000.0
    )
    let applyStarted = getMonoTime()
    viewer.invalidateRenderCache()
    host.acknowledgeRender(snapshot.renderId)
    applyMilliseconds.add(
      (getMonoTime() - applyStarted).inNanoseconds.float / 1_000_000.0
    )

for frame in 0 ..< WarmupFrames:
  renderScrollFrame(frame)
when defined(fragmentNativeProfile):
  documentCaptureBaseline =
    retainedScene.viewCaptureGeneration(viewer.textView().renderViewId())
checksum = 0
capturedViews = 0
traversedNodes = 0
prepareMilliseconds.setLen(0)
transferMilliseconds.setLen(0)
applyMilliseconds.setLen(0)
traversalMilliseconds.setLen(0)

var
  wallMilliseconds = newSeqOfCap[float](ProfileFrames)
  cpuMilliseconds = newSeqOfCap[float](ProfileFrames)
let
  totalWallStarted = getMonoTime()
  totalCpuStarted = cpuTime()
for frame in 0 ..< ProfileFrames:
  let
    wallStarted = getMonoTime()
    cpuStarted = cpuTime()
  renderScrollFrame(frame + WarmupFrames)
  cpuMilliseconds.add((cpuTime() - cpuStarted) * 1_000.0)
  wallMilliseconds.add((getMonoTime() - wallStarted).inNanoseconds.float / 1_000_000.0)
let
  totalCpu = cpuTime() - totalCpuStarted
  totalWall = (getMonoTime() - totalWallStarted).inNanoseconds.float / 1_000_000_000.0
  mode = when defined(fragmentNativeProfile): "fragment-native" else: "monolithic"

echo "README Markdown scroll profile (", mode, ")"
echo &"document: {source.len} bytes, maximum scroll: {maximumY:.1f} px"
echo &"frames: {ProfileFrames}, checksum: {checksum}"
echo &"wall: median {wallMilliseconds.percentile(0.50):.3f} ms/frame, " &
  &"p95 {wallMilliseconds.percentile(0.95):.3f} ms/frame"
echo &"CPU:  median {cpuMilliseconds.percentile(0.50):.3f} ms/frame, " &
  &"p95 {cpuMilliseconds.percentile(0.95):.3f} ms/frame"
echo &"stages (median wall): prepare {prepareMilliseconds.percentile(0.50):.3f} ms, " &
  &"transfer {transferMilliseconds.percentile(0.50):.3f} ms, " &
  &"apply/ack {applyMilliseconds.percentile(0.50):.3f} ms, " &
  &"traversal {traversalMilliseconds.percentile(0.50):.3f} ms"
echo &"traversed nodes: {traversedNodes}"
when defined(fragmentNativeProfile):
  echo &"captured view contributions: {capturedViews}"
  echo &"document contribution captures: " &
    $(
      retainedScene.viewCaptureGeneration(viewer.textView().renderViewId()) -
      documentCaptureBaseline
    )
echo &"total: {totalWall:.3f} s wall, {totalCpu:.3f} s CPU, " &
  &"CPU/wall {totalCpu / max(totalWall, 0.000_001) * 100.0:.1f}%"
