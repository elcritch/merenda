## Dmon invalidation delivered on the GUI thread. Callbacks touch only a locked
## inbox, never GUI objects or dmon's watch list (callbacks can hold its lock).

import std/[algorithm, exitprocs, locks, monotimes, os, strutils, tables, times]
import chronicles
import dmon
import sigils/[core, threadChronos, threadProxies, threads]
import ../nimkit/foundation/backgroundworkers
import ./workspacechanges

const DefaultWorkspaceReconciliationInterval* = initDuration(minutes = 2)

type
  WorkspaceChanges = object
    rescan: bool
    paths: seq[string]

  WorkspaceWatchFilter = ref object of AgentActor
  WorkspaceWatchTicker = ref object of AgentActor
  WorkspaceWatch* = ref object of Agent
    token: uint
    roots: seq[string]
    folders: seq[string]
    metadata: seq[string]
    directories: seq[string]
    watches: seq[WatchId]
    handles: Table[string, WatchId]
    timer: SigilTimer
    ticker: AgentProxy[WorkspaceWatchTicker]
    filter: AgentProxy[WorkspaceWatchFilter]
    filtering: bool
    active: bool
    fallback: bool
    nativeReady: bool
    elapsed: int
    reconciliationInterval: Duration
    lastReconciledMonoTime: MonoTime
    lastReconciledTime: Time
    reconciliationPending: bool

var
  watchUsers: int
  ownsDmon: bool
  nextToken: uint
  inboxLock: Lock
  inbox: Table[uint, WorkspaceChanges]

initLock(inboxLock)

proc stopWatchBackend() {.noconv.} =
  if ownsDmon and dmonInst.initialized:
    deinitDmon()
    ownsDmon = false

proc startWatchBackend() =
  ## Start dmon without losing its one-shot readiness signal. The upstream
  ## helper creates the thread before entering the condition wait, allowing a
  ## fast monitor thread to signal before the caller is waiting and deadlock
  ## application startup. Holding the mutex across thread creation makes the
  ## wait-and-signal handoff deterministic.
  withLock dmonInst.threadLock:
    createThread(dmonInst.threadHandle, monitorThread)
    wait(dmonInst.threadSem, dmonInst.threadLock)
  for index in 0 ..< dmonInst.freeList.len:
    dmonInst.freeList[index] = dmonInst.freeList.len - index - 1
  dmonInst.initialized = true

proc nativeWatchesReady(watch: WorkspaceWatch): bool =
  ## macOS creates FSEvents streams synchronously but schedules and starts them
  ## later on dmon's monitor thread. Other supported backends finish
  ## registration before `watch` returns (or use our polling fallback).
  if watch.nativeReady:
    return true
  when defined(macosx):
    if not dmonInst.initialized:
      return
    # The backend holds this mutex while its CoreFoundation loop polls for up
    # to half a second. Never make the GUI timer wait for it.
    if not tryAcquire(dmonInst.threadLock):
      return
    defer:
      release(dmonInst.threadLock)
    var failed: bool
    block:
      for id in watch.watches:
        let index = int(uint32(id)) - 1
        if index < 0 or index >= dmonInst.watches.len or dmonInst.watches[index].isNil or
            not dmonInst.watches[index].init:
          return
        if not dmonInst.watches[index].started:
          failed = true
    if failed:
      watch.fallback = true
      warn "Kosmo workspace watcher using periodic fallback after FSEvents startup failure",
        roots = watch.roots
  watch.nativeReady = true
  result = true

proc didChange(
    watchId: WatchId,
    action: DmonAction,
    rootDir, filepath, oldfilepath: string,
    userData: pointer,
) =
  # Some backends can finish a callback after unwatch. Tokens are never reused;
  # removing the inbox makes late notifications harmless without dangling pointers.
  let token = cast[uint](userData)
  withLock inboxLock:
    if token in inbox:
      var changes = addr inbox[token]
      for relative in [filepath, oldfilepath]:
        if relative.len > 0 and not changes[].rescan:
          let path = normalizedPath(absolutePath(relative, rootDir))
          if path notin changes[].paths:
            if changes[].paths.len < 1024:
              changes[].paths.add path
            else:
              changes[] = WorkspaceChanges(rescan: true)
      if filepath.len == 0:
        changes[] = WorkspaceChanges(rescan: true)

