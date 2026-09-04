## Native Markdown rendering for NimKit text views.
##
## CommonMark and GFM parsing runs on a Sigils pool worker, then the complete AST
## moves back to the view's owning thread for incremental attributed-text
## construction between application frames. HTML image tags share the native
## Markdown image path; other raw HTML stays inert. Local images resolve
## explicitly, remote images load through a Chronos worker, and unavailable
## images use linked alt text.

import std/[algorithm, lists, math, monotimes, os, strutils, tables, times, unicode]

when not defined(useNativeDynlib):
  import std/hashes
  from pkg/pixie import resize

import markdown as markdownParser
from markdownpkg/entities import htmlEntityToUtf8
import sigils/[core, threads]
import threading/smartptrs

import ../accessibility/accessibility
import ../app/[animationproperties, animations]
from ../app/windows import Window, startAnimation, stopAnimation
import ../drawing
import ../foundation/events
import ../foundation/mainthreadwork
import ../foundation/selectors
import ../foundation/types
import ../foundation/urlassets
import ../foundation/urls
import ../themes
from ../view/viewgeometry import setFrameFromLayout
import ../view/views
import ./markdownhtmlimages
import ./markdownparsing
import ./matterhighlighting
import ./syntaxhighlighting
import ./texteditors
import ./textstorage
import ./texttypes

export texteditors
export textstorage
export matterhighlighting
export syntaxhighlighting
export texttypes

