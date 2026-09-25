## Verify that Kosmo's LSP launcher passes only stdio to the server.

when defined(posix):
  import std/[monotimes, os, osproc, posix, streams, strutils, times, unittest]

  import merenda/kosmo/cli

  const
    launchProbe = "--merenda-launch-probe"
    checkProbe = "--merenda-check-probe"

  if paramCount() == 2:
    let fd = parseInt(paramStr(2)).cint
    case paramStr(1)
    of launchProbe:
      if fcntl(fd, F_GETFD) == -1:
        quit(2)
      execLspServer(@[getAppFilename(), checkProbe, $fd])
    of checkProbe:
      let standardInput = stdin.readLine()
      stdout.writeLine("stdio-ready")
      stdout.flushFile()
      quit(if fcntl(fd, F_GETFD) == -1 and standardInput == "ping": 0 else: 3)
    else:
      discard

  suite "Kosmo LSP process descriptors":
    test "launcher closes unrelated inherited descriptors before exec":
      var pipeFds: array[0 .. 1, cint]
      require pipe(pipeFds) == 0
      defer:
        discard close(pipeFds[0])
        discard close(pipeFds[1])

      let extraFd = fcntl(pipeFds[1], F_DUPFD, 200)
      require extraFd >= 200
      defer:
        discard close(extraFd)
      check (fcntl(extraFd, F_GETFD) and FD_CLOEXEC) == 0

      let process =
        startProcess(getAppFilename(), args = @[launchProbe, $extraFd], options = {})
      try:
        process.inputStream().writeLine("ping")
        process.inputStream().flush()
        let deadline = getMonoTime() + initDuration(seconds = 5)
        var exitCode = process.peekExitCode()
        while exitCode == -1 and getMonoTime() < deadline:
          sleep(5)
          exitCode = process.peekExitCode()
        require exitCode == 0
        let outputLine = process.outputStream().readLine()
        check outputLine == "stdio-ready"
      finally:
        if process.peekExitCode() == -1:
          process.kill()
        discard process.waitForExit()
        process.close()
