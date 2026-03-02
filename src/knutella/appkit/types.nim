type
  NSBorderType* {.size: sizeof(cint).} = enum
    NSNoBorder = 0
    NSLineBorder = 1
    NSBezelBorder = 2
    NSGrooveBorder = 3

  NSTextAlignment* {.size: sizeof(cint).} = enum
    NSLeftTextAlignment = 0
    NSRightTextAlignment = 1
    NSCenterTextAlignment = 2
    NSJustifiedTextAlignment = 3
    NSNaturalTextAlignment = 4

  NSWritingDirection* {.size: sizeof(cint).} = enum
    NSWritingDirectionNatural = -1
    NSWritingDirectionLeftToRight = 0
    NSWritingDirectionRightToLeft = 1

  NSLineBreakMode* {.size: sizeof(cint).} = enum
    NSLineBreakByWordWrapping = 0
    NSLineBreakByCharWrapping = 1
    NSLineBreakByClipping = 2
    NSLineBreakByTruncatingHead = 3
    NSLineBreakByTruncatingTail = 4
    NSLineBreakByTruncatingMiddle = 5

  NSCellType* {.size: sizeof(cint).} = enum
    NSNullCellType = 0
    NSTextCellType = 1
    NSImageCellType = 2

  NSControlSize* {.size: sizeof(cint).} = enum
    NSRegularControlSize = 0
    NSSmallControlSize = 1
    NSMiniControlSize = 2

  NSFocusRingType* {.size: sizeof(cint).} = enum
    NSFocusRingTypeDefault = 0
    NSFocusRingTypeNone = 1
    NSFocusRingTypeExterior = 2

  NSBackgroundStyle* {.size: sizeof(cint).} = enum
    NSBackgroundStyleLight = 0
    NSBackgroundStyleDark = 1
    NSBackgroundStyleRaised = 2
    NSBackgroundStyleLowered = 3

  NSCompositingOperation* {.size: sizeof(cint).} = enum
    NSCompositeClear = 0
    NSCompositeCopy = 1
    NSCompositeSourceOver = 2
    NSCompositeSourceIn = 3
    NSCompositeSourceOut = 4
    NSCompositeSourceAtop = 5
    NSCompositeDestinationOver = 6
    NSCompositeDestinationIn = 7
    NSCompositeDestinationOut = 8
    NSCompositeDestinationAtop = 9
    NSCompositeXOR = 10
    NSCompositePlusDarker = 11
    NSCompositeHighlight = 12
    NSCompositePlusLighter = 13

  NSWindowOrderingMode* {.size: sizeof(cint).} = enum
    NSWindowBelow = -1
    NSWindowOut = 0
    NSWindowAbove = 1

  NSFocusRingPlacement* {.size: sizeof(cint).} = enum
    NSFocusRingOnly = 0
    NSFocusRingBelow = 1
    NSFocusRingAbove = 2

  NSDisplayGamut* {.size: sizeof(cint).} = enum
    NSDisplayGamutSRGB = 1
    NSDisplayGamutP3 = 2

  NSWindowDepth* {.size: sizeof(int32).} = enum
    NSWindowDepthOnehundredtwentyeightBitRGB = 544
    NSWindowDepthSixtyfourBitRGB = 528
    NSWindowDepthTwentyfourBitRGB = 520

  NSImageInterpolation* {.size: sizeof(cint).} = enum
    NSImageInterpolationDefault = 0
    NSImageInterpolationNone = 1
    NSImageInterpolationLow = 2
    NSImageInterpolationHigh = 3

  NSColorRenderingIntent* {.size: sizeof(cint).} = enum
    NSColorRenderingIntentDefault = 0
    NSColorRenderingIntentAbsoluteColorimetric = 1
    NSColorRenderingIntentRelativeColorimetric = 2
    NSColorRenderingIntentPerceptual = 3
    NSColorRenderingIntentSaturation = 4

  NSControlTint* = int

  NSPoint* = object
    x*: float32
    y*: float32

  NSRectEdge* {.size: sizeof(cint).} = enum
    NSMinXEdge = 0
    NSMinYEdge = 1
    NSMaxXEdge = 2
    NSMaxYEdge = 3

  NSSize* = object
    width*: float32
    height*: float32

  NSRect* = object
    origin*: NSPoint
    size*: NSSize

  NSRange* = object
    location*: uint
    length*: uint

  NSColor* = object
    r*: float32
    g*: float32
    b*: float32
    a*: float32

  NSAlertStyle* {.size: sizeof(cint).} = enum
    NSWarningAlertStyle = 0
    NSInformationalAlertStyle = 1
    NSCriticalAlertStyle = 2

  NSAlertReturn* {.size: sizeof(cint).} = enum
    NSAlertFirstButtonReturn = 1000
    NSAlertSecondButtonReturn = 1001
    NSAlertThirdButtonReturn = 1002

  NSButtonType* {.size: sizeof(cint).} = enum
    NSMomentaryLightButton = 0
    NSPushOnPushOffButton = 1
    NSToggleButton = 2
    NSSwitchButton = 3
    NSRadioButton = 4
    NSMomentaryChangeButton = 5
    NSOnOffButton = 6
    NSMomentaryPushInButton = 7

  NSImageAlignment* {.size: sizeof(cint).} = enum
    NSImageAlignCenter = 0
    NSImageAlignTop = 1
    NSImageAlignTopLeft = 2
    NSImageAlignTopRight = 3
    NSImageAlignLeft = 4
    NSImageAlignBottom = 5
    NSImageAlignBottomLeft = 6
    NSImageAlignBottomRight = 7
    NSImageAlignRight = 8

  NSScrollerPart* {.size: sizeof(cint).} = enum
    NSScrollerNoPart = 0
    NSScrollerIncrementLine = 1
    NSScrollerDecrementLine = 2
    NSScrollerIncrementPage = 3
    NSScrollerDecrementPage = 4
    NSScrollerKnob = 5
    NSScrollerKnobSlot = 6

  NSScrollerArrow* {.size: sizeof(cint).} = enum
    NSScrollerIncrementArrow = 0
    NSScrollerDecrementArrow = 1

  NSScrollArrowPosition* {.size: sizeof(cint).} = enum
    NSScrollerArrowsMaxEnd = 0
    NSScrollerArrowsMinEnd = 1
    NSScrollerArrowsNone = 2

  NSRulerOrientation* {.size: sizeof(cint).} = enum
    NSHorizontalRuler = 0
    NSVerticalRuler = 1

