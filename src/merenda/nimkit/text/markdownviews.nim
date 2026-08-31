## Native Markdown rendering for NimKit text views.
##
## The renderer converts a CommonMark or GFM syntax tree into attributed NimKit
## text. Raw HTML stays inert, local images can be resolved explicitly, and
## unavailable images use linked alt text without requiring an embedded browser.

import std/[lists, os, strutils, tables, unicode, uri]

import markdown as markdownParser
from markdownpkg/entities import htmlEntityToUtf8

import ../accessibility/accessibility
import ../drawing
import ../foundation/selectors
import ../foundation/types
import ../themes
import ../view/views
import ./texteditors
import ./textstorage
import ./texttypes

export texteditors
export textstorage
export texttypes

type
  MarkdownImageLoader* = proc(url: string): ImageResource {.closure.}
    ## Application-provided resolver for non-local or generated Markdown images.

  MarkdownBlockStyle* = object ## Native panel styling for a Markdown block.
    backgroundColor*: Color ## Fill behind the block contents.
    outlineColor*: Color ## Border drawn around the block.
    outlineWidth*: float32 ## Border width in points.
    cornerRadius*: float32 ## Panel corner radius in points.
    padding*: EdgeInsets ## Space between the text bounds and panel edges.

  MarkdownDialect* = enum ## Built-in parser configurations supported by the viewer.
    mddCommonMark ## CommonMark block and inline syntax.
    mddGitHub ## CommonMark plus tables and strikethrough.

  MarkdownParserConfig* = markdownParser.MarkdownConfig ## Parser extension surface.

  MarkdownStyle* = object ## Complete value-style presentation for a document.
    backgroundColor*: Color ## Document paper color.
    textColor*: Color ## Normal paragraph and list text.
    headingColor*: Color ## Heading and table-header text.
    strongColor*: Color ## Strong inline emphasis.
    emphasisColor*: Color ## Regular inline emphasis.
    linkColor*: Color ## Linked text and image descriptions.
    codeColor*: Color ## Inline and fenced code text.
    quoteColor*: Color ## Block quote contents.
    mutedColor*: Color ## Raw HTML and code-language labels.
    ruleColor*: Color ## Quotes, table separators, and thematic breaks.
    bodyFontName*: string ## Proportional document font.
    emphasisFontName*: string ## Bold proportional font for inline emphasis.
    codeFontName*: string ## Monospace font for code and tables.
    emphasisCodeFontName*: string ## Bold monospace font for emphasized table text.
    codeBlockStyle*: MarkdownBlockStyle ## Fenced and indented code-block panel.
    maximumImageSize*: Size
      ## Largest rendered image size; non-positive axes are unlimited.
    bodyFontSize*: float32 ## Base text size in points.
    headingFontSizes*: array[6, float32] ## Sizes for heading levels one through six.
    documentInsets*: EdgeInsets ## Scrollable text padding.
    listIndent*: int ## Spaces added for each nested list level.
    quotePrefix*: string ## Marker prepended to quote blocks.
    imagePrefix*: string ## Marker prepended to linked image alt text.
    thematicBreak*: string ## Native text used for horizontal rules.

  MarkdownView* = ref object of TextEditor ## Scrollable, selectable Markdown document.
    xMarkdown: string
    xMarkdownStyle: MarkdownStyle
    xMarkdownConfig: MarkdownParserConfig
    xMarkdownRoot: markdownParser.Document
    xImageBasePath: string
    xImageLoader: MarkdownImageLoader
    xImageCache: Table[string, ImageResource]

  MarkdownImagePresentation = object
    range: TextRange
    image: ImageResource
    displaySize: Size

  MarkdownTextView = ref object of TextView
    codeBlockRanges: seq[TextRange]
    codeBlockStyle: MarkdownBlockStyle
    markdownImages: seq[MarkdownImagePresentation]

  MarkdownDocument = object
    storage: TextStorage
    codeBlockRanges: seq[TextRange]
    images: seq[MarkdownImagePresentation]

  MarkdownBuilder = object
    text: string
    runeLength: int
    runs: seq[TextAttributeRun]
    codeBlockRanges: seq[TextRange]
    images: seq[MarkdownImagePresentation]
    style: MarkdownStyle
    imageLoader: MarkdownImageLoader

