version       = "0.18.1"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit"
license       = "BSD-3-Clause"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles >= 0.4"
requires "crunchy >= 0.1.11"
requires "siwin#5bc4ce6"
requires "figdraw >= 0.37.4 [siwin, sharedlib, harfbuzz]"
requires "sigils >= 0.28.1 [sigNameAsString, closures, siwin, chronos]"
requires "kiwiberry"
requires "cborious"
requires "unicodedb >= 0.14.0"
requires "faststreams >= 0.5.1"
requires "gh:elcritch/nim-markdown#devel[regex]"
requires "gh:elcritch/matter >= 0.4.3"
requires "gh:elcritch/terminex >= 0.3.2"
requires "gh:Araq/iconbundler"
requires "libbacktrace"
requires "zippy >= 0.10.20"
requires "gh:elcritch/dmon-nim >= 0.5.1"

feature "uirelays":
  requires "gh:nim-lang/uirelays#688dd44"

feature "kosmo":
  requires "gh:elcritch/moe#feature/matter-highlighting"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
