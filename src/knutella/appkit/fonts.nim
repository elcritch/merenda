import std/[os, strutils, tables]

import figdraw/common/fonttypes
import figdraw/common/typefaces

import ./runtime
import ./fontdescriptors

const
  DefaultSystemFontSize = 12.0'f32
  DefaultSmallSystemFontSize = 10.0'f32
  DefaultLabelFontSize = 12.0'f32

type FontState = ref object
  fontName: NSString
  familyName: NSString
  displayName: NSString
  pointSize: float32
  fixedPitch: bool
  italicAngle: float32
  ascender: float32
  descender: float32
  leading: float32
  defaultLineHeight: float32
  xHeight: float32
  capHeight: float32

var typefaceCache {.threadvar.}: Table[string, TypefaceId]

proc inferFamilyName(name: string): string =
  var stem = splitFile(name).name
  if stem.len == 0:
    stem = name
  let dashIndex = stem.find('-')
  if dashIndex > 0:
    stem = stem[0 ..< dashIndex]
  if stem.len == 0:
    return "System"
  result = stem.replace('_', ' ')

proc cachedTypefaceId(candidate: string): TypefaceId =
  if typefaceCache.hasKey(candidate):
    return typefaceCache[candidate]
  let typefaceId = loadTypeface(candidate)
  typefaceCache[candidate] = typefaceId
  typefaceId

proc inferItalicAngle(name: string): float32 =
  let lowered = name.toLowerAscii()
  if lowered.contains("italic") or lowered.contains("oblique"):
    return -12.0
  0.0

proc inferFixedPitch(name: string): bool =
  let lowered = name.toLowerAscii()
  lowered.contains("mono") or lowered.contains("code") or lowered.contains("courier") or
    lowered.contains("hack")

proc makeFontCandidates(name: string): seq[string] =
  result = @[]
  if name.len > 0:
    result.add(name)
    let file = splitFile(name)
    if file.ext.len == 0:
      result.add(name & ".ttf")
      result.add(name & ".otf")
  for candidate in appkitFontCandidates():
    if candidate notin result:
      result.add(candidate)
  if result.len == 0:
    result = @["Ubuntu.ttf", "HackNerdFont-Regular.ttf"]

proc loadFigFont(
    name: string, pointSize: float32
): tuple[resolvedName: string, font: FigFont] =
  let candidates = makeFontCandidates(name)
  for candidate in candidates:
    try:
      let typefaceId = cachedTypefaceId(candidate)
      let figFont = typefaceId.fontWithSize(max(pointSize, 1.0))
      return (candidate, figFont)
    except CatchableError:
      discard
  if ensureAppKitFont():
    let figFont = appkitTypefaceId.fontWithSize(max(pointSize, 1.0))
    return ("System", figFont)
  let fallback = FigFont(typefaceId: 0, size: max(pointSize, 1.0))
  ("System", fallback)

proc defaultPointSize(size: float32): float32 =
  if size <= 0.0:
    return DefaultSystemFontSize
  size

proc buildFontDescriptor(font: NSFont): NSFontDescriptor

proc makeMetrics(state: FontState, figFont: FigFont) =
  let size =
    if figFont.size > 0:
      figFont.size
    else:
      max(state.pointSize, 1.0)
  state.ascender = size * 0.8
  state.descender = -size * 0.2
  state.leading = size * 0.15
  state.defaultLineHeight = size
  state.capHeight = size * 0.7
  state.xHeight = size * 0.5

objcImpl:
  type NSFont* {.impl: NSCopying.} = object of NSObject
    xState: FontState

  method initWithName*(
      self: var NSFont, name: NSString, size {.kw("size").}: float32
  ): NSFont =
    result = asTypeRaw[NSFont](callSuperIdFrom(NSFont, self, getSelector("init")))
    if result.isNil:
      return
    initIvarFields(result)

    let pointSize = defaultPointSize(size)
    let requestedName =
      if name.isNil:
        ""
      else:
        $name
    let loaded = loadFigFont(requestedName, pointSize)
    let resolvedName =
      if loaded.resolvedName.len == 0: "System" else: loaded.resolvedName

    var state = FontState()
    state.fontName = ns(resolvedName)
    state.displayName = ns(resolvedName)
    state.familyName = ns(inferFamilyName(resolvedName))
    state.pointSize = pointSize
    state.fixedPitch = inferFixedPitch(resolvedName)
    state.italicAngle = inferItalicAngle(resolvedName)
    makeMetrics(state, loaded.font)
    result.xState = state

  method init*(self: var NSFont): NSFont =
    result = self.initWithName(ns("System"), DefaultSystemFontSize)

  method fontName*(self: NSFont): NSString =
    let state = self.xState
    if state.isNil or state.fontName.isNil:
      return @ns""
    state.fontName

  method familyName*(self: NSFont): NSString =
    let state = self.xState
    if state.isNil or state.familyName.isNil:
      return @ns""
    state.familyName

  method displayName*(self: NSFont): NSString =
    let state = self.xState
    if state.isNil or state.displayName.isNil:
      return @ns""
    state.displayName

  method pointSize*(self: NSFont): float32 =
    let state = self.xState
    if state.isNil:
      return DefaultSystemFontSize
    state.pointSize

  method isFixedPitch*(self: NSFont): bool =
    let state = self.xState
    if state.isNil:
      return false
    state.fixedPitch

  method italicAngle*(self: NSFont): float32 =
    let state = self.xState
    if state.isNil:
      return 0.0
    state.italicAngle

  method ascender*(self: NSFont): float32 =
    let state = self.xState
    if state.isNil:
      return DefaultSystemFontSize * 0.8
    state.ascender

  method descender*(self: NSFont): float32 =
    let state = self.xState
    if state.isNil:
      return -DefaultSystemFontSize * 0.2
    state.descender

  method leading*(self: NSFont): float32 =
    let state = self.xState
    if state.isNil:
      return DefaultSystemFontSize * 0.15
    state.leading

  method defaultLineHeightForFont*(self: NSFont): float32 =
    let state = self.xState
    if state.isNil:
      return DefaultSystemFontSize
    state.defaultLineHeight

  method xHeight*(self: NSFont): float32 =
    let state = self.xState
    if state.isNil:
      return DefaultSystemFontSize * 0.5
    state.xHeight

  method capHeight*(self: NSFont): float32 =
    let state = self.xState
    if state.isNil:
      return DefaultSystemFontSize * 0.7
    state.capHeight

  method fontDescriptor*(self: NSFont): NSFontDescriptor =
    if self.isNil:
      return NSFontDescriptor(value: nil)
    buildFontDescriptor(self)

  method description*(self: NSFont): NSString =
    ns("<NSFont " & $self.fontName() & " " & $self.pointSize() & ">")

  method copyWithZone*(self: NSFont, zone: pointer): NSFont =
    retain(self)

  method dealloc(self: NSFont) {.used.} =
    self.xState = nil
    destroyIvarFields(self)
    discard callSuperIdFrom(NSFont, self, getSelector("dealloc"))

