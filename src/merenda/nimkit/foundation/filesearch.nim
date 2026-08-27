## Asynchronous, memory-mapped regular-expression search for local files.

import std/[algorithm, atomics, monotimes, os, tables, times]

import faststreams/inputs
import regex
import sigils/[core, threads]
import threading/smartptrs

const
  DefaultFileSearchMaxResults* = 10_000
  DefaultFileSearchMaxMatchesPerFile* = 1_000
  DefaultFileSearchMaxFiles* = 100_000
  DefaultFileSearchMaxFileSizeBytes* = 16'i64 * 1024 * 1024
  FileSearchMatchBatchSize = 64
  FileSearchMatchBatchMaxDelayMilliseconds = 50

type
  FileSearchFinishReason* = enum
    fsfrCompleted
    fsfrCancelled
    fsfrResultLimitReached
    fsfrFileLimitReached

  FileSearchOptions* = object
    recursive*: bool
    includeHidden*: bool
    caseSensitive*: bool
    maxResults*: int
    maxMatchesPerFile*: int
    maxFiles*: int
    maxFileSizeBytes*: int64

  FileSearchQuery* = object
    rootPath*: string
    pattern*: string
    options*: FileSearchOptions

  FileSearchMatch* = object
    path*: string
    line*, column*: int
    byteOffset*: int64
    matchLength*: int
    lineText*: string

  FileSearchStats* = object
    workerThreadId*: int
    discoveredFileCount*: int
    searchedFileCount*: int
    mappedFileCount*: int
    skippedLargeFileCount*: int
    failedFileCount*: int
    limitedFileCount*: int
    bytesSearched*: int64

  FileSearchResult* = object
    reason*: FileSearchFinishReason
    matches*: seq[FileSearchMatch]
    stats*: FileSearchStats

  FileSearchPendingError* = object of CatchableError
  FileSearchClosedError* = object of CatchableError

  FileSearchControl = object
    cancelled: Atomic[bool]

  FileSearchWorker = ref object of AgentActor

  FileSearchHandle* = ref object
    xIdentifier: uint64
    xControl: SharedPtr[FileSearchControl]
    xFinished: bool
    xResult: FileSearchResult

  FileSearchService* = ref object of Agent
    xPool: SigilThreadPoolPtr
    xWorkers: seq[AgentProxy[FileSearchWorker]]
    xActive: Table[uint64, FileSearchHandle]
    xNextIdentifier: uint64
    xNextWorker: int
    xClosed: bool

proc fileSearchMatchesFound(
  worker: FileSearchWorker, identifier: uint64, matches: seq[FileSearchMatch]
) {.signal.}

type FileSearchBatchState = object
  worker: FileSearchWorker
  identifier: uint64
  pendingMatches: seq[FileSearchMatch]
  lastPublishedAt: MonoTime
  hasPublished: bool

proc initFileSearchBatchState(
    worker: FileSearchWorker, identifier: uint64
): FileSearchBatchState =
  FileSearchBatchState(
    worker: worker,
    identifier: identifier,
    pendingMatches: newSeqOfCap[FileSearchMatch](FileSearchMatchBatchSize),
    lastPublishedAt: getMonoTime(),
  )

proc publish(batchState: var FileSearchBatchState) =
  if batchState.pendingMatches.len == 0:
    return
  let matches = move batchState.pendingMatches
  batchState.lastPublishedAt = getMonoTime()
  batchState.hasPublished = true
  emit batchState.worker.fileSearchMatchesFound(batchState.identifier, matches)

proc addMatch(batchState: var FileSearchBatchState, match: FileSearchMatch) =
  batchState.pendingMatches.add match
  if not batchState.hasPublished or
      batchState.pendingMatches.len == FileSearchMatchBatchSize:
    batchState.publish()

proc publishIfDue(batchState: var FileSearchBatchState) =
  if batchState.pendingMatches.len > 0 and
      getMonoTime() - batchState.lastPublishedAt >=
      initDuration(milliseconds = FileSearchMatchBatchMaxDelayMilliseconds):
    batchState.publish()

