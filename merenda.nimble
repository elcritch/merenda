version       = "0.4.0"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit"
license       = "BSD-3-Clause"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles"
requires "figdraw[siwin, sharedlib, harfbuzz] >= 0.26.1"
requires "gh:elcritch/kiwiberry"
requires "siwin#063fc0f"
requires "sigils >= 0.24.3"

feature "libbacktrace":
  requires "libbacktrace"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"

