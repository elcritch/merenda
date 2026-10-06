## Byte transport for Kosmo's dedicated LSP stdio-to-TCP child process.

import std/[atomics, nativesockets, net, os, strutils, typedthreads, uri]

when defined(windows):
  import std/winlean
  proc readInput(
    fd: cint, buffer: pointer, size: cuint
  ): cint {.importc: "_read", header: "<io.h>".}

  proc writeOutput(
    fd: cint, buffer: pointer, size: cuint
  ): cint {.importc: "_write", header: "<io.h>".}

  proc setBinaryMode(fd, mode: cint): cint {.importc: "_setmode", header: "<io.h>".}
else:
  import std/posix

type
  LspTcpEndpoint* = object
    ## A TCP LSP endpoint. The port is always between 1 and 65535.
    host*: string
    port*: Port

  InputStatus = enum
    inputReading
    inputClosed
    inputFailed

  InputPump = object
    socket: SocketHandle
    status: ptr Atomic[InputStatus]

const BufferSize = 16 * 1024

proc parseLspTcpEndpoint*(address: string): LspTcpEndpoint =
  ## Parse `tcp://host:port`, including bracketed IPv6 addresses.
  ## Raise ValueError for missing ports, credentials, paths or invalid ports.
  let endpoint = parseUri(address)
  if not address.startsWith("tcp://") or endpoint.scheme != "tcp" or
      endpoint.hostname.len == 0 or endpoint.username.len > 0 or
      endpoint.password.len > 0 or endpoint.path.len > 0 or endpoint.query.len > 0 or
      endpoint.anchor.len > 0 or endpoint.port.len == 0 or
      address.contains({' ', '\t', '\r', '\n'}):
    raise newException(ValueError, "TCP LSP address must be tcp://host:port")
  for character in endpoint.port:
    if character notin {'0' .. '9'}:
      raise newException(ValueError, "TCP LSP port must be between 1 and 65535")
  let port = parseInt(endpoint.port)
  if port < 1 or port > 65535:
    raise newException(ValueError, "TCP LSP port must be between 1 and 65535")
  LspTcpEndpoint(host: endpoint.hostname, port: Port(port))

proc interrupted(): bool =
  when defined(posix):
    osLastError().int == EINTR.int

proc readInput(buffer: pointer, size: int): int =
  when defined(windows):
    readInput(0, buffer, size.cuint).int
  else:
    posix.read(STDIN_FILENO, buffer, size).int

proc writeOutput(buffer: pointer, size: int): int =
  when defined(windows):
    writeOutput(1, buffer, size.cuint).int
  else:
    posix.write(STDOUT_FILENO, buffer, size).int

proc stopSocket(socket: SocketHandle) =
  when defined(windows):
    discard winlean.shutdown(socket, 2)
  else:
    discard posix.shutdown(socket, SHUT_RDWR)

proc pumpInput(state: InputPump) {.thread.} =
  try:
    var buffer: array[BufferSize, byte]
    while true:
      let count = readInput(addr buffer[0], buffer.len)
      if count == 0:
        state.status[].store(inputClosed)
        break
      if count < 0:
        if not interrupted():
          raiseOSError(osLastError())
      else:
        var offset = 0
        while offset < count:
          let flags =
            when defined(windows) or defined(macosx): 0.cint else: MSG_NOSIGNAL.cint
          let sent = nativesockets.send(
            state.socket, addr buffer[offset], (count - offset).cint, flags
          )
          if sent < 0:
            if not interrupted():
              raiseOSError(osLastError())
          elif sent == 0:
            raise newException(IOError, "TCP LSP socket closed while writing")
          else:
            offset += sent.int
  except CatchableError as error:
    state.status[].store(inputFailed)
    stderr.writeLine("Kosmo TCP LSP input failed: " & error.msg)
  finally:
    state.socket.stopSocket()

proc runLspTcpChild*(address: string) {.noreturn.} =
  ## Connect a dedicated child process to an LSP socket and forward stdio bytes.
  ## Exit when stdin or the peer closes; stdout contains only protocol bytes.
  try:
    let endpoint = parseLspTcpEndpoint(address)
    let domain = if endpoint.host.contains(':'): AF_INET6 else: AF_INET
    let socket = newSocket(domain, SOCK_STREAM, IPPROTO_TCP, buffered = false)
    socket.connect(endpoint.host, endpoint.port, timeout = 5000)
    when defined(windows):
      const BinaryMode = 0x8000.cint
      if setBinaryMode(0, BinaryMode) < 0 or setBinaryMode(1, BinaryMode) < 0:
        raiseOSError(osLastError())

    var status: Atomic[InputStatus]
    var inputThread: Thread[InputPump]
    createThread(
      inputThread, pumpInput, InputPump(socket: socket.getFd(), status: addr status)
    )
    var buffer: array[BufferSize, byte]
    while true:
      let count = socket.recv(addr buffer[0], buffer.len)
      if count == 0:
        break
      if count < 0:
        if not interrupted():
          if status.load() != inputClosed:
            raiseOSError(osLastError())
          break
      else:
        var offset = 0
        while offset < count:
          let written = writeOutput(addr buffer[offset], count - offset)
          if written < 0:
            if not interrupted():
              raiseOSError(osLastError())
          elif written == 0:
            raise newException(IOError, "TCP LSP stdout closed while writing")
          else:
            offset += written
    # The input thread may still be blocked on stdin after a peer disconnect.
    # Ending this dedicated process releases both directions without a join.
    quit(if status.load() == inputFailed: 1 else: 0)
  except CatchableError as error:
    stderr.writeLine("Kosmo TCP LSP connection failed: " & error.msg)
    quit(1)
