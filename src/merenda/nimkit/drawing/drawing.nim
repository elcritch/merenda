import std/[tables, unicode]

import pkg/bumpy

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw
  import figdraw/figextras
  from figdraw/common/typefaces import getLineHeightImpl

import ./images
import ./renderresources
import ../themes
import ../themes/themecore as themeCore
import ../text/textstorage
import ../text/texttypes
import ../foundation/types as nimkitTypes

when defined(useNativeDynlib):
  export
    dynlib.FillGradientAxis, dynlib.FillKind, dynlib.Linear2, dynlib.Linear3,
    dynlib.Fill, dynlib.ColorRGBA, dynlib.toFill, themeCore.sampleColor,
    themeCore.centerColorRgba, themeCore.centerColor
else:
  export
    figdraw.FillGradientAxis, figdraw.FillKind, figdraw.Linear2, figdraw.Linear3,
    figdraw.Fill, figdraw.ColorRGBA, figdraw.toFill, figdraw.sampleColor,
    figdraw.centerColorRgba, figdraw.centerColor
export images
export renderresources

const
  DefaultDrawLevel* = 50.ZLevel
  FocusRingDrawLevel* = 90.ZLevel
  PopupDrawLevel* = 100.ZLevel
  DefaultTypefaceFallbackNames* = ["Ubuntu.ttf", "HackNerdFont-Regular.ttf"]
  TextEllipsis = "…"

type DrawContext* = ref object
  xRenders: Renders
  xParent: FigIdx
  xViewParent: FigIdx
  xRenderOrigin: nimkitTypes.Point
  xBounds: nimkitTypes.Rect
  xVisibleRect: nimkitTypes.Rect
  xAppearance: Appearance
  xResources: RenderResourceManifest

var defaultTypefaceIds {.threadvar.}: Table[string, TypefaceId]

proc defaultTypefaceRequest(
    fontName = defaultFontName()
): tuple[name: string, fallbackNames: seq[string]] =
  result.name =
    if fontName.len > 0:
      fontName
    else:
      defaultFontName()
  if result.name != DefaultFontName:
    result.fallbackNames.add DefaultFontName
  result.fallbackNames.add DefaultTypefaceFallbackNames

proc defaultTypefaceCacheKey(
    request: tuple[name: string, fallbackNames: seq[string]]
): string =
  result = request.name
  for fallbackName in request.fallbackNames:
    result.add '\0'
    result.add fallbackName

proc toFigRect(rect: nimkitTypes.Rect): bumpy.Rect =
  bumpy.rect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)

proc defaultFont(size: float32, fontName = defaultFontName()): FontRef =
  let
    request = defaultTypefaceRequest(fontName)
    cacheKey = request.defaultTypefaceCacheKey()
  if defaultTypefaceIds.len == 0:
    defaultTypefaceIds = initTable[string, TypefaceId]()
  if cacheKey notin defaultTypefaceIds:
    defaultTypefaceIds[cacheKey] = loadTypeface(request.name, request.fallbackNames)
  fontRef(defaultTypefaceIds[cacheKey].fontWithSize(size))

proc fontFor(style: TextStyle): FontRef =
  defaultFont(style.fontSize, style.fontName)

proc fontLineHeight(font: FontRef): float32 =
  when defined(useNativeDynlib):
    max(font.font.size, font.font.lineHeight)
  else:
    getLineHeightImpl(font.font)