type
  NSWindowDecorations* {.size: sizeof(cint).} = enum
    NSTitledWindow = 1
    NSClosableWindow = 2
    NSMiniaturizableWindow = 3
    NSResizableWindow = 4
    NSTexturedBackgroundWindow = 8
    NSAppKitPrivateWindow = 28

const
  NSBorderlessWindowMask*: set[NSWindowDecorations] = {}

type
  NSBackingStoreType* {.size: sizeof(cint).} = enum
    NSBackingStoreRetained = 0
    NSBackingStoreNonretained = 1
    NSBackingStoreBuffered = 2

  NSCellMask* {.size: sizeof(cint).} = enum
    NSContentsCell = 1
    NSPushInCell = 2
    NSChangeGrayCell = 3
    NSChangeBackgroundCell = 4

const
  NSNoCellMask*: set[NSCellMask] = {}

type
  NSAutoResizingMask* {.size: sizeof(cint).} = enum
    NSViewMinXMargin = 0
    NSViewWidthSizable = 1
    NSViewMaxXMargin = 2
    NSViewMinYMargin = 3
    NSViewHeightSizable = 4
    NSViewMaxYMargin = 5

const
  NSViewNotSizable*: set[NSAutoResizingMask] = {}

type
  NSBezelStyle* {.size: sizeof(cint).} = enum
    NSRoundedBezelStyle = 1
    NSRegularSquareBezelStyle = 2
    NSThickSquareBezelStyle = 3
    NSThickerSquareBezelStyle = 4
    NSDisclosureBezelStyle = 5
    NSShadowlessSquareBezelStyle = 6
    NSCircularBezelStyle = 7
    NSTexturedSquareBezelStyle = 8
    NSHelpButtonBezelStyle = 9
    NSSmallSquareBezelStyle = 10
    NSTexturedRoundedBezelStyle = 11
    NSRoundRectBezelStyle = 12
    NSRecessedBezelStyle = 13
    NSRoundedDisclosureBezelStyle = 14

  NSGradientType* {.size: sizeof(cint).} = enum
    NSGradientNone = 0
    NSGradientConcaveWeak = 1
    NSGradientConcaveStrong = 2
    NSGradientConvexWeak = 3
    NSGradientConvexStrong = 4

  NSCellImagePosition* {.size: sizeof(cint).} = enum
    NSNoImage = 0
    NSImageOnly = 1
    NSImageLeft = 2
    NSImageRight = 3
    NSImageBelow = 4
    NSImageAbove = 5
    NSImageOverlaps = 6

  NSImageScaling* {.size: sizeof(cint).} = enum
    NSImageScaleProportionallyDown = 0
    NSImageScaleAxesIndependently = 1
    NSImageScaleNone = 2
    NSImageScaleProportionallyUpOrDown = 3

const
  NSScaleProportionally* = NSImageScaleProportionallyDown
  NSScaleToFit* = NSImageScaleAxesIndependently
  NSScaleNone* = NSImageScaleNone

type
  NSImageFrameStyle* {.size: sizeof(cint).} = enum
    NSImageFrameNone = 0
    NSImageFramePhoto = 1
    NSImageFrameGrayBezel = 2
    NSImageFrameGroove = 3
    NSImageFrameButton = 4

  NSCellState* {.size: sizeof(cint).} = enum
    NSMixedState = -1
    NSOffState = 0
    NSOnState = 1

  NSAnimationEffect* {.size: sizeof(cint).} = enum
    NSAnimationEffectDisappearingItemDefault = 0
    NSAnimationEffectPoof = 10