func initFileSearchOptions*(
    recursive = true,
    includeHidden = false,
    caseSensitive = true,
    maxResults: Positive = DefaultFileSearchMaxResults,
    maxMatchesPerFile: Positive = DefaultFileSearchMaxMatchesPerFile,
    maxFiles: Positive = DefaultFileSearchMaxFiles,
    maxFileSizeBytes: Positive = DefaultFileSearchMaxFileSizeBytes,
): FileSearchOptions =
  ## Configure traversal and resource limits for one search.
  FileSearchOptions(
    recursive: recursive,
    includeHidden: includeHidden,
    caseSensitive: caseSensitive,
    maxResults: maxResults,
    maxMatchesPerFile: maxMatchesPerFile,
    maxFiles: maxFiles,
    maxFileSizeBytes: maxFileSizeBytes,
  )

func initFileSearchQuery*(
    rootPath, pattern: string, options = initFileSearchOptions()
): FileSearchQuery =
  ## Create a regular-expression search rooted at `rootPath`.
  FileSearchQuery(rootPath: rootPath, pattern: pattern, options: options)

func identifier*(handle: FileSearchHandle): uint64 =
  if not handle.isNil:
    result = handle.xIdentifier

func isFinished*(handle: FileSearchHandle): bool =
  not handle.isNil and handle.xFinished

func cancelRequested*(handle: FileSearchHandle): bool =
  not handle.isNil and handle.xControl[].cancelled.load(moAcquire)

proc cancel*(handle: FileSearchHandle) =
  ## Request cooperative cancellation of directory traversal and file scanning.
  if not handle.isNil and not handle.xFinished:
    handle.xControl[].cancelled.store(true, moRelease)

func result*(handle: FileSearchHandle): lent FileSearchResult =
  ## Return the completed result, or raise while the search is still running.
  if handle.isNil or not handle.xFinished:
    raise newException(FileSearchPendingError, "file search has not finished")
  handle.xResult

func cancellationRequested(control: SharedPtr[FileSearchControl]): bool =
  control[].cancelled.load(moAcquire)

proc validate(query: FileSearchQuery) =
  if not dirExists(query.rootPath):
    raise
      newException(IOError, "file search root is not a directory: " & query.rootPath)
  if query.pattern.len == 0:
    raise newException(ValueError, "file search pattern cannot be empty")
  if query.options.maxResults <= 0:
    raise newException(ValueError, "maxResults must be positive")
  if query.options.maxMatchesPerFile <= 0:
    raise newException(ValueError, "maxMatchesPerFile must be positive")
  if query.options.maxFiles <= 0:
    raise newException(ValueError, "maxFiles must be positive")
  if query.options.maxFileSizeBytes <= 0:
    raise newException(ValueError, "maxFileSizeBytes must be positive")

proc searchPattern(query: FileSearchQuery): Regex2 =
  var flags = {regexArbitraryBytes}
  if not query.options.caseSensitive:
    flags.incl(regexCaseless)
  re2(query.pattern, flags)

func hiddenPath(path: string): bool =
  let name = path.extractFilename()
  name.len > 0 and name[0] == '.'

type FileSearchTraversalState = object
  options: FileSearchOptions
  control: SharedPtr[FileSearchControl]
  pendingDirectories: seq[string]
  pendingFiles: seq[string]
  nextFileIndex: int

proc initFileSearchTraversal(
    rootPath: string, options: FileSearchOptions, control: SharedPtr[FileSearchControl]
): FileSearchTraversalState =
  FileSearchTraversalState(
    options: options, control: control, pendingDirectories: @[absolutePath(rootPath)]
  )

proc nextSearchFile(
    traversal: var FileSearchTraversalState,
    stats: var FileSearchStats,
    reason: var FileSearchFinishReason,
    path: var string,
): bool =
  while traversal.nextFileIndex >= traversal.pendingFiles.len:
    traversal.pendingFiles.setLen(0)
    traversal.nextFileIndex = 0
    if traversal.control.cancellationRequested():
      reason = fsfrCancelled
      return
    if traversal.pendingDirectories.len == 0:
      return

    let directory = traversal.pendingDirectories.pop()
    var directories: seq[string]
    try:
      for kind, entryPath in walkDir(directory, relative = false):
        if traversal.control.cancellationRequested():
          break
        if traversal.options.includeHidden or not entryPath.hiddenPath():
          case kind
          of pcFile:
            traversal.pendingFiles.add entryPath
          of pcDir:
            if traversal.options.recursive:
              directories.add entryPath
          of pcLinkToFile, pcLinkToDir:
            discard
    except OSError:
      inc stats.failedFileCount

    if traversal.control.cancellationRequested():
      reason = fsfrCancelled
      return
    traversal.pendingFiles.sort()
    directories.sort(SortOrder.Descending)
    for entryPath in directories:
      traversal.pendingDirectories.add entryPath

  if stats.discoveredFileCount == traversal.options.maxFiles:
    reason = fsfrFileLimitReached
    return
  path = traversal.pendingFiles[traversal.nextFileIndex]
  inc traversal.nextFileIndex
  inc stats.discoveredFileCount
  result = true

