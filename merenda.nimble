version       = "0.3.0"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit and Objective-C AppKit experiments"
license       = "MPL-2.0"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles"
# requires "siwin >= 1.0.2"
requires "gh:elcritch/siwin#handle-horizontal-scrolling-macos"
requires "figdraw[siwin] >= 0.22.9"
requires "sigils >= 0.22.2"
requires "gh:elcritch/kiwiberry"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
