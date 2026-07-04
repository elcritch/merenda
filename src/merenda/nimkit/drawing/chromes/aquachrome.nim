import sigils/core
import sigils/selectors

import ../../themes
import ../drawing
import ../chrome
import ../../foundation/types

type AquaChrome = ref object of Chrome

const AquaButtonInset = 2.5'f32

var fallbackAquaChrome {.threadvar.}: Chrome

func transparentFill(): Fill =
  fill(color(0.0, 0.0, 0.0, 0.0))

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

func aquaButtonFaceFill(fillValue: Fill, enabled: bool): Fill =
  let
    base = fillValue.centerColor()
    topMix = 0.82'f32
    bottomMix = 0.46'f32
    alpha = base.scaledAlpha(if enabled: 0.37'f32 else: 0.21'f32)
  linear(base.lightenColor(topMix, alpha), base.lightenColor(bottomMix, alpha), fgaY)

func aquaButtonLowerWash(fillValue: Fill, enabled: bool): Fill =
  let
    base = fillValue.centerColor()
    alpha = base.scaledAlpha(if not enabled: 0.01'f32 else: 0.09'f32)
    tint = base.darkenColor(0.15'f32, alpha)
  linear(color(1.0, 1.0, 1.0, 0.0), tint, fgaY)

func aquaButtonGlossFill(enabled: bool): Fill =
  let alpha = if enabled: 0.25'f32 else: 0.07'f32
  linear(color(1.0, 1.0, 1.0, alpha), color(1.0, 1.0, 1.0, 0.0), fgaY)

func aquaButtonInnerShadows(fillValue: Fill, enabled: bool): seq[BoxShadow] =
  discard fillValue
  let darkAlpha = if enabled: 0.10'f32 else: 0.08'f32
  @[
    insetShadow(color(1.0, 1.0, 1.0, if enabled: 0.38 else: 0.14), y = 2.0, blur = 7.0),
    insetShadow(color(0.0, 0.0, 0.0, darkAlpha), y = -2.0, blur = 7.0),
  ]

func aquaRadioShellFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if chrome.isEnabled:
    let alpha = base.scaledAlpha(1.0'f32)
    return linear(color(0.99, 0.99, 0.98, alpha), color(0.65, 0.66, 0.64, alpha), fgaY)
  let alpha = base.scaledAlpha(0.62'f32)
  linear(color(0.90, 0.91, 0.93, alpha), color(0.76, 0.78, 0.82, alpha), fgaY)

func aquaRadioInnerFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if chrome.isSelected:
    return chrome.baseFill
  if chrome.isEnabled:
    let alpha = base.scaledAlpha(1.0'f32)
    return linear(color(1.0, 1.0, 1.0, alpha), color(0.92, 0.92, 0.91, alpha), fgaY)
  let alpha = base.scaledAlpha(0.62'f32)
  linear(color(0.94, 0.95, 0.96, alpha), color(0.82, 0.84, 0.88, alpha), fgaY)

func aquaRadioInnerBorderColor(chrome: ChromeContext): Color =
  if chrome.isSelected and chrome.isEnabled:
    return color(0.0, 0.32, 0.75, 0.96)
  if chrome.isEnabled:
    return color(0.79, 0.80, 0.78, 0.78)
  color(0.62, 0.66, 0.72, 0.42)

func aquaRadioInnerShadows(chrome: ChromeContext): seq[BoxShadow] =
  if chrome.isSelected and chrome.isEnabled:
    return
      @[
        insetShadow(color(0.0, 0.23, 0.56, 0.34), y = 1.0, blur = 2.8),
        insetShadow(color(1.0, 1.0, 1.0, 0.32), x = -1.0, y = -1.0, blur = 2.8),
        insetShadow(color(0.0, 0.20, 0.47, 0.18), x = 1.0, blur = 3.8),
      ]
  @[
    insetShadow(
      color(0.0, 0.0, 0.0, if chrome.isEnabled: 0.12 else: 0.05), y = 1.0, blur = 2.4
    ),
    insetShadow(
      color(1.0, 1.0, 1.0, if chrome.isEnabled: 0.46 else: 0.18), y = -1.0, blur = 2.0
    ),
  ]

func aquaChoiceFaceFill(chrome: ChromeContext): Fill =
  if chrome.isRadioChoice:
    return aquaRadioShellFill(chrome)
  chrome.baseFill

func aquaChoiceGlossFill(chrome: ChromeContext): Fill =
  let
    base = chrome.baseFill.centerColor()
    topAlpha = base.scaledAlpha(
      if not chrome.isEnabled:
        0.24'f32
      elif chrome.isSelected:
        0.56'f32
      else:
        0.70'f32
    )
  linear(color(1.0, 1.0, 1.0, topAlpha), color(1.0, 1.0, 1.0, 0.0), fgaY)

func aquaComboFaceFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    return linear(
      base.lightenColor(0.18'f32, base.scaledAlpha(0.62'f32)),
      base.darkenColor(0.04'f32, base.scaledAlpha(0.62'f32)),
      fgaY,
    )
  if chrome.isPressed or chrome.isOpen:
    let alpha = base.scaledAlpha(1.0'f32)
    return linear(
      base.lightenColor(0.70'f32, alpha),
      base.lightenColor(0.18'f32, alpha),
      base.darkenColor(0.18'f32, alpha),
      fgaY,
      104'u8,
    )
  let alpha = base.scaledAlpha(1.0'f32)
  linear(
    base.lightenColor(0.86'f32, alpha),
    base.lightenColor(0.42'f32, alpha),
    base.darkenColor(0.12'f32, alpha),
    fgaY,
    92'u8,
  )

func aquaComboGlossFill(chrome: ChromeContext): Fill =
  let
    base = chrome.baseFill.centerColor()
    alpha = base.scaledAlpha(
      if not chrome.isEnabled:
        0.20'f32
      elif chrome.isPressed or chrome.isOpen:
        0.42'f32
      else:
        0.58'f32
    )
  linear(color(1.0, 1.0, 1.0, alpha), color(1.0, 1.0, 1.0, 0.0), fgaY)

func aquaComboLowerWash(chrome: ChromeContext): Fill =
  let
    base = chrome.baseFill.centerColor()
    alpha =
      if not chrome.isEnabled:
        0.08'f32
      elif chrome.isPressed or chrome.isOpen:
        0.20'f32
      else:
        0.14'f32
  linear(
    color(1.0, 1.0, 1.0, 0.0), base.darkenColor(0.18'f32, base.scaledAlpha(alpha)), fgaY
  )

func aquaComboArrowFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    let alpha = base.scaledAlpha(0.78'f32)
    return linear(color(0.82, 0.84, 0.86, alpha), color(0.62, 0.65, 0.68, alpha), fgaY)
  if chrome.isPressed or chrome.isOpen:
    let alpha = base.scaledAlpha(1.0'f32)
    return linear(
      color(0.62, 0.84, 1.0, alpha),
      color(0.08, 0.48, 0.94, alpha),
      color(0.0, 0.25, 0.70, alpha),
      fgaY,
      104'u8,
    )
  let alpha = base.scaledAlpha(1.0'f32)
  linear(
    color(0.50, 0.90, 1.0, alpha),
    color(0.15, 0.67, 0.98, alpha),
    color(0.0, 0.44, 0.88, alpha),
    fgaY,
    104'u8,
  )

func aquaComboSeparatorFill(chrome: ChromeContext): Fill =
  if not chrome.isEnabled:
    return fill(color(0.50, 0.54, 0.58, 0.52))
  linear(color(0.0, 0.34, 0.78, 0.72), color(0.0, 0.18, 0.52, 0.88), fgaY)

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
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    return linear(
      base.lightenColor(0.18'f32, base.scaledAlpha(0.88'f32)),
      base.darkenColor(0.02'f32, base.scaledAlpha(0.88'f32)),
      fgaY,
    )
  let alpha = base.scaledAlpha(1.0'f32)
  linear(base.lightenColor(0.88'f32, alpha), base.lightenColor(0.24'f32, alpha), fgaY)

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
      aquaButtonInnerShadows(chrome.baseFill, chrome.isEnabled),
      lightMaskContent = true,
    )
    topGloss = rect(
      inner.origin.x, inner.origin.y, inner.size.width, inner.size.height * 0.62'f32
    )
    lowerWash = rect(
      inner.origin.x,
      inner.origin.y + inner.size.height * 0.36'f32,
      inner.size.width,
      inner.size.height * 0.64'f32,
    )
    glowWidth = max(inner.size.width - 2.0'f32, 0.0'f32)
    topGlow =
      rect(inner.origin.x + 1.0'f32, inner.origin.y + 1.0'f32, glowWidth, 1.0'f32)
    waistGlow = rect(
      inner.origin.x + 1.0'f32,
      inner.origin.y + inner.size.height * 0.50'f32,
      glowWidth,
      1.0'f32,
    )
  discard context.addRenderRectangle(
    extras.layer,
    innerRoot,
    topGlow,
    transparentFill(),
    shadows = [
      dropShadow(
        color(1.0, 1.0, 1.0, if chrome.isEnabled: 0.22 else: 0.08), y = 0.8, blur = 3.0
      )
    ],
  )
  discard context.addRenderRectangle(
    extras.layer,
    innerRoot,
    topGloss,
    context.appearance.chromeFill(chrome.withPart(cpGloss)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    innerRadius,
  )
  discard context.addRenderRectangle(
    extras.layer,
    innerRoot,
    lowerWash,
    context.appearance.chromeFill(chrome.withPart(cpLowerWash)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    innerRadius,
  )
  discard context.addRenderRectangle(
    extras.layer,
    innerRoot,
    waistGlow,
    transparentFill(),
    shadows = [
      dropShadow(
        color(1.0, 1.0, 1.0, if chrome.isEnabled: 0.08 else: 0.03), y = 0.5, blur = 4.0
      ),
      dropShadow(
        color(0.0, 0.0, 0.0, if chrome.isEnabled: 0.05 else: 0.02), y = 2.0, blur = 5.0
      ),
    ],
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
    inset = if ssSelected in chrome.states: 1.2'f32 else: 1.4'f32
    gloss = rect(
      extras.rect.origin.x + inset,
      extras.rect.origin.y + inset,
      max(extras.rect.size.width - inset * 2.0'f32, 0.0'f32),
      max(extras.rect.size.height * 0.34'f32, 1.0'f32),
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
    max(extras.cornerRadius - inset, 1.0'f32),
  )

proc drawAquaComboFaceExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let
    gloss = rect(
      extras.rect.origin.x + 2.0'f32,
      extras.rect.origin.y + 1.0'f32,
      max(extras.rect.size.width - 4.0'f32, 0.0'f32),
      max(extras.rect.size.height * 0.32'f32, 1.0'f32),
    )
    lowerWash = rect(
      extras.rect.origin.x,
      extras.rect.origin.y + extras.rect.size.height * 0.48'f32,
      extras.rect.size.width,
      extras.rect.size.height * 0.52'f32,
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
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    lowerWash,
    context.appearance.chromeFill(chrome.withPart(cpLowerWash)),
  )

proc drawAquaComboArrowExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let gloss = rect(
    extras.rect.origin.x + 2.0'f32,
    extras.rect.origin.y + 1.0'f32,
    max(extras.rect.size.width - 4.0'f32, 0.0'f32),
    max(extras.rect.size.height * 0.26'f32, 1.0'f32),
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
      extras.rect.origin.x + 2.0'f32,
      extras.rect.origin.y + 1.0'f32,
      max(extras.rect.size.width - 4.0'f32, 0.0'f32),
      1.0'f32,
    )
    bottomShade = rect(
      extras.rect.origin.x + 1.0'f32,
      extras.rect.maxY - 2.0'f32,
      max(extras.rect.size.width - 2.0'f32, 0.0'f32),
      1.0'f32,
    )
  discard context.addRenderRectangle(
    extras.layer, extras.parent, topHighlight, fill(color(1.0, 1.0, 1.0, 0.62))
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

protocol AquaChromeProtocol of ChromeProtocol:
  method chromeFillFor(chrome: AquaChrome, context: ChromeContext): Fill =
    case context.role
    of crButton:
      case context.part
      of cpInnerFace:
        aquaButtonFaceFill(context.baseFill, context.isEnabled)
      of cpGloss:
        aquaButtonGlossFill(context.isEnabled)
      of cpLowerWash:
        aquaButtonLowerWash(context.baseFill, context.isEnabled)
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
    else:
      context.baseFill

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
    else:
      discard

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
