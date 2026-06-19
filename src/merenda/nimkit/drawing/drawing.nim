import pkg/bumpy

import figdraw/commons
import figdraw/common/filltypes
import figdraw/common/typefaces
import figdraw/fignodes

import ./images
import ./theme
import ../text/textstorage
import ../text/texttypes
import ../foundation/types as nimkitTypes

export filltypes
export images

const
  DefaultDrawLevel* = 50.ZLevel
  PopupDrawLevel* = 100.ZLevel

type DrawContext* = ref object
  xRenders: Renders
  xParent: FigIdx
  xViewParent: FigIdx
  xRenderOrigin: nimkitTypes.Point
  xBounds: nimkitTypes.Rect
  xVisibleRect: nimkitTypes.Rect
  xAppearance: Appearance

var defaultTypefaceId {.threadvar.}: TypefaceId
var defaultTypefaceReady {.threadvar.}: bool

proc toFigRect(rect: nimkitTypes.Rect): bumpy.Rect =
  bumpy.rect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)

proc defaultFont(size: float32): FigFont =
  if not defaultTypefaceReady:
    defaultTypefaceId = loadTypeface(
      "IBMPlexSans-Regular.ttf", ["Ubuntu.ttf", "HackNerdFont-Regular.ttf"]
    )
    defaultTypefaceReady = true
  defaultTypefaceId.fontWithSize(size)

const AllCorners = {dcTopLeft, dcTopRight, dcBottomLeft, dcBottomRight}

