import std/strutils

import pkg/chroma

import ./runtime

const
  NSCalibratedRGBColorSpaceName = "NSCalibratedRGBColorSpace"
  NSDeviceRGBColorSpaceName = "NSDeviceRGBColorSpace"
  NSCalibratedWhiteColorSpaceName = "NSCalibratedWhiteColorSpace"
  NSDeviceWhiteColorSpaceName = "NSDeviceWhiteColorSpace"
  NSDeviceCMYKColorSpaceName = "NSDeviceCMYKColorSpace"
  NSNamedColorSpaceName = "NSNamedColorSpace"
  NSPatternColorSpaceName = "NSPatternColorSpace"

var
  NSCalibratedRGBColorSpace* {.threadvar.}: NSString
  NSDeviceRGBColorSpace* {.threadvar.}: NSString
  NSCalibratedWhiteColorSpace* {.threadvar.}: NSString
  NSDeviceWhiteColorSpace* {.threadvar.}: NSString
  NSDeviceCMYKColorSpace* {.threadvar.}: NSString
  NSNamedColorSpace* {.threadvar.}: NSString
  NSPatternColorSpace* {.threadvar.}: NSString

proc clamp01(value: float32): float32 {.inline.} =
  if value < 0.0:
    return 0.0
  if value > 1.0:
    return 1.0
  value

proc ensureColorSpaceNames*() =
  if NSCalibratedRGBColorSpace.isNil:
    NSCalibratedRGBColorSpace = ns(NSCalibratedRGBColorSpaceName)
    NSDeviceRGBColorSpace = ns(NSDeviceRGBColorSpaceName)
    NSCalibratedWhiteColorSpace = ns(NSCalibratedWhiteColorSpaceName)
    NSDeviceWhiteColorSpace = ns(NSDeviceWhiteColorSpaceName)
    NSDeviceCMYKColorSpace = ns(NSDeviceCMYKColorSpaceName)
    NSNamedColorSpace = ns(NSNamedColorSpaceName)
    NSPatternColorSpace = ns(NSPatternColorSpaceName)

proc toChromaColor(c: NSColor): Color {.inline.} =
  color(clamp01(c.r), clamp01(c.g), clamp01(c.b), clamp01(c.a))

proc fromChromaColor(c: Color, alpha: float32): NSColor {.inline.} =
  nsColor(clamp01(c.r), clamp01(c.g), clamp01(c.b), clamp01(alpha))

proc colorWithDeviceWhite*(
    t: typedesc[NSColor], white: float32, alpha {.kw("alpha").}: float32
): NSColor =
  let w = clamp01(white)
  nsColor(w, w, w, clamp01(alpha))

proc colorWithCalibratedWhite*(
    t: typedesc[NSColor], white: float32, alpha {.kw("alpha").}: float32
): NSColor =
  NSColor.colorWithDeviceWhite(white, alpha)

proc colorWithDeviceRed*(
    t: typedesc[NSColor],
    red: float32,
    green {.kw("green").}: float32,
    blue {.kw("blue").}: float32,
    alpha {.kw("alpha").}: float32,
): NSColor =
  nsColor(clamp01(red), clamp01(green), clamp01(blue), clamp01(alpha))

proc colorWithCalibratedRed*(
    t: typedesc[NSColor],
    red: float32,
    green {.kw("green").}: float32,
    blue {.kw("blue").}: float32,
    alpha {.kw("alpha").}: float32,
): NSColor =
  NSColor.colorWithDeviceRed(red, green, blue, alpha)

proc colorWithDeviceHue*(
    t: typedesc[NSColor],
    hue: float32,
    saturation {.kw("saturation").}: float32,
    brightness {.kw("brightness").}: float32,
    alpha {.kw("alpha").}: float32,
): NSColor =
  let rgb = color(
    hsv(clamp01(hue) * 360.0, clamp01(saturation) * 100.0, clamp01(brightness) * 100.0)
  )
  fromChromaColor(rgb, alpha)

proc colorWithCalibratedHue*(
    t: typedesc[NSColor],
    hue: float32,
    saturation {.kw("saturation").}: float32,
    brightness {.kw("brightness").}: float32,
    alpha {.kw("alpha").}: float32,
): NSColor =
  NSColor.colorWithDeviceHue(hue, saturation, brightness, alpha)

proc colorWithDeviceCyan*(
    t: typedesc[NSColor],
    cyan: float32,
    magenta {.kw("magenta").}: float32,
    yellow {.kw("yellow").}: float32,
    black {.kw("black").}: float32,
    alpha {.kw("alpha").}: float32,
): NSColor =
  let c = clamp01(cyan)
  let m = clamp01(magenta)
  let y = clamp01(yellow)
  let k = clamp01(black)
  nsColor(
    (1.0 - c) * (1.0 - k), (1.0 - m) * (1.0 - k), (1.0 - y) * (1.0 - k), clamp01(alpha)
  )

