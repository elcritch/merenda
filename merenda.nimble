version       = "0.20.9"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit"
license       = "BSD-3-Clause"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles >= 0.4"
requires "chroniclers >= 0.6"
requires "crunchy >= 0.1.11"
# Native damage must request onRender: https://github.com/levovix0/siwin/pull/55
requires "gh:elcritch/siwin#fdec8e4"
requires "gh:elcritch/figdraw >= 0.41.0 [siwin, sharedlib, harfbuzz]"
requires "sigils >= 0.30.0 [sigNameAsString, closures, siwin, chronos]"
requires "gh:elcritch/variant#fix/ic-type-ids"
requires "kiwiberry"
requires "cborious"
requires "unicodedb >= 0.14.0"
requires "faststreams >= 0.5.1"
requires "gh:elcritch/nim-markdown#fix/arc-emphasis-ownership[regex]"
requires "gh:elcritch/matter >= 0.5.0"
requires "gh:elcritch/terminex >= 0.3.2"
requires "gh:Araq/iconbundler"
requires "libbacktrace"
requires "zippy >= 0.10.20"
requires "gh:elcritch/dmon-nim >= 0.5.1"

feature "uirelays":
  requires "gh:nim-lang/uirelays#688dd44"

feature "kosmo":
  requires "gh:fox0430/moe#8de7be4"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
