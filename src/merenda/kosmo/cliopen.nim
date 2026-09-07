## Local command-line request routing for a running Kosmo application.

import std/[algorithm, json, nativesockets, net, os, sets, strutils, sysrand, times]

import sigils/[core, threadChronos, threadProxies, threads]

import ../nimkit/foundation/backgroundworkers

const
  KosmoCliProtocolVersion* = 2
  KosmoCliEndpointEnvironment* = "KOSMO_CLI_ENDPOINT"
  KosmoCliWindowEnvironment* = "KOSMO_CLI_WINDOW"
  KosmoCliMaxPaths* = 64
  KosmoCliMaxDiffBytes* = 8 * 1024 * 1024
  KosmoCliMaxMessageBytes* = KosmoCliMaxDiffBytes * 6 + 64 * 1024
  KosmoCliConnectTimeoutMilliseconds* = 2_000
  KosmoCliResponseTimeoutMilliseconds* = 10_000
  KosmoCliPollInterval = initDuration(milliseconds = 50)
  KosmoCliCurrentEndpointName = "current.json"

type
  KosmoCliRequestKind* = enum
    kcrOpenPaths
    kcrShowDiff

  KosmoCliOpenRequest* = object
    requestId*: string
    kind*: KosmoCliRequestKind
    paths*: seq[string]
    originWindow*: string
    workingDirectory*: string
    diffText*: string

  KosmoCliOpenResponse* = object
    delivered*: bool
    errors*: seq[string]

  KosmoCliOpenHandler* =
    proc(request: KosmoCliOpenRequest): KosmoCliOpenResponse {.closure.}

  KosmoCliEndpoint = object
    version: int
    instanceId: string
    processId: int
    port: int
    token: string

  KosmoCliClient = object
    socket: Socket
    input: string

  KosmoCliTicker = ref object of AgentActor

  KosmoCliOpenServer* = ref object of Agent
    socket: Socket
    clients: seq[KosmoCliClient]
    ticker: AgentProxy[KosmoCliTicker]
    timer: SigilTimer
    endpoint: KosmoCliEndpoint
    registryDirectory: string
    endpointPath: string
    handler: KosmoCliOpenHandler
    closed: bool

proc kosmoCliTicked(ticker: KosmoCliTicker) {.signal.}

proc tick(ticker: KosmoCliTicker) {.slot.} =
  emit ticker.kosmoCliTicked()

func defaultKosmoCliRegistryDirectory*(): string =
  getConfigDir() / "kosmo" / "cli"

proc randomIdentifier*(): string =
  for value in urandom(16):
    result.add value.toHex(2).toLowerAscii()

func endpointJson(endpoint: KosmoCliEndpoint): JsonNode =
  %*{
    "version": endpoint.version,
    "instanceId": endpoint.instanceId,
    "processId": endpoint.processId,
    "port": endpoint.port,
    "token": endpoint.token,
  }

proc parseEndpoint(content: string): KosmoCliEndpoint =
  let node = parseJson(content)
  result = KosmoCliEndpoint(
    version: node["version"].getInt(),
    instanceId: node["instanceId"].getStr(),
    processId: node["processId"].getInt(),
    port: node["port"].getInt(),
    token: node["token"].getStr(),
  )
  if result.version != KosmoCliProtocolVersion or result.instanceId.len == 0 or
      result.token.len < 16 or result.port notin 1 .. 65_535:
    raise newException(ValueError, "Invalid Kosmo CLI endpoint")

proc secureRegistryDirectory(path: string) =
  createDir(path)
  when defined(posix):
    setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})

proc writeEndpoint(path: string, endpoint: KosmoCliEndpoint) =
  path.parentDir().secureRegistryDirectory()
  let temporary = path & "." & $getCurrentProcessId() & ".tmp"
  try:
    writeFile(temporary, $endpoint.endpointJson())
    when defined(posix):
      setFilePermissions(temporary, {fpUserRead, fpUserWrite})
    moveFile(temporary, path)
  except:
    discard tryRemoveFile(temporary)
    raise

