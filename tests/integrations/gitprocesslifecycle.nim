## Keep process termination coverage outside the shared widget/service runner.
import std/[atomics, monotimes, os, strutils, tempfiles, times, unittest]
import sigils/threads
import merenda/services/backgroundprocesses
import merenda/services/git/processes
import ./fixtures/backgroundcommand
import merenda/nimkit/app/diagnostics

type CommandWorkers = object
  ready: Atomic[int]
  start: Atomic[bool]
  failures: Atomic[int]
  finished: Atomic[int]

proc runConcurrentCommands(state: ptr CommandWorkers) {.thread.} =
  discard state.ready.fetchAdd(1, moRelease)
  while not state.start.load(moAcquire):
    sleep(1)
  for attempt in 0 ..< 5:
    let command =
      runBackgroundCommand(getAppFilename(), [backgroundCommandProbe, "both"])
    if command.exitCode != 0 or command.output.count('a') != 32 * 8192 or
        command.output.count('b') != 32 * 8192:
      discard state.failures.fetchAdd(1, moRelaxed)
  discard state.finished.fetchAdd(1, moRelease)

suite "Git command lifecycle":
  test "concurrent background commands retain both complete output streams":
    var state: CommandWorkers
    var workers: array[3, Thread[ptr CommandWorkers]]
    for worker in workers.mitems:
      createThread(worker, runConcurrentCommands, addr state)
    var joined = false
    defer:
      if not joined:
        state.start.store(true, moRelease)
        joinThreads(workers)
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while state.ready.load(moAcquire) < workers.len and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(1)
    require state.ready.load(moAcquire) == workers.len
    state.start.store(true, moRelease)
    while state.finished.load(moAcquire) < workers.len and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(1)
    require state.finished.load(moAcquire) == workers.len
    joinThreads(workers)
    joined = true
    check state.failures.load(moRelaxed) == 0

  test "background commands drain both output streams and respect their combined limit":
    let before = processResourceUsage()
    let command =
      runBackgroundCommand(getAppFilename(), [backgroundCommandProbe, "both"])
    check command.exitCode == 0
    check command.output.count('a') == 32 * 8192
    check command.output.count('b') == 32 * 8192
    for mode in ["stdout", "stderr"]:
      let single =
        runBackgroundCommand(getAppFilename(), [backgroundCommandProbe, mode])
      check single.exitCode == 0
      if mode == "stdout":
        check single.output.count('a') == 32 * 8192
      else:
        check single.output.count('b') == 32 * 8192
    let limited = runBackgroundCommand(
      getAppFilename(), [backgroundCommandProbe, "both"], maxOutputBytes = 32 * 8192
    )
    check limited.exitCode == -1
    check limited.outputLimitExceeded
    when defined(macosx) or defined(linux):
      check processResourceUsage().childProcesses == before.childProcesses
      check processResourceUsage().fileDescriptors <= before.fileDescriptors + 2

  test "timed out commands are reaped and later commands still work":
    let root = createTempDir("merenda-git-timeout-", "")
    defer:
      removeDir(root)
    require runGitCommand(root, ["init", "-q"]).exitCode == 0
    let before = processResourceUsage()
    for attempt in 0 ..< 3:
      checkpoint("timeout cycle: " & $attempt)
      let started = getMonoTime()
      # Git itself blocks on its input pipe. No shell or orphaned sleep helper
      # is needed to exercise the timeout and terminate/wait/close path.
      let timedOut =
        runGitCommand(root, ["hash-object", "--stdin"], timeoutMilliseconds = 200)
      check timedOut.exitCode == -1
      check timedOut.output == "Git workspace command timed out"
      check getMonoTime() - started < initDuration(seconds = 10)
      when defined(macosx) or defined(linux):
        check processResourceUsage().childProcesses == before.childProcesses
      check runGitCommand(root, ["status", "--short"]).exitCode == 0