proc darkGrayColor*(t: typedesc[NSColor]): NSColor =
  nsColor(0.333, 0.333, 0.333, 1.0)

proc grayColor*(t: typedesc[NSColor]): NSColor =
  nsColor(0.5, 0.5, 0.5, 1.0)

proc lightGrayColor*(t: typedesc[NSColor]): NSColor =
  nsColor(0.667, 0.667, 0.667, 1.0)

proc blackColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCalibratedWhite(0.0, 1.0)

proc whiteColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCalibratedWhite(1.0, 1.0)

proc clearColor*(t: typedesc[NSColor]): NSColor =
  nsColor(0.0, 0.0, 0.0, 0.0)

proc blueColor*(t: typedesc[NSColor]): NSColor =
  nsColor(0.0, 0.478, 1.0, 1.0)

proc brownColor*(t: typedesc[NSColor]): NSColor =
  nsColor(0.612, 0.396, 0.122, 1.0)

proc cyanColor*(t: typedesc[NSColor]): NSColor =
  nsColor(0.0, 1.0, 1.0, 1.0)

proc greenColor*(t: typedesc[NSColor]): NSColor =
  nsColor(0.204, 0.780, 0.349, 1.0)

proc magentaColor*(t: typedesc[NSColor]): NSColor =
  nsColor(1.0, 0.0, 1.0, 1.0)

proc orangeColor*(t: typedesc[NSColor]): NSColor =
  nsColor(1.0, 0.584, 0.0, 1.0)

proc purpleColor*(t: typedesc[NSColor]): NSColor =
  nsColor(0.686, 0.322, 0.871, 1.0)

proc redColor*(t: typedesc[NSColor]): NSColor =
  nsColor(1.0, 0.231, 0.188, 1.0)

proc yellowColor*(t: typedesc[NSColor]): NSColor =
  nsColor(1.0, 0.8, 0.0, 1.0)

proc catalogColor(catalogName, colorName: string): NSColor =
  let catalog = catalogName.toLowerAscii()
  let name = colorName.toLowerAscii()
  if catalog == "basic":
    case name
    of "cyan":
      return NSColor.cyanColor()
    of "magenta":
      return NSColor.magentaColor()
    else:
      return NSColor.blackColor()

  case name
  of "alternateselectedcontrolcolor":
    nsColor(0.227, 0.529, 0.996, 1.0)
  of "alternateselectedcontroltextcolor", "selectedcontroltextcolor",
      "selectedmenuitemtextcolor":
    NSColor.whiteColor()
  of "keyboardfocusindicatorcolor":
    nsColor(0.172, 0.45, 0.984, 1.0)
  of "highlightcolor":
    nsColor(0.95, 0.95, 0.95, 1.0)
  of "shadowcolor":
    nsColor(0.0, 0.0, 0.0, 0.35)
  of "gridcolor":
    nsColor(0.81, 0.81, 0.81, 1.0)
  of "controlcolor", "controlbackgroundcolor", "windowbackgroundcolor", "headercolor",
      "menubackgroundcolor":
    nsColor(0.93, 0.93, 0.93, 1.0)
  of "selectedcontrolcolor", "secondaryselectedcontrolcolor":
    nsColor(0.75, 0.83, 0.96, 1.0)
  of "controltextcolor", "textcolor", "headertextcolor", "menuitemtextcolor":
    NSColor.blackColor()
  of "disabledcontroltextcolor":
    nsColor(0.58, 0.58, 0.58, 1.0)
  of "controldarkshadowcolor":
    nsColor(0.35, 0.35, 0.35, 1.0)
  of "controlhighlightcolor":
    NSColor.whiteColor()
  of "controllighthighlightcolor":
    nsColor(0.97, 0.97, 0.97, 1.0)
  of "controlshadowcolor":
    nsColor(0.58, 0.58, 0.58, 1.0)
  of "controlalternatingrowcolor":
    nsColor(0.96, 0.96, 0.96, 1.0)
  of "textbackgroundcolor":
    NSColor.whiteColor()
  of "selectedtextcolor":
    NSColor.whiteColor()
  of "selectedtextbackgroundcolor", "selectedmenuitemcolor":
    nsColor(0.227, 0.529, 0.996, 1.0)
  of "scrollbarcolor":
    nsColor(0.82, 0.82, 0.82, 1.0)
  of "knobcolor":
    nsColor(0.70, 0.70, 0.70, 1.0)
  of "selectedknobcolor":
    nsColor(0.42, 0.42, 0.42, 1.0)
  of "windowframecolor":
    nsColor(0.43, 0.43, 0.43, 1.0)
  of "systemdarkgraycolor":
    NSColor.darkGrayColor()
  of "systemgraycolor":
    NSColor.grayColor()
  of "systemlightgraycolor":
    NSColor.lightGrayColor()
  of "systembluecolor":
    NSColor.blueColor()
  of "systembrowncolor":
    NSColor.brownColor()
  of "systemtealcolor":
    nsColor(0.353, 0.784, 0.980, 1.0)
  of "systemindigocolor":
    nsColor(0.345, 0.337, 0.839, 1.0)
  of "systemgreencolor":
    NSColor.greenColor()
  of "systemorangecolor":
    NSColor.orangeColor()
  of "systempinkcolor":
    nsColor(1.0, 0.176, 0.333, 1.0)
  of "systempurplecolor":
    NSColor.purpleColor()
  of "systemredcolor":
    NSColor.redColor()
  of "systemyellowcolor":
    NSColor.yellowColor()
  else:
    NSColor.blackColor()

