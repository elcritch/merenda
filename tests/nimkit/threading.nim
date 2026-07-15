import std/[assertions, os, unittest]

import figdraw
import figdraw/windowing/siwinshim as figdrawSiwin
import pkg/pixie except draw
import threading/channels

import merenda/nimkit/app/application
import merenda/nimkit/app/backend as nimkitBackend
import merenda/nimkit/app/windows
import merenda/nimkit/foundation/selectors
import merenda/nimkit/foundation/types as nimkitTypes
import merenda/nimkit/drawing
import merenda/nimkit/view/views

type RaisingDrawView = ref object of View

protocol RaisingDrawing of ViewDrawingProtocol:
  method draw(view: RaisingDrawView, context: DrawContext) =
    discard view
    discard context
    raise newException(ValueError, "intentional drawing failure")

proc newRaisingDrawView(frame: nimkitTypes.Rect): RaisingDrawView =
  result = RaisingDrawView()
  initViewFields(result, frame)
  discard result.withProtocol(RaisingDrawing)

proc waitForRendererThread(client: nimkitBackend.ThreadRendererClient): int =
  for _ in 0 ..< 100:
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

  test "application loop joins dedicated renderer after an exception":
    if not nimkitBackend.dedicatedRendererSupported():
      skip()
    else:
      let
        app = newApplication("Threading Exception Test")
        window = newWindow(
          "Threading Exception Test", frame = nimkitTypes.rect(80, 80, 120, 80)
        )
        root = newRaisingDrawView(nimkitTypes.rect(0, 0, 120, 80))
      app.renderExecutionMode = nimkitBackend.remDedicatedThread
      window.setContentView(root)
      app.addWindow(window)
      window.orderFront()

      var raised = false
      try:
        app.run()
      except ValueError:
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
