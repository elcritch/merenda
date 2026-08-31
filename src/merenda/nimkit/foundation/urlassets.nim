## Asynchronous URL-backed assets cached in the platform application cache.

import std/[appdirs, monotimes, os, paths, strutils, tables, times, uri]

import chronos
import chronos/apps/http/httpclient
import crunchy/[common, sha256]
import sigils/[core, threads]

const
  DefaultUrlAssetMaximumBytes* = 64 * 1024 * 1024 ## Default per-asset size limit.
  UrlAssetCacheDirectoryName = "url-assets"

type
  UrlAssetLoadState* = enum ## Current state of a URL asset request.
    ualsPending ## The worker has not completed the request.
    ualsReady ## The asset is available at `UrlAssetResult.path`.
    ualsFailed ## The request or cache write failed.
    ualsCancelled ## The request was cancelled before completion.

  UrlAssetResult* = object ## Completed URL asset request details.
    url*: string ## Requested HTTP or HTTPS URL.
    path*: string ## Cached file path when `state` is `ualsReady`.
    state*: UrlAssetLoadState ## Final request state.
    statusCode*: int ## HTTP status, or zero if no response was received.
    byteLength*: int64 ## Size of the ready cached file in bytes.
    cacheHit*: bool ## Whether an existing cache file satisfied the request.
    errorMessage*: string ## Failure or cancellation details, if any.
    workerThreadId*: int ## Worker thread ID, or `-1` for an immediate cache hit.

  UrlAssetPendingError* = object of CatchableError ## Raised for a pending result.
  UrlAssetLoaderClosedError* = object of CatchableError ## Raised after shutdown.

  UrlAssetHandle* = ref object ## Stable handle for one coalesced URL request.
    xIdentifier: uint64
    xResult: UrlAssetResult

  UrlAssetWorker = ref object of AgentActor
    session: HttpSessionRef
    tasks: Table[uint64, Future[void]]
    closing: bool
    closeStarted: bool

  UrlAssetLoader* = ref object of Agent ## Reusable URL downloader and disk cache.
    xThread: SigilChronosThreadPtr
    xWorker: AgentProxy[UrlAssetWorker]
    xCacheDirectory: string
    xMaximumAssetBytes: int
    xActive: Table[uint64, UrlAssetHandle]
    xActiveUrls: Table[string, UrlAssetHandle]
    xNextIdentifier: uint64
    xWorkerClosed: bool
    xClosed: bool

proc validateUrlAssetUrl(url: string): Uri =
  if url.len == 0:
    raise newException(ValueError, "URL asset URL cannot be empty")
  result = parseUri(url)
  if result.scheme.toLowerAscii() notin ["http", "https"] or result.hostname.len == 0:
    raise newException(ValueError, "URL asset URL must use HTTP or HTTPS: " & url)

func safeAssetExtension(uri: Uri): string =
  let extension = splitFile(uri.path).ext
  if extension.len notin 2 .. 16:
    return
  for index in 1 ..< extension.len:
    if not extension[index].isAlphaNumeric:
      return
  extension.toLowerAscii()

proc urlAssetFileName(url: string): string =
  let uri = url.validateUrlAssetUrl()
  sha256(url).toHex() & uri.safeAssetExtension()

proc urlAssetCacheDirectory*(applicationIdentifier: string): string =
  ## Return the platform cache directory used for one application's URL assets.
  ##
  ## This follows `std/appdirs`: LocalAppData on Windows, Library/Caches on
  ## macOS, and XDG_CACHE_HOME (or ~/.cache) on Linux and BSD.
  if applicationIdentifier.strip().len == 0:
    raise newException(ValueError, "application identifier cannot be empty")
  $(appdirs.getCacheDir(Path(applicationIdentifier)) / Path(UrlAssetCacheDirectoryName))

func identifier*(handle: UrlAssetHandle): uint64 =
  ## Return the request identifier, or zero for a nil handle.
  if not handle.isNil:
    result = handle.xIdentifier

