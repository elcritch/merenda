version       = "0.15.4"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit"
license       = "BSD-3-Clause"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles >= 0.4"
requires "crunchy >= 0.1.11"
requires "siwin#96ca695"
requires "figdraw >= 0.35.2 [siwin, sharedlib, harfbuzz]"
requires "sigils >= 0.27.4 [sigNameAsString, closures, siwin, chronos]"
requires "gh:elcritch/kiwiberry"
requires "cborious"
requires "unicodedb >= 0.14.0"
requires "faststreams >= 0.5.1"
requires "gh:elcritch/nim-markdown#devel[regex]"
requires "gh:elcritch/terminex >= 0.2.1"
requires "https://github.com/Araq/iconbundler"

feature "libbacktrace":
  requires "libbacktrace"

feature "uirelays":
  requires "gh:nim-lang/uirelays#688dd44"

feature "kosmo":
  requires "gh:elcritch/moe#affa5c8fbd40"
  # requires "gh:elcritch/moe#integration-improvements"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