proc readEndpoint(path: string): KosmoCliEndpoint =
  if path.len == 0 or not fileExists(path) or symlinkExists(path):
    raise newException(IOError, "Kosmo CLI endpoint is unavailable")
  parseEndpoint(readFile(path))

proc requestJson(endpoint: KosmoCliEndpoint, request: KosmoCliOpenRequest): JsonNode =
  %*{
    "version": KosmoCliProtocolVersion,
    "instanceId": endpoint.instanceId,
    "token": endpoint.token,
    "requestId": request.requestId,
    "kind": request.kind.ord,
    "paths": request.paths,
    "originWindow": request.originWindow,
    "workingDirectory": request.workingDirectory,
    "diffText": request.diffText,
  }

proc parseRequest(content: string, endpoint: KosmoCliEndpoint): KosmoCliOpenRequest =
  let node = parseJson(content)
  if node["version"].getInt() != KosmoCliProtocolVersion or
      node["instanceId"].getStr() != endpoint.instanceId or
      node["token"].getStr() != endpoint.token:
    raise newException(ValueError, "Kosmo CLI authentication failed")
  result.requestId = node["requestId"].getStr()
  let kind = node["kind"].getInt()
  if kind notin KosmoCliRequestKind.low.ord .. KosmoCliRequestKind.high.ord:
    raise newException(ValueError, "Invalid Kosmo CLI request kind")
  result.kind = KosmoCliRequestKind(kind)
  result.originWindow = node{"originWindow"}.getStr()
  result.workingDirectory = node{"workingDirectory"}.getStr()
  result.diffText = node{"diffText"}.getStr()
  for path in node["paths"]:
    result.paths.add path.getStr()
  if result.requestId.len == 0:
    raise newException(ValueError, "Invalid Kosmo CLI open request")
  case result.kind
  of kcrOpenPaths:
    if result.paths.len == 0 or result.paths.len > KosmoCliMaxPaths:
      raise newException(ValueError, "Invalid Kosmo CLI open request")
    for path in result.paths:
      if path.len == 0 or not path.isAbsolute():
        raise newException(ValueError, "Kosmo CLI paths must be absolute")
  of kcrShowDiff:
    if result.paths.len > 0 or result.workingDirectory.len == 0 or
        not result.workingDirectory.isAbsolute() or
        result.diffText.len > KosmoCliMaxDiffBytes:
      raise newException(ValueError, "Invalid Kosmo CLI diff request")

func responseJson(response: KosmoCliOpenResponse): JsonNode =
  %*{
    "version": KosmoCliProtocolVersion,
    "delivered": response.delivered,
    "errors": response.errors,
  }

proc parseResponse(content: string): KosmoCliOpenResponse =
  let node = parseJson(content)
  if node["version"].getInt() != KosmoCliProtocolVersion:
    raise newException(ValueError, "Incompatible Kosmo CLI response")
  result.delivered = node["delivered"].getBool()
  for message in node["errors"]:
    result.errors.add message.getStr()

proc addEndpointCandidate(
    candidates: var seq[string], seen: var HashSet[string], path: string
) =
  if path.len > 0 and path notin seen:
    seen.incl path
    candidates.add path

proc endpointCandidates(registryDirectory, preferredEndpoint: string): seq[string] =
  var seen = initHashSet[string]()
  result.addEndpointCandidate(seen, preferredEndpoint)
  result.addEndpointCandidate(seen, registryDirectory / KosmoCliCurrentEndpointName)
  if dirExists(registryDirectory):
    var instances: seq[(Time, string)]
    try:
      for kind, path in walkDir(registryDirectory):
        if kind == pcFile and path.extractFilename().startsWith("instance-") and
            path.endsWith(".json"):
          instances.add (getLastModificationTime(path), path)
    except OSError:
      discard
    instances.sort(
      proc(left, right: (Time, string)): int =
        cmp(right[0], left[0])
    )
    for instance in instances:
      result.addEndpointCandidate(seen, instance[1])

