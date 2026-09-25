import std/[assertions, monotimes, os, times, unittest]

import figdraw
import figdraw/windowing/siwinshim as figdrawSiwin
import pkg/pixie except draw
import sigils/[rchannels, weakrefs]

import merenda/nimkit/app/application
import merenda/nimkit/app/backend as nimkitBackend
import merenda/nimkit/app/windows
import merenda/nimkit/foundation/selectors
import merenda/nimkit/foundation/types as nimkitTypes
import merenda/nimkit/drawing
import merenda/nimkit/drawing/renderscenes as retainedScenes
import merenda/nimkit/view/views

type
  RaisingDrawView = ref object of View
  ThreadResourceView = ref object of View
    image: ImageResource

when not defined(useNativeDynlib):
  type ReleaseProbe = object
    started, proceed, completed: RChan[bool]
    armed: bool
    framesFinished: bool

  proc `=destroy`(probe: ReleaseProbe) =
    if probe.armed:
      doAssert probe.framesFinished, "renderer destroyed before finishing its frames"
      probe.completed.send(true)
    `=destroy`(probe.started)
    `=destroy`(probe.proceed)
    `=destroy`(probe.completed)

  type DelayedReleaseContext = ref object of BackendContext
    probe: ReleaseProbe

  method kind(context: DelayedReleaseContext): RendererBackendKind =
    PreferredBackendKind

  method finishPendingFrames(context: DelayedReleaseContext) =
    context.probe.started.send(true)
    var allowed: bool
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while not context.probe.proceed.tryRecv(allowed) and getMonoTime() < deadline:
      sleep(1)
    doAssert allowed, "renderer cleanup was not allowed to finish"
    context.probe.framesFinished = true

  proc installReleaseProbe(
      host: nimkitBackend.HostWindow, started, proceed, completed: RChan[bool]
  ) =
    let context = DelayedReleaseContext()
    context.probe.started = started
    context.probe.proceed = proceed
    context.probe.completed = completed
    context.probe.armed = true
    host.rendererOrNil().ctx = context

  proc checkRendererRelease(stopRuntime: bool) =
    var runtime = nimkitBackend.newThreadRendererRuntime()
    let started = newRChan[bool](1)
    let proceed = newRChan[bool](1)
    let completed = newRChan[bool](1)
    var host: nimkitBackend.HostWindow
    runtime.start()
    defer:
      discard proceed.trySend(true)
      runtime.stop()
      runtime.join()
      if not host.isNil:
        host.close()
    host = nimkitBackend.createHostWindow(
      nimkitTypes.rect(20, 20, 80, 60),
      "Renderer release order",
      nimkitBackend.HostWindowCallbacks(),
    )
    host.installReleaseProbe(started, proceed, completed)
    let client = host.attachThreadRenderer(runtime.client, nimkitTypes.initSize(80, 60))
    require not client.isNil
    if stopRuntime:
      runtime.stop()
    else:
      host.detachThreadRenderer(runtime.client, client)

    let deadline = getMonoTime() + initDuration(seconds = 60)
    var cleanupStarted: bool
    while not started.tryRecv(cleanupStarted) and getMonoTime() < deadline:
      discard nimkitBackend.pollNativeEvents()
      sleep(1)
    require cleanupStarted
    check not runtime.client.hasFinished()
    var event: nimkitBackend.ThreadHostEvent
    check not client.pollEvent(event)
    check host.nativeWindowOrNil().opened()
    proceed.send(true)
    var released: bool
    while not released and getMonoTime() < deadline:
      if client.pollEvent(event):
        released = event.kind == nimkitBackend.theRenderTargetReleased
      discard nimkitBackend.pollNativeEvents()
      if not released:
        sleep(1)
    require released
    var cleanupCompleted: bool
    check completed.tryRecv(cleanupCompleted)
    check cleanupCompleted
    check host.nativeWindowOrNil().opened()
    host.close()
    check not host.nativeWindowOrNil().opened()

protocol RaisingDrawing of ViewDrawingProtocol:
  method draw(view: RaisingDrawView, context: DrawContext) =
    discard view
    discard context
    raise newException(ValueError, "intentional drawing failure")

protocol ThreadResourceDrawing of ViewDrawingProtocol:
  method draw(view: ThreadResourceView, context: DrawContext) =
    discard context.addImage(nimkitTypes.rect(2, 3, 12, 8), view.image)

