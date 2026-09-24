## Diagnostic memory checkpoints; no machine-dependent RSS threshold.
## Run: nim r tests/benchmark_memory.nim
import std/[strformat, strutils]
import merenda/nimkit
import merenda/nimkit/app/diagnostics
when not defined(useNativeDynlib):
  import merenda/nimkit/drawing/renderscenes

proc report(label: string) =
  let usage = processResourceUsage()
  echo &"{label}: RSS {usage.residentBytes.float / 1048576:.2f} MiB, " &
    &"peak {usage.peakResidentBytes.float / 1048576:.2f} MiB, " &
    &"fds {usage.fileDescriptors}, threads {usage.threads}"

proc measureText() =
  let source = repeat("alpha βeta and some ordinary text\n", 10_000)
  let storage = newTextGapStorage(source)
  echo "text source bytes: ", source.len, "; runes: ", storage.len
  report("gap storage")
  for _ in 0 ..< 100:
    storage.replace(initTextRange(storage.len div 2, 0), "edit")
  report("after edits")

proc measureMarkdown() =
  var views: seq[MarkdownView]
  for count in 1 .. 4:
    let view =
      newMarkdownView(repeat("## Heading\n\nA paragraph with **bold** text.\n\n", 100))
    doAssert view.waitForMarkdownParsing()
    doAssert view.waitForMarkdownLayout()
    discard view.buildRenders()
    views.add view
    report("Markdown tabs " & $count)

when not defined(useNativeDynlib):
  proc measureScenes() =
    let root = newView(frame = rect(0, 0, 1000, 1000))
    for index in 0 ..< 1000:
      root.addSubview(
        newView(frame = rect((index mod 100).float32, (index div 100).float32, 10, 10))
      )
    let scene = root.buildRenderScene()
    var full = scene.newRenderSceneUpdate(0, 0)
    echo "scene views: ",
      scene.viewEntryCount(), "; nodes: ", scene.traversalNodeCount()
    echo "full update array bytes: ", full.estimatedTransferBytes()
    let generation = scene.frameGeneration()
    scene.acknowledgeRenderGeneration(generation)
    root.subviews[0].needsDisplay = true
    discard root.buildRenderScene()
    let update = scene.newRenderSceneUpdate(scene.sceneIdentity(), generation)
    echo "one-view update array bytes: ",
      update.estimatedTransferBytes(),
      "; frames: ",
      update.viewCount(),
      "; captured: ",
      update.capturedViewCount()
    report("retained scene and snapshots")

report("baseline")
measureText()
report("text released")
measureMarkdown()
report("Markdown released")
when not defined(useNativeDynlib):
  measureScenes()
  report("scene released")