proc sendRequest(
    endpoint: KosmoCliEndpoint, request: KosmoCliOpenRequest
): KosmoCliOpenResponse =
  let socket = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, buffered = false)
  defer:
    socket.close()
  socket.connect(
    "127.0.0.1", Port(endpoint.port), timeout = KosmoCliConnectTimeoutMilliseconds
  )
  socket.send($endpoint.requestJson(request) & "\n")
  try:
    let response = socket.recvLine(
      timeout = KosmoCliResponseTimeoutMilliseconds, maxLength = KosmoCliMaxMessageBytes
    )
    if response.len == 0:
      raise newException(IOError, "Kosmo closed the CLI connection without a response")
    result = parseResponse(response)
  except CatchableError:
    result.delivered = true
    result.errors.add "Kosmo did not confirm the CLI open request"

proc sendToRunningKosmo(
    request: KosmoCliOpenRequest,
    preferredEndpoint = getEnv(KosmoCliEndpointEnvironment),
    registryDirectory = defaultKosmoCliRegistryDirectory(),
): KosmoCliOpenResponse =
  for path in endpointCandidates(registryDirectory, preferredEndpoint):
    try:
      let endpoint = readEndpoint(path)
      result = endpoint.sendRequest(request)
      if result.delivered:
        return
    except CatchableError:
      discard

proc openInRunningKosmo*(
    paths: openArray[string],
    preferredEndpoint = getEnv(KosmoCliEndpointEnvironment),
    originWindow = getEnv(KosmoCliWindowEnvironment),
    registryDirectory = defaultKosmoCliRegistryDirectory(),
): KosmoCliOpenResponse =
  ## Forward absolute paths to a responsive Kosmo process. `delivered` remains
  ## false when no usable process was found.
  if paths.len == 0 or paths.len > KosmoCliMaxPaths:
    result.errors.add "A Kosmo CLI request must contain 1 to 64 paths"
    return
  result = sendToRunningKosmo(
    KosmoCliOpenRequest(
      requestId: randomIdentifier(),
      kind: kcrOpenPaths,
      paths: @paths,
      originWindow: originWindow,
    ),
    preferredEndpoint,
    registryDirectory,
  )

proc showDiffInRunningKosmo*(
    diffText, workingDirectory: string,
    preferredEndpoint = getEnv(KosmoCliEndpointEnvironment),
    originWindow = getEnv(KosmoCliWindowEnvironment),
    registryDirectory = defaultKosmoCliRegistryDirectory(),
): KosmoCliOpenResponse =
  ## Forward a bounded unified diff to a responsive Kosmo process.
  if workingDirectory.len == 0 or not workingDirectory.isAbsolute():
    result.errors.add "Kosmo CLI diff working directory must be absolute"
    return
  if diffText.len > KosmoCliMaxDiffBytes:
    result.errors.add "Kosmo diff input exceeds the 8 MiB limit"
    return
  result = sendToRunningKosmo(
    KosmoCliOpenRequest(
      requestId: randomIdentifier(),
      kind: kcrShowDiff,
      originWindow: originWindow,
      workingDirectory: workingDirectory,
      diffText: diffText,
    ),
    preferredEndpoint,
    registryDirectory,
  )

proc removeEndpointIfOwned(path, token: string) =
  try:
    if fileExists(path) and readEndpoint(path).token == token:
      removeFile(path)
  except CatchableError:
    discard

proc processClient(server: KosmoCliOpenServer, index: int): bool =
  ## Return true while this client should remain connected.
  var chunk: string
  let received = server.clients[index].socket.recv(chunk, 64 * 1024)
  if received == 0:
    return
  server.clients[index].input.add chunk
  if server.clients[index].input.len > KosmoCliMaxMessageBytes:
    server.clients[index].socket.send(
      $(
        KosmoCliOpenResponse(errors: @["Kosmo CLI request is too large"]).responseJson()
      ) & "\n"
    )
    return
  let lineEnd = server.clients[index].input.find('\n')
  if lineEnd < 0:
    return true
  var
    request: KosmoCliOpenRequest
    response: KosmoCliOpenResponse
  try:
    request = parseRequest(server.clients[index].input[0 ..< lineEnd], server.endpoint)
  except CatchableError as error:
    response.errors.add error.msg
    server.clients[index].socket.send($response.responseJson() & "\n")
    return
  response.delivered = true
  try:
    response = server.handler(request)
    response.delivered = true
  except CatchableError as error:
    response.errors.add error.msg
  server.clients[index].socket.send($response.responseJson() & "\n")

