## Measures the ownership-transfer and bounded-channel cost paid when the
## application thread submits a FigDraw render snapshot to the primary renderer
## thread.
##
## Run with:
##   nim r tests/benchmark_render_snapshots.nim
##
## This is a diagnostic benchmark. It intentionally has no timing threshold so
## machine load and CI hardware cannot turn performance noise into test failures.

import std/[assertions, monotimes, strformat, times]

import figdraw

import merenda/nimkit/app/backend as nimkitBackend
import merenda/nimkit/foundation/types as nimkitTypes

type BenchmarkCase = object
  nodeCount: int
  iterations: int

const BenchmarkCases = [
  BenchmarkCase(nodeCount: 100, iterations: 1_000_000),
  BenchmarkCase(nodeCount: 1_000, iterations: 1_000_000),
  BenchmarkCase(nodeCount: 5_000, iterations: 1_000_000),
  BenchmarkCase(nodeCount: 10_000, iterations: 1_000_000),
]

proc makeRenders(nodeCount: int): Renders =
  result = newRenders()
  for index in 0 ..< nodeCount:
    discard result.addRoot(
      Fig(
        kind: nkRectangle,
        screenBox:
          figdraw.rect((index mod 100).float32, (index div 100).float32, 20.0, 10.0),
      )
    )

proc benchmark(benchmarkCase: BenchmarkCase) =
  let
    runtime = nimkitBackend.newThreadRenderer()
    host = nimkitBackend.newThreadHostClient(runtime.client)
    logicalSize = nimkitTypes.initSize(1_000.0, 1_000.0)
  var renders = makeRenders(benchmarkCase.nodeCount)
  host.requestCreation(
    runtime.client,
    nimkitTypes.rect(0.0, 0.0, logicalSize.width, logicalSize.height),
    "Render Snapshot Benchmark",
  )

  var snapshot: nimkitBackend.ThreadRenderSnapshot
  doAssert host.submitRenders(ensureMove renders, logicalSize)
  doAssert host.channels.pollLatestRender(snapshot)
  doAssert snapshot.renders.len(0.ZLevel) == benchmarkCase.nodeCount
  renders = move snapshot.renders

  let startedAt = getMonoTime()
  for _ in 0 ..< benchmarkCase.iterations:
    doAssert host.submitRenders(ensureMove renders, logicalSize)
    doAssert host.channels.pollLatestRender(snapshot)
    renders = move snapshot.renders
  let
    elapsed = getMonoTime() - startedAt
    elapsedSeconds = max(elapsed.inNanoseconds.float / 1_000_000_000.0, 0.000_001)
    meanMicroseconds = elapsedSeconds * 1_000_000.0 / benchmarkCase.iterations.float
    rawNodeBytes = benchmarkCase.nodeCount * sizeof(Fig)
    rawNodeMiB = rawNodeBytes.float / (1024.0 * 1024.0)
    rawThroughput = rawNodeMiB * benchmarkCase.iterations.float / elapsedSeconds

  echo &"{benchmarkCase.nodeCount:>6} nodes  " &
    &"{meanMicroseconds:>9.2f} us/snapshot  " & &"{rawThroughput:>9.1f} raw-node MiB/s"

echo "Threaded render snapshot transport"
echo "Fig size: ", sizeof(Fig), " bytes"
for benchmarkCase in BenchmarkCases:
  benchmark(benchmarkCase)
