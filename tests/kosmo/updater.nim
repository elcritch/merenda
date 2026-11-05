## Release selection and installer ownership for Kosmo's update checks.
import std/[os, tempfiles, unittest]

import merenda/kosmo/updater

suite "Kosmo updater":
  test "only newer stable release tags are offered":
    check newerKosmoRelease("0.30.3", """{"tag_name":"v0.31.0"}""") == "v0.31.0"
    check newerKosmoRelease("0.30.3", """{"tag_name":"v0.30.3"}""") == ""
    check newerKosmoRelease("0.30.3", """{"tag_name":"v0.29.99"}""") == ""
    check newerKosmoRelease("0.30.3", """{"tag_name":"v1.0.0","prerelease":true}""") ==
      ""
    check newerKosmoRelease("0.30.3", """{"tag_name":"v1.0.0","draft":true}""") == ""
    check newerKosmoRelease("0.30.3", """{"tag_name":"v1.0.0-rc1"}""") == ""
    check newerKosmoRelease("0.30.3", """{"tag_name":"v1.0.0;touch file"}""") == ""
    check newerKosmoRelease("0.30.3", "invalid JSON") == ""

  test "only installer-managed locations are eligible for an update":
    let root = createTempDir("kosmo-update-test-", "")
    defer:
      removeDir(root)
    when defined(macosx):
      let executable = root / "Kosmo.app" / "Contents" / "MacOS" / "kosmo"
      let marker = root / ".kosmo-update"
      let binaryDirectory = root / "bin"
      let contents = "macos\n" & binaryDirectory & "\n"
    elif defined(windows):
      let executable = root / "kosmo.exe"
      let marker = root / ".kosmo-update"
      let contents = "windows\n\n"
    elif defined(linux):
      let executable = root / "kosmo"
      let marker = root / ".kosmo-update"
      let contents = "linux-static\n\n"
    elif defined(freebsd):
      let executable = root / "kosmo"
      let marker = root / ".kosmo-update"
      let contents = "freebsd\n\n"
    else:
      skip()
    when defined(macosx) or defined(windows) or defined(linux) or defined(freebsd):
      check installedKosmo(executable).directory == ""
      writeFile(marker, contents)
      let installation = installedKosmo(executable)
      check installation.directory == root
      check installedKosmo(root / "other-program").directory == ""
      when defined(posix):
        createDir(executable.parentDir())
        writeFile(executable, "test executable")
        let alias = root / "kosmo-link"
        createSymlink(executable, alias)
        check installedKosmo(alias).directory == expandFilename(root)
      when defined(macosx):
        check installation.binaryDirectory == binaryDirectory
      when defined(linux):
        check installation.staticLinux
      writeFile(marker, "unsupported\n\n")
      check installedKosmo(executable).directory == ""

  test "update failures are reported once with their log":
    let root = createTempDir("kosmo-update-error-", "")
    defer:
      removeDir(root)
    recordKosmoUpdateFailure("download failed", root)
    let logPath = kosmoUpdateLogPath(root)
    check readFile(logPath) == "download failed\n"
    check consumeKosmoUpdateFailure(root) == logPath
    check consumeKosmoUpdateFailure(root) == ""
    writeFile(root / "kosmo" / "update.status", "0\n")
    check consumeKosmoUpdateFailure(root) == ""