proc colorWithCatalogName*(
    t: typedesc[NSColor], catalogName: NSString, colorName {.kw("colorName").}: NSString
): NSColor =
  catalogColor($catalogName, $colorName)

proc alternateSelectedControlColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"alternateSelectedControlColor")

proc alternateSelectedControlTextColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"alternateSelectedControlTextColor")

proc keyboardFocusIndicatorColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"keyboardFocusIndicatorColor")

proc highlightColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"highlightColor")

proc shadowColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"shadowColor")

proc gridColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"gridColor")

proc controlColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"controlColor")

proc selectedControlColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"selectedControlColor")

proc secondarySelectedControlColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"secondarySelectedControlColor")

proc controlTextColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"controlTextColor")

proc selectedControlTextColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"selectedControlTextColor")

proc disabledControlTextColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"disabledControlTextColor")

proc controlBackgroundColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"controlBackgroundColor")

proc controlDarkShadowColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"controlDarkShadowColor")

proc controlHighlightColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"controlHighlightColor")

proc controlLightHighlightColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"controlLightHighlightColor")

proc controlShadowColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"controlShadowColor")

proc textColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"textColor")

proc textBackgroundColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"textBackgroundColor")

proc selectedTextColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"selectedTextColor")

proc selectedTextBackgroundColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"selectedTextBackgroundColor")

proc headerColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"headerColor")

proc headerTextColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"headerTextColor")

proc scrollBarColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"scrollBarColor")

proc knobColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"knobColor")

proc selectedKnobColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"selectedKnobColor")

proc windowBackgroundColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"windowBackgroundColor")

proc windowFrameColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"windowFrameColor")

proc selectedMenuItemColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"selectedMenuItemColor")

proc selectedMenuItemTextColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"selectedMenuItemTextColor")

proc menuBackgroundColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"menuBackgroundColor")

proc mainMenuBarColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"windowBackgroundColor")

proc menuItemTextColor*(t: typedesc[NSColor]): NSColor =
  NSColor.colorWithCatalogName(@ns"System", @ns"menuItemTextColor")

proc colorFromPasteboard*(t: typedesc[NSColor], pasteboard: NSObject): NSColor =
  NSColor.clearColor()

proc colorWithPatternImage*(t: typedesc[NSColor], image: NSImage): NSColor =
  if image.isNil:
    return NSColor.clearColor()
  NSColor.whiteColor()

proc colorSpaceName*(self: NSColor): NSString =
  ensureColorSpaceNames()
  NSCalibratedRGBColorSpace

proc numberOfComponents*(self: NSColor): int =
  4

proc getComponents*(self: NSColor, components: ptr float32) =
  if components.isNil:
    return
  components[0] = self.r
  components[1] = self.g
  components[2] = self.b
  components[3] = self.a

proc getWhite*(self: NSColor, white: ptr float32, alpha {.kw("alpha").}: ptr float32) =
  let value = clamp01(0.299 * self.r + 0.587 * self.g + 0.114 * self.b)
  if not white.isNil:
    white[] = value
  if not alpha.isNil:
    alpha[] = clamp01(self.a)

proc getRed*(
    self: NSColor,
    red: ptr float32,
    green {.kw("green").}: ptr float32,
    blue {.kw("blue").}: ptr float32,
    alpha {.kw("alpha").}: ptr float32,
) =
  if not red.isNil:
    red[] = clamp01(self.r)
  if not green.isNil:
    green[] = clamp01(self.g)
  if not blue.isNil:
    blue[] = clamp01(self.b)
  if not alpha.isNil:
    alpha[] = clamp01(self.a)

