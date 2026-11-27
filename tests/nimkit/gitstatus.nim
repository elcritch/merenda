import
  std/[monotimes, os, osproc, sequtils, streams, strutils, tempfiles, times, unittest]

import sigils/core

import merenda/nimkit/foundation/gitstatus
import merenda/nimkit/foundation/gitprocesses

type GitStatusSpy = ref object of Agent
  snapshots: seq[GitStatusSnapshot]
  switchCode: int
  switchOutput: string
  switchCount: int
  updateCode: int
  updateCount: int

proc rememberGitStatus(spy: GitStatusSpy, snapshot: GitStatusSnapshot) {.slot.} =
  spy.snapshots.add snapshot

proc rememberGitSwitch(
    spy: GitStatusSpy, root, branch: string, code: int, output: string
) {.slot.} =
  inc spy.switchCount
  spy.switchCode = code
  spy.switchOutput = output

proc rememberGitUpdate(
    spy: GitStatusSpy,
    root, branch: string,
    action: GitRepositoryAction,
    code: int,
    output: string,
) {.slot.} =
  inc spy.updateCount
  spy.updateCode = code

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
      "-c", "user.name=NimKit Tests", "-c", "user.email=nimkit@example.invalid", "-c",
      "commit.gpgsign=false", "commit", "-qm", "initial",
    ],
  )

func entryForPath(
    snapshot: GitStatusSnapshot, path: string
): tuple[found: bool, entry: GitStatusEntry] =
  for entry in snapshot.entries:
    if entry.path == path:
      return (true, entry)

