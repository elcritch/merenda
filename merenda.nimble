version       = "0.8.2"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit"
license       = "BSD-3-Clause"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles"
requires "gh:elcritch/figdraw#toasty-updates"
requires "figdraw[siwin, sharedlib, harfbuzz]"
requires "gh:elcritch/kiwiberry"
requires "gh:elcritch/siwin#toasty-updates"
requires "sigils[sigNameAsString, closures] >= 0.25.3"
requires "cborious"

feature "libbacktrace":
  requires "libbacktrace"

feature "uirelays":
  requires "gh:nim-lang/uirelays#688dd44"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
