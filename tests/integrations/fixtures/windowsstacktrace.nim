## Standalone smoke test for the Windows stack-trace compiler settings.

when isMainModule:
  import std/strutils

  when not defined(windows):
    {.error: "Compile this fixture for Windows".}

  proc captureFailure() {.noinline.} =
    raise newException(ValueError, "Windows stack trace probe")

  try:
    captureFailure()
  except ValueError as error:
    let trace = getStackTrace(error)
    doAssert trace.contains("captureFailure"), trace
    doAssert trace.contains("windowsstacktrace.nim"), trace
    echo "Windows stack trace includes the function and Nim source location"