when defined(useNativeDynlib):
  proc figLine(a, b: Vec2, fillValue: Fill, weight: float32, zlevel = 0.ZLevel): Fig =
    let
      delta = b - a
      halfWeight = max(0.0'f32, weight) / 2.0'f32
      bounds = bumpy.rect(
        min(a.x, b.x) - halfWeight,
        min(a.y, b.y) - halfWeight,
        abs(delta.x) + halfWeight * 2.0'f32,
        abs(delta.y) + halfWeight * 2.0'f32,
      )

    result = Fig(kind: nkDrawable)
    result.zlevel = zlevel
    result.screenBox = bounds
    result.fill = fillValue
    result.drawStroke = RenderStroke(weight: weight, fill: fillValue)
    result.drawOps.add drawableLine(a - bounds.xy, b - bounds.xy)

  proc figLine(
      x1, y1, x2, y2: float32, fillValue: Fill, weight: float32, zlevel = 0.ZLevel
  ): Fig =
    figLine(vec2(x1, y1), vec2(x2, y2), fillValue, weight, zlevel)

  proc figCircle(
      center: Vec2, fillValue: Fill, radius: float32, zlevel = 0.ZLevel
  ): Fig =
    let
      clampedRadius = max(0.0'f32, radius)
      diameter = clampedRadius * 2.0'f32

    result = Fig(kind: nkDrawable)
    result.zlevel = zlevel
    result.fill = fillValue
    result.screenBox =
      bumpy.rect(center.x - clampedRadius, center.y - clampedRadius, diameter, diameter)
    result.drawOps.add drawableCircle(vec2(clampedRadius), clampedRadius)

  proc figCircle(
      x, y: float32, fillValue: Fill, radius: float32, zlevel = 0.ZLevel
  ): Fig =
    figCircle(vec2(x, y), fillValue, radius, zlevel)

const AllCorners = {dcTopLeft, dcTopRight, dcBottomLeft, dcBottomRight}

proc uniformCornerRadii(
    radius: float32, roundedCorners: set[DirectionCorners] = AllCorners
): array[DirectionCorners, uint16] =
  let clamped = max(radius, 0.0'f32)
  for corner in DirectionCorners:
    if corner in roundedCorners:
      result[corner] = clamped.round().uint16

proc figCornerRadii(radii: themeCore.CornerRadii): array[DirectionCorners, uint16] =
  result[dcTopLeft] = radii.topLeft.round().uint16
  result[dcTopRight] = radii.topRight.round().uint16
  result[dcBottomLeft] = radii.bottomLeft.round().uint16
  result[dcBottomRight] = radii.bottomRight.round().uint16

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
    strokeColor = color(0.0, 0.0, 0.0, 0.0),
    strokeWidth = 0.0'f32,
    cornerRadius = 0.0'f32,
    shadows: openArray[BoxShadow] = [],
    clips = false,
    maskContent = false,
    roundedCorners: set[DirectionCorners] = AllCorners,
    lightMaskContent = false,
    cornerRadii = initCornerRadii(0.0'f32),
): Fig =
  result = Fig(
    kind: nkRectangle,
    screenBox: rect.toFigRect,
    fill: fillValue,
    corners:
      if cornerRadii.isZero:
        uniformCornerRadii(cornerRadius, roundedCorners)
      else:
        cornerRadii.figCornerRadii(),
    stroke: RenderStroke(weight: strokeWidth, fill: fill(strokeColor.rgba)),
  )
  if maskContent or clips:
    result.flags.incl NfClipContent
  elif lightMaskContent:
    result.flags.incl NfRectMaskContent
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
    rect: nimkitTypes.Rect, text: string, style: TextStyle, alignment = taLeft
): GlyphArrangement =
  let
    font = style.fontFor()
    fontStyle = fs(font, fill(style.color.rgba))
  typeset(
    rect.toFigRect,
    [(fontStyle, text)],
    hAlign = alignment.toFontHorizontal,
    vAlign = Middle,
    minContent = false,
    wrap = false,
  )

proc textLayout*(
    rect: nimkitTypes.Rect, text: string, color: nimkitTypes.Color, alignment = taLeft
): GlyphArrangement =
  textLayout(
    rect,
    text,
    initAppearance().resolveTextStyle(controlStyle(srTextField), color, insets(0.0)),
    alignment,
  )

proc textLayout*(
    rect: nimkitTypes.Rect,
    storage: TextStorage,
    style: TextStyle,
    alignment = taLeft,
    wrap = false,
): GlyphArrangement =
  var spans: seq[(FontStyle, string)]
  if storage.isNil or storage.len == 0:
    let attributes = defaultTextAttributes(style.color, style.fontSize)
    var font = defaultFont(attributes.fontSize, style.fontName).font
    font.underline = attributes.hasUnderline
    font.strikethrough = attributes.hasStrikethrough
    spans.add((fs(font, fill(style.color.rgba)), ""))
  else:
    for (attributes, text) in storage.styledRuns:
      var font = defaultFont(attributes.fontSize, style.fontName).font
      font.underline = attributes.hasUnderline
      font.strikethrough = attributes.hasStrikethrough
      spans.add((fs(font, fill(attributes.foregroundColor.rgba)), text))
  typeset(
    rect.toFigRect,
    spans,
    hAlign = alignment.toFontHorizontal,
    vAlign = Top,
    minContent = false,
    wrap = wrap,
  )

proc textLayout*(
    rect: nimkitTypes.Rect, storage: TextStorage, alignment = taLeft, wrap = false
): GlyphArrangement =
  textLayout(
    rect,
    storage,
    initAppearance().resolveTextStyle(
      controlStyle(srTextView), color(0.08, 0.09, 0.11, 1.0), insets(0.0)
    ),
    alignment,
    wrap,
  )

proc textNaturalSize*(text: string, style: TextStyle): nimkitTypes.Size =
  let
    fontSize = style.fontSize
    font = style.fontFor()
    style = fs(font, fill(color(0.0, 0.0, 0.0, 1.0).rgba))
    lineHeight = max(fontSize, font.fontLineHeight())
    lineCount = block:
      var count = 1
      for ch in text:
        if ch == '\n':
          inc count
      count
    layout = typesetForMeasurement(
      bumpy.rect(0.0, 0.0, 10000.0, max(lineHeight * lineCount.float32, 100.0'f32)),
      [(style, text)],
      hAlign = Left,
      vAlign = Top,
      minContent = false,
      wrap = false,
    )
  initSize(
    max(layout.bounding.w, layout.maxSize.x),
    max(lineHeight * lineCount.float32, layout.bounding.h),
  )

proc textNaturalSize*(text: string): nimkitTypes.Size =
  text.textNaturalSize(
    initAppearance().resolveTextStyle(
      controlStyle(srTextField), color(0.08, 0.09, 0.11, 1.0), insets(0.0)
    )
  )

proc runePrefix(text: string, count: int): string =
  var index = 0
  for rune in text.runes:
    if index >= count:
      break
    result.add rune.toUTF8()
    inc index

proc clippedText*(text: string, width: float32, style: TextStyle): string =
  if text.len == 0 or width <= 0.0'f32:
    return ""
  if text.textNaturalSize(style).width <= width:
    return text
  let ellipsisWidth = TextEllipsis.textNaturalSize(style).width
  if ellipsisWidth > width:
    return ""

  var
    low = 0
    high = text.runeLen()
  while low < high:
    let middle = (low + high + 1) div 2
    if (text.runePrefix(middle) & TextEllipsis).textNaturalSize(style).width <= width:
      low = middle
    else:
      high = middle - 1
  if low == 0:
    TextEllipsis
  else:
    text.runePrefix(low) & TextEllipsis

proc clippedText*(text: string, width: float32): string =
  text.clippedText(
    width,
    initAppearance().resolveTextStyle(
      controlStyle(srTextField), color(0.08, 0.09, 0.11, 1.0), insets(0.0)
    ),
  )

proc textNode(
    rect: nimkitTypes.Rect, text: string, style: TextStyle, alignment = taLeft
): Fig =
  Fig(
    kind: nkText,
    screenBox: rect.toFigRect,
    textLayout: textLayout(rect, text, style, alignment),
  )

proc textNode(
    rect: nimkitTypes.Rect, text: string, color: nimkitTypes.Color, alignment = taLeft
): Fig =
  textNode(
    rect,
    text,
    initAppearance().resolveTextStyle(controlStyle(srTextField), color, insets(0.0)),
    alignment,
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
  let carets = layout.caretPositionsFor(index)
  if carets.len > 0:
    var caret = carets[0]
    for candidate in carets:
      if candidate.lineIndex > caret.lineIndex:
        caret = candidate
    return rect(
      textRect.origin.x + caret.rect.x,
      textRect.origin.y + caret.rect.y,
      1.0,
      caret.rect.h,
    )

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
    return rect(textRect.origin.x + x, textRect.origin.y + rect.y, 1.0, rect.h)

  let
    fontSize = defaultFontSize()
    font = defaultFont(fontSize)
    lineHeight = max(fontSize, font.fontLineHeight())
  rect(
    textRect.origin.x,
    textRect.origin.y + max((textRect.size.height - lineHeight) / 2.0'f32, 0.0),
    1.0,
    min(lineHeight, textRect.size.height),
  )

proc initDrawContext*(): DrawContext =
  result = DrawContext(
    xRenders: Renders(layers: initOrderedTable[ZLevel, RenderList]()),
    xResources: initRenderResourceManifest(),
  )
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

proc renderParent*(context: DrawContext): FigIdx =
  context.xParent

proc renderViewParent*(context: DrawContext): FigIdx =
  context.xViewParent

proc renders*(context: DrawContext): Renders =
  context.xRenders

proc resources*(context: DrawContext): RenderResourceManifest =
  context.xResources

proc appearance*(context: DrawContext): Appearance =
  context.xAppearance

proc renderRectFor*(context: DrawContext, rect: nimkitTypes.Rect): nimkitTypes.Rect =
  nimkitTypes.rect(
    context.xRenderOrigin.x + rect.origin.x,
    context.xRenderOrigin.y + rect.origin.y,
    rect.size.width,
    rect.size.height,
  )

proc renderPointFor(context: DrawContext, point: nimkitTypes.Point): nimkitTypes.Point =
  nimkitTypes.initPoint(
    context.xRenderOrigin.x + point.x, context.xRenderOrigin.y + point.y
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
    strokeColor = color(0.0, 0.0, 0.0, 0.0),
    strokeWidth = 0.0'f32,
    cornerRadius = 0.0'f32,
    shadows: openArray[BoxShadow] = [],
    clips = false,
    maskContent = false,
    roundedCorners: set[DirectionCorners] = AllCorners,
    lightMaskContent = false,
    cornerRadii = initCornerRadii(0.0'f32),
): FigIdx {.discardable.} =
  context.addFig(
    layer,
    parent,
    rectangleNode(
      rect, fillValue, strokeColor, strokeWidth, cornerRadius, shadows, clips,
      maskContent, roundedCorners, lightMaskContent, cornerRadii,
    ),
  )

proc addRenderRectangle*(
    context: DrawContext,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    fillValue: Fill,
    strokeColor = color(0.0, 0.0, 0.0, 0.0),
    strokeWidth = 0.0'f32,
    cornerRadius = 0.0'f32,
    shadows: openArray[BoxShadow] = [],
    clips = false,
    maskContent = false,
    roundedCorners: set[DirectionCorners] = AllCorners,
    lightMaskContent = false,
    cornerRadii = initCornerRadii(0.0'f32),
): FigIdx {.discardable.} =
  context.addRenderRectangle(
    DefaultDrawLevel, parent, rect, fillValue, strokeColor, strokeWidth, cornerRadius,
    shadows, clips, maskContent, roundedCorners, lightMaskContent, cornerRadii,
  )

proc addRenderRectangle*(
    context: DrawContext,
    rect: nimkitTypes.Rect,
    fillValue: Fill,
    strokeColor = color(0.0, 0.0, 0.0, 0.0),
    strokeWidth = 0.0'f32,
    cornerRadius = 0.0'f32,
    shadows: openArray[BoxShadow] = [],
    clips = false,
    maskContent = false,
    roundedCorners: set[DirectionCorners] = AllCorners,
    lightMaskContent = false,
    cornerRadii = initCornerRadii(0.0'f32),
): FigIdx {.discardable.} =
  context.addRenderRectangle(
    context.xParent, rect, fillValue, strokeColor, strokeWidth, cornerRadius, shadows,
    clips, maskContent, roundedCorners, lightMaskContent, cornerRadii,
  )

proc addRenderLine*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    start, stop: nimkitTypes.Point,
    fillValue: Fill,
    weight: float32,
): FigIdx {.discardable.} =
  let
    renderedStart = context.renderPointFor(start)
    renderedStop = context.renderPointFor(stop)
  context.addFig(
    layer,
    parent,
    figLine(
      renderedStart.x, renderedStart.y, renderedStop.x, renderedStop.y, fillValue,
      weight, layer,
    ),
  )

proc addRenderLine*(
    context: DrawContext,
    parent: FigIdx,
    start, stop: nimkitTypes.Point,
    fillValue: Fill,
    weight: float32,
): FigIdx {.discardable.} =
  context.addRenderLine(DefaultDrawLevel, parent, start, stop, fillValue, weight)

proc addRenderLine*(
    context: DrawContext,
    start, stop: nimkitTypes.Point,
    fillValue: Fill,
    weight: float32,
): FigIdx {.discardable.} =
  context.addRenderLine(context.xParent, start, stop, fillValue, weight)

proc addRenderCircle*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    center: nimkitTypes.Point,
    fillValue: Fill,
    radius: float32,
): FigIdx {.discardable.} =
  let renderedCenter = context.renderPointFor(center)
  context.addFig(
    layer,
    parent,
    figCircle(renderedCenter.x, renderedCenter.y, fillValue, radius, layer),
  )

proc addRenderCircle*(
    context: DrawContext,
    parent: FigIdx,
    center: nimkitTypes.Point,
    fillValue: Fill,
    radius: float32,
): FigIdx {.discardable.} =
  context.addRenderCircle(DefaultDrawLevel, parent, center, fillValue, radius)

proc addRenderCircle*(
    context: DrawContext, center: nimkitTypes.Point, fillValue: Fill, radius: float32
): FigIdx {.discardable.} =
  context.addRenderCircle(context.xParent, center, fillValue, radius)

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
    style: TextStyle,
    alignment = taLeft,
): FigIdx {.discardable.} =
  let renderedRect = context.renderRectFor(rect)
  let layout = textLayout(renderedRect, text, style, alignment)
  context.xResources.addFonts(layout)
  context.addFig(textNode(renderedRect, layout))

proc addText*(
    context: DrawContext,
    rect: nimkitTypes.Rect,
    text: string,
    color: nimkitTypes.Color,
    alignment = taLeft,
): FigIdx {.discardable.} =
  context.addText(
    rect,
    text,
    context.appearance.resolveTextStyle(controlStyle(srTextField), color, insets(0.0)),
    alignment,
  )

proc addText*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    text: string,
    style: TextStyle,
    alignment = taLeft,
): FigIdx {.discardable.} =
  let renderedRect = context.renderRectFor(rect)
  let layout = textLayout(renderedRect, text, style, alignment)
  context.xResources.addFonts(layout)
  context.addFig(layer, parent, textNode(renderedRect, layout))

proc addText*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    text: string,
    color: nimkitTypes.Color,
    alignment = taLeft,
): FigIdx {.discardable.} =
  context.addText(
    layer,
    parent,
    rect,
    text,
    context.appearance.resolveTextStyle(controlStyle(srTextField), color, insets(0.0)),
    alignment,
  )

proc addText*(
    context: DrawContext, rect: nimkitTypes.Rect, layout: GlyphArrangement
): FigIdx {.discardable.} =
  context.xResources.addFonts(layout)
  context.addFig(textNode(context.renderRectFor(rect), layout))

proc addImage*(
    context: DrawContext,
    rect: nimkitTypes.Rect,
    image: ImageResource,
    tint = color(1.0, 1.0, 1.0, 1.0),
): FigIdx {.discardable.} =
  if image.isNil:
    return (-1).FigIdx
  context.xResources.addImage(image)
  context.addFig(imageNode(context.renderRectFor(rect), image, fill(tint.rgba)))

proc addImage*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    image: ImageResource,
    tint = color(1.0, 1.0, 1.0, 1.0),
): FigIdx {.discardable.} =
  if image.isNil:
    return (-1).FigIdx
  context.xResources.addImage(image)
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
  context.xResources.addFonts(layout)
  var node = textNode(context.renderRectFor(rect), layout)
  node.selectTextNode(selectedLocation, selectedLength, selectionColor)
  context.addFig(node)

proc addFocusRing*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    box: ControlBoxStyle,
) =
  if box.focusRingWidth <= 0.0'f32:
    return
  let ringRect = rect.inset(insets(box.focusRingInset))
  if ringRect.isEmpty:
    return
  discard context.addRenderRectangle(
    layer,
    parent,
    ringRect,
    color(0.0, 0.0, 0.0, 0.0),
    box.focusRingColor,
    box.focusRingWidth,
    max(box.cornerRadius - box.focusRingInset, 0.0'f32),
    cornerRadii = box.cornerRadii.inset(box.focusRingInset),
  )

proc addFocusRing*(context: DrawContext, rect: nimkitTypes.Rect, box: ControlBoxStyle) =
  let parent =
    if box.focusRingInset < 0.0'f32: context.xViewParent else: context.xParent
  context.addFocusRing(DefaultDrawLevel, parent, rect, box)

proc addFocusRing*(
    context: DrawContext, layer: ZLevel, rect: nimkitTypes.Rect, box: ControlBoxStyle
) =
  context.addFocusRing(layer, (-1).FigIdx, rect, box)

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
    parent, rect(centerX - width * 0.50'f32, topY, width, 1.0'f32), color
  )
  discard context.addRenderRectangle(
    parent,
    rect(centerX - width * 0.35'f32, topY + 1.0'f32, width * 0.70'f32, 1.0'f32),
    color,
  )
  discard context.addRenderRectangle(
    parent,
    rect(centerX - width * 0.20'f32, topY + 2.0'f32, width * 0.40'f32, 1.0'f32),
    color,
  )

proc addComboBoxArrow*(
    context: DrawContext, rect: nimkitTypes.Rect, color: nimkitTypes.Color
) =
  context.addComboBoxArrow(context.xParent, rect, color)