proc workspaceWatchChanged*(watch: WorkspaceWatch) {.signal.}
proc workspaceWatchIgnoredChange*(watch: WorkspaceWatch) {.signal.}
proc workspaceWatchPulse*(watch: WorkspaceWatch) {.signal.}
proc pulsed(ticker: WorkspaceWatchTicker) {.signal.}
proc pulse(ticker: WorkspaceWatchTicker) {.slot.} =
  emit ticker.pulsed()

proc setRoots*(
  watch: WorkspaceWatch, roots: openArray[string], folders: openArray[string] = []
)

proc filterChanges(
  worker: AgentProxy[WorkspaceWatchFilter],
  paths: seq[string],
  roots: seq[string],
  metadata: seq[string],
) {.signal.}

proc changesFiltered(worker: WorkspaceWatchFilter, relevant: bool) {.signal.}

proc filterChanges(
    worker: WorkspaceWatchFilter,
    paths: seq[string],
    roots: seq[string],
    metadata: seq[string],
) {.slot.} =
  emit worker.changesFiltered(hasRelevantRepositoryChanges(paths, roots, metadata))

proc notifyChanged(watch: WorkspaceWatch) =
  # A .git file can appear or change targets after the project was opened.
  watch.setRoots(watch.roots, watch.folders)
  emit watch.workspaceWatchChanged()

proc changesFiltered(watch: WorkspaceWatch, relevant: bool) {.slot.} =
  watch.filtering = false
  if watch.active:
    if relevant:
      watch.notifyChanged()
    else:
      emit watch.workspaceWatchIgnoredChange()

proc deliver(watch: WorkspaceWatch) {.slot.} =
  if not watch.active:
    return
  watch.elapsed = min(watch.elapsed + 1, 30)
  let watchesReady = watch.nativeWatchesReady()
  var changes: WorkspaceChanges
  if watchesReady and not watch.filtering:
    withLock inboxLock:
      # Keep setup and native events queued until the backend is listening and
      # the previous batch has finished filtering on the worker.
      changes = move inbox[watch.token]
      inbox[watch.token] = WorkspaceChanges()
  # A timer drains notifications, not the filesystem. Fall back only when
  # native coverage cannot be established (including dmon's Linux recursion bug).
  let
    reconciliationInterval = watch.reconciliationInterval
    reconciliationDue =
      not watch.reconciliationPending and reconciliationInterval.inNanoseconds > 0 and (
        getMonoTime() - watch.lastReconciledMonoTime >= reconciliationInterval or
        getTime() - watch.lastReconciledTime >= reconciliationInterval
      )
  if changes.rescan or reconciliationDue or (watch.fallback and watch.elapsed >= 30):
    watch.elapsed = 0
    if reconciliationDue:
      watch.reconciliationPending = true
    watch.notifyChanged()
  elif changes.paths.len > 0:
    watch.elapsed = 0
    watch.filtering = true
    emit watch.filter.filterChanges(changes.paths, watch.roots, watch.metadata)
  emit watch.workspaceWatchPulse()

proc metadataDirectories(root: string): seq[string] =
  var current = root
  while current.len > 0:
    let marker = current / ".git"
    var gitDir: string
    if dirExists(marker):
      gitDir = marker
    elif fileExists(marker):
      try:
        let content = readFile(marker).strip()
        if content.startsWith("gitdir: "):
          gitDir = normalizedPath(absolutePath(content[8 ..^ 1], current))
      except OSError, IOError:
        discard
    if gitDir.len > 0:
      result.add gitDir
      if fileExists(gitDir / "commondir"):
        try:
          result.add normalizedPath(
            absolutePath(readFile(gitDir / "commondir").strip(), gitDir)
          )
        except OSError, IOError:
          discard
      return
    let parent = current.parentDir()
    if parent == current:
      return
    current = parent

proc watchedMetadataDirectories(root: string): seq[string] =
  for metadata in metadataDirectories(root):
    if metadata notin result:
      result.add metadata
    # HEAD/index live directly in the Git directory. Watch refs separately so
    # native backends never recurse through the object database or ignored files.
    var pending = @[metadata / "refs"]
    var visited: int
    while pending.len > 0 and result.len < 16 and visited < 64:
      let directory = pending.pop()
      if dirExists(directory):
        result.add directory
        try:
          for kind, path in walkDir(directory):
            if visited >= 64:
              break
            inc visited
            if kind == pcDir:
              pending.add path
        except OSError:
          discard

