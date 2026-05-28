--nimcache:
  ".nimcache/"
--passc:
  "-Wno-incompatible-function-pointer-types"
--define:
  useMalloc
--mm:
  arc

import std/strutils
import std/os

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

proc isDefaultTest(file: string): bool =
  file.nimFileStemHasPrefix("t") and not file.nimFileStemHasPrefix("tappkit_")

proc isAppKitTest(file: string): bool =
  file.nimFileStemHasPrefix("tappkit_")

proc isDefaultExample(file: string): bool =
  file.nimFileStemHasPrefix("") and not file.nimFileStemHasPrefix("appkit_")

proc isAppKitExample(file: string): bool =
  file.nimFileStemHasPrefix("appkit_")

proc platforms(): seq[string] =
  when defined(linux) or defined(bsd):
    let
      sessionType = getEnv("XDG_SESSION_TYPE").toLowerAscii()
      hasWaylandDisplay = getEnv("WAYLAND_DISPLAY").len != 0
      hasX11Display = getEnv("DISPLAY").len != 0
    if hasWaylandDisplay or sessionType == "wayland":
      result.add "XDG_SESSION_TYPE=wayland FIGDRAW_FORCE_OPENGL=0 "
      result.add "XDG_SESSION_TYPE=wayland FIGDRAW_FORCE_OPENGL=1 "
    if hasX11Display or sessionType == "x11":
      result.add "XDG_SESSION_TYPE=x11 FIGDRAW_FORCE_OPENGL=0 "
      result.add "XDG_SESSION_TYPE=x11 FIGDRAW_FORCE_OPENGL=1 "
  else:
    @[""]

task test, "run unit test":
  for platformArg in platforms():
    if platformArg != "":
      echo "Running platform args: ", platformArg
    for file in listFiles("tests"):
      if isDefaultTest(file):
        nimExec("r", file, platform = platformArg)

  for file in listFiles("examples"):
    if isDefaultExample(file):
      nimExec("c", file)

task testAppKit, "run AppKit tests":
  for platformArg in platforms():
    if platformArg != "":
      echo "Running platform args: ", platformArg
    for file in listFiles("tests"):
      if isAppKitTest(file):
        nimExec("r", file, platform = platformArg)

  for file in listFiles("examples"):
    if isAppKitExample(file):
      nimExec("c", file)

task test_compile, "compile unit tests without running":
  for file in listFiles("tests"):
    if nimFileStemHasPrefix(file, "t"):
      nimExec("c", file)

task test_compile_examples, "compile unit tests without running":
  for file in listFiles("examples"):
    if nimFileStemHasPrefix(file, ""):
      nimExec("c", file)

task test_emscripten, "build emscripten examples":
  for file in listFiles("examples"):
    if nimFileStemHasPrefix(file, "windy_"):
      nimExec("c", file, "-d:emscripten")
