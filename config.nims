--define:
  useMalloc
--mm:
  arc
--threads:
  on
--define:
  release
--mangle:
  cpp
--debugger:
  native
--exceptions:
  goto
--stacktrace:
  off
--path:
  "src/"
--nimcache:
  "deps/.nimcache"
when defined(windows) and defined(vcc):
  # Use the configured Developer shell directly; vccexe expands response files
  # into command lines that exceed Windows' limit for large applications.
  switch("vcc.exe", "cl.exe")
  switch("vcc.linkerexe", "cl.exe")
  # MSVC emits PDBs; GNU libbacktrace expects DWARF and a GNU unwinder.
  switch("stackTrace", "on")
  switch("lineTrace", "on")
else:
  switch("define", "nimStackTraceOverride")
  switch("import", "libbacktrace")

when defined(windows) and defined(gcc):
  # The C linker needs libstdc++ for libbacktrace's demangler. Select the
  # static archives explicitly: -static-libstdc++ only affects g++'s own link.
  switch("passL", "-static-libgcc")
  switch("passL", "-Wl,-Bstatic -lstdc++ -lwinpthread -Wl,-Bdynamic")

when defined(freebsd):
  --define:
    libbacktraceUseSystemLibs

when defined(linux) and defined(gcc):
  # GCC 15 promotes Siwin's generated typed-empty-sequence pointer warning to an error.
  switch("passC", "-Wno-error=incompatible-pointer-types")

# FigDraw owns Vulkan dispatch and loads the driver lazily. Disable the Vulkan
# bindings' process-wide eager loader so missing drivers can fall back to OpenGL.
switch("define", "vkCustomLoader")

switch("define", "features.markdown.regex") # temporary hack until we get atlas 0.15.1

# Give bounded TextMate regex probes room for generated native declarations.
switch("define", "MatterTimedRegexStepLimit=100000")

when not defined(figdrawTextBackend):
  when defined(harfbuzzyStatic) or defined(features.harfbuzzy.static):
    # FigDraw defaults static builds to Pixie; retain shaping in bundled builds.
    switch("define", "figdrawTextBackend=harfbuzzy")
  else:
    # Atlas -k can retain the old textBackendHarfbuzzy feature after an upgrade.
    switch("define", "figdrawTextBackend=runtime")

when defined(features.merenda.kosmo):
  switch("define", "moe.embedded")
  switch("define", "features.moe.matter")

import std/strutils
import std/os

when defined(useNativeDynlib):
  quit "Merenda no longer supports useNativeDynlib; remove -d:useNativeDynlib."

const
  referenceDir = "docs/reference"
  openStepSpecUrl = "https://levenez.com/NeXTSTEP/OpenStepSpec.pdf"

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
    "curl -L --fail --show-error -o " & outputFile.quoteShell() & " " & url.quoteShell()
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
      if file.nimFileStemHasPrefix("t") and extractFilename(file) != "tintegrations.nim":
        nimExec("ic", file, extraFlags = "-r", platform = platformArg)

task integration, "run integration tests":
  for platformArg in platforms():
    if platformArg != "":
      echo "Running platform args: ", platformArg
    for file in listFiles("tests"):
      if file.nimFileStemHasPrefix("t"):
        nimExec("ic", file, extraFlags = "-r", platform = platformArg)

task test_compile, "compile unit tests without running":
  for file in listFiles("tests"):
    if file.nimFileStemHasPrefix("nimkit_"):
      nimExec("ic", file)

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

task install_kosmo, "build and install the local macOS Kosmo.app":
  exec("bash packaging/macos/install-local.sh")

when defined(nimkitTerminalTrace):
  switch("define", "terminexTrace")

when defined(merenda.devControl):
  switch("define", "figdraw.vulkanReadback=on")
