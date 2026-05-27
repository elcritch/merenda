version       = "0.1.2"
author        = "Jaremy Creechley"
description   = "Neovim backend in Nim and FigDraw"
license       = "MPL2"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.6"
requires "msgpack4nim"
requires "chronicles"
requires "https://github.com/elcritch/figdraw[siwin] >= 0.22.5"
requires "sigils"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"

