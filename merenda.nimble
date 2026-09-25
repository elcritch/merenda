version       = "0.23.0"
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
requires "siwin#fdec8e4"
# Render ownership and GPU completion require FigDraw 0.43.0.
requires "gh:elcritch/figdraw >= 0.43.0 [siwin, harfbuzz]"
requires "sigils >= 0.31.0 [sigNameAsString, closures, siwin, chronos]"
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
  # Host hooks and nonblocking Git pipe reads are supplied by this Moe branch.
  requires "gh:elcritch/moe#feat/kosmo-host-ui"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
