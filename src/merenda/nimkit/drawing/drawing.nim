import std/[hashes, os, strutils, tables, unicode]

import pkg/bumpy

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw
  import figdraw/figextras
  from figdraw/common/typefaces import getLineHeightImpl
  import ./fontfallbacks

const AutomaticFontFallbackEnabled =
  when defined(useNativeDynlib):
    false
  else:
    figdrawTextBackend == "harfbuzzy" or figdrawTextBackend == "hybrid"

import ./images
import ./renderresources
import ./svgimages
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
  export fontfallbacks
export images
export renderresources

const
  DefaultDrawLevel* = 50.ZLevel
  FocusRingDrawLevel* = 90.ZLevel
  PopupDrawLevel* = 100.ZLevel
  TooltipDrawLevel* = 110.ZLevel
  DefaultTypefaceFallbackNames* =
    when defined(macosx):
      ["SFNS.ttf", "Arial"]
    elif defined(windows):
      ["Arial", "Tahoma"]
    else:
      ["DejaVu Sans", "Liberation Sans"]
  MonospaceTypefaceFallbackNames =
    when defined(macosx):
      ["SFNSMono.ttf", "Monaco", "Courier New"]
    elif defined(windows):
      ["Cascadia Mono", "Lucida Console", "Courier New"]
    else:
      ["DejaVu Sans Mono", "Liberation Mono", "Ubuntu Mono"]
  SlantedTypefaceFallbackNames =
    when defined(macosx):
      ["SFNSItalic.ttf", "Arial Italic.ttf", "Helvetica Oblique"]
    elif defined(windows):
      ["segoeuii.ttf", "ariali.ttf", "timesi.ttf"]
    else:
      [
        "NotoSans-Italic.ttf", "DejaVuSans-Oblique.ttf", "LiberationSans-Italic.ttf",
        "Ubuntu-Italic.ttf",
      ]
  SlantedMonospaceTypefaceFallbackNames =
    when defined(macosx):
      ["SFNSMonoItalic.ttf", "Menlo Italic", "Courier New Italic.ttf"]
    elif defined(windows):
      ["consolai.ttf", "courii.ttf"]
    else:
      [
        "NotoSansMono-Italic.ttf", "DejaVuSansMono-Oblique.ttf",
        "LiberationMono-Italic.ttf", "UbuntuMono-RI.ttf",
      ]
  TextEllipsis = "…"

type
  RenderSlotCapture* = object
    ## Captured or retained drawing for one stable slot inside a view.
    slotId*: RenderSlotId
    position*: RenderSlotPosition
    revision*: uint64
    captured*: bool
    renders*: Renders
    resources*: RenderResourceManifest
    usesVisibleRect*: bool

  DrawContext* = ref object
    xRenders: Renders
    xLayer: ZLevel
    xParent: FigIdx
    xViewParent: FigIdx
    xRenderOrigin: nimkitTypes.Point
    xBounds: nimkitTypes.Rect
    xVisibleRect: nimkitTypes.Rect
    xUsesVisibleRect: bool
    xAppearance: Appearance
    xResources: RenderResourceManifest
    xCapturesSlots: bool
    xSlotShell: Fig
    xDefaultSlotRevision: uint64
    xCachedSlotRevisions: Table[RenderSlotId, uint64]
    xForcedSlots: Table[RenderSlotId, bool]
    xForceAllSlots: bool
    xSlotCaptures: seq[RenderSlotCapture]
    xActiveSlot: int

var defaultTypefaceIds {.threadvar.}: Table[string, TypefaceId]

when AutomaticFontFallbackEnabled:
  installAutomaticFontFallbackResolver()

proc typefaceVariantNames(fontName: string, slant: FontSlant): seq[string] =
  if slant == fsUpright:
    return @[fontName]
  let parts = fontName.splitFile()
  var stem = parts.name
  let lowerStem = stem.toLowerAscii()
  if lowerStem.endsWith("italic") or lowerStem.endsWith("oblique"):
    return @[fontName]
  for suffix in ["-Regular", "_Regular", " Regular", "Regular"]:
    if stem.endsWith(suffix):
      stem.setLen(stem.len - suffix.len)
      break
  let variants =
    if slant == fsOblique:
      ["Oblique", "Italic"]
    else:
      ["Italic", "Oblique"]
  for variant in variants:
    result.add parts.dir / (stem & "-" & variant & parts.ext)
    result.add parts.dir / (stem & " " & variant & parts.ext)