proc addLineMatches(
    batchState: var FileSearchBatchState,
    path, lineText: string,
    lineNumber: int,
    lineByteOffset: int64,
    pattern: Regex2,
    options: FileSearchOptions,
    control: SharedPtr[FileSearchControl],
    fileMatchCount: var int,
    searchResult: var FileSearchResult,
): bool =
  for bounds in findAllBounds(lineText, pattern):
    if control.cancellationRequested():
      searchResult.reason = fsfrCancelled
      return false
    let match = FileSearchMatch(
      path: path,
      line: lineNumber,
      column: bounds.a + 1,
      byteOffset: lineByteOffset + bounds.a.int64,
      matchLength: max(bounds.b - bounds.a + 1, 0),
      lineText: lineText,
    )
    searchResult.matches.add match
    batchState.addMatch(match)
    inc fileMatchCount
    if searchResult.matches.len == options.maxResults:
      searchResult.reason = fsfrResultLimitReached
      return false
    if fileMatchCount == options.maxMatchesPerFile:
      inc searchResult.stats.limitedFileCount
      return false
  true

proc searchMappedFile(
    batchState: var FileSearchBatchState,
    path: string,
    pattern: Regex2,
    options: FileSearchOptions,
    control: SharedPtr[FileSearchControl],
    searchResult: var FileSearchResult,
) =
  let fileSize = getFileSize(path)
  if fileSize > options.maxFileSizeBytes:
    inc searchResult.stats.skippedLargeFileCount
    return
  if control.cancellationRequested():
    searchResult.reason = fsfrCancelled
    return

  var stream =
    if fileSize == 0:
      memFileInput(path)
    else:
      memFileInput(path, mappedSize = fileSize.int)
  try:
    inc searchResult.stats.searchedFileCount
    if fileSize > 0:
      inc searchResult.stats.mappedFileCount
    var
      lineText = newStringOfCap(min(fileSize, 4_096).int)
      lineNumber = 1
      lineByteOffset = 0'i64
      bytesRead = 0'i64
      fileMatchCount = 0
      keepSearching = true
    while keepSearching and stream.readable:
      let value = stream.read()
      inc bytesRead
      if value == byte('\n'):
        if lineText.len > 0 and lineText[^1] == '\r':
          lineText.setLen(lineText.len - 1)
        keepSearching = addLineMatches(
          batchState, path, lineText, lineNumber, lineByteOffset, pattern, options,
          control, fileMatchCount, searchResult,
        )
        lineText.setLen(0)
        inc lineNumber
        lineByteOffset = bytesRead
      else:
        lineText.add char(value)
      if (bytesRead and 0x3fff) == 0:
        batchState.publishIfDue()
        if control.cancellationRequested():
          searchResult.reason = fsfrCancelled
          keepSearching = false

    if keepSearching and lineText.len > 0:
      if lineText[^1] == '\r':
        lineText.setLen(lineText.len - 1)
      discard addLineMatches(
        batchState, path, lineText, lineNumber, lineByteOffset, pattern, options,
        control, fileMatchCount, searchResult,
      )
    searchResult.stats.bytesSearched += bytesRead
  finally:
    stream.close()

proc performFileSearch(
    worker: FileSearchWorker,
    identifier: uint64,
    query: FileSearchQuery,
    control: SharedPtr[FileSearchControl],
): FileSearchResult =
  var batchState = initFileSearchBatchState(worker, identifier)
  defer:
    batchState.publish()
  result.reason = fsfrCompleted
  result.stats.workerThreadId = getThreadId()
  let pattern = query.searchPattern()
  var
    traversal = initFileSearchTraversal(query.rootPath, query.options, control)
    path: string
  while traversal.nextSearchFile(result.stats, result.reason, path):
    try:
      searchMappedFile(batchState, path, pattern, query.options, control, result)
    except IOError, OSError:
      inc result.stats.failedFileCount
    if result.reason != fsfrCompleted:
      return
    batchState.publishIfDue()

