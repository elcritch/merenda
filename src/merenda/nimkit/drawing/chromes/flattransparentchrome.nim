import sigils/core
import sigils/selectors

import ../../foundation/types
import ../../themes
import ../chrome
import ../drawing

const FlatInset = 1.6'f32

type FlatTransparentChrome = ref object of Chrome

var fallbackFlatTransparentChrome: Chrome

func withPart(chrome: ChromeContext, part: ChromePart): ChromeContext =
  result = chrome
  result.part = part

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

func flatFaceFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    return linear(
      base.lightenColor(0.08'f32, 0.42'f32), base.darkenColor(0.14'f32, 0.42'f32), fgaY
    )
  if chrome.isPressed or chrome.isOpen:
    return linear(
      base.lightenColor(0.30'f32, 0.88'f32),
      base.lightenColor(0.04'f32, 0.82'f32),
      base.darkenColor(0.24'f32, 0.88'f32),
      fgaY,
      104'u8,
    )
  linear(
    base.lightenColor(0.20'f32, 0.84'f32),
    base.lightenColor(0.02'f32, 0.78'f32),
    base.darkenColor(0.18'f32, 0.84'f32),
    fgaY,
    96'u8,
  )

func flatButtonInnerFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    return linear(
      base.lightenColor(0.08'f32, 0.46'f32), base.darkenColor(0.12'f32, 0.46'f32), fgaY
    )
  if chrome.isPressed:
    return linear(
      base.lightenColor(0.22'f32, 0.86'f32),
      base.lightenColor(0.00'f32, 0.82'f32),
      base.darkenColor(0.26'f32, 0.88'f32),
      fgaY,
      112'u8,
    )
  linear(
    base.lightenColor(0.28'f32, 0.82'f32),
    base.lightenColor(0.04'f32, 0.76'f32),
    base.darkenColor(0.20'f32, 0.84'f32),
    fgaY,
    112'u8,
  )

func flatGlossFill(chrome: ChromeContext): Fill =
  let alpha =
    if not chrome.isEnabled:
      0.06'f32
    elif chrome.isPressed or chrome.isOpen:
      0.16'f32
    else:
      0.20'f32
  linear(color(1.0, 1.0, 1.0, alpha), color(1.0, 1.0, 1.0, 0.0), fgaY)