proc defaultTypefaceRequest(
    fontName = defaultFontName(), slant = fsUpright, role = frUI
): tuple[name: string, fallbackNames: seq[string]] =
  let baseName =
    if fontName.len > 0:
      fontName
    else:
      defaultFontName(role)
  let variants = baseName.typefaceVariantNames(slant)
  result.name = variants[0]
  for index in 1 ..< variants.len:
    result.fallbackNames.add variants[index]
  if slant != fsUpright:
    case role
    of frUI:
      result.fallbackNames.add SlantedTypefaceFallbackNames
    of frMonospace:
      result.fallbackNames.add SlantedMonospaceTypefaceFallbackNames
  if result.name != baseName:
    result.fallbackNames.add baseName
  case role
  of frUI:
    if baseName != DefaultFontName:
      result.fallbackNames.add DefaultFontName
    result.fallbackNames.add DefaultTypefaceFallbackNames
  of frMonospace:
    if baseName != DefaultMonospaceFontName:
      result.fallbackNames.add DefaultMonospaceFontName
    result.fallbackNames.add MonospaceTypefaceFallbackNames

proc defaultTypefaceCacheKey(
    request: tuple[name: string, fallbackNames: seq[string]], fontFace: SystemTypeface
): string =
  if fontFace.file.path.len > 0:
    result = "face\0" & fontFace.file.path & "\0" & $fontFace.file.faceIndex
    for variation in fontFace.variations:
      result.add '\0'
      result.add variation.tag
      result.add '='
      result.add $cast[uint32](variation.value)
    return
  result = request.name
  for fallbackName in request.fallbackNames:
    result.add '\0'
    result.add fallbackName

proc toFigRect(rect: nimkitTypes.Rect): bumpy.Rect =
  bumpy.rect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)

proc defaultFont(
    size: float32,
    fontName = defaultFontName(),
    language = defaultLanguageTag(),
    slant = fsUpright,
    role = frUI,
    fontFace = SystemTypeface(),
): FontRef =
  let
    resolvedLanguage =
      if language.isAutomatic:
        defaultLanguageTag()
      else:
        language
    request = defaultTypefaceRequest(fontName, slant, role)
    exactFontFace =
      if slant == fsUpright:
        fontFace
      else:
        SystemTypeface()
    cacheKey = request.defaultTypefaceCacheKey(exactFontFace)
  if defaultTypefaceIds.len == 0:
    defaultTypefaceIds = initTable[string, TypefaceId]()
  if cacheKey notin defaultTypefaceIds:
    defaultTypefaceIds[cacheKey] =
      if exactFontFace.file.path.len > 0:
        exactFontFace.fontWithSize(size).typefaceId
      else:
        loadTypeface(request.name, request.fallbackNames)
  var font = defaultTypefaceIds[cacheKey].fontWithSize(size)
  if exactFontFace.file.path.len > 0:
    font.variations =
      newSeqOfCap[typeof(font.variations[0])](exactFontFace.variations.len)
    for variation in exactFontFace.variations:
      font.variations.add typeof(font.variations[0])(
        tag: variation.tag, value: variation.value
      )
  when AutomaticFontFallbackEnabled:
    font.language = $resolvedLanguage
  fontRef(font)

proc textFont*(style: TextStyle, role = frUI): FontRef =
  defaultFont(
    style.fontSize, style.fontName, style.language, style.fontSlant, role,
    style.fontFace,
  )

proc fontFor(style: TextStyle): FontRef =
  style.textFont()

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

