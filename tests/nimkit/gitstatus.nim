import std/[monotimes, os, osproc, streams, tempfiles, times, unittest]

import sigils/core

import merenda/nimkit/foundation/gitstatus

type GitStatusSpy = ref object of Agent
  snapshots: seq[GitStatusSnapshot]

proc rememberGitStatus(spy: GitStatusSpy, snapshot: GitStatusSnapshot) {.slot.} =
  spy.snapshots.add snapshot

proc runGit(rootPath: string, args: openArray[string]): string =
  let process = startProcess(
    "git", workingDir = rootPath, args = args, options = {poUsePath, poStdErrToStdOut}
  )
  try:
    result = process.outputStream().readAll()
    check process.waitForExit() == 0
  finally:
    process.close()

proc initializeRepository(rootPath: string) =
  discard runGit(rootPath, ["init", "-q"])
  writeFile(rootPath / "tracked.nim", "let value = 1\n")
  discard runGit(rootPath, ["add", "tracked.nim"])
  discard runGit(
    rootPath,
    [
      "-c", "user.name=NimKit Tests", "-c", "user.email=nimkit@example.invalid",
      "commit", "-qm", "initial",
    ],
  )

func entryForPath(
    snapshot: GitStatusSnapshot, path: string
): tuple[found: bool, entry: GitStatusEntry] =
  for entry in snapshot.entries:
    if entry.path == path:
      return (true, entry)

suite "nimkit Git status service":
  test "parses modified untracked renamed and conflicted porcelain records":
    let
      root = absolutePath("parser-root")
      entries = parseGitStatusPorcelain(
        root,
        " M tracked.nim\0?? untracked file.txt\0R  renamed.nim\0old.nim\0" &
          "UU conflict.nim\0",
      )

    require entries.len == 4
    check entries[0].path == root / "tracked.nim"
    check entries[0].state == gfsModified
    check entries[0].indexCode == ' '
    check entries[0].workTreeCode == 'M'
    check entries[1].path == root / "untracked file.txt"
    check entries[1].state == gfsUntracked
    check entries[2].path == root / "renamed.nim"
    check entries[2].originalPath == root / "old.nim"
    check entries[2].state == gfsRenamed
    check entries[3].state == gfsConflicted

  test "runs Git on a worker and reports work-tree changes":
    let
      root = createTempDir("merenda-git-status-", "")
      service = newGitStatusService(refreshInterval = initDuration())
      spy = GitStatusSpy()
    root.initializeRepository()
    writeFile(root / "tracked.nim", "let value = 2\n")
    writeFile(root / "untracked.txt", "new\n")
    service.connect(gitStatusDidRefresh, spy, rememberGitStatus)

    try:
      service.rootPath = root
      check service.waitForIdle(timeoutMilliseconds = 10_000)

      let snapshot = service.lastSnapshot()
      check snapshot.isRepository
      check snapshot.errorMessage.len == 0
      check snapshot.workerThreadId != getThreadId()
      check snapshot.entries.len == 2
      let
        modified = snapshot.entryForPath(root / "tracked.nim")
        untracked = snapshot.entryForPath(root / "untracked.txt")
      check modified.found
      check modified.entry.state == gfsModified
      check untracked.found
      check untracked.entry.state == gfsUntracked
      check spy.snapshots.len == 1
    finally:
      service.close()
      removeDir(root)

  test "periodic refresh notices changes without overlapping Git commands":
    let
      root = createTempDir("merenda-git-status-periodic-", "")
      service = newGitStatusService(refreshInterval = initDuration(milliseconds = 20))
      spy = GitStatusSpy()
    root.initializeRepository()
    service.connect(gitStatusDidRefresh, spy, rememberGitStatus)

    try:
      service.rootPath = root
      check service.waitForIdle(timeoutMilliseconds = 10_000)
      writeFile(root / "later.txt", "later\n")

      let deadline = getMonoTime() + initDuration(seconds = 5)
      var foundLater = false
      while not foundLater and getMonoTime() < deadline:
        discard service.poll()
        for snapshot in spy.snapshots:
          if snapshot.entryForPath(root / "later.txt").found:
            foundLater = true
        if not foundLater:
          sleep(1)

      check foundLater
      check spy.snapshots.len >= 2
    finally:
      service.close()
      removeDir(root)

  test "non-repositories produce a recoverable empty snapshot":
    let
      root = createTempDir("merenda-git-status-plain-", "")
      service = newGitStatusService(refreshInterval = initDuration())
    try:
      service.rootPath = root
      check service.waitForIdle(timeoutMilliseconds = 10_000)
      check not service.lastSnapshot().isRepository
      check service.lastSnapshot().entries.len == 0
      check service.lastSnapshot().errorMessage.len > 0
    finally:
      service.close()
      removeDir(root)