func state*(handle: UrlAssetHandle): UrlAssetLoadState =
  ## Return the handle's current load state.
  if not handle.isNil:
    result = handle.xResult.state

func isFinished*(handle: UrlAssetHandle): bool =
  ## Return whether the request reached a terminal state.
  not handle.isNil and handle.xResult.state != ualsPending

func succeeded*(handle: UrlAssetHandle): bool =
  ## Return whether the asset is ready in the disk cache.
  not handle.isNil and handle.xResult.state == ualsReady

func result*(handle: UrlAssetHandle): lent UrlAssetResult =
  ## Return the completed load result, or raise while the load is pending.
  if handle.isNil or not handle.isFinished():
    raise newException(UrlAssetPendingError, "URL asset has not finished loading")
  handle.xResult

proc cacheDirectory*(loader: UrlAssetLoader): string =
  ## Return the loader's absolute cache directory.
  if not loader.isNil:
    result = loader.xCacheDirectory

func maximumAssetBytes*(loader: UrlAssetLoader): int =
  ## Return the maximum response size accepted for one asset.
  if not loader.isNil:
    result = loader.xMaximumAssetBytes

func isClosed*(loader: UrlAssetLoader): bool =
  ## Return whether the worker has been shut down.
  loader.isNil or loader.xClosed

func pendingCount*(loader: UrlAssetLoader): int =
  ## Return the number of distinct in-flight URLs.
  if not loader.isNil:
    result = loader.xActive.len

proc cachedAssetPath*(loader: UrlAssetLoader, url: string): string =
  ## Return the deterministic cache path for `url` without loading it.
  if loader.isNil:
    raise newException(UrlAssetLoaderClosedError, "URL asset loader is nil")
  loader.xCacheDirectory / url.urlAssetFileName()

proc executeUrlAssetLoad(
  worker: AgentProxy[UrlAssetWorker],
  identifier: uint64,
  url: string,
  path: string,
  maximumAssetBytes: int,
) {.signal.}

proc cancelUrlAssetLoad(
  worker: AgentProxy[UrlAssetWorker], identifier: uint64
) {.signal.}

proc closeUrlAssetWorker(worker: AgentProxy[UrlAssetWorker]) {.signal.}

proc urlAssetLoadFinished(
  worker: UrlAssetWorker, identifier: uint64, loadResult: UrlAssetResult
) {.signal.}

proc urlAssetWorkerDidClose(worker: UrlAssetWorker) {.signal.}

proc notifyWorkerClosed(worker: UrlAssetWorker) {.raises: [].} =
  try:
    emit worker.urlAssetWorkerDidClose()
  except Exception:
    discard

proc notifyLoadFinished(
    worker: UrlAssetWorker, identifier: uint64, loadResult: UrlAssetResult
) {.raises: [].} =
  try:
    emit worker.urlAssetLoadFinished(identifier, loadResult)
  except Exception:
    discard

proc finishClosing(worker: UrlAssetWorker): Future[void] {.async: (raises: []).} =
  if worker.closeStarted:
    return
  worker.closeStarted = true
  if not worker.session.isNil:
    await worker.session.closeWait()
    worker.session = nil
  worker.notifyWorkerClosed()

