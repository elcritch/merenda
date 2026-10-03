## Exercise Kosmo's actual Moe LSP client and its TCP child-process lifecycle.
import
  std/[
    atomics, json, monotimes, nativesockets, net, options, os, osproc, streams,
    strutils, tempfiles, times, typedthreads, unittest,
  ]

import sigils/threads
import sigils/rpcs/json/jrFraming
import merenda/kosmo/[cli, moe]

type TcpLspFixture = object
  listener: SocketHandle
  expectedUri, expectedText: string
  initialized, opened, disconnected, finished, stop: Atomic[bool]
  failure: string

proc serveLsp(state: ptr TcpLspFixture) {.thread.} =
  let listener = newSocket(state.listener, buffered = false)
  var client: Socket
  try:
    var parser = initJsonRpcFrameParser()
    var buffer: array[8192, char]
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while not state.stop.load() and getMonoTime() < deadline:
      var readable =
        @[
          if client.isNil:
            listener.getFd()
          else:
            client.getFd()
        ]
      if selectRead(readable, 20) > 0:
        if client.isNil:
          listener.accept(client)
        else:
          let count = client.recv(addr buffer[0], buffer.len)
          if count <= 0:
            state.disconnected.store(true)
            break
          parser.add(buffer.toOpenArray(0, count - 1).join())
          var frame = parser.nextFrame()
          while frame.isSome():
            let message = parseJson(frame.get())
            let methodName = message{"method"}.getStr()
            var response: JsonNode
            case methodName
            of "initialize":
              response =
                %*{
                  "jsonrpc": "2.0",
                  "id": message["id"],
                  "result": {
                    "capabilities": {
                      "textDocumentSync": 1,
                      "experimental": {"padding": repeat('x', 32768)},
                    }
                  },
                }
              state.initialized.store(true)
            of "textDocument/didOpen":
              let document = message["params"]["textDocument"]
              if document["uri"].getStr() != state.expectedUri or
                  document["text"].getStr() != state.expectedText:
                raise newException(
                  ValueError,
                  "TCP LSP didOpen mismatch: URI " & document["uri"].getStr() &
                    " expected " & state.expectedUri & "; text length " &
                    $document["text"].getStr().len & " expected " &
                    $state.expectedText.len,
                )
              state.opened.store(true)
            of "shutdown":
              response = %*{"jsonrpc": "2.0", "id": message["id"], "result": nil}
            else:
              if message.hasKey("id"):
                response = %*{"jsonrpc": "2.0", "id": message["id"], "result": nil}
            if not response.isNil:
              let bytes = frameJsonRpcMessage($response)
              # Split framing headers and send more than one transport buffer.
              var offset = 0
              while offset < bytes.len:
                let next = min(offset + 512, bytes.len)
                client.send(bytes[offset ..< next])
                offset = next
            frame = parser.nextFrame()
  except CatchableError as error:
    state.failure = error.msg
  finally:
    if not client.isNil:
      client.close()
    state.finished.store(true)

proc waitForExit(process: Process, timeout = initDuration(seconds = 10)): int =
  let deadline = getMonoTime() + timeout
  result = process.peekExitCode()
  while result == -1 and getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    sleep(5)
    result = process.peekExitCode()

proc stopProcess(process: Process) =
  if process.peekExitCode() == -1:
    process.kill()
  discard process.waitForExit()
  process.close()

proc acceptClient(listener: Socket): Socket =
  let deadline = getMonoTime() + initDuration(seconds = 10)
  while result.isNil and getMonoTime() < deadline:
    var readable = @[listener.getFd()]
    if selectRead(readable, 0) > 0:
      listener.accept(result)
    else:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(5)

suite "Kosmo TCP LSP integration":
  test "initializes Moe over TCP opens a document and shuts down the connection":
    let
      root = createTempDir("merenda-kosmo-tcp-client-", "")
      path = root / "main.nim"
      text = "const answer* = 42\n# " & repeat('a', 32768)
      listener = newSocket(buffered = false)
      previousLauncher = kosmoLspLauncherExecutable
    listener.bindAddr(Port(0), "127.0.0.1")
    listener.listen()
    writeFile(path, text)
    var state = TcpLspFixture(
      listener: listener.getFd(), expectedUri: "file://" & path, expectedText: text
    )
    var serverThread: Thread[ptr TcpLspFixture]
    var serverJoined: bool
    createThread(serverThread, serveLsp, addr state)
    kosmoLspLauncherExecutable = getAppFilename()
    var editor: KosmoEditor
    defer:
      if not editor.isNil:
        editor.close()
      state.stop.store(true)
      if not serverJoined:
        joinThread(serverThread)
      listener.close()
      kosmoLspLauncherExecutable = previousLauncher
      removeDir(root)
    editor = newKosmoEditor(
      workingDirectory = root,
      nimLspCommand = "tcp://127.0.0.1:" & $listener.getLocalAddr()[1],
    )
    require editor.openFile(path).loaded
    var render = newRenderBuffer(48, 12)
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while not state.opened.load() and not state.finished.load() and
        getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      editor.render(render)
      sleep(5)
    check state.initialized.load()
    check state.opened.load()
    editor.close()
    let closeDeadline = getMonoTime() + initDuration(seconds = 10)
    while not state.disconnected.load() and not state.finished.load() and
        getMonoTime() < closeDeadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(5)
    check state.disconnected.load()
    state.stop.store(true)
    joinThread(serverThread)
    serverJoined = true
    check state.failure == ""

  test "bridge exits when either the peer or its stdin closes":
    for peerCloses in [true, false]:
      let listener = newSocket(buffered = false)
      listener.bindAddr(Port(0), "127.0.0.1")
      listener.listen()
      defer:
        listener.close()
      let process = startProcess(
        getAppFilename(),
        args = kosmoLspChildArguments("tcp://127.0.0.1:" & $listener.getLocalAddr()[1]),
        options = {},
      )
      defer:
        process.stopProcess()
      let client = listener.acceptClient()
      require not client.isNil
      var peerClosed: bool
      defer:
        if not peerClosed:
          client.close()
      if peerCloses:
        client.close()
        peerClosed = true
      else:
        process.inputStream().close()
      require process.waitForExit() == 0
      check process.outputStream().readAll().len == 0
      check process.errorStream().readAll().len == 0

  test "bridge reports connection failure on stderr without protocol output":
    let listener = newSocket()
    listener.bindAddr(Port(0), "127.0.0.1")
    let address = "tcp://127.0.0.1:" & $listener.getLocalAddr()[1]
    # Keep the port reserved without listening, so the connection is refused.
    defer:
      listener.close()
    let process = startProcess(
      getAppFilename(), args = kosmoLspChildArguments(address), options = {}
    )
    defer:
      process.stopProcess()
    require process.waitForExit() == 1
    check process.outputStream().readAll().len == 0
    check process.errorStream().readAll().contains("Kosmo TCP LSP connection failed")
