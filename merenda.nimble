version       = "0.26.0"
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
requires "siwin#fdec8e4"
requires "gh:elcritch/figdraw >= 0.43.0 [siwin, harfbuzz]"
requires "sigils >= 0.31.0 [sigNameAsString, closures, siwin, chronos]"
requires "gh:elcritch/variant#fix/ic-type-ids"
requires "gh:elcritch/kiwiberry#4d273da93f67d8e5d6317898851772b32fa635ec"
requires "cborious"
requires "unicodedb >= 0.14.0"
requires "faststreams >= 0.5.1"
requires "gh:elcritch/nim-markdown#fix/arc-emphasis-ownership[regex]"
requires "gh:elcritch/matter >= 0.5.2"
requires "gh:elcritch/terminex >= 0.4.0 [sigils]"
requires "gh:Araq/iconbundler"
requires "libbacktrace"
requires "zippy >= 0.10.20"
requires "gh:elcritch/dmon-nim >= 0.5.2"
requires "stylus == 0.1.5"

feature "uirelays":
  requires "gh:nim-lang/uirelays#688dd44"

feature "kosmo":
  # Host results, read/write hooks, and stable targeted buffer deletion.
  requires "gh:fox0430/moe#2ad904c1cc70e8aa783c2533dcb8c4230fa44a48"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
