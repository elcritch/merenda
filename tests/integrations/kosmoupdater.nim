## Update checks use bounded background processes and deliver on the owner thread.
when defined(posix):
  import std/[monotimes, os, osproc, posix, strutils, tempfiles, times, unittest]
  import sigils/threads
  import merenda/kosmo/updater

  proc installFakeCurl(directory, script: string) =
    let executable = directory / "curl"
    writeFile(executable, "#!/bin/sh\n" & script & "\n")
    setFilePermissions(executable, {fpUserRead, fpUserWrite, fpUserExec})

  proc stopAndReap(process: var Process) =
    if process.isNil:
      return
    if process.running():
      process.terminate()
      if process.waitForExit(100) == -1:
        process.kill()
    discard process.waitForExit()
    process.close()
    process = nil

  proc waitForProcess(process: Process): bool =
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while process.running() and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(2)
    not process.running()

  suite "Kosmo update checks":
    test "a newer release is delivered to the application thread":
      let root = createTempDir("kosmo-update-check-", "")
      let originalPath = getEnv("PATH")
      defer:
        putEnv("PATH", originalPath)
        removeDir(root)
      installFakeCurl(
        root,
        "printf '%s' '{\"tag_name\":\"v1.2.4\",\"draft\":false,\"prerelease\":false}'",
      )
      putEnv("PATH", root & $PathSep & originalPath)
      var received: string
      let checker = startKosmoUpdateCheck(
        "1.2.3",
        proc(version: string) =
          received = version,
      )
      defer:
        checker.close()
      let deadline = getMonoTime() + initDuration(seconds = 20)
      while received.len == 0 and getMonoTime() < deadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(1)
      check received == "v1.2.4"

    test "closing a checker cancels and reaps its active request":
      let root = createTempDir("kosmo-update-cancel-", "")
      let originalPath = getEnv("PATH")
      let pidPath = root / "pid"
      let previousPidPath = getEnv("KOSMO_UPDATE_TEST_PID")
      let hadPidPath = existsEnv("KOSMO_UPDATE_TEST_PID")
      var child: Pid
      defer:
        if child > 0 and kill(child, 0) == 0:
          discard kill(child, SIGKILL)
        putEnv("PATH", originalPath)
        if hadPidPath:
          putEnv("KOSMO_UPDATE_TEST_PID", previousPidPath)
        else:
          delEnv("KOSMO_UPDATE_TEST_PID")
        removeDir(root)
      installFakeCurl(root, "echo $$ > \"$KOSMO_UPDATE_TEST_PID\"\nexec sleep 30")
      putEnv("PATH", root & $PathSep & originalPath)
      putEnv("KOSMO_UPDATE_TEST_PID", pidPath)
      let checker = startKosmoUpdateCheck(
        "1.2.3",
        proc(version: string) =
          discard,
      )
      defer:
        checker.close()
      var deadline = getMonoTime() + initDuration(seconds = 20)
      while not fileExists(pidPath) and getMonoTime() < deadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(1)
      require fileExists(pidPath)
      child = Pid(parseInt(readFile(pidPath).strip()))
      checker.close()
      deadline = getMonoTime() + initDuration(seconds = 20)
      while kill(child, 0) == 0 and getMonoTime() < deadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(1)
      check kill(child, 0) != 0

    when (defined(macosx) and defined(arm64)) or
        (defined(linux) and (defined(amd64) or defined(arm64))) or
        (defined(freebsd) and defined(amd64)):
      test "approved update waits for its parent and installs verified files":
        startLocalThreadDefault()
        let
          root = createTempDir("kosmo-update-install-", "")
          originalPath = getEnv("PATH")
          payload = root / "payload"
          installation = root / "install"
          binaryDirectory = root / "bin"
          configDirectory = root / "config"
          checksums = root / "SHA256SUMS.txt"
        let oldArchive = getEnv("KOSMO_TEST_UPDATE_ARCHIVE")
        let oldChecksums = getEnv("KOSMO_TEST_UPDATE_CHECKSUMS")
        let hadArchive = existsEnv("KOSMO_TEST_UPDATE_ARCHIVE")
        let hadChecksums = existsEnv("KOSMO_TEST_UPDATE_CHECKSUMS")
        defer:
          putEnv("PATH", originalPath)
          if hadArchive:
            putEnv("KOSMO_TEST_UPDATE_ARCHIVE", oldArchive)
          else:
            delEnv("KOSMO_TEST_UPDATE_ARCHIVE")
          if hadChecksums:
            putEnv("KOSMO_TEST_UPDATE_CHECKSUMS", oldChecksums)
          else:
            delEnv("KOSMO_TEST_UPDATE_CHECKSUMS")
          removeDir(root)
        createDir(payload)
        createDir(installation)
        createDir(binaryDirectory)
        when defined(macosx):
          let
            archiveName = "kosmo-macos-arm64.zip"
            relativeBinary = "Kosmo.app/Contents/MacOS/kosmo"
          createDir(payload / "Kosmo.app" / "Contents" / "MacOS")
        elif defined(linux):
          when defined(amd64):
            let archiveName = "kosmo-linux-amd64.tar.gz"
          else:
            let archiveName = "kosmo-linux-arm64.tar.gz"
          let relativeBinary = "kosmo"
        else:
          let
            archiveName = "kosmo-freebsd-amd64.tar.gz"
            relativeBinary = "kosmo"
        let archive = root / archiveName
        writeFile(payload / relativeBinary, "new Kosmo executable\n")
        setFilePermissions(
          payload / relativeBinary, {fpUserRead, fpUserWrite, fpUserExec}
        )
        when defined(macosx):
          let packageCommand =
            "cd " & quoteShell(payload) & " && zip -qr " & quoteShell(archive) &
            " Kosmo.app"
        else:
          let packageCommand =
            "tar -czf " & quoteShell(archive) & " -C " & quoteShell(payload) & " kosmo"
        let packed = execCmdEx(packageCommand)
        require packed.exitCode == 0
        let hashCommand =
          if findExe("sha256sum").len > 0: "sha256sum" else: "shasum -a 256"
        let digest = execCmdEx(hashCommand & " " & quoteShell(archive))
        require digest.exitCode == 0
        writeFile(
          checksums, digest.output.splitWhitespace()[0] & "  " & archiveName & "\n"
        )
        installFakeCurl(
          root,
          """target=""
  url=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -o) target="$2"; shift 2 ;;
      https://*) url="$1"; shift ;;
      *) shift ;;
    esac
  done
  case "$url" in
    */SHA256SUMS.txt) cp "$KOSMO_TEST_UPDATE_CHECKSUMS" "$target" ;;
    *) cp "$KOSMO_TEST_UPDATE_ARCHIVE" "$target" ;;
  esac""",
        )
        putEnv("PATH", root & $PathSep & originalPath)
        putEnv("KOSMO_TEST_UPDATE_ARCHIVE", archive)
        putEnv("KOSMO_TEST_UPDATE_CHECKSUMS", checksums)
        var parent = startProcess("sleep", args = ["30"], options = {poUsePath})
        defer:
          parent.stopAndReap()
        var helper = startKosmoUpdate(
          KosmoUpdateInstall(directory: installation, binaryDirectory: binaryDirectory),
          "v9.9.9",
          configDirectory,
          parent.processID(),
        )
        defer:
          helper.stopAndReap()
        let statusPath = configDirectory / "kosmo" / "update.status"
        check helper.running()
        check not fileExists(statusPath)
        parent.stopAndReap()
        require helper.waitForProcess()
        require helper.waitForExit() == 0
        require fileExists(statusPath)
        let log = kosmoUpdateLogPath(configDirectory)
        checkpoint(
          if fileExists(log):
            readFile(log)
          else:
            "update log missing"
        )
        check readFile(statusPath).strip() == "0"
        let installedBinary = installation / relativeBinary
        require fileExists(installedBinary)
        check readFile(installedBinary) == "new Kosmo executable\n"
        check fileExists(installation / ".kosmo-update")

        # A corrupt download must leave the currently installed executable intact.
        writeFile(installedBinary, "preserved executable\n")
        writeFile(checksums, repeat('0', 64) & "  " & archiveName & "\n")
        removeFile(statusPath)
        var nextParent = startProcess("sleep", args = ["30"], options = {poUsePath})
        defer:
          nextParent.stopAndReap()
        var rejected = startKosmoUpdate(
          KosmoUpdateInstall(directory: installation, binaryDirectory: binaryDirectory),
          "v9.9.9",
          configDirectory,
          nextParent.processID(),
        )
        defer:
          rejected.stopAndReap()
        nextParent.stopAndReap()
        require rejected.waitForProcess()
        check rejected.waitForExit() != 0
        require fileExists(statusPath)
        check readFile(statusPath).strip() != "0"
        check readFile(installedBinary) == "preserved executable\n"
