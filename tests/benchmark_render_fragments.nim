## Compares monolithic NimKit rendering with the incremental-render scene
## foundation and probes fragment operations for nonlinear scaling.
##
## Run a release build so bounds checks and debug diagnostics do not dominate:
##
##   nim c -d:release -o:/tmp/benchmark_render_fragments \
##     tests/benchmark_render_fragments.nim
##   /tmp/benchmark_render_fragments
##
## This is a diagnostic benchmark. It intentionally has no timing threshold so
## machine load and CI hardware cannot turn performance noise into test failures.

import std/[algorithm, monotimes, strformat, times]

import figdraw

import merenda/nimkit

type BenchmarkCase = object
  viewCount: int
  iterations: int

const
  SampleCount = 7
  BenchmarkCases = [
    BenchmarkCase(viewCount: 100, iterations: 1_000),
    BenchmarkCase(viewCount: 1_000, iterations: 100),
    BenchmarkCase(viewCount: 5_000, iterations: 20),
    BenchmarkCase(viewCount: 10_000, iterations: 10),
  ]

var benchmarkSink: uint64

proc medianNanoseconds(iterations: int, action: proc()): float =
  var samples = newSeqOfCap[int64](SampleCount)
  for _ in 0 ..< SampleCount:
    let startedAt = getMonoTime()
    for _ in 0 ..< iterations:
      action()
    samples.add (getMonoTime() - startedAt).inNanoseconds
  samples.sort()
  samples[SampleCount div 2].float / iterations.float

proc report(name: string, viewCount: int, nanoseconds: float) =
  let
    microseconds = nanoseconds / 1_000.0
    nanosecondsPerView = nanoseconds / viewCount.float
  echo &"{name:<28} {viewCount:>6} views  {microseconds:>11.2f} us/op  " &
    &"{nanosecondsPerView:>9.2f} ns/view"

proc reportPopulationOperation(name: string, population: int, nanoseconds: float) =
  echo &"{name:<28} {population:>6} slots  {nanoseconds / 1_000.0:>11.2f} us/op"

proc makeFlatTree(viewCount: int): View =
  result = newView(frame = rect(0, 0, 1_000, 1_000))
  for index in 1 ..< viewCount:
    result.addSubview(
      newView(
        frame = rect((index mod 100).float32, (index div 100).float32, 20.0, 10.0)
      )
    )

proc benchmarkMonolithic(benchmarkCase: BenchmarkCase) =
  let root = makeFlatTree(benchmarkCase.viewCount)
  let leaf = root.subviews[root.subviews.len div 2]
  discard root.buildRenders()

  let cachedTime = medianNanoseconds(
    benchmarkCase.iterations,
    proc() =
      let renders = root.buildRenders()
      benchmarkSink = benchmarkSink xor renders.len(DefaultDrawLevel).uint64,
  )
  report("monolithic cached", benchmarkCase.viewCount, cachedTime)

  let dirtyTime = medianNanoseconds(
    benchmarkCase.iterations,
    proc() =
      root.needsDisplay = true
      let renders = root.buildRenders()
      benchmarkSink = benchmarkSink xor renders.len(DefaultDrawLevel).uint64,
  )
  report("monolithic dirty", benchmarkCase.viewCount, dirtyTime)

  let leafDirtyTime = medianNanoseconds(
    benchmarkCase.iterations,
    proc() =
      leaf.needsDisplay = true
      let renders = root.buildRenders()
      benchmarkSink = benchmarkSink xor renders.len(DefaultDrawLevel).uint64,
  )
  report("monolithic leaf dirty", benchmarkCase.viewCount, leafDirtyTime)

