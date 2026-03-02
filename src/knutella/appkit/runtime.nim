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

proc addUniqueDir(dirs: var seq[string], dir: string) =
  if dir.len == 0 or not dirExists(dir):
    return
  if dir notin dirs:
    dirs.add(dir)

proc addUniquePath(paths: var seq[string], path: string) =
  if path.len == 0:
    return
  if path notin paths:
    paths.add(path)

proc appkitFontSearchDirs(): seq[string] =
  result = @[]
  result.addUniqueDir(figDataDir())
  let exePath = getAppFilename()
  if exePath.len == 0:
    return
  var dir = parentDir(exePath)
  for _ in 0 .. 6:
    result.addUniqueDir(dir / "data")
    let nextDir = parentDir(dir)
    if nextDir.len == 0 or nextDir == dir:
      break
    dir = nextDir

proc appkitFontCandidates*(): seq[string] =
  const preferred = ["Ubuntu.ttf", "HackNerdFont-Regular.ttf"]
  result = @[]
  for dir in appkitFontSearchDirs():
    for fileName in preferred:
      let path = dir / fileName
      if fileExists(path):
        result.addUniquePath(path)

    for kind, path in walkDir(dir):
      if kind != pcFile:
        continue
      let lowerExt = splitFile(path).ext.toLowerAscii()
      if lowerExt notin [".ttf", ".otf"]:
        continue
      result.addUniquePath(path)

  # Keep file-name candidates for environments where figDataDir is already correct.
  for fileName in preferred:
    result.addUniquePath(fileName)

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

proc normalizeButtonState*(value: NSCellState, allowsMixedState: bool): NSCellState {.inline.} =
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

proc ownFromId*[T: NSObject](id: IDPtr): T =
  if id.isNil:
    return T(value: nil)
  var borrowed = asTypeRaw[T](id)
  result = retain(borrowed)
  borrowed.value = nil

proc ownFromId*[T: NSObject](id: ID): T =
  ownFromId[T](id.value)

proc retainId*(id: IDPtr): IDPtr =
  if id.isNil:
    return nil
  var borrowed = asTypeRaw[NSObject](id)
  var owned = retain(borrowed)
  borrowed.value = nil
  result = owned.value
  owned.value = nil

proc retainId*(id: ID): ID =
  ID(value: retainId(id.value))

proc releaseId*(id: IDPtr) =
  if id.isNil:
    return
  var owned = asTypeRaw[NSObject](id)
  discard owned

proc releaseId*(id: ID) =
  releaseId(id.value)

proc replacedOwnedId*(slot: IDPtr, next: IDPtr): IDPtr =
  if slot == next:
    return slot
  result = retainId(next)
  releaseId(slot)

proc replacedOwnedId*(slot: ID, next: ID): ID =
  ID(value: replacedOwnedId(slot.value, next.value))

proc clearOwnedIds*(ids: var seq[IDPtr]) =
  for id in ids:
    releaseId(id)
  ids.setLen(0)

proc removeOwnedIdAt*(ids: var seq[IDPtr], idx: int) =
  let old = ids[idx]
  ids.del(idx)
  releaseId(old)

template callSuperIdFrom*(currentType: typedesc, obj: NSObject, op: SEL): IDPtr =
  block:
    var superObj =
      ObjcSuper(receiver: obj.value, superClass: getClass(currentType).getSuperclass())
    cast[proc(superObj: var ObjcSuper, selParam: SEL): IDPtr {.cdecl, varargs.}](objc_msgSendSuper)(
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
    discard cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs.}](objc_msgSend)(
      target.value, action
    )
    true
  of 3:
    discard cast[proc(self: IDPtr, op: SEL, value: IDPtr): IDPtr {.cdecl, varargs.}](objc_msgSend)(
      target.value, action, sender.value
    )
    true
  else:
    false

type
  ## Pre-declare core types
  NSResponder* = object of NSObject

  NSApplication* = object of NSResponder
  NSWindow* = object of NSResponder
  NSCell* = object of NSObject
  NSImageCell* = object of NSCell
  NSEvent* = object of NSObject

  NSView* = object of NSResponder

  NSCollectionView* = object of NSView
  NSText* = object of NSView
  NSClipView* = object of NSView
  NSScrollView* = object of NSView
  NSTableHeaderView* = object of NSView
  NSRulerView* = object of NSView
  NSControl* = object of NSView
  NSTableView* = object of NSControl
  NSScroller* = object of NSControl
  NSImageView* = object of NSControl
  NSTextField* = object of NSControl

  NSFont* = object of NSObject
  NSFontDescriptor* = object of NSObject
  NSShadow* = object of NSObject
  NSImage* = object of NSObject
  NSBitmapImageRep* = object of NSObject
  NSGraphicsContext* = object of NSObject
  NSTableColumn* = object of NSObject
  NSTableHeaderCell* = object of NSCell
  NSCursor* = object of NSObject
  NSMenu* = object of NSObject
  NSFormatter* = object of NSObject
  NSAttributedString* = object of NSObject

  NSDefect* = ref object of Defect
  NSException* = ref object of CatchableError
