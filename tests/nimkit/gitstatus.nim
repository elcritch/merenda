import std/[monotimes, os, osproc, streams, strutils, tempfiles, times, unittest]

when defined(posix):
  import std/posix

import sigils/core

import merenda/nimkit/foundation/gitstatus
import merenda/nimkit/foundation/gitprocesses

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
  writeFile(rootPath / ".gitignore", "*.log\n")
  discard runGit(rootPath, ["add", "tracked.nim", ".gitignore"])
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
  test "Git commands drain output larger than a pipe buffer":
    let root = createTempDir("merenda-git-process-output-", "")
    defer:
      removeDir(root)
    discard runGit(root, ["init", "-q"])
    let payload = repeat("0123456789abcdef\n", 32 * 1024)
    writeFile(root / "large.txt", payload)
    let stored = runGitCommand(root, ["hash-object", "-w", "large.txt"])
    require stored.exitCode == 0

    let loaded = runGitCommand(root, ["cat-file", "blob", stored.output.strip()])
    check loaded.exitCode == 0
    check loaded.output == payload

  test "Git command failures retain diagnostics and permit later commands":
    let root = createTempDir("merenda-git-process-error-", "")
    defer:
      removeDir(root)
    discard runGit(root, ["init", "-q"])

    let failed = runGitCommand(root, ["definitely-not-a-git-command"])
    check failed.exitCode != 0
    check "not a git command" in failed.output
    let recovered = runGitCommand(root, ["rev-parse", "--is-inside-work-tree"])
    check recovered.exitCode == 0
    check recovered.output.strip() == "true"

  when defined(posix):
    test "timed out Git commands are bounded and reaped":
      let root = createTempDir("merenda-git-process-timeout-", "")
      var helperPid: Pid
      defer:
        if helperPid > 0 and posix.kill(helperPid, 0) == 0:
          discard posix.kill(helperPid, SIGKILL)
        removeDir(root)
      discard runGit(root, ["init", "-q"])
      let
        pidPath = root / "git-command.pid"
        alias =
          "alias.waitforever=!printf '%s %s' \"$PPID\" \"$$\" > " & quoteShell(pidPath) &
          "; exec sleep 30"
        started = getMonoTime()
        timedOut =
          runGitCommand(root, ["-c", alias, "waitforever"], timeoutMilliseconds = 250)
      check timedOut.exitCode == -1
      check timedOut.output == "Git workspace command timed out"
      check getMonoTime() - started < initDuration(seconds = 5)
      require fileExists(pidPath)

      let pids = readFile(pidPath).splitWhitespace()
      require pids.len == 2
      let gitPid = Pid(pids[0].parseInt())
      helperPid = Pid(pids[1].parseInt())
      let reapDeadline = getMonoTime() + initDuration(seconds = 2)
      while posix.kill(gitPid, 0) == 0 and getMonoTime() < reapDeadline:
        sleep(10)
      check posix.kill(gitPid, 0) != 0
      check errno == ESRCH
      check runGitCommand(root, ["status", "--short"]).exitCode == 0

  test "parses modified untracked renamed conflicted and ignored records":
    let
      root = absolutePath("parser-root")
      entries = parseGitStatusPorcelain(
        root,
        " M tracked.nim\0?? untracked file.txt\0R  renamed.nim\0old.nim\0" &
          "UU conflict.nim\0!! ignored.log\0!! .github/\0",
      )

    require entries.len == 6
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
    check entries[4].path == root / "ignored.log"
    check entries[4].state == gfsIgnored
    check entries[5].path == root / ".github"
    check entries[5].state == gfsIgnored

  test "runs Git on a worker and reports work-tree changes":
    let
      root = createTempDir("merenda-git-status-", "")
      service = newGitStatusService(refreshInterval = initDuration())
      spy = GitStatusSpy()
    root.initializeRepository()
    writeFile(root / "tracked.nim", "let value = 2\n")
    writeFile(root / "untracked.txt", "new\n")
    writeFile(root / "ignored.log", "ignored\n")
    service.connect(gitStatusDidRefresh, spy, rememberGitStatus)

    try:
      service.rootPath = root
      check service.waitForIdle(timeoutMilliseconds = 10_000)

      let snapshot = service.lastSnapshot()
      check snapshot.isRepository
      check snapshot.errorMessage.len == 0
      check snapshot.workerThreadId != getThreadId()
      check snapshot.entries.len == 4
      let
        gitDirectory = snapshot.entryForPath(root / ".git")
        modified = snapshot.entryForPath(root / "tracked.nim")
        untracked = snapshot.entryForPath(root / "untracked.txt")
        ignored = snapshot.entryForPath(root / "ignored.log")
      check gitDirectory.found
      check gitDirectory.entry.state == gfsIgnored
      check modified.found
      check modified.entry.state == gfsModified
      check untracked.found
      check untracked.entry.state == gfsUntracked
      check ignored.found
      check ignored.entry.state == gfsIgnored
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
