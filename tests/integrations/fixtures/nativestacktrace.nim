## Separate process because packaging tests strip this executable's symbols.
when isMainModule:
  import std/[os, strutils]

  proc nativeTraceLeaf(): string {.noinline.} =
    result = getStackTrace()
    doAssert result.len > 0, "native trace was lost"

  proc nativeTraceCaller(): string {.noinline.} =
    result = nativeTraceLeaf()
    doAssert result.len > 0

  let trace = nativeTraceCaller()
  echo trace
  when defined(merendaRawStackTraces):
    doAssert "raw[" in trace and " pc=0x" in trace
    doAssert " load=0x" in trace and " addr=0x" in trace and " id=" in trace
    doAssert getAppFilename().extractFilename in trace
  if paramCount() > 0 and paramStr(1) == "--raise":
    raise newException(ValueError, "intentional native trace fixture")
