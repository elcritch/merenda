import std/unittest

import sigils/threadBase

import merenda/nimkit/app/application

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