func initMarkdownBlockStyle*(): MarkdownBlockStyle =
  ## Returns the default light code-block panel presentation.
  MarkdownBlockStyle(
    backgroundColor: color(0.90, 0.92, 0.95, 1.0),
    outlineColor: color(0.68, 0.72, 0.79, 1.0),
    outlineWidth: 1.0'f32,
    cornerRadius: 6.0'f32,
    padding: insets(6.0'f32, 8.0'f32),
  )

func boldFontVariant(fontName: string): string =
  if fontName.len == 0:
    return
  let parts = fontName.splitFile()
  var stem = parts.name
  let lowerStem = stem.toLowerAscii()
  for suffix in ["-bold", "_bold", " bold", "bold"]:
    if lowerStem.endsWith(suffix):
      return fontName
  for suffix in ["-regular", "_regular", " regular", "regular"]:
    if lowerStem.endsWith(suffix):
      stem.setLen(stem.len - suffix.len)
      break
  parts.dir / (stem & "-Bold" & parts.ext)

proc initMarkdownStyle*(): MarkdownStyle =
  ## Returns the light paper-style default presentation.
  let
    bodyFontName = defaultFontName(frUI)
    codeFontName = defaultFontName(frMonospace)
  MarkdownStyle(
    backgroundColor: color(0.965, 0.97, 0.98, 1.0),
    textColor: color(0.12, 0.14, 0.18, 1.0),
    headingColor: color(0.06, 0.09, 0.15, 1.0),
    strongColor: color(0.04, 0.07, 0.13, 1.0),
    emphasisColor: color(0.42, 0.22, 0.58, 1.0),
    linkColor: color(0.06, 0.36, 0.72, 1.0),
    codeColor: color(0.66, 0.16, 0.28, 1.0),
    quoteColor: color(0.32, 0.38, 0.48, 1.0),
    mutedColor: color(0.43, 0.48, 0.56, 1.0),
    ruleColor: color(0.58, 0.62, 0.68, 1.0),
    bodyFontName: bodyFontName,
    emphasisFontName: bodyFontName.boldFontVariant(),
    codeFontName: codeFontName,
    emphasisCodeFontName: codeFontName.boldFontVariant(),
    codeBlockStyle: initMarkdownBlockStyle(),
    maximumImageSize: initSize(640.0'f32, 420.0'f32),
    bodyFontSize: 14.0'f32,
    headingFontSizes: [30.0'f32, 25.0'f32, 21.0'f32, 18.0'f32, 16.0'f32, 14.0'f32],
    documentInsets: insets(24.0, 28.0, 24.0, 28.0),
    listIndent: 2,
    quotePrefix: "│ ",
    imagePrefix: "▧ ",
    thematicBreak:
      "────────────────────────────────────────",
  )

proc initMarkdownParserConfig*(dialect = mddGitHub): MarkdownParserConfig =
  ## Creates an independent parser configuration for `dialect`.
  case dialect
  of mddCommonMark:
    markdownParser.initCommonmarkConfig()
  of mddGitHub:
    markdownParser.initGfmConfig()

proc resolvedConfig(config: MarkdownParserConfig): MarkdownParserConfig =
  if config.isNil:
    initMarkdownParserConfig()
  else:
    config

func scaledDown(size, maximumSize: Size): Size =
  if size.width <= 0.0'f32 or size.height <= 0.0'f32:
    return
  var scale = 1.0'f32
  if maximumSize.width > 0.0'f32:
    scale = min(scale, maximumSize.width / size.width)
  if maximumSize.height > 0.0'f32:
    scale = min(scale, maximumSize.height / size.height)
  initSize(size.width * scale, size.height * scale)

func hasUrlScheme(value: string): bool =
  let colon = value.find(':')
  if colon <= 0 or not value[0].isAlphaAscii:
    return
  for index in 1 ..< colon:
    if not (value[index].isAlphaNumeric or value[index] in {'+', '-', '.'}):
      return
  true

func imageUrlPath(value: string): string =
  let suffix = value.find({'?', '#'})
  if suffix < 0:
    value
  else:
    value[0 ..< suffix]

proc localImagePath(url, basePath: string): string =
  let source = url.imageUrlPath()
  if source.len == 0:
    return
  if source.startsWith("file://"):
    return decodeUrl(source[7 ..^ 1], decodePlus = false)
  if source.hasUrlScheme():
    return
  let path = decodeUrl(source, decodePlus = false)
  if path.isAbsolute:
    path
  elif basePath.len > 0:
    basePath / path
  else:
    ""

