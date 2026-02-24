import std/[math, os, strutils, unicode]
import pkg/chroma
import pkg/vmath

import figdraw/commons
import figdraw/fignodes

import ../objc
import ./types

export objc, types

proc toFigColor*(c: NSColor): Color {.inline.} =
  color(c.r, c.g, c.b, c.a)

proc toFigRgba*(c: NSColor): ColorRGBA {.inline.} =
  rgba(c.toFigColor())

proc solidFill*(c: NSColor): Fill {.inline.} =
  fill(c.toFigRgba())

var appkitTypefaceId* {.threadvar.}: TypefaceId
var appkitFontReady* {.threadvar.}: bool
var appkitFontUnavailable* {.threadvar.}: bool

proc appkitFontCandidates*(): seq[string] =
  result = @["Ubuntu.ttf", "HackNerdFont-Regular.ttf"]
  let dir = figDataDir()
  if not dirExists(dir):
    return
  for kind, path in walkDir(dir):
    if kind != pcFile:
      continue
    let (_, name, ext) = splitFile(path)
    let lowerExt = ext.toLowerAscii()
    if lowerExt notin [".ttf", ".otf"]:
      continue
    let fileName = name & ext
    if fileName notin result:
      result.add(fileName)

proc ensureAppKitFont*(): bool =
  if appkitFontReady:
    return true
  if appkitFontUnavailable:
    return false
  for candidate in appkitFontCandidates():
    try:
      appkitTypefaceId = loadTypeface(candidate)
      appkitFontReady = true
      return true
    except Exception:
      discard
  appkitFontUnavailable = true
  false

proc appkitFont*(size: float32): FigFont {.inline.} =
  appkitTypefaceId.fontWithSize(size)

proc uniformCorners*(radius: float32): array[DirectionCorners, float32] {.inline.} =
  [radius, radius, radius, radius]

proc clampWindowSize*(v: float32): int32 {.inline.} =
  if v < 1.0: 1 else: v.round.int32

proc toFontHorizontal*(alignment: NSTextAlignment): FontHorizontal {.inline.} =
  case alignment
  of NSRightTextAlignment: FontHorizontal.Right
  of NSCenterTextAlignment: FontHorizontal.Center
  else: FontHorizontal.Left

proc normalizeButtonState*(value: int, allowsMixedState: bool): int {.inline.} =
  if value == NSMixedState and allowsMixedState:
    return NSMixedState
  if value == NSOnState:
    return NSOnState
  NSOffState

proc stripMnemonicMarkers*(value: NSString): NSString =
  let src = $value
  var i = 0
  var dst = newStringOfCap(src.len)
  while i < src.len:
    if src[i] != '&':
      dst.add(src[i])
      inc i
      continue
    if i + 1 >= src.len:
      inc i
      continue
    if src[i + 1] == '&':
      dst.add('&')
      i += 2
      continue
    dst.add(src[i + 1])
    i += 2
  result = ns(dst)

proc initOwned*[T: NSObject](allocated: sink T): T {.inline.} =
  var obj = move(allocated)
  result = obj.init()
  obj.value = nil

proc ownFromId*[T: NSObject](id: ID): T =
  if id.isNil:
    return T(value: nil)
  var borrowed = asType[T](id)
  result = retain(borrowed)
  borrowed.value = nil

proc retainId*(id: ID): ID =
  if id.isNil:
    return nil
  var borrowed = asType[NSObject](id)
  var owned = retain(borrowed)
  borrowed.value = nil
  result = owned.value
  owned.value = nil

proc releaseId*(id: ID) =
  if id.isNil:
    return
  var owned = asType[NSObject](id)
  discard owned

proc replacedOwnedId*(slot: ID, next: ID): ID =
  if slot == next:
    return slot
  result = retainId(next)
  releaseId(slot)

proc clearOwnedIds*(ids: var seq[ID]) =
  for id in ids:
    releaseId(id)
  ids.setLen(0)

proc removeOwnedIdAt*(ids: var seq[ID], idx: int) =
  let old = ids[idx]
  ids.del(idx)
  releaseId(old)

template callSuperIdFrom*(currentType: typedesc, obj: NSObject, op: SEL): ID =
  block:
    var superObj =
      ObjcSuper(receiver: obj.value, superClass: getClass(currentType).getSuperclass())
    cast[proc(superObj: var ObjcSuper, selParam: SEL): ID {.cdecl, varargs.}](objc_msgSendSuper)(
      superObj, op
    )

proc performResponderSelector*(target: NSObject, action: SEL, sender: NSObject): bool =
  if target.isNil or cast[pointer](action).isNil:
    return false
  let cls = getClass(target.value)
  if cls.isNil or not cls.respondsToSelector(action):
    return false
  let meth = cls.getInstanceMethod(action)
  if cast[pointer](meth) == nil:
    return false
  case meth.getNumberOfArguments()
  of 2:
    discard cast[proc(self: ID, op: SEL): ID {.cdecl, varargs.}](objc_msgSend)(
      target.value, action
    )
    true
  of 3:
    discard cast[proc(self: ID, op: SEL, value: ID): ID {.cdecl, varargs.}](objc_msgSend)(
      target.value, action, sender.value
    )
    true
  else:
    false
