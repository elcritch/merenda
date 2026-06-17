from figdraw/fignodes import FigIdx

import ./drawing
import ./theme
import ./types

type
  ChromeRole* = enum
    crButton
    crChoiceIndicator
    crTab
    crTabPanel

  ChromePart* = enum
    cpFace
    cpInnerFace
    cpGloss
    cpLowerWash
    cpHighlight
    cpSeam

  ChromeEdge* = enum
    ceNone
    ceTop
    ceBottom

  ChromeContext* = object
    name*: string
    role*: ChromeRole
    part*: ChromePart
    states*: set[WidgetState]
    baseFill*: Fill

  ChromeExtras* = object
    parent*: FigIdx
    rect*: Rect
    cornerRadius*: float32
    edge*: ChromeEdge
    seamFill*: Fill
    highlightFill*: Fill

const AquaButtonInset = 2.5'f32

func transparentFill(): Fill =
  fill(initColor(0.0, 0.0, 0.0, 0.0))

func chromeContext*(
    name: string,
    role: ChromeRole,
    part: ChromePart,
    baseFill: Fill,
    states: set[WidgetState] = {},
): ChromeContext =
  ChromeContext(name: name, role: role, part: part, states: states, baseFill: baseFill)

func initChromeExtras*(
    parent: FigIdx,
    rect: Rect,
    cornerRadius = 0.0'f32,
    edge = ceNone,
    seamFill = transparentFill(),
    highlightFill = transparentFill(),
): ChromeExtras =
  ChromeExtras(
    parent: parent,
    rect: rect,
    cornerRadius: cornerRadius,
    edge: edge,
    seamFill: seamFill,
    highlightFill: highlightFill,
  )

func withPart(chrome: ChromeContext, part: ChromePart): ChromeContext =
  result = chrome
  result.part = part

func withPart(chrome: ChromeContext, part: ChromePart, baseFill: Fill): ChromeContext =
  result = chrome
  result.part = part
  result.baseFill = baseFill

func isAqua(chrome: ChromeContext): bool =
  chrome.name == AquaChromeName

func isEnabled(chrome: ChromeContext): bool =
  ssDisabled notin chrome.states

func isPressed(chrome: ChromeContext): bool =
  ssHighlighted in chrome.states or ssPressed in chrome.states

