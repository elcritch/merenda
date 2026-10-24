## Private Unix-socket transport. No GUI imports or implicit instance discovery.
import std/[json, monotimes, nativesockets, net, os, strutils, tables, times]
import sigils/[core, selectors]
import sigils/rpcs/json/jrAgents
import ./protocol

when defined(posix):
  import std/posix

const
  DevMaxClients = 4
  DevIoTimeout = initDuration(seconds = 15)
  DevChunkBytes = 64 * 1024
  DevMaxSocketPath =
    when defined(posix):
      min(100, Sockaddr_un_path_length - 1)
    else:
      100

type
  DevCompletion* = proc(response: DevResponse) {.closure.}
  DevHandler* = proc(request: DevRequest, complete: DevCompletion) {.closure.}

  DevConnection = ref object
    socket: Socket
    id: uint64
    input, output: string
    sent: int
    dispatched, closed: bool
    deadline: MonoTime

  DevPendingReply = ref object
    response: DevResponse
    finished: bool
    deadline: MonoTime

  DevRpcEndpoint = ref object of DynamicAgent
    handler: DevHandler
    replies: Table[string, DevPendingReply]
    nextToken: uint64
    closed: bool

  DevServer* = ref object of JsonRpcIoAgent
    socket: Socket
    path: string
    clients: seq[DevConnection]
    endpoint: DevRpcEndpoint
    dispatcher: JsonRpcDispatcher
    nextConnection: uint64
    closed: bool
    when defined(posix):
      device: Dev
      inode: Ino

proc devSocketPath*(pid: Positive): string =
  ## Deterministic per-user address, independent of the caller's TMPDIR.
  when defined(posix):
    "/tmp/merenda-dev-" & $getuid() & "/" & $pid & ".sock"
  else:
    raise newException(OSError, "Development control requires Unix sockets")

proc close(connection: DevConnection) =
  if not connection.closed:
    connection.closed = true
    connection.socket.close()
    connection.output.setLen(0)

proc close*(server: DevServer) =
  ## Closes clients and removes only the socket inode created by this server.
  if server.isNil or server.closed:
    return
  server.closed = true
  for connection in server.clients:
    connection.close()
  server.clients.setLen(0)
  server.endpoint.closed = true
  server.endpoint.handler = nil
  server.endpoint.replies.clear()
  server.socket.close()
  when defined(posix):
    var status: Stat
    if lstat(server.path.cstring, status) == 0 and status.st_dev == server.device and
        status.st_ino == server.inode:
      discard unlink(server.path.cstring)

proc validateSocketPath(path: string) =
  if not path.isAbsolute() or path.len > DevMaxSocketPath or '\0' in path:
    raise newException(
      ValueError,
      "Socket path must be absolute and at most " & $DevMaxSocketPath & " bytes",
    )

proc dispatchRequest(self: DynamicAgent, request: DevRequest): JsonNode =
  let endpoint = DevRpcEndpoint(self)
  if endpoint.closed:
    return devFailure(request.id, "unavailable", "Development control stopped")
      .responseJson()
  let reply = DevPendingReply(deadline: getMonoTime() + DevIoTimeout)
  endpoint.handler(
    request,
    proc(response: DevResponse) =
      if not reply.finished:
        reply.response = response
        reply.finished = true
    ,
  )
  if reply.finished:
    return reply.response.responseJson()
  if endpoint.closed:
    return devFailure(request.id, "unavailable", "Development control stopped")
      .responseJson()
  if endpoint.replies.len >= DevMaxClients:
    return
      devFailure(request.id, "busy", "Pending request queue is full").responseJson()
  inc endpoint.nextToken
  let token = "r" & $endpoint.nextToken
  endpoint.replies[token] = reply
  devSuccess(request.id, %*{"pending": token}).responseJson()

proc pendingResult(self: DynamicAgent, query: DevPendingQuery): JsonNode =
  let endpoint = DevRpcEndpoint(self)
  if not endpoint.replies.hasKey(query.token):
    return
      devFailure("", "result_not_found", "Pending result is unavailable").responseJson()
  let reply = endpoint.replies[query.token]
  if not reply.finished:
    return devSuccess("", %*{"pending": query.token}).responseJson()
  endpoint.replies.del(query.token)
  reply.response.responseJson()