proc newRaisingDrawView(frame: nimkitTypes.Rect): RaisingDrawView =
  result = RaisingDrawView()
  initViewFields(result, frame)
  discard result.withProtocol(RaisingDrawing)

proc newThreadResourceView(
    frame: nimkitTypes.Rect, image: ImageResource
): ThreadResourceView =
  result = ThreadResourceView(image: image)
  initViewFields(result, frame)
  discard result.withProtocol(ThreadResourceDrawing)

proc waitForRendererThread(client: nimkitBackend.ThreadRendererClient): int =
  let deadline = getMonoTime() + initDuration(seconds = 60)
  while getMonoTime() < deadline:
    result = client.rendererThreadId()
    if result >= 0:
      return
    sleep(1)
  return -1

proc newRectangleRenders(): Renders =
  result = newRenders()
  discard result.addRoot(
    Fig(kind: nkRectangle, screenBox: figdraw.rect(0.0, 0.0, 40.0, 20.0))
  )

proc waitForRenderedFrame(
    host: nimkitBackend.HostWindow,
    client: nimkitBackend.ThreadHostClient,
    renderId: uint64,
): bool =
  let deadline = getMonoTime() + initDuration(seconds = 60)
  while getMonoTime() < deadline:
    discard nimkitBackend.pollNativeEvents()
    host.pump()
    var event: nimkitBackend.ThreadHostEvent
    while client.pollEvent(event):
      if event.kind == nimkitBackend.theRendered and event.renderId == renderId:
        client.acknowledgeRender(event.renderId)
        return true
    sleep(1)