const
  MarkdownUnderlayRenderSlot = initRenderSlotId(0x4d41524b'u32, 1)
  MarkdownImageBlockSpacing = 12.0'f32
    ## Fixed separation around image attachment lines, independent of image size.
  MarkdownTableDefaultColumnLimit = 100
  MarkdownTableMinimumColumnLimit = 24
  MarkdownTableMaximumColumnLimit = 160
  MarkdownTableColumnQuantum = 4
  MarkdownTableMinimumColumnWidth = 3
  MarkdownTablePreferredCellWidth = 12
  MarkdownTableSeparatorWidth = 3
  MarkdownTableFontScale = 0.9'f32
  MarkdownTableViewportFraction = 0.9'f32

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
    syntaxTokenColors*: array[SyntaxTokenClass, Color]
      ## Fenced-code colors keyed by frontend-neutral token class.
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

  MarkdownRangeLayout = object
    layoutHash: int
    rect: Rect
    resolved: bool

  MarkdownCodeBlockPresentation = object
    range: TextRange
    storage: TextStorage

  MarkdownCodeBlockScrollPresentation = object
    range: TextRange
    storage: TextStorage
    scrollView: ScrollView
    textView: TextView
    rangeLayout: MarkdownRangeLayout
    contentSize: Size
    contentSizeValid: bool

  MarkdownTablePresentation = object
    range: TextRange
    storage: TextStorage
    overflowing: bool

  MarkdownTableScrollPresentation = object
    range: TextRange
    storage: TextStorage
    scrollView: ScrollView
    textView: TextView
    rangeLayout: MarkdownRangeLayout
    contentSize: Size
    contentSizeValid: bool

  MarkdownTextView = ref object of TextView
    codeBlockStyle: MarkdownBlockStyle
    markdownImages: seq[MarkdownImagePresentation]
    markdownCodeBlocks: seq[MarkdownCodeBlockScrollPresentation]
    markdownTables: seq[MarkdownTableScrollPresentation]
    markdownEmbeddedViewport: Rect
    hasMarkdownEmbeddedViewport: bool
    markdownViewportLayoutPending: bool

  MarkdownDocument = object
    storage: TextStorage
    codeBlocks: seq[MarkdownCodeBlockPresentation]
    images: seq[MarkdownImagePresentation]
    imageUrls: seq[string]
    tables: seq[MarkdownTablePresentation]
    hasTables: bool

  MarkdownBuilder = object
    text: string
    runeLength: int
    runs: seq[TextAttributeRun]
    codeBlocks: seq[MarkdownCodeBlockPresentation]
    images: seq[MarkdownImagePresentation]
    imageUrls: seq[string]
    style: MarkdownStyle
    imageLoader: MarkdownImageLoader
    imageContentTypeLoader: MarkdownImageContentTypeLoader
    syntaxHighlighter: SyntaxHighlighter
    tableColumnLimit: int
    tables: seq[MarkdownTablePresentation]
    hasTables: bool

  MarkdownTableAlignment = enum
    mtaLeft
    mtaCenter
    mtaRight

  MarkdownTableRune = object
    value: Rune
    attributes: TextAttributes
    image: ImageResource
    imageDisplaySize: Size

  MarkdownTableCell = object
    content: seq[MarkdownTableRune]
    alignment: MarkdownTableAlignment
    paddingAttributes: TextAttributes

  MarkdownTableRow = object
    cells: seq[MarkdownTableCell]
    header: bool

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
    xSyntaxHighlighter: SyntaxHighlighter
    xImageBasePath: string
    xImageLoader: MarkdownImageLoader
    xUrlAssetLoader: UrlAssetLoader
    xImageCache: Table[string, ImageResource]
    xImageMediaTypes: Table[string, string]
    xPendingUrlAssets: Table[string, UrlAssetHandle]
    xHasMarkdownTables: bool
    xMarkdownTableColumnLimit: int
    xMarkdownTableResizePending: bool
    xMarkdownTableResizeDeadline: MonoTime
    xKeyboardScrollAnimation: Animation
    xKeyboardScrollTarget: Point

const
  MarkdownRenderBlocksPerChunk = 16
  MarkdownRenderChunkBudgetNanoseconds = 4_000_000'i64
  MarkdownBackgroundLayoutMinimumLength = 4_096
  MarkdownTableResizeDebounce = initDuration(milliseconds = 120)
  MarkdownKeyboardScrollDuration = initDuration(milliseconds = 140)
  MarkdownKeyboardScrollRows = 4.0'f32
  MarkdownKeyboardPageFraction = 0.25'f32

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
  result = MarkdownStyle(
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
  for tokenClass in SyntaxTokenClass:
    result.syntaxTokenColors[tokenClass] = result.codeColor
  result.syntaxTokenColors[stcKeyword] = color(0.48, 0.14, 0.60, 1.0)
  result.syntaxTokenColors[stcIdentifier] = color(0.10, 0.31, 0.57, 1.0)
  result.syntaxTokenColors[stcString] = color(0.10, 0.43, 0.24, 1.0)
  result.syntaxTokenColors[stcNumber] = color(0.72, 0.32, 0.08, 1.0)
  result.syntaxTokenColors[stcComment] = result.mutedColor
  result.syntaxTokenColors[stcOperator] = color(0.08, 0.40, 0.66, 1.0)
  result.syntaxTokenColors[stcPunctuation] = result.ruleColor
  result.syntaxTokenColors[stcPreprocessor] = result.emphasisColor

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

proc imageForMarkdownDisplay(view: MarkdownView, image: ImageResource): ImageResource =
  when defined(useNativeDynlib):
    result = image
  else:
    if image.isNil:
      return
    let
      sourceSize = image.size()
      displaySize = sourceSize.scaledDown(view.xMarkdownStyle.maximumImageSize)
      width = max(1, ceil(displaySize.width).int)
      height = max(1, ceil(displaySize.height).int)
    if width >= sourceSize.width.int and height >= sourceSize.height.int:
      return image
    let name =
      "markdown.scaled:" & $Hash(image.imageId()) & ":" & $width & "x" & $height
    result = newImageResource(image.pixels().resize(width, height), name = name)

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
  result = probeFontSize * targetLineHeight / probeLineHeight
  var measuredStyle = probeStyle
  for _ in 0 ..< 2:
    measuredStyle.fontSize = result
    let measuredLineHeight = textNaturalSize("", measuredStyle).height
    if measuredLineHeight <= 0.0'f32 or
        abs(measuredLineHeight - targetLineHeight) <= 0.5'f32:
      break
    result *= targetLineHeight / measuredLineHeight

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
  builder.hasTables = builder.hasTables or rendered.hasTables
  builder.imageUrls.add(rendered.imageUrls)
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
  for presentation in rendered.codeBlocks:
    var shifted = presentation
    shifted.range = initTextRange(
      offset + int(presentation.range.location), int(presentation.range.length)
    )
    builder.codeBlocks.add shifted
  for presentation in rendered.images:
    var shifted = presentation
    shifted.range = initTextRange(
      offset + int(presentation.range.location), int(presentation.range.length)
    )
    builder.images.add shifted
  for presentation in rendered.tables:
    var shifted = presentation
    shifted.range = initTextRange(
      offset + int(presentation.range.location), int(presentation.range.length)
    )
    builder.tables.add shifted

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
  builder.imageUrls.add(token.url)
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
  if token of markdownParser.Text:
    # nim-markdown may leave a soft break in its fallback Text token.
    builder.add(token.doc.replace("\n", " "), attributes)
  elif token of markdownParser.Escape:
    builder.add(token.doc, attributes)
  elif token of markdownParser.HtmlEntity:
    let decoded = htmlEntityToUtf8(token.doc)
    builder.add(if decoded.len > 0: decoded else: token.doc, attributes)
  elif token of markdownParser.SoftBreak:
    # A physical source line ending remains part of the surrounding paragraph.
    # Preserve word separation while leaving wrapping to the text layout engine.
    builder.add(" ", attributes)
  elif token of markdownParser.HardBreak:
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

func endsWithCodeBlock(builder: MarkdownBuilder): bool =
  builder.codeBlocks.len > 0 and
    builder.codeBlocks[^1].range.maxIndex == builder.runeLength

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
      if builder.endsWithCodeBlock():
        builder.addBlockBreak(attributes)
      else:
        builder.add("\n", attributes)
      builder.renderList(child, depth + 1, attributes)
    else:
      if child of markdownParser.CodeBlock or builder.endsWithCodeBlock():
        builder.addBlockBreak(attributes)
        builder.add(continuation, attributes)
      elif not first:
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
        if builder.endsWithCodeBlock():
          builder.addBlockBreak(attributes)
        else:
          builder.add("\n", attributes)
      let marker =
        if token of markdownParser.Ol:
          $index & "."
        else:
          "•"
      builder.renderListItem(markdownParser.Li(child), marker, depth, attributes)
      inc index
      first = false

func tableAlignment(cell: markdownParser.Token): MarkdownTableAlignment =
  let alignment =
    if cell of markdownParser.THeadCell:
      markdownParser.THeadCell(cell).align
    elif cell of markdownParser.TBodyCell:
      markdownParser.TBodyCell(cell).align
    else:
      ""
  case alignment
  of "center": mtaCenter
  of "right": mtaRight
  else: mtaLeft

proc tableRunes(rendered: MarkdownBuilder): seq[MarkdownTableRune] =
  let runes = rendered.text.toRunes()
  var
    runIndex = 0
    imageIndex = 0
  for index, value in runes:
    while runIndex < rendered.runs.high and
        index >= rendered.runs[runIndex].range.maxIndex:
      inc runIndex
    while imageIndex < rendered.images.len and
        rendered.images[imageIndex].range.maxIndex <= index:
      inc imageIndex
    var tableRune = MarkdownTableRune(
      value: value,
      attributes:
        if runIndex < rendered.runs.len:
          rendered.runs[runIndex].attributes
        else:
          rendered.style.bodyAttributes(),
    )
    if imageIndex < rendered.images.len and
        int(rendered.images[imageIndex].range.location) <= index and
        rendered.images[imageIndex].range.maxIndex > index:
      tableRune.image = rendered.images[imageIndex].image
      tableRune.imageDisplaySize = rendered.images[imageIndex].displaySize
    result.add tableRune

func naturalTableCellWidth(content: openArray[MarkdownTableRune]): int =
  var
    lineWidth = 0
    pendingSpace = false
  for unit in content:
    if unit.value == Rune('\n'):
      result = max(result, lineWidth)
      lineWidth = 0
      pendingSpace = false
    elif unit.value.isWhiteSpace and not unit.attributes.hasAttachment:
      pendingSpace = lineWidth > 0
    else:
      if pendingSpace:
        inc lineWidth
      inc lineWidth
      pendingSpace = false
  max(result, lineWidth)

func minimumTableCellWidth(content: openArray[MarkdownTableRune]): int =
  var wordWidth = 0
  for unit in content:
    if unit.value == Rune('\n') or
        (unit.value.isWhiteSpace and not unit.attributes.hasAttachment):
      result = max(result, wordWidth)
      wordWidth = 0
    else:
      inc wordWidth
  result = max(result, wordWidth)
  result =
    max(result, min(content.naturalTableCellWidth(), MarkdownTablePreferredCellWidth))

proc finishTableLine(
    lines: var seq[seq[MarkdownTableRune]],
    line: var seq[MarkdownTableRune],
    hasPendingSpace: var bool,
) =
  lines.add move line
  line = @[]
  hasPendingSpace = false

proc appendTableWord(
    lines: var seq[seq[MarkdownTableRune]],
    line: var seq[MarkdownTableRune],
    word: var seq[MarkdownTableRune],
    pendingSpace: MarkdownTableRune,
    hasPendingSpace: var bool,
    limit: int,
) =
  if word.len == 0:
    return
  let spacing = if line.len > 0 and hasPendingSpace: 1 else: 0
  if line.len > 0 and line.len + spacing + word.len > limit:
    lines.finishTableLine(line, hasPendingSpace)

  if line.len > 0 and hasPendingSpace:
    line.add pendingSpace
  line.add word
  word = @[]
  hasPendingSpace = false

proc wrapTableCell(
    content: openArray[MarkdownTableRune], width: int
): seq[seq[MarkdownTableRune]] =
  let limit = max(width, 1)
  var
    line: seq[MarkdownTableRune]
    word: seq[MarkdownTableRune]
    pendingSpace: MarkdownTableRune
    hasPendingSpace = false

  for unit in content:
    if unit.value == Rune('\n'):
      result.appendTableWord(line, word, pendingSpace, hasPendingSpace, limit)
      result.finishTableLine(line, hasPendingSpace)
    elif unit.value.isWhiteSpace and not unit.attributes.hasAttachment:
      result.appendTableWord(line, word, pendingSpace, hasPendingSpace, limit)
      if line.len > 0:
        pendingSpace = unit
        pendingSpace.value = Rune(' ')
        hasPendingSpace = true
    else:
      word.add unit
  result.appendTableWord(line, word, pendingSpace, hasPendingSpace, limit)
  if line.len > 0 or result.len == 0:
    result.add move line

func fittedTableWidths(
    naturalWidths, minimumWidths: openArray[int], columnLimit: int
): seq[int] =
  if naturalWidths.len == 0:
    return
  let
    separatorColumns = MarkdownTableSeparatorWidth * (naturalWidths.len - 1)
    contentLimit = max(
      columnLimit - separatorColumns,
      MarkdownTableMinimumColumnWidth * naturalWidths.len,
    )
  var
    maximumWidth = MarkdownTableMinimumColumnWidth
    minimumTotal = 0
    naturalTotal = 0
  for index, width in naturalWidths:
    let
      minimumWidth = max(minimumWidths[index], MarkdownTableMinimumColumnWidth)
      naturalWidth = max(width, minimumWidth)
    maximumWidth = max(maximumWidth, naturalWidth)
    minimumTotal += minimumWidth
    naturalTotal += naturalWidth
  if naturalTotal <= contentLimit:
    for index, width in naturalWidths:
      result.add max(max(width, minimumWidths[index]), MarkdownTableMinimumColumnWidth)
    return
  if minimumTotal >= contentLimit:
    for width in minimumWidths:
      result.add max(width, MarkdownTableMinimumColumnWidth)
    return

  var
    low = 0
    high = maximumWidth
    cap = 0
  while low <= high:
    let candidate = (low + high) div 2
    var used = 0
    for index, width in naturalWidths:
      let minimumWidth = max(minimumWidths[index], MarkdownTableMinimumColumnWidth)
      used += max(min(max(width, minimumWidth), candidate), minimumWidth)
    if used <= contentLimit:
      cap = candidate
      low = candidate + 1
    else:
      high = candidate - 1

  var used = 0
  for index, width in naturalWidths:
    let
      minimumWidth = max(minimumWidths[index], MarkdownTableMinimumColumnWidth)
      fitted = max(min(max(width, minimumWidth), cap), minimumWidth)
    result.add fitted
    used += fitted
  var remaining = contentLimit - used
  while remaining > 0:
    var distributed = false
    for index, naturalWidth in naturalWidths:
      let target = max(naturalWidth, minimumWidths[index])
      if result[index] < target and remaining > 0:
        inc result[index]
        dec remaining
        distributed = true
    if not distributed:
      break

proc addTableRunes(
    builder: var MarkdownBuilder, content: openArray[MarkdownTableRune]
) =
  for unit in content:
    let start = builder.runeLength
    builder.add($unit.value, unit.attributes)
    if not unit.image.isNil:
      builder.images.add MarkdownImagePresentation(
        range: initTextRange(start, 1),
        image: unit.image,
        displaySize: unit.imageDisplaySize,
      )

proc addTableCellLine(
    builder: var MarkdownBuilder,
    line: openArray[MarkdownTableRune],
    width: int,
    alignment: MarkdownTableAlignment,
    paddingAttributes: TextAttributes,
) =
  let padding = max(width - line.len, 0)
  var leftPadding, rightPadding: int
  case alignment
  of mtaLeft:
    rightPadding = padding
  of mtaCenter:
    leftPadding = padding div 2
    rightPadding = padding - leftPadding
  of mtaRight:
    leftPadding = padding
  if leftPadding > 0:
    builder.add(" ".repeat(leftPadding), paddingAttributes)
  builder.addTableRunes(line)
  if rightPadding > 0:
    builder.add(" ".repeat(rightPadding), paddingAttributes)

proc renderTable(
    builder: var MarkdownBuilder,
    table: markdownParser.Token,
    attributes: TextAttributes,
) =
  var tableAttributes = attributes
  tableAttributes.fontName = builder.style.codeFontName
  tableAttributes.fontSize =
    max(builder.style.bodyFontSize * MarkdownTableFontScale, 1.0'f32)
  tableAttributes.paragraphStyle.lineBreakMode = tlbmClipping
  var rows: seq[MarkdownTableRow]
  for section in table.children:
    let isHeader = section of markdownParser.THead
    for row in section.children:
      var rowAttributes = tableAttributes
      if isHeader:
        rowAttributes.foregroundColor = builder.style.headingColor
      var renderedRow = MarkdownTableRow(header: isHeader)
      for cell in row.children:
        var renderedCell = MarkdownBuilder(
          style: builder.style,
          imageLoader: builder.imageLoader,
          imageContentTypeLoader: builder.imageContentTypeLoader,
          syntaxHighlighter: builder.syntaxHighlighter,
          tableColumnLimit: builder.tableColumnLimit,
        )
        renderedCell.renderInlineChildren(cell, rowAttributes)
        builder.imageUrls.add(renderedCell.imageUrls)
        renderedRow.cells.add MarkdownTableCell(
          content: renderedCell.tableRunes(),
          alignment: cell.tableAlignment(),
          paddingAttributes: rowAttributes,
        )
      rows.add move renderedRow

  var columnCount = 0
  for row in rows:
    columnCount = max(columnCount, row.cells.len)
  if columnCount == 0:
    return

  var
    naturalWidths = newSeq[int](columnCount)
    minimumWidths = newSeq[int](columnCount)
  for row in rows:
    for index, cell in row.cells:
      naturalWidths[index] =
        max(naturalWidths[index], cell.content.naturalTableCellWidth())
      minimumWidths[index] =
        max(minimumWidths[index], cell.content.minimumTableCellWidth())
  let widths = naturalWidths.fittedTableWidths(
    minimumWidths,
    if builder.tableColumnLimit > 0:
      builder.tableColumnLimit
    else:
      MarkdownTableDefaultColumnLimit,
  )
  var tableColumnWidth = MarkdownTableSeparatorWidth * (columnCount - 1)
  for width in widths:
    tableColumnWidth += width
  let tableStart = builder.runeLength
  var separatorAttributes = tableAttributes
  separatorAttributes.foregroundColor = builder.style.ruleColor

  for rowIndex, row in rows:
    if rowIndex > 0:
      builder.add("\n", tableAttributes)
    var
      wrappedCells = newSeq[seq[seq[MarkdownTableRune]]](columnCount)
      rowHeight = 1
    for index in 0 ..< columnCount:
      if index < row.cells.len:
        wrappedCells[index] = row.cells[index].content.wrapTableCell(widths[index])
        rowHeight = max(rowHeight, wrappedCells[index].len)
      else:
        wrappedCells[index] = @[newSeq[MarkdownTableRune]()]

    for lineIndex in 0 ..< rowHeight:
      if lineIndex > 0:
        builder.add("\n", tableAttributes)
      for columnIndex in 0 ..< columnCount:
        if columnIndex > 0:
          builder.add(" │ ", separatorAttributes)
        let
          cellExists = columnIndex < row.cells.len
          lineExists = lineIndex < wrappedCells[columnIndex].len
          alignment =
            if cellExists:
              row.cells[columnIndex].alignment
            else:
              mtaLeft
          paddingAttributes =
            if cellExists:
              row.cells[columnIndex].paddingAttributes
            else:
              tableAttributes
        if lineExists:
          builder.addTableCellLine(
            wrappedCells[columnIndex][lineIndex],
            widths[columnIndex],
            alignment,
            paddingAttributes,
          )
        else:
          builder.add(" ".repeat(widths[columnIndex]), paddingAttributes)

    if row.header:
      builder.add("\n", tableAttributes)
      for columnIndex, width in widths:
        if columnIndex > 0:
          builder.add("─┼─", separatorAttributes)
        builder.add("─".repeat(width), separatorAttributes)
  let overflowing = tableColumnWidth > builder.tableColumnLimit
  let tableRange = initTextRange(tableStart, builder.runeLength - tableStart)
  var presentation =
    MarkdownTablePresentation(range: tableRange, overflowing: overflowing)
  if overflowing:
    presentation.storage =
      newTextStorage(builder.text, builder.runs).sliceTextStorage(tableRange)
  builder.tables.add move presentation
  builder.hasTables = true

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
    syntaxHighlighter: builder.syntaxHighlighter,
    tableColumnLimit: builder.tableColumnLimit,
  )
  rendered.renderBlock(child, attributes)
  if rendered.text.len > 0:
    let previousBlockEndsWithImage =
      builder.images.len > 0 and builder.text.endsWith("\n") and
      builder.images[^1].range.maxIndex == builder.runeLength - 1
    if wroteBlock and not previousBlockEndsWithImage:
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
    syntaxHighlighter: builder.syntaxHighlighter,
    tableColumnLimit: builder.tableColumnLimit,
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

  for presentation in quoted.codeBlocks:
    var mapped = presentation
    let
      start = sourceToDestination[int(presentation.range.location)]
      stop = sourceToDestination[presentation.range.maxIndex]
    mapped.range = initTextRange(start, stop - start)
    builder.codeBlocks.add mapped
  for presentation in quoted.images:
    var mapped = presentation
    let
      start = sourceToDestination[int(presentation.range.location)]
      stop = sourceToDestination[presentation.range.maxIndex]
    mapped.range = initTextRange(start, stop - start)
    builder.images.add mapped
  for presentation in quoted.tables:
    var mapped = presentation
    let
      start = sourceToDestination[int(presentation.range.location)]
      stop = sourceToDestination[presentation.range.maxIndex]
    mapped.range = initTextRange(start, stop - start)
    builder.tables.add mapped
  builder.hasTables = builder.hasTables or quoted.hasTables

proc addHighlightedCode(
    builder: var MarkdownBuilder, source, language: string, attributes: TextAttributes
) =
  if source.len == 0 or language.len == 0 or builder.syntaxHighlighter.isNil:
    builder.add(source, attributes)
    return

  var spans: seq[SyntaxTokenSpan]
  try:
    spans = builder.syntaxHighlighter(source, language)
  except CatchableError:
    builder.add(source, attributes)
    return

  let runeCount = source.runeLen
  var position = 0
  for span in spans:
    let
      start = max(position, min(int(span.range.location), runeCount))
      stop = max(start, min(span.range.maxIndex, runeCount))
    if stop > start:
      if start > position:
        builder.add(source.runeSubStr(position, start - position), attributes)
      var tokenAttributes = attributes
      tokenAttributes.foregroundColor = builder.style.syntaxTokenColors[span.tokenClass]
      builder.add(source.runeSubStr(start, stop - start), tokenAttributes)
      position = stop
  if position < runeCount:
    builder.add(source.runeSubStr(position), attributes)

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
    var renderedCode = MarkdownBuilder(
      style: builder.style,
      imageLoader: builder.imageLoader,
      imageContentTypeLoader: builder.imageContentTypeLoader,
      syntaxHighlighter: builder.syntaxHighlighter,
      tableColumnLimit: builder.tableColumnLimit,
    )
    var codeAttributes = renderedCode.style.codeAttributes(attributes)
    codeAttributes.backgroundColor = renderedCode.style.codeBlockStyle.backgroundColor
    codeAttributes.paragraphStyle.lineBreakMode = tlbmClipping
    if code.info.len > 0:
      var infoAttributes = renderedCode.style.mutedCodeAttributes(attributes)
      infoAttributes.backgroundColor = renderedCode.style.codeBlockStyle.backgroundColor
      infoAttributes.paragraphStyle.lineBreakMode = tlbmClipping
      renderedCode.add("[" & code.info & "]\n", infoAttributes)
    renderedCode.addHighlightedCode(
      code.doc.strip(chars = {'\n'}), code.info, codeAttributes
    )
    if renderedCode.runeLength > 0:
      let blockRange = initTextRange(0, renderedCode.runeLength)
      renderedCode.codeBlocks.add MarkdownCodeBlockPresentation(
        range: blockRange, storage: newTextStorage(renderedCode.text, renderedCode.runs)
      )
      builder.add(move renderedCode)
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
  result = MarkdownDocument(
    storage: newTextStorage(builder.text, builder.runs),
    codeBlocks: builder.codeBlocks,
    images: builder.images,
    imageUrls: builder.imageUrls,
    tables: builder.tables,
    hasTables: builder.hasTables,
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
    syntaxHighlighter: SyntaxHighlighter = matterSyntaxHighlighter,
): MarkdownDocument =
  var builder = MarkdownBuilder(
    style: style,
    imageLoader: imageLoader,
    imageContentTypeLoader: imageContentTypeLoader,
    syntaxHighlighter: syntaxHighlighter,
    tableColumnLimit: MarkdownTableDefaultColumnLimit,
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
    syntaxHighlighter: SyntaxHighlighter = matterSyntaxHighlighter,
): MarkdownDocument =
  source.parseMarkdownRoot(config).markdownDocument(
    style, imageLoader, imageContentTypeLoader, syntaxHighlighter
  )

proc markdownTextStorage*(
    source: string,
    style = initMarkdownStyle(),
    config: MarkdownParserConfig = nil,
    syntaxHighlighter: SyntaxHighlighter = matterSyntaxHighlighter,
): TextStorage =
  ## Parses `source` and returns native attributed text without creating a view.
  ## A nil configuration selects GFM so tables and strikethrough work by default.
  source.markdownDocument(style, config, syntaxHighlighter = syntaxHighlighter).storage

proc codeBlockRect(
    textView: MarkdownTextView, contentRect: Rect, style: MarkdownBlockStyle
): Rect =
  result = contentRect
  if not contentRect.isEmpty:
    let
      padding = style.padding
      outlineInset = max(style.outlineWidth, 0.0'f32) / 2.0'f32
    result =
      result.inset(insets(-padding.top, -padding.left, -padding.bottom, -padding.right))
    result = rect(
      result.origin,
      initSize(
        min(
          result.size.width,
          max(textView.bounds().maxX - outlineInset - result.origin.x, 0.0'f32),
        ),
        result.size.height,
      ),
    )

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

func verticallyBuffered(source: Rect, screens = 1.0'f32): Rect =
  let padding = source.size.height * max(screens, 0.0'f32)
  rect(
    source.origin.x,
    source.origin.y - padding,
    source.size.width,
    source.size.height + padding * 2.0'f32,
  )

func textRangesIntersect(left, right: TextRange): bool =
  let
    leftStart = int(left.location)
    rightStart = int(right.location)
  if left.length == 0:
    return leftStart >= rightStart and leftStart <= right.maxIndex
  if right.length == 0:
    return rightStart >= leftStart and rightStart <= left.maxIndex
  leftStart < right.maxIndex and rightStart < left.maxIndex

func textRangeIntersectsRect(
    range: TextRange, snapshot: TextLayoutSnapshot, bounds: Rect
): bool =
  for fragment in snapshot.lineFragments:
    if fragment.textRange.textRangesIntersect(range) and
        not fragment.fragmentRect.intersection(bounds).isEmpty:
      return true

proc resolveMarkdownRangeLayout(
    presentation: var MarkdownRangeLayout,
    range: TextRange,
    snapshot: TextLayoutSnapshot,
) =
  let layoutHash = int(snapshot.layoutHash)
  if presentation.resolved and presentation.layoutHash == layoutHash:
    return

  presentation = MarkdownRangeLayout(layoutHash: layoutHash, resolved: true)
  for fragment in snapshot.lineFragments:
    if fragment.textRange.textRangesIntersect(range):
      let fragmentRect =
        if fragment.usedRect.isEmpty: fragment.fragmentRect else: fragment.usedRect
      if presentation.rect.isEmpty:
        presentation.rect = fragmentRect
      else:
        presentation.rect = presentation.rect.union(fragmentRect)

proc configureMarkdownEmbeddedTextView(
    storage: TextStorage, backgroundColor: Color, accessibilityLabel: string
): tuple[scrollView: ScrollView, textView: TextView] =
  result.textView = newTextView()
  result.scrollView = newScrollView(documentView = result.textView)
  result.textView.propagatesIntrinsicContentSizeChanges = false
  result.textView.richText = true
  result.textView.editable = false
  result.textView.selectable = true
  result.textView.backgroundColor = backgroundColor
  result.textView.textContainer = initTextContainer(
    wraps = false, widthTracksTextView = true, heightTracksTextView = true
  )
  result.textView.textStorage = storage
  result.textView.accessibilityLabel = accessibilityLabel
  result.scrollView.hasHorizontalScroller = true
  result.scrollView.hasVerticalScroller = false
  result.scrollView.autohidePolicy = sapWhenNeeded
  result.scrollView.borderType = svbNoBorder
  result.scrollView.drawsBackground = false
  result.scrollView.clipView().backgroundColor = backgroundColor
  result.scrollView.clipView().drawsBackground = true

proc cachedMarkdownContentSize(
    textView: TextView, initialSize: Size, cachedSize: var Size, cacheValid: var bool
): Size =
  if not cacheValid:
    textView.setFrameFromLayout(rect(initPoint(0.0'f32, 0.0'f32), initialSize))
    let snapshot = textView.layoutManager().layoutSnapshot()
    cachedSize = initSize(
      max(snapshot.contentSize.width, snapshot.usedRect.maxX),
      max(snapshot.contentSize.height, snapshot.usedRect.maxY),
    )
    cacheValid = true
  cachedSize

proc ensureMarkdownCodeBlockView(
    textView: MarkdownTextView, presentation: var MarkdownCodeBlockScrollPresentation
) =
  if not presentation.scrollView.isNil:
    return
  let embedded = configureMarkdownEmbeddedTextView(
    presentation.storage, textView.codeBlockStyle.backgroundColor, "Markdown code block"
  )
  presentation.scrollView = embedded.scrollView
  presentation.textView = embedded.textView
  presentation.scrollView.setHiddenFromLayout(true)
  textView.addSubview(presentation.scrollView)

proc ensureMarkdownTableView(
    textView: MarkdownTextView, presentation: var MarkdownTableScrollPresentation
) =
  if not presentation.scrollView.isNil:
    return
  let embedded = configureMarkdownEmbeddedTextView(
    presentation.storage, textView.backgroundColor(), "Markdown table"
  )
  presentation.scrollView = embedded.scrollView
  presentation.textView = embedded.textView
  textView.addSubview(presentation.scrollView)

proc layoutMarkdownCodeBlock(
    textView: MarkdownTextView,
    presentation: var MarkdownCodeBlockScrollPresentation,
    viewportRight: float32,
    rightPadding: float32,
) =
  let codeRect = presentation.rangeLayout.rect
  if codeRect.isEmpty:
    return
  textView.ensureMarkdownCodeBlockView(presentation)
  let
    codeOrigin = codeRect.origin
    scrollView = presentation.scrollView
    codeTextView = presentation.textView
    parentCodeHeight = max(codeRect.maxY - codeOrigin.y, codeRect.size.height)
    viewportWidth = max(viewportRight - codeOrigin.x, 0.0'f32)
    initialDocumentWidth = max(codeRect.size.width, viewportWidth)
    contentSize = codeTextView.cachedMarkdownContentSize(
      initSize(initialDocumentWidth, parentCodeHeight),
      presentation.contentSize,
      presentation.contentSizeValid,
    )
  let
    codeWidth = contentSize.width
    paddedCodeWidth = codeWidth + max(rightPadding, 0.0'f32)
    codeHeight = max(parentCodeHeight, contentSize.height)
    overflowing = paddedCodeWidth > viewportWidth
    documentWidth = max(paddedCodeWidth, viewportWidth)
    scrollerHeight =
      if overflowing:
        scrollView.scrollerThickness()
      else:
        0.0'f32
  scrollView.setFrameFromLayout(
    rect(codeOrigin.x, codeOrigin.y, viewportWidth, codeHeight + scrollerHeight)
  )
  codeTextView.setFrameFromLayout(rect(0.0'f32, 0.0'f32, documentWidth, codeHeight))
  scrollView.tile()
  scrollView.setHiddenFromLayout(not overflowing)

proc layoutMarkdownCodeBlocks(
    textView: MarkdownTextView, snapshot: TextLayoutSnapshot, bufferedVisible: Rect
) =
  let
    style = textView.codeBlockStyle
    viewportRight = textView.bounds().maxX - max(style.outlineWidth, 0.0'f32)
  if viewportRight <= 0.0'f32:
    return
  for presentation in textView.markdownCodeBlocks.mitems:
    presentation.rangeLayout.resolveMarkdownRangeLayout(presentation.range, snapshot)
    if presentation.rangeLayout.rect.intersection(bufferedVisible).isEmpty:
      if not presentation.scrollView.isNil:
        presentation.scrollView.setHiddenFromLayout(true)
    else:
      textView.layoutMarkdownCodeBlock(presentation, viewportRight, style.padding.right)

proc layoutMarkdownTables(
    textView: MarkdownTextView, snapshot: TextLayoutSnapshot, bufferedVisible: Rect
) =
  let tableViewportRight = textView.bounds().maxX
  if tableViewportRight <= 0.0'f32:
    return
  for presentation in textView.markdownTables.mitems:
    presentation.rangeLayout.resolveMarkdownRangeLayout(presentation.range, snapshot)
    let tableRect = presentation.rangeLayout.rect
    if tableRect.intersection(bufferedVisible).isEmpty:
      if not presentation.scrollView.isNil:
        presentation.scrollView.setHiddenFromLayout(true)
    elif not tableRect.isEmpty:
      textView.ensureMarkdownTableView(presentation)
      let
        tableOrigin = tableRect.origin
        scrollView = presentation.scrollView
        tableTextView = presentation.textView
        parentTableHeight = max(tableRect.maxY - tableOrigin.y, tableRect.size.height)
        viewportWidth = max(tableViewportRight - tableOrigin.x, 0.0'f32)
        initialDocumentWidth = max(tableRect.size.width, viewportWidth)
        contentSize = tableTextView.cachedMarkdownContentSize(
          initSize(initialDocumentWidth, parentTableHeight),
          presentation.contentSize,
          presentation.contentSizeValid,
        )
      let
        tableWidth = contentSize.width
        tableHeight = max(parentTableHeight, contentSize.height)
        documentWidth = max(tableWidth, viewportWidth)
        scrollerHeight =
          if tableWidth > viewportWidth:
            scrollView.scrollerThickness()
          else:
            0.0'f32
      scrollView.setFrameFromLayout(
        rect(tableOrigin.x, tableOrigin.y, viewportWidth, tableHeight + scrollerHeight)
      )
      tableTextView.setFrameFromLayout(
        rect(0.0'f32, 0.0'f32, documentWidth, tableHeight)
      )
      scrollView.tile()
      scrollView.setHiddenFromLayout(false)

proc clearMarkdownTables(textView: MarkdownTextView) =
  for presentation in textView.markdownTables:
    if not presentation.scrollView.isNil:
      presentation.scrollView.removeFromSuperview()
  textView.markdownTables.setLen(0)

proc clearMarkdownCodeBlocks(textView: MarkdownTextView) =
  for presentation in textView.markdownCodeBlocks:
    if not presentation.scrollView.isNil:
      presentation.scrollView.removeFromSuperview()
  textView.markdownCodeBlocks.setLen(0)

proc installMarkdownCodeBlocks(
    textView: MarkdownTextView, codeBlocks: openArray[MarkdownCodeBlockPresentation]
) =
  textView.clearMarkdownCodeBlocks()
  for codeBlock in codeBlocks:
    textView.markdownCodeBlocks.add MarkdownCodeBlockScrollPresentation(
      range: codeBlock.range, storage: codeBlock.storage
    )
  textView.hasMarkdownEmbeddedViewport = false
  textView.setNeedsLayout()

proc installMarkdownTables(
    textView: MarkdownTextView, tables: openArray[MarkdownTablePresentation]
) =
  textView.clearMarkdownTables()
  for table in tables:
    if not table.overflowing:
      continue
    textView.markdownTables.add MarkdownTableScrollPresentation(
      range: table.range, storage: table.storage
    )
  textView.hasMarkdownEmbeddedViewport = false
  textView.setNeedsLayout()

proc markdownTextLayoutDidComplete(
    textView: MarkdownTextView, snapshot: TextLayoutSnapshot
) {.slot.} =
  discard snapshot
  textView.setNeedsLayout()

func containsRect(outer, inner: Rect): bool =
  inner.minX >= outer.minX and inner.maxX <= outer.maxX and inner.minY >= outer.minY and
    inner.maxY <= outer.maxY

proc markdownViewportGeometryDidChange(textView: MarkdownTextView) {.slot.} =
  if textView.markdownCodeBlocks.len == 0 and textView.markdownTables.len == 0:
    return
  let visible = textView.visibleRect()
  if textView.markdownViewportLayoutPending or
      textView.hasMarkdownEmbeddedViewport and
      textView.markdownEmbeddedViewport.containsRect(visible):
    return
  textView.markdownViewportLayoutPending = true
  scheduleMainThreadWork(
    proc(): bool =
      textView.markdownViewportLayoutPending = false
      let currentVisible = textView.visibleRect()
      if not textView.hasMarkdownEmbeddedViewport or
          not textView.markdownEmbeddedViewport.containsRect(currentVisible):
        textView.setNeedsLayout()
      false
  )

protocol MarkdownTextViewLayout of ViewLayoutProtocol:
  method layoutSubviews(textView: MarkdownTextView) =
    if textView.markdownCodeBlocks.len == 0 and textView.markdownTables.len == 0:
      return
    let
      snapshot = textView.layoutManager().layoutSnapshot()
      bufferedVisible = textView.visibleRect().verticallyBuffered()
    textView.markdownEmbeddedViewport = bufferedVisible
    textView.hasMarkdownEmbeddedViewport = true
    textView.layoutMarkdownCodeBlocks(snapshot, bufferedVisible)
    textView.layoutMarkdownTables(snapshot, bufferedVisible)

protocol MarkdownTextViewDrawing of ViewDrawingProtocol:
  method drawUnderlay(textView: MarkdownTextView, context: DrawContext) =
    let revision = textView.renderSlotRevision(MarkdownUnderlayRenderSlot)
    if context.beginRenderSlot(MarkdownUnderlayRenderSlot, revision):
      let
        bufferedVisible = context.visibleRect().verticallyBuffered()
        snapshot = textView.layoutManager().layoutSnapshot()
        style = textView.codeBlockStyle
      textView.markdownViewportGeometryDidChange()
      if style.backgroundColor.a > 0.0'f32 or
          (style.outlineColor.a > 0.0'f32 and style.outlineWidth > 0.0'f32):
        var blockRects: seq[Rect]
        for presentation in textView.markdownCodeBlocks.mitems:
          presentation.rangeLayout.resolveMarkdownRangeLayout(
            presentation.range, snapshot
          )
          let blockRect = textView.codeBlockRect(presentation.rangeLayout.rect, style)
          if not blockRect.intersection(bufferedVisible).isEmpty:
            blockRects.add blockRect
        blockRects.sort(
          proc(left, right: Rect): int =
            cmp(left.minY, right.minY)
        )
        for blockRect in blockRects:
          discard context.addRenderRectangle(
            context.renderRectFor(blockRect),
            fill(style.backgroundColor),
            style.outlineColor,
            max(style.outlineWidth, 0.0'f32),
            max(style.cornerRadius, 0.0'f32),
          )
      for presentation in textView.markdownImages:
        if presentation.range.textRangeIntersectsRect(snapshot, bufferedVisible):
          let imageRect = textView.imageRect(presentation)
          if not imageRect.isEmpty:
            discard context.addImage(imageRect, presentation.image)
    TextView(textView).drawTextViewUnderlayInViewport(context)

  method draw(textView: MarkdownTextView, context: DrawContext) =
    TextView(textView).drawTextViewTextInViewport(context)

  method drawOverlay(textView: MarkdownTextView, context: DrawContext) =
    TextView(textView).drawTextViewOverlay(context)

func markdownImageCacheKey(view: MarkdownView, url: string): string

proc pruneMarkdownImageCache(view: MarkdownView, imageUrls: openArray[string]) =
  var activeKeys = initTable[string, bool]()
  for url in imageUrls:
    activeKeys[view.markdownImageCacheKey(url)] = true

  var obsoleteKeys: seq[string]
  for key in view.xImageCache.keys:
    if key notin activeKeys:
      obsoleteKeys.add(key)
  for key in obsoleteKeys:
    view.xImageCache.del(key)

  obsoleteKeys.setLen(0)
  for key in view.xImageMediaTypes.keys:
    if key notin activeKeys:
      obsoleteKeys.add(key)
  for key in obsoleteKeys:
    view.xImageMediaTypes.del(key)

  var obsoleteUrls: seq[string]
  for url in view.xPendingUrlAssets.keys:
    if view.markdownImageCacheKey(url) notin activeKeys:
      obsoleteUrls.add(url)
  for url in obsoleteUrls:
    view.xPendingUrlAssets.del(url)

proc applyMarkdownDocument(view: MarkdownView, document: sink MarkdownDocument) =
  let textView = MarkdownTextView(view.textView())
  textView.codeBlockStyle = view.xMarkdownStyle.codeBlockStyle
  textView.markdownImages = document.images
  view.xHasMarkdownTables = document.hasTables
  view.minimumWrappedDocumentWidth = 0.0'f32
  if document.storage.len >= MarkdownBackgroundLayoutMinimumLength and
      textView.layoutManager().usesBackgroundLayout():
    textView.textStorage = document.storage
    textView.layoutManager().requestBackgroundLayout(allowUncachedLayout = true)
    view.setNeedsLayout()
  else:
    view.textStorage = document.storage
  textView.installMarkdownCodeBlocks(document.codeBlocks)
  textView.installMarkdownTables(document.tables)
  view.pruneMarkdownImageCache(document.imageUrls)
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

proc markdownTableCharacterWidth(view: MarkdownView): float32 =
  let codeStyle = TextStyle(
    color: view.xMarkdownStyle.textColor,
    fontName: view.xMarkdownStyle.codeFontName,
    fontSize: max(view.xMarkdownStyle.bodyFontSize * MarkdownTableFontScale, 1.0'f32),
  )
  max(textNaturalSize("M", codeStyle).width, 1.0'f32)

proc markdownTableColumnLimit(view: MarkdownView): int =
  if view.isNil:
    return MarkdownTableDefaultColumnLimit
  let
    characterWidth = view.markdownTableCharacterWidth()
    viewportWidth = view.bounds().size.width
    availableWidth =
      max(viewportWidth - view.xMarkdownStyle.documentInsets.horizontal, characterWidth)
    measuredLimit = int(availableWidth * MarkdownTableViewportFraction / characterWidth)
    quantizedLimit =
      (measuredLimit div MarkdownTableColumnQuantum) * MarkdownTableColumnQuantum
  clamp(
    quantizedLimit, MarkdownTableMinimumColumnLimit, MarkdownTableMaximumColumnLimit
  )

proc scheduleMarkdownTableResize(view: MarkdownView) =
  if view.isNil or not view.xHasMarkdownTables:
    return
  view.xMarkdownTableResizeDeadline = getMonoTime() + MarkdownTableResizeDebounce
  if view.xMarkdownTableResizePending:
    return

  view.xMarkdownTableResizePending = true
  scheduleMainThreadWork(
    proc(): bool =
      if getMonoTime() < view.xMarkdownTableResizeDeadline:
        return true

      view.xMarkdownTableResizePending = false
      if view.xHasMarkdownTables and view.xActiveMarkdownGeneration == 0 and
          view.markdownTableColumnLimit() != view.xMarkdownTableColumnLimit:
        view.renderCurrentMarkdownDocument()
      false
  )

proc markdownViewGeometryDidChange(view: MarkdownView) {.slot.} =
  view.scheduleMarkdownTableResize()

proc markdownUrlAssetDidFinish(view: MarkdownView, handle: UrlAssetHandle) {.slot.} =
  let url = handle.result().url
  if url notin view.xPendingUrlAssets or view.xPendingUrlAssets[url] != handle:
    return
  view.xPendingUrlAssets.del(url)
  if not view.xImageLoader.isNil or not handle.succeeded():
    return
  try:
    let key = view.markdownImageCacheKey(url)
    let image = view.imageForMarkdownDisplay(
      newImageResourceFromFile(handle.result().path, name = url)
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
        result = newImageResourceFromFile(path, name = path)
        view.xImageMediaTypes[key] = parsedUrl.mediaType()
      elif parsedUrl.isHttpUrl():
        let handle = view.resolvedUrlAssetLoader().load(url)
        if handle.succeeded():
          result = newImageResourceFromFile(handle.result().path, name = url)
          view.xImageMediaTypes[key] = handle.result().mediaType
        else:
          view.xPendingUrlAssets[url] = handle
    if not result.isNil:
      result = view.imageForMarkdownDisplay(result)
      view.xImageCache[key] = result
  except CatchableError:
    result = nil

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
  let
    generation = view.xMarkdownRenderGeneration
    tableColumnLimit = view.markdownTableColumnLimit()
  view.xMarkdownTableColumnLimit = tableColumnLimit
  view.xActiveMarkdownRenderGeneration = generation
  view.xMarkdownRenderJob = MarkdownRenderJob(
    generation: generation,
    rootGeneration: view.xMarkdownRootGeneration,
    root: view.xMarkdownRoot,
    nextBlock: view.xMarkdownRoot.children.head,
    builder: MarkdownBuilder(
      style: view.xMarkdownStyle,
      syntaxHighlighter: view.xSyntaxHighlighter,
      tableColumnLimit: tableColumnLimit,
    ),
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
  ## Return whether incremental rendering or table resize reflow is pending.
  not view.isNil and
    (view.xActiveMarkdownRenderGeneration != 0 or view.xMarkdownTableResizePending)

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
  if view.xActiveMarkdownRenderGeneration != 0:
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
  ## Poll until incremental rendering and table resize reflow finish.
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

proc clampMarkdownKeyboardScrollTarget(scrollView: ScrollView, target: Point): Point =
  let maximum = scrollView.maximumContentOffset()
  initPoint(
    min(max(target.x, 0.0'f32), maximum.x), min(max(target.y, 0.0'f32), maximum.y)
  )

proc finishMarkdownKeyboardScroll(view: MarkdownView) {.slot.} =
  view.xKeyboardScrollAnimation = nil

proc stopMarkdownKeyboardScroll(view: MarkdownView) =
  let animation = view.xKeyboardScrollAnimation
  if animation.isNil:
    return
  view.xKeyboardScrollAnimation = nil
  let owner = view.window()
  if owner of Window:
    discard Window(owner).stopAnimation(animation)
  else:
    animation.stop()

proc scrollMarkdownBy(view: MarkdownView, delta: Point) =
  let scrollView = view.scrollView()
  if scrollView.isNil:
    return
  let
    current = scrollView.contentOffset()
    start =
      if not view.xKeyboardScrollAnimation.isNil and
          view.xKeyboardScrollAnimation.isRunning:
        view.xKeyboardScrollTarget
      else:
        current
    target = scrollView.clampMarkdownKeyboardScrollTarget(
      initPoint(start.x + delta.x, start.y + delta.y)
    )
  view.stopMarkdownKeyboardScroll()
  if target == current:
    return

  let animation = newContentOffsetAnimation(
    scrollView,
    current,
    target,
    duration = MarkdownKeyboardScrollDuration,
    timing = easeOutTiming(),
  )
  view.xKeyboardScrollTarget = target
  view.xKeyboardScrollAnimation = Animation(animation)
  animation.connect(finished, view, finishMarkdownKeyboardScroll)
  let owner = view.window()
  if not (owner of Window) or not Window(owner).startAnimation(animation):
    view.xKeyboardScrollAnimation = nil
    scrollView.contentOffset = target

proc handleMarkdownNavigationKey*(view: MarkdownView, event: KeyEvent): bool =
  if view.isNil or event.modifiers != {}:
    return
  let scrollView = view.scrollView()
  if scrollView.isNil:
    return
  let delta =
    case event.key
    of keyArrowLeft:
      initPoint(
        -scrollView.lineScroll(laHorizontal) * MarkdownKeyboardScrollRows, 0.0'f32
      )
    of keyArrowRight:
      initPoint(
        scrollView.lineScroll(laHorizontal) * MarkdownKeyboardScrollRows, 0.0'f32
      )
    of keyArrowUp:
      initPoint(
        0.0'f32, -scrollView.lineScroll(laVertical) * MarkdownKeyboardScrollRows
      )
    of keyArrowDown:
      initPoint(0.0'f32, scrollView.lineScroll(laVertical) * MarkdownKeyboardScrollRows)
    of keyK:
      initPoint(0.0'f32, -scrollView.lineScroll(laVertical))
    of keyJ:
      initPoint(0.0'f32, scrollView.lineScroll(laVertical))
    of keySpace:
      initPoint(
        0.0'f32, scrollView.viewportSize().height * MarkdownKeyboardPageFraction
      )
    else:
      return
  view.scrollMarkdownBy(delta)
  true

protocol MarkdownViewKeyEquivalents of ResponderCommandDispatchProtocol:
  method performKeyEquivalent(view: MarkdownView, event: KeyEvent): bool =
    view.handleMarkdownNavigationKey(event)

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

proc syntaxHighlighter*(view: MarkdownView): SyntaxHighlighter =
  ## Return the classifier used for fenced code blocks.
  view.xSyntaxHighlighter

proc `syntaxHighlighter=`*(view: MarkdownView, highlighter: SyntaxHighlighter) =
  ## Replace the classifier and rerender fenced code blocks.
  view.xSyntaxHighlighter = highlighter
  view.renderCurrentMarkdownDocument()

proc markdownStyle*(view: MarkdownView): MarkdownStyle =
  ## Returns a copy of the current document presentation.
  view.xMarkdownStyle

proc `markdownStyle=`*(view: MarkdownView, style: MarkdownStyle) =
  ## Applies `style` and incrementally rerenders the current source.
  if view.xMarkdownStyle == style:
    return
  let maximumImageSizeChanged =
    view.xMarkdownStyle.maximumImageSize != style.maximumImageSize
  view.xMarkdownStyle = style
  if maximumImageSizeChanged:
    view.xImageCache.clear()
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
    syntaxHighlighter: SyntaxHighlighter = matterSyntaxHighlighter,
) =
  ## Initializes a custom `MarkdownView` subtype.
  ##
  ## HTTP(S) images use `urlAssetLoader`, or a lazy shared loader when it is nil.
  let textView = MarkdownTextView()
  textView.initTextViewFields()
  discard textView.withProtocol(MarkdownTextViewLayout)
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
  view.xSyntaxHighlighter = syntaxHighlighter
  view.xImageCache = initTable[string, ImageResource]()
  view.xImageMediaTypes = initTable[string, string]()
  view.xPendingUrlAssets = initTable[string, UrlAssetHandle]()
  view.xMarkdownTableColumnLimit = view.markdownTableColumnLimit()
  view.xMarkdown = source
  view.editable = false
  view.selectable = true
  view.allowsUndo = false
  view.scrollView().borderType = svbNoBorder
  discard view.withProtocol(MarkdownViewKeyEquivalents)
  view.connect(geometryDidChange, view, markdownViewGeometryDidChange)
  view.accessibilityLabel = "Markdown document"
  view.applyMarkdownStyle()
  view.applyMarkdownDocument(
    view.xMarkdownRoot.markdownDocument(style, syntaxHighlighter = syntaxHighlighter)
  )
  view.textView().layoutManager().usesBackgroundLayout = true
  textView.layoutManager().connect(
    layoutDidComplete, textView, markdownTextLayoutDidComplete
  )
  view.scheduleMarkdownParse()

proc newMarkdownView*(
    source = "",
    frame: Rect = AutoRect,
    style = initMarkdownStyle(),
    config: MarkdownParserConfig = nil,
    imageBasePath = "",
    imageLoader: MarkdownImageLoader = nil,
    urlAssetLoader: UrlAssetLoader = nil,
    syntaxHighlighter: SyntaxHighlighter = matterSyntaxHighlighter,
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
    source, frame, style, config, imageBasePath, imageLoader, urlAssetLoader,
    syntaxHighlighter,
  )