proc executeFileSearch(
  worker: AgentProxy[FileSearchWorker],
  identifier: uint64,
  query: FileSearchQuery,
  control: SharedPtr[FileSearchControl],
) {.signal.}

proc fileSearchFinished(
  worker: FileSearchWorker, identifier: uint64, searchResult: FileSearchResult
) {.signal.}

proc executeFileSearch(
    worker: FileSearchWorker,
    identifier: uint64,
    query: FileSearchQuery,
    control: SharedPtr[FileSearchControl],
) {.slot.} =
  emit worker.fileSearchFinished(
    identifier, performFileSearch(worker, identifier, query, control)
  )

## Publishes ordered, non-empty match batches while the handle is still pending.
proc fileSearchDidFindMatches*(
  service: FileSearchService, handle: FileSearchHandle, matches: seq[FileSearchMatch]
) {.signal.}

proc fileSearchDidFinish*(
  service: FileSearchService, handle: FileSearchHandle
) {.signal.}

proc publishFileSearchMatches(
    service: FileSearchService, identifier: uint64, matches: seq[FileSearchMatch]
) {.slot.} =
  if service.xClosed or identifier notin service.xActive:
    return
  emit service.fileSearchDidFindMatches(service.xActive[identifier], matches)

proc completeFileSearch(
    service: FileSearchService, identifier: uint64, searchResult: FileSearchResult
) {.slot.} =
  if identifier notin service.xActive:
    return
  let handle = service.xActive[identifier]
  service.xActive.del(identifier)
  handle.xResult = searchResult
  if handle.cancelRequested():
    handle.xResult.reason = fsfrCancelled
  handle.xFinished = true
  emit service.fileSearchDidFinish(handle)

proc newFileSearchService*(workers: Positive = 2): FileSearchService =
  ## Start a reusable Sigils worker pool for asynchronous file searches.
  startLocalThreadDefault()
  result = FileSearchService(
    xPool: newSigilThreadPool(workers = workers),
    xActive: initTable[uint64, FileSearchHandle](),
  )
  result.xPool.start()
  for _ in 0 ..< workers:
    var worker = FileSearchWorker()
    let proxy = worker.moveToThread(result.xPool)
    connectThreaded(proxy, executeFileSearch, proxy, executeFileSearch)
    connectThreaded(
      proxy,
      fileSearchMatchesFound,
      result,
      FileSearchService.publishFileSearchMatches(),
    )
    connectThreaded(
      proxy, fileSearchFinished, result, FileSearchService.completeFileSearch()
    )
    result.xWorkers.add proxy

proc search*(
    service: FileSearchService, query: FileSearchQuery
): FileSearchHandle {.discardable.} =
  ## Queue one search and return a handle that can be cancelled or observed.
  if service.isNil or service.xClosed:
    raise newException(FileSearchClosedError, "file search service is closed")
  query.validate()
  discard query.searchPattern()

  inc service.xNextIdentifier
  let control = newSharedPtr(FileSearchControl)
  control[].cancelled.store(false, moRelaxed)
  result = FileSearchHandle(xIdentifier: service.xNextIdentifier, xControl: control)
  service.xActive[result.xIdentifier] = result
  let worker = service.xWorkers[service.xNextWorker]
  service.xNextWorker = (service.xNextWorker + 1) mod service.xWorkers.len
  emit worker.executeFileSearch(result.xIdentifier, query, control)

proc poll*(service: FileSearchService): int {.discardable.} =
  ## Deliver completed worker results on the service's owning thread.
  if not service.isNil:
    getCurrentSigilThread().pollAll()

proc waitFor*(
    service: FileSearchService,
    handle: FileSearchHandle,
    timeoutMilliseconds: Natural = 5_000,
): bool {.discardable.} =
  ## Poll until `handle` finishes or the timeout expires.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
  while not handle.isFinished() and getMonoTime() < deadline:
    discard service.poll()
    if not handle.isFinished():
      sleep(1)
  discard service.poll()
  handle.isFinished()

proc close*(service: FileSearchService) =
  ## Cancel active searches and join every worker thread.
  if service.isNil or service.xClosed:
    return
  service.xClosed = true
  for handle in service.xActive.values:
    handle.cancel()
  service.xPool.stop(immediate = true)
  service.xPool.join()
  discard service.poll()
  for handle in service.xActive.values:
    handle.xResult.reason = fsfrCancelled
    handle.xFinished = true
    emit service.fileSearchDidFinish(handle)
  service.xActive.clear()
