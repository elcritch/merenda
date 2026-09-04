## Asynchronous Git work-tree status snapshots backed by a Sigils worker pool.

import std/[monotimes, os, osproc, streams, strutils, times]

import sigils/[core, threadChronos, threadProxies, threads]

const DefaultGitStatusRefreshInterval*: Duration = initDuration(seconds = 3)

type
  GitFileState* = enum
    gfsModified
    gfsAdded
    gfsDeleted
    gfsRenamed
    gfsUntracked
    gfsConflicted
    gfsIgnored

  GitStatusEntry* = object
    path*: string
    originalPath*: string
    state*: GitFileState
    indexCode*: char
    workTreeCode*: char

  GitStatusSnapshot* = object
    rootPath*: string
    entries*: seq[GitStatusEntry]
    isRepository*: bool
    errorMessage*: string
    workerThreadId*: int

  GitCommandResult = object
    output: string
    exitCode: int

  GitStatusWorker = ref object of AgentActor
  GitStatusRefreshTicker = ref object of AgentActor

  GitStatusService* = ref object of Agent
    xPool: SigilThreadPoolPtr
    xWorker: AgentProxy[GitStatusWorker]
    xTimerThread: SigilChronosThreadPtr
    xTicker: AgentProxy[GitStatusRefreshTicker]
    xTimer: SigilTimer
    xRootPath: string
    xLastSnapshot: GitStatusSnapshot
    xNextIdentifier: uint64
    xActiveIdentifier: uint64
    xRefreshPending: bool
    xClosed: bool

proc nextNulField(output: string, cursor: var int): string =
  if cursor >= output.len:
    return
  let fieldEnd = output.find('\0', cursor)
  if fieldEnd < 0:
    result = output[cursor ..^ 1]
    cursor = output.len
  else:
    result = output[cursor ..< fieldEnd]
    cursor = fieldEnd + 1

func gitFileState(code: string): GitFileState =
  if code == "??":
    return gfsUntracked
  if code == "!!":
    return gfsIgnored
  let
    indexCode =
      if code.len > 0:
        code[0]
      else:
        ' '
    workTreeCode =
      if code.len > 1:
        code[1]
      else:
        ' '
  if indexCode == 'U' or workTreeCode == 'U' or code in ["AA", "DD"]:
    gfsConflicted
  elif indexCode == 'D' or workTreeCode == 'D':
    gfsDeleted
  elif indexCode == 'R' or workTreeCode == 'R':
    gfsRenamed
  elif indexCode in {'A', 'C'} or workTreeCode in {'A', 'C'}:
    gfsAdded
  else:
    gfsModified

func absoluteGitPath(rootPath, relativePath: string): string =
  normalizedPath(rootPath / relativePath)

func rootRelativeGitPath(path, repositoryPrefix: string): string =
  if repositoryPrefix.len > 0 and path.startsWith(repositoryPrefix):
    path[repositoryPrefix.len ..^ 1]
  else:
    path

proc parseGitStatusPorcelain*(
    rootPath, output: string, repositoryPrefix = ""
): seq[GitStatusEntry] =
  ## Parse `git status --porcelain=v1 -z` output into absolute paths.
  let root = absolutePath(rootPath)
  var cursor = 0
  while cursor < output.len:
    let record = output.nextNulField(cursor)
    if record.len >= 3:
      let
        code = record[0 .. 1]
        relativePath = record[3 ..^ 1].rootRelativeGitPath(repositoryPrefix)
        renamed = code[0] in {'R', 'C'} or code[1] in {'R', 'C'}
        originalRelativePath =
          if renamed:
            output.nextNulField(cursor).rootRelativeGitPath(repositoryPrefix)
          else:
            ""
      result.add GitStatusEntry(
        path: absoluteGitPath(root, relativePath),
        originalPath:
          if originalRelativePath.len > 0:
            absoluteGitPath(root, originalRelativePath)
          else:
            "",
        state: gitFileState(code),
        indexCode: code[0],
        workTreeCode: code[1],
      )

proc runGit(rootPath: string, args: openArray[string]): GitCommandResult =
  var process: Process
  try:
    process = startProcess(
      "git", workingDir = rootPath, args = args, options = {poUsePath, poStdErrToStdOut}
    )
    result.output = process.outputStream().readAll()
    result.exitCode = process.waitForExit()
  finally:
    if not process.isNil:
      process.close()

proc readGitStatus(rootPath: string): GitStatusSnapshot =
  result.rootPath = absolutePath(rootPath)
  result.workerThreadId = getThreadId()
  if not dirExists(result.rootPath):
    result.errorMessage = "Git status root is not a directory: " & result.rootPath
    return

  try:
    let repository = runGit(result.rootPath, ["rev-parse", "--show-prefix"])
    if repository.exitCode != 0:
      result.errorMessage = repository.output.strip()
      return
    let
      repositoryPrefix = repository.output.strip()
      status = runGit(
        result.rootPath,
        [
          "status", "--porcelain=v1", "-z", "--untracked-files=all",
          "--ignored=matching", "--", ".",
        ],
      )
    if status.exitCode == 0:
      result.isRepository = true
      result.entries =
        parseGitStatusPorcelain(result.rootPath, status.output, repositoryPrefix)
      let gitMetadataPath = normalizedPath(result.rootPath / ".git")
      if dirExists(gitMetadataPath) or fileExists(gitMetadataPath) or
          symlinkExists(gitMetadataPath):
        result.entries.add GitStatusEntry(
          path: gitMetadataPath, state: gfsIgnored, indexCode: '!', workTreeCode: '!'
        )
    else:
      result.errorMessage = status.output.strip()
  except CatchableError:
    result.errorMessage = getCurrentExceptionMsg()

