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

  NSControlTint* = int

  NSPoint* = object
    x*: float32
    y*: float32

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

  NSUsableScrollerParts* = int

const
  NSBorderlessWindowMask* = 0x00
  NSTitledWindowMask* = 0x01
  NSClosableWindowMask* = 0x02
  NSMiniaturizableWindowMask* = 0x04
  NSResizableWindowMask* = 0x08
  NSTexturedBackgroundWindowMask* = 0x100

  NSBackingStoreRetained* = 0
  NSBackingStoreNonretained* = 1
  NSBackingStoreBuffered* = 2

  NSNoCellMask* = 0x00
  NSContentsCellMask* = 0x01
  NSPushInCellMask* = 0x02
  NSChangeGrayCellMask* = 0x04
  NSChangeBackgroundCellMask* = 0x08

  NSViewNotSizable* = 0
  NSViewMinXMargin* = 1
  NSViewWidthSizable* = 2
  NSViewMaxXMargin* = 4
  NSViewMinYMargin* = 8
  NSViewHeightSizable* = 16
  NSViewMaxYMargin* = 32

  NSRoundedBezelStyle* = 1
  NSRegularSquareBezelStyle* = 2
  NSThickSquareBezelStyle* = 3
  NSThickerSquareBezelStyle* = 4
  NSDisclosureBezelStyle* = 5
  NSShadowlessSquareBezelStyle* = 6
  NSCircularBezelStyle* = 7
  NSTexturedSquareBezelStyle* = 8
  NSHelpButtonBezelStyle* = 9
  NSSmallSquareBezelStyle* = 10
  NSTexturedRoundedBezelStyle* = 11
  NSRoundRectBezelStyle* = 12
  NSRecessedBezelStyle* = 13
  NSRoundedDisclosureBezelStyle* = 14

  NSGradientNone* = 0
  NSGradientConcaveWeak* = 1
  NSGradientConcaveStrong* = 2
  NSGradientConvexWeak* = 3
  NSGradientConvexStrong* = 4

  NSNoImage* = 0
  NSImageOnly* = 1
  NSImageLeft* = 2
  NSImageRight* = 3
  NSImageBelow* = 4
  NSImageAbove* = 5
  NSImageOverlaps* = 6

  NSImageScaleProportionallyDown* = 0
  NSImageScaleAxesIndependently* = 1
  NSImageScaleNone* = 2
  NSImageScaleProportionallyUpOrDown* = 3
  NSScaleProportionally* = NSImageScaleProportionallyDown
  NSScaleToFit* = NSImageScaleAxesIndependently
  NSScaleNone* = NSImageScaleNone

  NSImageFrameNone* = 0
  NSImageFramePhoto* = 1
  NSImageFrameGrayBezel* = 2
  NSImageFrameGroove* = 3
  NSImageFrameButton* = 4

  NSMixedState* = -1
  NSOffState* = 0
  NSOnState* = 1

  NSAnyType* = 0
  NSIntType* = 1
  NSPositiveIntType* = 2
  NSFloatType* = 3
  NSPositiveFloatType* = 4
  NSDoubleType* = 6
  NSPositiveDoubleType* = 7

  NSCellHitNone* = 0x00
  NSCellHitContentArea* = 0x01
  NSCellHitEditableTextArea* = 0x02
  NSCellHitTrackableArea* = 0x04
  NSNoScrollerParts* = 0
  NSOnlyScrollerArrows* = 1
  NSAllScrollerParts* = 2
  NSScrollerArrowsDefaultSetting* = NSScrollerArrowsMaxEnd
  NSNotFound* = high(uint)

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