proc fontWithName*(
    t: typedesc[NSFont], name: NSString, size {.kw("size").}: float32
): NSFont =
  let pointSize = defaultPointSize(size)

  var allocated = NSFont.alloc()
  result = allocated.initWithName(name, pointSize)
  allocated.value = nil

proc fontWithDescriptor*(
    t: typedesc[NSFont], descriptor: NSFontDescriptor, size {.kw("size").}: float32
): NSFont =
  var pointSize = size
  if not descriptor.isNil:
    if pointSize <= 0.0:
      pointSize = descriptor.pointSize()
  if pointSize <= 0.0:
    pointSize = DefaultSystemFontSize

  var allocated = NSFont.alloc()
  # Keep descriptor-backed size semantics without relying on descriptor key object lifetime.
  result = allocated.initWithName(ns("System"), pointSize)
  allocated.value = nil

proc buildFontDescriptor(font: NSFont): NSFontDescriptor =
  ensureFontDescriptorConstants()
  var attributes = nsDictionary[NSObject, NSObject]()
  attributes[NSObject(NSFontNameAttribute)] = NSObject(font.fontName())
  attributes[NSObject(NSFontFamilyAttribute)] = NSObject(font.familyName())
  attributes[NSObject(NSFontVisibleNameAttribute)] = NSObject(font.displayName())
  attributes[NSObject(NSFontSizeAttribute)] = boxNSObject(font.pointSize())

  var traits = nsDictionary[NSObject, NSObject]()
  traits[NSObject(NSFontSymbolicTrait)] = boxNSObject(0.NSUInteger)
  traits[NSObject(NSFontWeightTrait)] = boxNSObject(0)
  traits[NSObject(NSFontSlantTrait)] = boxNSObject(font.italicAngle())
  attributes[NSObject(NSFontTraitsAttribute)] = NSObject(traits)

  NSFontDescriptor.fontDescriptorWithFontAttributes(attributes)

proc systemFontSize*(t: typedesc[NSFont]): float32 =
  DefaultSystemFontSize

proc smallSystemFontSize*(t: typedesc[NSFont]): float32 =
  DefaultSmallSystemFontSize

proc labelFontSize*(t: typedesc[NSFont]): float32 =
  DefaultLabelFontSize

proc systemFontSizeForControlSize*(t: typedesc[NSFont], size: NSControlSize): float32 =
  case size
  of NSMiniControlSize: 9.0
  of NSSmallControlSize: 11.0
  else: 13.0

proc systemFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.fontWithName(ns("System"), if size <= 0.0: DefaultSystemFontSize else: size)

proc boldSystemFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.fontWithName(
    ns("System-Bold"), if size <= 0.0: DefaultSystemFontSize else: size
  )

proc controlContentFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.systemFontOfSize(if size <= 0.0: 10.0 else: size)

proc labelFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.systemFontOfSize(if size <= 0.0: 10.0 else: size)

proc menuFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.systemFontOfSize(if size <= 0.0: 12.0 else: size)

proc menuBarFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.systemFontOfSize(if size <= 0.0: 12.0 else: size)

proc messageFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.systemFontOfSize(if size <= 0.0: 10.0 else: size)

proc paletteFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.systemFontOfSize(if size <= 0.0: 10.0 else: size)

proc titleBarFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.boldSystemFontOfSize(if size <= 0.0: DefaultSystemFontSize else: size)

proc toolTipsFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.systemFontOfSize(if size <= 0.0: 9.0 else: size)

proc userFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.fontWithName(@ns"Inter-Regular", if size <= 0.0: 10.0 else: size)

proc userFixedPitchFontOfSize*(t: typedesc[NSFont], size: float32): NSFont =
  NSFont.fontWithName(@ns"HackNerdFont-Regular", if size <= 0.0: 12.0 else: size)

proc preferredFontNames*(t: typedesc[NSFont]): NSArray[NSString] =
  var names = nsArray[NSString]()
  for candidate in appkitFontCandidates():
    names.add(ns(candidate))
  names

proc new*(t: typedesc[NSFont]): NSFont =
  var allocated = NSFont.alloc()
  result = initOwned(move(allocated))
