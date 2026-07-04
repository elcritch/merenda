## SynEdit-style source editor widget adapted from nim-lang/uirelays.
##
## The public language/theme/token model follows the uirelays SynEdit widget,
## while editing, selection, scrolling, and text input are delegated to
## Merenda's TextEditor/TextView stack.

import std/[math, strutils, unicode]

import sigils/core
import sigils/selectors

import ../accessibility/accessibilityprotocols
import ../containers/scrollviews
import ../drawing
import ../foundation/selectors
import ../foundation/types
import ../themes
import ../text/texteditors
import ../text/textstorage
import ../text/texttypes
import ../text/textviews
import ../view/views

export texteditors
export textstorage
export texttypes
export textviews

type
  SourceLanguage* = enum
    langNone
    langNim
    langCpp
    langCsharp
    langC
    langJava
    langJs
    langXml
    langHtml
    langConsole
    langPython
    langRust
    langMarkdown

  SynEditTokenClass* {.pure.} = enum
    None
    Whitespace
    DecNumber
    BinNumber
    HexNumber
    OctNumber
    FloatNumber
    Identifier
    Keyword
    StringLit
    LongStringLit
    CharLit
    Backticks
    EscapeSequence
    Operator
    Punctuation
    Comment
    LongComment
    RegularExpression
    TagStart
    TagStandalone
    TagEnd
    Key
    Value
    RawData
    Assembler
    Preprocessor
    Directive
    Command
    Rule
    Link
    Label
    Reference
    Text
    Other
    Green
    Yellow
    Red
    MarkdownFence

  SynEditTheme* = object
    foreground*: array[SynEditTokenClass, Color]
    background*: Color
    selectionBackground*: Color
    bracketBackground*: Color
    cursorColor*: Color
    lineNumberColor*: Color
    markerBackground*: Color
    scrollBarColor*: Color
    scrollBarActiveColor*: Color
    scrollTrackColor*: Color

  SynEditTokenSpan* = object
    range*: TextRange
    token*: SynEditTokenClass

  SynEditView* = ref object of View
    xEditor: TextEditor
    xGutter: SynEditGutterView
    xLanguage: SourceLanguage
    xTheme: SynEditTheme
    xShowLineNumbers: bool
    xLineNumberWidth: float32
    xFontSize: float32
    xApplyingHighlight: bool

  SynEditGutterView = ref object of View
    xOwner: SynEditView

const
  DefaultSynEditWidth = 640.0'f32
  DefaultSynEditHeight = 360.0'f32
  DefaultSynEditLineNumberWidth = 52.0'f32
  DefaultSynEditFontSize = 14.0'f32

  NimKeywords = [
    "addr", "and", "as", "asm", "atomic", "bind", "block", "break", "case", "cast",
    "concept", "const", "continue", "converter", "defer", "discard", "distinct", "div",
    "do", "elif", "else", "end", "enum", "except", "export", "finally", "for", "from",
    "func", "generic", "if", "import", "in", "include", "interface", "is", "isnot",
    "iterator", "let", "macro", "method", "mixin", "mod", "nil", "not", "notin",
    "object", "of", "or", "out", "proc", "ptr", "raise", "ref", "return", "shl", "shr",
    "static", "template", "try", "tuple", "type", "using", "var", "when", "while",
    "with", "without", "xor", "yield",
  ]

