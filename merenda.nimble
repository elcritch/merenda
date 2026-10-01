version       = "0.25.2"
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
# Compiled grammar ownership must reclaim recursive rules under ARC.
requires "gh:elcritch/matter#80a1e67815da0e6af2d17a24d26378ae5ae0fdcc"
# Keep search and replacement on the same Reni scanner used by Matter.
requires "gh:fox0430/reni#7703aa83d8bbd358872bbab388b2c62e6798b88a"
# Budgeted reads must preserve final output until the PTY has been drained.
requires "gh:elcritch/terminex#143c79018554c4e81a329a9a898e176df0a92344"
requires "gh:Araq/iconbundler"
requires "libbacktrace"
requires "zippy >= 0.10.20"
requires "gh:elcritch/dmon-nim >= 0.5.2"

feature "uirelays":
  requires "gh:nim-lang/uirelays#688dd44"

feature "kosmo":
  # Upstream develop includes the host result hook merged in Moe PR #3332.
  requires "gh:fox0430/moe#22c74002ff653b0d6ee88e712160d837b4850986"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
