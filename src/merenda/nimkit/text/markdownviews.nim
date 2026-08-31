## Native Markdown rendering for NimKit text views.
##
## CommonMark and GFM parsing runs on a Sigils pool worker, then the complete AST
## moves back to the view's owning thread for incremental attributed-text
## construction between application frames. HTML image tags share the native
## Markdown image path; other raw HTML stays inert. Local images resolve
## explicitly, remote images load through a Chronos worker, and unavailable
## images use linked alt text.

import std/[lists, monotimes, os, strutils, tables, times, unicode]

import markdown as markdownParser
from markdownpkg/entities import htmlEntityToUtf8
import sigils/[core, threads]
import threading/smartptrs

import ../accessibility/accessibility
import ../drawing
import ../foundation/mainthreadwork
import ../foundation/selectors
import ../foundation/types
import ../foundation/urlassets
import ../foundation/urls
import ../themes
import ../view/views
import ./markdownhtmlimages
import ./markdownparsing
import ./texteditors
import ./textstorage
import ./texttypes

export texteditors
export textstorage
export texttypes

const MarkdownImageBlockSpacing = 12.0'f32
  ## Fixed separation around image attachment lines, independent of image size.

type
  MarkdownImageLoader* = proc(url: string): ImageResource {.closure.}
    ## Application-provided resolver for non-local or generated Markdown images.

  MarkdownImageContentTypeLoader = proc(url: string): string {.closure.}

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
    imageContentTypeLoader: MarkdownImageContentTypeLoader

  MarkdownRenderJob = object
    generation: uint64
    rootGeneration: uint64
    root: markdownParser.Token ## Retains the complete AST while its cursor advances.
    nextBlock: DoublyLinkedNode[markdownParser.Token]
    builder: MarkdownBuilder
    attributes: TextAttributes
    wroteBlock: bool
    chunkCount: int
    maximumChunkDuration: Duration

  MarkdownView* = ref object of TextEditor ## Scrollable, selectable Markdown document.
    xMarkdown: string
    xMarkdownStyle: MarkdownStyle
    xMarkdownConfig: MarkdownParserConfig
    xMarkdownRoot: markdownParser.Document
    xMarkdownRootGeneration: uint64
    xMarkdownParseWorker: AgentProxy[MarkdownParseWorker]
    xMarkdownGeneration: uint64
    xActiveMarkdownGeneration: uint64
    xPendingMarkdownCompletionGeneration: uint64
    xMarkdownParseWorkerThreadId: int
    xMarkdownParseError: string
    xMarkdownRenderGeneration: uint64
    xActiveMarkdownRenderGeneration: uint64
    xMarkdownRenderJob: MarkdownRenderJob
    xMarkdownRenderChunkCount: int
    xMarkdownMaximumRenderChunkDuration: Duration
    xImageBasePath: string
    xImageLoader: MarkdownImageLoader
    xUrlAssetLoader: UrlAssetLoader
    xImageCache: Table[string, ImageResource]
    xImageMediaTypes: Table[string, string]
    xPendingUrlAssets: Table[string, UrlAssetHandle]

const
  MarkdownRenderBlocksPerChunk = 16
  MarkdownRenderChunkBudgetNanoseconds = 4_000_000'i64

var defaultMarkdownUrlAssetLoader {.threadvar.}: UrlAssetLoader

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

func resolvedImageSize(imageSize, requestedSize: Size): Size =
  if requestedSize.width > 0.0'f32 and requestedSize.height > 0.0'f32:
    requestedSize
  elif requestedSize.width > 0.0'f32:
    initSize(
      requestedSize.width, imageSize.height * requestedSize.width / imageSize.width
    )
  elif requestedSize.height > 0.0'f32:
    initSize(
      imageSize.width * requestedSize.height / imageSize.height, requestedSize.height
    )
  else:
    imageSize