func rgb(r, g, b: int): Color =
  color(r.float32 / 255.0'f32, g.float32 / 255.0'f32, b.float32 / 255.0'f32, 1.0)

func catppuccinMochaSynEditTheme*(): SynEditTheme =
  let base = rgb(205, 214, 244)
  for token in SynEditTokenClass:
    result.foreground[token] = base
  result.foreground[SynEditTokenClass.Keyword] = rgb(203, 166, 247)
  result.foreground[SynEditTokenClass.StringLit] = rgb(166, 227, 161)
  result.foreground[SynEditTokenClass.LongStringLit] = rgb(166, 227, 161)
  result.foreground[SynEditTokenClass.CharLit] = rgb(166, 227, 161)
  result.foreground[SynEditTokenClass.RawData] = rgb(166, 227, 161)
  result.foreground[SynEditTokenClass.Comment] = rgb(108, 112, 134)
  result.foreground[SynEditTokenClass.LongComment] = rgb(108, 112, 134)
  result.foreground[SynEditTokenClass.DecNumber] = rgb(250, 179, 135)
  result.foreground[SynEditTokenClass.BinNumber] = rgb(250, 179, 135)
  result.foreground[SynEditTokenClass.HexNumber] = rgb(250, 179, 135)
  result.foreground[SynEditTokenClass.OctNumber] = rgb(250, 179, 135)
  result.foreground[SynEditTokenClass.FloatNumber] = rgb(250, 179, 135)
  result.foreground[SynEditTokenClass.Operator] = rgb(137, 180, 250)
  result.foreground[SynEditTokenClass.Punctuation] = rgb(147, 153, 178)
  result.foreground[SynEditTokenClass.EscapeSequence] = rgb(245, 194, 231)
  result.foreground[SynEditTokenClass.Preprocessor] = rgb(203, 166, 247)
  result.foreground[SynEditTokenClass.Green] = rgb(166, 227, 161)
  result.foreground[SynEditTokenClass.Yellow] = rgb(249, 226, 175)
  result.foreground[SynEditTokenClass.Red] = rgb(243, 139, 168)
  result.foreground[SynEditTokenClass.MarkdownFence] = rgb(128, 128, 128)
  result.background = rgb(30, 30, 46)
  result.selectionBackground = rgb(88, 91, 112)
  result.bracketBackground = rgb(69, 71, 90)
  result.cursorColor = base
  result.lineNumberColor = rgb(108, 112, 134)
  result.markerBackground = rgb(62, 68, 43)
  result.scrollBarColor = rgb(69, 71, 90)
  result.scrollBarActiveColor = rgb(108, 112, 134)
  result.scrollTrackColor = rgb(36, 36, 54)

func synEditTheme*(): SynEditTheme =
  catppuccinMochaSynEditTheme()

func fileExtToLanguage*(ext: string): SourceLanguage =
  case ext.toLowerAscii()
  of ".nim", ".nims", ".nimble": langNim
  of ".cpp", ".hpp", ".cxx", ".h": langCpp
  of ".c": langC
  of ".js": langJs
  of ".java": langJava
  of ".cs": langCsharp
  of ".xml": langXml
  of ".html", ".htm": langHtml
  of ".py", ".pyw": langPython
  of ".rs": langRust
  of ".md", ".markdown": langMarkdown
  else: langNone

func asciiAt(runes: openArray[Rune], index: int): char =
  if index < 0 or index >= runes.len:
    '\0'
  elif runes[index].int >= 0 and runes[index].int <= 255:
    char(runes[index].int)
  else:
    '\x80'

func isIdentChar(ch: char): bool =
  ch in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '\x80' .. '\xFF'}

func isOperatorChar(ch: char): bool =
  ch in {
    '+',
    '-',
    '*',
    '/',
    '\\',
    '<',
    '>',
    '!',
    '?',
    '^',
    '.',
    '|',
    '=',
    '%',
    '&',
    '$',
    '@',
    '~',
    ':',
    '\x80' .. '\xFF',
  }

func isNimKeyword(word: string): bool =
  for keyword in NimKeywords:
    if word == keyword:
      return true

func span(start, stop: int, token: SynEditTokenClass): SynEditTokenSpan =
  SynEditTokenSpan(range: initTextRange(start, max(stop - start, 0)), token: token)

proc scanNimNumber(
    runes: openArray[Rune], start: int
): tuple[stop: int, token: SynEditTokenClass] =
  var index = start
  result.token = SynEditTokenClass.DecNumber
  if asciiAt(runes, index) == '0':
    let next = asciiAt(runes, index + 1)
    if next in {'x', 'X'}:
      index += 2
      while asciiAt(runes, index) in {'0' .. '9', 'a' .. 'f', 'A' .. 'F', '_'}:
        inc index
      result.stop = index
      result.token = SynEditTokenClass.HexNumber
      return
    if next in {'b', 'B'}:
      index += 2
      while asciiAt(runes, index) in {'0', '1', '_'}:
        inc index
      result.stop = index
      result.token = SynEditTokenClass.BinNumber
      return
    if next in {'o', 'O'}:
      index += 2
      while asciiAt(runes, index) in {'0' .. '7', '_'}:
        inc index
      result.stop = index
      result.token = SynEditTokenClass.OctNumber
      return

  while asciiAt(runes, index) in {'0' .. '9', '_'}:
    inc index
  if asciiAt(runes, index) == '.' and asciiAt(runes, index + 1) != '.':
    result.token = SynEditTokenClass.FloatNumber
    inc index
    while asciiAt(runes, index) in {'0' .. '9', '_'}:
      inc index
  if asciiAt(runes, index) in {'e', 'E'}:
    result.token = SynEditTokenClass.FloatNumber
    inc index
    if asciiAt(runes, index) in {'+', '-'}:
      inc index
    while asciiAt(runes, index) in {'0' .. '9', '_'}:
      inc index
  result.stop = index