suite "nimkit Git status service":
  test "cleanup removes selected merged and squash-merged branches and rechecks moved tips":
    let
      root = createTempDir("merenda-git-cleanup-", "")
      service = newGitStatusService(refreshInterval = initDuration())
      spy = GitStatusSpy()
    defer:
      service.close()
      removeDir(root)
    root.initializeRepository()
    discard runGit(root, ["branch", "-M", "main"])
    discard runGit(root, ["branch", "merged"])
    discard runGit(root, ["switch", "-c", "squashed"])
    for name in ["first", "second"]:
      writeFile(root / name, name)
      discard runGit(root, ["add", name])
      discard runGit(
        root,
        [
          "-c", "user.name=Tests", "-c", "user.email=tests@example.invalid", "-c",
          "commit.gpgsign=false", "commit", "-qm", name,
        ],
      )
    discard runGit(root, ["switch", "main"])
    discard runGit(root, ["merge", "--squash", "squashed"])
    discard runGit(
      root,
      [
        "-c", "user.name=Tests", "-c", "user.email=tests@example.invalid", "-c",
        "commit.gpgsign=false", "commit", "-qm", "Squash branch",
      ],
    )
    discard runGit(root, ["switch", "-c", "unmerged"])
    writeFile(root / "unmerged", "unmerged changes")
    discard runGit(root, ["add", "unmerged"])
    discard runGit(
      root,
      [
        "-c", "user.name=Tests", "-c", "user.email=tests@example.invalid", "-c",
        "commit.gpgsign=false", "commit", "-qm", "Unmerged change",
      ],
    )
    discard runGit(root, ["switch", "main"])
    service.connect(gitRepositoryDidUpdate, spy, rememberGitUpdate)
    service.rootPath = root
    require service.waitForIdle(timeoutMilliseconds = 10_000)
    let initial = service.lastSnapshot().branchInfo
    let merged = initial.filterIt(it.merged and not it.protected)
    check merged.mapIt(it.name) == @["merged", "squashed"]
    let defaultBranch = initial[initial.findIt(it.name == "main")]
    let unmerged = initial[initial.findIt(it.name == "unmerged")]
    check defaultBranch.protected
    check not unmerged.merged
    discard runGit(root, ["branch", "-f", "merged", "unmerged"])
    require service.removeBranches(
      root, merged & @[defaultBranch, unmerged], mergedOnly = true
    )
    require service.waitForIdle(timeoutMilliseconds = 10_000)
    check spy.updateCount == 1
    check spy.updateCode != 0
    check service.lastSnapshot().branches == @["main", "merged", "unmerged"]
    require service.removeBranches(root, @[unmerged], mergedOnly = false)
    require service.waitForIdle(timeoutMilliseconds = 10_000)
    check spy.updateCount == 2
    check spy.updateCode == 0
    check service.lastSnapshot().branches == @["main", "merged"]

  test "updating a branch from origin fast-forwards only an inactive local branch":
    let
      workspace = createTempDir("merenda-git-update-", "")
      origin = workspace / "origin"
      local = workspace / "local"
      service = newGitStatusService(refreshInterval = initDuration())
      spy = GitStatusSpy()
    defer:
      service.close()
      removeDir(workspace)
    createDir(origin)
    origin.initializeRepository()
    let current = runGit(origin, ["branch", "--show-current"]).strip()
    let original = runGit(origin, ["rev-parse", "HEAD"]).strip()
    discard runGit(origin, ["branch", "topic"])
    discard runGit(workspace, ["clone", "-q", "--", origin, local])
    discard runGit(local, ["branch", "topic", "origin/topic"])
    discard runGit(origin, ["switch", "topic"])
    discard runGit(
      origin,
      [
        "-c", "user.name=NimKit Tests", "-c", "user.email=nimkit@example.invalid", "-c",
        "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "Advance topic",
      ],
    )
    let advanced = runGit(origin, ["rev-parse", "HEAD"]).strip()
    service.connect(gitRepositoryDidUpdate, spy, rememberGitUpdate)
    service.rootPath = local
    require service.waitForIdle(timeoutMilliseconds = 10_000)
    require service.performGitAction(local, "topic", GitRepositoryAction.UpdateBranch)
    require service.waitForIdle(timeoutMilliseconds = 10_000)
    check spy.updateCount == 1
    check spy.updateCode == 0
    check runGit(local, ["branch", "--show-current"]).strip() == current
    check runGit(local, ["rev-parse", "refs/heads/topic"]).strip() == advanced

    discard runGit(local, ["switch", "topic"])
    require service.performGitAction(local, "topic", GitRepositoryAction.UpdateBranch)
    require service.waitForIdle(timeoutMilliseconds = 10_000)
    check spy.updateCount == 2
    check spy.updateCode != 0
    discard runGit(local, ["switch", current])
    discard runGit(origin, ["switch", current])
    discard runGit(origin, ["branch", "-f", "topic", original])
    require service.performGitAction(local, "topic", GitRepositoryAction.UpdateBranch)
    require service.waitForIdle(timeoutMilliseconds = 10_000)
    check spy.updateCount == 3
    check spy.updateCode != 0
    check runGit(local, ["rev-parse", "refs/heads/topic"]).strip() == advanced

  test "discovers branches and switches without discarding conflicting work":
    let
      root = createTempDir("merenda-git-branches-", "")
      service = newGitStatusService(refreshInterval = initDuration())
      spy = GitStatusSpy()
    defer:
      service.close()
      removeDir(root)
    root.initializeRepository()
    discard runGit(root, ["branch", "other"])
    discard runGit(root, ["tag", "other"])
    let original = runGit(root, ["branch", "--show-current"]).strip()
    service.connect(gitBranchDidSwitch, spy, rememberGitSwitch)
    service.rootPath = root
    require service.waitForIdle(timeoutMilliseconds = 10_000)
    check service.lastSnapshot().branch == original
    check "other" in service.lastSnapshot().branches
    require service.switchBranch(root, "other")
    require service.waitForIdle(timeoutMilliseconds = 10_000)
    check spy.switchCount == 1
    check spy.switchCode == 0
    check service.lastSnapshot().branch == "other"
    discard runGit(root, ["checkout", original])
    writeFile(root / "tracked.nim", "uncommitted work\n")
    discard runGit(root, ["checkout", "-b", "changes"])
    discard runGit(root, ["add", "tracked.nim"])
    discard runGit(
      root,
      [
        "-c", "user.name=Tests", "-c", "user.email=tests@example.invalid", "-c",
        "commit.gpgsign=false", "commit", "-qm", "change",
      ],
    )
    writeFile(root / "tracked.nim", "more work\n")
    require service.switchBranch(root, "other")
    require service.waitForIdle(timeoutMilliseconds = 10_000)
    check spy.switchCount == 2
    check spy.switchCode != 0
    check readFile(root / "tracked.nim") == "more work\n"
  test "Git commands drain output larger than a pipe buffer":
    let root = createTempDir("merenda-git-process-output-", "")
    defer:
      removeDir(root)
    discard runGit(root, ["init", "-q"])
    let payload = repeat("0123456789abcdef\n", 32 * 1024)
    writeFile(root / "large.txt", payload)
    let stored = runGitCommand(
      root, ["-c", "core.autocrlf=false", "hash-object", "-w", "large.txt"]
    )
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