proc loadUrlAsset(
    worker: UrlAssetWorker,
    identifier: uint64,
    url: string,
    path: string,
    maximumAssetBytes: int,
): Future[void] {.async: (raises: []).} =
  var loadResult =
    UrlAssetResult(url: url, state: ualsFailed, workerThreadId: getThreadId())
  let temporaryPath = path & ".part-" & $identifier
  try:
    # Let the launching slot record this task before it can finish or be cancelled.
    await sleepAsync(ZeroDuration)
    if worker.session.isNil:
      worker.session = HttpSessionRef.new()
    let response = await worker.session.fetch(parseUri(url))
    loadResult.statusCode = response.status
    if response.status notin 200 .. 299:
      loadResult.errorMessage = "HTTP request returned status " & $response.status
    elif response.data.len > maximumAssetBytes:
      loadResult.errorMessage =
        "URL asset exceeds the " & $maximumAssetBytes & " byte limit"
    else:
      createDir(path.parentDir())
      writeFile(temporaryPath, response.data)
      if fileExists(path):
        removeFile(temporaryPath)
        loadResult.cacheHit = true
        loadResult.byteLength = getFileSize(path)
      else:
        moveFile(temporaryPath, path)
        loadResult.byteLength = response.data.len.int64
      loadResult.path = path
      loadResult.state = ualsReady
  except CancelledError:
    loadResult.state = ualsCancelled
    loadResult.errorMessage = "URL asset load was cancelled"
  except Exception:
    loadResult.errorMessage = getCurrentExceptionMsg()
  finally:
    if fileExists(temporaryPath):
      try:
        removeFile(temporaryPath)
      except OSError:
        discard

  worker.tasks.del(identifier)
  worker.notifyLoadFinished(identifier, loadResult)
  if worker.closing and worker.tasks.len == 0:
    await worker.finishClosing()

proc executeUrlAssetLoad(
    worker: UrlAssetWorker,
    identifier: uint64,
    url: string,
    path: string,
    maximumAssetBytes: int,
) {.slot.} =
  if worker.closing:
    emit worker.urlAssetLoadFinished(
      identifier,
      UrlAssetResult(
        url: url,
        state: ualsCancelled,
        errorMessage: "URL asset loader is closing",
        workerThreadId: getThreadId(),
      ),
    )
    return
  let task = worker.loadUrlAsset(identifier, url, path, maximumAssetBytes)
  worker.tasks[identifier] = task
  asyncSpawn task

proc cancelUrlAssetLoad(worker: UrlAssetWorker, identifier: uint64) {.slot.} =
  if identifier in worker.tasks:
    worker.tasks[identifier].cancelSoon()

proc closeUrlAssetWorker(worker: UrlAssetWorker) {.slot.} =
  if worker.closing:
    return
  worker.closing = true
  var tasks: seq[Future[void]]
  for task in worker.tasks.values:
    tasks.add task
  for task in tasks:
    task.cancelSoon()
  if tasks.len == 0:
    asyncSpawn worker.finishClosing()

proc urlAssetDidFinish*(loader: UrlAssetLoader, handle: UrlAssetHandle) {.signal.}
  ## Emitted on the owning thread for ready, failed, and cancelled loads.

proc completeUrlAssetLoad(
    loader: UrlAssetLoader, identifier: uint64, loadResult: UrlAssetResult
) {.slot.} =
  if identifier notin loader.xActive:
    return
  let handle = loader.xActive[identifier]
  loader.xActive.del(identifier)
  if loadResult.url in loader.xActiveUrls and
      loader.xActiveUrls[loadResult.url] == handle:
    loader.xActiveUrls.del(loadResult.url)
  handle.xResult = loadResult
  emit loader.urlAssetDidFinish(handle)

proc completeUrlAssetWorkerClose(loader: UrlAssetLoader) {.slot.} =
  loader.xWorkerClosed = true