proc scanQuoted(
    runes: openArray[Rune], start: int, quote: char, token: SynEditTokenClass
): SynEditTokenSpan =
  var index = start + 1
  while index < runes.len:
    let ch = asciiAt(runes, index)
    if ch == '\n' or ch == '\r':
      break
    if ch == '\\':
      index += 2
    elif ch == quote:
      inc index
      break
    else:
      inc index
  span(start, index, token)

proc scanTripleString(runes: openArray[Rune], start: int): SynEditTokenSpan =
  var index = start + 3
  while index < runes.len:
    if asciiAt(runes, index) == '"' and asciiAt(runes, index + 1) == '"' and
        asciiAt(runes, index + 2) == '"':
      index += 3
      break
    inc index
  span(start, index, SynEditTokenClass.LongStringLit)

proc scanNimMultilineComment(runes: openArray[Rune], start: int): SynEditTokenSpan =
  var index = start + 2
  while index < runes.len:
    if asciiAt(runes, index) == ']' and asciiAt(runes, index + 1) == '#':
      index += 2
      break
    inc index
  span(start, index, SynEditTokenClass.LongComment)

proc scanNimTokens(text: string): seq[SynEditTokenSpan] =
  let runes = text.toRunes()
  var index = 0
  while index < runes.len:
    let start = index
    case asciiAt(runes, index)
    of ' ', '\t', '\r', '\n':
      while asciiAt(runes, index) in {' ', '\t', '\r', '\n'}:
        inc index
      result.add span(start, index, SynEditTokenClass.Whitespace)
    of '#':
      if asciiAt(runes, index + 1) == '[':
        let token = scanNimMultilineComment(runes, index)
        index = token.range.maxIndex
        result.add token
      else:
        while index < runes.len and asciiAt(runes, index) notin {'\n', '\r'}:
          inc index
        result.add span(start, index, SynEditTokenClass.Comment)
    of '"':
      let token =
        if asciiAt(runes, index + 1) == '"' and asciiAt(runes, index + 2) == '"':
          scanTripleString(runes, index)
        else:
          scanQuoted(runes, index, '"', SynEditTokenClass.StringLit)
      index = token.range.maxIndex
      result.add token
    of '\'':
      let token = scanQuoted(runes, index, '\'', SynEditTokenClass.CharLit)
      index = token.range.maxIndex
      result.add token
    of '0' .. '9':
      let number = scanNimNumber(runes, index)
      index = number.stop
      result.add span(start, index, number.token)
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var word = ""
      while asciiAt(runes, index).isIdentChar():
        word.add runes[index].toUTF8()
        inc index
      let token =
        if word.isNimKeyword():
          SynEditTokenClass.Keyword
        else:
          SynEditTokenClass.Identifier
      result.add span(start, index, token)
    of '(', '[', '{', ')', ']', '}', '`', ':', ',', ';':
      inc index
      result.add span(start, index, SynEditTokenClass.Punctuation)
    of '.':
      if asciiAt(runes, index + 1) in {')', ']', '}'}:
        index += 2
        result.add span(start, index, SynEditTokenClass.Punctuation)
      else:
        inc index
        result.add span(start, index, SynEditTokenClass.Operator)
    else:
      if asciiAt(runes, index).isOperatorChar():
        while asciiAt(runes, index).isOperatorChar():
          inc index
        result.add span(start, index, SynEditTokenClass.Operator)
      else:
        inc index
        result.add span(start, index, SynEditTokenClass.None)

