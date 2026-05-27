version       = "0.1.2"
author        = "Jaremy Creechley"
description   = "Neovim backend in Nim and FigDraw"
license       = "MPL2"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles"
requires "siwin >= 1.0.1"
requires "figdraw[siwin] >= 0.22.9"
requires "sigils >= 0.20"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"