proc getHue*(
    self: NSColor,
    hue: ptr float32,
    saturation {.kw("saturation").}: ptr float32,
    brightness {.kw("brightness").}: ptr float32,
    alpha {.kw("alpha").}: ptr float32,
) =
  let hsvColor = hsv(self.toChromaColor())
  if not hue.isNil:
    hue[] = clamp01(hsvColor.h / 360.0)
  if not saturation.isNil:
    saturation[] = clamp01(hsvColor.s / 100.0)
  if not brightness.isNil:
    brightness[] = clamp01(hsvColor.v / 100.0)
  if not alpha.isNil:
    alpha[] = clamp01(self.a)

proc getCyan*(
    self: NSColor,
    cyan: ptr float32,
    magenta {.kw("magenta").}: ptr float32,
    yellow {.kw("yellow").}: ptr float32,
    black {.kw("black").}: ptr float32,
    alpha {.kw("alpha").}: ptr float32,
) =
  let maxRgb = max(self.r, max(self.g, self.b))
  let k = 1.0 - maxRgb
  var c = 0.0
  var m = 0.0
  var y = 0.0
  if k < 0.9999:
    c = (1.0 - self.r - k) / (1.0 - k)
    m = (1.0 - self.g - k) / (1.0 - k)
    y = (1.0 - self.b - k) / (1.0 - k)
  if not cyan.isNil:
    cyan[] = clamp01(c)
  if not magenta.isNil:
    magenta[] = clamp01(m)
  if not yellow.isNil:
    yellow[] = clamp01(y)
  if not black.isNil:
    black[] = clamp01(k)
  if not alpha.isNil:
    alpha[] = clamp01(self.a)

proc whiteComponent*(self: NSColor): float32 =
  var value = 0.0'f32
  self.getWhite(addr value, nil)
  value

proc redComponent*(self: NSColor): float32 =
  clamp01(self.r)

proc greenComponent*(self: NSColor): float32 =
  clamp01(self.g)

proc blueComponent*(self: NSColor): float32 =
  clamp01(self.b)

proc hueComponent*(self: NSColor): float32 =
  var value = 0.0'f32
  self.getHue(addr value, nil, nil, nil)
  value

proc saturationComponent*(self: NSColor): float32 =
  var value = 0.0'f32
  self.getHue(nil, addr value, nil, nil)
  value

proc brightnessComponent*(self: NSColor): float32 =
  var value = 0.0'f32
  self.getHue(nil, nil, addr value, nil)
  value

proc cyanComponent*(self: NSColor): float32 =
  var value = 0.0'f32
  self.getCyan(addr value, nil, nil, nil, nil)
  value

proc magentaComponent*(self: NSColor): float32 =
  var value = 0.0'f32
  self.getCyan(nil, addr value, nil, nil, nil)
  value

proc yellowComponent*(self: NSColor): float32 =
  var value = 0.0'f32
  self.getCyan(nil, nil, addr value, nil, nil)
  value

proc blackComponent*(self: NSColor): float32 =
  var value = 0.0'f32
  self.getCyan(nil, nil, nil, addr value, nil)
  value

proc alphaComponent*(self: NSColor): float32 =
  clamp01(self.a)

proc colorWithAlphaComponent*(self: NSColor, alpha: float32): NSColor =
  nsColor(self.r, self.g, self.b, clamp01(alpha))

proc colorUsingColorSpaceName*(self: NSColor, colorSpace: NSString): NSColor =
  self

proc colorUsingColorSpaceName*(
    self: NSColor,
    colorSpace: NSString,
    device {.kw("device").}: NSDictionary[NSObject, NSObject],
): NSColor =
  self

proc blendedColorWithFraction*(
    self: NSColor, fraction: float32, color {.kw("ofColor").}: NSColor
): NSColor =
  let f = clamp01(fraction)
  nsColor(
    color.r * f + self.r * (1.0 - f),
    color.g * f + self.g * (1.0 - f),
    color.b * f + self.b * (1.0 - f),
    color.a * f + self.a * (1.0 - f),
  )

proc `set`*(self: NSColor) =
  discard

proc setFill*(self: NSColor) =
  discard

proc setStroke*(self: NSColor) =
  discard

proc drawSwatchInRect*(self: NSColor, rect: NSRect) =
  discard

proc writeToPasteboard*(self: NSColor, pasteboard: NSObject) =
  discard

ensureColorSpaceNames()