proc startDevServer*(path: string, handler: DevHandler): DevServer =
  ## Refuses occupied paths and directories not privately owned by this user.
  when defined(posix):
    validateSocketPath(path)
    let directory = path.parentDir()
    if directory == devSocketPath(getCurrentProcessId().Positive).parentDir():
      if posix.mkdir(directory.cstring, Mode(0o700)) != 0 and
          osLastError() != OSErrorCode(EEXIST):
        raiseOSError(osLastError())
    var status: Stat
    if lstat(directory.cstring, status) != 0:
      raiseOSError(osLastError())
    if not S_ISDIR(status.st_mode) or status.st_uid != getuid() or
        (status.st_mode and Mode(0o077)) != 0:
      raise newException(
        OSError, "Socket directory must be owned by this user with mode 0700"
      )
    let endpoint = DevRpcEndpoint(handler: handler)
    discard endpoint.addMethod(DevRequestSelector, toDynamicMethod(dispatchRequest))
    discard endpoint.addMethod(DevResultSelector, toDynamicMethod(pendingResult))
    let adapter = newJsonRpcAdapter()
    adapter.registerSelector("merenda", endpoint, DevRequestSelector)
    adapter.registerSelector("merenda", endpoint, DevResultSelector)
    let dispatcher = newJsonRpcDispatcher(adapter)
    let socket =
      newSocket(AF_UNIX, SOCK_STREAM, nativesockets.IPPROTO_NONE, buffered = false)
    var bound = false
    try:
      socket.bindUnix(path)
      bound = true
      if chmod(path.cstring, Mode(0o600)) != 0:
        raiseOSError(osLastError())
      if lstat(path.cstring, status) != 0:
        raiseOSError(osLastError())
      socket.listen(DevMaxClients)
      socket.getFd().setBlocking(false)
      result = DevServer(
        socket: socket,
        path: path,
        endpoint: endpoint,
        dispatcher: dispatcher,
        device: status.st_dev,
        inode: status.st_ino,
      )
      dispatcher.connectJsonRpc(result)
    except:
      socket.close()
      if bound:
        discard unlink(path.cstring)
      raise
  else:
    raise newException(OSError, "Development control requires Unix sockets")

method startIo(server: DevServer) {.gcsafe.} =
  if not server.closed:
    emit server.jsonRpcStarted(server.path)

method stopIo(server: DevServer) {.gcsafe.} =
  server.close()
  emit server.jsonRpcStopped()

method queueResponse(server: DevServer, response: sink JsonRpcResponse) {.gcsafe.} =
  if server.closed:
    return
  for connection in server.clients:
    if connection.id == response.connectionId and not connection.closed:
      if connection.output.len == 0:
        if response.data.len + 1 > DevMaxResponseBytes:
          connection.close()
        else:
          connection.output = response.data & "\n"
          connection.deadline = getMonoTime() + DevIoTimeout
      return

proc socketWouldBlock(): bool =
  when defined(posix):
    let error = osLastError()
    error in [OSErrorCode(EAGAIN), OSErrorCode(EWOULDBLOCK), OSErrorCode(EINTR)]

proc poll*(server: DevServer) =
  ## Bounded, nonblocking work on the application's owning thread.
  if server.isNil or server.closed:
    return
  var expired: seq[string]
  for token, reply in server.endpoint.replies:
    if getMonoTime() >= reply.deadline:
      expired.add token
  for token in expired:
    server.endpoint.replies.del(token)
  var requests: seq[JsonRpcRequest]
  var handles = @[server.socket.getFd()]
  if server.clients.len < DevMaxClients and selectRead(handles, 0) > 0:
    try:
      var client: owned(Socket)
      server.socket.accept(client)
      client.getFd().setBlocking(false)
      inc server.nextConnection
      server.clients.add DevConnection(
        id: server.nextConnection,
        socket: client,
        deadline: getMonoTime() + DevIoTimeout,
      )
    except OSError:
      discard # Readiness can be interrupted before accept completes.
  var index = 0
  while index < server.clients.len:
    let connection = server.clients[index]
    try:
      if getMonoTime() >= connection.deadline:
        connection.close()
      elif connection.output.len > 0:
        var writable = @[connection.socket.getFd()]
        if selectWrite(writable, 0) > 0:
          let count = min(DevChunkBytes, connection.output.len - connection.sent)
          let sent =
            connection.socket.send(unsafeAddr connection.output[connection.sent], count)
          if sent > 0:
            connection.sent += sent
            connection.deadline = getMonoTime() + DevIoTimeout
            if connection.sent == connection.output.len:
              connection.close()
          elif sent == 0 or not socketWouldBlock():
            connection.close()
      elif connection.dispatched:
        var readable = @[connection.socket.getFd()]
        if selectRead(readable, 0) > 0:
          connection.close() # EOF or additional input after the single request.
      elif not connection.dispatched:
        var readable = @[connection.socket.getFd()]
        if selectRead(readable, 0) > 0:
          var chunk = newString(DevChunkBytes)
          let received = connection.socket.recv(addr chunk[0], chunk.len)
          if received <= 0:
            connection.close()
          else:
            chunk.setLen(received)
            connection.input.add chunk
            if connection.input.len > DevMaxRequestBytes:
              connection.close()
            elif '\n' in connection.input:
              connection.dispatched = true
              requests.add JsonRpcRequest(
                connectionId: connection.id,
                data: connection.input[0 ..< connection.input.find('\n')],
              )
              connection.input.setLen(0)
    except CatchableError:
      connection.close()
    if connection.closed:
      server.clients.delete(index)
    else:
      inc index

  # Dispatch only after socket iteration. A handler can enter a modal loop,
  # poll recursively, or stop this endpoint without invalidating an outer index.
  for request in requests:
    if server.closed:
      break
    emit server.jsonRpcRequestReceived(request)

