## Standalone MSVC smoke test for the Windows stack-trace compiler settings.
## The release job compiles this separately so its PDB stays beside the process.

when isMainModule:
  import std/strutils

  when not (defined(windows) and defined(vcc)):
    {.error: "Compile this fixture for Windows with --cc:vcc".}

  proc captureFailure() {.noinline.} =
    raise newException(ValueError, "MSVC stack trace probe")

  try:
    captureFailure()
  except ValueError as error:
    let trace = getStackTrace(error)
    doAssert trace.contains("captureFailure"), trace
    doAssert trace.contains("windowsstacktrace.nim"), trace
    echo "MSVC stack trace includes the function and Nim source location"
