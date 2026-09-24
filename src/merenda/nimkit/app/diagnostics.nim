import std/os
when defined(linux):
  import std/strutils

when defined(posix):
  import std/posix_utils
  import std/posix

when defined(macosx):
  type ProcTaskInfo {.
    importc: "struct proc_taskinfo", header: "<sys/proc_info.h>", bycopy
  .} = object
    pti_virtual_size, pti_resident_size: uint64
    pti_total_user, pti_total_system, pti_threads_user, pti_threads_system: uint64
    pti_policy, pti_faults, pti_pageins, pti_cow_faults: int32
    pti_messages_sent, pti_messages_received, pti_syscalls_mach, pti_syscalls_unix:
      int32
    pti_csw, pti_threadnum, pti_numrunning, pti_priority: int32

  proc procPidInfo(
    pid, flavor: cint, arg: uint64, buffer: pointer, size: cint
  ): cint {.importc: "proc_pidinfo", header: "<libproc.h>", cdecl.}

  proc procListChildPids(
    pid: cint, buffer: pointer, size: cint
  ): cint {.importc: "proc_listchildpids", header: "<libproc.h>", cdecl.}

import pkg/chronicles

type RuntimeEnvironmentDiagnostics* = object
  targetOS*, targetCPU*: string
  osName*, osRelease*, osVersion*, architecture*: string
  xdgSessionType*, display*, waylandDisplay*: string
  currentDesktop*, desktopSession*: string
  figdrawBackend*, forceOpenGl*, softwareOpenGl*: string
  nimkitUiScale*, nimkitCompactUiScale*, merendaUiScale*: string
  uiScale*, legacyUiScale*: string

type ProcessResourceUsage* = object
  ## OS observations for diagnostics, including native allocations. Unsupported
  ## or unavailable measurements are -1. RSS is not a count of live Nim objects.
  residentBytes*, peakResidentBytes*: int64
  fileDescriptors*, childProcesses*, threads*: int

proc processResourceUsage*(): ProcessResourceUsage =
  ## Read this process's memory and resource counts without launching a child.
  ## Implemented on macOS and Linux; individual unavailable values remain -1.
  result = ProcessResourceUsage(
    residentBytes: -1,
    peakResidentBytes: -1,
    fileDescriptors: -1,
    childProcesses: -1,
    threads: -1,
  )
  when defined(macosx):
    var info: ProcTaskInfo
    if procPidInfo(getCurrentProcessId().cint, 4, 0, addr info, sizeof(info).cint) ==
        sizeof(info).cint:
      result.residentBytes = info.pti_resident_size.int64
      result.threads = info.pti_threadnum.int
    let required = procListChildPids(getCurrentProcessId().cint, nil, 0)
    if required >= 0:
      var children = newSeq[cint](required.int + 16)
      let count = procListChildPids(
        getCurrentProcessId().cint, addr children[0], (children.len * sizeof(cint)).cint
      )
      if count >= 0 and count.int < children.len:
        result.childProcesses = count.int
    var usage: Rusage
    if getrusage(RUSAGE_SELF, addr usage) == 0:
      result.peakResidentBytes = usage.ru_maxrss.int64
  elif defined(linux):
    try:
      for line in readFile("/proc/self/status").splitLines():
        let fields = line.splitWhitespace()
        if fields.len >= 2:
          case fields[0]
          of "VmRSS:":
            result.residentBytes = fields[1].parseBiggestInt() * 1024
          of "VmHWM:":
            result.peakResidentBytes = fields[1].parseBiggestInt() * 1024
          of "Threads:":
            result.threads = fields[1].parseInt()
          else:
            discard
      result.childProcesses = 0
      for kind, task in walkDir("/proc/self/task"):
        if kind == pcDir:
          result.childProcesses += readFile(task / "children").splitWhitespace().len
    except CatchableError:
      result.childProcesses = -1
  when defined(macosx) or defined(linux):
    try:
      let directory = when defined(linux): "/proc/self/fd" else: "/dev/fd"
      var count = 0
      for _ in walkDir(directory):
        inc count
      result.fileDescriptors = count
    except OSError:
      discard

var runtimeEnvironmentLogged {.threadvar.}: bool

proc runtimeEnvironmentDiagnostics*(): RuntimeEnvironmentDiagnostics =
  result.targetOS = hostOS
  result.targetCPU = hostCPU
  result.osName = hostOS
  result.architecture = hostCPU

  when defined(posix):
    try:
      let systemInfo = uname()
      result.osName = systemInfo.sysname
      result.osRelease = systemInfo.release
      result.osVersion = systemInfo.version
      result.architecture = systemInfo.machine
    except OSError:
      discard
  elif defined(windows):
    let windowsName = getEnv("OS")
    if windowsName.len > 0:
      result.osName = windowsName
    let windowsArchitecture = getEnv("PROCESSOR_ARCHITECTURE")
    if windowsArchitecture.len > 0:
      result.architecture = windowsArchitecture

  result.xdgSessionType = getEnv("XDG_SESSION_TYPE")
  result.display = getEnv("DISPLAY")
  result.waylandDisplay = getEnv("WAYLAND_DISPLAY")
  result.currentDesktop = getEnv("XDG_CURRENT_DESKTOP")
  result.desktopSession = getEnv("DESKTOP_SESSION")
  result.figdrawBackend = getEnv("FIGDRAW_BACKEND")
  result.forceOpenGl = getEnv("FIGDRAW_FORCE_OPENGL")
  result.softwareOpenGl = getEnv("FIGDRAW_SOFTWARE_GL")
  result.nimkitUiScale = getEnv("NIMKIT_UI_SCALE")
  result.nimkitCompactUiScale = getEnv("NIMKIT_UISCALE")
  result.merendaUiScale = getEnv("MERENDA_UISCALE")
  result.uiScale = getEnv("UISCALE")
  result.legacyUiScale = getEnv("HDI")

proc logRuntimeEnvironment*() =
  if runtimeEnvironmentLogged:
    return
  runtimeEnvironmentLogged = true

  let environment = runtimeEnvironmentDiagnostics()
  info "Merenda operating system",
    targetOS = environment.targetOS,
    targetCPU = environment.targetCPU,
    osName = environment.osName,
    osRelease = environment.osRelease,
    osVersion = environment.osVersion,
    architecture = environment.architecture
  info "Merenda runtime",
    nimVersion = NimVersion,
    threads = compileOption("threads"),
    nativeDynlib = defined(useNativeDynlib)
  info "Merenda desktop and display",
    xdgSessionType = environment.xdgSessionType,
    display = environment.display,
    waylandDisplay = environment.waylandDisplay,
    currentDesktop = environment.currentDesktop,
    desktopSession = environment.desktopSession
  info "Merenda and FigDraw environment settings",
    figdrawBackend = environment.figdrawBackend,
    forceOpenGl = environment.forceOpenGl,
    softwareOpenGl = environment.softwareOpenGl,
    nimkitUiScale = environment.nimkitUiScale,
    nimkitCompactUiScale = environment.nimkitCompactUiScale,
    merendaUiScale = environment.merendaUiScale,
    uiScale = environment.uiScale,
    legacyUiScale = environment.legacyUiScale