func imageContentType(url: string): string =
  case splitFile(url.imageUrlPath()).ext.toLowerAscii()
  of ".png": "image/png"
  of ".jpg", ".jpeg": "image/jpeg"
  of ".gif": "image/gif"
  of ".webp": "image/webp"
  of ".bmp": "image/bmp"
  of ".tif", ".tiff": "image/tiff"
  else: "image/*"

func bodyAttributes(style: MarkdownStyle): TextAttributes =
  defaultTextAttributes(
    style.textColor, max(style.bodyFontSize, 1.0'f32), style.bodyFontName
  )

func codeAttributes(style: MarkdownStyle, base: TextAttributes): TextAttributes =
  result = base
  result.foregroundColor = style.codeColor
  result.fontName = style.codeFontName

func mutedCodeAttributes(style: MarkdownStyle, base: TextAttributes): TextAttributes =
  result = base
  result.foregroundColor = style.mutedColor
  result.fontName = style.codeFontName
  result.fontSize = max(base.fontSize - 1.0'f32, 1.0'f32)

func emphasizedFontName(style: MarkdownStyle, baseFontName: string): string =
  let configured =
    if baseFontName in [style.codeFontName, style.emphasisCodeFontName]:
      style.emphasisCodeFontName
    else:
      style.emphasisFontName
  if configured.len > 0:
    configured
  else:
    baseFontName.boldFontVariant()

proc add(builder: var MarkdownBuilder, value: string, attributes: TextAttributes) =
  let length = value.runeLen
  if length == 0:
    return
  let start = builder.runeLength
  builder.text.add value
  builder.runeLength += length
  if builder.runs.len > 0 and builder.runs[^1].attributes == attributes and
      builder.runs[^1].range.maxIndex == start:
    builder.runs[^1].range.length =
      (int(builder.runs[^1].range.length) + length).Natural
  else:
    builder.runs.add TextAttributeRun(
      range: initTextRange(start, length), attributes: attributes
    )

proc addBlockBreak(builder: var MarkdownBuilder, attributes: TextAttributes) =
  if builder.text.len == 0 or builder.text.endsWith("\n\n"):
    return
  if builder.text.endsWith("\n"):
    builder.add("\n", attributes)
  else:
    builder.add("\n\n", attributes)

proc add(builder: var MarkdownBuilder, rendered: sink MarkdownBuilder) =
  let offset = builder.runeLength
  builder.text.add rendered.text
  builder.runeLength += rendered.runeLength
  for run in rendered.runs:
    let shifted = TextAttributeRun(
      range: initTextRange(offset + int(run.range.location), int(run.range.length)),
      attributes: run.attributes,
    )
    if builder.runs.len > 0 and builder.runs[^1].attributes == shifted.attributes and
        builder.runs[^1].range.maxIndex == int(shifted.range.location):
      builder.runs[^1].range.length =
        (int(builder.runs[^1].range.length) + int(shifted.range.length)).Natural
    else:
      builder.runs.add shifted
  for range in rendered.codeBlockRanges:
    builder.codeBlockRanges.add initTextRange(
      offset + int(range.location), int(range.length)
    )
  for presentation in rendered.images:
    var shifted = presentation
    shifted.range = initTextRange(
      offset + int(presentation.range.location), int(presentation.range.length)
    )
    builder.images.add shifted

proc renderInline(
  builder: var MarkdownBuilder, token: markdownParser.Token, attributes: TextAttributes
)

proc renderInlineChildren(
    builder: var MarkdownBuilder,
    token: markdownParser.Token,
    attributes: TextAttributes,
) =
  for child in token.children:
    builder.renderInline(child, attributes)

proc renderImage(
    builder: var MarkdownBuilder,
    token: markdownParser.Image,
    attributes: TextAttributes,
) =
  var image: ImageResource
  if not builder.imageLoader.isNil:
    try:
      image = builder.imageLoader(token.url)
    except CatchableError:
      discard

  if image.isNil or image.size().width <= 0.0'f32 or image.size().height <= 0.0'f32:
    var fallbackAttributes = attributes
    fallbackAttributes.foregroundColor = builder.style.linkColor
    fallbackAttributes.link = token.url
    builder.add(builder.style.imagePrefix, fallbackAttributes)
    if token.children.head.isNil:
      builder.add(token.alt, fallbackAttributes)
    else:
      builder.renderInlineChildren(token, fallbackAttributes)
    return

  if builder.text.len > 0 and not builder.text.endsWith("\n"):
    builder.add("\n", attributes)

  let
    displaySize = image.size().scaledDown(builder.style.maximumImageSize)
    start = builder.runeLength
    sourcePath = token.url.imageUrlPath()
    parts = splitFile(sourcePath)
  var imageAttributes = attributes
  imageAttributes.foregroundColor = color(0.0, 0.0, 0.0, 0.0)
  imageAttributes.fontSize = max(displaySize.height, builder.style.bodyFontSize)
  imageAttributes.link = token.url
  imageAttributes.attachment = initTextAttachment(
    identifier = "markdown-image:" & token.url,
    contentType = token.url.imageContentType(),
    fileName = parts.name & parts.ext,
    fileUrl = token.url,
    size = displaySize,
    metadata = [
      TextMetadataItem(key: "alt", value: token.alt),
      TextMetadataItem(key: "title", value: token.title),
    ],
  )
  builder.add(" ", imageAttributes)
  builder.images.add MarkdownImagePresentation(
    range: initTextRange(start, 1), image: image, displaySize: displaySize
  )
  builder.add("\n", attributes)

proc renderInline(
    builder: var MarkdownBuilder,
    token: markdownParser.Token,
    attributes: TextAttributes,
) =
  if token.isNil:
    return
  if token of markdownParser.Text or token of markdownParser.Escape:
    builder.add(token.doc, attributes)
  elif token of markdownParser.HtmlEntity:
    let decoded = htmlEntityToUtf8(token.doc)
    builder.add(if decoded.len > 0: decoded else: token.doc, attributes)
  elif token of markdownParser.SoftBreak or token of markdownParser.HardBreak:
    builder.add("\n", attributes)
  elif token of markdownParser.CodeSpan:
    builder.add(token.doc, builder.style.codeAttributes(attributes))
  elif token of markdownParser.Strikethrough:
    var strikeAttributes = attributes
    strikeAttributes.strikethroughStyle = tldsSingle
    builder.add(token.doc, strikeAttributes)
  elif token of markdownParser.Em:
    var emphasisAttributes = attributes
    emphasisAttributes.foregroundColor = builder.style.emphasisColor
    emphasisAttributes.fontName =
      builder.style.emphasizedFontName(emphasisAttributes.fontName)
    builder.renderInlineChildren(token, emphasisAttributes)
  elif token of markdownParser.Strong:
    var strongAttributes = attributes
    strongAttributes.foregroundColor = builder.style.strongColor
    strongAttributes.fontName =
      builder.style.emphasizedFontName(strongAttributes.fontName)
    builder.renderInlineChildren(token, strongAttributes)
  elif token of markdownParser.Link:
    var linkAttributes = attributes
    linkAttributes.foregroundColor = builder.style.linkColor
    linkAttributes.link = markdownParser.Link(token).url
    linkAttributes.underlineStyle = tldsSingle
    builder.renderInlineChildren(token, linkAttributes)
  elif token of markdownParser.AutoLink:
    let link = markdownParser.AutoLink(token)
    var linkAttributes = attributes
    linkAttributes.foregroundColor = builder.style.linkColor
    linkAttributes.link = link.url
    linkAttributes.underlineStyle = tldsSingle
    builder.add(link.text, linkAttributes)
  elif token of markdownParser.Image:
    builder.renderImage(markdownParser.Image(token), attributes)
  elif token of markdownParser.InlineHtml:
    builder.add(token.doc, builder.style.mutedCodeAttributes(attributes))
  elif not token.children.head.isNil:
    builder.renderInlineChildren(token, attributes)
  else:
    builder.add(token.doc, attributes)

proc renderBlock(
  builder: var MarkdownBuilder, token: markdownParser.Token, attributes: TextAttributes
)

proc renderList(
  builder: var MarkdownBuilder,
  token: markdownParser.Token,
  depth: int,
  attributes: TextAttributes,
)

proc renderListItem(
    builder: var MarkdownBuilder,
    item: markdownParser.Li,
    marker: string,
    depth: int,
    attributes: TextAttributes,
) =
  let
    indentation = " ".repeat(max(depth * builder.style.listIndent, 0))
    continuation = indentation & " ".repeat(marker.runeLen + 1)
  var markerAttributes = attributes
  markerAttributes.foregroundColor = builder.style.mutedColor
  builder.add(indentation & marker & " ", markerAttributes)

  var first = true
  for child in item.children:
    if child of markdownParser.Ul or child of markdownParser.Ol:
      builder.add("\n", attributes)
      builder.renderList(child, depth + 1, attributes)
    else:
      if not first:
        builder.add("\n" & continuation, attributes)
      builder.renderBlock(child, attributes)
    first = false

proc renderList(
    builder: var MarkdownBuilder,
    token: markdownParser.Token,
    depth: int,
    attributes: TextAttributes,
) =
  var index =
    if token of markdownParser.Ol:
      markdownParser.Ol(token).start
    else:
      1
  var first = true
  for child in token.children:
    if child of markdownParser.Li:
      if not first:
        builder.add("\n", attributes)
      let marker =
        if token of markdownParser.Ol:
          $index & "."
        else:
          "•"
      builder.renderListItem(markdownParser.Li(child), marker, depth, attributes)
      inc index
      first = false

proc childCount(token: markdownParser.Token): int =
  for child in token.children:
    discard child
    inc result

proc renderTableRow(
    builder: var MarkdownBuilder, row: markdownParser.Token, attributes: TextAttributes
) =
  var first = true
  for cell in row.children:
    if not first:
      var separatorAttributes = attributes
      separatorAttributes.foregroundColor = builder.style.ruleColor
      builder.add("  │  ", separatorAttributes)
    builder.renderInlineChildren(cell, attributes)
    first = false

proc renderTable(
    builder: var MarkdownBuilder,
    table: markdownParser.Token,
    attributes: TextAttributes,
) =
  var tableAttributes = attributes
  tableAttributes.fontName = builder.style.codeFontName
  var wroteRow = false
  for section in table.children:
    let isHeader = section of markdownParser.THead
    for row in section.children:
      if wroteRow:
        builder.add("\n", tableAttributes)
      var rowAttributes = tableAttributes
      if isHeader:
        rowAttributes.foregroundColor = builder.style.headingColor
        rowAttributes.underlineStyle = tldsSingle
      builder.renderTableRow(row, rowAttributes)
      if isHeader:
        var ruleAttributes = tableAttributes
        ruleAttributes.foregroundColor = builder.style.ruleColor
        let columns = max(row.childCount(), 1)
        builder.add("\n" & "────".repeat(columns), ruleAttributes)
      wroteRow = true

proc renderContainer(
    builder: var MarkdownBuilder,
    token: markdownParser.Token,
    attributes: TextAttributes,
) =
  var wroteBlock = false
  for child in token.children:
    var rendered =
      MarkdownBuilder(style: builder.style, imageLoader: builder.imageLoader)
    rendered.renderBlock(child, attributes)
    if rendered.text.len > 0:
      if wroteBlock:
        builder.addBlockBreak(attributes)
      builder.add(rendered)
      wroteBlock = true

proc renderBlockquote(
    builder: var MarkdownBuilder,
    quote: markdownParser.Token,
    attributes: TextAttributes,
) =
  var quoteAttributes = attributes
  quoteAttributes.foregroundColor = builder.style.quoteColor
  var prefixAttributes = quoteAttributes
  prefixAttributes.foregroundColor = builder.style.ruleColor

  var quoted = MarkdownBuilder(style: builder.style, imageLoader: builder.imageLoader)
  quoted.renderContainer(quote, quoteAttributes)
  if quoted.text.len == 0:
    builder.add(builder.style.quotePrefix, prefixAttributes)
    return

  let runes = quoted.text.toRunes()
  var
    atLineStart = true
    runIndex = 0
    sourceToDestination = newSeq[int](runes.len + 1)
  for index, rune in runes:
    while runIndex < quoted.runs.high and index >= quoted.runs[runIndex].range.maxIndex:
      inc runIndex
    if atLineStart:
      builder.add(builder.style.quotePrefix, prefixAttributes)
      atLineStart = false
    sourceToDestination[index] = builder.runeLength
    builder.add($rune, quoted.runs[runIndex].attributes)
    sourceToDestination[index + 1] = builder.runeLength
    if rune == Rune('\n'):
      atLineStart = true

  for range in quoted.codeBlockRanges:
    let
      start = sourceToDestination[int(range.location)]
      stop = sourceToDestination[range.maxIndex]
    builder.codeBlockRanges.add initTextRange(start, stop - start)
  for presentation in quoted.images:
    var mapped = presentation
    let
      start = sourceToDestination[int(presentation.range.location)]
      stop = sourceToDestination[presentation.range.maxIndex]
    mapped.range = initTextRange(start, stop - start)
    builder.images.add mapped

proc renderBlock(
    builder: var MarkdownBuilder,
    token: markdownParser.Token,
    attributes: TextAttributes,
) =
  if token.isNil:
    return
  if token of markdownParser.Paragraph:
    builder.renderInlineChildren(token, attributes)
  elif token of markdownParser.Heading:
    let heading = markdownParser.Heading(token)
    var headingAttributes = attributes
    headingAttributes.foregroundColor = builder.style.headingColor
    let level = min(max(heading.level, 1), 6)
    headingAttributes.fontSize = max(builder.style.headingFontSizes[level - 1], 1.0'f32)
    builder.renderInlineChildren(token, headingAttributes)
  elif token of markdownParser.CodeBlock:
    let code = markdownParser.CodeBlock(token)
    let blockStart = builder.runeLength
    var codeAttributes = builder.style.codeAttributes(attributes)
    codeAttributes.backgroundColor = builder.style.codeBlockStyle.backgroundColor
    if code.info.len > 0:
      var infoAttributes = builder.style.mutedCodeAttributes(attributes)
      infoAttributes.backgroundColor = builder.style.codeBlockStyle.backgroundColor
      builder.add("[" & code.info & "]\n", infoAttributes)
    builder.add(code.doc.strip(chars = {'\n'}), codeAttributes)
    let blockLength = builder.runeLength - blockStart
    if blockLength > 0:
      builder.codeBlockRanges.add initTextRange(blockStart, blockLength)
  elif token of markdownParser.ThematicBreak:
    var ruleAttributes = attributes
    ruleAttributes.foregroundColor = builder.style.ruleColor
    builder.add(builder.style.thematicBreak, ruleAttributes)
  elif token of markdownParser.Blockquote:
    builder.renderBlockquote(token, attributes)
  elif token of markdownParser.Ul or token of markdownParser.Ol:
    builder.renderList(token, 0, attributes)
  elif token of markdownParser.HtmlTable:
    builder.renderTable(token, attributes)
  elif token of markdownParser.HtmlBlock:
    builder.add(
      token.doc.strip(chars = {'\n'}), builder.style.mutedCodeAttributes(attributes)
    )
  elif $token == "":
    # Reference-definition nodes intentionally have no rendered representation.
    discard
  elif not token.children.head.isNil:
    builder.renderContainer(token, attributes)
  else:
    builder.add(token.doc, attributes)

proc toMarkdownDocument(builder: sink MarkdownBuilder): MarkdownDocument =
  MarkdownDocument(
    storage: newTextStorage(builder.text, builder.runs),
    codeBlockRanges: builder.codeBlockRanges,
    images: builder.images,
  )

proc parseMarkdownRoot(
    source: string, config: MarkdownParserConfig
): markdownParser.Document =
  result = markdownParser.Document()
  discard markdownParser.markdown(source, config.resolvedConfig(), result)

proc markdownDocument(
    root: markdownParser.Token,
    style = initMarkdownStyle(),
    imageLoader: MarkdownImageLoader = nil,
): MarkdownDocument =
  var builder = MarkdownBuilder(style: style, imageLoader: imageLoader)
  let attributes = style.bodyAttributes()
  builder.renderContainer(root, attributes)
  builder.toMarkdownDocument()

proc markdownDocument(
    source: string,
    style = initMarkdownStyle(),
    config: MarkdownParserConfig = nil,
    imageLoader: MarkdownImageLoader = nil,
): MarkdownDocument =
  source.parseMarkdownRoot(config).markdownDocument(style, imageLoader)

proc markdownTextStorage*(
    source: string, style = initMarkdownStyle(), config: MarkdownParserConfig = nil
): TextStorage =
  ## Parses `source` and returns native attributed text without creating a view.
  ## A nil configuration selects GFM so tables and strikethrough work by default.
  source.markdownDocument(style, config).storage

proc codeBlockRect(
    textView: MarkdownTextView, range: TextRange, padding: EdgeInsets
): Rect =
  for lineRect in textView.selectionRects(range):
    if result.isEmpty:
      result = lineRect
    else:
      result = result.union(lineRect)
  if not result.isEmpty:
    result =
      result.inset(insets(-padding.top, -padding.left, -padding.bottom, -padding.right))

proc imageRect(
    textView: MarkdownTextView, presentation: MarkdownImagePresentation
): Rect =
  var anchor: Rect
  for selectionRect in textView.selectionRects(presentation.range):
    if anchor.isEmpty:
      anchor = selectionRect
    else:
      anchor = anchor.union(selectionRect)
  if anchor.isEmpty:
    return
  let
    rightInset = textView.textContainer().insets.right
    availableSize = initSize(
      max(textView.bounds.maxX - rightInset - anchor.origin.x, 0.0'f32),
      anchor.size.height,
    )
    drawSize = presentation.displaySize.scaledDown(availableSize)
  if drawSize.width <= 0.0'f32 or drawSize.height <= 0.0'f32:
    return
  rect(
    anchor.origin.x,
    anchor.origin.y + max(anchor.size.height - drawSize.height, 0.0'f32) / 2.0'f32,
    drawSize.width,
    drawSize.height,
  )

protocol MarkdownTextViewDrawing of ViewDrawingProtocol:
  method draw(textView: MarkdownTextView, context: DrawContext) =
    let style = textView.codeBlockStyle
    if style.backgroundColor.a > 0.0'f32 or
        (style.outlineColor.a > 0.0'f32 and style.outlineWidth > 0.0'f32):
      for range in textView.codeBlockRanges:
        let blockRect = textView.codeBlockRect(range, style.padding)
        if not blockRect.isEmpty:
          discard context.addRenderRectangle(
            context.renderRectFor(blockRect),
            fill(style.backgroundColor),
            style.outlineColor,
            max(style.outlineWidth, 0.0'f32),
            max(style.cornerRadius, 0.0'f32),
          )
    for presentation in textView.markdownImages:
      let rect = textView.imageRect(presentation)
      if not rect.isEmpty:
        discard context.addImage(rect, presentation.image)
    TextView(textView).drawTextViewContents(context)

proc applyMarkdownDocument(view: MarkdownView, document: sink MarkdownDocument) =
  let textView = MarkdownTextView(view.textView())
  textView.codeBlockRanges = document.codeBlockRanges
  textView.codeBlockStyle = view.xMarkdownStyle.codeBlockStyle
  textView.markdownImages = document.images
  view.textStorage = document.storage
  textView.needsDisplay = true

proc applyMarkdownStyle(view: MarkdownView) =
  view.textInsets = view.xMarkdownStyle.documentInsets
  view.backgroundColor = view.xMarkdownStyle.backgroundColor
  view.textColor = view.xMarkdownStyle.textColor
  view.textView().backgroundColor = view.xMarkdownStyle.backgroundColor
  view.scrollView().drawsBackground = false

proc loadMarkdownImage(view: MarkdownView, url: string): ImageResource =
  let key = view.xImageBasePath & "\x00" & url
  if key in view.xImageCache:
    return view.xImageCache[key]
  try:
    if not view.xImageLoader.isNil:
      result = view.xImageLoader(url)
    else:
      let path = url.localImagePath(view.xImageBasePath)
      if path.len > 0 and path.fileExists:
        result = newImageResourceFromFile(path, name = path, cachePolicy = icpBySize)
  except CatchableError:
    discard
  if not result.isNil:
    view.xImageCache[key] = result

proc renderMarkdownDocument(
    view: MarkdownView, root: markdownParser.Token, style: MarkdownStyle
): MarkdownDocument =
  let loader: MarkdownImageLoader = proc(url: string): ImageResource =
    view.loadMarkdownImage(url)
  root.markdownDocument(style, loader)

proc editable*(view: MarkdownView): bool =
  ## Markdown views are deliberately read-only.
  discard view

proc selectable*(view: MarkdownView): bool =
  ## Rendered Markdown remains selectable and copyable.
  discard view
  true

proc markdown*(view: MarkdownView): string =
  ## Returns the source Markdown last rendered by `view`.
  view.xMarkdown

proc `markdown=`*(view: MarkdownView, source: string) =
  ## Parses and atomically replaces the displayed document.
  if view.xMarkdown == source:
    return
  let
    root = source.parseMarkdownRoot(view.xMarkdownConfig)
    document = view.renderMarkdownDocument(root, view.xMarkdownStyle)
  view.xMarkdown = source
  view.xMarkdownRoot = root
  view.applyMarkdownDocument(document)

proc imageBasePath*(view: MarkdownView): string =
  ## Returns the directory used to resolve relative local image destinations.
  view.xImageBasePath

proc `imageBasePath=`*(view: MarkdownView, basePath: string) =
  ## Changes the local image directory and rerenders the current document.
  if view.xImageBasePath == basePath:
    return
  view.xImageBasePath = basePath
  view.xImageCache.clear()
  view.applyMarkdownDocument(
    view.renderMarkdownDocument(view.xMarkdownRoot, view.xMarkdownStyle)
  )

proc imageLoader*(view: MarkdownView): MarkdownImageLoader =
  ## Returns the optional application-provided image resolver.
  view.xImageLoader

proc `imageLoader=`*(view: MarkdownView, loader: MarkdownImageLoader) =
  ## Changes the image resolver and rerenders the current document.
  view.xImageLoader = loader
  view.xImageCache.clear()
  view.applyMarkdownDocument(
    view.renderMarkdownDocument(view.xMarkdownRoot, view.xMarkdownStyle)
  )

proc markdownStyle*(view: MarkdownView): MarkdownStyle =
  ## Returns a copy of the current document presentation.
  view.xMarkdownStyle

proc `markdownStyle=`*(view: MarkdownView, style: MarkdownStyle) =
  ## Applies `style` and rerenders the current source.
  if view.xMarkdownStyle == style:
    return
  let document = view.renderMarkdownDocument(view.xMarkdownRoot, style)
  view.xMarkdownStyle = style
  view.applyMarkdownStyle()
  view.applyMarkdownDocument(document)

proc markdownConfig*(view: MarkdownView): MarkdownParserConfig =
  ## Returns the active parser configuration.
  view.xMarkdownConfig

proc `markdownConfig=`*(view: MarkdownView, config: MarkdownParserConfig) =
  ## Applies `config` and reparses the current source; nil selects GFM.
  let resolved = config.resolvedConfig()
  if view.xMarkdownConfig == resolved:
    return
  let
    root = view.xMarkdown.parseMarkdownRoot(resolved)
    document = view.renderMarkdownDocument(root, view.xMarkdownStyle)
  view.xMarkdownConfig = resolved
  view.xMarkdownRoot = root
  view.applyMarkdownDocument(document)

proc initMarkdownViewFields*(
    view: MarkdownView,
    source = "",
    frame: Rect = AutoRect,
    style = initMarkdownStyle(),
    config: MarkdownParserConfig = nil,
    imageBasePath = "",
    imageLoader: MarkdownImageLoader = nil,
) =
  ## Initializes a custom `MarkdownView` subtype.
  let textView = MarkdownTextView()
  textView.initTextViewFields()
  discard textView.withProtocol(MarkdownTextViewDrawing)
  initTextEditorFields(
    view, frame = frame, richText = true, wraps = true, textView = textView
  )
  view.xMarkdownStyle = style
  view.xMarkdownConfig = config.resolvedConfig()
  view.xMarkdownRoot = source.parseMarkdownRoot(view.xMarkdownConfig)
  view.xImageBasePath = imageBasePath
  view.xImageLoader = imageLoader
  view.xImageCache = initTable[string, ImageResource]()
  view.xMarkdown = source
  view.editable = false
  view.selectable = true
  view.allowsUndo = false
  view.scrollView().borderType = svbNoBorder
  view.accessibilityLabel = "Markdown document"
  view.applyMarkdownStyle()
  view.applyMarkdownDocument(view.renderMarkdownDocument(view.xMarkdownRoot, style))

proc newMarkdownView*(
    source = "",
    frame: Rect = AutoRect,
    style = initMarkdownStyle(),
    config: MarkdownParserConfig = nil,
    imageBasePath = "",
    imageLoader: MarkdownImageLoader = nil,
): MarkdownView =
  ## Creates a scrollable, selectable, read-only Markdown document view.
  result = MarkdownView()
  result.initMarkdownViewFields(
    source, frame, style, config, imageBasePath, imageLoader
  )