proc scanMarkdownTokens(text: string): seq[SynEditTokenSpan] =
  let runes = text.toRunes()
  var
    lineStart = 0
    index = 0
    inFence = false
  while lineStart < runes.len:
    index = lineStart
    while index < runes.len and asciiAt(runes, index) notin {'\n', '\r'}:
      inc index
    let
      lineStop = index
      line = text.runeSubStr(lineStart, lineStop - lineStart)
      stripped = line.strip()
      token =
        if stripped.startsWith("```"):
          inFence = not inFence
          SynEditTokenClass.MarkdownFence
        elif inFence:
          SynEditTokenClass.RawData
        elif stripped.startsWith("#"):
          SynEditTokenClass.Keyword
        elif stripped.startsWith("-") or stripped.startsWith("*"):
          SynEditTokenClass.Punctuation
        else:
          SynEditTokenClass.Text
    if lineStop > lineStart:
      result.add span(lineStart, lineStop, token)
    if index < runes.len:
      let newlineStart = index
      while index < runes.len and asciiAt(runes, index) in {'\n', '\r'}:
        inc index
      result.add span(newlineStart, index, SynEditTokenClass.Whitespace)
    lineStart = index

proc synEditTokenSpans*(text: string, language: SourceLanguage): seq[SynEditTokenSpan] =
  case language
  of langNim:
    scanNimTokens(text)
  of langMarkdown:
    scanMarkdownTokens(text)
  else:
    if text.runeLen > 0:
      @[span(0, text.runeLen, SynEditTokenClass.Text)]
    else:
      @[]

proc synEditTokenAt*(
    spans: openArray[SynEditTokenSpan], index: int
): SynEditTokenClass =
  for item in spans:
    if index >= int(item.range.location) and index < item.range.maxIndex:
      return item.token
  SynEditTokenClass.None

func lineCountOf(text: string): int =
  result = 1
  for ch in text:
    if ch == '\n':
      inc result

proc textAttributes(view: SynEditView, token: SynEditTokenClass): TextAttributes =
  defaultTextAttributes(view.xTheme.foreground[token], view.xFontSize)

proc updateGutter(view: SynEditView)
proc applySynEditTheme(view: SynEditView)

proc textEditor*(view: SynEditView): TextEditor =
  if view.isNil: nil else: view.xEditor

proc textView*(view: SynEditView): TextView =
  if view.isNil or view.xEditor.isNil:
    nil
  else:
    view.xEditor.textView()

proc scrollView*(view: SynEditView): ScrollView =
  if view.isNil or view.xEditor.isNil:
    nil
  else:
    view.xEditor.scrollView()

proc gutterView*(view: SynEditView): View =
  if view.isNil:
    nil
  else:
    View(view.xGutter)

proc stringValue*(view: SynEditView): string =
  if view.isNil or view.xEditor.isNil:
    ""
  else:
    view.xEditor.stringValue()

proc applySyntaxHighlighting*(view: SynEditView) =
  if view.isNil or view.xEditor.isNil or view.xApplyingHighlight:
    return
  let
    storage = view.xEditor.textStorage()
    total = storage.len()
  view.xApplyingHighlight = true
  storage.beginEditing()
  if total > 0:
    storage.setAttributes(
      initTextRange(0, total), view.textAttributes(SynEditTokenClass.None)
    )
    for item in synEditTokenSpans(storage.stringValue(), view.xLanguage):
      if item.range.length > 0:
        storage.setAttributes(item.range, view.textAttributes(item.token))
  storage.endEditing()
  if not view.xEditor.textView().isNil:
    view.xEditor.textView().layoutManager().invalidateLayout()
    view.xEditor.textView().setNeedsDisplay(true)
  view.xApplyingHighlight = false

proc `stringValue=`*(view: SynEditView, value: string) =
  if view.isNil or view.xEditor.isNil:
    return
  if view.xEditor.stringValue() == value:
    return
  view.xEditor.stringValue = value
  view.updateGutter()
  view.applySyntaxHighlighting()

proc text*(view: SynEditView): string =
  view.stringValue()

proc `text=`*(view: SynEditView, value: string) =
  view.stringValue = value

proc language*(view: SynEditView): SourceLanguage =
  if view.isNil: langNone else: view.xLanguage

proc `language=`*(view: SynEditView, language: SourceLanguage) =
  if view.isNil or view.xLanguage == language:
    return
  view.xLanguage = language
  view.applySyntaxHighlighting()

proc theme*(view: SynEditView): SynEditTheme =
  if view.isNil:
    synEditTheme()
  else:
    view.xTheme

