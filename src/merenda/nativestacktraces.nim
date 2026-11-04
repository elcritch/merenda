## Native traces with relocatable addresses for offline symbolication.
## Release builds can archive debug files separately using merendaRawStackTraces.

when not defined(nimscript) and not defined(js):
  import std/os
  import pkg/libbacktrace as nativeBacktrace
  import system/stacktraces

  # These callbacks also run while a goto-based exception is pending. As in
  # libbacktrace, compiler-inserted defect checks would abort trace construction.
  {.
    push
    stackTrace: off,
    lineTrace: off,
    checks: off,
    assertions: off,
    raises: [],
    gcsafe
  .}

  const
    merendaRawStackTraces {.booldefine.} = false
    frameHeader = currentSourcePath().parentDir / "nativeframeinfo.h"

  {.compile: "nativeframeinfo.c".}

  type FrameInfo {.importc: "MerendaFrameInfo", header: frameHeader, bycopy.} = object
    loadBase, symbolAddress: uint
    imageName: array[1024, char]
    imageId: array[160, char]

  proc frameInfo(
    pc: uint, info: ptr FrameInfo
  ): cint {.importc: "merenda_frame_info", header: frameHeader, cdecl.}

  proc hexAddress(value: uint): string =
    const digits = "0123456789abcdef"
    result = newString(2 * sizeof(uint))
    var remaining = value
    for index in countdown(result.high, 0):
      result[index] = digits[int(remaining and 15)]
      remaining = remaining shr 4

  proc rawFrame(pc: uint): string =
    var info: FrameInfo
    result = "raw[" & hostOS & "/" & hostCPU & "] pc=0x" & hexAddress(pc)
    if frameInfo(pc, addr info) != 0:
      result.add " load=0x" & hexAddress(info.loadBase)
      result.add " addr=0x" & hexAddress(info.symbolAddress)
      result.add " id=" & $cast[cstring](addr info.imageId[0])
      result.add " image=" & $cast[cstring](addr info.imageName[0])

  proc traceEntries(
      pcs: seq[cuintptr_t], maxLength: cint
  ): seq[StackTraceEntry] {.noinline, tags: [].} =
    when not merendaRawStackTraces:
      result = nativeBacktrace.getDebuggingInfo(pcs, maxLength)
      if result.len != 0:
        return
    for pc in pcs:
      if result.len >= maxLength.int:
        break
      result.add StackTraceEntry(procnameStr: rawFrame(pc.uint))
    for entry in result.mitems:
      entry.procname = entry.procnameStr.cstring

  proc traceText(): string {.noinline, tags: [].} =
    let entries = traceEntries(nativeBacktrace.getProgramCounters(128), 128)
    for entry in entries:
      if entry.filename != nil:
        result.add $entry.filename & "(" & $entry.line & "): "
      if entry.procname != nil:
        result.add $entry.procname
      result.add '\n'

  when defined(nimStackTraceOverride):
    registerStackTraceOverrideGetDebuggingInfo(traceEntries)
    registerStackTraceOverride(traceText)

  {.pop.}
