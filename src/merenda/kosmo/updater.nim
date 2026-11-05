## Background release checks and deferred updates for installer-managed Kosmo builds.

import std/[atomics, json, os, osproc, strtabs, strutils, tempfiles]
import threading/smartptrs

import sigils/[core, threadProxies, threads]
import ../nimkit/foundation/[backgroundprocesses, backgroundworkers]

const
  KosmoReleaseApi = "https://api.github.com/repos/elcritch/merenda/releases/latest"
  KosmoInstaller = staticRead("../../../install.sh")
  KosmoUpdateMarker = ".kosmo-update"

type
  KosmoUpdateInstall* = object
    directory*: string
    binaryDirectory*: string
    staticLinux*: bool

  UpdateControl = object
    cancelled: Atomic[bool]

  UpdateWorker = ref object of AgentActor
  UpdateHandler* = proc(version: string) {.closure.}
  KosmoUpdateChecker* = ref object of Agent
    worker: AgentProxy[UpdateWorker]
    currentVersion: string
    control: SharedPtr[UpdateControl]
    handler: UpdateHandler
    closed: bool

proc versionParts(version: string): seq[int] =
  var value = version.strip()
  if value.startsWith("v"):
    value = value[1 .. ^1]
  let parts = value.split('.')
  if parts.len != 3:
    return
  for part in parts:
    if part.len == 0 or part.len > 9:
      return @[]
    for ch in part:
      if ch notin {'0' .. '9'}:
        return @[]
    result.add parseInt(part)

proc newerKosmoRelease*(currentVersion, response: string): string =
  ## Return the stable release tag only when it is newer than this build.
  try:
    let
      node = parseJson(response)
      tag = node["tag_name"].getStr()
      latest = versionParts(tag)
      current = versionParts(currentVersion)
    if latest.len != 3 or current.len != 3 or node{"draft"}.getBool() or
        node{"prerelease"}.getBool():
      return
    for index in 0 .. 2:
      if latest[index] > current[index]:
        return tag
      if latest[index] < current[index]:
        return
  except CatchableError:
    discard

proc installedKosmo*(executable: string): KosmoUpdateInstall =
  ## Only installer-managed builds opt into automatic replacement.
  if executable.len == 0:
    return
  var executablePath = executable
  try:
    if fileExists(executable):
      executablePath = expandFilename(executable)
  except OSError:
    return
  when defined(windows):
    if executablePath.lastPathPart().toLowerAscii() != "kosmo.exe":
      return
  else:
    if executablePath.lastPathPart() != "kosmo":
      return
  var directory = executablePath.parentDir()
  when defined(macosx):
    if directory.lastPathPart() != "MacOS" or
        directory.parentDir().lastPathPart() != "Contents" or
        directory.parentDir().parentDir().lastPathPart() != "Kosmo.app":
      return
    directory = directory.parentDir().parentDir().parentDir()
  let marker = directory / KosmoUpdateMarker
  try:
    if not fileExists(marker):
      return
    let lines = readFile(marker).splitLines()
    if lines.len < 2:
      return
    when defined(macosx):
      if lines[0] != "macos" or lines[1].len == 0:
        return
      result.binaryDirectory = lines[1]
    elif defined(windows):
      if lines[0] != "windows":
        return
    elif defined(linux):
      if lines[0] notin ["linux", "linux-static"]:
        return
      result.staticLinux = lines[0] == "linux-static"
    elif defined(freebsd):
      if lines[0] != "freebsd":
        return
    else:
      return
    result.directory = directory
  except CatchableError:
    discard

proc checkRelease(
  worker: AgentProxy[UpdateWorker], control: SharedPtr[UpdateControl]
) {.signal.}

proc releaseChecked(worker: UpdateWorker, response: string) {.signal.}

proc checkRelease(worker: UpdateWorker, control: SharedPtr[UpdateControl]) {.slot.} =
  let response = runBackgroundCommand(
    "curl",
    ["-fsSL", "--max-time", "10", "--user-agent", "Kosmo updater", KosmoReleaseApi],
    timeoutMilliseconds = 12_000,
    cancelled = proc(): bool {.gcsafe.} =
      control[].cancelled.load(moAcquire),
    maxOutputBytes = 1024 * 1024,
    diagnosticName = "Kosmo update check",
  )
  if response.exitCode == 0:
    emit worker.releaseChecked(response.output)

proc releaseChecked(checker: KosmoUpdateChecker, response: string) {.slot.} =
  if checker.closed or checker.handler.isNil:
    return
  let version = newerKosmoRelease(checker.currentVersion, response)
  if version.len > 0:
    checker.handler(version)

proc startKosmoUpdateCheck*(
    currentVersion: string, handler: UpdateHandler
): KosmoUpdateChecker =
  ## Check for a release off the UI thread and deliver a newer tag on the owner thread.
  if handler.isNil:
    raise newException(ValueError, "update handler is required")
  startLocalThreadDefault()
  result = KosmoUpdateChecker(
    currentVersion: currentVersion,
    handler: handler,
    control: newSharedPtr(UpdateControl),
  )
  result.control[].cancelled.store(false, moRelaxed)
  var worker = UpdateWorker()
  result.worker = worker.moveToThread(nimkitWorkerPool())
  connectThreaded(result.worker, checkRelease, result.worker, checkRelease)
  connectThreaded(
    result.worker, releaseChecked, result, KosmoUpdateChecker.releaseChecked()
  )
  emit result.worker.checkRelease(result.control)

