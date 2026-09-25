## Asynchronous URL-backed assets cached in the platform application cache.

import std/[appdirs, monotimes, os, paths, strutils, tables, times]
from std/uri import Uri, parseUri

import chronos
import chronos/apps/http/httpclient
import chronos/streams/asyncstream
import crunchy/[common, sha256]
import sigils/[core, threads]

import ./urls

const
  DefaultUrlAssetMaximumBytes* = 64 * 1024 * 1024 ## Default per-asset size limit.
  DefaultUrlAssetConcurrentLoads* = 4
  DefaultUrlAssetPendingLoads* = 256
  UrlAssetReadBufferBytes = 32 * 1024
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
    mediaType*: string ## Normalized response media type or URL-derived fallback.
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

  UrlAssetRequest = object
    identifier: uint64
    url, path: string
    maximumAssetBytes: int

  UrlAssetWorker = ref object of AgentActor
    session: HttpSessionRef
    tasks: Table[uint64, Future[void]]
    pending: seq[UrlAssetRequest]
    maximumConcurrentLoads: int
    maximumPendingLoads: int
    closing: bool
    closeStarted: bool

  UrlAssetLoader* = ref object of Agent ## Reusable URL downloader and disk cache.
    xThread: SigilChronosThreadPtr
    xWorker: AgentProxy[UrlAssetWorker]
    xCacheDirectory: string
    xMaximumAssetBytes: int
    xMaximumPendingLoads: int
    xActive: Table[uint64, UrlAssetHandle]
    xActiveUrls: Table[string, UrlAssetHandle]
    xNextIdentifier: uint64
    xWorkerClosed: bool
    xClosed: bool

  UrlAssetHttpResponse = object
    status: int
    byteLength: int64
    limitExceeded: bool
    mediaType: string

proc validateUrlAssetUrl(url: string): urls.Url =
  if url.len == 0:
    raise newException(ValueError, "URL asset URL cannot be empty")
  result = initUrl(url)
  if not result.isHttpUrl():
    raise newException(ValueError, "URL asset URL must use HTTP or HTTPS: " & url)

func safeAssetExtension(url: urls.Url): string =
  let extension = url.pathExtension()
  if extension.len notin 1 .. 15:
    return
  for character in extension:
    if not character.isAlphaNumeric:
      return
  "." & extension

proc urlAssetFileName(url: string): string =
  let parsedUrl = url.validateUrlAssetUrl()
  sha256(url).toHex() & parsedUrl.safeAssetExtension()

func urlAssetMetadataPath(path: string): string =
  path & ".media-type"

proc cachedUrlAssetMediaType(url, path: string): string =
  let metadataPath = path.urlAssetMetadataPath()
  if fileExists(metadataPath):
    try:
      result = readFile(metadataPath).normalizedMediaType()
    except OSError:
      discard
  if result.len == 0:
    result = initUrl(url).mediaType()

proc fetchUrlAsset(
    session: HttpSessionRef, url: Uri, path: string, maximumAssetBytes: int
): Future[UrlAssetHttpResponse] {.async.} =
  let address = getHttpAddress(url).valueOr:
    raiseHttpAddressError($error)
  var
    request = HttpClientRequestRef.new(session, address)
    response: HttpClientResponseRef
    redirect: HttpClientRequestRef
    reader: HttpBodyReader
  try:
    while true:
      response = await request.send()
      if response.status in 300 .. 399:
        if "location" notin response.headers:
          raiseHttpRedirectError("Location header missing")
        let location = response.headers.getString("location")
        if location.len == 0:
          raiseHttpRedirectError("Location header with an empty value")
        let redirected = request.redirect(parseUri(location))
        if redirected.isErr():
          raiseHttpRedirectError(redirected.error())
        redirect = redirected.get()
        # Redirect bodies are irrelevant; close without downloading them.
        await response.closeWait()
        response = nil
        await request.closeWait()
        request = redirect
        redirect = nil
      else:
        result.status = response.status
        result.mediaType =
          response.headers.getString(ContentTypeHeader).normalizedMediaType()
        if response.status notin 200 .. 299:
          return
        reader = response.getBodyReader()
        var file = open(path, fmWrite)
        defer:
          file.close()
        var buffer: array[UrlAssetReadBufferBytes, byte]
        while true:
          let remaining = maximumAssetBytes - result.byteLength.int
          # Probe one byte at the boundary, including chunked/unknown-size bodies.
          let count =
            await reader.readOnce(addr buffer[0], max(1, min(buffer.len, remaining)))
          if count == 0:
            break
          if count > remaining:
            result.limitExceeded = true
            return
          if file.writeBuffer(addr buffer[0], count) != count:
            raise newException(IOError, "Unable to write URL asset")
          result.byteLength += count
        await reader.closeWait()
        reader = nil
        await response.finish()
        return
  finally:
    # Cancellation must finish releasing readers, sockets and redirected requests.
    if not reader.isNil:
      await noCancel(reader.closeWait())
    if not response.isNil:
      await noCancel(response.closeWait())
    if not request.isNil:
      await noCancel(request.closeWait())
    if not redirect.isNil:
      await noCancel(redirect.closeWait())

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

