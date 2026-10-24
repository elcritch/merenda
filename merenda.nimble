version       = "0.27.1"
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
# Merged platform ABI fixes and X11 helpers: https://github.com/levovix0/siwin/pull/58
requires "gh:levovix0/siwin#78bb49c7fd7e5e14590f567e1ccbb07eb5ab6739"
requires "gh:elcritch/figdraw >= 0.44.0 [siwin, harfbuzz]"
requires "sigils >= 0.31.0 [sigNameAsString, closures, siwin, chronos]"
requires "gh:elcritch/variant#fix/ic-type-ids"
requires "gh:elcritch/kiwiberry#4d273da93f67d8e5d6317898851772b32fa635ec"
requires "cborious"
requires "unicodedb >= 0.14.0"
requires "faststreams >= 0.5.1"
requires "gh:elcritch/nim-markdown#fix/arc-emphasis-ownership [regex]"
requires "gh:elcritch/matter >= 0.6.1"
requires "gh:elcritch/terminex >= 0.4.0 [sigils]"
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
  requires "gh:fox0430/moe#8d997efdb79d72a5934389c621efa2754856c824"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