proc sendDevRpcRequest*(path: string, request: JsonNode, timeoutMs = 15000): JsonNode =
  ## Sends once. A timeout never retries a possibly executed input command.
  when defined(posix):
    validateSocketPath(path)
    if timeoutMs <= 0:
      raise newException(ValueError, "Timeout must be positive")
    let socket =
      newSocket(AF_UNIX, SOCK_STREAM, nativesockets.IPPROTO_NONE, buffered = false)
    defer:
      socket.close()
    socket.getFd().setBlocking(false)
    socket.connectUnix(path)
    let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
    let message = $request & "\n"
    if message.len > DevMaxRequestBytes:
      raise newException(ValueError, "Control request exceeds size limit")
    var sent = 0
    var input: string
    while getMonoTime() < deadline:
      if sent < message.len:
        var writable = @[socket.getFd()]
        if selectWrite(writable, 20) > 0:
          let count = socket.send(unsafeAddr message[sent], message.len - sent)
          if count > 0:
            sent += count
          elif count == 0:
            raise newException(IOError, "Control connection closed while sending")
          elif not socketWouldBlock():
            raiseOSError(osLastError())
      else:
        var readable = @[socket.getFd()]
        if selectRead(readable, 20) > 0:
          var chunk = newString(DevChunkBytes)
          let received = socket.recv(addr chunk[0], chunk.len)
          if received == 0:
            raise newException(IOError, "Control connection closed before its response")
          if received < 0:
            if socketWouldBlock():
              continue
            raiseOSError(osLastError())
          chunk.setLen(received)
          input.add chunk
          if input.len > DevMaxResponseBytes:
            raise newException(IOError, "Control response exceeds size limit")
          let newline = input.find('\n')
          if newline >= 0:
            result = parseJson(input[0 ..< newline])
            if result.kind != JObject or
                result.getOrDefault("jsonrpc") != %JsonRpcVersion or
                result.getOrDefault("id") != request.getOrDefault("id") or
                result.hasKey("result") == result.hasKey("error"):
              raise newException(IOError, "Invalid JSON-RPC control response")
            return
    raise newException(
      IOError, "Control request timed out; execution may already have occurred"
    )
  else:
    raise newException(OSError, "Development control requires Unix sockets")

proc sendDevRequest*(path: string, request: DevRequest, timeoutMs = 15000): JsonNode =
  ## Calls Sigils RPC once, then retrieves a pending result without retrying input.
  if timeoutMs <= 0:
    raise newException(ValueError, "Timeout must be positive")
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
  proc exchange(message: JsonNode): JsonNode =
    let remaining = max(1, (deadline - getMonoTime()).inMilliseconds.int)
    let response = sendDevRpcRequest(path, message, remaining)
    if response.hasKey("error"):
      return devFailure(request.id, "rpc_error", $response["error"]).responseJson()
    response["result"]

  result = exchange(request.rpcRequestJson())
  while result["ok"].getBool() and result["result"].kind == JObject and
      result["result"].hasKey("pending"):
    if getMonoTime() >= deadline:
      raise newException(
        IOError, "Control request timed out; execution may already have occurred"
      )
    let token = result["result"]["pending"].getStr()
    sleep(5)
    result =
      exchange(newJsonRpcRequest(%request.id, "merenda.result", %*{"token": token}))
