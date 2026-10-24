when defined(merenda.devControl) and defined(posix):
  import
    std/[
      base64, json, monotimes, net, nativesockets, os, osproc, tempfiles, times,
      unittest,
    ]
  from std/posix import access, F_OK
  import std/strutils
  import pixie
  import merenda/nimkit/devcontrol/[protocol, transport]
  import ./fixtures/devcontrol
  when defined(macosx):
    import darwin/app_kit/[nsworkspace, nsrunningapplication]
    import darwin/objc/runtime
    proc processIdentifier(
      app: NSRunningApplication
    ): cint {.objc: "processIdentifier".}

    proc frontmostApplication(
      workspace: NSWorkspace
    ): NSRunningApplication {.objc: "frontmostApplication".}

  proc socketExists(path: string): bool =
    access(path.cstring, F_OK) == 0

  proc request(path: string, command: DevCommand, window = ""): JsonNode =
    sendDevRequest(path, DevRequest(id: "test", command: command, window: window))

  proc capture(path, window: string): Image =
    let response = request(path, dcScreenshot, window)
    doAssert response["ok"].getBool(), $response
    result = decodeImage(decode(response["result"]["data"].getStr()))
    doAssert result.width == response["result"]["width"].getInt()
    doAssert result.height == response["result"]["height"].getInt()
    doAssert response["result"]["scale"].getFloat() == result.width.float64 / 320.0
    doAssert response["result"]["renderId"].getBiggestInt() > 0

  suite "Development control native process":
    for execution in ["main", "dedicated"]:
      test "captures fresh pixels and injects input with " & execution & " rendering":
        let directory = createTempDir("mdc-", "", "/tmp")
        setFilePermissions(directory, {fpUserRead, fpUserWrite, fpUserExec})
        let explicitPath = directory / "control.sock"
        when defined(macosx):
          let foreground =
            NSWorkspace.sharedWorkspace().frontmostApplication().processIdentifier()
        let child = startProcess(
          getAppFilename(),
          args = [
            DevControlProbe,
            (if execution == "main": "pid" else: explicitPath),
            execution,
          ],
          options = {poParentStreams},
        )
        let path =
          if execution == "main":
            devSocketPath(child.processID().Positive)
          else:
            explicitPath
        defer:
          if child.running():
            child.terminate()
          discard child.waitForExit(5000)
          if child.running():
            child.kill()
            discard child.waitForExit(5000)
          child.close()
          if socketExists(path):
            removeFile(path)
          removeDir(directory)
        let deadline = getMonoTime() + initDuration(seconds = 60)
        var window: string
        while child.running() and getMonoTime() < deadline:
          if socketExists(path):
            try:
              let response = request(path, dcWindows)
              let windows = response["result"]["windows"]
              if windows.len > 0 and windows[0]["nativeReady"].getBool():
                window = windows[0]["id"].getStr()
                break
            except OSError, IOError:
              discard
          sleep(5)
        require window.len > 0
        when defined(macosx):
          check NSWorkspace.sharedWorkspace().frontmostApplication().processIdentifier() ==
            foreground
        let info = request(path, dcInfo)
        check info["result"]["pid"].getInt() == child.processID()
        check info["result"]["background"].getBool()
        let before = capture(path, window)
        require before.width >= 320
        require before.height >= 240
        let scale = before.width div 320
        check before[300 * scale, 10 * scale].r > 240
        check before[300 * scale, 200 * scale].b > 240
        let click = sendDevRequest(
          path,
          DevRequest(
            id: "click",
            command: dcPointer,
            window: window,
            action: "click",
            x: 50,
            y: 95,
          ),
        )
        check click["ok"].getBool()
        check click["result"]["handled"].getBool()
        let after = capture(path, window)
        check after[300 * scale, 200 * scale].g > 240
        check after[300 * scale, 200 * scale].b < 10
        discard sendDevRequest(
          path,
          DevRequest(
            id: "field",
            command: dcPointer,
            window: window,
            action: "click",
            x: 100,
            y: 48,
          ),
        )
        let text = sendDevRequest(
          path,
          DevRequest(id: "text", command: dcText, window: window, text: " External"),
        )
        check text["ok"].getBool()
        check text["result"]["handled"].getBool()
        let typed = capture(path, window)
        check typed.data != after.data
        let cssFile = directory / "theme.css"
        let notLoaded = request(path, dcThemeReload)
        check notLoaded["error"]["code"].getStr() == "theme_not_loaded"
        writeFile(cssFile, "#dev-theme-probe { background-color: #ff0000; }")
        let loaded = sendDevRequest(
          path, DevRequest(id: "css", command: dcThemeLoad, file: cssFile)
        )
        checkpoint($loaded)
        check loaded["ok"].getBool()
        let redTheme = capture(path, window)
        check redTheme[290 * scale, 35 * scale].r > 240
        check redTheme[290 * scale, 35 * scale].b < 10
        writeFile(cssFile, "#dev-theme-probe { background-color: #0000ff; }")
        check request(path, dcThemeReload)["ok"].getBool()
        let blueTheme = capture(path, window)
        check blueTheme[290 * scale, 35 * scale].b > 240
        check blueTheme[290 * scale, 35 * scale].r < 10
        writeFile(cssFile, "#dev-theme-probe { background-color: invalid-color; }")
        let invalidCss = request(path, dcThemeReload)
        check invalidCss["error"]["code"].getStr() == "invalid_css"
        let retainedTheme = capture(path, window)
        check retainedTheme[290 * scale, 35 * scale].b > 240
        check retainedTheme[290 * scale, 35 * scale].r < 10
        let unknown = request(path, dcScreenshot, "missing")
        check unknown["error"]["code"].getStr() == "window_not_found"
        when defined(macosx):
          check NSWorkspace.sharedWorkspace().frontmostApplication().processIdentifier() ==
            foreground

        discard sendDevRequest(
          path,
          DevRequest(
            id: "second",
            command: dcPointer,
            window: window,
            action: "click",
            x: 160,
            y: 95,
          ),
        )
        let secondDeadline = getMonoTime() + initDuration(seconds = 10)
        var second: string
        while getMonoTime() < secondDeadline:
          for item in request(path, dcWindows)["result"]["windows"]:
            if item["title"].getStr() == "Second Probe" and item["nativeReady"].getBool():
              second = item["id"].getStr()
          if second.len > 0:
            break
          sleep(5)
        require second.len > 0
        discard sendDevRequest(
          path,
          DevRequest(
            id: "popup",
            command: dcPointer,
            window: second,
            action: "click",
            x: 60,
            y: 35,
          ),
        )
        let popupDeadline = getMonoTime() + initDuration(seconds = 10)
        var popupReady = false
        while getMonoTime() < popupDeadline:
          let items = request(path, dcWindows)["result"]["windows"]
          if items.len == 3 and items[2]["nativeReady"].getBool():
            popupReady = true
            break
          sleep(5)
        check popupReady
        when defined(macosx):
          check NSWorkspace.sharedWorkspace().frontmostApplication().processIdentifier() ==
            foreground
        # Dismiss the popup before delivering the fixture's stop action.
        discard sendDevRequest(
          path,
          DevRequest(
            id: "escape", command: dcKey, window: second, action: "down", key: "escape"
          ),
        )
        let stop =
          newSocket(AF_UNIX, SOCK_STREAM, nativesockets.IPPROTO_NONE, buffered = false)
        stop.connectUnix(path)
        stop.send(
          $DevRequest(
            id: "stop",
            command: dcPointer,
            window: window,
            action: "click",
            x: 250,
            y: 95,
          ).rpcRequestJson() & "\n"
        )
        stop.close()
        let exitDeadline = getMonoTime() + initDuration(seconds = 10)
        while child.running() and getMonoTime() < exitDeadline:
          sleep(5)
        require not child.running()
        check child.waitForExit(1000) == 0
        check not socketExists(path)

  suite "Development control socket lifecycle":
    test "refuses occupied paths and removes its own endpoint":
      let directory = createTempDir("mdc-", "", "/tmp")
      setFilePermissions(directory, {fpUserRead, fpUserWrite, fpUserExec})
      let path = directory / "control.sock"
      defer:
        removeDir(directory)
      let server = startDevServer(
        path,
        proc(request: DevRequest, complete: DevCompletion) =
          complete(devSuccess(request.id, %*{"ready": true})),
      )
      require socketExists(path)
      expect OSError:
        discard startDevServer(
          path,
          proc(request: DevRequest, complete: DevCompletion) =
            discard,
        )
      server.close()
      check not socketExists(path)
      server.close()

    test "fragmented requests and partial large writes preserve framing":
      let directory = createTempDir("mdc-", "", "/tmp")
      setFilePermissions(directory, {fpUserRead, fpUserWrite, fpUserExec})
      let path = directory / "control.sock"
      defer:
        removeDir(directory)
      var called = 0
      let payload = "payload-".repeat(128 * 1024)
      let server = startDevServer(
        path,
        proc(request: DevRequest, complete: DevCompletion) =
          inc called
          complete(devSuccess(request.id, %*{"payload": payload})),
      )
      defer:
        server.close()
      let client =
        newSocket(AF_UNIX, SOCK_STREAM, nativesockets.IPPROTO_NONE, buffered = false)
      defer:
        client.close()
      client.connectUnix(path)
      let wire = $DevRequest(id: "split", command: dcInfo).rpcRequestJson() & "\n"
      client.send(wire[0 ..< wire.len div 2])
      server.poll()
      check called == 0
      client.send(wire[wire.len div 2 .. ^1])
      client.getFd().setBlocking(false)
      let deadline = getMonoTime() + initDuration(seconds = 10)
      var response: string
      while getMonoTime() < deadline and '\n' notin response:
        server.poll()
        var handles = @[client.getFd()]
        if selectRead(handles, 0) > 0:
          var chunk = newString(8192)
          let count = client.recv(addr chunk[0], chunk.len)
          if count <= 0:
            break
          chunk.setLen(count)
          response.add chunk
        sleep(1)
      require '\n' in response
      check called == 1
      let decoded = parseJson(response.strip())
      check decoded["id"].getStr() == "split"
      check decoded["result"]["result"]["payload"].getStr() == payload

    test "disconnected clients free connection capacity":
      let directory = createTempDir("mdc-", "", "/tmp")
      setFilePermissions(directory, {fpUserRead, fpUserWrite, fpUserExec})
      let path = directory / "control.sock"
      defer:
        removeDir(directory)
      var called = 0
      let server = startDevServer(
        path,
        proc(request: DevRequest, complete: DevCompletion) =
          inc called
          complete(devSuccess(request.id, %*{"ready": true})),
      )
      defer:
        server.close()
      for index in 0 ..< 8:
        let client =
          newSocket(AF_UNIX, SOCK_STREAM, nativesockets.IPPROTO_NONE, buffered = false)
        client.connectUnix(path)
        client.send($DevRequest(id: $index, command: dcInfo).rpcRequestJson() & "\n")
        let deadline = getMonoTime() + initDuration(seconds = 2)
        while called <= index and getMonoTime() < deadline:
          server.poll()
          sleep(1)
        check called == index + 1
        client.close()
        server.poll()

    test "recursive polling after a client disconnect does not remove a stale index":
      let directory = createTempDir("mdc-", "", "/tmp")
      setFilePermissions(directory, {fpUserRead, fpUserWrite, fpUserExec})
      let path = directory / "control.sock"
      var server: DevServer
      let client =
        newSocket(AF_UNIX, SOCK_STREAM, nativesockets.IPPROTO_NONE, buffered = false)
      defer:
        client.close()
        server.close()
        removeDir(directory)
      var called = false
      server = startDevServer(
        path,
        proc(request: DevRequest, complete: DevCompletion) =
          called = true
          client.close()
          server.poll()
          complete(devSuccess(request.id, %*{"ready": true})),
      )
      client.connectUnix(path)
      client.send($DevRequest(id: "nested", command: dcInfo).rpcRequestJson() & "\n")
      server.poll()
      check called
      server.poll()

    test "a request callback can close its own endpoint":
      let directory = createTempDir("mdc-", "", "/tmp")
      setFilePermissions(directory, {fpUserRead, fpUserWrite, fpUserExec})
      let path = directory / "control.sock"
      var server: DevServer
      let client =
        newSocket(AF_UNIX, SOCK_STREAM, nativesockets.IPPROTO_NONE, buffered = false)
      defer:
        client.close()
        server.close()
        removeDir(directory)
      server = startDevServer(
        path,
        proc(request: DevRequest, complete: DevCompletion) =
          server.close()
          complete(devSuccess(request.id, %*{"ready": true})),
      )
      client.connectUnix(path)
      client.send($DevRequest(id: "close", command: dcInfo).rpcRequestJson() & "\n")
      server.poll()
      server.poll()
      check not socketExists(path)

    test "shutdown preserves an endpoint replaced after startup":
      let directory = createTempDir("mdc-", "", "/tmp")
      setFilePermissions(directory, {fpUserRead, fpUserWrite, fpUserExec})
      let path = directory / "control.sock"
      defer:
        removeDir(directory)
      let server = startDevServer(
        path,
        proc(request: DevRequest, complete: DevCompletion) =
          discard,
      )
      defer:
        server.close()
      moveFile(path, path & ".old")
      writeFile(path, "replacement")
      server.close()
      check readFile(path) == "replacement"

    test "public socket directories are rejected":
      let directory = createTempDir("mdc-", "", "/tmp")
      defer:
        removeDir(directory)
      setFilePermissions(
        directory, {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec}
      )
      expect OSError:
        discard startDevServer(
          directory / "control.sock",
          proc(request: DevRequest, complete: DevCompletion) =
            discard,
        )
