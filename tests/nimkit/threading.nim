import std/unittest

import figdraw
import pkg/pixie
import threading/channels

import merenda/nimkit/app/application
import merenda/nimkit/app/backend as nimkitBackend
import merenda/nimkit/foundation/types as nimkitTypes
import merenda/nimkit/drawing

suite "NimKit threading":
  test "render snapshots cross a bounded channel as independent values":
    let
      runtime = nimkitBackend.newThreadRenderer()
      host = nimkitBackend.newThreadHostClient(runtime.client)
      renders = newRenders()
    discard renders.addRoot(
      Fig(kind: nkRectangle, screenBox: figdraw.rect(0.0, 0.0, 40.0, 20.0))
    )
    host.requestCreation(
      runtime.client, nimkitTypes.rect(0.0, 0.0, 40.0, 20.0), "Snapshot Test"
    )

    check host.submitRenders(renders, nimkitTypes.initSize(40.0, 20.0))

    var snapshot: nimkitBackend.ThreadRenderSnapshot
    require host.channels.renders.tryRecv(snapshot)
    check snapshot.renders != renders
    check snapshot.logicalSize == nimkitTypes.initSize(40.0, 20.0)
    check snapshot.renders.len(0.ZLevel) == 1

    check host.submitRenders(renders, nimkitTypes.initSize(50.0, 20.0))
    check host.submitRenders(renders, nimkitTypes.initSize(60.0, 20.0))
    check host.submitRenders(renders, nimkitTypes.initSize(70.0, 20.0))
    var newer, newest: nimkitBackend.ThreadRenderSnapshot
    require host.channels.renders.tryRecv(newer)
    require host.channels.renders.tryRecv(newest)
    check newer.logicalSize == nimkitTypes.initSize(60.0, 20.0)
    check newest.logicalSize == nimkitTypes.initSize(70.0, 20.0)

    check host.submitRenders(renders, nimkitTypes.initSize(80.0, 20.0))
    check host.submitRenders(renders, nimkitTypes.initSize(90.0, 20.0))
    check host.submitRenders(renders, nimkitTypes.initSize(100.0, 20.0))
    var latest: nimkitBackend.ThreadRenderSnapshot
    require host.channels.pollLatestRender(latest)
    check latest.logicalSize == nimkitTypes.initSize(100.0, 20.0)
    check not host.channels.renders.tryRecv(latest)

  test "application loop runs on a selector thread and renderer stays primary":
    let
      primaryThread = getThreadId()
      app = newApplication("Threading Test")

    app.run()

    check app.applicationThreadId() != primaryThread
    check app.rendererThreadId() == primaryThread
    check not app.isThreaded()
    check not app.isRunning()

  test "render snapshots carry value-only managed image sources":
    let
      runtime = nimkitBackend.newThreadRenderer()
      host = nimkitBackend.newThreadHostClient(runtime.client)
      renders = newRenders()
      pixels = pixie.newImage(3, 2)
      image = newImageResource(pixels)
    var manifest = initRenderResourceManifest()
    manifest.addImage(image)
    host.requestCreation(
      runtime.client, nimkitTypes.rect(0.0, 0.0, 30.0, 20.0), "Resources"
    )

    check host.submitRenders(
      renders, nimkitTypes.initSize(30.0, 20.0), manifest.freeze()
    )
    var snapshot: nimkitBackend.ThreadRenderSnapshot
    require host.channels.renders.tryRecv(snapshot)
    require snapshot.resources.images.len == 1
    check snapshot.resources.images[0].id == image.imageId()
    check snapshot.resources.images[0].width == 3
    check snapshot.resources.images[0].height == 2
    check snapshot.resources.images[0].data.len == 6
