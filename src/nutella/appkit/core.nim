import std/[math, os, strutils, unicode]
import pkg/chroma
import pkg/vmath

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as figrender
import figdraw/windowing/siwinshim as siwinshim

import ../objc
import ../objc/ivar
import ./types

include ./core_parts/runtime
include ./core_parts/view_control
include ./core_parts/rendering
include ./core_parts/application