proc `theme=`*(view: SynEditView, theme: SynEditTheme) =
  if view.isNil:
    return
  view.xTheme = theme
  view.applySynEditTheme()
  view.applySyntaxHighlighting()
  view.setNeedsDisplay(true)

proc showLineNumbers*(view: SynEditView): bool =
  (not view.isNil) and view.xShowLineNumbers

proc `showLineNumbers=`*(view: SynEditView, showLineNumbers: bool) =
  if view.isNil or view.xShowLineNumbers == showLineNumbers:
    return
  view.xShowLineNumbers = showLineNumbers
  view.updateGutter()

proc lineNumberWidth*(view: SynEditView): float32 =
  if view.isNil: 0.0'f32 else: view.xLineNumberWidth

proc `lineNumberWidth=`*(view: SynEditView, width: float32) =
  let normalized = max(width, 0.0'f32)
  if view.isNil or view.xLineNumberWidth == normalized:
    return
  view.xLineNumberWidth = normalized
  view.updateGutter()

proc fontSize*(view: SynEditView): float32 =
  if view.isNil: DefaultSynEditFontSize else: view.xFontSize

proc `fontSize=`*(view: SynEditView, fontSize: float32) =
  let normalized = max(fontSize, 1.0'f32)
  if view.isNil or view.xFontSize == normalized:
    return
  view.xFontSize = normalized
  view.applySynEditTheme()
  view.applySyntaxHighlighting()
  view.updateGutter()

proc editable*(view: SynEditView): bool =
  (not view.isNil) and (not view.xEditor.isNil) and view.xEditor.editable()

proc `editable=`*(view: SynEditView, editable: bool) =
  if not view.isNil and not view.xEditor.isNil:
    view.xEditor.editable = editable

proc lineCount*(view: SynEditView): int =
  view.stringValue().lineCountOf()

proc effectiveLineNumberWidth(view: SynEditView): float32 =
  if view.isNil or not view.xShowLineNumbers:
    return 0.0'f32
  let digits = max(($max(view.lineCount(), 1)).len, 2)
  max(view.xLineNumberWidth, digits.float32 * view.xFontSize * 0.65'f32 + 18.0'f32)

proc synEditLineHeight(view: SynEditView): float32 =
  max(view.xFontSize * 1.32'f32, view.xFontSize + 4.0'f32)

proc updateGutter(view: SynEditView) =
  if view.isNil or view.xEditor.isNil:
    return
  let scroll = view.xEditor.scrollView()
  if scroll.isNil:
    return
  if view.xShowLineNumbers:
    let width = view.effectiveLineNumberWidth()
    view.xGutter.frame =
      rect(0.0'f32, 0.0'f32, width, max(view.bounds().size.height, 1.0'f32))
    if scroll.verticalHeaderView() != View(view.xGutter):
      scroll.verticalHeaderView = View(view.xGutter)
  elif scroll.verticalHeaderView() == View(view.xGutter):
    scroll.verticalHeaderView = nil
  scroll.tile()
  view.xGutter.setNeedsDisplay(true)

proc applySynEditTheme(view: SynEditView) =
  if view.isNil or view.xEditor.isNil:
    return
  let
    textView = view.xEditor.textView()
    scroll = view.xEditor.scrollView()
    baseAttributes = view.textAttributes(SynEditTokenClass.None)
  view.background = view.xTheme.background
  view.xEditor.background = color(0.0, 0.0, 0.0, 0.0)
  view.xEditor.textInsets = insets(8.0'f32, 10.0'f32, 8.0'f32, 10.0'f32)
  view.xEditor.textColor = view.xTheme.foreground[SynEditTokenClass.None]
  view.xEditor.selectionColor = view.xTheme.selectionBackground
  if not textView.isNil:
    textView.typingAttributes = baseAttributes
    textView.insertionPointColor = view.xTheme.cursorColor
    textView.selectedTextAttributes = defaultTextAttributes(
      view.xTheme.foreground[SynEditTokenClass.None], view.xFontSize
    )
  if not scroll.isNil:
    scroll.drawsBackground = false
    scroll.borderType = svbNoBorder
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidePolicy = sapWhenNeeded

proc synEditTextDidChange(view: SynEditView, sender: DynamicAgent) {.slot.} =
  discard sender
  if view.isNil or view.xApplyingHighlight:
    return
  view.updateGutter()
  view.applySyntaxHighlighting()

proc synEditGutterNeedsDisplay(view: SynEditView) {.slot.} =
  if not view.isNil and not view.xGutter.isNil:
    view.xGutter.setNeedsDisplay(true)

protocol DefaultSynEditDrawing of ViewDrawingProtocol:
  method draw(view: SynEditView, context: DrawContext) =
    discard context.addRectangle(context.bounds(), fill(view.xTheme.background))

protocol DefaultSynEditLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: SynEditView): IntrinsicSize =
    initIntrinsicSize(DefaultSynEditWidth, DefaultSynEditHeight)

  method layoutSubviews(view: SynEditView) =
    if not view.xEditor.isNil:
      view.xEditor.frame = view.bounds()
      view.updateGutter()

protocol DefaultSynEditAccessibility of AccessibilityProtocol:
  method isAccessibilityElement(view: SynEditView): bool =
    false

  method accessibilityChildren(view: SynEditView): seq[View] =
    if view.xEditor.isNil:
      @[]
    else:
      @[View(view.xEditor)]

protocol DefaultSynEditGutterDrawing of ViewDrawingProtocol:
  method draw(gutter: SynEditGutterView, context: DrawContext) =
    let owner = gutter.xOwner
    if owner.isNil:
      return
    let
      bounds = context.bounds()
      lineHeight = owner.synEditLineHeight()
      offset = owner.scrollView().contentOffset()
      firstLine = max(int(floor(offset.y / lineHeight)), 0)
      visibleLines = int(ceil(bounds.size.height / lineHeight)) + 2
      lastLine = min(owner.lineCount(), firstLine + visibleLines)
      textStyle = TextStyle(
        color: owner.xTheme.lineNumberColor,
        fontSize: owner.xFontSize,
        insets: insets(0.0'f32),
      )

    discard context.addRectangle(bounds, fill(owner.xTheme.background))
    discard context.addRenderLine(
      initPoint(bounds.maxX - 1.0'f32, bounds.minY),
      initPoint(bounds.maxX - 1.0'f32, bounds.maxY),
      fill(owner.xTheme.scrollTrackColor),
      1.0'f32,
    )
    for line in firstLine ..< lastLine:
      let lineRect = rect(
        bounds.minX,
        line.float32 * lineHeight - offset.y,
        max(bounds.size.width - 8.0'f32, 0.0'f32),
        lineHeight,
      )
      discard context.addText(lineRect, $(line + 1), textStyle, taRight)

proc initSynEditGutterFields(gutter: SynEditGutterView, owner: SynEditView) =
  initViewFields(gutter, rect(0.0'f32, 0.0'f32, DefaultSynEditLineNumberWidth, 1.0'f32))
  gutter.xOwner = owner
  gutter.background = owner.xTheme.background
  discard gutter.withProtocol(DefaultSynEditGutterDrawing)

proc initSynEditViewFields*(
    view: SynEditView, value = "", frame: Rect = AutoRect, language = langNim
) =
  initViewFields(view, frame)
  view.xTheme = synEditTheme()
  view.xLanguage = language
  view.xShowLineNumbers = true
  view.xLineNumberWidth = DefaultSynEditLineNumberWidth
  view.xFontSize = DefaultSynEditFontSize
  view.background = view.xTheme.background
  view.xEditor = newTextEditor(value, richText = true, wraps = false)
  view.xGutter = SynEditGutterView()
  view.xGutter.initSynEditGutterFields(view)
  view.addSubview(view.xEditor)
  view.xEditor.connect(textDidChange, view, synEditTextDidChange)
  if not view.xEditor.scrollView().isNil:
    view.xEditor.scrollView().clipView().connect(
      geometryDidChange, view, synEditGutterNeedsDisplay
    )
  discard view.withProtocol(DefaultSynEditDrawing)
  discard view.withProtocol(DefaultSynEditLayout)
  discard view.withProtocol(DefaultSynEditAccessibility)
  view.applySynEditTheme()
  view.updateGutter()
  view.applySyntaxHighlighting()
  view.applyInitialFrame(frame)

proc newSynEditView*(
    value = "", frame: Rect = AutoRect, language = langNim
): SynEditView =
  result = SynEditView()
  result.initSynEditViewFields(value, frame, language)
