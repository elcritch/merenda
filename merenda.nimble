version       = "0.3.0"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit"
license       = "MPL-2.0"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles"
requires "figdraw[siwin] >= 0.22.9"
requires "gh:elcritch/kiwiberry"
requires "siwin#head"
requires "sigils#head"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