proc imageLineFontSize(attributes: TextAttributes, imageHeight: float32): float32 =
  let
    probeFontSize = max(attributes.fontSize, 1.0'f32)
    probeStyle = TextStyle(
      color: attributes.foregroundColor,
      fontName: attributes.fontName,
      fontSize: probeFontSize,
      language: attributes.language,
    )
    probeLineHeight = textNaturalSize("", probeStyle).height
  if probeLineHeight <= 0.0'f32:
    return max(imageHeight + MarkdownImageBlockSpacing, probeFontSize)
  let targetLineHeight = max(imageHeight + MarkdownImageBlockSpacing, probeLineHeight)
  probeFontSize * targetLineHeight / probeLineHeight

proc resolvedImageContentType(builder: MarkdownBuilder, url: string): string =
  if not builder.imageContentTypeLoader.isNil:
    result = builder.imageContentTypeLoader(url).normalizedMediaType()
  if not result.isImageMediaType():
    result = initUrl(url).mediaType()
  if not result.isImageMediaType():
    result = "image/*"

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
    requestedSize = Size(),
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
    displaySize = image.size().resolvedImageSize(requestedSize).scaledDown(
        builder.style.maximumImageSize
      )
    start = builder.runeLength
    fileName = initUrl(token.url).lastPathComponent()
  var imageAttributes = attributes
  imageAttributes.foregroundColor = color(0.0, 0.0, 0.0, 0.0)
  imageAttributes.fontSize = attributes.imageLineFontSize(displaySize.height)
  imageAttributes.link = token.url
  imageAttributes.attachment = initTextAttachment(
    identifier = "markdown-image:" & token.url,
    contentType = builder.resolvedImageContentType(token.url),
    fileName = fileName,
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

proc renderHtmlImages(
    builder: var MarkdownBuilder, html: string, attributes: TextAttributes
): bool =
  var htmlImages: seq[MarkdownHtmlImage]
  if not html.parseMarkdownHtmlImages(htmlImages):
    return
  for htmlImage in htmlImages:
    let image = markdownParser.Image(
      url: htmlImage.url, alt: htmlImage.alt, title: htmlImage.title
    )
    builder.renderImage(image, attributes, initSize(htmlImage.width, htmlImage.height))
  true

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
    if not builder.renderHtmlImages(token.doc, attributes):
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

proc renderContainerChild(
    builder: var MarkdownBuilder,
    child: markdownParser.Token,
    attributes: TextAttributes,
    wroteBlock: var bool,
) =
  var rendered = MarkdownBuilder(
    style: builder.style,
    imageLoader: builder.imageLoader,
    imageContentTypeLoader: builder.imageContentTypeLoader,
  )
  rendered.renderBlock(child, attributes)
  if rendered.text.len > 0:
    if wroteBlock:
      builder.addBlockBreak(attributes)
    builder.add(rendered)
    wroteBlock = true

proc renderContainer(
    builder: var MarkdownBuilder,
    token: markdownParser.Token,
    attributes: TextAttributes,
) =
  var wroteBlock = false
  for child in token.children:
    builder.renderContainerChild(child, attributes, wroteBlock)

proc renderBlockquote(
    builder: var MarkdownBuilder,
    quote: markdownParser.Token,
    attributes: TextAttributes,
) =
  var quoteAttributes = attributes
  quoteAttributes.foregroundColor = builder.style.quoteColor
  var prefixAttributes = quoteAttributes
  prefixAttributes.foregroundColor = builder.style.ruleColor

  var quoted = MarkdownBuilder(
    style: builder.style,
    imageLoader: builder.imageLoader,
    imageContentTypeLoader: builder.imageContentTypeLoader,
  )
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
    let html = token.doc.strip(chars = {'\n'})
    if not builder.renderHtmlImages(html, attributes):
      builder.add(html, builder.style.mutedCodeAttributes(attributes))
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
    imageContentTypeLoader: MarkdownImageContentTypeLoader = nil,
): MarkdownDocument =
  var builder = MarkdownBuilder(
    style: style,
    imageLoader: imageLoader,
    imageContentTypeLoader: imageContentTypeLoader,
  )
  let attributes = style.bodyAttributes()
  builder.renderContainer(root, attributes)
  builder.toMarkdownDocument()

proc markdownDocument(
    source: string,
    style = initMarkdownStyle(),
    config: MarkdownParserConfig = nil,
    imageLoader: MarkdownImageLoader = nil,
    imageContentTypeLoader: MarkdownImageContentTypeLoader = nil,
): MarkdownDocument =
  source.parseMarkdownRoot(config).markdownDocument(
    style, imageLoader, imageContentTypeLoader
  )

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
  rect(anchor.origin.x, anchor.origin.y, drawSize.width, drawSize.height)

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

func markdownImageCacheKey(view: MarkdownView, url: string): string =
  view.xImageBasePath & "\x00" & url

proc resolvedDefaultMarkdownUrlAssetLoader(): UrlAssetLoader =
  if defaultMarkdownUrlAssetLoader.isNil or defaultMarkdownUrlAssetLoader.isClosed():
    let executableName = getAppFilename().splitFile.name
    defaultMarkdownUrlAssetLoader =
      newUrlAssetLoader(if executableName.len > 0: executableName else: "merenda")
  defaultMarkdownUrlAssetLoader

proc renderCurrentMarkdownDocument(view: MarkdownView)

proc markdownUrlAssetDidFinish(view: MarkdownView, handle: UrlAssetHandle) {.slot.} =
  let url = handle.result().url
  if url notin view.xPendingUrlAssets or view.xPendingUrlAssets[url] != handle:
    return
  view.xPendingUrlAssets.del(url)
  if not view.xImageLoader.isNil or not handle.succeeded():
    return
  try:
    let key = view.markdownImageCacheKey(url)
    let image = newImageResourceFromFile(
      handle.result().path, name = url, cachePolicy = icpBySize
    )
    view.xImageCache[key] = image
    view.xImageMediaTypes[key] = handle.result().mediaType
    view.renderCurrentMarkdownDocument()
  except CatchableError:
    discard

proc resolvedUrlAssetLoader(view: MarkdownView): UrlAssetLoader =
  result =
    if view.xUrlAssetLoader.isNil:
      resolvedDefaultMarkdownUrlAssetLoader()
    else:
      view.xUrlAssetLoader
  result.connect(urlAssetDidFinish, view, markdownUrlAssetDidFinish)

proc loadMarkdownImage(view: MarkdownView, url: string): ImageResource =
  let key = view.markdownImageCacheKey(url)
  if key in view.xImageCache:
    return view.xImageCache[key]
  try:
    if not view.xImageLoader.isNil:
      result = view.xImageLoader(url)
    else:
      let parsedUrl = initUrl(url)
      let path = parsedUrl.localFilePath(view.xImageBasePath)
      if path.len > 0 and path.fileExists:
        result = newImageResourceFromFile(path, name = path, cachePolicy = icpBySize)
        view.xImageMediaTypes[key] = parsedUrl.mediaType()
      elif parsedUrl.isHttpUrl():
        let handle = view.resolvedUrlAssetLoader().load(url)
        if handle.succeeded():
          result = newImageResourceFromFile(
            handle.result().path, name = url, cachePolicy = icpBySize
          )
          view.xImageMediaTypes[key] = handle.result().mediaType
        else:
          view.xPendingUrlAssets[url] = handle
  except CatchableError:
    discard
  if not result.isNil:
    view.xImageCache[key] = result

## Emitted on the view's owning thread after the latest parse is applied.
## `workerThreadId` is `-1` only for a custom parser configuration that must
## retain its synchronous extension behavior.
proc markdownDidFinishParsing*(view: MarkdownView, workerThreadId: int) {.signal.}

proc startLatestMarkdownParse(view: MarkdownView)

proc configureMarkdownImageLoaders(view: MarkdownView, builder: var MarkdownBuilder) =
  builder.imageLoader = proc(url: string): ImageResource =
    view.loadMarkdownImage(url)
  builder.imageContentTypeLoader = proc(url: string): string =
    let key = view.markdownImageCacheKey(url)
    view.xImageMediaTypes.getOrDefault(key, initUrl(url).mediaType())

proc clearMarkdownImageLoaders(builder: var MarkdownBuilder) =
  builder.imageLoader = nil
  builder.imageContentTypeLoader = nil

proc continueMarkdownRendering(view: MarkdownView, generation: uint64): bool =
  if view.isNil or generation != view.xActiveMarkdownRenderGeneration or
      generation != view.xMarkdownRenderJob.generation:
    return

  var job = move view.xMarkdownRenderJob
  let chunkStarted = getMonoTime()
  view.configureMarkdownImageLoaders(job.builder)
  var processedBlocks = 0
  while not job.nextBlock.isNil and processedBlocks < MarkdownRenderBlocksPerChunk:
    let child = job.nextBlock.value
    job.nextBlock = job.nextBlock.next
    job.builder.renderContainerChild(child, job.attributes, job.wroteBlock)
    inc processedBlocks
    if (getMonoTime() - chunkStarted).inNanoseconds >=
        MarkdownRenderChunkBudgetNanoseconds:
      break
  job.builder.clearMarkdownImageLoaders()

  if generation != view.xMarkdownRenderGeneration:
    return

  inc job.chunkCount
  if not job.nextBlock.isNil:
    let chunkDuration = getMonoTime() - chunkStarted
    if chunkDuration > job.maximumChunkDuration:
      job.maximumChunkDuration = chunkDuration
    view.xMarkdownRenderJob = move job
    return true

  let
    rootGeneration = job.rootGeneration
    document = toMarkdownDocument(move job.builder)
  view.xActiveMarkdownRenderGeneration = 0
  view.applyMarkdownDocument(document)
  let chunkDuration = getMonoTime() - chunkStarted
  if chunkDuration > job.maximumChunkDuration:
    job.maximumChunkDuration = chunkDuration
  view.xMarkdownRenderChunkCount = job.chunkCount
  view.xMarkdownMaximumRenderChunkDuration = job.maximumChunkDuration

  if generation == view.xMarkdownRenderGeneration and
      rootGeneration == view.xPendingMarkdownCompletionGeneration:
    view.xPendingMarkdownCompletionGeneration = 0
    emit view.markdownDidFinishParsing(view.xMarkdownParseWorkerThreadId)

proc scheduleMarkdownRendering(view: MarkdownView) =
  inc view.xMarkdownRenderGeneration
  let generation = view.xMarkdownRenderGeneration
  view.xActiveMarkdownRenderGeneration = generation
  view.xMarkdownRenderJob = MarkdownRenderJob(
    generation: generation,
    rootGeneration: view.xMarkdownRootGeneration,
    root: view.xMarkdownRoot,
    nextBlock: view.xMarkdownRoot.children.head,
    builder: MarkdownBuilder(style: view.xMarkdownStyle),
    attributes: view.xMarkdownStyle.bodyAttributes(),
  )
  scheduleMainThreadWork(
    proc(): bool =
      view.continueMarkdownRendering(generation)
  )

proc cancelMarkdownRendering(view: MarkdownView) =
  inc view.xMarkdownRenderGeneration
  view.xActiveMarkdownRenderGeneration = 0
  view.xMarkdownRenderJob = default(MarkdownRenderJob)

proc completeMarkdownParse(
    view: MarkdownView, parseResultBox: SharedPtr[MarkdownParseResult]
) {.slot.} =
  var parseResult = move parseResultBox[]
  if parseResult.generation != view.xActiveMarkdownGeneration:
    return

  view.xActiveMarkdownGeneration = 0
  if parseResult.generation == view.xMarkdownGeneration:
    view.xMarkdownParseWorkerThreadId = parseResult.workerThreadId
    view.xMarkdownParseError = parseResult.errorMessage
    if parseResult.errorMessage.len == 0:
      view.xMarkdownRoot = move parseResult.root
      view.xMarkdownRootGeneration = parseResult.generation
      view.xPendingMarkdownCompletionGeneration = parseResult.generation
      view.scheduleMarkdownRendering()
    else:
      view.xPendingMarkdownCompletionGeneration = 0
      emit view.markdownDidFinishParsing(parseResult.workerThreadId)
  if parseResult.generation != view.xMarkdownGeneration:
    view.startLatestMarkdownParse()

proc ensureMarkdownParseWorker(view: MarkdownView) =
  if not view.xMarkdownParseWorker.isNil:
    return
  view.xMarkdownParseWorker = newMarkdownParseWorker()
  connectThreaded(
    view.xMarkdownParseWorker,
    markdownParseFinished,
    view,
    MarkdownView.completeMarkdownParse(),
  )

proc startLatestMarkdownParse(view: MarkdownView) =
  if view.xActiveMarkdownGeneration != 0:
    return

  var dialect: MarkdownParseDialect
  if view.xMarkdownConfig.builtInMarkdownDialect(dialect):
    view.ensureMarkdownParseWorker()
    view.xActiveMarkdownGeneration = view.xMarkdownGeneration
    emit view.xMarkdownParseWorker.requestMarkdownParse(
      view.xActiveMarkdownGeneration, view.xMarkdown, dialect,
      view.xMarkdownConfig.escape, view.xMarkdownConfig.keepHtml,
    )
  else:
    # Arbitrary parser subclasses are thread-affine reference objects. Preserve
    # their existing behavior rather than sharing or attempting to clone them.
    view.xMarkdownRoot = view.xMarkdown.parseMarkdownRoot(view.xMarkdownConfig)
    view.xMarkdownRootGeneration = view.xMarkdownGeneration
    view.xMarkdownParseWorkerThreadId = -1
    view.xMarkdownParseError.setLen(0)
    view.xPendingMarkdownCompletionGeneration = view.xMarkdownGeneration
    view.scheduleMarkdownRendering()

proc scheduleMarkdownParse(view: MarkdownView) =
  view.cancelMarkdownRendering()
  view.xPendingMarkdownCompletionGeneration = 0
  inc view.xMarkdownGeneration
  view.xMarkdownParseError.setLen(0)
  view.startLatestMarkdownParse()

proc renderCurrentMarkdownDocument(view: MarkdownView) =
  view.scheduleMarkdownRendering()

func isMarkdownRendering*(view: MarkdownView): bool =
  ## Return whether the owning thread has an incremental render in progress.
  not view.isNil and view.xActiveMarkdownRenderGeneration != 0

func isMarkdownParsing*(view: MarkdownView): bool =
  ## Return whether parsing or incremental AST application is in progress.
  not view.isNil and (view.xActiveMarkdownGeneration != 0 or view.isMarkdownRendering())

func isMarkdownLayoutPending*(view: MarkdownView): bool =
  ## Return whether resize reflow is finishing on a text-layout worker.
  not view.isNil and view.textView().layoutManager().isBackgroundLayoutPending()

func markdownRenderChunkCount*(view: MarkdownView): int =
  ## Return the number of chunks used by the current or last completed render.
  if view.isNil:
    return
  if view.isMarkdownRendering():
    view.xMarkdownRenderJob.chunkCount
  else:
    view.xMarkdownRenderChunkCount

func markdownMaximumRenderChunkDuration*(view: MarkdownView): Duration =
  ## Return the longest owner-thread chunk in the last completed render.
  if not view.isNil:
    result = view.xMarkdownMaximumRenderChunkDuration

func markdownParseWorkerThreadId*(view: MarkdownView): int =
  ## Return the thread ID of the last applied parse, or `-1` before completion.
  if view.isNil: -1 else: view.xMarkdownParseWorkerThreadId

func markdownParseError*(view: MarkdownView): string =
  ## Return the last asynchronous parser error, if any.
  if not view.isNil:
    result = view.xMarkdownParseError

proc pollMarkdownParsing*(view: MarkdownView): int {.discardable.} =
  ## Deliver worker results and run at most one rendering chunk per ready job.
  if not view.isNil:
    result = getCurrentSigilThread().pollAll()
    result += drainMainThreadWork()

proc waitForMarkdownRendering*(
    view: MarkdownView, timeoutMilliseconds: Natural = 5_000
): bool {.discardable.} =
  ## Poll until this view's active incremental render finishes.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
  while getMonoTime() < deadline:
    discard view.pollMarkdownParsing()
    if not view.isMarkdownRendering():
      return true
    sleep(1)

proc waitForMarkdownParsing*(
    view: MarkdownView, timeoutMilliseconds: Natural = 5_000
): bool {.discardable.} =
  ## Poll until the latest parse and incremental application finish.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
  while getMonoTime() < deadline:
    discard view.pollMarkdownParsing()
    if not view.isMarkdownParsing():
      return true
    sleep(1)

proc waitForMarkdownLayout*(
    view: MarkdownView, timeoutMilliseconds: Natural = 5_000
): bool {.discardable.} =
  ## Poll until the latest background resize reflow is installed.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
  while getMonoTime() < deadline:
    discard view.pollMarkdownParsing()
    view.layoutSubtreeIfNeeded()
    if not view.isMarkdownLayoutPending():
      return true
    sleep(1)

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
  ## Schedules a parse and atomically replaces the document when it completes.
  if view.xMarkdown == source:
    return
  view.xPendingUrlAssets.clear()
  view.xMarkdown = source
  view.scheduleMarkdownParse()

proc imageBasePath*(view: MarkdownView): string =
  ## Returns the directory used to resolve relative local image destinations.
  view.xImageBasePath

proc `imageBasePath=`*(view: MarkdownView, basePath: string) =
  ## Changes the local image directory and rerenders the current document.
  if view.xImageBasePath == basePath:
    return
  view.xImageBasePath = basePath
  view.xImageCache.clear()
  view.xImageMediaTypes.clear()
  view.xPendingUrlAssets.clear()
  view.renderCurrentMarkdownDocument()

proc imageLoader*(view: MarkdownView): MarkdownImageLoader =
  ## Returns the optional application-provided image resolver.
  view.xImageLoader

proc `imageLoader=`*(view: MarkdownView, loader: MarkdownImageLoader) =
  ## Changes the image resolver and rerenders the current document.
  view.xImageLoader = loader
  view.xImageCache.clear()
  view.xImageMediaTypes.clear()
  view.xPendingUrlAssets.clear()
  view.renderCurrentMarkdownDocument()

proc urlAssetLoader*(view: MarkdownView): UrlAssetLoader =
  ## Returns the optional application-owned loader used for HTTP(S) images.
  ##
  ## A nil value selects a lazy loader shared by Markdown views on this thread.
  view.xUrlAssetLoader

proc `urlAssetLoader=`*(view: MarkdownView, loader: UrlAssetLoader) =
  ## Changes the URL asset loader and rerenders remote images.
  ##
  ## The caller retains ownership and must close a non-nil `loader` after all
  ## views using it have finished.
  if view.xUrlAssetLoader == loader:
    return
  view.xUrlAssetLoader = loader
  view.xImageCache.clear()
  view.xImageMediaTypes.clear()
  view.xPendingUrlAssets.clear()
  view.renderCurrentMarkdownDocument()

proc markdownStyle*(view: MarkdownView): MarkdownStyle =
  ## Returns a copy of the current document presentation.
  view.xMarkdownStyle

proc `markdownStyle=`*(view: MarkdownView, style: MarkdownStyle) =
  ## Applies `style` and incrementally rerenders the current source.
  if view.xMarkdownStyle == style:
    return
  view.xMarkdownStyle = style
  view.applyMarkdownStyle()
  view.renderCurrentMarkdownDocument()

proc markdownConfig*(view: MarkdownView): MarkdownParserConfig =
  ## Returns the active parser configuration.
  view.xMarkdownConfig

proc `markdownConfig=`*(view: MarkdownView, config: MarkdownParserConfig) =
  ## Applies `config` and schedules the current source for reparsing.
  let resolved = config.resolvedConfig()
  if view.xMarkdownConfig == resolved:
    return
  view.xPendingUrlAssets.clear()
  view.xMarkdownConfig = resolved
  view.scheduleMarkdownParse()

proc initMarkdownViewFields*(
    view: MarkdownView,
    source = "",
    frame: Rect = AutoRect,
    style = initMarkdownStyle(),
    config: MarkdownParserConfig = nil,
    imageBasePath = "",
    imageLoader: MarkdownImageLoader = nil,
    urlAssetLoader: UrlAssetLoader = nil,
) =
  ## Initializes a custom `MarkdownView` subtype.
  ##
  ## HTTP(S) images use `urlAssetLoader`, or a lazy shared loader when it is nil.
  let textView = MarkdownTextView()
  textView.initTextViewFields()
  discard textView.withProtocol(MarkdownTextViewDrawing)
  initTextEditorFields(
    view, frame = frame, richText = true, wraps = true, textView = textView
  )
  view.xMarkdownStyle = style
  view.xMarkdownConfig = config.resolvedConfig()
  view.xMarkdownRoot = markdownParser.Document()
  view.xMarkdownRootGeneration = 0
  view.xMarkdownParseWorkerThreadId = -1
  view.xImageBasePath = imageBasePath
  view.xImageLoader = imageLoader
  view.xUrlAssetLoader = urlAssetLoader
  view.xImageCache = initTable[string, ImageResource]()
  view.xImageMediaTypes = initTable[string, string]()
  view.xPendingUrlAssets = initTable[string, UrlAssetHandle]()
  view.xMarkdown = source
  view.editable = false
  view.selectable = true
  view.allowsUndo = false
  view.scrollView().borderType = svbNoBorder
  view.accessibilityLabel = "Markdown document"
  view.applyMarkdownStyle()
  view.applyMarkdownDocument(view.xMarkdownRoot.markdownDocument(style))
  view.textView().layoutManager().usesBackgroundLayout = true
  view.scheduleMarkdownParse()

proc newMarkdownView*(
    source = "",
    frame: Rect = AutoRect,
    style = initMarkdownStyle(),
    config: MarkdownParserConfig = nil,
    imageBasePath = "",
    imageLoader: MarkdownImageLoader = nil,
    urlAssetLoader: UrlAssetLoader = nil,
): MarkdownView =
  ## Creates a scrollable, selectable, read-only Markdown document view.
  ##
  ## Built-in CommonMark and GFM configurations parse asynchronously on a
  ## shared Sigils pool worker. The owning application thread applies the AST
  ## incrementally between application frames, then swaps in the final document.
  ## Remote HTTP(S) images load asynchronously through `urlAssetLoader`. The
  ## default shared loader uses the executable name for its platform cache.
  result = MarkdownView()
  result.initMarkdownViewFields(
    source, frame, style, config, imageBasePath, imageLoader, urlAssetLoader
  )