proc newUrlAssetLoader*(
    applicationIdentifier: string,
    cacheDirectory = "",
    maximumAssetBytes: Positive = DefaultUrlAssetMaximumBytes,
): UrlAssetLoader =
  ## Start a reusable Chronos-backed loader for one application's URL assets.
  ##
  ## By default, files are stored beneath the platform application cache. Pass
  ## `cacheDirectory` to override that location, primarily for tests or tools.
  let resolvedCacheDirectory =
    if cacheDirectory.len > 0:
      absolutePath(cacheDirectory)
    else:
      applicationIdentifier.urlAssetCacheDirectory()
  createDir(resolvedCacheDirectory)
  startLocalThreadDefault()
  result = UrlAssetLoader(
    xThread: newSigilChronosThread(),
    xCacheDirectory: resolvedCacheDirectory,
    xMaximumAssetBytes: maximumAssetBytes,
    xActive: initTable[uint64, UrlAssetHandle](),
    xActiveUrls: initTable[string, UrlAssetHandle](),
  )
  result.xThread.start()

  var worker = UrlAssetWorker(tasks: initTable[uint64, Future[void]]())
  result.xWorker = worker.moveToThread(result.xThread)
  connectThreaded(
    result.xWorker,
    executeUrlAssetLoad,
    result.xWorker,
    UrlAssetWorker.executeUrlAssetLoad(),
  )
  connectThreaded(
    result.xWorker,
    cancelUrlAssetLoad,
    result.xWorker,
    UrlAssetWorker.cancelUrlAssetLoad(),
  )
  connectThreaded(
    result.xWorker,
    closeUrlAssetWorker,
    result.xWorker,
    UrlAssetWorker.closeUrlAssetWorker(),
  )
  connectThreaded(
    result.xWorker, urlAssetLoadFinished, result, UrlAssetLoader.completeUrlAssetLoad()
  )
  connectThreaded(
    result.xWorker,
    urlAssetWorkerDidClose,
    result,
    UrlAssetLoader.completeUrlAssetWorkerClose(),
  )

proc load*(loader: UrlAssetLoader, url: string): UrlAssetHandle {.discardable.} =
  ## Load `url`, reusing an existing cached file or in-flight request.
  if loader.isNil or loader.xClosed:
    raise newException(UrlAssetLoaderClosedError, "URL asset loader is closed")
  discard url.validateUrlAssetUrl()
  if url in loader.xActiveUrls:
    return loader.xActiveUrls[url]

  inc loader.xNextIdentifier
  let path = loader.cachedAssetPath(url)
  result = UrlAssetHandle(
    xIdentifier: loader.xNextIdentifier,
    xResult: UrlAssetResult(url: url, state: ualsPending),
  )
  if fileExists(path):
    result.xResult = UrlAssetResult(
      url: url,
      path: path,
      state: ualsReady,
      byteLength: getFileSize(path),
      cacheHit: true,
      workerThreadId: -1,
    )
    emit loader.urlAssetDidFinish(result)
  else:
    loader.xActive[result.xIdentifier] = result
    loader.xActiveUrls[url] = result
    emit loader.xWorker.executeUrlAssetLoad(
      result.xIdentifier, url, path, loader.xMaximumAssetBytes
    )

proc cancel*(loader: UrlAssetLoader, handle: UrlAssetHandle) =
  ## Cancel an in-flight load. Coalesced callers share the same handle.
  if loader.isNil or loader.xClosed or handle.isNil or handle.isFinished():
    return
  if handle.xIdentifier in loader.xActive and
      loader.xActive[handle.xIdentifier] == handle:
    emit loader.xWorker.cancelUrlAssetLoad(handle.xIdentifier)

proc poll*(loader: UrlAssetLoader): int {.discardable.} =
  ## Deliver worker results on the loader's owning thread.
  if not loader.isNil:
    getCurrentSigilThread().pollAll(NonBlocking)

proc waitFor*(
    loader: UrlAssetLoader,
    handle: UrlAssetHandle,
    timeoutMilliseconds: Natural = 30_000,
): bool {.discardable.} =
  ## Poll until `handle` finishes or the timeout expires.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
  while not handle.isFinished() and getMonoTime() < deadline:
    discard loader.poll()
    if not handle.isFinished():
      sleep(1)
  discard loader.poll()
  handle.isFinished()

proc close*(loader: UrlAssetLoader) =
  ## Cancel pending loads, close the HTTP session, and join the worker thread.
  if loader.isNil or loader.xClosed:
    return
  loader.xClosed = true
  emit loader.xWorker.closeUrlAssetWorker()
  while not loader.xWorkerClosed:
    discard loader.poll()
    if not loader.xWorkerClosed:
      sleep(1)
  loader.xWorker = nil
  loader.xThread.stop()
  loader.xThread.join()
  discard loader.poll()
  loader.xActive.clear()
  loader.xActiveUrls.clear()