func urlValue*(loadResult: UrlAssetResult): urls.Url =
  ## Return the requested location as a parsed Foundation URL.
  initUrl(loadResult.url)

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

proc cachedAssetPath*(loader: UrlAssetLoader, url: urls.Url): string =
  ## Return the deterministic cache path for a parsed `url` without loading it.
  loader.cachedAssetPath(url.absoluteString())

func urlAssetCacheBaseName(fileName: string): string =
  var candidate = fileName
  if candidate.endsWith(".media-type"):
    candidate.setLen(candidate.len - ".media-type".len)
  if candidate.len < 64:
    return
  for character in candidate[0 ..< 64]:
    if character notin {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}:
      return
  if candidate.len > 64:
    if candidate[64] != '.' or candidate.len notin 66 .. 80:
      return
    for character in candidate[65 .. ^1]:
      if not character.isAlphaNumeric:
        return
  candidate

proc removeCachedAssetFiles(path: string): bool =
  for candidate in [path, path.urlAssetMetadataPath()]:
    if fileExists(candidate):
      removeFile(candidate)
      result = true

proc removeCachedAsset*(loader: UrlAssetLoader, url: string): bool =
  ## Remove the cached file and media-type metadata for one completed asset.
  ##
  ## An in-flight asset is left alone and returns false, so its worker cannot
  ## race a cache deletion. This does not invalidate handles already returned.
  if loader.isNil:
    raise newException(UrlAssetLoaderClosedError, "URL asset loader is nil")
  discard url.validateUrlAssetUrl()
  if url in loader.xActiveUrls:
    return
  removeCachedAssetFiles(loader.cachedAssetPath(url))

proc removeCachedAsset*(loader: UrlAssetLoader, url: urls.Url): bool =
  ## Remove one completed asset addressed by a parsed URL.
  loader.removeCachedAsset(url.absoluteString())

proc clearCachedAssets*(loader: UrlAssetLoader): int {.discardable.} =
  ## Remove completed URL assets owned by this loader's cache directory.
  ##
  ## Only deterministic URL asset names are touched. Unrelated files and
  ## in-flight assets remain intact. The result is the number of asset entries
  ## removed; a data file and its metadata count as one entry.
  if loader.isNil:
    raise newException(UrlAssetLoaderClosedError, "URL asset loader is nil")
  if not dirExists(loader.xCacheDirectory):
    return

  var paths = initTable[string, bool]()
  for kind, path in walkDir(loader.xCacheDirectory):
    if kind != pcFile:
      continue
    let baseName = path.extractFilename().urlAssetCacheBaseName()
    if baseName.len > 0:
      paths[loader.xCacheDirectory / baseName] = true

  for path in paths.keys:
    var active = false
    for url in loader.xActiveUrls.keys:
      if loader.cachedAssetPath(url) == path:
        active = true
        break
    if not active and removeCachedAssetFiles(path):
      inc result

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

proc startQueuedLoads(worker: UrlAssetWorker) {.raises: [], gcsafe.}

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
    createDir(path.parentDir())
    let response = await worker.session.fetchUrlAsset(
      parseUri(url), temporaryPath, maximumAssetBytes
    )
    loadResult.statusCode = response.status
    loadResult.mediaType = response.mediaType
    if loadResult.mediaType.len == 0:
      loadResult.mediaType = initUrl(url).mediaType()
    if response.status notin 200 .. 299:
      loadResult.errorMessage = "HTTP request returned status " & $response.status
    elif response.limitExceeded:
      loadResult.errorMessage =
        "URL asset exceeds the " & $maximumAssetBytes & " byte limit"
    else:
      if fileExists(path):
        removeFile(temporaryPath)
        loadResult.cacheHit = true
        loadResult.byteLength = getFileSize(path)
      else:
        moveFile(temporaryPath, path)
        loadResult.byteLength = response.byteLength
      if loadResult.mediaType.len > 0:
        try:
          writeFile(path.urlAssetMetadataPath(), loadResult.mediaType)
        except OSError:
          discard
      loadResult.path = path
      loadResult.state = ualsReady
  except CancelledError:
    loadResult.state = ualsCancelled
    loadResult.errorMessage = "URL asset load was cancelled"
  except Defect:
    raise
  except Exception:
    # std/os.moveFile exposes Exception in its effect contract. Programming
    # defects still propagate through the preceding branch.
    loadResult.errorMessage = getCurrentExceptionMsg()
  finally:
    if fileExists(temporaryPath):
      try:
        removeFile(temporaryPath)
      except OSError:
        discard

  worker.tasks.del(identifier)
  worker.notifyLoadFinished(identifier, loadResult)
  if worker.closing:
    if worker.tasks.len == 0:
      await worker.finishClosing()
  else:
    worker.startQueuedLoads()

