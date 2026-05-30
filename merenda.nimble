version       = "0.1.2"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit and Objective-C AppKit experiments"
license       = "MPL-2.0"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles"
requires "siwin >= 1.0.1"
requires "figdraw[siwin] >= 0.22.9"
requires "sigils >= 0.20.1"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
