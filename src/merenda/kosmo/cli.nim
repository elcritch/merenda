## Command-line handling and detached launching for standalone Kosmo.

import std/os

when defined(windows):
  import std/[widestrs, winlean]
else:
  import std/posix

const
  KosmoBackgroundFlag* = "--bg"
  KosmoHelpFlag* = "--help"
  KosmoShortHelpFlag* = "-h"
  KosmoUsage* =
    """
Usage: kosmo [--bg] [--] [file-or-folder]

Options:
  --bg       Start Kosmo detached from the invoking shell.
  --         Stop parsing options.
  -h, --help Show this help text.
"""

type KosmoStandaloneCommandLine* = object ## Parsed standalone command-line options.
  background*: bool
  help*: bool
  arguments*: seq[string]
  filePath*: string

proc writeKosmoUsage*() =
  ## Write standalone usage when the process has an attached output handle.
  when defined(windows):
    let
      output = getStdHandle(STD_OUTPUT_HANDLE)
      usage = KosmoUsage
    if output != INVALID_HANDLE_VALUE and output != Handle(0):
      var bytesWritten: int32
      discard winlean.writeFile(
        output, unsafeAddr usage[0], usage.len.int32, addr bytesWritten, nil
      )
  else:
    stdout.write KosmoUsage
    stdout.flushFile()

proc parseKosmoCommandLine*(arguments: openArray[string]): KosmoStandaloneCommandLine =
  ## Parse standalone Kosmo options while retaining every non-option argument.
  var
    optionsEnded: bool
    hasFilePath: bool
  for argument in arguments:
    if optionsEnded:
      result.arguments.add argument
      if not hasFilePath:
        result.filePath = argument
        hasFilePath = true
    else:
      case argument
      of "--":
        optionsEnded = true
        result.arguments.add argument
      of KosmoBackgroundFlag:
        result.background = true
      of KosmoHelpFlag, KosmoShortHelpFlag:
        result.help = true
      else:
        result.arguments.add argument
        if not hasFilePath:
          result.filePath = argument
          hasFilePath = true

when defined(windows):
  const CreateNewProcessGroup = 0x00000200'i32

  proc launchKosmoInBackground*(
      executable: string, arguments: openArray[string], workingDirectory: string
  ) =
    ## Launch Kosmo without a console or a parent process-group dependency.
    var
      security = SECURITY_ATTRIBUTES(
        nLength: sizeof(SECURITY_ATTRIBUTES).int32, bInheritHandle: 1
      )
      startupInfo =
        STARTUPINFO(cb: sizeof(STARTUPINFO).int32, dwFlags: STARTF_USESTDHANDLES)
      processInfo: PROCESS_INFORMATION
      commandParts = @[executable]
    commandParts.add arguments
    let nullHandle = createFileW(
      newWideCString("NUL"),
      GENERIC_READ or GENERIC_WRITE,
      FILE_SHARE_READ or FILE_SHARE_WRITE,
      addr security,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      Handle(0),
    )
    if nullHandle == INVALID_HANDLE_VALUE:
      raiseOSError(osLastError(), "Could not open NUL for detached Kosmo")
    defer:
      discard closeHandle(nullHandle)

    startupInfo.hStdInput = nullHandle
    startupInfo.hStdOutput = nullHandle
    startupInfo.hStdError = nullHandle
    let commandLine = newWideCString(quoteShellCommand(commandParts))
    if createProcessW(
      newWideCString(executable),
      commandLine,
      nil,
      nil,
      1,
      DETACHED_PROCESS or CreateNewProcessGroup or CREATE_UNICODE_ENVIRONMENT,
      nil,
      newWideCString(workingDirectory),
      startupInfo,
      processInfo,
    ) == 0:
      raiseOSError(osLastError(), "Could not start detached Kosmo")
    discard closeHandle(processInfo.hThread)
    discard closeHandle(processInfo.hProcess)

else:
  proc exitBackgroundChild(errorFd: cint) {.noreturn.} =
    let errorCode = errno
    discard write(errorFd, addr errorCode, sizeof(errorCode))
    exitnow(1)

  proc launchKosmoInBackground*(
      executable: string, arguments: openArray[string], workingDirectory: string
  ) =
    ## Double-fork, start a new session, and redirect standard streams before
    ## executing Kosmo. The immediate child is reaped to avoid a zombie.
    var errorPipe: array[0 .. 1, cint]
    if pipe(errorPipe) != 0:
      raiseOSError(osLastError(), "Could not create detached Kosmo error pipe")
    if fcntl(errorPipe[1], F_SETFD, FD_CLOEXEC) == -1:
      discard close(errorPipe[0])
      discard close(errorPipe[1])
      raiseOSError(osLastError(), "Could not configure detached Kosmo error pipe")

    var commandParts = @[executable]
    commandParts.add arguments
    let commandArguments = allocCStringArray(commandParts)
    defer:
      deallocCStringArray(commandArguments)

    let child = fork()
    if child < 0:
      discard close(errorPipe[0])
      discard close(errorPipe[1])
      raiseOSError(osLastError(), "Could not fork detached Kosmo")
    if child == 0:
      discard close(errorPipe[0])
      if setsid() == Pid(-1):
        exitBackgroundChild(errorPipe[1])
      let grandchild = fork()
      if grandchild < 0:
        exitBackgroundChild(errorPipe[1])
      if grandchild > 0:
        exitnow(0)

      let nullFd = open("/dev/null", O_RDWR)
      if nullFd < 0:
        exitBackgroundChild(errorPipe[1])
      for standardFd in 0 .. 2:
        if dup2(nullFd, standardFd.cint) < 0:
          exitBackgroundChild(errorPipe[1])
      if nullFd > 2:
        discard close(nullFd)
      if chdir(workingDirectory) != 0:
        exitBackgroundChild(errorPipe[1])
      discard execv(executable, commandArguments)
      exitBackgroundChild(errorPipe[1])

    discard close(errorPipe[1])
    var childStatus: cint
    if waitpid(child, childStatus, 0) < 0:
      discard close(errorPipe[0])
      raiseOSError(osLastError(), "Could not reap detached Kosmo launcher")
    var launchError: cint
    let bytesRead = read(errorPipe[0], addr launchError, sizeof(launchError))
    discard close(errorPipe[0])
    if bytesRead == sizeof(launchError):
      raiseOSError(OSErrorCode(launchError), "Could not start detached Kosmo")
    if bytesRead < 0:
      raiseOSError(osLastError(), "Could not read detached Kosmo launch status")
    if bytesRead != 0 or childStatus != 0:
      raise newException(OSError, "Detached Kosmo launcher exited unexpectedly")

proc launchKosmoInBackground*(arguments: openArray[string]) =
  ## Relaunch this Kosmo executable from the current working directory.
  let executable = getAppFilename()
  if executable.len == 0:
    raise newException(OSError, "Could not determine the Kosmo executable")
  launchKosmoInBackground(executable, arguments, getCurrentDir())
