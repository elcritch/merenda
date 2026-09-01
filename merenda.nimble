version       = "0.12.0"
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
requires "figdraw[siwin,sharedlib,harfbuzz] >= 0.35.2"
requires "sigils[sigNameAsString,closures,siwin,chronos] >= 0.27.4"
requires "gh:elcritch/kiwiberry"
requires "cborious"
requires "unicodedb >= 0.14.0"
requires "faststreams >= 0.5.1"
requires "gh:elcritch/nim-markdown[regex]#devel"
requires "regex >= 0.26.3" # markdown[regex] backend; see nim-lang/nimble#1832

feature "libbacktrace":
  requires "libbacktrace"

feature "uirelays":
  requires "gh:nim-lang/uirelays#688dd44"

feature "kosmo":
  requires "gh:fox0430/moe#532c657"
  # requires "gh:elcritch/moe#integration-improvements"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
