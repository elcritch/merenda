import std/[assertions, unittest]

import figdraw
import pkg/pixie
import threading/channels

import merenda/nimkit/app/application
import merenda/nimkit/app/backend as nimkitBackend
import merenda/nimkit/foundation/events as nimkitEvents
import merenda/nimkit/foundation/types as nimkitTypes
import merenda/nimkit/drawing

const ThreadHostEventBurst = 1_024

proc postTextInputBurst(queue: nimkitBackend.ThreadHostEventQueue) {.thread.} =
  for index in 0 ..< ThreadHostEventBurst:
    queue.post(
      nimkitBackend.ThreadHostEvent(kind: nimkitBackend.theTextInput, text: $index)
    )

proc newRectangleRenders(): Renders =
  result = newRenders()
  discard result.addRoot(
    Fig(kind: nkRectangle, screenBox: figdraw.rect(0.0, 0.0, 40.0, 20.0))
  )

suite "NimKit threading":
  test "discrete host events survive a stalled consumer":
    let queue = nimkitBackend.newThreadHostEventQueue()
    var producer: Thread[nimkitBackend.ThreadHostEventQueue]
    createThread(producer, postTextInputBurst, queue)
    joinThread(producer)

    var event: nimkitBackend.ThreadHostEvent
    for index in 0 ..< ThreadHostEventBurst:
      doAssert queue.poll(event)
      check event.kind == nimkitBackend.theTextInput
      check event.text == $index
    check not queue.poll(event)

  test "consecutive mouse moves coalesce without crossing discrete events":
    let queue = nimkitBackend.newThreadHostEventQueue()
    queue.post(
      nimkitBackend.ThreadHostEvent(
        kind: nimkitBackend.theMouseMove,
        mouseEvent: nimkitEvents.MouseEvent(timestamp: 1.0),
      )
    )
    queue.post(
      nimkitBackend.ThreadHostEvent(
        kind: nimkitBackend.theMouseMove,
        mouseEvent: nimkitEvents.MouseEvent(timestamp: 2.0),
      )
    )
    queue.post(
      nimkitBackend.ThreadHostEvent(kind: nimkitBackend.theTextInput, text: "barrier")
    )
    queue.post(
      nimkitBackend.ThreadHostEvent(
        kind: nimkitBackend.theMouseMove,
        mouseEvent: nimkitEvents.MouseEvent(timestamp: 3.0),
      )
    )
    queue.post(
      nimkitBackend.ThreadHostEvent(
        kind: nimkitBackend.theMouseMove,
        mouseEvent: nimkitEvents.MouseEvent(timestamp: 4.0),
      )
    )

    var event: nimkitBackend.ThreadHostEvent
    doAssert queue.poll(event)
    check event.kind == nimkitBackend.theMouseMove
    check event.mouseEvent.timestamp == 2.0
    doAssert queue.poll(event)
    check event.kind == nimkitBackend.theTextInput
    check event.text == "barrier"
    doAssert queue.poll(event)
    check event.kind == nimkitBackend.theMouseMove
    check event.mouseEvent.timestamp == 4.0
    check not queue.poll(event)

  test "render snapshots move through a bounded channel":
    let
      runtime = nimkitBackend.newThreadRenderer()
      host = nimkitBackend.newThreadHostClient(runtime.client)
    host.requestCreation(
      runtime.client, nimkitTypes.rect(0.0, 0.0, 40.0, 20.0), "Snapshot Test"
    )

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
      pixels = pixie.newImage(3, 2)
      image = newImageResource(pixels)
    var manifest = initRenderResourceManifest()
    manifest.addImage(image)
    host.requestCreation(
      runtime.client, nimkitTypes.rect(0.0, 0.0, 30.0, 20.0), "Resources"
    )

    doAssert host.submitRenders(
      ensureMove newRenders(),
      nimkitTypes.initSize(30.0, 20.0),
      ensureMove manifest.freeze(),
    )
    var snapshot: nimkitBackend.ThreadRenderSnapshot
    require host.channels.renders.tryRecv(snapshot)
    require snapshot.resources.images.len == 1
    check snapshot.resources.images[0].id == image.imageId()
    check snapshot.resources.images[0].width == 3
    check snapshot.resources.images[0].height == 2
    check snapshot.resources.images[0].data.len == 6
