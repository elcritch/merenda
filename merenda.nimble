version       = "0.16.3"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit"
license       = "BSD-3-Clause"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles >= 0.4"
requires "crunchy >= 0.1.11"
requires "gh:elcritch/siwin#5bc4ce6122a8515de00c85da48c847d568600b74"
requires "gh:elcritch/figdraw#fca556bdaa7a2c732ab76ab6a57c7a9c6977effa[siwin, sharedlib, harfbuzz]"
requires "sigils >= 0.27.4 [sigNameAsString, closures, siwin, chronos]"
requires "kiwiberry"
requires "cborious"
requires "unicodedb >= 0.14.0"
requires "faststreams >= 0.5.1"
requires "gh:elcritch/nim-markdown#devel[regex]"
requires "gh:elcritch/matter >= 0.2.2"
requires "gh:elcritch/terminex >= 0.3"
requires "https://github.com/Araq/iconbundler"
requires "libbacktrace"
requires "zippy >= 0.10.20"

feature "uirelays":
  requires "gh:nim-lang/uirelays#688dd44"

feature "kosmo":
  requires "gh:fox0430/moe#18f2e9d"
  # requires "gh:elcritch/moe#integration-improvements"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