proc startQueuedLoads(worker: UrlAssetWorker) {.raises: [], gcsafe.} =
  while not worker.closing and worker.pending.len > 0 and
      worker.tasks.len < worker.maximumConcurrentLoads:
    let request = worker.pending[0]
    worker.pending.delete(0)
    let task = worker.loadUrlAsset(
      request.identifier, request.url, request.path, request.maximumAssetBytes
    )
    worker.tasks[request.identifier] = task
    asyncSpawn task

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
  if worker.tasks.len + worker.pending.len >= worker.maximumPendingLoads:
    worker.notifyLoadFinished(
      identifier,
      UrlAssetResult(
        url: url,
        state: ualsFailed,
        workerThreadId: getThreadId(),
        errorMessage: "URL asset request queue is full",
      ),
    )
    return
  worker.pending.add UrlAssetRequest(
    identifier: identifier, url: url, path: path, maximumAssetBytes: maximumAssetBytes
  )
  worker.startQueuedLoads()

proc cancelUrlAssetLoad(worker: UrlAssetWorker, identifier: uint64) {.slot.} =
  if identifier in worker.tasks:
    worker.tasks[identifier].cancelSoon()
  else:
    for index, request in worker.pending:
      if request.identifier == identifier:
        worker.notifyLoadFinished(
          identifier,
          UrlAssetResult(
            url: request.url,
            state: ualsCancelled,
            errorMessage: "URL asset load was cancelled",
          ),
        )
        worker.pending.delete(index)
        return

proc closeUrlAssetWorker(worker: UrlAssetWorker) {.slot.} =
  if worker.closing:
    return
  worker.closing = true
  for request in worker.pending:
    worker.notifyLoadFinished(
      request.identifier,
      UrlAssetResult(
        url: request.url,
        state: ualsCancelled,
        errorMessage: "URL asset loader is closing",
      ),
    )
  worker.pending.setLen(0)
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
    maximumConcurrentLoads: Positive = DefaultUrlAssetConcurrentLoads,
    maximumPendingLoads: Positive = DefaultUrlAssetPendingLoads,
): UrlAssetLoader =
  ## Start a reusable Chronos-backed loader for one application's URL assets.
  ## Responses stream to disk with a fixed-size buffer and stop at the byte limit.
  ## `maximumPendingLoads` bounds active plus queued requests; duplicate URLs share
  ## one request. Concurrent network transfers are limited independently.
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
    xMaximumPendingLoads: maximumPendingLoads,
    xActive: initTable[uint64, UrlAssetHandle](),
    xActiveUrls: initTable[string, UrlAssetHandle](),
  )
  result.xThread.start()

  var worker = UrlAssetWorker(
    tasks: initTable[uint64, Future[void]](),
    maximumConcurrentLoads: maximumConcurrentLoads,
    maximumPendingLoads: maximumPendingLoads,
  )
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
  if fileExists(path) and getFileSize(path) > loader.xMaximumAssetBytes:
    result.xResult.state = ualsFailed
    result.xResult.errorMessage =
      "Cached URL asset exceeds the " & $loader.xMaximumAssetBytes & " byte limit"
    emit loader.urlAssetDidFinish(result)
  elif fileExists(path):
    result.xResult = UrlAssetResult(
      url: url,
      path: path,
      mediaType: cachedUrlAssetMediaType(url, path),
      state: ualsReady,
      byteLength: getFileSize(path),
      cacheHit: true,
      workerThreadId: -1,
    )
    emit loader.urlAssetDidFinish(result)
  elif loader.xActive.len >= loader.xMaximumPendingLoads:
    # Bound handles and cross-thread messages before enqueuing worker work.
    result.xResult.state = ualsFailed
    result.xResult.errorMessage = "URL asset request queue is full"
    emit loader.urlAssetDidFinish(result)
  else:
    loader.xActive[result.xIdentifier] = result
    loader.xActiveUrls[url] = result
    emit loader.xWorker.executeUrlAssetLoad(
      result.xIdentifier, url, path, loader.xMaximumAssetBytes
    )

proc load*(loader: UrlAssetLoader, url: urls.Url): UrlAssetHandle {.discardable.} =
  ## Load a parsed HTTP or HTTPS URL.
  loader.load(url.absoluteString())

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
