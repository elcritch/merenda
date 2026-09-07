## Bounded, fully reaped Git commands for background workspace discovery.

import std/[monotimes, os, osproc, times]
when defined(posix):
  import std/posix
elif defined(windows):
  import winim/lean

type GitCommandResult* = object
  output*: string
  exitCode*: int

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

proc runGitCommand*(
    root: string,
    args: openArray[string],
    timeoutMilliseconds: Positive = 10_000,
    cancelled: proc(): bool {.closure, gcsafe.} = nil,
): GitCommandResult =
  ## Drain output while the child runs, avoiding pipe-capacity deadlocks. Never
  ## enable filesystem-monitor hooks: workspace monitoring already belongs to us.
  result.exitCode = -1
  var process: Process
  var arguments = @["-C", root, "--no-optional-locks", "-c", "core.fsmonitor=false"]
  arguments.add args
  try:
    if not cancelled.isNil and cancelled():
      raise newException(IOError, "Git workspace command cancelled")
    process =
      startProcess("git", args = arguments, options = {poUsePath, poStdErrToStdOut})
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
        raise newException(IOError, "Git workspace command cancelled")
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
        if result.output.len + count > 128 * 1024 * 1024:
          raise newException(IOError, "Git output exceeded the workspace limit")
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
        raise newException(IOError, "Git workspace command timed out")
  except CatchableError:
    result.output = getCurrentExceptionMsg()
    result.exitCode = -1
  finally:
    try:
      releaseProcess(process)
    except CatchableError:
      result.output = "Unable to release Git process: " & getCurrentExceptionMsg()
      result.exitCode = -1