proc close*(checker: KosmoUpdateChecker) =
  if checker.isNil or checker.closed:
    return
  checker.closed = true
  checker.control[].cancelled.store(true, moRelease)
  checker.handler = nil
  if not checker.worker.isNil:
    checker.worker.disconnect(releaseChecked, checker)
    checker.worker.disconnect(checkRelease, checker.worker)
  checker.worker = nil

proc kosmoUpdateLogPath*(configDirectory = getConfigDir()): string =
  ## Location of output from the most recent deferred installation.
  configDirectory / "kosmo" / "update.log"

proc kosmoUpdateStatusPath(configDirectory: string): string =
  configDirectory / "kosmo" / "update.status"

proc consumeKosmoUpdateFailure*(configDirectory = getConfigDir()): string =
  ## Consume a failed installation result once, returning the diagnostic log path.
  let path = kosmoUpdateStatusPath(configDirectory)
  try:
    if fileExists(path):
      let status = readFile(path).strip()
      removeFile(path)
      if status != "0":
        return kosmoUpdateLogPath(configDirectory)
  except CatchableError:
    discard

proc recordKosmoUpdateFailure*(message: string, configDirectory = getConfigDir()) =
  ## Preserve launch failures for display the next time Kosmo starts.
  let logPath = kosmoUpdateLogPath(configDirectory)
  createDir(logPath.parentDir())
  writeFile(logPath, message & "\n")
  writeFile(kosmoUpdateStatusPath(configDirectory), "1\n")

proc bashExecutable(): string =
  when defined(windows):
    for key in ["ProgramW6432", "ProgramFiles"]:
      let path = getEnv(key) / "Git" / "bin" / "bash.exe"
      if fileExists(path):
        return path
  findExe("bash")

proc canInstallKosmoUpdate*(): bool =
  bashExecutable().len > 0

proc startKosmoUpdate*(
    install: KosmoUpdateInstall,
    version: string,
    configDirectory = getConfigDir(),
    parentProcessId = getCurrentProcessId(),
): Process =
  ## Start a helper that waits for the parent before running the verified installer.
  ## The caller owns the returned process handle.
  if install.directory.len == 0 or versionParts(version).len != 3 or parentProcessId <= 0:
    raise newException(ValueError, "Invalid Kosmo update installation or version")
  let bash = bashExecutable()
  if bash.len == 0:
    raise newException(OSError, "Updating Kosmo requires Bash")
  let (file, scriptPath) = createTempFile("kosmo-update-", ".sh")
  try:
    file.write(KosmoInstaller)
    file.close()
    var environment =
      when defined(windows):
        newStringTable(modeCaseInsensitive)
      else:
        newStringTable(modeCaseSensitive)
    for key, value in envPairs():
      environment[key] = value
    environment["KOSMO_VERSION"] = version
    environment["KOSMO_GITHUB_REPO"] = "elcritch/merenda"
    environment["KOSMO_RELEASE_BASE_URL"] = ""
    environment["KOSMO_INSTALL_DIR"] = install.directory
    if install.binaryDirectory.len > 0:
      environment["KOSMO_BIN_DIR"] = install.binaryDirectory
    let
      pid = $parentProcessId
      logPath = kosmoUpdateLogPath(configDirectory)
      statusPath = kosmoUpdateStatusPath(configDirectory)
    createDir(logPath.parentDir())
    var process: Process
    when defined(windows):
      proc psQuote(value: string): string =
        "'" & value.replace("'", "''") & "'"

      let command =
        "$p = Get-Process -Id " & pid &
        " -ErrorAction SilentlyContinue; if ($p) { $p.WaitForExit() }; & " &
        psQuote(bash) & " " & psQuote(scriptPath) & " *> " & psQuote(logPath) &
        "; $result = $LASTEXITCODE; if ($null -eq $result) { $result = 1 }; " &
        "Set-Content -LiteralPath " & psQuote(statusPath) &
        " -Value $result -Encoding ASCII; " & "Remove-Item -LiteralPath " &
        psQuote(scriptPath) & " -Force; exit $result"
      process = startProcess(
        "powershell.exe",
        args = ["-NoProfile", "-NonInteractive", "-Command", command],
        env = environment,
        options = {poUsePath, poDaemon, poParentStreams},
      )
    else:
      let command =
        "while kill -0 \"$1\" 2>/dev/null; do sleep 1; done; " &
        "\"$2\" \"$3\" $4 > \"$5\" 2>&1; result=$?; " &
        "printf '%s\\n' \"$result\" > \"$6\"; rm -f \"$3\"; exit $result"
      let staticFlag = if install.staticLinux: "--static" else: ""
      process = startProcess(
        bash,
        args = [
          "-c", command, "kosmo-update", pid, bash, scriptPath, staticFlag, logPath,
          statusPath,
        ],
        env = environment,
        options = {poUsePath, poDaemon, poParentStreams},
      )
    result = process
  except:
    try:
      file.close()
    except CatchableError:
      discard
    if fileExists(scriptPath):
      removeFile(scriptPath)
    raise

proc launchKosmoUpdate*(
    install: KosmoUpdateInstall, version: string, configDirectory = getConfigDir()
) =
  ## Launch the updater to run after Kosmo exits.
  let process = startKosmoUpdate(install, version, configDirectory)
  process.close()