func clampUnit(value: float32): float32 =
  min(max(value, 0.0'f32), 1.0'f32)

func lightenColor(color: Color, amount: float32, alpha: float32): Color =
  let mix = amount.clampUnit
  initColor(
    color.r + (1.0'f32 - color.r) * mix,
    color.g + (1.0'f32 - color.g) * mix,
    color.b + (1.0'f32 - color.b) * mix,
    alpha.clampUnit,
  )

func darkenColor(color: Color, amount: float32, alpha: float32): Color =
  let mix = 1.0'f32 - amount.clampUnit
  initColor(color.r * mix, color.g * mix, color.b * mix, alpha.clampUnit)

func colorSaturation(color: Color): float32 =
  let
    high = max(max(color.r, color.g), color.b)
    low = min(min(color.r, color.g), color.b)
  high - low

func aquaButtonFaceFill(fillValue: Fill, enabled: bool): Fill =
  let
    base = fillValue.centerColor()
    saturated = base.colorSaturation() > 0.18'f32
    topMix = if saturated: 0.58'f32 else: 0.82'f32
    bottomMix = if saturated: 0.14'f32 else: 0.46'f32
    alpha = if enabled: 0.92'f32 else: 0.58'f32
  linear(base.lightenColor(topMix, alpha), base.lightenColor(bottomMix, alpha), fgaY)

func aquaButtonLowerWash(fillValue: Fill, enabled: bool): Fill =
  let
    base = fillValue.centerColor()
    saturated = base.colorSaturation() > 0.18'f32
    alpha =
      if not enabled:
        0.10'f32
      elif saturated:
        0.28'f32
      else:
        0.22'f32
    tint =
      if saturated:
        base.lightenColor(0.10'f32, alpha)
      else:
        base.darkenColor(0.15'f32, alpha)
  linear(initColor(1.0, 1.0, 1.0, 0.0), tint, fgaY)

func aquaButtonGlossFill(enabled: bool): Fill =
  let alpha = if enabled: 0.62'f32 else: 0.24'f32
  linear(initColor(1.0, 1.0, 1.0, alpha), initColor(1.0, 1.0, 1.0, 0.0), fgaY)

func aquaButtonInnerShadows(fillValue: Fill, enabled: bool): seq[BoxShadow] =
  let
    base = fillValue.centerColor()
    saturated = base.colorSaturation() > 0.18'f32
    darkAlpha =
      if not enabled:
        0.08'f32
      elif saturated:
        0.16'f32
      else:
        0.10'f32
  @[
    insetShadow(
      initColor(1.0, 1.0, 1.0, if enabled: 0.38 else: 0.14), y = 2.0, blur = 7.0
    ),
    insetShadow(initColor(0.0, 0.0, 0.0, darkAlpha), y = -2.0, blur = 7.0),
  ]

func aquaTabFaceFill(chrome: ChromeContext): Fill =
  let base = chrome.baseFill.centerColor()
  if not chrome.isEnabled:
    linear(
      base.lightenColor(0.24'f32, 0.95'f32), base.darkenColor(0.04'f32, 0.95'f32), fgaY
    )
  elif ssSelected in chrome.states:
    linear(
      base.lightenColor(0.70'f32, 1.0'f32),
      base.lightenColor(0.32'f32, 1.0'f32),
      base,
      fgaY,
      96'u8,
    )
  elif chrome.isPressed:
    linear(
      base.lightenColor(0.12'f32, 1.0'f32), base.darkenColor(0.18'f32, 1.0'f32), fgaY
    )
  else:
    linear(
      base.lightenColor(0.36'f32, 1.0'f32), base.darkenColor(0.16'f32, 1.0'f32), fgaY
    )

func chromeFill*(chrome: ChromeContext): Fill =
  if not chrome.isAqua:
    return chrome.baseFill

  case chrome.role
  of crButton:
    case chrome.part
    of cpInnerFace:
      aquaButtonFaceFill(chrome.baseFill, chrome.isEnabled)
    of cpGloss:
      aquaButtonGlossFill(chrome.isEnabled)
    of cpLowerWash:
      aquaButtonLowerWash(chrome.baseFill, chrome.isEnabled)
    else:
      chrome.baseFill
  of crTab:
    case chrome.part
    of cpFace:
      aquaTabFaceFill(chrome)
    of cpHighlight:
      chrome.baseFill
    of cpSeam:
      chrome.baseFill
    else:
      chrome.baseFill
  else:
    chrome.baseFill

func chromeEdgeHighlightRect(edge: ChromeEdge, rect: Rect): Rect =
  case edge
  of ceTop:
    initRect(
      rect.origin.x + 4.0'f32,
      rect.origin.y + 1.0'f32,
      max(rect.size.width - 8.0'f32, 0.0'f32),
      1.0'f32,
    )
  of ceBottom:
    initRect(
      rect.origin.x + 4.0'f32,
      rect.maxY - 2.0'f32,
      max(rect.size.width - 8.0'f32, 0.0'f32),
      1.0'f32,
    )
  of ceNone:
    initRect(rect.origin.x, rect.origin.y, 0.0'f32, 0.0'f32)

func chromeEdgeSeamRect(edge: ChromeEdge, rect: Rect): Rect =
  case edge
  of ceTop:
    initRect(
      rect.origin.x + 1.0'f32,
      rect.maxY - 1.0'f32,
      max(rect.size.width - 2.0'f32, 0.0'f32),
      2.0'f32,
    )
  of ceBottom:
    initRect(
      rect.origin.x + 1.0'f32,
      rect.origin.y,
      max(rect.size.width - 2.0'f32, 0.0'f32),
      2.0'f32,
    )
  of ceNone:
    initRect(rect.origin.x, rect.origin.y, 0.0'f32, 0.0'f32)

proc drawAquaButtonExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  let
    radius = extras.cornerRadius
    inner = extras.rect.inset(initEdgeInsets(AquaButtonInset))
  if inner.isEmpty:
    return

  let
    innerChrome = chrome.withPart(cpInnerFace)
    innerRadius = max(radius - AquaButtonInset, 1.0'f32)
    innerRoot = context.addRenderRectangle(
      extras.parent,
      inner,
      innerChrome.chromeFill(),
      initColor(0.0, 0.0, 0.0, 0.0),
      0.0'f32,
      innerRadius,
      aquaButtonInnerShadows(chrome.baseFill, chrome.isEnabled),
      maskContent = true,
    )
    topGloss = initRect(
      inner.origin.x - 4.0'f32,
      inner.origin.y,
      inner.size.width + 8.0'f32,
      inner.size.height * 0.62'f32,
    )
    lowerWash = initRect(
      inner.origin.x - 4.0'f32,
      inner.origin.y + inner.size.height * 0.36'f32,
      inner.size.width + 8.0'f32,
      inner.size.height * 0.64'f32,
    )
    topGlow = initRect(
      inner.origin.x - 8.0'f32,
      inner.origin.y + 1.0'f32,
      inner.size.width + 16.0'f32,
      1.0'f32,
    )
    waistGlow = initRect(
      inner.origin.x - 8.0'f32,
      inner.origin.y + inner.size.height * 0.49'f32,
      inner.size.width + 16.0'f32,
      1.0'f32,
    )

  discard context.addRenderRectangle(
    innerRoot,
    topGlow,
    transparentFill(),
    shadows = [
      dropShadow(
        initColor(1.0, 1.0, 1.0, if chrome.isEnabled: 0.46 else: 0.16),
        y = 1.2,
        blur = 5.0,
      )
    ],
  )
  discard context.addRenderRectangle(
    innerRoot, topGloss, chrome.withPart(cpGloss).chromeFill()
  )
  discard context.addRenderRectangle(
    innerRoot, lowerWash, chrome.withPart(cpLowerWash).chromeFill()
  )
  discard context.addRenderRectangle(
    innerRoot,
    waistGlow,
    transparentFill(),
    shadows = [
      dropShadow(
        initColor(1.0, 1.0, 1.0, if chrome.isEnabled: 0.16 else: 0.06),
        y = 0.8,
        blur = 7.0,
      ),
      dropShadow(
        initColor(0.0, 0.0, 0.0, if chrome.isEnabled: 0.08 else: 0.03),
        y = 4.0,
        blur = 8.0,
      ),
    ],
  )

proc drawAquaTabExtras(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  if extras.edge == ceNone:
    return

  discard context.addRenderRectangle(
    extras.parent,
    chromeEdgeHighlightRect(extras.edge, extras.rect),
    chrome.withPart(cpHighlight, extras.highlightFill).chromeFill(),
  )
  if ssSelected in chrome.states:
    discard context.addRenderRectangle(
      extras.parent,
      chromeEdgeSeamRect(extras.edge, extras.rect),
      chrome.withPart(cpSeam, extras.seamFill).chromeFill(),
    )

proc drawChromeExtras*(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  if not chrome.isAqua:
    return

  case chrome.role
  of crButton:
    if chrome.part == cpFace:
      context.drawAquaButtonExtras(chrome, extras)
  of crTab:
    if chrome.part == cpFace:
      context.drawAquaTabExtras(chrome, extras)
  else:
    discard