proc normalizeLineAdvances(layout: var GlyphArrangement) =
  ## Keep mixed-height line boxes from overlapping when a backend advances a
  ## baseline using the following line's metrics.
  if layout.lines.len < 2:
    return

  var
    nextLineTop = 0.0'f32
    hasLineTop = false
    minimumY = float32.high
    maximumY = -float32.high
  for line in layout.lines:
    var
      lineMinimumY = float32.high
      lineMaximumY = -float32.high
      hasGlyph = false
    for glyphIndex in line:
      let glyphRect =
        if glyphIndex >= 0 and glyphIndex < layout.arrangedGlyphs.len:
          layout.arrangedGlyphs[glyphIndex].rect
        elif glyphIndex >= 0 and glyphIndex < layout.selectionRects.len:
          layout.selectionRects[glyphIndex]
        else:
          continue
      lineMinimumY = min(lineMinimumY, glyphRect.y)
      lineMaximumY = max(lineMaximumY, glyphRect.y + glyphRect.h)
      hasGlyph = true
    if not hasGlyph:
      continue

    if not hasLineTop:
      nextLineTop = lineMinimumY
      hasLineTop = true
    let offset = nextLineTop - lineMinimumY
    if abs(offset) > 0.001'f32:
      for glyphIndex in line:
        if glyphIndex >= 0 and glyphIndex < layout.arrangedGlyphs.len:
          layout.arrangedGlyphs[glyphIndex].rect.y += offset
          layout.arrangedGlyphs[glyphIndex].pos.y += offset
        if glyphIndex >= 0 and glyphIndex < layout.selectionRects.len:
          layout.selectionRects[glyphIndex].y += offset
        if glyphIndex >= 0 and glyphIndex < layout.positions.len:
          layout.positions[glyphIndex].y += offset
    let lineHeight = max(lineMaximumY - lineMinimumY, 0.0'f32)
    minimumY = min(minimumY, nextLineTop)
    maximumY = max(maximumY, nextLineTop + lineHeight)
    nextLineTop += lineHeight

  if hasLineTop:
    layout.bounding.y = minimumY
    layout.bounding.h = max(maximumY - minimumY, 0.0'f32)
    layout.maxSize.y = max(layout.maxSize.y, layout.bounding.h)

func paragraphIndices(runes: openArray[Rune]): seq[int] =
  result = newSeq[int](runes.len + 1)
  var
    paragraphIndex = 0
    previousWasCarriageReturn = false
  for index, rune in runes:
    result[index] = paragraphIndex
    if rune == Rune('\r'):
      inc paragraphIndex
    elif rune == Rune('\n') and not previousWasCarriageReturn:
      inc paragraphIndex
    previousWasCarriageReturn = rune == Rune('\r')
  result[^1] = paragraphIndex

func lineSourceIndex(layout: GlyphArrangement, line: Slice[int]): int =
  result = layout.sourceRunes.len
  for glyphIndex in line:
    result = min(result, layout.arrangedGlyphs[glyphIndex].source.runeStart)
  result = clamp(result, 0, layout.sourceRunes.len)

func linesByParagraph(
    layout: GlyphArrangement, indices: openArray[int]
): seq[seq[Slice[int]]] =
  let paragraphCount =
    if indices.len == 0:
      1
    else:
      indices[^1] + 1
  result = newSeq[seq[Slice[int]]](paragraphCount)
  for line in layout.lineGlyphRanges():
    let sourceIndex = layout.lineSourceIndex(line)
    result[indices[sourceIndex]].add line

func paragraphStarts(indices: openArray[int]): seq[int] =
  let paragraphCount =
    if indices.len == 0:
      1
    else:
      indices[^1] + 1
  result = newSeq[int](paragraphCount)
  var paragraphIndex = 1
  for sourceIndex in 1 ..< indices.len:
    if indices[sourceIndex] != indices[sourceIndex - 1]:
      result[paragraphIndex] = sourceIndex
      inc paragraphIndex

proc paragraphLineBreakModes(
    storage: TextStorage, indices: openArray[int]
): seq[TextLineBreakMode] =
  let starts = indices.paragraphStarts()
  result = newSeq[TextLineBreakMode](starts.len)
  for paragraphIndex, start in starts:
    if not storage.isNil and storage.len > 0:
      result[paragraphIndex] =
        storage.attributesAt(min(start, storage.len - 1)).paragraphStyle.lineBreakMode
    else:
      result[paragraphIndex] = tlbmWordWrapping

func canCombineLineBreakLayouts(wrapped, unwrapped: GlyphArrangement): bool =
  wrapped.sourceRunes == unwrapped.sourceRunes and
    wrapped.arrangedGlyphs.len == unwrapped.arrangedGlyphs.len and
    wrapped.positions.len == unwrapped.positions.len and
    wrapped.selectionRects.len == unwrapped.selectionRects.len

proc mixedLineBreakLayout(
    wrapped, unwrapped: GlyphArrangement, storage: TextStorage
): GlyphArrangement =
  if not wrapped.canCombineLineBreakLayouts(unwrapped) or
      unwrapped.arrangedGlyphs.len == 0:
    return wrapped

  let
    indices = unwrapped.sourceRunes.paragraphIndices()
    modes = storage.paragraphLineBreakModes(indices)
    wrappedLines = wrapped.linesByParagraph(indices)
    unwrappedLines = unwrapped.linesByParagraph(indices)
  result = unwrapped
  result.lines = @[]
  result.arrangedGlyphs = newSeq[ArrangedGlyph](wrapped.arrangedGlyphs.len)
  result.positions = newSeq[Vec2](wrapped.positions.len)
  result.selectionRects = newSeq[bumpy.Rect](wrapped.selectionRects.len)
  var visited = newSeq[bool](wrapped.arrangedGlyphs.len)

  for paragraphIndex, mode in modes:
    let selectedLines =
      if mode == tlbmClipping:
        unwrappedLines[paragraphIndex]
      else:
        wrappedLines[paragraphIndex]
    let source = if mode == tlbmClipping: unwrapped else: wrapped
    for line in selectedLines:
      result.lines.add line
      for glyphIndex in line:
        result.arrangedGlyphs[glyphIndex] = source.arrangedGlyphs[glyphIndex]
        result.positions[glyphIndex] = source.positions[glyphIndex]
        result.selectionRects[glyphIndex] = source.selectionRects[glyphIndex]
        visited[glyphIndex] = true

  for wasVisited in visited:
    if not wasVisited:
      return wrapped

  var layoutHash = hash((wrapped.contentHash, result.contentHash))
  for mode in modes:
    layoutHash = layoutHash !& hash(mode)
  result.contentHash = !$layoutHash

proc usesMixedLineBreakModes(storage: TextStorage): bool =
  if storage.isNil:
    return
  for run in storage.runs:
    if run.attributes.paragraphStyle.lineBreakMode == tlbmClipping:
      return true

proc textLayoutImpl(
    rect: nimkitTypes.Rect,
    storage: TextStorage,
    style: TextStyle,
    alignment = taLeft,
    wrap = false,
    rasterize = true,
): GlyphArrangement =
  var spans: seq[(FontStyle, string)]
  if storage.isNil or storage.len == 0:
    let attributes = defaultTextAttributes(style.color, style.fontSize)
    var font = defaultFont(
      attributes.fontSize,
      style.fontName,
      style.language,
      style.fontSlant,
      fontFace = style.fontFace,
    ).font
    font.underline = attributes.hasUnderline
    font.strikethrough = attributes.hasStrikethrough
    spans.add((fs(font, fill(style.color.rgba)), ""))
  else:
    for (attributes, text) in storage.styledRuns:
      let
        fontName =
          if attributes.fontName.len > 0: attributes.fontName else: style.fontName
        language =
          if attributes.language.isAutomatic: style.language else: attributes.language
        fontFace =
          if fontName == style.fontName:
            style.fontFace
          else:
            SystemTypeface()
      var font = defaultFont(
        attributes.fontSize, fontName, language, style.fontSlant, fontFace = fontFace
      ).font
      font.underline = attributes.hasUnderline
      font.strikethrough = attributes.hasStrikethrough
      spans.add((fs(font, fill(attributes.foregroundColor.rgba)), text))
  if wrap and storage.usesMixedLineBreakModes():
    let
      wrapped =
        if rasterize:
          typeset(
            rect.toFigRect,
            spans,
            hAlign = alignment.toFontHorizontal,
            vAlign = Top,
            minContent = false,
            wrap = true,
          )
        else:
          typesetForMeasurement(
            rect.toFigRect,
            spans,
            hAlign = alignment.toFontHorizontal,
            vAlign = Top,
            minContent = false,
            wrap = true,
          )
      unwrapped =
        if rasterize:
          typeset(
            rect.toFigRect,
            spans,
            hAlign = alignment.toFontHorizontal,
            vAlign = Top,
            minContent = false,
            wrap = false,
          )
        else:
          typesetForMeasurement(
            rect.toFigRect,
            spans,
            hAlign = alignment.toFontHorizontal,
            vAlign = Top,
            minContent = false,
            wrap = false,
          )
    result = mixedLineBreakLayout(wrapped, unwrapped, storage)
  elif rasterize:
    result = typeset(
      rect.toFigRect,
      spans,
      hAlign = alignment.toFontHorizontal,
      vAlign = Top,
      minContent = false,
      wrap = wrap,
    )
  else:
    result = typesetForMeasurement(
      rect.toFigRect,
      spans,
      hAlign = alignment.toFontHorizontal,
      vAlign = Top,
      minContent = false,
      wrap = wrap,
    )
  result.normalizeLineAdvances()

proc textLayout*(
    rect: nimkitTypes.Rect,
    storage: TextStorage,
    style: TextStyle,
    alignment = taLeft,
    wrap = false,
): GlyphArrangement =
  textLayoutImpl(rect, storage, style, alignment, wrap, rasterize = true)

proc textLayoutForMeasurement*(
    rect: nimkitTypes.Rect,
    storage: TextStorage,
    style: TextStyle,
    alignment = taLeft,
    wrap = false,
): GlyphArrangement =
  ## Typesets attributed text without generating and publishing glyph images.
  textLayoutImpl(rect, storage, style, alignment, wrap, rasterize = false)

proc textLayoutForMeasurement*(
    rect: nimkitTypes.Rect, storage: TextStorage, alignment = taLeft, wrap = false
): GlyphArrangement =
  textLayoutForMeasurement(
    rect,
    storage,
    initAppearance().resolveTextStyle(
      controlStyle(srTextView), color(0.08, 0.09, 0.11, 1.0), insets(0.0)
    ),
    alignment,
    wrap,
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
    xLayer: DefaultDrawLevel,
    xResources: initRenderResourceManifest(),
    xActiveSlot: -1,
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
    layer = DefaultDrawLevel,
) =
  context.xCapturesSlots = false
  context.xSlotCaptures.setLen(0)
  context.xActiveSlot = -1
  context.xLayer = layer
  context.xParent = parent
  context.xViewParent = viewParent
  context.xRenderOrigin = renderOrigin
  context.xBounds = bounds
  context.xVisibleRect = visibleRect
  context.xUsesVisibleRect = false
  context.xAppearance = appearance

proc beginRenderSlotCapture*(
    context: DrawContext,
    shell: Fig,
    renderOrigin: nimkitTypes.Point,
    bounds: nimkitTypes.Rect,
    visibleRect: nimkitTypes.Rect,
    appearance: Appearance,
    defaultRevision: uint64,
    cachedRevisions: Table[RenderSlotId, uint64],
    forcedSlots: openArray[RenderSlotId],
    forceAll = false,
    layer = DefaultDrawLevel,
) =
  ## Prepares a view draw whose named outputs become independently retained slots.
  context.xRenders = nil
  context.xResources = nil
  context.xLayer = layer
  context.xParent = (-1).FigIdx
  context.xViewParent = (-1).FigIdx
  context.xRenderOrigin = renderOrigin
  context.xBounds = bounds
  context.xVisibleRect = visibleRect
  context.xUsesVisibleRect = false
  context.xAppearance = appearance
  context.xCapturesSlots = true
  context.xSlotShell = shell
  context.xDefaultSlotRevision = defaultRevision
  context.xCachedSlotRevisions = cachedRevisions
  context.xForcedSlots = initTable[RenderSlotId, bool]()
  for slot in forcedSlots:
    context.xForcedSlots[slot] = true
  context.xForceAllSlots = forceAll
  context.xSlotCaptures.setLen(0)
  context.xActiveSlot = -1

proc renderSlotIndex(context: DrawContext, slot: RenderSlotId): int =
  for index, capture in context.xSlotCaptures:
    if capture.slotId == slot:
      return index
  -1

proc activateRenderSlot(context: DrawContext, index: int) =
  context.xActiveSlot = index
  if index < 0 or not context.xSlotCaptures[index].captured:
    context.xRenders = nil
    context.xResources = nil
    context.xParent = (-1).FigIdx
    context.xViewParent = (-1).FigIdx
    return
  context.xRenders = context.xSlotCaptures[index].renders
  context.xResources = context.xSlotCaptures[index].resources
  context.xParent = context.xRenders.layers[context.xLayer].rootIds[0]
  context.xViewParent = (-1).FigIdx

proc beginRenderSlot*(
    context: DrawContext,
    slot: RenderSlotId,
    revision: uint64,
    position = rspBeforeSubviews,
): bool =
  ## Selects one stable drawing slot and reports whether it needs recapturing.
  ##
  ## Callers must only emit drawing operations when this returns `true`. Every
  ## draw must enumerate all of its current slots so removed slots can be detached.
  if context.isNil:
    raise newException(ValueError, "cannot draw a render slot with a nil context")
  if not context.xCapturesSlots:
    return true
  var index = context.renderSlotIndex(slot)
  if index >= 0:
    let capture = context.xSlotCaptures[index]
    if capture.revision != revision or capture.position != position:
      raise newException(
        ValueError, "a render slot cannot change revision or position within one draw"
      )
  else:
    let captured =
      context.xForceAllSlots or slot in context.xForcedSlots or
      slot notin context.xCachedSlotRevisions or
      context.xCachedSlotRevisions[slot] != revision
    var renders: Renders
    var resources: RenderResourceManifest
    if captured:
      renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())
      renders.layers[context.xLayer] = RenderList()
      discard renders.addRoot(context.xLayer, context.xSlotShell)
      resources = initRenderResourceManifest()
    context.xSlotCaptures.add RenderSlotCapture(
      slotId: slot,
      position: position,
      revision: revision,
      captured: captured,
      renders: renders,
      resources: resources,
    )
    index = context.xSlotCaptures.high
  context.activateRenderSlot(index)
  context.xSlotCaptures[index].captured

proc ensureDefaultRenderSlot(context: DrawContext) =
  if context.xCapturesSlots and context.xActiveSlot < 0:
    discard context.beginRenderSlot(
      0.RenderSlotId, context.xDefaultSlotRevision, rspBeforeSubviews
    )

proc takeRenderSlotCaptures*(context: DrawContext): seq[RenderSlotCapture] =
  ## Moves the ordered slot captures out of a completed retained view draw.
  if context.isNil or not context.xCapturesSlots:
    return
  if context.xSlotCaptures.len == 0:
    discard context.beginRenderSlot(
      0.RenderSlotId, context.xDefaultSlotRevision, rspBeforeSubviews
    )
  result = move context.xSlotCaptures
  context.xActiveSlot = -1
  context.xRenders = nil
  context.xResources = nil

proc renderList*(context: DrawContext): RenderList =
  context.ensureDefaultRenderSlot()
  if context.xRenders.isNil:
    return RenderList()
  if DefaultDrawLevel in context.xRenders.layers:
    return context.xRenders.layers[DefaultDrawLevel]
  RenderList()

proc renderParent*(context: DrawContext): FigIdx =
  context.ensureDefaultRenderSlot()
  context.xParent

proc renderLayer*(context: DrawContext): ZLevel =
  context.xLayer

proc renderViewParent*(context: DrawContext): FigIdx =
  context.ensureDefaultRenderSlot()
  context.xViewParent

proc renders*(context: DrawContext): Renders =
  context.ensureDefaultRenderSlot()
  context.xRenders

proc resources*(context: DrawContext): RenderResourceManifest =
  context.ensureDefaultRenderSlot()
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
  context.ensureDefaultRenderSlot()
  context.xUsesVisibleRect = true
  if context.xCapturesSlots and context.xActiveSlot >= 0:
    context.xSlotCaptures[context.xActiveSlot].usesVisibleRect = true
  context.xVisibleRect

proc drawingDependsOnVisibleRect*(context: DrawContext): bool =
  ## Reports whether the current drawing read its dynamically clipped bounds.
  not context.isNil and context.xUsesVisibleRect

proc addFig*(
    context: DrawContext, layer: ZLevel, parent: FigIdx, node: Fig
): FigIdx {.discardable.} =
  context.ensureDefaultRenderSlot()
  if context.xRenders.isNil:
    raise newException(ValueError, "cannot draw an unchanged render slot")
  if parent == (-1).FigIdx:
    context.xRenders.addRoot(layer, node)
  else:
    context.xRenders.addChild(layer, parent, node)

proc addFig*(context: DrawContext, parent: FigIdx, node: Fig): FigIdx {.discardable.} =
  context.addFig(context.xLayer, parent, node)

proc addFig*(context: DrawContext, node: Fig): FigIdx {.discardable.} =
  context.ensureDefaultRenderSlot()
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
    context.xLayer, parent, rect, fillValue, strokeColor, strokeWidth, cornerRadius,
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
  context.ensureDefaultRenderSlot()
  context.addRenderRectangle(
    context.xParent, rect, fillValue, strokeColor, strokeWidth, cornerRadius, shadows,
    clips, maskContent, roundedCorners, lightMaskContent, cornerRadii,
  )

proc addRenderBackdropBlur*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    tint: Fill,
    blurRadius: float32,
    cornerRadius = 0.0'f32,
    cornerRadii = initCornerRadii(0.0'f32),
): FigIdx {.discardable.} =
  ## Add a rounded Figdraw backdrop blur with an optional color tint.
  context.addFig(
    layer,
    parent,
    Fig(
      kind: nkBackdropBlur,
      screenBox: rect.toFigRect,
      fill: tint,
      corners:
        if cornerRadii.isZero:
          uniformCornerRadii(cornerRadius, AllCorners)
        else:
          cornerRadii.figCornerRadii(),
      backdropBlur: BackdropBlurStyle(blur: max(blurRadius, 0.0'f32)),
    ),
  )

proc addRenderBackdropBlur*(
    context: DrawContext,
    layer: ZLevel,
    rect: nimkitTypes.Rect,
    tint: Fill,
    blurRadius: float32,
    cornerRadius = 0.0'f32,
    cornerRadii = initCornerRadii(0.0'f32),
): FigIdx {.discardable.} =
  context.addRenderBackdropBlur(
    layer, (-1).FigIdx, rect, tint, blurRadius, cornerRadius, cornerRadii
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
  context.addRenderLine(context.xLayer, parent, start, stop, fillValue, weight)

proc addRenderLine*(
    context: DrawContext,
    start, stop: nimkitTypes.Point,
    fillValue: Fill,
    weight: float32,
): FigIdx {.discardable.} =
  context.ensureDefaultRenderSlot()
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
  context.addRenderCircle(context.xLayer, parent, center, fillValue, radius)

proc addRenderCircle*(
    context: DrawContext, center: nimkitTypes.Point, fillValue: Fill, radius: float32
): FigIdx {.discardable.} =
  context.ensureDefaultRenderSlot()
  context.addRenderCircle(context.xParent, center, fillValue, radius)

proc addRenderDrawable*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    drawOps: openArray[DrawableOp],
    fillValue: Fill,
    stroke = RenderStroke(),
    drawSteps = 0'u16,
    drawAa = 0.0'f32,
): FigIdx {.discardable.} =
  ## Adds one FigDraw drawable node containing caller-provided primitive operations.
  context.addFig(
    layer,
    parent,
    Fig(
      kind: nkDrawable,
      screenBox: context.renderRectFor(rect).toFigRect,
      fill: fillValue,
      drawStroke: stroke,
      drawSteps: drawSteps,
      drawAa: drawAa,
      drawOps: @drawOps,
    ),
  )

proc addRenderDrawable*(
    context: DrawContext,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    drawOps: openArray[DrawableOp],
    fillValue: Fill,
    stroke = RenderStroke(),
    drawSteps = 0'u16,
    drawAa = 0.0'f32,
): FigIdx {.discardable.} =
  context.addRenderDrawable(
    context.xLayer, parent, rect, drawOps, fillValue, stroke, drawSteps, drawAa
  )

proc addRenderDrawable*(
    context: DrawContext,
    rect: nimkitTypes.Rect,
    drawOps: openArray[DrawableOp],
    fillValue: Fill,
    stroke = RenderStroke(),
    drawSteps = 0'u16,
    drawAa = 0.0'f32,
): FigIdx {.discardable.} =
  context.ensureDefaultRenderSlot()
  context.addRenderDrawable(
    context.xParent, rect, drawOps, fillValue, stroke, drawSteps, drawAa
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
  context.addRenderTranslation(context.xLayer, parent, rect, translation)

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
  context.ensureDefaultRenderSlot()
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
  context.ensureDefaultRenderSlot()
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
  context.ensureDefaultRenderSlot()
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
  context.ensureDefaultRenderSlot()
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
  context.ensureDefaultRenderSlot()
  context.xResources.addImage(image)
  context.addFig(
    layer, parent, imageNode(context.renderRectFor(rect), image, fill(tint.rgba))
  )

proc toFigStrokeCap(value: SvgStrokeCap): StrokeCap =
  case value
  of svcButt: scButt
  of svcRound: scRound
  of svcSquare: scSquare

proc toFigStrokeJoin(value: SvgStrokeJoin): StrokeJoin =
  case value
  of svjMiter: sjMiter
  of svjRound: sjRound
  of svjBevel: sjBevel

proc svgLayerRect(
    target: nimkitTypes.Rect, documentSize: nimkitTypes.Size, frame: nimkitTypes.Rect
): nimkitTypes.Rect =
  let
    scaleX = target.size.width / documentSize.width
    scaleY = target.size.height / documentSize.height
  nimkitTypes.rect(
    target.origin.x + frame.origin.x * scaleX,
    target.origin.y + frame.origin.y * scaleY,
    frame.size.width * scaleX,
    frame.size.height * scaleY,
  )

proc svgLocalPoint(point: nimkitTypes.Point, scaleX, scaleY: float32): Vec2 =
  vec2(point.x * scaleX, point.y * scaleY)

proc svgPathNode(
    target: nimkitTypes.Rect,
    documentSize: nimkitTypes.Size,
    svgLayer: SvgLayer,
    fillValue: Fill,
): Fig =
  let
    scaleX = target.size.width / documentSize.width
    scaleY = target.size.height / documentSize.height
  result = Fig(
    kind: nkDrawable,
    screenBox: target.toFigRect,
    fill: fill(rgba(0, 0, 0, 0)),
    drawStroke: RenderStroke(
      weight: svgLayer.strokeWidth * min(abs(scaleX), abs(scaleY)),
      fill: fillValue,
      cap: svgLayer.strokeCap.toFigStrokeCap(),
      join: svgLayer.strokeJoin.toFigStrokeJoin(),
    ),
  )
  for segment in svgLayer.segments:
    let
      start = segment.start.svgLocalPoint(scaleX, scaleY)
      stop = segment.stop.svgLocalPoint(scaleX, scaleY)
    case segment.kind
    of spsLine:
      result.drawOps.add drawableLine(start, stop)
    of spsQuadratic:
      result.drawOps.add drawableBezier(
        start, segment.control1.svgLocalPoint(scaleX, scaleY), stop
      )
    of spsCubic:
      result.drawOps.add drawableBezier(
        start,
        segment.control1.svgLocalPoint(scaleX, scaleY),
        segment.control2.svgLocalPoint(scaleX, scaleY),
        stop,
      )

proc svgCircleNodes(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    target: nimkitTypes.Rect,
    documentSize: nimkitTypes.Size,
    svgLayer: SvgLayer,
    fillValue: Fill,
    strokeFillValue: Fill,
): FigIdx =
  let
    scaleX = target.size.width / documentSize.width
    scaleY = target.size.height / documentSize.height
    transform = svgLayer.transform
    translation = vec2(
      target.origin.x + transform.tx * scaleX, target.origin.y + transform.ty * scaleY
    )
  var matrix = mat4()
  matrix[0, 0] = transform.a * scaleX
  matrix[0, 1] = transform.b * scaleY
  matrix[1, 0] = transform.c * scaleX
  matrix[1, 1] = transform.d * scaleY

  let transformIndex = context.addFig(
    layer,
    parent,
    Fig(
      kind: nkTransform,
      screenBox: target.toFigRect,
      transform:
        TransformStyle(translation: translation, matrix: matrix, useMatrix: true),
    ),
  )
  var circle = Fig(
    kind: nkDrawable,
    screenBox: bumpy.rect(-1.0'f32, -1.0'f32, 2.0'f32, 2.0'f32),
    fill:
      if svgLayer.drawsFill:
        fillValue
      else:
        fill(rgba(0, 0, 0, 0)),
  )
  if svgLayer.drawsStroke:
    circle.drawStroke =
      RenderStroke(weight: svgLayer.localStrokeWidth, fill: strokeFillValue)
  circle.drawOps.add drawableCircle(vec2(1.0'f32, 1.0'f32), 1.0'f32)
  context.addFig(layer, transformIndex, circle)

type SvgPaintOverride = object
  enabled: bool
  value: Fill

proc layerFill(svgLayer: SvgLayer, paintOverride: SvgPaintOverride): Fill =
  if paintOverride.enabled:
    paintOverride.value
  else:
    fill(svgLayer.paint.rgba)

proc addSvgMtsdfLayers(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    svg: SvgMtsdfResource,
    paintOverride: SvgPaintOverride,
    strokeWeight = 0.0'f32,
    sdThreshold = 0.5'f32,
): FigIdx {.discardable.} =
  if svg.layers.len == 0 or svg.size.width <= 0.0'f32 or svg.size.height <= 0.0'f32:
    return (-1).FigIdx

  context.ensureDefaultRenderSlot()
  let target = context.renderRectFor(rect)
  result = (-1).FigIdx
  for svgLayer in svg.layers:
    let fillValue = svgLayer.layerFill(paintOverride)
    case svgLayer.kind
    of slkMtsdfFill, slkMtsdfStroke:
      if not svgLayer.image.isNil:
        context.xResources.addImage(svgLayer.image)
        let
          layerRect = target.svgLayerRect(svg.size, svgLayer.frame)
          layerStrokeWeight =
            if svgLayer.kind == slkMtsdfStroke:
              svgLayer.mtsdfStrokeWidth *
                min(
                  abs(target.size.width / svg.size.width),
                  abs(target.size.height / svg.size.height),
                )
            else:
              strokeWeight
        result = context.addFig(
          layer,
          parent,
          Fig(
            kind: nkMtsdfImage,
            screenBox: layerRect.toFigRect,
            mtsdfImage: MsdfImageStyle(
              id: svgLayer.image.imageId(),
              fill: fillValue,
              pxRange: svgLayer.pixelRange,
              sdThreshold: sdThreshold,
              strokeWeight: layerStrokeWeight,
            ),
          ),
        )
    of slkStrokePath:
      result =
        context.addFig(layer, parent, target.svgPathNode(svg.size, svgLayer, fillValue))
    of slkCircle:
      let strokeFillValue =
        if paintOverride.enabled:
          paintOverride.value
        else:
          fill(svgLayer.strokePaint.rgba)
      result = context.svgCircleNodes(
        layer, parent, target, svg.size, svgLayer, fillValue, strokeFillValue
      )

proc addSvgMtsdf*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    svg: SvgMtsdfResource,
    strokeWeight = 0.0'f32,
    sdThreshold = 0.5'f32,
): FigIdx {.discardable.} =
  ## Draws an SVG using its source fill and stroke colors.
  context.addSvgMtsdfLayers(
    layer, parent, rect, svg, SvgPaintOverride(), strokeWeight, sdThreshold
  )

proc addSvgMtsdf*(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: nimkitTypes.Rect,
    svg: SvgMtsdfResource,
    fillValue: Fill,
    strokeWeight = 0.0'f32,
    sdThreshold = 0.5'f32,
): FigIdx {.discardable.} =
  ## Draws an SVG with one caller-selected tint replacing its source paints.
  context.addSvgMtsdfLayers(
    layer,
    parent,
    rect,
    svg,
    SvgPaintOverride(enabled: true, value: fillValue),
    strokeWeight,
    sdThreshold,
  )

proc addSvgMtsdf*(
    context: DrawContext,
    rect: nimkitTypes.Rect,
    svg: SvgMtsdfResource,
    strokeWeight = 0.0'f32,
    sdThreshold = 0.5'f32,
): FigIdx {.discardable.} =
  ## Draws an SVG using its source fill and stroke colors.
  context.ensureDefaultRenderSlot()
  context.addSvgMtsdf(
    context.xLayer, context.xParent, rect, svg, strokeWeight, sdThreshold
  )

proc addSvgMtsdf*(
    context: DrawContext,
    rect: nimkitTypes.Rect,
    svg: SvgMtsdfResource,
    fillValue: Fill,
    strokeWeight = 0.0'f32,
    sdThreshold = 0.5'f32,
): FigIdx {.discardable.} =
  ## Draws an SVG with one caller-selected tint replacing its source paints.
  context.ensureDefaultRenderSlot()
  context.addSvgMtsdf(
    context.xLayer, context.xParent, rect, svg, fillValue, strokeWeight, sdThreshold
  )

proc addSelectedText*(
    context: DrawContext,
    rect: nimkitTypes.Rect,
    layout: GlyphArrangement,
    selectedLocation, selectedLength: int,
    selectionColor: nimkitTypes.Color,
): FigIdx {.discardable.} =
  context.ensureDefaultRenderSlot()
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
  context.ensureDefaultRenderSlot()
  let parent =
    if box.focusRingInset < 0.0'f32: context.xViewParent else: context.xParent
  context.addFocusRing(context.xLayer, parent, rect, box)

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
  context.ensureDefaultRenderSlot()
  context.addComboBoxArrow(context.xParent, rect, color)