proc executeGitStatus(
  worker: AgentProxy[GitStatusWorker], identifier: uint64, rootPath: string
) {.signal.}

proc gitStatusFinished(
  worker: GitStatusWorker, identifier: uint64, snapshot: GitStatusSnapshot
) {.signal.}

proc executeGitStatus(
    worker: GitStatusWorker, identifier: uint64, rootPath: string
) {.slot.} =
  emit worker.gitStatusFinished(identifier, readGitStatus(rootPath))

proc gitStatusRefreshTicked(ticker: GitStatusRefreshTicker) {.signal.}

proc emitGitStatusRefreshTick(ticker: GitStatusRefreshTicker) {.slot.} =
  emit ticker.gitStatusRefreshTicked()

proc gitStatusDidRefresh*(
  service: GitStatusService, snapshot: GitStatusSnapshot
) {.signal.}

proc refresh*(service: GitStatusService): bool {.discardable.}

proc completeGitStatus(
    service: GitStatusService, identifier: uint64, snapshot: GitStatusSnapshot
) {.slot.} =
  if service.xClosed or identifier != service.xActiveIdentifier:
    return
  service.xActiveIdentifier = 0
  if snapshot.rootPath == service.xRootPath:
    service.xLastSnapshot = snapshot
    emit service.gitStatusDidRefresh(snapshot)
  let refreshPending = service.xRefreshPending
  service.xRefreshPending = false
  if refreshPending:
    discard service.refresh()

proc requestPeriodicGitStatusRefresh(service: GitStatusService) {.slot.} =
  discard service.refresh()

proc rootPath*(service: GitStatusService): string =
  if not service.isNil:
    result = service.xRootPath

proc `rootPath=`*(service: GitStatusService, rootPath: string) =
  if service.isNil or service.xClosed:
    return
  let next =
    if rootPath.len > 0:
      absolutePath(rootPath)
    else:
      ""
  if service.xRootPath == next:
    return
  service.xRootPath = next
  service.xLastSnapshot = GitStatusSnapshot(rootPath: next)
  if service.xActiveIdentifier != 0:
    service.xRefreshPending = next.len > 0
  elif next.len > 0:
    discard service.refresh()

proc lastSnapshot*(service: GitStatusService): lent GitStatusSnapshot =
  service.xLastSnapshot

func isRefreshing*(service: GitStatusService): bool =
  not service.isNil and service.xActiveIdentifier != 0

proc refresh*(service: GitStatusService): bool {.discardable.} =
  ## Request one status refresh, coalescing requests while Git is already running.
  if service.isNil or service.xClosed or service.xRootPath.len == 0:
    return
  if service.xActiveIdentifier != 0:
    service.xRefreshPending = true
    return
  inc service.xNextIdentifier
  service.xActiveIdentifier = service.xNextIdentifier
  emit service.xWorker.executeGitStatus(service.xActiveIdentifier, service.xRootPath)
  true

proc newGitStatusService*(
    rootPath = "", refreshInterval: Duration = DefaultGitStatusRefreshInterval
): GitStatusService =
  ## Start a one-worker Git service and optionally refresh it on an interval.
  startLocalThreadDefault()
  result = GitStatusService(xPool: newSigilThreadPool(workers = 1))
  result.xPool.start()
  var worker = GitStatusWorker()
  result.xWorker = worker.moveToThread(result.xPool)
  connectThreaded(result.xWorker, executeGitStatus, result.xWorker, executeGitStatus)
  connectThreaded(
    result.xWorker, gitStatusFinished, result, GitStatusService.completeGitStatus()
  )

  if refreshInterval.inNanoseconds > 0:
    result.xTimerThread = newSigilChronosThread()
    result.xTimerThread.start()
    var ticker = GitStatusRefreshTicker()
    result.xTicker = ticker.moveToThread(result.xTimerThread)
    result.xTimer = newSigilTimer(refreshInterval)
    connectThreaded(
      result.xTimer,
      timeout,
      result.xTicker,
      GitStatusRefreshTicker.emitGitStatusRefreshTick(),
    )
    connectThreaded(
      result.xTicker,
      gitStatusRefreshTicked,
      result,
      GitStatusService.requestPeriodicGitStatusRefresh(),
    )
    result.xTimer.start(result.xTimerThread)

  result.rootPath = rootPath

proc poll*(service: GitStatusService): int {.discardable.} =
  ## Deliver completed status snapshots on the service's owning thread.
  if not service.isNil:
    getCurrentSigilThread().pollAll(NonBlocking)

proc waitForIdle*(
    service: GitStatusService, timeoutMilliseconds: Natural = 5_000
): bool {.discardable.} =
  ## Poll until the active and coalesced refreshes have completed.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
  while (service.isRefreshing() or service.xRefreshPending) and getMonoTime() < deadline:
    discard service.poll()
    if service.isRefreshing() or service.xRefreshPending:
      sleep(1)
  discard service.poll()
  not service.isRefreshing() and not service.xRefreshPending

proc close*(service: GitStatusService) =
  ## Stop the refresh timer and join the Git worker.
  if service.isNil or service.xClosed:
    return
  service.xClosed = true
  if not service.xTimer.isNil and not service.xTimerThread.isNil:
    service.xTimer.cancel(service.xTimerThread)
  if not service.xTimerThread.isNil:
    service.xTimerThread.stop(immediate = true)
    service.xTimerThread.join()
  service.xPool.stop(immediate = true)
  service.xPool.join()
  discard service.poll()
  service.xTimer = nil
  service.xTicker = nil
  service.xTimerThread = nil
  service.xActiveIdentifier = 0
  service.xRefreshPending = false