const
  NSCompositingOperationClear* = NSCompositeClear
  NSCompositingOperationCopy* = NSCompositeCopy
  NSCompositingOperationSourceOver* = NSCompositeSourceOver
  NSCompositingOperationSourceIn* = NSCompositeSourceIn
  NSCompositingOperationSourceOut* = NSCompositeSourceOut
  NSCompositingOperationSourceAtop* = NSCompositeSourceAtop
  NSCompositingOperationDestinationOver* = NSCompositeDestinationOver
  NSCompositingOperationDestinationIn* = NSCompositeDestinationIn
  NSCompositingOperationDestinationOut* = NSCompositeDestinationOut
  NSCompositingOperationDestinationAtop* = NSCompositeDestinationAtop
  NSCompositingOperationXOR* = NSCompositeXOR
  NSCompositingOperationPlusDarker* = NSCompositePlusDarker
  NSCompositingOperationHighlight* = NSCompositeHighlight
  NSCompositingOperationPlusLighter* = NSCompositePlusLighter

type
  NSValueType* {.size: sizeof(cint).} = enum
    NSAnyType = 0
    NSIntType = 1
    NSPositiveIntType = 2
    NSFloatType = 3
    NSPositiveFloatType = 4
    NSDoubleType = 6
    NSPositiveDoubleType = 7

  NSCellHit* {.size: sizeof(cint).} = enum
    NSCellHitContentArea = 0
    NSCellHitEditableTextArea = 1
    NSCellHitTrackableArea = 2

const
  NSCellHitNone*: set[NSCellHit] = {}
  NSNotFound* = high(uint)

type
  NSUsableScrollerParts* {.size: sizeof(cint).} = enum
    NSNoScrollerParts = 0
    NSOnlyScrollerArrows = 1
    NSAllScrollerParts = 2

const
  NSScrollerArrowsDefaultSetting* = NSScrollerArrowsMaxEnd


proc nsPoint*(x, y: float32): NSPoint =
  NSPoint(x: x, y: y)

proc nsSize*(width, height: float32): NSSize =
  NSSize(width: width, height: height)

proc nsRect*(x, y, width, height: float32): NSRect =
  NSRect(origin: nsPoint(x, y), size: nsSize(width, height))

proc nsColor*(r, g, b: float32, a: float32 = 1.0'f32): NSColor =
  NSColor(r: r, g: g, b: b, a: a)

converter alertStyleToInt*(value: NSAlertStyle): int {.inline.} =
  value.int

converter alertReturnToInt*(value: NSAlertReturn): int {.inline.} =
  value.int

converter buttonTypeToInt*(value: NSButtonType): int {.inline.} =
  value.int

converter imageAlignmentToInt*(value: NSImageAlignment): int {.inline.} =
  value.int

proc NSMakeRange*(location, length: uint): NSRange {.inline.} =
  NSRange(location: location, length: length)

proc NSMaxRange*(r: NSRange): uint {.inline.} =
  r.location + r.length

proc NSLocationInRange*(location: uint, r: NSRange): bool {.inline.} =
  location >= r.location and location < NSMaxRange(r)

proc contains*(r: NSRect, x, y: float32): bool =
  x >= r.origin.x and y >= r.origin.y and x < (r.origin.x + r.size.width) and
    y < (r.origin.y + r.size.height)

proc NSEqualSizes*(size0, size1: NSSize): bool =
   return (size0.width==size1.width) and (size0.height==size1.height)

proc maxX*(rect: NSRect): float32 {.inline.} =
  rect.origin.x + rect.size.width

proc maxY*(rect: NSRect): float32 {.inline.} =
  rect.origin.y + rect.size.height

proc isEmpty*(rect: NSRect): bool {.inline.} =
  rect.size.width <= 0.0 or rect.size.height <= 0.0

proc nsIntersectionRect*(a: NSRect, b: NSRect): NSRect =
  let x0 = max(a.origin.x, b.origin.x)
  let y0 = max(a.origin.y, b.origin.y)
  let x1 = min(maxX(a), maxX(b))
  let y1 = min(maxY(a), maxY(b))
  if x1 <= x0 or y1 <= y0:
    return nsRect(0.0, 0.0, 0.0, 0.0)
  nsRect(x0, y0, x1 - x0, y1 - y0)

proc nsUnionRect*(a: NSRect, b: NSRect): NSRect =
  if isEmpty(a):
    return b
  if isEmpty(b):
    return a
  let x0 = min(a.origin.x, b.origin.x)
  let y0 = min(a.origin.y, b.origin.y)
  let x1 = max(maxX(a), maxX(b))
  let y1 = max(maxY(a), maxY(b))
  nsRect(x0, y0, x1 - x0, y1 - y0)

proc nsContainsRect*(outer: NSRect, inner: NSRect): bool {.inline.} =
  not isEmpty(inner) and inner.origin.x >= outer.origin.x and
    inner.origin.y >= outer.origin.y and maxX(inner) <= maxX(outer) and
    maxY(inner) <= maxY(outer)

proc nsIntersectsRect*(a: NSRect, b: NSRect): bool {.inline.} =
  not isEmpty(nsIntersectionRect(a, b))