proc poll(server: KosmoCliOpenServer) {.slot.} =
  if server.isNil or server.closed:
    return
  var serverHandles = @[server.socket.getFd()]
  if selectRead(serverHandles, 0) > 0 and server.clients.len < 8:
    try:
      var client: owned(Socket)
      server.socket.accept(client)
      client.getFd().setBlocking(false)
      server.clients.add KosmoCliClient(socket: client)
    except OSError:
      discard
  var index: int
  while index < server.clients.len:
    var clientHandles = @[server.clients[index].socket.getFd()]
    var keep = true
    if selectRead(clientHandles, 0) > 0:
      try:
        keep = server.processClient(index)
      except CatchableError:
        keep = false
    if keep:
      inc index
    else:
      server.clients[index].socket.close()
      server.clients.delete(index)

proc startKosmoCliOpenServer*(
    handler: KosmoCliOpenHandler, registryDirectory = defaultKosmoCliRegistryDirectory()
): KosmoCliOpenServer =
  ## Listen on an authenticated loopback endpoint and publish this process as
  ## the newest CLI destination.
  if handler.isNil:
    raise newException(ValueError, "Kosmo CLI open handler is required")
  let socket = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, buffered = false)
  var
    endpoint: KosmoCliEndpoint
    endpointPath: string
  try:
    socket.bindAddr(Port(0), "127.0.0.1")
    socket.listen()
    socket.getFd().setBlocking(false)
    endpoint = KosmoCliEndpoint(
      version: KosmoCliProtocolVersion,
      instanceId: randomIdentifier(),
      processId: getCurrentProcessId(),
      port: socket.getLocalAddr()[1].int,
      token: randomIdentifier(),
    )
    endpointPath = registryDirectory / ("instance-" & endpoint.instanceId & ".json")
    writeEndpoint(endpointPath, endpoint)
    writeEndpoint(registryDirectory / KosmoCliCurrentEndpointName, endpoint)
    result = KosmoCliOpenServer(
      socket: socket,
      endpoint: endpoint,
      registryDirectory: registryDirectory,
      endpointPath: endpointPath,
      handler: handler,
    )
    var ticker = KosmoCliTicker()
    let timerThread = nimkitTimerThread()
    result.ticker = ticker.moveToThread(timerThread)
    result.timer = newSigilTimer(KosmoCliPollInterval)
    connectThreaded(result.timer, timeout, result.ticker, KosmoCliTicker.tick())
    connectThreaded(result.ticker, kosmoCliTicked, result, KosmoCliOpenServer.poll())
    result.timer.start(timerThread)
  except:
    socket.close()
    endpointPath.removeEndpointIfOwned(endpoint.token)
    (registryDirectory / KosmoCliCurrentEndpointName).removeEndpointIfOwned(
      endpoint.token
    )
    raise

proc endpointPath*(server: KosmoCliOpenServer): string =
  if not server.isNil:
    result = server.endpointPath

proc close*(server: KosmoCliOpenServer) =
  if server.isNil or server.closed:
    return
  server.closed = true
  if not server.timer.isNil:
    server.timer.cancel(nimkitTimerThread())
  for client in server.clients.mitems:
    client.socket.close()
  server.clients.setLen(0)
  if not server.socket.isNil:
    server.socket.close()
  server.endpointPath.removeEndpointIfOwned(server.endpoint.token)
  (server.registryDirectory / KosmoCliCurrentEndpointName).removeEndpointIfOwned(
    server.endpoint.token
  )
  server.timer = nil
  server.ticker = nil
