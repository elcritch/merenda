import
  std/[
    appdirs, atomics, monotimes, nativesockets, net, os, paths, strutils, tempfiles,
    times, unittest,
  ]

import merenda/nimkit/foundation/urlassets
import merenda/nimkit/foundation/urls
import merenda/nimkit/text/markdownviews

const
  RepositoryRoot = currentSourcePath().parentDir.parentDir
  TestImagePath = RepositoryRoot / "data" / "img1.png"
  TestBody = "cached asset payload"
  LargeTestBody = "asset body larger than four bytes"

type
  TestServerState = object
    port: Atomic[int]
    requestCount: Atomic[int]
    failed: Atomic[bool]
    statusCode: int
    bodyKind: int

  TestServer = ref object
    state: ptr TestServerState
    thread: Thread[ptr TestServerState]

proc responseBody(state: ptr TestServerState): string =
  case state.bodyKind
  of 1:
    LargeTestBody
  of 2:
    readFile(TestImagePath)
  else:
    TestBody

proc serveOneRequest(state: ptr TestServerState) {.thread.} =
  try:
    let server = newSocket(buffered = true)
    defer:
      server.close()
    server.setSockOpt(OptReuseAddr, true)
    server.bindAddr(Port(0), "127.0.0.1")
    server.listen()
    let (_, port) = server.getLocalAddr()
    state.port.store(port.int, moRelease)

    var descriptors = @[server.getFd()]
    if nativesockets.selectRead(descriptors, 5_000) == 0:
      state.failed.store(true, moRelease)
      return

    var client: owned Socket
    server.accept(client)
    defer:
      client.close()
    while true:
      let line = client.recvLine(timeout = 2_000)
      if line.len == 0 or line == "\r\n":
        break

    let
      body = state.responseBody()
      reason = if state.statusCode == 200: "OK" else: "Not Found"
      contentType = if state.bodyKind == 2: "image/png" else: "application/octet-stream"
      response =
        "HTTP/1.1 " & $state.statusCode & " " & reason & "\r\n" & "Content-Length: " &
        $body.len & "\r\n" & "Content-Type: " & contentType & "\r\n" &
        "Connection: close\r\n\r\n" & body
    client.send(response)
    discard state.requestCount.fetchAdd(1, moRelaxed)
  except Exception:
    state.failed.store(true, moRelease)

proc newTestServer(statusCode = 200, bodyKind = 0): TestServer =
  result =
    TestServer(state: cast[ptr TestServerState](allocShared0(sizeof(TestServerState))))
  result.state.statusCode = statusCode
  result.state.bodyKind = bodyKind
  result.state.port.store(0, moRelaxed)
  result.state.requestCount.store(0, moRelaxed)
  result.state.failed.store(false, moRelaxed)
  createThread(result.thread, serveOneRequest, result.state)

  let deadline = getMonoTime() + initDuration(seconds = 2)
  while result.state.port.load(moAcquire) == 0 and
      not result.state.failed.load(moAcquire) and getMonoTime() < deadline:
    sleep(1)
  doAssert result.state.port.load(moAcquire) > 0, "test HTTP server did not start"

proc close(server: TestServer) =
  if server.isNil or server.state.isNil:
    return
  server.thread.joinThread()
  deallocShared(server.state)
  server.state = nil

proc url(server: TestServer, path: string): string =
  "http://127.0.0.1:" & $server.state.port.load(moAcquire) & path

