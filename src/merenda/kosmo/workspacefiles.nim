## Shared, asynchronous file inventory for Kosmo's browser and quick open.
## GUI consumers borrow one controller; worker snapshots contain only value data.

import std/[algorithm, isolation, monotimes, os, sets, strutils, tables, times]
import sigils/[core, threadProxies, threads]
import threading/smartptrs
import ../nimkit/containers/filebrowsers
import ../nimkit/foundation/backgroundworkers
import ./workspacewatch
import ../nimkit/foundation/gitprocesses

type
  WorkspaceFileSnapshot* = object
    roots*: seq[string]
    labels*: seq[string]
    paths*: seq[string]
    listings: Table[string, seq[FileBrowserEntry]]
    generation: uint64

  WorkspaceFileWorker = ref object of AgentActor

  WorkspaceFiles* = ref object of Agent
    worker: AgentProxy[WorkspaceFileWorker]
    roots: seq[string]
    gitRoots: seq[string]
    current: WorkspaceFileSnapshot
    fallback: FileSystemBrowserModel
    generation: uint64
    active: bool
    pending: bool
    closed: bool
    watch: WorkspaceWatch
    reconciliationInterval: Duration

proc nextNulField(value: string, cursor: var int): string =
  if cursor >= value.len:
    return
  let fieldEnd = value.find('\0', cursor)
  if fieldEnd < 0:
    result = value[cursor ..^ 1]
    cursor = value.len
  else:
    result = value[cursor ..< fieldEnd]
    cursor = fieldEnd + 1

