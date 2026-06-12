version       = "0.3.0"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit"
license       = "BSD-3-Clause"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles"
requires "figdraw[siwin, sharedlib] >= 0.24.0"
requires "gh:elcritch/kiwiberry"
requires "siwin#head"
requires "sigils >= 0.23.0"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