proc cornerRadii(
    radius: float32, roundedCorners: set[DirectionCorners] = AllCorners
): array[DirectionCorners, uint16] =
  let clamped = max(radius, 0.0'f32)
  for corner in DirectionCorners:
    if corner in roundedCorners:
      result[corner] = clamped.round().uint16

proc toFigShadow(shadow: BoxShadow): RenderShadow =
  RenderShadow(
    style: if shadow.kind == bskInset: InnerShadow else: DropShadow,
    fill: fill(shadow.color.rgba),
    blur: shadow.blur,
    spread: shadow.spread,
    x: shadow.x,
    y: shadow.y,
  )

proc rectangleNode(
    rect: nimkitTypes.Rect,
    fillValue: Fill,
    strokeColor = initColor(0.0, 0.0, 0.0, 0.0),
    strokeWidth = 0.0'f32,
    cornerRadius = 0.0'f32,
    shadows: openArray[BoxShadow] = [],
    clips = false,
    maskContent = false,
    roundedCorners: set[DirectionCorners] = AllCorners,
): Fig =
  result = Fig(
    kind: nkRectangle,
    screenBox: rect.toFigRect,
    fill: fillValue,
    corners: cornerRadii(cornerRadius, roundedCorners),
    stroke: RenderStroke(weight: strokeWidth, fill: fill(strokeColor.rgba)),
  )
  if maskContent:
    result.flags.incl NfRectMaskContent
  elif clips:
    result.flags.incl NfClipContent
  for idx in 0 ..< min(shadows.len, result.shadows.len):
    result.shadows[idx] = shadows[idx].toFigShadow()

proc translationNode(rect: nimkitTypes.Rect, translation: nimkitTypes.Point): Fig =
  Fig(
    kind: nkTransform,
    screenBox: rect.toFigRect,
    transform: TransformStyle(translation: vec2(translation.x, translation.y)),
  )

proc toFontHorizontal(alignment: TextAlignment): FontHorizontal =
  case alignment
  of taLeft: Left
  of taCenter: Center
  of taRight: Right

proc textLayout*(
    rect: nimkitTypes.Rect, text: string, color: nimkitTypes.Color, alignment = taLeft
): GlyphArrangement =
  let
    font = defaultFont(DefaultFontSize)
    style = fs(font, fill(color.rgba))
  typeset(
    rect.toFigRect,
    [(style, text)],
    hAlign = alignment.toFontHorizontal,
    vAlign = Middle,
    minContent = false,
    wrap = false,
  )

proc textLayout*(
    rect: nimkitTypes.Rect, storage: TextStorage, alignment = taLeft, wrap = false
): GlyphArrangement =
  var spans: seq[(FontStyle, string)]
  if storage.isNil or storage.len == 0:
    let attributes = defaultTextAttributes()
    var font = defaultFont(attributes.fontSize)
    font.underline = attributes.underline
    font.strikethrough = attributes.strikethrough
    spans.add((fs(font, fill(attributes.foregroundColor.rgba)), ""))
  else:
    for (attributes, text) in storage.styledRuns:
      var font = defaultFont(attributes.fontSize)
      font.underline = attributes.underline
      font.strikethrough = attributes.strikethrough
      spans.add((fs(font, fill(attributes.foregroundColor.rgba)), text))
  typeset(
    rect.toFigRect,
    spans,
    hAlign = alignment.toFontHorizontal,
    vAlign = Middle,
    minContent = false,
    wrap = wrap,
  )

proc textNaturalSize*(text: string): nimkitTypes.Size =
  let
    font = defaultFont(DefaultFontSize)
    style = fs(font, fill(initColor(0.0, 0.0, 0.0, 1.0).rgba))
    lineHeight = max(DefaultFontSize, getLineHeightImpl(font))
    layout = typeset(
      bumpy.rect(0.0, 0.0, 10000.0, max(lineHeight, 100.0'f32)),
      [(style, text)],
      hAlign = Left,
      vAlign = Top,
      minContent = false,
      wrap = false,
    )
  initSize(max(layout.bounding.w, layout.maxSize.x), lineHeight)

proc textNode(
    rect: nimkitTypes.Rect, text: string, color: nimkitTypes.Color, alignment = taLeft
): Fig =
  Fig(
    kind: nkText,
    screenBox: rect.toFigRect,
    textLayout: textLayout(rect, text, color, alignment),
  )

proc textNode(rect: nimkitTypes.Rect, layout: GlyphArrangement): Fig =
  Fig(kind: nkText, screenBox: rect.toFigRect, textLayout: layout)

proc imageNode(rect: nimkitTypes.Rect, image: ImageResource, fillValue: Fill): Fig =
  Fig(
    kind: nkImage,
    screenBox: rect.toFigRect,
    image: ImageStyle(id: image.imageId(), fill: fillValue),
  )

proc selectTextNode(
    node: var Fig, selectedLocation, selectedLength: int, color: nimkitTypes.Color
) =
  let count = node.textLayout.selectionRects.len
  if selectedLength == 0 or count == 0:
    return

  let
    first = min(max(selectedLocation, 0), count)
    last = min(first + max(selectedLength, 0), count)
  if first >= last or first > high(int16).int:
    return

  node.flags.incl NfSelectText
  node.fill = fill(color.rgba)
  node.selectionRange = first.int16 .. min(last - 1, high(int16).int).int16

proc caretRect*(
    textRect: nimkitTypes.Rect, layout: GlyphArrangement, insertionPoint: int
): nimkitTypes.Rect =
  let index = max(insertionPoint, 0)
  if layout.selectionRects.len > 0:
    let rect =
      if index <= 0:
        layout.selectionRects[0]
      else:
        layout.selectionRects[min(index - 1, layout.selectionRects.high)]
    let x =
      if index <= 0:
        rect.x
      else:
        min(rect.x + rect.w, textRect.size.width - 1.0'f32)
    return initRect(textRect.origin.x + x, textRect.origin.y + rect.y, 1.0, rect.h)

  let
    font = defaultFont(DefaultFontSize)
    lineHeight = max(DefaultFontSize, getLineHeightImpl(font))
  initRect(
    textRect.origin.x,
    textRect.origin.y + max((textRect.size.height - lineHeight) / 2.0'f32, 0.0),
    1.0,
    min(lineHeight, textRect.size.height),
  )

proc initDrawContext*(): DrawContext =
  result =
    DrawContext(xRenders: Renders(layers: initOrderedTable[ZLevel, RenderList]()))
  result.xRenders.layers[DefaultDrawLevel] = RenderList()

proc beginDraw*(
    context: DrawContext,
    parent: FigIdx,
    viewParent: FigIdx,
    renderOrigin: nimkitTypes.Point,
    bounds: nimkitTypes.Rect,
    visibleRect: nimkitTypes.Rect,
    appearance: Appearance,
) =
  context.xParent = parent
  context.xViewParent = viewParent
  context.xRenderOrigin = renderOrigin
  context.xBounds = bounds
  context.xVisibleRect = visibleRect
  context.xAppearance = appearance

proc renderList*(context: DrawContext): RenderList =
  if DefaultDrawLevel in context.xRenders.layers:
    return context.xRenders.layers[DefaultDrawLevel]
  RenderList()

proc renders*(context: DrawContext): Renders =
  context.xRenders

proc appearance*(context: DrawContext): Appearance =
  context.xAppearance

proc renderRectFor*(context: DrawContext, rect: nimkitTypes.Rect): nimkitTypes.Rect =
  nimkitTypes.initRect(
    context.xRenderOrigin.x + rect.origin.x,
    context.xRenderOrigin.y + rect.origin.y,
    rect.size.width,
    rect.size.height,
  )

proc bounds*(context: DrawContext): nimkitTypes.Rect =
  context.xBounds

proc visibleRect*(context: DrawContext): nimkitTypes.Rect =
  context.xVisibleRect

proc addFig*(
    context: DrawContext, layer: ZLevel, parent: FigIdx, node: Fig
): FigIdx {.discardable.} =
  if parent == (-1).FigIdx:
    context.xRenders.addRoot(layer, node)
  else:
    context.xRenders.addChild(layer, parent, node)

proc addFig*(context: DrawContext, parent: FigIdx, node: Fig): FigIdx {.discardable.} =
  context.addFig(DefaultDrawLevel, parent, node)

proc addFig*(context: DrawContext, node: Fig): FigIdx {.discardable.} =
  context.addFig(context.xParent, node)

proc addRenderRectangle*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    fillValue: Fill,
    strokeColor = initColor(0.0, 0.0, 0.0, 0.0),
    strokeWidth = 0.0'f32,
    cornerRadius = 0.0'f32,
    shadows: openArray[BoxShadow] = [],
    clips = false,
    maskContent = false,
    roundedCorners: set[DirectionCorners] = AllCorners,
): FigIdx {.discardable.} =
  context.addFig(
    layer,
    parent,
    rectangleNode(
      rect, fillValue, strokeColor, strokeWidth, cornerRadius, shadows, clips,
      maskContent, roundedCorners,
    ),
  )

proc addRenderRectangle*(
    context: DrawContext,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    fillValue: Fill,
    strokeColor = initColor(0.0, 0.0, 0.0, 0.0),
    strokeWidth = 0.0'f32,
    cornerRadius = 0.0'f32,
    shadows: openArray[BoxShadow] = [],
    clips = false,
    maskContent = false,
    roundedCorners: set[DirectionCorners] = AllCorners,
): FigIdx {.discardable.} =
  context.addRenderRectangle(
    DefaultDrawLevel, parent, rect, fillValue, strokeColor, strokeWidth, cornerRadius,
    shadows, clips, maskContent, roundedCorners,
  )

proc addRenderRectangle*(
    context: DrawContext,
    rect: nimkitTypes.Rect,
    fillValue: Fill,
    strokeColor = initColor(0.0, 0.0, 0.0, 0.0),
    strokeWidth = 0.0'f32,
    cornerRadius = 0.0'f32,
    shadows: openArray[BoxShadow] = [],
    clips = false,
    maskContent = false,
    roundedCorners: set[DirectionCorners] = AllCorners,
): FigIdx {.discardable.} =
  context.addRenderRectangle(
    context.xParent, rect, fillValue, strokeColor, strokeWidth, cornerRadius, shadows,
    clips, maskContent, roundedCorners,
  )

proc addRenderTranslation*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    translation: nimkitTypes.Point,
): FigIdx {.discardable.} =
  context.addFig(layer, parent, translationNode(rect, translation))

proc addRenderTranslation*(
    context: DrawContext,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    translation: nimkitTypes.Point,
): FigIdx {.discardable.} =
  context.addRenderTranslation(DefaultDrawLevel, parent, rect, translation)

proc addRectangle*(
    context: DrawContext, rect: nimkitTypes.Rect, fillValue: Fill
): FigIdx {.discardable.} =
  context.addFig(rectangleNode(context.renderRectFor(rect), fillValue))

proc addText*(
    context: DrawContext,
    rect: nimkitTypes.Rect,
    text: string,
    color: nimkitTypes.Color,
    alignment = taLeft,
): FigIdx {.discardable.} =
  context.addFig(textNode(context.renderRectFor(rect), text, color, alignment))

proc addText*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    text: string,
    color: nimkitTypes.Color,
    alignment = taLeft,
): FigIdx {.discardable.} =
  context.addFig(
    layer, parent, textNode(context.renderRectFor(rect), text, color, alignment)
  )

proc addText*(
    context: DrawContext, rect: nimkitTypes.Rect, layout: GlyphArrangement
): FigIdx {.discardable.} =
  context.addFig(textNode(context.renderRectFor(rect), layout))

proc addImage*(
    context: DrawContext,
    rect: nimkitTypes.Rect,
    image: ImageResource,
    tint = initColor(1.0, 1.0, 1.0, 1.0),
): FigIdx {.discardable.} =
  if image.isNil:
    return (-1).FigIdx
  context.addFig(imageNode(context.renderRectFor(rect), image, fill(tint.rgba)))

proc addImage*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    image: ImageResource,
    tint = initColor(1.0, 1.0, 1.0, 1.0),
): FigIdx {.discardable.} =
  if image.isNil:
    return (-1).FigIdx
  context.addFig(
    layer, parent, imageNode(context.renderRectFor(rect), image, fill(tint.rgba))
  )

proc addSelectedText*(
    context: DrawContext,
    rect: nimkitTypes.Rect,
    layout: GlyphArrangement,
    selectedLocation, selectedLength: int,
    selectionColor: nimkitTypes.Color,
): FigIdx {.discardable.} =
  var node = textNode(context.renderRectFor(rect), layout)
  node.selectTextNode(selectedLocation, selectedLength, selectionColor)
  context.addFig(node)

proc addFocusRing*(context: DrawContext, rect: nimkitTypes.Rect, box: ControlBoxStyle) =
  if box.focusRingWidth <= 0.0'f32:
    return
  let ringRect = rect.inset(initEdgeInsets(box.focusRingInset))
  if ringRect.isEmpty:
    return
  let parent =
    if box.focusRingInset < 0.0'f32: context.xViewParent else: context.xParent
  discard context.addRenderRectangle(
    parent,
    ringRect,
    initColor(0.0, 0.0, 0.0, 0.0),
    box.focusRingColor,
    box.focusRingWidth,
    max(box.cornerRadius - box.focusRingInset, 0.0'f32),
  )

proc addComboBoxArrow*(
    context: DrawContext,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    color: nimkitTypes.Color,
) =
  if rect.size.width <= 0.0'f32 or rect.size.height <= 0.0'f32:
    return
  let
    width = max(min(rect.size.width * 0.32'f32, 7.0'f32), 4.0'f32)
    centerX = rect.origin.x + rect.size.width * 0.5'f32
    centerY = rect.origin.y + rect.size.height * 0.5'f32
    topY = centerY - 1.0'f32
  discard context.addRenderRectangle(
    parent, initRect(centerX - width * 0.50'f32, topY, width, 1.0'f32), color
  )
  discard context.addRenderRectangle(
    parent,
    initRect(centerX - width * 0.35'f32, topY + 1.0'f32, width * 0.70'f32, 1.0'f32),
    color,
  )
  discard context.addRenderRectangle(
    parent,
    initRect(centerX - width * 0.20'f32, topY + 2.0'f32, width * 0.40'f32, 1.0'f32),
    color,
  )

proc addComboBoxArrow*(
    context: DrawContext, rect: nimkitTypes.Rect, color: nimkitTypes.Color
) =
  context.addComboBoxArrow(context.xParent, rect, color)

proc addComboBoxDoubleArrow*(
    context: DrawContext,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    color: nimkitTypes.Color,
) =
  if rect.size.width <= 0.0'f32 or rect.size.height <= 0.0'f32:
    return
  let
    width = max(min(rect.size.width * 0.28'f32, 6.0'f32), 4.0'f32)
    centerX = rect.origin.x + rect.size.width * 0.5'f32
    centerY = rect.origin.y + rect.size.height * 0.5'f32
    upY = centerY - 5.0'f32
    downY = centerY + 2.0'f32
  discard context.addRenderRectangle(
    parent, initRect(centerX - width * 0.20'f32, upY, width * 0.40'f32, 1.0'f32), color
  )
  discard context.addRenderRectangle(
    parent,
    initRect(centerX - width * 0.35'f32, upY + 1.0'f32, width * 0.70'f32, 1.0'f32),
    color,
  )
  discard context.addRenderRectangle(
    parent, initRect(centerX - width * 0.50'f32, upY + 2.0'f32, width, 1.0'f32), color
  )
  discard context.addRenderRectangle(
    parent, initRect(centerX - width * 0.50'f32, downY, width, 1.0'f32), color
  )
  discard context.addRenderRectangle(
    parent,
    initRect(centerX - width * 0.35'f32, downY + 1.0'f32, width * 0.70'f32, 1.0'f32),
    color,
  )
  discard context.addRenderRectangle(
    parent,
    initRect(centerX - width * 0.20'f32, downY + 2.0'f32, width * 0.40'f32, 1.0'f32),
    color,
  )
