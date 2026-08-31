import std/unittest

import sigils/threadBase

import merenda/nimkit/app/application
import merenda/nimkit/foundation/mainthreadwork

suite "NimKit application Sigils scheduler":
  test "automatic local scheduler can be disabled before running":
    check not hasLocalSigilThread()
    let app = newApplication("Sigils Opt Out Test")
    app.automaticallyStartsLocalSigilThread = false

    discard app.runForFrames(1)

    check not hasLocalSigilThread()

  test "application frames install a local scheduler by default":
    check not hasLocalSigilThread()
    let app = newApplication("Sigils Default Test")

    discard app.runForFrames(1)

    check hasLocalSigilThread()

  test "application frames preserve an existing local scheduler":
    require hasLocalSigilThread()
    let
      existing = getCurrentSigilThread()
      app = newApplication("Sigils Existing Scheduler Test")

    discard app.runForFrames(1)

    check getCurrentSigilThread() == existing

  test "cooperative work continuations run once per application frame":
    let app = newApplication("Cooperative Work Test")
    var chunkCount = 0
    scheduleMainThreadWork(
      proc(): bool =
        inc chunkCount
        chunkCount < 3
    )

    discard app.runForFrames(1)
    check chunkCount == 1
    check hasPendingMainThreadWork()
    discard app.runForFrames(1)
    check chunkCount == 2
    check hasPendingMainThreadWork()
    discard app.runForFrames(1)
    check chunkCount == 3
    check not hasPendingMainThreadWork()