proc gitProjectFiles(
    rootPath: string
): tuple[isRepository, succeeded: bool, files: seq[string]] =
  let listing = runGitCommand(
    rootPath,
    ["ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "."],
  )
  if listing.exitCode != 0:
    return
  result.isRepository = true
  result.succeeded = true

  var
    cursor = 0
    seen = initHashSet[string]()
  while cursor < listing.output.len:
    let relativePath = listing.output.nextNulField(cursor)
    if relativePath.len == 0:
      continue
    if relativePath notin seen and fileExists(rootPath / relativePath):
      seen.incl relativePath
      result.files.add relativePath

proc filesystemProjectFiles(rootPath: string): seq[string] =
  var
    directories = @[rootPath]
    seen = initHashSet[string]()
  while directories.len > 0:
    let directory = directories.pop()
    try:
      for kind, path in walkDir(directory):
        case kind
        of pcDir:
          if path.extractFilename() != ".git":
            directories.add path
        of pcLinkToDir:
          discard
        of pcFile, pcLinkToFile:
          let relativePath = relativePath(path, rootPath)
          if relativePath notin seen:
            seen.incl relativePath
            result.add relativePath
    except OSError:
      discard

proc projectFiles*(rootPath: string): seq[string] =
  ## List project files, respecting Git's standard ignore rules in work trees.
  if rootPath.len == 0 or not dirExists(rootPath):
    return
  let root = absolutePath(rootPath)
  let gitFiles = gitProjectFiles(root)
  if gitFiles.isRepository:
    if gitFiles.succeeded:
      result = gitFiles.files
  else:
    result = filesystemProjectFiles(root)
  result.sort(system.cmp[string])

proc normalizedRoots(rootPaths: openArray[string]): seq[string] =
  for root in rootPaths:
    if root.len > 0 and dirExists(root):
      let path = normalizedPath(absolutePath(root))
      if path notin result:
        result.add path

proc readWorkspaceFiles(roots: seq[string], generation: uint64): WorkspaceFileSnapshot =
  result = WorkspaceFileSnapshot(roots: roots, generation: generation)
  var seen = initHashSet[string]()
  var model = initFileSystemBrowserModel()
  for root in roots:
    var prefix = root.extractFilename()
    for other in roots:
      if other != root and other.extractFilename() == prefix:
        prefix = root
        break
    for relative in projectFiles(root):
      let path = normalizedPath(root / relative)
      if path notin seen:
        seen.incl path
        result.labels.add(
          if roots.len == 1:
            relative
          else:
            prefix / relative
        )
        result.paths.add path
      # Seed the browser from the same inventory, retaining ignored siblings and
      # empty directories. Ignored subtrees remain lazy, not recursively scanned.
      var parent = path.parentDir()
      while parent.len > 0 and not model.isDirectoryLoaded(parent):
        result.listings[parent] = model.entries(parent)
        if parent == root:
          break
        parent = parent.parentDir()
    result.listings[root] = model.entries(root)

proc workspaceFilesDidChange*(files: WorkspaceFiles) {.signal.}
proc workspaceRepositoryDidChange*(files: WorkspaceFiles) {.signal.}
proc workspacePulse*(files: WorkspaceFiles) {.signal.}
proc loadFiles(
  worker: AgentProxy[WorkspaceFileWorker], roots: seq[string], generation: uint64
) {.signal.}

proc filesLoaded(
  worker: WorkspaceFileWorker, snapshot: SharedPtr[WorkspaceFileSnapshot]
) {.signal.}

proc loadFiles(
    worker: WorkspaceFileWorker, roots: seq[string], generation: uint64
) {.slot.} =
  var snapshot = readWorkspaceFiles(roots, generation)
  emit worker.filesLoaded(newSharedPtr(unsafeIsolate(move snapshot)))

proc refresh*(files: WorkspaceFiles)

proc watchChanged(files: WorkspaceFiles) {.slot.} =
  if not files.closed:
    files.refresh()
    emit files.workspaceRepositoryDidChange()

proc watchPulse(files: WorkspaceFiles) {.slot.} =
  if not files.closed:
    emit files.workspacePulse()

proc startMonitoring*(files: WorkspaceFiles) =
  if files.watch.isNil and not files.closed:
    files.watch = newWorkspaceWatch(files.reconciliationInterval)
    files.watch.connect(workspaceWatchChanged, files, watchChanged)
    files.watch.connect(workspaceWatchPulse, files, watchPulse)
    files.watch.setRoots(files.roots & files.gitRoots)

proc setGitRoots*(files: WorkspaceFiles, roots: openArray[string]) =
  ## Cover open buffers outside the browser's roots without indexing their folders.
  if files.closed or files.gitRoots == @roots:
    return
  files.gitRoots = @roots
  if not files.watch.isNil:
    files.watch.setRoots(files.roots & files.gitRoots)

proc stopMonitoring*(files: WorkspaceFiles) =
  if not files.watch.isNil:
    files.watch.close()
    files.watch = nil

proc receiveFiles(
    files: WorkspaceFiles, snapshot: SharedPtr[WorkspaceFileSnapshot]
) {.slot.} =
  if files.closed:
    return
  files.active = false
  if snapshot[].generation == files.generation:
    files.current = move snapshot[]
    files.fallback.invalidate()
    if not files.watch.isNil:
      files.watch.markReconciled()
    emit files.workspaceFilesDidChange()
  if files.pending:
    files.pending = false
    files.refresh()

proc newWorkspaceFiles*(
    reconciliationInterval = DefaultWorkspaceReconciliationInterval
): WorkspaceFiles =
  ## Create an owner-thread controller borrowing NimKit's shared worker pool.
  result = WorkspaceFiles(reconciliationInterval: reconciliationInterval)
  var worker = WorkspaceFileWorker()
  result.worker = worker.moveToThread(nimkitWorkerPool())
  connectThreaded(result.worker, loadFiles, result.worker, loadFiles)
  connectThreaded(result.worker, filesLoaded, result, WorkspaceFiles.receiveFiles())

proc snapshot*(files: WorkspaceFiles): lent WorkspaceFileSnapshot =
  files.current

proc isLoading*(files: WorkspaceFiles): bool =
  files.active or files.pending

proc entries*(files: WorkspaceFiles, directory: string): seq[FileBrowserEntry] =
  ## Shared browser listings; unindexed (including ignored) folders load lazily.
  if directory in files.current.listings:
    files.current.listings[directory]
  else:
    files.fallback.entries(directory)

proc refresh*(files: WorkspaceFiles) =
  ## Invalidate in-flight work and coalesce changes into one follow-up scan.
  if files.closed:
    return
  inc files.generation
  files.current.listings.clear()
  files.fallback.invalidate()
  if files.active:
    files.pending = true
  else:
    files.active = true
    emit files.worker.loadFiles(files.roots, files.generation)

proc setRoots*(files: WorkspaceFiles, roots: openArray[string]) =
  let next = normalizedRoots(roots)
  if next != files.roots:
    files.roots = next
    files.current = WorkspaceFileSnapshot(roots: next)
    files.fallback.invalidate()
    if not files.watch.isNil:
      files.watch.setRoots(next & files.gitRoots)
    files.refresh()

proc reload*(files: WorkspaceFiles, roots: openArray[string]) =
  ## Synchronous compatibility entry point for tools and tests.
  if files.closed:
    return
  inc files.generation
  files.pending = false
  files.roots = normalizedRoots(roots)
  if not files.watch.isNil:
    files.watch.setRoots(files.roots & files.gitRoots)
  files.current = readWorkspaceFiles(files.roots, files.generation)
  files.fallback.invalidate()
  if not files.watch.isNil:
    files.watch.markReconciled()
  emit files.workspaceFilesDidChange()

proc waitForFiles*(files: WorkspaceFiles, timeoutMilliseconds: Natural = 10_000): bool =
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
  while files.isLoading() and getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    sleep(1)
  not files.isLoading()

proc close*(files: WorkspaceFiles) =
  ## Ignore queued results without stopping other users of the shared pool.
  if not files.isNil:
    files.stopMonitoring()
    files.closed = true
    files.pending = false
    files.active = false
