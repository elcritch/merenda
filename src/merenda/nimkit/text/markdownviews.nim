## Native Markdown rendering for NimKit text views.
##
## The renderer converts a CommonMark or GFM syntax tree into attributed NimKit
## text. Raw HTML stays inert and images use linked alt text, so displaying an
## untrusted document does not require an embedded browser.

import std/[lists, strutils, unicode]

import markdown as markdownParser
from markdownpkg/entities import htmlEntityToUtf8

import ../accessibility/accessibility
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
    codeFontName*: string ## Monospace font for code and tables.
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

  MarkdownBuilder = object
    text: string
    runs: seq[TextAttributeRun]
    style: MarkdownStyle

proc initMarkdownStyle*(): MarkdownStyle =
  ## Returns the light paper-style default presentation.
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
    bodyFontName: defaultFontName(frUI),
    codeFontName: defaultFontName(frMonospace),
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

proc add(builder: var MarkdownBuilder, value: string, attributes: TextAttributes) =
  let length = value.runeLen
  if length == 0:
    return
  let start = builder.text.runeLen
  builder.text.add value
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

proc add(builder: var MarkdownBuilder, rendered: MarkdownBuilder) =
  for run in rendered.runs:
    builder.add(
      rendered.text.runeSubStr(int(run.range.location), int(run.range.length)),
      run.attributes,
    )

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
    builder.renderInlineChildren(token, emphasisAttributes)
  elif token of markdownParser.Strong:
    var strongAttributes = attributes
    strongAttributes.foregroundColor = builder.style.strongColor
    strongAttributes.fontSize =
      max(strongAttributes.fontSize * 1.04'f32, builder.style.bodyFontSize)
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
    let image = markdownParser.Image(token)
    var imageAttributes = attributes
    imageAttributes.foregroundColor = builder.style.linkColor
    imageAttributes.link = image.url
    builder.add(builder.style.imagePrefix, imageAttributes)
    if token.children.head.isNil:
      builder.add(image.alt, imageAttributes)
    else:
      builder.renderInlineChildren(token, imageAttributes)
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
    var rendered = MarkdownBuilder(style: builder.style)
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

  var quoted = MarkdownBuilder(style: builder.style)
  quoted.renderContainer(quote, quoteAttributes)
  if quoted.text.len == 0:
    builder.add(builder.style.quotePrefix, prefixAttributes)
    return

  let runes = quoted.text.toRunes()
  var
    atLineStart = true
    runIndex = 0
  for index, rune in runes:
    while runIndex < quoted.runs.high and index >= quoted.runs[runIndex].range.maxIndex:
      inc runIndex
    if atLineStart:
      builder.add(builder.style.quotePrefix, prefixAttributes)
      atLineStart = false
    builder.add($rune, quoted.runs[runIndex].attributes)
    if rune == Rune('\n'):
      atLineStart = true

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
    let codeAttributes = builder.style.codeAttributes(attributes)
    if code.info.len > 0:
      builder.add(
        "[" & code.info & "]\n", builder.style.mutedCodeAttributes(attributes)
      )
    builder.add(code.doc.strip(chars = {'\n'}), codeAttributes)
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

proc toTextStorage(builder: sink MarkdownBuilder): TextStorage =
  newTextStorage(builder.text, builder.runs)

proc markdownTextStorage*(
    source: string, style = initMarkdownStyle(), config: MarkdownParserConfig = nil
): TextStorage =
  ## Parses `source` and returns native attributed text without creating a view.
  ## A nil configuration selects GFM so tables and strikethrough work by default.
  let root = markdownParser.Document()
  discard markdownParser.markdown(source, config.resolvedConfig(), root)

  var builder = MarkdownBuilder(style: style)
  let attributes = style.bodyAttributes()
  builder.renderContainer(root, attributes)
  builder.toTextStorage()

proc applyMarkdownStyle(view: MarkdownView) =
  view.textInsets = view.xMarkdownStyle.documentInsets
  view.backgroundColor = view.xMarkdownStyle.backgroundColor
  view.textColor = view.xMarkdownStyle.textColor
  view.textView().backgroundColor = view.xMarkdownStyle.backgroundColor
  view.scrollView().drawsBackground = false

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
  let storage = markdownTextStorage(source, view.xMarkdownStyle, view.xMarkdownConfig)
  view.xMarkdown = source
  view.textStorage = storage

proc markdownStyle*(view: MarkdownView): MarkdownStyle =
  ## Returns a copy of the current document presentation.
  view.xMarkdownStyle

proc `markdownStyle=`*(view: MarkdownView, style: MarkdownStyle) =
  ## Applies `style` and rerenders the current source.
  if view.xMarkdownStyle == style:
    return
  let storage = markdownTextStorage(view.xMarkdown, style, view.xMarkdownConfig)
  view.xMarkdownStyle = style
  view.applyMarkdownStyle()
  view.textStorage = storage

proc markdownConfig*(view: MarkdownView): MarkdownParserConfig =
  ## Returns the active parser configuration.
  view.xMarkdownConfig

proc `markdownConfig=`*(view: MarkdownView, config: MarkdownParserConfig) =
  ## Applies `config` and reparses the current source; nil selects GFM.
  let resolved = config.resolvedConfig()
  if view.xMarkdownConfig == resolved:
    return
  let storage = markdownTextStorage(view.xMarkdown, view.xMarkdownStyle, resolved)
  view.xMarkdownConfig = resolved
  view.textStorage = storage

proc initMarkdownViewFields*(
    view: MarkdownView,
    source = "",
    frame: Rect = AutoRect,
    style = initMarkdownStyle(),
    config: MarkdownParserConfig = nil,
) =
  ## Initializes a custom `MarkdownView` subtype.
  initTextEditorFields(view, frame = frame, richText = true, wraps = true)
  view.xMarkdownStyle = style
  view.xMarkdownConfig = config.resolvedConfig()
  view.xMarkdown = source
  view.editable = false
  view.selectable = true
  view.allowsUndo = false
  view.scrollView().borderType = svbNoBorder
  view.accessibilityLabel = "Markdown document"
  view.applyMarkdownStyle()
  view.textStorage = markdownTextStorage(source, style, view.xMarkdownConfig)

proc newMarkdownView*(
    source = "",
    frame: Rect = AutoRect,
    style = initMarkdownStyle(),
    config: MarkdownParserConfig = nil,
): MarkdownView =
  ## Creates a scrollable, selectable, read-only Markdown document view.
  result = MarkdownView()
  result.initMarkdownViewFields(source, frame, style, config)
