## Copy notices from the pinned native sources used by the static build.
import std/os
import harfbuzzy/private/staticHarfbuzz

let destination = getEnv("KOSMO_TEXT_LICENSE_DIR")
if destination.len == 0:
  raise newException(ValueError, "KOSMO_TEXT_LICENSE_DIR is required")
mkDir(destination)
cpFile(harfbuzzSourceDir.parentDir / "COPYING", destination / "harfbuzz.txt")
cpFile(fribidiSourceDir / "COPYING", destination / "fribidi.txt")
