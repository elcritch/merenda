## Process-local transport coverage for Kosmo CLI open requests.

import std/[atomics, json, monotimes, os, tempfiles, times, unittest]

import sigils/[core, threads]

import merenda/kosmo/cliopen

const ClientValueCapacity = 2048

type CliClientState = object
  path: array[ClientValueCapacity, char]
  endpoint: array[ClientValueCapacity, char]
  registry: array[ClientValueCapacity, char]
  origin: array[ClientValueCapacity, char]
  delivered: Atomic[bool]
  errorCount: Atomic[int]
  done: Atomic[bool]

proc store(value: string, buffer: var array[ClientValueCapacity, char]) =
  doAssert value.len < buffer.len
  for index, character in value:
    buffer[index] = character

proc load(buffer: ptr array[ClientValueCapacity, char]): string =
  $cast[cstring](addr buffer[][0])

proc sendOpenRequest(state: ptr CliClientState) {.thread.} =
  try:
    let response = openInRunningKosmo(
      [state.path.addr.load()],
      preferredEndpoint = state.endpoint.addr.load(),
      originWindow = state.origin.addr.load(),
      registryDirectory = state.registry.addr.load(),
    )
    state.delivered.store(response.delivered, moRelease)
    state.errorCount.store(response.errors.len, moRelease)
  except CatchableError:
    state.errorCount.store(-1, moRelease)
  state.done.store(true, moRelease)

proc requestWhilePumping(
    path, endpoint, registry: string, origin = ""
): tuple[delivered: bool, errorCount: int] =
  let state = cast[ptr CliClientState](allocShared0(sizeof(CliClientState)))
  defer:
    deallocShared(state)
  path.store(state.path)
  endpoint.store(state.endpoint)
  registry.store(state.registry)
  origin.store(state.origin)
  var thread: Thread[ptr CliClientState]
  createThread(thread, sendOpenRequest, state)
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while not state.done.load(moAcquire) and getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    sleep(1)
  check state.done.load(moAcquire)
  thread.joinThread()
  result = (
    delivered: state.delivered.load(moAcquire),
    errorCount: state.errorCount.load(moAcquire),
  )

suite "Kosmo CLI open transport":
  test "authenticated requests reach the newest responsive process":
    let
      registry = createTempDir("merenda-kosmo-cli-registry-", "")
      target = registry / "notes with spaces.md"
    defer:
      removeDir(registry)
    var
      firstRequests: seq[KosmoCliOpenRequest]
      secondRequests: seq[KosmoCliOpenRequest]
    let first = startKosmoCliOpenServer(
      proc(request: KosmoCliOpenRequest): KosmoCliOpenResponse =
        firstRequests.add request
        KosmoCliOpenResponse(),
      registry,
    )
    defer:
      first.close()
    let second = startKosmoCliOpenServer(
      proc(request: KosmoCliOpenRequest): KosmoCliOpenResponse =
        secondRequests.add request
        KosmoCliOpenResponse(),
      registry,
    )
    defer:
      second.close()

    let response = requestWhilePumping(target, "", registry)
    check response.delivered
    check response.errorCount == 0
    check firstRequests.len == 0
    require secondRequests.len == 1
    check secondRequests[0].paths == @[target]
    check secondRequests[0].originWindow.len == 0

    let staleEndpoint = readFile(second.endpointPath())
    second.close()
    writeFile(registry / "current.json", staleEndpoint)
    let fallback = requestWhilePumping(target, "", registry)
    check fallback.delivered
    check fallback.errorCount == 0
    require firstRequests.len == 1
    check firstRequests[0].paths == @[target]

  test "an embedded-terminal endpoint takes precedence over the newest process":
    let
      registry = createTempDir("merenda-kosmo-cli-origin-", "")
      target = registry / "terminal-target.nim"
    defer:
      removeDir(registry)
    var
      firstOrigin: string
      secondRequests: int
    let first = startKosmoCliOpenServer(
      proc(request: KosmoCliOpenRequest): KosmoCliOpenResponse =
        firstOrigin = request.originWindow
        KosmoCliOpenResponse(),
      registry,
    )
    defer:
      first.close()
    let second = startKosmoCliOpenServer(
      proc(request: KosmoCliOpenRequest): KosmoCliOpenResponse =
        inc secondRequests
        KosmoCliOpenResponse(),
      registry,
    )
    defer:
      second.close()

    let response = requestWhilePumping(
      target, first.endpointPath(), registry, origin = "owning-window"
    )
    check response.delivered
    check firstOrigin == "owning-window"
    check secondRequests == 0

  test "wrong credentials are rejected and endpoint files are removed on close":
    let registry = createTempDir("merenda-kosmo-cli-auth-", "")
    defer:
      removeDir(registry)
    var requestCount: int
    let server = startKosmoCliOpenServer(
      proc(request: KosmoCliOpenRequest): KosmoCliOpenResponse =
        discard request
        inc requestCount
        KosmoCliOpenResponse(),
      registry,
    )
    let endpointPath = server.endpointPath()
    let badEndpointPath = registry / "bad-endpoint.json"
    var endpoint = parseJson(readFile(endpointPath))
    endpoint["token"] = %"incorrect-authentication-token"
    writeFile(badEndpointPath, $endpoint)
    let emptyRegistry = createTempDir("merenda-kosmo-cli-empty-", "")
    defer:
      removeDir(emptyRegistry)

    let response =
      requestWhilePumping(registry / "rejected.nim", badEndpointPath, emptyRegistry)
    check not response.delivered
    check requestCount == 0
    server.close()
    check not fileExists(endpointPath)
    check not fileExists(registry / "current.json")

  test "handler failures are delivered without trying another process":
    let
      registry = createTempDir("merenda-kosmo-cli-handler-", "")
      target = registry / "handler-error.nim"
    defer:
      removeDir(registry)
    var fallbackRequests: int
    let fallback = startKosmoCliOpenServer(
      proc(request: KosmoCliOpenRequest): KosmoCliOpenResponse =
        discard request
        inc fallbackRequests
        KosmoCliOpenResponse(),
      registry,
    )
    defer:
      fallback.close()
    let failing = startKosmoCliOpenServer(
      proc(request: KosmoCliOpenRequest): KosmoCliOpenResponse =
        discard request
        raise newException(IOError, "open failed"),
      registry,
    )
    defer:
      failing.close()

    let response = requestWhilePumping(target, "", registry)
    check response.delivered
    check response.errorCount == 1
    check fallbackRequests == 0
