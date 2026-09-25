## Keep process termination coverage outside the shared widget/service runner.
import std/[monotimes, os, tempfiles, times, unittest]
import merenda/nimkit/foundation/gitprocesses
import merenda/nimkit/app/diagnostics

suite "Git command lifecycle":
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
