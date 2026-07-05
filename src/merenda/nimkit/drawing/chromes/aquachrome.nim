import sigils/core
import sigils/selectors

import ../../themes
import ../drawing
import ../chrome
import ../../foundation/types

type
  AquaChrome = ref object of Chrome

  AquaButtonPalette = object
    rimTop, rimMid, rimBottom, rimStroke: Color
    innerTop, innerMid, innerBottom: Color
    topShade, waistShade, lowerWash, sideShade, bottomGlow: Color

const AquaButtonInset = 2.0'f32

var fallbackAquaChrome {.threadvar.}: Chrome

func transparentFill(): Fill =
  fill(color(0.0, 0.0, 0.0, 0.0))

func rgbaColor(r, g, b, a: int): Color =
  color(
    r.float32 / 255.0'f32,
    g.float32 / 255.0'f32,
    b.float32 / 255.0'f32,
    a.float32 / 255.0'f32,
  )

func withAlphaByte(source: Color, alpha: int): Color =
  color(source.r, source.g, source.b, alpha.float32 / 255.0'f32)

func withPart(chrome: ChromeContext, part: ChromePart): ChromeContext =
  result = chrome
  result.part = part

func withPart(chrome: ChromeContext, part: ChromePart, baseFill: Fill): ChromeContext =
  result = chrome
  result.part = part
  result.baseFill = baseFill

func isEnabled(chrome: ChromeContext): bool =
  ssDisabled notin chrome.states

func isPressed(chrome: ChromeContext): bool =
  ssHighlighted in chrome.states or ssPressed in chrome.states

func isSelected(chrome: ChromeContext): bool =
  ssSelected in chrome.states

func isOpen(chrome: ChromeContext): bool =
  ssOpen in chrome.states

func isRadioChoice(chrome: ChromeContext): bool =
  chrome.role == crRadioIndicator

func clampUnit(value: float32): float32 =
  min(max(value, 0.0'f32), 1.0'f32)

func lightenColor(color: Color, amount: float32, alpha: float32): Color =
  let mix = amount.clampUnit
  color(
    color.r + (1.0'f32 - color.r) * mix,
    color.g + (1.0'f32 - color.g) * mix,
    color.b + (1.0'f32 - color.b) * mix,
    alpha.clampUnit,
  )

func darkenColor(color: Color, amount: float32, alpha: float32): Color =
  let mix = 1.0'f32 - amount.clampUnit
  color(color.r * mix, color.g * mix, color.b * mix, alpha.clampUnit)

func scaledAlpha(color: Color, alpha: float32): float32 =
  (color.a * alpha).clampUnit

func withAlphaScale(color: Color, scale: float32): Color =
  color(color.r, color.g, color.b, (color.a * scale).clampUnit)

func darkenKeepingAlpha(color: Color, amount: float32): Color =
  let scale = 1.0'f32 - amount.clampUnit
  color(color.r * scale, color.g * scale, color.b * scale, color.a)

func aquaButtonBasePalette(): AquaButtonPalette =
  AquaButtonPalette(
    rimTop: rgbaColor(50, 82, 190, 150),
    rimMid: rgbaColor(70, 150, 230, 128),
    rimBottom: rgbaColor(58, 132, 210, 122),
    rimStroke: rgbaColor(30, 80, 180, 150),
    innerTop: rgbaColor(172, 205, 250, 125),
    innerMid: rgbaColor(88, 160, 245, 120),
    innerBottom: rgbaColor(135, 220, 255, 125),
    topShade: rgbaColor(0, 48, 150, 36),
    waistShade: rgbaColor(0, 74, 180, 28),
    lowerWash: rgbaColor(255, 255, 255, 22),
    sideShade: rgbaColor(0, 68, 160, 18),
    bottomGlow: rgbaColor(210, 248, 255, 74),
  )

func scaleAlpha(palette: AquaButtonPalette, scale: float32): AquaButtonPalette =
  AquaButtonPalette(
    rimTop: palette.rimTop.withAlphaScale(scale),
    rimMid: palette.rimMid.withAlphaScale(scale),
    rimBottom: palette.rimBottom.withAlphaScale(scale),
    rimStroke: palette.rimStroke.withAlphaScale(scale),
    innerTop: palette.innerTop.withAlphaScale(scale),
    innerMid: palette.innerMid.withAlphaScale(scale),
    innerBottom: palette.innerBottom.withAlphaScale(scale),
    topShade: palette.topShade.withAlphaScale(scale),
    waistShade: palette.waistShade.withAlphaScale(scale),
    lowerWash: palette.lowerWash.withAlphaScale(scale),
    sideShade: palette.sideShade.withAlphaScale(scale),
    bottomGlow: palette.bottomGlow.withAlphaScale(scale),
  )

func darken(palette: AquaButtonPalette, amount: float32): AquaButtonPalette =
  AquaButtonPalette(
    rimTop: palette.rimTop.darkenKeepingAlpha(amount),
    rimMid: palette.rimMid.darkenKeepingAlpha(amount),
    rimBottom: palette.rimBottom.darkenKeepingAlpha(amount),
    rimStroke: palette.rimStroke.darkenKeepingAlpha(amount),
    innerTop: palette.innerTop.darkenKeepingAlpha(amount),
    innerMid: palette.innerMid.darkenKeepingAlpha(amount),
    innerBottom: palette.innerBottom.darkenKeepingAlpha(amount),
    topShade: palette.topShade,
    waistShade: palette.waistShade,
    lowerWash: palette.lowerWash,
    sideShade: palette.sideShade,
    bottomGlow: palette.bottomGlow,
  )

func aquaButtonPalette(chrome: ChromeContext): AquaButtonPalette =
  let
    alphaScale = if chrome.isEnabled: 1.0'f32 else: 0.42'f32
    pressedDarken = if chrome.isPressed: 0.18'f32 else: 0.0'f32
  aquaButtonBasePalette().scaleAlpha(alphaScale).darken(pressedDarken)

func aquaButtonFaceFill(chrome: ChromeContext): Fill =
  let p = chrome.aquaButtonPalette
  linear(p.innerTop, p.innerMid, p.innerBottom, fgaY, 124'u8)

func aquaButtonLowerWash(chrome: ChromeContext): Fill =
  let p = chrome.aquaButtonPalette
  linear(
    color(1.0, 1.0, 1.0, 0.0),
    p.lowerWash,
    color(p.bottomGlow.r, p.bottomGlow.g, p.bottomGlow.b, 44.0'f32 / 255.0'f32),
    fgaY,
    164'u8,
  )

func aquaButtonGlossFill(chrome: ChromeContext): Fill =
  let p = chrome.aquaButtonPalette
  linear(p.topShade, color(p.topShade.r, p.topShade.g, p.topShade.b, 0.0), fgaY)

func aquaButtonInnerShadows(chrome: ChromeContext): seq[BoxShadow] =
  let p = chrome.aquaButtonPalette
  @[
    insetShadow(rgbaColor(0, 0, 0, 26), y = 1.2, blur = 3.0),
    insetShadow(rgbaColor(255, 255, 255, 68), y = -1.0, blur = 2.0),
    insetShadow(p.sideShade, x = 2.0, blur = 7.0),
    insetShadow(p.sideShade, x = -2.0, blur = 7.0),
  ]

func aquaRadioShellFill(chrome: ChromeContext): Fill =
  if chrome.isEnabled:
    return linear(rgbaColor(253, 253, 250, 255), rgbaColor(166, 168, 164, 255), fgaY)
  linear(rgbaColor(230, 232, 237, 160), rgbaColor(194, 199, 209, 160), fgaY)

func aquaRadioInnerFill(chrome: ChromeContext): Fill =
  if chrome.isSelected:
    return chrome.baseFill
  if chrome.isEnabled:
    return linear(rgbaColor(255, 255, 255, 255), rgbaColor(235, 235, 232, 255), fgaY)
  linear(rgbaColor(240, 242, 245, 160), rgbaColor(209, 214, 224, 160), fgaY)

func aquaRadioInnerBorderColor(chrome: ChromeContext): Color =
  if chrome.isSelected and chrome.isEnabled:
    return rgbaColor(0, 82, 191, 245)
  if chrome.isEnabled:
    return rgbaColor(201, 203, 199, 200)
  rgbaColor(158, 168, 184, 108)

func aquaRadioInnerShadows(chrome: ChromeContext): seq[BoxShadow] =
  if chrome.isSelected and chrome.isEnabled:
    return
      @[
        insetShadow(rgbaColor(0, 58, 142, 86), y = 1.0, blur = 2.8),
        insetShadow(rgbaColor(255, 255, 255, 80), x = -1.0, y = -1.0, blur = 2.8),
        insetShadow(rgbaColor(0, 51, 120, 46), x = 1.0, blur = 3.8),
      ]
  @[
    insetShadow(
      rgbaColor(0, 0, 0, if chrome.isEnabled: 30 else: 13), y = 1.0, blur = 2.5
    ),
    insetShadow(
      rgbaColor(255, 255, 255, if chrome.isEnabled: 115 else: 46), y = -1.0, blur = 2.0
    ),
  ]

func aquaChoiceFaceFill(chrome: ChromeContext): Fill =
  if chrome.isRadioChoice:
    return aquaRadioShellFill(chrome)
  chrome.baseFill

func aquaChoiceGlossFill(chrome: ChromeContext): Fill =
  let alpha =
    if not chrome.isEnabled:
      46
    elif chrome.isSelected:
      142
    else:
      178
  linear(rgbaColor(255, 255, 255, alpha), rgbaColor(255, 255, 255, 0), fgaY)

func aquaComboFaceFill(chrome: ChromeContext): Fill =
  if not chrome.isEnabled:
    return linear(rgbaColor(236, 238, 238, 150), rgbaColor(204, 208, 210, 142), fgaY)
  if chrome.isPressed or chrome.isOpen:
    return linear(
      rgbaColor(238, 241, 241, 224),
      rgbaColor(220, 224, 224, 214),
      rgbaColor(178, 183, 181, 196),
      fgaY,
      92'u8,
    )
  linear(
    rgbaColor(255, 255, 255, 226),
    rgbaColor(238, 242, 244, 214),
    rgbaColor(196, 207, 212, 196),
    fgaY,
    92'u8,
  )

func aquaComboGlossFill(chrome: ChromeContext): Fill =
  let alpha =
    if not chrome.isEnabled:
      46
    elif chrome.isPressed or chrome.isOpen:
      132
    else:
      185
  linear(rgbaColor(255, 255, 255, alpha), rgbaColor(255, 255, 255, 0), fgaY)

func aquaComboLowerWash(chrome: ChromeContext): Fill =
  discard chrome
  fill(color(0.0, 0.0, 0.0, 0.0))

func aquaTextFieldFaceFill(chrome: ChromeContext): Fill =
  let
    base = chrome.baseFill.centerColor()
    alpha =
      if chrome.isEnabled:
        base.scaledAlpha(1.18'f32)
      else:
        base.scaledAlpha(0.48'f32)
  linear(
    base.lightenColor(0.96'f32, alpha),
    base.lightenColor(0.34'f32, alpha),
    base.darkenColor(0.08'f32, alpha),
    fgaY,
    82'u8,
  )

func aquaTextFieldGlossFill(chrome: ChromeContext): Fill =
  let
    base = chrome.baseFill.centerColor()
    alpha =
      if chrome.isEnabled:
        base.scaledAlpha(0.86'f32)
      else:
        base.scaledAlpha(0.28'f32)
  linear(color(1.0, 1.0, 1.0, alpha), color(1.0, 1.0, 1.0, 0.0), fgaY)

func aquaTextFieldLowerWash(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  linear(
    color(1.0, 1.0, 1.0, 0.0),
    base.lightenColor(0.20'f32, base.scaledAlpha(0.24'f32)),
    base.lightenColor(0.46'f32, base.scaledAlpha(0.34'f32)),
    fgaY,
    164'u8,
  )

func aquaTextFieldInnerShadows(chrome: ChromeContext): seq[BoxShadow] =
  let
    base = chrome.baseFill.centerColor()
    sideShade = base.darkenColor(0.28'f32, base.scaledAlpha(0.18'f32))
  @[
    insetShadow(rgbaColor(0, 0, 0, 24), y = 1.2, blur = 3.0),
    insetShadow(rgbaColor(255, 255, 255, 86), y = -1.0, blur = 2.0),
    insetShadow(sideShade, x = 2.0, blur = 7.0),
    insetShadow(sideShade, x = -2.0, blur = 7.0),
  ]

func aquaComboArrowFill(chrome: ChromeContext): Fill =
  if not chrome.isEnabled:
    return linear(rgbaColor(210, 214, 219, 168), rgbaColor(158, 166, 173, 164), fgaY)
  if chrome.isPressed or chrome.isOpen:
    return linear(
      rgbaColor(98, 204, 252, 230),
      rgbaColor(18, 132, 231, 224),
      rgbaColor(0, 70, 178, 226),
      fgaY,
      104'u8,
    )
  linear(
    rgbaColor(125, 230, 255, 230),
    rgbaColor(38, 171, 251, 224),
    rgbaColor(0, 112, 224, 226),
    fgaY,
    104'u8,
  )

func aquaComboSeparatorFill(chrome: ChromeContext): Fill =
  if not chrome.isEnabled:
    return fill(rgbaColor(120, 126, 132, 110))
  linear(rgbaColor(0, 70, 168, 165), rgbaColor(0, 40, 112, 205), fgaY)

func aquaSliderTrackFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    return linear(
      base.lightenColor(0.32'f32, base.scaledAlpha(0.50'f32)),
      base.lightenColor(0.64'f32, base.scaledAlpha(0.50'f32)),
      fgaY,
    )
  let alpha = base.scaledAlpha(0.92'f32)
  linear(base.darkenColor(0.18'f32, alpha), base.lightenColor(0.36'f32, alpha), fgaY)

func aquaSliderTrackHighlightFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    return linear(
      base.lightenColor(0.52'f32, base.scaledAlpha(0.34'f32)),
      base.lightenColor(0.76'f32, base.scaledAlpha(0.34'f32)),
      fgaY,
    )
  let alpha = base.scaledAlpha(1.0'f32)
  linear(
    base.lightenColor(0.54'f32, alpha),
    base.lightenColor(0.18'f32, alpha),
    base.darkenColor(0.10'f32, alpha),
    fgaY,
    106'u8,
  )

func aquaSliderKnobFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    return linear(
      base.lightenColor(0.42'f32, base.scaledAlpha(0.68'f32)),
      base.darkenColor(0.06'f32, base.scaledAlpha(0.68'f32)),
      fgaY,
    )
  if chrome.isPressed:
    let alpha = base.scaledAlpha(1.0'f32)
    return linear(
      base.lightenColor(0.58'f32, alpha),
      base.lightenColor(0.18'f32, alpha),
      base.darkenColor(0.22'f32, alpha),
      fgaY,
      104'u8,
    )
  let alpha = base.scaledAlpha(1.0'f32)
  linear(
    base.lightenColor(0.98'f32, alpha),
    base.lightenColor(0.48'f32, alpha),
    base.darkenColor(0.10'f32, alpha),
    fgaY,
    102'u8,
  )

func aquaSliderKnobGlossFill(chrome: ChromeContext): Fill =
  let
    base = chrome.baseFill.centerColor()
    alpha = base.scaledAlpha(
      if not chrome.isEnabled:
        0.18'f32
      elif chrome.isPressed:
        0.44'f32
      else:
        0.62'f32
    )
  linear(color(1.0, 1.0, 1.0, alpha), color(1.0, 1.0, 1.0, 0.0), fgaY)

func aquaSliderKnobLowerWash(chrome: ChromeContext): Fill =
  let
    base = chrome.baseFill.centerColor()
    alpha =
      if not chrome.isEnabled:
        0.08'f32
      elif chrome.isPressed:
        0.20'f32
      else:
        0.14'f32
  linear(
    color(1.0, 1.0, 1.0, 0.0), base.darkenColor(0.22'f32, base.scaledAlpha(alpha)), fgaY
  )

func aquaPopupListFaceFill(chrome: ChromeContext): Fill =
  if not chrome.isEnabled:
    return linear(rgbaColor(236, 238, 238, 180), rgbaColor(204, 208, 210, 180), fgaY)
  linear(
    rgbaColor(255, 255, 255, 255),
    rgbaColor(238, 239, 237, 255),
    rgbaColor(205, 207, 203, 255),
    fgaY,
    92'u8,
  )

func aquaTabFaceFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    let alpha = base.scaledAlpha(0.95'f32)
    linear(base.lightenColor(0.24'f32, alpha), base.darkenColor(0.04'f32, alpha), fgaY)
  elif ssSelected in chrome.states:
    let alpha = base.scaledAlpha(1.0'f32)
    linear(
      base.lightenColor(0.72'f32, alpha),
      base.lightenColor(0.36'f32, alpha),
      base.darkenColor(0.04'f32, alpha),
      fgaY,
      112'u8,
    )
  elif chrome.isPressed:
    let alpha = base.scaledAlpha(1.0'f32)
    linear(base.lightenColor(0.12'f32, alpha), base.darkenColor(0.18'f32, alpha), fgaY)
  else:
    let alpha = base.scaledAlpha(1.0'f32)
    linear(
      base.lightenColor(0.80'f32, alpha),
      base.lightenColor(0.34'f32, alpha),
      base.darkenColor(0.05'f32, alpha),
      fgaY,
      112'u8,
    )

func aquaTabInnerFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if chrome.isSelected:
    let alpha = base.scaledAlpha(0.98'f32)
    return linear(
      base.lightenColor(0.88'f32, alpha),
      base.lightenColor(0.46'f32, alpha),
      base.darkenColor(0.03'f32, alpha),
      fgaY,
      116'u8,
    )
  let alpha = base.scaledAlpha(0.98'f32)
  linear(
    base.lightenColor(0.96'f32, alpha),
    base.lightenColor(0.54'f32, alpha),
    base.darkenColor(0.08'f32, alpha),
    fgaY,
    112'u8,
  )

func aquaTabPanelFaceFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  let alpha = base.scaledAlpha(1.0'f32)
  linear(base.lightenColor(0.16'f32, alpha), base.darkenColor(0.05'f32, alpha), fgaY)

func aquaDocumentTabFaceFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    let alpha = base.scaledAlpha(0.62'f32)
    return linear(
      base.lightenColor(0.28'f32, alpha), base.darkenColor(0.08'f32, alpha), fgaY
    )
  if chrome.isSelected:
    let alpha = base.scaledAlpha(1.0'f32)
    return linear(
      base.lightenColor(0.82'f32, alpha),
      base.lightenColor(0.50'f32, alpha),
      base.lightenColor(0.10'f32, alpha),
      fgaY,
      112'u8,
    )
  if chrome.isPressed:
    let alpha = base.scaledAlpha(1.0'f32)
    return linear(
      base.lightenColor(0.24'f32, alpha), base.darkenColor(0.14'f32, alpha), fgaY
    )
  let alpha = base.scaledAlpha(1.0'f32)
  linear(
    base.lightenColor(0.70'f32, alpha),
    base.lightenColor(0.32'f32, alpha),
    base.darkenColor(0.08'f32, alpha),
    fgaY,
    112'u8,
  )

func aquaDocumentTabInnerFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  let alpha = base.scaledAlpha(if chrome.isEnabled: 0.96'f32 else: 0.44'f32)
  if chrome.isSelected:
    return linear(
      base.lightenColor(0.92'f32, alpha),
      base.lightenColor(0.58'f32, alpha),
      base.lightenColor(0.16'f32, alpha),
      fgaY,
      112'u8,
    )
  linear(
    base.lightenColor(0.86'f32, alpha),
    base.lightenColor(0.44'f32, alpha),
    base.darkenColor(0.04'f32, alpha),
    fgaY,
    112'u8,
  )

func aquaDocumentTabBarFaceFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  let alpha = base.scaledAlpha(0.92'f32)
  linear(base.lightenColor(0.22'f32, alpha), base.darkenColor(0.08'f32, alpha), fgaY)

func chromeEdgeHighlightRect(edge: ChromeEdge, rect: Rect): Rect =
  case edge
  of ceTop:
    rect(
      rect.origin.x + 4.0'f32,
      rect.origin.y + 1.0'f32,
      max(rect.size.width - 8.0'f32, 0.0'f32),
      1.0'f32,
    )
  of ceBottom:
    rect(
      rect.origin.x + 4.0'f32,
      rect.maxY - 2.0'f32,
      max(rect.size.width - 8.0'f32, 0.0'f32),
      1.0'f32,
    )
  of ceNone:
    rect(rect.origin.x, rect.origin.y, 0.0'f32, 0.0'f32)

func chromeEdgeSeamRect(edge: ChromeEdge, rect: Rect): Rect =
  case edge
  of ceTop:
    rect(
      rect.origin.x + 1.0'f32,
      rect.maxY - 1.0'f32,
      max(rect.size.width - 2.0'f32, 0.0'f32),
      2.0'f32,
    )
  of ceBottom:
    rect(
      rect.origin.x + 1.0'f32,
      rect.origin.y,
      max(rect.size.width - 2.0'f32, 0.0'f32),
      2.0'f32,
    )
  of ceNone:
    rect(rect.origin.x, rect.origin.y, 0.0'f32, 0.0'f32)

proc drawAquaButtonBacking(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  if not chrome.isEnabled:
    return
  let shadowRect = rect(
    extras.rect.origin.x,
    extras.rect.origin.y + 1.5'f32,
    extras.rect.size.width,
    extras.rect.size.height,
  )
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    shadowRect,
    fill(rgbaColor(0, 0, 0, 54)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    extras.cornerRadius,
    [dropShadow(rgbaColor(0, 0, 0, 58), y = 1.8, blur = 5.8)],
  )

proc drawAquaRoundedControlBacking(
    context: DrawContext,
    chrome: ChromeContext,
    extras: ChromeExtras,
    fillAlpha: int,
    shadowAlpha: int,
    yOffset: float32,
    blur: float32,
) =
  if not chrome.isEnabled:
    return
  let shadowRect = rect(
    extras.rect.origin.x,
    extras.rect.origin.y + yOffset,
    extras.rect.size.width,
    extras.rect.size.height,
  )
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    shadowRect,
    fill(rgbaColor(0, 0, 0, fillAlpha)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    extras.cornerRadius,
    [dropShadow(rgbaColor(0, 0, 0, shadowAlpha), y = yOffset, blur = blur)],
  )

proc drawAquaButtonExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let
    radius = extras.cornerRadius
    inner = extras.rect.inset(insets(AquaButtonInset))
  if inner.isEmpty:
    return

  let
    innerChrome = chrome.withPart(cpInnerFace)
    innerRadius = max(radius - AquaButtonInset, 1.0'f32)
    innerRoot = context.addRenderRectangle(
      extras.layer,
      extras.parent,
      inner,
      context.appearance.chromeFill(innerChrome),
      color(0.0, 0.0, 0.0, 0.0),
      0.0'f32,
      innerRadius,
      aquaButtonInnerShadows(chrome),
      lightMaskContent = true,
    )
    topShade = rect(
      inner.origin.x - 2.0'f32,
      inner.origin.y,
      inner.size.width + 4.0'f32,
      inner.size.height * 0.38'f32,
    )
    upperSheen = rect(
      inner.origin.x + 15.0'f32,
      inner.origin.y + 3.2'f32,
      max(inner.size.width - 30.0'f32, 0.0'f32),
      1.0'f32,
    )
    waistShade = rect(
      inner.origin.x + 12.0'f32,
      inner.origin.y + inner.size.height * 0.36'f32,
      max(inner.size.width - 24.0'f32, 0.0'f32),
      1.0'f32,
    )
    lowerGloss = rect(
      inner.origin.x - 2.0'f32,
      inner.origin.y + inner.size.height * 0.45'f32,
      inner.size.width + 4.0'f32,
      inner.size.height * 0.55'f32,
    )
    lowerBloom = rect(
      inner.origin.x + 16.0'f32,
      inner.origin.y + inner.size.height * 0.66'f32,
      max(inner.size.width - 32.0'f32, 0.0'f32),
      1.0'f32,
    )
    bottomGlow = rect(
      inner.origin.x + 10.0'f32,
      inner.origin.y + inner.size.height - 2.8'f32,
      max(inner.size.width - 20.0'f32, 0.0'f32),
      1.0'f32,
    )
  discard context.addRenderRectangle(
    extras.layer,
    innerRoot,
    topShade,
    context.appearance.chromeFill(chrome.withPart(cpGloss)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    innerRadius,
  )
  if not upperSheen.isEmpty:
    discard context.addRenderRectangle(
      extras.layer,
      innerRoot,
      upperSheen,
      transparentFill(),
      shadows = [
        dropShadow(rgbaColor(255, 255, 255, 36), y = 1.0, blur = 8.0),
        dropShadow(
          chrome.aquaButtonPalette.innerTop.withAlphaByte(38), y = 2.0, blur = 5.0
        ),
      ],
    )
  if not waistShade.isEmpty:
    discard context.addRenderRectangle(
      extras.layer,
      innerRoot,
      waistShade,
      transparentFill(),
      shadows = [
        dropShadow(
          chrome.aquaButtonPalette.waistShade.withAlphaByte(30), y = 1.2, blur = 6.0
        ),
        dropShadow(rgbaColor(255, 255, 255, 14), y = -1.2, blur = 4.0),
      ],
    )
  discard context.addRenderRectangle(
    extras.layer,
    innerRoot,
    lowerGloss,
    context.appearance.chromeFill(chrome.withPart(cpLowerWash)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    innerRadius,
  )
  if not lowerBloom.isEmpty:
    discard context.addRenderRectangle(
      extras.layer,
      innerRoot,
      lowerBloom,
      transparentFill(),
      shadows = [
        dropShadow(
          chrome.aquaButtonPalette.bottomGlow.withAlphaByte(36), y = 1.2, blur = 8.0
        ),
        dropShadow(rgbaColor(255, 255, 255, 14), y = -0.6, blur = 5.0),
      ],
    )
  if not bottomGlow.isEmpty:
    discard context.addRenderRectangle(
      extras.layer,
      innerRoot,
      bottomGlow,
      transparentFill(),
      shadows = [
        dropShadow(
          chrome.aquaButtonPalette.bottomGlow.withAlphaByte(30), y = -1.2, blur = 5.5
        )
      ],
    )

proc drawAquaTextFieldExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let
    base = chrome.baseFill.centerColor()
    radius = extras.cornerRadius
    innerInset = 1.6'f32
    inner = extras.rect.inset(insets(innerInset))
  if inner.isEmpty:
    return

  let
    innerChrome = chrome.withPart(cpInnerFace)
    innerRadius = max(radius - innerInset, 1.0'f32)
    innerRoot = context.addRenderRectangle(
      extras.layer,
      extras.parent,
      inner,
      context.appearance.chromeFill(innerChrome),
      color(0.0, 0.0, 0.0, 0.0),
      0.0'f32,
      innerRadius,
      aquaTextFieldInnerShadows(chrome),
      lightMaskContent = true,
    )
    topShade = rect(
      inner.origin.x - 2.0'f32,
      inner.origin.y,
      inner.size.width + 4.0'f32,
      inner.size.height * 0.42'f32,
    )
    upperSheen = rect(
      inner.origin.x + 10.0'f32,
      inner.origin.y + 2.6'f32,
      max(inner.size.width - 20.0'f32, 0.0'f32),
      1.0'f32,
    )
    waistShade = rect(
      inner.origin.x + 8.0'f32,
      inner.origin.y + inner.size.height * 0.38'f32,
      max(inner.size.width - 16.0'f32, 0.0'f32),
      1.0'f32,
    )
    lowerGloss = rect(
      inner.origin.x - 2.0'f32,
      inner.origin.y + inner.size.height * 0.46'f32,
      inner.size.width + 4.0'f32,
      inner.size.height * 0.54'f32,
    )
    lowerBloom = rect(
      inner.origin.x + 12.0'f32,
      inner.origin.y + inner.size.height * 0.68'f32,
      max(inner.size.width - 24.0'f32, 0.0'f32),
      1.0'f32,
    )
    bottomGlow = rect(
      inner.origin.x + 8.0'f32,
      inner.origin.y + inner.size.height - 2.4'f32,
      max(inner.size.width - 16.0'f32, 0.0'f32),
      1.0'f32,
    )
  discard context.addRenderRectangle(
    extras.layer,
    innerRoot,
    topShade,
    context.appearance.chromeFill(chrome.withPart(cpGloss)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    innerRadius,
  )
  if not upperSheen.isEmpty:
    discard context.addRenderRectangle(
      extras.layer,
      innerRoot,
      upperSheen,
      transparentFill(),
      shadows = [
        dropShadow(rgbaColor(255, 255, 255, 54), y = 1.0, blur = 8.0),
        dropShadow(
          base.lightenColor(0.62'f32, base.scaledAlpha(0.22'f32)), y = 2.0, blur = 5.0
        ),
      ],
    )
  if not waistShade.isEmpty:
    discard context.addRenderRectangle(
      extras.layer,
      innerRoot,
      waistShade,
      transparentFill(),
      shadows = [
        dropShadow(
          base.darkenColor(0.20'f32, base.scaledAlpha(0.16'f32)), y = 1.2, blur = 6.0
        ),
        dropShadow(rgbaColor(255, 255, 255, 16), y = -1.2, blur = 4.0),
      ],
    )
  discard context.addRenderRectangle(
    extras.layer,
    innerRoot,
    lowerGloss,
    context.appearance.chromeFill(chrome.withPart(cpLowerWash)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    innerRadius,
  )
  if not lowerBloom.isEmpty:
    discard context.addRenderRectangle(
      extras.layer,
      innerRoot,
      lowerBloom,
      transparentFill(),
      shadows = [
        dropShadow(
          base.lightenColor(0.48'f32, base.scaledAlpha(0.30'f32)), y = 1.2, blur = 8.0
        ),
        dropShadow(rgbaColor(255, 255, 255, 16), y = -0.6, blur = 5.0),
      ],
    )
  if not bottomGlow.isEmpty:
    discard context.addRenderRectangle(
      extras.layer,
      innerRoot,
      bottomGlow,
      transparentFill(),
      shadows = [
        dropShadow(
          base.lightenColor(0.58'f32, base.scaledAlpha(0.34'f32)), y = -1.2, blur = 5.5
        )
      ],
    )

proc drawAquaComboBacking(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  context.drawAquaRoundedControlBacking(
    chrome, extras, fillAlpha = 32, shadowAlpha = 38, yOffset = 1.3'f32, blur = 3.8'f32
  )

proc drawAquaKnobBacking(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  context.drawAquaRoundedControlBacking(
    chrome, extras, fillAlpha = 34, shadowAlpha = 42, yOffset = 1.2'f32, blur = 4.2'f32
  )

proc drawAquaChoiceExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  if chrome.isRadioChoice:
    let
      innerInset = if chrome.isSelected: 1.6'f32 else: 2.0'f32
      inner = extras.rect.inset(insets(innerInset))
      innerRadius = max(min(inner.size.width, inner.size.height) / 2.0'f32, 1.0'f32)
    if inner.isEmpty:
      return
    let
      innerRoot = context.addRenderRectangle(
        extras.layer,
        extras.parent,
        inner,
        context.appearance.chromeFill(chrome.withPart(cpInnerFace)),
        aquaRadioInnerBorderColor(chrome),
        0.5'f32,
        innerRadius,
        aquaRadioInnerShadows(chrome),
        lightMaskContent = true,
      )
      glossWidth =
        if chrome.isSelected:
          max(inner.size.width * 0.52'f32, 1.0'f32)
        else:
          max(inner.size.width - 4.0'f32, 0.0'f32)
      glossHeight =
        if chrome.isSelected:
          max(inner.size.height * 0.18'f32, 1.0'f32)
        else:
          max(inner.size.height * 0.22'f32, 1.0'f32)
      innerGloss = rect(
        inner.origin.x + (inner.size.width - glossWidth) / 2.0'f32,
        inner.origin.y + 1.0'f32,
        glossWidth,
        glossHeight,
      )
    if not innerGloss.isEmpty:
      discard context.addRenderRectangle(
        extras.layer,
        innerRoot,
        innerGloss,
        context.appearance.chromeFill(chrome.withPart(cpGloss)),
        color(0.0, 0.0, 0.0, 0.0),
        0.0'f32,
        max(innerRadius - 2.0'f32, 1.0'f32),
      )
    return

  let
    inset = if chrome.isSelected: 1.5'f32 else: 1.4'f32
    glossHeight = if chrome.isSelected: 3.1'f32 else: 2.6'f32
    gloss = rect(
      extras.rect.origin.x + inset,
      extras.rect.origin.y + 1.1'f32,
      max(extras.rect.size.width - inset * 2.0'f32, 0.0'f32),
      min(glossHeight, max(extras.rect.size.height - 2.2'f32, 0.0'f32)),
    )
  if gloss.isEmpty:
    return
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    gloss,
    context.appearance.chromeFill(chrome.withPart(cpGloss)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    if chrome.isSelected: 1.4'f32 else: 1.1'f32,
  )

proc drawAquaComboFaceExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let gloss = rect(
    extras.rect.origin.x + 2.4'f32,
    extras.rect.origin.y + 1.2'f32,
    max(extras.rect.size.width - 4.8'f32, 0.0'f32),
    min(4.0'f32, max(extras.rect.size.height - 2.4'f32, 0.0'f32)),
  )
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    gloss,
    context.appearance.chromeFill(chrome.withPart(cpGloss)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    max(extras.cornerRadius - 1.0'f32, 1.0'f32),
  )

proc drawAquaComboArrowExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let gloss = rect(
    extras.rect.origin.x + 2.0'f32,
    extras.rect.origin.y + 1.1'f32,
    max(extras.rect.size.width - 4.0'f32, 0.0'f32),
    min(3.2'f32, max(extras.rect.size.height - 2.2'f32, 0.0'f32)),
  )
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    gloss,
    context.appearance.chromeFill(chrome.withPart(cpGloss)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    1.4'f32,
  )

proc drawAquaPopupListExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let
    topHighlight = rect(
      extras.rect.origin.x + 2.4'f32,
      extras.rect.origin.y + 1.2'f32,
      max(extras.rect.size.width - 4.8'f32, 0.0'f32),
      min(4.0'f32, max(extras.rect.size.height - 2.4'f32, 0.0'f32)),
    )
    bottomShade = rect(
      extras.rect.origin.x + 1.0'f32,
      extras.rect.maxY - 2.0'f32,
      max(extras.rect.size.width - 2.0'f32, 0.0'f32),
      1.0'f32,
    )
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    topHighlight,
    context.appearance.chromeFill(chrome.withPart(cpGloss)),
    cornerRadius = max(extras.cornerRadius - 2.0'f32, 1.0'f32),
  )
  discard context.addRenderRectangle(
    extras.layer, extras.parent, bottomShade, fill(color(0.0, 0.0, 0.0, 0.08))
  )

proc drawAquaSliderTrackExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let
    topHighlight = rect(
      extras.rect.origin.x + 1.0'f32,
      extras.rect.origin.y + 1.0'f32,
      max(extras.rect.size.width - 2.0'f32, 0.0'f32),
      1.0'f32,
    )
    bottomShade = rect(
      extras.rect.origin.x + 1.0'f32,
      extras.rect.maxY - 2.0'f32,
      max(extras.rect.size.width - 2.0'f32, 0.0'f32),
      1.0'f32,
    )
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    topHighlight,
    fill(color(1.0, 1.0, 1.0, if chrome.isEnabled: 0.34 else: 0.14)),
  )
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    bottomShade,
    fill(color(0.0, 0.0, 0.0, if chrome.isEnabled: 0.10 else: 0.04)),
  )

proc drawAquaSliderKnobExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let
    inset = 1.6'f32
    gloss = rect(
      extras.rect.origin.x + inset,
      extras.rect.origin.y + inset,
      max(extras.rect.size.width - inset * 2.0'f32, 0.0'f32),
      max(extras.rect.size.height * 0.38'f32, 1.0'f32),
    )
    lowerWash = rect(
      extras.rect.origin.x + inset,
      extras.rect.origin.y + extras.rect.size.height * 0.46'f32,
      max(extras.rect.size.width - inset * 2.0'f32, 0.0'f32),
      max(extras.rect.size.height * 0.42'f32, 1.0'f32),
    )
    radius = max(extras.cornerRadius - inset, 1.0'f32)
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    gloss,
    context.appearance.chromeFill(chrome.withPart(cpGloss)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    radius,
  )
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    lowerWash,
    context.appearance.chromeFill(chrome.withPart(cpLowerWash)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    radius,
  )

proc drawAquaTabExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let
    inset = 2.0'f32
    inner = extras.rect.inset(insets(inset))
    innerRadius = max(extras.cornerRadius - inset, 1.0'f32)
  if inner.isEmpty:
    return

  let innerRoot = context.addRenderRectangle(
    extras.layer,
    extras.parent,
    inner,
    context.appearance.chromeFill(chrome.withPart(cpInnerFace)),
    color(1.0, 1.0, 1.0, if chrome.isSelected: 0.22 else: 0.42),
    0.45'f32,
    innerRadius,
    [
      insetShadow(
        color(1.0, 1.0, 1.0, if chrome.isEnabled: 0.36 else: 0.14), y = 1.0, blur = 4.0
      ),
      insetShadow(
        color(0.0, 0.0, 0.0, if chrome.isSelected: 0.08 else: 0.07),
        y = -1.0,
        blur = 5.0,
      ),
    ],
    lightMaskContent = true,
  )
  discard innerRoot

  if extras.edge == ceNone:
    return

  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    chromeEdgeHighlightRect(extras.edge, extras.rect),
    context.appearance.chromeFill(chrome.withPart(cpHighlight, extras.highlightFill)),
  )
  if ssSelected in chrome.states:
    discard context.addRenderRectangle(
      extras.layer,
      extras.parent,
      chromeEdgeSeamRect(extras.edge, extras.rect),
      context.appearance.chromeFill(chrome.withPart(cpSeam, extras.seamFill)),
    )

proc drawAquaTabPanelExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  discard chrome
  let
    topHighlight = rect(
      extras.rect.origin.x + 1.0'f32,
      extras.rect.origin.y + 1.0'f32,
      max(extras.rect.size.width - 2.0'f32, 0.0'f32),
      1.0'f32,
    )
    innerShade = rect(
      extras.rect.origin.x + 1.0'f32,
      extras.rect.maxY - 2.0'f32,
      max(extras.rect.size.width - 2.0'f32, 0.0'f32),
      1.0'f32,
    )
  discard context.addRenderRectangle(
    extras.layer, extras.parent, topHighlight, fill(color(1.0, 1.0, 1.0, 0.36))
  )
  discard context.addRenderRectangle(
    extras.layer, extras.parent, innerShade, fill(color(0.0, 0.0, 0.0, 0.05))
  )

proc drawAquaDocumentTabBarExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  discard chrome
  let
    topHighlight = rect(
      extras.rect.origin.x + 1.0'f32,
      extras.rect.origin.y + 1.0'f32,
      max(extras.rect.size.width - 2.0'f32, 0.0'f32),
      1.0'f32,
    )
    innerShade = rect(
      extras.rect.origin.x + 1.0'f32,
      extras.rect.maxY - 2.0'f32,
      max(extras.rect.size.width - 2.0'f32, 0.0'f32),
      1.0'f32,
    )
  discard context.addRenderRectangle(
    extras.layer, extras.parent, topHighlight, fill(color(1.0, 1.0, 1.0, 0.24))
  )
  discard context.addRenderRectangle(
    extras.layer, extras.parent, innerShade, fill(color(0.0, 0.0, 0.0, 0.035))
  )

protocol AquaChromeProtocol of ChromeProtocol:
  method chromeFillFor(chrome: AquaChrome, context: ChromeContext): Fill =
    case context.role
    of crButton:
      case context.part
      of cpInnerFace:
        aquaButtonFaceFill(context)
      of cpGloss:
        aquaButtonGlossFill(context)
      of cpLowerWash:
        aquaButtonLowerWash(context)
      else:
        context.baseFill
    of crChoiceIndicator, crCheckBoxIndicator, crRadioIndicator:
      case context.part
      of cpFace:
        aquaChoiceFaceFill(context)
      of cpInnerFace:
        aquaRadioInnerFill(context)
      of cpGloss:
        aquaChoiceGlossFill(context)
      else:
        context.baseFill
    of crComboBox:
      case context.part
      of cpFace:
        aquaComboFaceFill(context)
      of cpArrow:
        aquaComboArrowFill(context)
      of cpSeparator:
        aquaComboSeparatorFill(context)
      of cpGloss:
        aquaComboGlossFill(context)
      of cpLowerWash:
        aquaComboLowerWash(context)
      else:
        context.baseFill
    of crTextField:
      case context.part
      of cpInnerFace:
        aquaTextFieldFaceFill(context)
      of cpGloss:
        aquaTextFieldGlossFill(context)
      of cpLowerWash:
        aquaTextFieldLowerWash(context)
      else:
        context.baseFill
    of crSliderTrack:
      case context.part
      of cpFace:
        aquaSliderTrackFill(context)
      of cpHighlight:
        aquaSliderTrackHighlightFill(context)
      else:
        context.baseFill
    of crSliderKnob:
      case context.part
      of cpFace:
        aquaSliderKnobFill(context)
      of cpGloss:
        aquaSliderKnobGlossFill(context)
      of cpLowerWash:
        aquaSliderKnobLowerWash(context)
      else:
        context.baseFill
    of crPopupList:
      case context.part
      of cpFace:
        aquaPopupListFaceFill(context)
      else:
        context.baseFill
    of crTab:
      case context.part
      of cpFace:
        aquaTabFaceFill(context)
      of cpInnerFace:
        aquaTabInnerFill(context)
      of cpHighlight:
        context.baseFill
      of cpSeam:
        context.baseFill
      else:
        context.baseFill
    of crTabPanel:
      case context.part
      of cpFace:
        aquaTabPanelFaceFill(context)
      else:
        context.baseFill
    of crDocumentTab:
      case context.part
      of cpFace:
        aquaDocumentTabFaceFill(context)
      of cpInnerFace:
        aquaDocumentTabInnerFill(context)
      of cpHighlight:
        context.baseFill
      of cpSeam:
        context.baseFill
      else:
        context.baseFill
    of crDocumentTabBar:
      case context.part
      of cpFace:
        aquaDocumentTabBarFaceFill(context)
      else:
        context.baseFill
    of crDocumentTabButton:
      case context.part
      of cpInnerFace:
        aquaButtonFaceFill(context)
      of cpGloss:
        aquaButtonGlossFill(context)
      of cpLowerWash:
        aquaButtonLowerWash(context)
      else:
        context.baseFill

  method drawChromeBackingFor(
      chrome: AquaChrome,
      context: DrawContext,
      chromeContext: ChromeContext,
      extras: ChromeExtras,
  ) =
    discard chrome
    case chromeContext.role
    of crButton:
      if chromeContext.part == cpFace:
        context.drawAquaButtonBacking(chromeContext, extras)
    of crDocumentTabButton:
      if chromeContext.part == cpFace:
        context.drawAquaButtonBacking(chromeContext, extras)
    of crComboBox:
      if chromeContext.part == cpFace:
        context.drawAquaComboBacking(chromeContext, extras)
    of crTextField:
      discard
    of crSliderKnob:
      if chromeContext.part == cpFace:
        context.drawAquaKnobBacking(chromeContext, extras)
    else:
      discard

  method drawChromeExtrasFor(
      chrome: AquaChrome,
      context: DrawContext,
      chromeContext: ChromeContext,
      extras: ChromeExtras,
  ) =
    discard chrome
    case chromeContext.role
    of crButton:
      if chromeContext.part == cpFace:
        context.drawAquaButtonExtras(chromeContext, extras)
    of crChoiceIndicator, crCheckBoxIndicator, crRadioIndicator:
      if chromeContext.part == cpFace:
        context.drawAquaChoiceExtras(chromeContext, extras)
    of crComboBox:
      case chromeContext.part
      of cpFace:
        context.drawAquaComboFaceExtras(chromeContext, extras)
      of cpArrow:
        context.drawAquaComboArrowExtras(chromeContext, extras)
      else:
        discard
    of crTextField:
      if chromeContext.part == cpFace:
        context.drawAquaTextFieldExtras(chromeContext, extras)
    of crPopupList:
      if chromeContext.part == cpFace:
        context.drawAquaPopupListExtras(chromeContext, extras)
    of crSliderTrack:
      if chromeContext.part == cpFace:
        context.drawAquaSliderTrackExtras(chromeContext, extras)
    of crSliderKnob:
      if chromeContext.part == cpFace:
        context.drawAquaSliderKnobExtras(chromeContext, extras)
    of crTab:
      if chromeContext.part == cpFace:
        context.drawAquaTabExtras(chromeContext, extras)
    of crTabPanel:
      if chromeContext.part == cpFace:
        context.drawAquaTabPanelExtras(chromeContext, extras)
    of crDocumentTab:
      if chromeContext.part == cpFace:
        context.drawAquaTabExtras(chromeContext, extras)
    of crDocumentTabBar:
      if chromeContext.part == cpFace:
        context.drawAquaDocumentTabBarExtras(chromeContext, extras)
    of crDocumentTabButton:
      if chromeContext.part == cpFace:
        context.drawAquaButtonExtras(chromeContext, extras)

proc newAquaChrome*(): Chrome =
  let aqua = AquaChrome()
  discard aqua.withProtocol(AquaChromeProtocol)
  Chrome(aqua)

proc aquaChrome(): Chrome =
  if fallbackAquaChrome.isNil:
    fallbackAquaChrome = newAquaChrome()
  fallbackAquaChrome

proc installAquaChrome*(theme: var Theme) =
  theme.installChrome(AquaChromeName, aquaChrome())

registerThemeInstaller(installAquaChrome)