suite "NimKit threading":
  test "dedicated renderer support follows the active FigDraw build":
    when defined(useNativeDynlib):
      check not nimkitBackend.dedicatedRendererSupported()
    else:
      check nimkitBackend.dedicatedRendererSupported() == (
        not runtimeForceOpenGlRequested() and
        figdrawSiwin.backendSupportsDedicatedRenderThread(PreferredBackendKind)
      )

  test "forced OpenGL keeps automatic rendering on the main thread":
    when not defined(useNativeDynlib) and UseOpenGlFallback:
      let
        existed = existsEnv("FIGDRAW_FORCE_OPENGL")
        previous = getEnv("FIGDRAW_FORCE_OPENGL")
      defer:
        if existed:
          putEnv("FIGDRAW_FORCE_OPENGL", previous)
        else:
          delEnv("FIGDRAW_FORCE_OPENGL")
      putEnv("FIGDRAW_FORCE_OPENGL", "1")
      check not nimkitBackend.dedicatedRendererSupported()
    else:
      skip()

  test "dedicated render runtime owns a different thread":
    let primaryThread = getThreadId()
    var runtime = nimkitBackend.newThreadRendererRuntime()
    runtime.start()
    defer:
      runtime.stop()
      runtime.join()

    let renderThread = runtime.client.waitForRendererThread()
    check runtime.client.isRunning()
    check renderThread >= 0
    check renderThread != primaryThread

  test "render target release is acknowledged after renderer destruction":
    when not defined(useNativeDynlib):
      if nimkitBackend.dedicatedRendererSupported():
        checkRendererRelease(stopRuntime = false)
      else:
        skip()
    else:
      skip()

  test "stopping the runtime waits for renderer destruction":
    when not defined(useNativeDynlib):
      if nimkitBackend.dedicatedRendererSupported():
        checkRendererRelease(stopRuntime = true)
      else:
        skip()
    else:
      skip()

  test "dedicated renderer draws and releases native frames after transfer":
    if not nimkitBackend.dedicatedRendererSupported():
      skip()
    else:
      var runtime = nimkitBackend.newThreadRendererRuntime()
      var host: nimkitBackend.HostWindow
      runtime.start()
      defer:
        runtime.stop()
        runtime.join()
        if not host.isNil:
          host.close()
      require runtime.client.waitForRendererThread() >= 0
      host = nimkitBackend.createHostWindow(
        nimkitTypes.rect(20, 20, 80, 60),
        "Dedicated renderer frames",
        nimkitBackend.HostWindowCallbacks(),
      )
      host.setVisible(true)
      let client =
        host.attachThreadRenderer(runtime.client, nimkitTypes.initSize(80, 60))
      require not client.isNil
      for frame in 1'u64 .. 3'u64:
        doAssert client.submitRenders(
          newRectangleRenders(), nimkitTypes.initSize(80, 60)
        )
        require host.waitForRenderedFrame(client, frame)
      when not defined(useNativeDynlib):
        let root = newView(frame = nimkitTypes.rect(0, 0, 80, 60))
        for frame in 4'u64 .. 6'u64:
          root.backgroundColor = color(frame.float32 / 6.0'f32, 0.2, 0.6)
          root.needsDisplay = true
          let scene = root.buildRenderScene()
          doAssert client.submitRenderScene(scene, nimkitTypes.initSize(80, 60))
          require host.waitForRenderedFrame(client, frame)
      runtime.stop()
      runtime.join()
      check runtime.client.hasFinished()
      check host.nativeWindowOrNil().opened()
      host.close()
      check not host.nativeWindowOrNil().opened()

  test "render snapshots move through a bounded channel":
    let
      runtime = nimkitBackend.newThreadRenderer()
      host = nimkitBackend.newThreadHostClient(runtime.client)
    doAssert host.submitRenders(
      ensureMove newRectangleRenders(), nimkitTypes.initSize(40.0, 20.0)
    )

    var snapshot: nimkitBackend.ThreadRenderSnapshot
    require host.channels.renders.tryRecv(snapshot)
    check snapshot.logicalSize == nimkitTypes.initSize(40.0, 20.0)
    check snapshot.renders.len(0.ZLevel) == 1

    for width in [50.0, 60.0, 70.0]:
      doAssert host.submitRenders(
        ensureMove newRenders(), nimkitTypes.initSize(width, 20.0)
      )
    var newer, newest: nimkitBackend.ThreadRenderSnapshot
    require host.channels.renders.tryRecv(newer)
    require host.channels.renders.tryRecv(newest)
    check newer.logicalSize == nimkitTypes.initSize(60.0, 20.0)
    check newest.logicalSize == nimkitTypes.initSize(70.0, 20.0)

    for width in [80.0, 90.0, 100.0]:
      doAssert host.submitRenders(
        ensureMove newRenders(), nimkitTypes.initSize(width, 20.0)
      )
    var latest: nimkitBackend.ThreadRenderSnapshot
    require host.channels.pollLatestRender(latest)
    check latest.logicalSize == nimkitTypes.initSize(100.0, 20.0)
    check not host.channels.renders.tryRecv(latest)

  test "snapshot replacement and channel teardown release render references":
    let first = newRectangleRenders()
    let second = newRectangleRenders()
    let third = newRectangleRenders()
    check first.unsafeGcCount() == 1
    block:
      let runtime = nimkitBackend.newThreadRenderer()
      let host = nimkitBackend.newThreadHostClient(runtime.client)
      # No worker runs here: aliases let this test observe ownership after
      # replacement, receive, and final-channel teardown on the same thread.
      doAssert host.submitRenders(first, nimkitTypes.initSize(40, 20))
      doAssert host.submitRenders(second, nimkitTypes.initSize(40, 20))
      doAssert host.submitRenders(third, nimkitTypes.initSize(40, 20))
      check first.unsafeGcCount() == 1
      check second.unsafeGcCount() == 2
      check third.unsafeGcCount() == 2
      var snapshot: nimkitBackend.ThreadRenderSnapshot
      require host.channels.renders.tryRecv(snapshot)
      check snapshot.renders == second
      require host.channels.renders.tryRecv(snapshot)
      check snapshot.renders == third
      check second.unsafeGcCount() == 1
      snapshot = default(nimkitBackend.ThreadRenderSnapshot)
      check third.unsafeGcCount() == 1
      doAssert host.submitRenders(first, nimkitTypes.initSize(40, 20))
      doAssert host.submitRenders(second, nimkitTypes.initSize(40, 20))
    check first.unsafeGcCount() == 1
    check second.unsafeGcCount() == 1
    check third.unsafeGcCount() == 1

  test "fragment updates coalesce cumulatively from the acknowledged generation":
    let
      runtime = nimkitBackend.newThreadRenderer()
      host = nimkitBackend.newThreadHostClient(runtime.client)
      root = newView(frame = nimkitTypes.rect(0, 0, 180, 100))
      first = newView(frame = nimkitTypes.rect(5, 5, 50, 30))
      second = newView(frame = nimkitTypes.rect(60, 5, 50, 30))
      logicalSize = nimkitTypes.initSize(180.0, 100.0)
    root.addSubview(first)
    root.addSubview(second)

    let scene = root.buildRenderScene()
    doAssert host.submitRenderScene(scene, logicalSize)
    var initial: nimkitBackend.ThreadRenderSnapshot
    require host.channels.renders.tryRecv(initial)
    check initial.usesFragments
    check initial.targetGeneration == 1
    check retainedScenes.fullSnapshot(initial.sceneUpdate)
    check retainedScenes.capturedViewCount(initial.sceneUpdate) == 3
    check initial.status(1, 0, 0, 0) == nimkitBackend.trssAccepted
    check initial.status(2, 0, 0, 0) == nimkitBackend.trssStaleTarget
    check initial.status(1, initial.renderId, 0, 0) == nimkitBackend.trssStaleRender

    let replica = retainedScenes.newRenderSceneReplica()
    var initialUpdate = move initial.sceneUpdate
    retainedScenes.apply(replica, initialUpdate)
    host.acknowledgeRender(initial.renderId)
    let acknowledgedGeneration = scene.frameGeneration()

    first.backgroundColor = color(0.8, 0.2, 0.1)
    first.needsDisplay = true
    discard root.buildRenderScene()
    doAssert host.submitRenderScene(scene, logicalSize)

    second.backgroundColor = color(0.1, 0.7, 0.3)
    second.needsDisplay = true
    discard root.buildRenderScene()
    doAssert host.submitRenderScene(scene, logicalSize)

    var latest: nimkitBackend.ThreadRenderSnapshot
    require host.channels.pollLatestRender(latest)
    check latest.usesFragments
    check not retainedScenes.fullSnapshot(latest.sceneUpdate)
    check retainedScenes.baseGeneration(latest.sceneUpdate) == acknowledgedGeneration
    check retainedScenes.capturedViewCount(latest.sceneUpdate) == 2
    check latest.status(1, initial.renderId, retainedScenes.sceneIdentity(scene), 0) ==
      nimkitBackend.trssSceneGap
    check not host.channels.renders.tryRecv(latest)

    var latestUpdate = move latest.sceneUpdate
    check retainedScenes.canApply(
      latestUpdate, retainedScenes.sceneIdentity(scene), acknowledgedGeneration
    )
    retainedScenes.apply(replica, latestUpdate)
    check replica.materialize().len(0.ZLevel) == scene.materialize().len(0.ZLevel)
    host.acknowledgeRender(latest.renderId)

    let replacement = newView(frame = nimkitTypes.rect(0, 0, 180, 100))
    let replacementScene = replacement.buildRenderScene()
    doAssert host.submitRenderScene(replacementScene, logicalSize)
    var barrier: nimkitBackend.ThreadRenderSnapshot
    require host.channels.pollLatestRender(barrier)
    check retainedScenes.fullSnapshot(barrier.sceneUpdate)

    host.rejectRenderUpdate(barrier.renderId)
    doAssert host.submitRenderScene(replacementScene, logicalSize)
    var recovery: nimkitBackend.ThreadRenderSnapshot
    require host.channels.pollLatestRender(recovery)
    check retainedScenes.fullSnapshot(recovery.sceneUpdate)

  test "application loop stays on the platform thread when rendering is direct":
    let
      primaryThread = getThreadId()
      app = newApplication("Threading Test")
    app.renderExecutionMode = nimkitBackend.remMainThread

    app.run()

    check app.applicationThreadId() == primaryThread
    check app.rendererThreadId() == -1
    check not app.isThreaded()
    check not app.isRunning()

  test "application loop releases native renderer after an exception":
    if not nimkitBackend.dedicatedRendererSupported() and not compileOption("mm", "orc"):
      skip()
    else:
      let
        app = newApplication("Threading Exception Test")
        window = newWindow(
          "Threading Exception Test", frame = nimkitTypes.rect(80, 80, 120, 80)
        )
        root = newRaisingDrawView(nimkitTypes.rect(0, 0, 120, 80))
      app.renderExecutionMode =
        if nimkitBackend.dedicatedRendererSupported():
          nimkitBackend.remDedicatedThread
        else:
          nimkitBackend.remAutomatic
      window.setContentView(root)
      app.addWindow(window)
      window.orderFront()

      var raised = false
      try:
        app.run()
      except ValueError as error:
        check error.msg == "intentional drawing failure"
        raised = true
      except OSError:
        when defined(linux) or defined(bsd):
          # Headless CI can fail during native-window creation before drawing.
          raised = true
        else:
          raise
      finally:
        window.close()

      check raised
      check app.rendererThreadId() == -1
      check not app.isThreaded()
      check not app.isRunning()

  test "render snapshots exclude app-thread managed resource handles":
    clearImageCache()
    let
      runtime = nimkitBackend.newThreadRenderer()
      host = nimkitBackend.newThreadHostClient(runtime.client)
      pixels = pixie.newImage(3, 2)
      image = newImageResource(pixels)
    var manifest = initRenderResourceManifest()
    manifest.addImage(image)
    doAssert host.submitRenders(
      ensureMove newRenders(), nimkitTypes.initSize(30.0, 20.0), manifest
    )
    manifest = nil
    check hasImage(image.imageId())
    var snapshot: nimkitBackend.ThreadRenderSnapshot
    require host.channels.renders.tryRecv(snapshot)
    check snapshot.renderId > 0
    check snapshot.logicalSize == nimkitTypes.initSize(30.0, 20.0)
    host.acknowledgeRender(snapshot.renderId)
    check hasImage(image.imageId())
    host.clearRenderResources()
    check not hasImage(image.imageId())

  test "latest render acknowledgement advances managed resource leases":
    clearImageCache()
    let
      runtime = nimkitBackend.newThreadRenderer()
      host = nimkitBackend.newThreadHostClient(runtime.client)
      first = newImageResource(pixie.newImage(2, 2))
      second = newImageResource(pixie.newImage(3, 3))
    var firstManifest = initRenderResourceManifest()
    firstManifest.addImage(first)
    doAssert host.submitRenders(
      ensureMove newRenders(), nimkitTypes.initSize(30.0, 20.0), firstManifest
    )
    firstManifest = nil

    var secondManifest = initRenderResourceManifest()
    secondManifest.addImage(second)
    doAssert host.submitRenders(
      ensureMove newRenders(), nimkitTypes.initSize(30.0, 20.0), secondManifest
    )
    secondManifest = nil
    check hasImage(first.imageId())
    check hasImage(second.imageId())

    var latest: nimkitBackend.ThreadRenderSnapshot
    require host.channels.pollLatestRender(latest)
    host.acknowledgeRender(latest.renderId)
    check not hasImage(first.imageId())
    check hasImage(second.imageId())
    host.clearRenderResources()
    check not hasImage(second.imageId())

  test "fragment acknowledgements release the originating scene resources":
    clearImageCache()
    let
      runtime = nimkitBackend.newThreadRenderer()
      host = nimkitBackend.newThreadHostClient(runtime.client)
      first = newImageResource(pixie.newImage(2, 2))
      second = newImageResource(pixie.newImage(3, 3))
      view = newThreadResourceView(nimkitTypes.rect(0, 0, 40, 30), first)
      logicalSize = nimkitTypes.initSize(40.0, 30.0)
    var scene = view.buildRenderScene()

    doAssert host.submitRenderScene(scene, logicalSize)
    var initial: nimkitBackend.ThreadRenderSnapshot
    require host.channels.pollLatestRender(initial)
    host.acknowledgeRender(initial.renderId)
    check hasImage(first.imageId())

    view.image = second
    view.needsDisplay = true
    discard view.buildRenderScene()
    check scene.retiredResourceCount() == 1
    doAssert host.submitRenderScene(scene, logicalSize)
    var replacement: nimkitBackend.ThreadRenderSnapshot
    require host.channels.pollLatestRender(replacement)
    check hasImage(first.imageId())
    check hasImage(second.imageId())

    host.acknowledgeRender(replacement.renderId)
    check scene.retiredResourceCount() == 0
    check not hasImage(first.imageId())
    check hasImage(second.imageId())
    host.clearRenderResources()
    view.invalidateRenderCache()
    scene = nil
    clearImageCache()
