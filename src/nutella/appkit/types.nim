type
  NSTextAlignment* {.size: sizeof(cint).} = enum
    NSLeftTextAlignment = 0
    NSRightTextAlignment = 1
    NSCenterTextAlignment = 2
    NSJustifiedTextAlignment = 3
    NSNaturalTextAlignment = 4

  NSPoint* = object
    x*: float32
    y*: float32

  NSSize* = object
    width*: float32
    height*: float32

  NSRect* = object
    origin*: NSPoint
    size*: NSSize

  NSColor* = object
    r*: float32
    g*: float32
    b*: float32
    a*: float32

const
  NSWarningAlertStyle* = 0
  NSInformationalAlertStyle* = 1
  NSCriticalAlertStyle* = 2
  NSAlertFirstButtonReturn* = 1000
  NSAlertSecondButtonReturn* = 1001
  NSAlertThirdButtonReturn* = 1002

  NSMomentaryLightButton* = 0
  NSPushOnPushOffButton* = 1
  NSToggleButton* = 2
  NSSwitchButton* = 3
  NSRadioButton* = 4
  NSMomentaryChangeButton* = 5
  NSOnOffButton* = 6
  NSMomentaryPushInButton* = 7

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

  NSMixedState* = -1
  NSOffState* = 0
  NSOnState* = 1

proc nsPoint*(x, y: float32): NSPoint =
  NSPoint(x: x, y: y)

proc nsSize*(width, height: float32): NSSize =
  NSSize(width: width, height: height)

proc nsRect*(x, y, width, height: float32): NSRect =
  NSRect(origin: nsPoint(x, y), size: nsSize(width, height))

proc nsColor*(r, g, b: float32, a: float32 = 1.0'f32): NSColor =
  NSColor(r: r, g: g, b: b, a: a)

proc contains*(r: NSRect, x, y: float32): bool =
  x >= r.origin.x and y >= r.origin.y and x < (r.origin.x + r.size.width) and
    y < (r.origin.y + r.size.height)