suite "URL asset loader":
  test "uses the platform application cache directory":
    let applicationIdentifier = "org.example.merenda-tests"
    check applicationIdentifier.urlAssetCacheDirectory() ==
      $(appdirs.getCacheDir(Path(applicationIdentifier)) / Path("url-assets"))
    expect ValueError:
      discard urlAssetCacheDirectory("  ")

  test "downloads on a Chronos worker and reuses the cached asset":
    let
      cache = createTempDir("merenda-url-assets-", "")
      server = newTestServer()
      assetUrl = initUrl(server.url("/images/icon.PNG?version=1"))
      mainThreadId = getThreadId()
    defer:
      removeDir(cache)
    defer:
      server.close()

    let loader = newUrlAssetLoader("org.example.merenda-tests", cache)
    defer:
      loader.close()

    let
      handle = loader.load(assetUrl)
      duplicate = loader.load(assetUrl)
    check duplicate == handle
    check loader.pendingCount() == 1
    check loader.waitFor(handle, 5_000)
    check handle.succeeded()
    check handle.result().state == ualsReady
    check handle.result().urlValue() == assetUrl
    check handle.result().statusCode == 200
    check handle.result().mediaType == "application/octet-stream"
    check handle.result().byteLength == TestBody.len.int64
    check handle.result().workerThreadId != mainThreadId
    check not handle.result().cacheHit
    check handle.result().path.endsWith(".png")
    check readFile(handle.result().path) == TestBody
    check loader.pendingCount() == 0

    server.close()
    check server.state.isNil
    let cached = loader.load(assetUrl)
    check cached.isFinished()
    check cached.result().cacheHit
    check cached.result().workerThreadId == -1
    check cached.result().path == handle.result().path
    check cached.result().mediaType == "application/octet-stream"

  test "reports HTTP errors without leaving partial files":
    let
      cache = createTempDir("merenda-url-assets-", "")
      server = newTestServer(statusCode = 404)
      assetUrl = server.url("/missing.dat")
    defer:
      removeDir(cache)
    defer:
      server.close()

    let loader = newUrlAssetLoader("org.example.merenda-tests", cache)
    defer:
      loader.close()
    let handle = loader.load(assetUrl)

    check loader.waitFor(handle, 5_000)
    check handle.state() == ualsFailed
    check handle.result().statusCode == 404
    check handle.result().errorMessage.contains("404")
    check not fileExists(loader.cachedAssetPath(assetUrl))

  test "enforces the configured asset size limit":
    let
      cache = createTempDir("merenda-url-assets-", "")
      server = newTestServer(bodyKind = 1)
      assetUrl = server.url("/large.bin")
    defer:
      removeDir(cache)
    defer:
      server.close()

    let loader =
      newUrlAssetLoader("org.example.merenda-tests", cache, maximumAssetBytes = 4)
    defer:
      loader.close()
    let handle = loader.load(assetUrl)

    check loader.waitFor(handle, 5_000)
    check handle.state() == ualsFailed
    check handle.result().errorMessage.contains("4 byte limit")
    check not fileExists(loader.cachedAssetPath(assetUrl))

  test "Markdown views rerender remote images after asynchronous loading":
    let
      cache = createTempDir("merenda-markdown-url-assets-", "")
      server = newTestServer(bodyKind = 2)
      assetUrl = server.url("/remote-image")
    defer:
      removeDir(cache)
    defer:
      server.close()

    let loader = newUrlAssetLoader("org.example.merenda-tests", cache)
    defer:
      loader.close()
    let view = newMarkdownView(
      "![Remote preview](" & assetUrl & ")\n\n" &
        "<img alt=\"HTML remote preview\" src=\"" & assetUrl & "\" />",
      urlAssetLoader = loader,
    )
    require view.waitForMarkdownParsing()
    check view.markdownParseError() == ""

    check view.urlAssetLoader() == loader
    check view.textView().attachmentPresentations().len == 0
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while loader.pendingCount() > 0 and getMonoTime() < deadline:
      discard loader.poll()
      if loader.pendingCount() > 0:
        sleep(1)
    discard loader.poll()

    check loader.pendingCount() == 0
    require view.waitForMarkdownRendering()
    check view.textView().attachmentPresentations().len == 2
    check view.textView().attachmentPresentations()[0].attachment.contentType ==
      "image/png"
    check server.state.requestCount.load(moAcquire) == 1
    check fileExists(loader.cachedAssetPath(assetUrl))

  test "validates URLs and rejects loads after closing":
    let cache = createTempDir("merenda-url-assets-", "")
    defer:
      removeDir(cache)
    let loader = newUrlAssetLoader("org.example.merenda-tests", cache)

    expect ValueError:
      discard loader.load("file:///tmp/not-a-remote-asset")
    expect ValueError:
      discard loader.load("https://")
    loader.close()
    check loader.isClosed()
    expect UrlAssetLoaderClosedError:
      discard loader.load("https://example.com/asset.png")
