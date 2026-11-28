version       = "0.32.9"
author        = "Jaremy Creechley"
description   = "Nim-native UI toolkit"
license       = "BSD-3-Clause"
srcDir        = "src"
bin           = @["merenda/kosmo/kosmo"]

# Dependencies
requires "nim >= 2.2.10"
requires "msgpack4nim"
requires "parsetoml >= 0.7.2"
requires "chronicles >= 0.4"
requires "chroniclers >= 0.6"
requires "crunchy >= 0.1.11"
# This revision loads Vulkan lazily so a missing driver can use OpenGL.
#requires "gh:elcritch/siwin#fix/cocoa-stale-ime-state"
requires "gh:elcritch/figdraw >= 0.49.0 [siwin]"
requires "harfbuzzy >= 0.7.1 [runtime]"
requires "sigils >= 0.37.3 [sigNameAsString, closures, siwin]"
requires "gh:elcritch/variant#fix/ic-type-ids"
requires "kiwiberry ^= 0.6.1"
requires "cborious"
requires "unicodedb >= 0.14.0"
requires "faststreams >= 0.5.1"
requires "gh:elcritch/nim-markdown#fix/arc-emphasis-ownership [regex]"
requires "gh:elcritch/matter >= 0.6.2"
requires "reni#fbf085a"
requires "gh:elcritch/terminex == 0.4.2"
requires "gh:Araq/iconbundler"
requires "libbacktrace"
requires "zippy >= 0.10.20"
requires "gh:elcritch/dmon-nim >= 0.5.2"
requires "stylus == 0.1.5"

feature "nifDemo":
  requires "gh:openpeeps/openparser >= 0.4.1"

feature "uirelays":
  requires "gh:nim-lang/uirelays#688dd44"

feature "chronos":
  requires "gh:status-im/nim-chronos >= 4.2.0"

feature "terminal":
  # Terminex's threaded sessions use Chronos.
  requires "gh:status-im/nim-chronos >= 4.2.0"

feature "kosmo":
  requires "gh:status-im/nim-chronos >= 4.2.0"
  requires "gh:fox0430/moe#195dcd8946705eb6a7445bebfc3a18b075576aab"

feature "references":
  requires "https://github.com/ravynsoft/ravynos"
  requires "https://github.com/elcritch/figuro"
  requires "https://github.com/treeform/windy"
