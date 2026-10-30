version       = "0.30.2"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit"
license       = "BSD-3-Clause"
srcDir        = "src"
bin           = @["merenda/kosmo/kosmo"]

# Dependencies
requires "nim >= 2.2.10"
requires "msgpack4nim"
requires "chronicles >= 0.4"
requires "chroniclers >= 0.6"
requires "crunchy >= 0.1.11"
# Includes ABI/X11 fixes, nonactivating windows, and FigDraw's WinAPI fallback API.
requires "siwin#5827ee9dadb5e2597db85375e0e87b8a2272174b"
# This revision loads Vulkan lazily so a missing driver can use OpenGL.
requires "gh:elcritch/figdraw >= 0.46.4 [siwin]"
requires "harfbuzzy >= 0.7.0 [runtime]"
requires "sigils >= 0.32.1 [sigNameAsString, closures, siwin, chronos]"
requires "gh:elcritch/variant#fix/ic-type-ids"
requires "kiwiberry#4d273da93f67d8e5d6317898851772b32fa635ec"
requires "cborious"
requires "unicodedb >= 0.14.0"
requires "faststreams >= 0.5.1"
requires "gh:elcritch/nim-markdown#fix/arc-emphasis-ownership [regex]"
requires "gh:elcritch/matter >= 0.6.2"
requires "reni#fbf085a"
requires "gh:elcritch/terminex == 0.4.2 [sigils]"
requires "gh:Araq/iconbundler"
requires "libbacktrace"
requires "zippy >= 0.10.20"
requires "gh:elcritch/dmon-nim >= 0.5.2"
requires "stylus == 0.1.5"

feature "nifDemo":
  requires "gh:openpeeps/openparser >= 0.4.1"

feature "uirelays":
  requires "gh:nim-lang/uirelays#688dd44"

feature "kosmo":
  requires "gh:fox0430/moe#fb804e2c00977428af98361d1a075ac2306b7856"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