func flatLowerWashFill(chrome: ChromeContext): Fill =
  let
    base = chrome.baseFill.centerColor()
    alpha =
      if not chrome.isEnabled:
        0.04'f32
      elif chrome.isPressed or chrome.isOpen:
        0.10'f32
      else:
        0.07'f32
  linear(color(1.0, 1.0, 1.0, 0.0), base.darkenColor(0.26'f32, alpha), fgaY)

func flatRadioShellFill(chrome: ChromeContext): Fill =
  flatFaceFill(chrome)

func flatRadioInnerFill(chrome: ChromeContext): Fill =
  if chrome.isSelected:
    return chrome.baseFill
  let base = chrome.baseFill.centerColor()
  if chrome.isEnabled:
    return linear(
      base.lightenColor(0.30'f32, 0.86'f32),
      base.lightenColor(0.08'f32, 0.76'f32),
      base.darkenColor(0.14'f32, 0.84'f32),
      fgaY,
      104'u8,
    )
  linear(
    base.lightenColor(0.08'f32, 0.42'f32), base.darkenColor(0.10'f32, 0.42'f32), fgaY
  )

func flatRadioInnerBorderColor(chrome: ChromeContext): Color =
  if chrome.isSelected and chrome.isEnabled:
    return color(1.0, 0.30, 0.92, 0.88)
  if chrome.isEnabled:
    return color(0.24, 0.94, 1.0, 0.72)
  color(0.36, 0.42, 0.58, 0.40)

func flatRadioInnerShadows(chrome: ChromeContext): seq[BoxShadow] =
  if chrome.isSelected and chrome.isEnabled:
    return
      @[
        insetShadow(color(0.0, 0.0, 0.0, 0.26), y = 1.0, blur = 2.8),
        insetShadow(color(0.30, 0.96, 1.0, 0.20), y = -1.0, blur = 2.6),
      ]
  @[
    insetShadow(
      color(0.0, 0.0, 0.0, if chrome.isEnabled: 0.18 else: 0.06), y = 1.0, blur = 2.4
    ),
    insetShadow(
      color(0.28, 0.96, 1.0, if chrome.isEnabled: 0.16 else: 0.06), y = -1.0, blur = 2.0
    ),
  ]

func flatComboArrowFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    return linear(
      base.lightenColor(0.10'f32, 0.44'f32), base.darkenColor(0.18'f32, 0.44'f32), fgaY
    )
  if chrome.isPressed or chrome.isOpen:
    return linear(
      base.lightenColor(0.38'f32, 0.88'f32),
      base.lightenColor(0.08'f32, 0.84'f32),
      base.darkenColor(0.26'f32, 0.90'f32),
      fgaY,
      104'u8,
    )
  linear(
    base.lightenColor(0.26'f32, 0.84'f32),
    base.lightenColor(0.04'f32, 0.78'f32),
    base.darkenColor(0.22'f32, 0.86'f32),
    fgaY,
    104'u8,
  )

func flatComboSeparatorFill(chrome: ChromeContext): Fill =
  if not chrome.isEnabled:
    return fill(color(0.36, 0.42, 0.58, 0.34))
  linear(color(0.18, 0.92, 1.0, 0.44), color(1.0, 0.08, 0.92, 0.36), fgaY)

func flatSliderHighlightFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    return linear(
      base.lightenColor(0.18'f32, 0.34'f32), base.darkenColor(0.08'f32, 0.34'f32), fgaY
    )
  linear(
    base.lightenColor(0.40'f32, 0.90'f32),
    base.lightenColor(0.08'f32, 0.84'f32),
    base.darkenColor(0.12'f32, 0.86'f32),
    fgaY,
    106'u8,
  )

proc drawFlatButtonExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let
    radius = extras.cornerRadius
    inner = extras.rect.inset(insets(FlatInset))
  if inner.isEmpty:
    return

  let
    innerChrome = chrome.withPart(cpInnerFace)
    innerRadius = max(radius - FlatInset, 0.0'f32)
    innerRadii = extras.cornerRadii.inset(FlatInset)
    innerRoot = context.addRenderRectangle(
      extras.layer,
      extras.parent,
      inner,
      context.appearance.chromeFill(innerChrome),
      color(0.0, 0.0, 0.0, 0.0),
      0.0'f32,
      innerRadius,
      [
        insetShadow(
          color(0.32, 0.96, 1.0, if chrome.isEnabled: 0.14 else: 0.04),
          y = 1.0,
          blur = 3.0,
        ),
        insetShadow(
          color(0.0, 0.0, 0.0, if chrome.isEnabled: 0.20 else: 0.06),
          y = -1.0,
          blur = 4.0,
        ),
      ],
      lightMaskContent = true,
      cornerRadii = innerRadii,
    )
    topGloss = rect(
      inner.origin.x, inner.origin.y, inner.size.width, inner.size.height * 0.30'f32
    )
    lowerWash = rect(
      inner.origin.x,
      inner.origin.y + inner.size.height * 0.46'f32,
      inner.size.width,
      inner.size.height * 0.54'f32,
    )
  discard context.addRenderRectangle(
    extras.layer,
    innerRoot,
    topGloss,
    context.appearance.chromeFill(chrome.withPart(cpGloss)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    innerRadius,
    cornerRadii = innerRadii,
  )
  discard context.addRenderRectangle(
    extras.layer,
    innerRoot,
    lowerWash,
    context.appearance.chromeFill(chrome.withPart(cpLowerWash)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    innerRadius,
    cornerRadii = innerRadii,
  )

proc drawFlatChoiceExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  if chrome.isRadioChoice:
    let
      innerInset = if chrome.isSelected: 1.6'f32 else: 2.0'f32
      inner = extras.rect.inset(insets(innerInset))
      innerRadius = max(min(inner.size.width, inner.size.height) / 2.0'f32, 1.0'f32)
    if inner.isEmpty:
      return
    let innerRoot = context.addRenderRectangle(
      extras.layer,
      extras.parent,
      inner,
      context.appearance.chromeFill(chrome.withPart(cpInnerFace)),
      flatRadioInnerBorderColor(chrome),
      0.5'f32,
      innerRadius,
      flatRadioInnerShadows(chrome),
      lightMaskContent = true,
    )
    let innerGloss = rect(
      inner.origin.x + 2.0'f32,
      inner.origin.y + 1.0'f32,
      max(inner.size.width - 4.0'f32, 0.0'f32),
      max(inner.size.height * 0.18'f32, 1.0'f32),
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
    inset = if chrome.isSelected: 1.2'f32 else: 1.4'f32
    glossRadii = extras.cornerRadii.inset(inset)
    gloss = rect(
      extras.rect.origin.x + inset,
      extras.rect.origin.y + inset,
      max(extras.rect.size.width - inset * 2.0'f32, 0.0'f32),
      max(extras.rect.size.height * 0.24'f32, 1.0'f32),
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
    max(extras.cornerRadius - inset, 0.0'f32),
    cornerRadii = glossRadii,
  )

proc drawFlatComboFaceExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let
    gloss = rect(
      extras.rect.origin.x + 2.0'f32,
      extras.rect.origin.y + 1.0'f32,
      max(extras.rect.size.width - 4.0'f32, 0.0'f32),
      max(extras.rect.size.height * 0.22'f32, 1.0'f32),
    )
    lowerWash = rect(
      extras.rect.origin.x,
      extras.rect.origin.y + extras.rect.size.height * 0.52'f32,
      extras.rect.size.width,
      extras.rect.size.height * 0.48'f32,
    )
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    gloss,
    context.appearance.chromeFill(chrome.withPart(cpGloss)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0'f32,
    max(extras.cornerRadius - 1.0'f32, 0.0'f32),
    cornerRadii = extras.cornerRadii.inset(1.0'f32),
  )
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    lowerWash,
    context.appearance.chromeFill(chrome.withPart(cpLowerWash)),
    cornerRadii = extras.cornerRadii,
  )

proc drawFlatComboArrowExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let gloss = rect(
    extras.rect.origin.x + 2.0'f32,
    extras.rect.origin.y + 1.0'f32,
    max(extras.rect.size.width - 4.0'f32, 0.0'f32),
    max(extras.rect.size.height * 0.20'f32, 1.0'f32),
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

proc drawFlatSimpleHighlight(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let topHighlight = rect(
    extras.rect.origin.x + 1.0'f32,
    extras.rect.origin.y + 1.0'f32,
    max(extras.rect.size.width - 2.0'f32, 0.0'f32),
    1.0'f32,
  )
  discard context.addRenderRectangle(
    extras.layer,
    extras.parent,
    topHighlight,
    fill(color(0.32, 0.96, 1.0, if chrome.isEnabled: 0.16 else: 0.05)),
  )

protocol FlatTransparentChromeProtocol of ChromeProtocol:
  method chromeFillFor(chrome: FlatTransparentChrome, context: ChromeContext): Fill =
    discard chrome
    case context.role
    of crButton, crDocumentTabButton:
      case context.part
      of cpInnerFace:
        flatButtonInnerFill(context)
      of cpGloss:
        flatGlossFill(context)
      of cpLowerWash:
        flatLowerWashFill(context)
      else:
        context.baseFill
    of crChoiceIndicator, crCheckBoxIndicator, crRadioIndicator:
      case context.part
      of cpFace:
        if context.isRadioChoice:
          flatRadioShellFill(context)
        else:
          context.baseFill
      of cpInnerFace:
        flatRadioInnerFill(context)
      of cpGloss:
        flatGlossFill(context)
      else:
        context.baseFill
    of crComboBox:
      case context.part
      of cpFace:
        flatFaceFill(context)
      of cpArrow:
        flatComboArrowFill(context)
      of cpSeparator:
        flatComboSeparatorFill(context)
      of cpGloss:
        flatGlossFill(context)
      of cpLowerWash:
        flatLowerWashFill(context)
      else:
        context.baseFill
    of crSliderTrack:
      case context.part
      of cpHighlight:
        flatSliderHighlightFill(context)
      else:
        flatFaceFill(context)
    of crSliderKnob:
      case context.part
      of cpGloss:
        flatGlossFill(context)
      of cpLowerWash:
        flatLowerWashFill(context)
      else:
        flatFaceFill(context)
    of crPopupList, crTab, crTabPanel, crDocumentTab, crDocumentTabBar:
      case context.part
      of cpGloss:
        flatGlossFill(context)
      of cpLowerWash:
        flatLowerWashFill(context)
      else:
        flatFaceFill(context)
    else:
      context.baseFill

  method drawChromeExtrasFor(
      chrome: FlatTransparentChrome,
      context: DrawContext,
      chromeContext: ChromeContext,
      extras: ChromeExtras,
  ) =
    discard chrome
    case chromeContext.role
    of crButton, crDocumentTabButton:
      if chromeContext.part == cpFace:
        context.drawFlatButtonExtras(chromeContext, extras)
    of crChoiceIndicator, crCheckBoxIndicator, crRadioIndicator:
      if chromeContext.part == cpFace:
        context.drawFlatChoiceExtras(chromeContext, extras)
    of crComboBox:
      case chromeContext.part
      of cpFace:
        context.drawFlatComboFaceExtras(chromeContext, extras)
      of cpArrow:
        context.drawFlatComboArrowExtras(chromeContext, extras)
      else:
        discard
    of crSliderTrack, crSliderKnob, crPopupList, crTab, crTabPanel, crDocumentTab,
        crDocumentTabBar:
      if chromeContext.part == cpFace:
        context.drawFlatSimpleHighlight(chromeContext, extras)
    else:
      discard

proc newFlatTransparentChrome*(): Chrome =
  let flat = FlatTransparentChrome()
  discard flat.withProtocol(FlatTransparentChromeProtocol)
  Chrome(flat)

proc flatTransparentChrome(): Chrome =
  if fallbackFlatTransparentChrome.isNil:
    fallbackFlatTransparentChrome = newFlatTransparentChrome()
  fallbackFlatTransparentChrome

proc installFlatTransparentChrome*(theme: var Theme) =
  theme.installChrome(FlatTransparentChromeName, flatTransparentChrome())

registerThemeInstaller(installFlatTransparentChrome)