proc setRoots*(
    watch: WorkspaceWatch, roots: openArray[string], folders: openArray[string] = []
) =
  ## Project directories and Git metadata use shallow, bounded watches.
  ## Filesystem roots are never watched, and each workspace has at most 64 paths.
  if not watch.active:
    return
  var
    directories: seq[string]
    metadataPaths: seq[string]
  for root in roots:
    let path = normalizedPath(absolutePath(root))
    if path.parentDir().len > 0 and path.parentDir() != path:
      if path notin directories and directories.len < 64:
        directories.add path
      for metadata in watchedMetadataDirectories(path):
        if metadata notin directories and directories.len < 64:
          directories.add metadata
          metadataPaths.add metadata
  for folder in folders:
    let path = normalizedPath(absolutePath(folder))
    if path.parentDir().len > 0 and path.parentDir() != path and path notin directories and
        directories.len < 64:
      directories.add path
  directories.sort()
  metadataPaths.sort()
  watch.roots = @roots
  watch.folders = @folders
  if directories == watch.directories and metadataPaths == watch.metadata:
    return
  var removed: seq[string]
  for directory, id in watch.handles:
    if directory notin directories:
      unwatch(id)
      removed.add directory
  for directory in removed:
    watch.handles.del(directory)
  watch.metadata = metadataPaths
  watch.directories = directories
  watch.fallback = false
  watch.nativeReady = false
  when defined(linux):
    # dmon 0.5.0 concatenates absolute event paths when watching newly created
    # directories, asserting in its monitor thread. Do not crash the application.
    watch.fallback = directories.len > 0
  else:
    for directory in directories:
      if directory in watch.handles:
        discard
      elif dirExists(directory):
        if dmonInst.numWatches >= 64:
          watch.fallback = true
        else:
          try:
            watch.handles[directory] =
              dmon.watch(directory, didChange, {}, cast[pointer](watch.token))
          except CatchableError:
            watch.fallback = true
      else:
        watch.fallback = true
  watch.watches.setLen(0)
  for id in watch.handles.values:
    watch.watches.add id
  if watch.fallback:
    warn "Kosmo workspace watcher using periodic fallback", roots = watch.roots
  withLock inboxLock:
    inbox[watch.token] = WorkspaceChanges(rescan: true)

proc newWorkspaceWatch*(
    reconciliationInterval = DefaultWorkspaceReconciliationInterval
): WorkspaceWatch =
  ## Own a subscription; all lifecycle calls belong on the GUI thread.
  if watchUsers == 0 and not dmonInst.initialized:
    initDmon()
    startWatchBackend()
    ownsDmon = true
    # Keep dmon's global backend at application lifetime, like the worker pool.
    # Windows only own watches, avoiding backend reinitialization on every close.
    addExitProc(stopWatchBackend)
  inc watchUsers
  inc nextToken
  result = WorkspaceWatch(
    active: true,
    token: nextToken,
    reconciliationInterval: reconciliationInterval,
    lastReconciledMonoTime: getMonoTime(),
    lastReconciledTime: getTime(),
  )
  withLock inboxLock:
    inbox[result.token] = WorkspaceChanges(rescan: true)
  var filter = WorkspaceWatchFilter()
  result.filter = filter.moveToThread(nimkitWorkerPool())
  connectThreaded(result.filter, filterChanges, result.filter, filterChanges)
  connectThreaded(
    result.filter, changesFiltered, result, WorkspaceWatch.changesFiltered()
  )
  let timerThread = nimkitTimerThread()
  var ticker = WorkspaceWatchTicker()
  result.ticker = ticker.moveToThread(timerThread)
  result.timer = newSigilTimer(initDuration(milliseconds = 100))
  connectThreaded(result.timer, timeout, result.ticker, WorkspaceWatchTicker.pulse())
  connectThreaded(result.ticker, pulsed, result, WorkspaceWatch.deliver())
  result.timer.start(timerThread)

proc usesPollingFallback*(watch: WorkspaceWatch): bool =
  watch.fallback

proc markReconciled*(watch: WorkspaceWatch) =
  ## Restart the backup deadline after a full workspace snapshot was accepted.
  if not watch.isNil and watch.active:
    watch.lastReconciledMonoTime = getMonoTime()
    watch.lastReconciledTime = getTime()
    watch.reconciliationPending = false

proc close*(watch: WorkspaceWatch) =
  if watch.isNil or not watch.active:
    return
  watch.active = false
  watch.timer.cancel(nimkitTimerThread())
  for id in watch.watches:
    unwatch(id)
  watch.watches.setLen(0)
  dec watchUsers
  withLock inboxLock:
    inbox.del(watch.token)
  watch.timer = nil
  watch.ticker = nil
  watch.filter = nil

var workspaceWatchWorkerLifetime {.used.}: NimkitBackgroundWorkerLifetime
