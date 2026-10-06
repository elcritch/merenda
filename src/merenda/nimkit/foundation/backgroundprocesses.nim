## Bounded, fully reaped subprocesses for background work.

import std/[monotimes, os, osproc, times, strtabs]
when defined(posix):
  import std/posix
elif defined(windows):
  import winim/lean

type BackgroundCommandResult* = object
  output*: string
  exitCode*: int
  outputLimitExceeded*: bool

proc releaseProcess(process: var Process) =
  if process.isNil:
    return
  try:
    if process.running():
      try:
        process.terminate()
      except OSError:
        if process.running():
          process.kill()
      if process.waitForExit(100) == -1:
        process.kill()
    discard process.waitForExit()
  finally:
    process.close()
    process = nil

proc runBackgroundCommand*(
    executable: string,
    args: openArray[string],
    workingDirectory = "",
    timeoutMilliseconds: Positive = 10_000,
    cancelled: proc(): bool {.closure, gcsafe.} = nil,
    maxOutputBytes: Natural = 128 * 1024 * 1024,
    environment: StringTableRef = nil,
    diagnosticName = "Background command",
): BackgroundCommandResult =
  ## Execute argument vectors directly, drain bounded output, and reap on every exit.
  result.exitCode = -1
  var process: Process
  try:
    if not cancelled.isNil and cancelled():
      raise newException(IOError, diagnosticName & " cancelled")
    when defined(posix):
      if workingDirectory.len > 0:
        # osproc's posix_spawn path temporarily changes the parent's cwd and
        # can fail before restoring it. env changes only the child's directory
        # and replaces itself with our command, preserving one process to reap.
        var arguments = @["-C", workingDirectory, "--", executable]
        arguments.add args
        process = startProcess(
          "/usr/bin/env",
          args = arguments,
          env = environment,
          options = {poStdErrToStdOut},
        )
      else:
        process = startProcess(
          executable,
          args = args,
          env = environment,
          options = {poUsePath, poStdErrToStdOut},
        )
    else:
      process = startProcess(
        executable,
        workingDir = workingDirectory,
        args = args,
        env = environment,
        options = {poUsePath, poStdErrToStdOut},
      )
    let handle = process.outputHandle()
    when defined(posix):
      let flags = fcntl(handle, F_GETFL)
      if flags < 0 or fcntl(handle, F_SETFL, flags or O_NONBLOCK) < 0:
        raiseOSError(osLastError())
    let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
    var buffer: array[16_384, char]
    var exited = false
    while true:
      if not cancelled.isNil and cancelled():
        raise newException(IOError, diagnosticName & " cancelled")
      var count = 0
      when defined(posix):
        count = posix.read(handle, addr buffer[0], buffer.len).int
        if count < 0 and errno notin [EAGAIN, EINTR]:
          raiseOSError(osLastError())
      elif defined(windows):
        var available, bytesRead: DWORD
        if PeekNamedPipe(cast[HANDLE](handle), nil, 0, nil, addr available, nil) != 0 and
            available > 0:
          if ReadFile(
            cast[HANDLE](handle),
            addr buffer[0],
            min(available.int, buffer.len).DWORD,
            addr bytesRead,
            nil,
          ) == 0:
            raiseOSError(osLastError())
          count = bytesRead.int
      if count > 0:
        if maxOutputBytes > 0 and result.output.len + count > maxOutputBytes:
          result.outputLimitExceeded = true
          raise newException(
            IOError, diagnosticName & " output exceeded the configured limit"
          )
        let offset = result.output.len
        result.output.setLen(offset + count)
        copyMem(addr result.output[offset], addr buffer[0], count)
      elif exited:
        result.exitCode = process.waitForExit()
        break
      elif not process.running():
        # Drain once more after observing exit; output may have arrived between
        # the empty nonblocking read and the child closing its pipe.
        exited = true
      else:
        sleep(5)
      if getMonoTime() >= deadline:
        raise newException(IOError, diagnosticName & " timed out")
  except CatchableError:
    result.output = getCurrentExceptionMsg()
    result.exitCode = -1
  finally:
    try:
      releaseProcess(process)
    except CatchableError:
      result.output =
        "Unable to release " & diagnosticName & " process: " & getCurrentExceptionMsg()
      result.exitCode = -1