when declared(RenderScene):
  proc benchmarkScene(benchmarkCase: BenchmarkCase) =
    let root = makeFlatTree(benchmarkCase.viewCount)
    let leaf = root.subviews[root.subviews.len div 2]
    let scene = root.buildRenderScene()

    let cachedTime = medianNanoseconds(
      benchmarkCase.iterations,
      proc() =
        let current = root.buildRenderScene()
        benchmarkSink = benchmarkSink xor current.frameGeneration(),
    )
    report("scene cached", benchmarkCase.viewCount, cachedTime)

    let dirtyTime = medianNanoseconds(
      benchmarkCase.iterations,
      proc() =
        root.needsDisplay = true
        let current = root.buildRenderScene()
        benchmarkSink = benchmarkSink xor current.frameGeneration(),
    )
    report("scene dirty", benchmarkCase.viewCount, dirtyTime)

    let leafDirtyTime = medianNanoseconds(
      benchmarkCase.iterations,
      proc() =
        leaf.needsDisplay = true
        let current = root.buildRenderScene()
        benchmarkSink = benchmarkSink xor current.frameGeneration(),
    )
    report("scene leaf dirty", benchmarkCase.viewCount, leafDirtyTime)

    let materializeTime = medianNanoseconds(
      benchmarkCase.iterations,
      proc() =
        let renders = scene.materialize()
        benchmarkSink = benchmarkSink xor renders.len(DefaultDrawLevel).uint64,
    )
    report("scene materialize", benchmarkCase.viewCount, materializeTime)

  proc makeLayeredRenders(nodeCount, layerCount: int): Renders =
    result = newRenders()
    for index in 0 ..< nodeCount:
      discard result.addRoot(
        (index mod layerCount).ZLevel,
        Fig(
          kind: nkRectangle,
          screenBox:
            figdraw.rect((index mod 100).float32, (index div 100).float32, 20.0, 10.0),
        ),
      )

  proc benchmarkSceneReplacement(nodeCount, layerCount, iterations: int) =
    let
      renders = makeLayeredRenders(nodeCount, layerCount)
      scene = newRenderScene()
    scene.replaceContents(renders, nil, newSeq[RenderViewId]())

    let elapsed = medianNanoseconds(
      iterations,
      proc() =
        scene.replaceContents(renders, nil, newSeq[RenderViewId]())
        benchmarkSink = benchmarkSink xor scene.frameGeneration(),
    )
    let label = &"scene replace/{layerCount} layers"
    report(label, nodeCount, elapsed)

  proc makePopulatedFragmentSiblings(
      fragmentCount: int
  ): tuple[fragments: RenderFragments, handles: seq[RenderFragmentHandle]] =
    result.fragments = newRenderFragments()
    let root = result.fragments.addRoot(0.ZLevel, Fig(kind: nkRectangle))
    let parent = result.fragments.nodeCursor(0.ZLevel, root)
    result.handles = newSeqOfCap[RenderFragmentHandle](fragmentCount)
    for index in 0 ..< fragmentCount:
      var contents = RenderList()
      discard contents.addRoot(
        Fig(
          kind: nkRectangle,
          screenBox:
            figdraw.rect((index mod 100).float32, (index div 100).float32, 20.0, 10.0),
        )
      )
      result.handles.add result.fragments.attachChildFragment(
        parent, index.Natural, move contents
      )

  proc benchmarkFragmentDensity(benchmarkCase: BenchmarkCase) =
    let siblings = makePopulatedFragmentSiblings(benchmarkCase.viewCount)

    let materializeTime = medianNanoseconds(
      benchmarkCase.iterations,
      proc() =
        let renders = siblings.fragments.materialize()
        benchmarkSink = benchmarkSink xor renders.len(DefaultDrawLevel).uint64,
    )
    report("materialize/fragment slots", benchmarkCase.viewCount, materializeTime)

    var current = siblings.handles[siblings.handles.len div 2]
    var replacement = RenderList()
    discard replacement.addRoot(Fig(kind: nkRectangle))
    let replacementTime = medianNanoseconds(
      benchmarkCase.iterations,
      proc() =
        current = siblings.fragments.replaceFragment(current, replacement)
        benchmarkSink = benchmarkSink xor current.fragmentId(),
    )
    reportPopulationOperation(
      "replace one fragment slot", benchmarkCase.viewCount, replacementTime
    )

  proc makeNestedFragmentChain(depth: int): RenderFragments =
    result = newRenderFragments()
    let root = result.addRoot(0.ZLevel, Fig(kind: nkRectangle))
    var parent = result.nodeCursor(0.ZLevel, root)
    for _ in 0 ..< depth:
      var contents = RenderList()
      discard contents.addRoot(Fig(kind: nkRectangle))
      let handle = result.attachChildFragment(parent, 0, move contents)
      parent = result.fragmentRoots(handle)[0]

  proc benchmarkNestedMaterialize(depth, iterations: int) =
    let fragments = makeNestedFragmentChain(depth)
    let elapsed = medianNanoseconds(
      iterations,
      proc() =
        let renders = fragments.materialize()
        benchmarkSink = benchmarkSink xor renders.len(DefaultDrawLevel).uint64,
    )
    report("materialize/nested slots", depth, elapsed)

  proc makeFragmentSiblings(
      fragmentCount: int
  ): tuple[
    fragments: RenderFragments, parent: RenderCursor, handles: seq[RenderFragmentHandle]
  ] =
    result.fragments = newRenderFragments()
    let root = result.fragments.addRoot(0.ZLevel, Fig(kind: nkRectangle))
    result.parent = result.fragments.nodeCursor(0.ZLevel, root)
    result.handles = newSeqOfCap[RenderFragmentHandle](fragmentCount)
    for index in 0 ..< fragmentCount:
      result.handles.add result.fragments.attachChildFragment(
        result.parent, index.Natural, RenderList()
      )

  proc benchmarkSingleMoveReorder(fragmentCount, iterations: int) =
    let siblings = makeFragmentSiblings(fragmentCount)
    let
      fragments = siblings.fragments
      parent = siblings.parent
      handles = siblings.handles

    let elapsed = medianNanoseconds(
      iterations,
      proc() =
        for index in countdown(fragmentCount - 1, 0):
          discard fragments.moveFragment(
            handles[index], parent, (fragmentCount - 1 - index).Natural
          )
        for index in 0 ..< fragmentCount:
          discard fragments.moveFragment(handles[index], parent, index.Natural)
        benchmarkSink = benchmarkSink xor handles[0].fragmentId(),
    )
    let label = "single-move full reorder"
    echo &"{label:<28} {fragmentCount:>6} slots  " &
      &"{elapsed / 1_000_000.0:>11.2f} ms/pass " &
      &"{elapsed / (fragmentCount * 2).float:>9.2f} ns/move"

  proc benchmarkBulkReorder(fragmentCount, iterations: int) =
    let siblings = makeFragmentSiblings(fragmentCount)
    var reversed = siblings.handles
    reversed.reverse()

    let elapsed = medianNanoseconds(
      iterations,
      proc() =
        siblings.fragments.reorderChildFragments(siblings.parent, reversed)
        siblings.fragments.reorderChildFragments(siblings.parent, siblings.handles)
        benchmarkSink = benchmarkSink xor siblings.handles[0].fragmentId(),
    )
    let label = "bulk full reorder"
    echo &"{label:<28} {fragmentCount:>6} slots  " &
      &"{elapsed / 1_000_000.0:>11.2f} ms/pass " &
      &"{elapsed / (fragmentCount * 2).float:>9.2f} ns/slot"

echo "Incremental render fragment diagnostic benchmark"
echo "Fig size: ", sizeof(Fig), " bytes; median of ", SampleCount, " samples"
for benchmarkCase in BenchmarkCases:
  benchmarkMonolithic(benchmarkCase)
  when declared(RenderScene):
    benchmarkScene(benchmarkCase)

when declared(RenderScene):
  echo "\nRenderScene replacement topology"
  benchmarkSceneReplacement(10_000, 1, 10)
  benchmarkSceneReplacement(10_000, 32, 10)

  echo "\nFragment density and nesting"
  for benchmarkCase in BenchmarkCases:
    benchmarkFragmentDensity(benchmarkCase)
  benchmarkNestedMaterialize(100, 1_000)
  benchmarkNestedMaterialize(1_000, 100)
  benchmarkNestedMaterialize(5_000, 20)

  echo "\nFragment sibling reorder scaling"
  benchmarkSingleMoveReorder(100, 100)
  benchmarkSingleMoveReorder(1_000, 10)
  benchmarkSingleMoveReorder(5_000, 2)
  benchmarkBulkReorder(100, 1_000)
  benchmarkBulkReorder(1_000, 100)
  benchmarkBulkReorder(5_000, 20)

echo "benchmark sink: ", benchmarkSink
