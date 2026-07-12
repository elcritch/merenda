--nimcache:
  ".nimcache/"
--define:
  useMalloc
--mm:
  arc
--define:
  release
--mangle:
  cpp
--debugger:
  native

import std/strutils
import std/os

when defined(useNativeDynlib):
  switch("path", "../figdraw/bin")

const
  referenceDir = "docs/reference"
  openStepSpecUrl = "https://levenez.com/NeXTSTEP/OpenStepSpec.pdf"

when defined(feature.merenda.libbacktrace):
  --stacktrace:
    off
  --define:
    nimStackTraceOverride
  switch("import", "libbacktrace")
  when defined(freebsd):
    --define:
      libbacktraceUseSystemLibs

when defined(macosx) and defined(figdraw.moltenvkBrew):
  let moltenVkPrefix = gorgeEx("brew --prefix molten-vk").output.strip()
  if moltenVkPrefix.len == 0:
    quit "figdraw.moltenvkBrew requires Homebrew molten-vk"
  switch("passL", "-Wl,-rpath," & moltenVkPrefix & "/lib")

proc nimExec(subcmd, file: string, extraFlags = "", platform = "") =
  let nimFlags = getEnv("NIMFLAGS").strip()
  var cmd: string
  cmd.add(platform)
  cmd.add("nim " & subcmd)
  cmd.add(" " & nimFlags)
  cmd.add(" " & extraFlags)
  cmd.add(" " & file)
  exec(cmd)

proc nimFileStemHasPrefix(file, prefix: string): bool =
  let (_, stem, ext) = splitFile(file)
  ext == ".nim" and stem.startsWith(prefix)

proc downloadReference(url, outputFile: string) =
  exec("mkdir -p " & parentDir(outputFile).quoteShell())
  exec(
    "curl -L --fail --show-error -o " & outputFile.quoteShell() & " " &
      url.quoteShell()
  )

proc platforms(): seq[string] =
  when defined(linux) or defined(bsd):
    let
      sessionType = getEnv("XDG_SESSION_TYPE").toLowerAscii()
      hasWaylandDisplay = getEnv("WAYLAND_DISPLAY").len != 0
      hasX11Display = getEnv("DISPLAY").len != 0
      forceOpenGlOnly =
        getEnv("MERENDA_TEST_OPENGL_ONLY").normalize() in ["1", "true", "yes"]
    if hasWaylandDisplay or sessionType == "wayland":
      if not forceOpenGlOnly:
        result.add "XDG_SESSION_TYPE=wayland FIGDRAW_FORCE_OPENGL=0 "
      result.add "XDG_SESSION_TYPE=wayland FIGDRAW_FORCE_OPENGL=1 "
    if hasX11Display or sessionType == "x11":
      if not forceOpenGlOnly:
        result.add "XDG_SESSION_TYPE=x11 FIGDRAW_FORCE_OPENGL=0 "
      result.add "XDG_SESSION_TYPE=x11 FIGDRAW_FORCE_OPENGL=1 "
  else:
    @[""]

task test, "run unit test":
  for platformArg in platforms():
    if platformArg != "":
      echo "Running platform args: ", platformArg
    for file in listFiles("tests"):
      if file.nimFileStemHasPrefix("t"):
        nimExec("r", file, platform = platformArg)

task integration, "run integration tests":
  for platformArg in platforms():
    if platformArg != "":
      echo "Running platform args: ", platformArg
    for file in listFiles("tests"):
      if file.nimFileStemHasPrefix("t"):
        nimExec("r", file, platform = platformArg)

task test_compile, "compile unit tests without running":
  for file in listFiles("tests"):
    if file.nimFileStemHasPrefix("nimkit_"):
      nimExec("c", file)

task examples, "compile examples":
  for file in listFiles("examples"):
    if nimFileStemHasPrefix(file, ""):
      nimExec("c", file)

task test_compile_examples, "compile examples (legacy compatibility task)":
  for file in listFiles("examples"):
    if nimFileStemHasPrefix(file, ""):
      nimExec("c", file)

task test_emscripten, "build emscripten examples":
  for file in listFiles("examples"):
    if nimFileStemHasPrefix(file, "windy_"):
      nimExec("c", file, "-d:emscripten")

task download_references, "download local study copies of reference docs":
  let openStepSpecPdf = referenceDir / "OpenStepSpec.pdf"
  downloadReference(openStepSpecUrl, openStepSpecPdf)
  echo "Downloaded ", openStepSpecPdf
  echo "OpenStep UI guidelines remain link-only; their notice restricts copying."
