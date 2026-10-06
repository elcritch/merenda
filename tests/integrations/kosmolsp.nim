## Exercise Kosmo's actual Moe LSP client and its TCP child-process lifecycle.
import
  std/[
    atomics, json, monotimes, nativesockets, net, options, os, osproc, streams,
    strutils, tempfiles, times, typedthreads, unittest,
  ]

import sigils/threads
import sigils/rpcs/json/jrFraming
import merenda/kosmo/[cli, moe]
from moepkg/lsp/worker import pathToFileUri

type
  TcpLspSession = object
    rootUri, documentUri, text: string

  TcpLspFixture = object
    listener: SocketHandle
    sessions: seq[TcpLspSession]
    initialized, opened, disconnected: Atomic[int]
    finished, stop: Atomic[bool]
    failure: string

proc serveLsp(state: ptr TcpLspFixture) {.thread.} =
  let listener = newSocket(state.listener, buffered = false)
  var client: Socket
  var session = 0
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
          parser = initJsonRpcFrameParser()
        else:
          let count = client.recv(addr buffer[0], buffer.len)
          if count <= 0:
            client.close()
            client = nil
            inc session
            state.disconnected.store(session)
            if session == state.sessions.len:
              break
          else:
            parser.add(buffer.toOpenArray(0, count - 1).join())
            var frame = parser.nextFrame()
            while frame.isSome():
              let message = parseJson(frame.get())
              let methodName = message{"method"}.getStr()
              var response: JsonNode
              case methodName
              of "initialize":
                if message["params"]["rootUri"].getStr() !=
                    state.sessions[session].rootUri:
                  raise newException(
                    ValueError,
                    "TCP LSP initialize workspace mismatch: " &
                      message["params"]["rootUri"].getStr() & " expected " &
                      state.sessions[session].rootUri,
                  )
                response =
                  %*{
                    "jsonrpc": "2.0",
                    "id": message["id"],
                    "result": {
                      "capabilities": {
                        "textDocumentSync":
                          {"openClose": true, "change": 1, "save": true},
                        "positionEncoding": "utf-16",
                        "experimental": {"padding": repeat('x', 32768)},
                      },
                      "serverInfo": {"name": "nimdex", "version": "0.1.2"},
                    },
                  }
                state.initialized.store(session + 1)
              of "textDocument/didOpen":
                let document = message["params"]["textDocument"]
                let expected = state.sessions[session]
                if document["uri"].getStr() != expected.documentUri or
                    document["text"].getStr() != expected.text:
                  raise newException(
                    ValueError,
                    "TCP LSP didOpen mismatch: URI " & document["uri"].getStr() &
                      " expected " & expected.documentUri & "; text length " &
                      $document["text"].getStr().len & " expected " & $expected.text.len,
                  )
                state.opened.store(session + 1)
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
  test "reconnects Moe with fresh workspaces and documents on a persistent listener":
    let
      root = expandFilename(createTempDir("merenda-kosmo-tcp-client-", ""))
      listener = newSocket(buffered = false)
      previousLauncher = kosmoLspLauncherExecutable
      previousDirectory = getCurrentDir()
    listener.bindAddr(Port(0), "127.0.0.1")
    listener.listen()
    var state = TcpLspFixture(listener: listener.getFd())
    for session in 0 .. 1:
      let
        directory = root / $session
        path = directory / "main.nim"
        text = "const answer" & $session & "* = 42\n# " & repeat('a', 32768)
      createDir(directory)
      writeFile(path, text)
      state.sessions.add TcpLspSession(
        rootUri: pathToFileUri(directory), documentUri: pathToFileUri(path), text: text
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
    var render = newRenderBuffer(48, 12)
    let deadline = getMonoTime() + initDuration(seconds = 60)
    for session in 0 ..< state.sessions.len:
      let directory = root / $session
      editor = newKosmoEditor(
        workingDirectory = directory,
        nimLspCommand = "tcp://127.0.0.1:" & $listener.getLocalAddr()[1],
      )
      check getCurrentDir() == previousDirectory
      require editor.openFile(directory / "main.nim").loaded
      while state.opened.load() <= session and not state.finished.load() and
          getMonoTime() < deadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        editor.render(render)
        sleep(5)
      if state.finished.load():
        joinThread(serverThread)
        serverJoined = true
        check state.failure == ""
      require state.initialized.load() == session + 1
      require state.opened.load() == session + 1
      editor.close()
      editor = nil
      while state.disconnected.load() <= session and not state.finished.load() and
          getMonoTime() < deadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(5)
      require state.disconnected.load() == session + 1
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
