version       = "0.11.0"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit"
license       = "BSD-3-Clause"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles"
requires "siwin#96ca695"
requires "figdraw[siwin, sharedlib, harfbuzz] >= 0.35.1"
requires "sigils[sigNameAsString, closures, siwin] >= 0.27.2"
requires "gh:elcritch/kiwiberry"
requires "cborious"
requires "unicodedb >= 0.14.0"
requires "regex >= 0.26.3"
requires "faststreams >= 0.5.1"

feature "libbacktrace":
  requires "libbacktrace"

feature "uirelays":
  requires "gh:nim-lang/uirelays#688dd44"

feature "kosmo":
  # requires "gh:fox0430/moe#4f18384"
  requires "gh:elcritch/moe#integration-improvements"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
