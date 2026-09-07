## Dmon invalidation delivered on the GUI thread. Callbacks touch only a locked
## inbox, never GUI objects or dmon's watch list (callbacks can hold its lock).

import std/[algorithm, exitprocs, locks, os, strutils, tables, times]
import chronicles
import dmon
import sigils/[core, threadChronos, threadProxies, threads]
import ../nimkit/foundation/backgroundworkers

type
  WorkspaceWatchTicker = ref object of AgentActor
  WorkspaceWatch* = ref object of Agent
    token: uint
    roots: seq[string]
    directories: seq[string]
    watches: seq[WatchId]
    timer: SigilTimer
    ticker: AgentProxy[WorkspaceWatchTicker]
    active: bool
    fallback: bool
    elapsed: int

var
  watchUsers: int
  ownsDmon: bool
  nextToken: uint
  inboxLock: Lock
  inbox: Table[uint, bool]

initLock(inboxLock)

proc stopWatchBackend() {.noconv.} =
  if ownsDmon and dmonInst.initialized:
    deinitDmon()
    ownsDmon = false

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
      inbox[token] = true

proc workspaceWatchChanged*(watch: WorkspaceWatch) {.signal.}
proc workspaceWatchPulse*(watch: WorkspaceWatch) {.signal.}
proc pulsed(ticker: WorkspaceWatchTicker) {.signal.}
proc pulse(ticker: WorkspaceWatchTicker) {.slot.} =
  emit ticker.pulsed()

proc setRoots*(watch: WorkspaceWatch, roots: openArray[string])

proc deliver(watch: WorkspaceWatch) {.slot.} =
  if not watch.active:
    return
  watch.elapsed = min(watch.elapsed + 1, 30)
  var dirty: bool
  withLock inboxLock:
    dirty = inbox.getOrDefault(watch.token)
    inbox[watch.token] = false
  # A timer drains notifications, not the filesystem. Fall back only when
  # native coverage cannot be established (including dmon's Linux recursion bug).
  if dirty or (watch.fallback and watch.elapsed >= 30):
    watch.elapsed = 0
    # A .git file can appear or change targets after the project was opened.
    watch.setRoots(watch.roots)
    emit watch.workspaceWatchChanged()
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

proc setRoots*(watch: WorkspaceWatch, roots: openArray[string]) =
  ## Also cover linked worktree metadata and shared refs outside project roots.
  if not watch.active:
    return
  var directories: seq[string]
  for root in roots:
    if root notin directories:
      directories.add root
    for metadata in metadataDirectories(root):
      if metadata notin directories:
        directories.add metadata
  var minimal: seq[string]
  for directory in directories:
    var covered = false
    for parent in directories:
      if parent != directory:
        let prefix = parent & (if parent[^1] in {DirSep, AltSep}: ""
        else: $DirSep)
        if directory.startsWith(prefix):
          covered = true
          break
    if not covered:
      minimal.add directory
  directories = minimal
  directories.sort()
  watch.roots = @roots
  if directories == watch.directories:
    return
  for id in watch.watches:
    unwatch(id)
  watch.watches.setLen(0)
  watch.directories = directories
  watch.fallback = false
  when defined(linux):
    # dmon 0.5.0 concatenates absolute event paths when watching newly created
    # directories, asserting in its monitor thread. Do not crash the application.
    watch.fallback = true
  else:
    for directory in directories:
      if dirExists(directory):
        if dmonInst.numWatches >= 64:
          watch.fallback = true
        else:
          try:
            watch.watches.add dmon.watch(
              directory, didChange, {Recursive}, cast[pointer](watch.token)
            )
          except CatchableError:
            watch.fallback = true
      else:
        watch.fallback = true
  if watch.fallback:
    warn "Kosmo workspace watcher using periodic fallback", roots = watch.roots
  withLock inboxLock:
    inbox[watch.token] = true

proc newWorkspaceWatch*(): WorkspaceWatch =
  ## Own a subscription; all lifecycle calls belong on the GUI thread.
  if watchUsers == 0 and not dmonInst.initialized:
    initDmon()
    startDmonThread()
    ownsDmon = true
    # Keep dmon's global backend at application lifetime, like the worker pool.
    # Windows only own watches, avoiding backend reinitialization on every close.
    addExitProc(stopWatchBackend)
  inc watchUsers
  inc nextToken
  result = WorkspaceWatch(active: true, token: nextToken)
  withLock inboxLock:
    inbox[result.token] = true
  let timerThread = nimkitTimerThread()
  var ticker = WorkspaceWatchTicker()
  result.ticker = ticker.moveToThread(timerThread)
  result.timer = newSigilTimer(initDuration(milliseconds = 100))
  connectThreaded(result.timer, timeout, result.ticker, WorkspaceWatchTicker.pulse())
  connectThreaded(result.ticker, pulsed, result, WorkspaceWatch.deliver())
  result.timer.start(timerThread)

proc usesPollingFallback*(watch: WorkspaceWatch): bool =
  watch.fallback

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
