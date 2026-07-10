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

  CKeywords = [
    "_Bool", "_Complex", "_Imaginary", "auto", "break", "case", "char", "const",
    "continue", "default", "do", "double", "else", "enum", "extern", "float", "for",
    "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short",
    "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned",
    "void", "volatile", "while",
  ]

  CppKeywords = [
    "asm", "auto", "break", "case", "catch", "char", "class", "const", "continue",
    "default", "delete", "do", "double", "else", "enum", "extern", "false", "float",
    "for", "friend", "goto", "if", "inline", "int", "long", "mutable", "namespace",
    "new", "operator", "private", "protected", "public", "register", "return", "short",
    "signed", "sizeof", "static", "struct", "switch", "template", "this", "throw",
    "true", "try", "typedef", "typename", "union", "unsigned", "using", "virtual",
    "void", "volatile", "while",
  ]

  JsKeywords = [
    "abstract", "arguments", "boolean", "break", "byte", "case", "catch", "char",
    "class", "const", "continue", "debugger", "default", "delete", "do", "double",
    "else", "enum", "eval", "export", "extends", "false", "final", "finally", "float",
    "for", "function", "goto", "if", "implements", "import", "in", "instanceof", "int",
    "interface", "let", "long", "native", "new", "null", "package", "private",
    "protected", "public", "return", "short", "static", "super", "switch",
    "synchronized", "this", "throw", "throws", "transient", "true", "try", "typeof",
    "var", "void", "volatile", "while", "with", "yield",
  ]

  PythonKeywords = [
    "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
    "continue", "def", "del", "elif", "else", "except", "finally", "for", "from",
    "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass",
    "raise", "return", "try", "while", "with", "yield",
  ]

  RustKeywords = [
    "as", "break", "const", "continue", "crate", "else", "enum", "extern", "false",
    "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut",
    "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait",
    "true", "type", "unsafe", "use", "where", "while",
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
  of ".cpp", ".hpp", ".cxx", ".cc", ".hh", ".hxx", ".h": langCpp
  of ".c": langC
  of ".js", ".jsx": langJs
  of ".java": langJava
  of ".cs": langCsharp
  of ".xml": langXml
  of ".html", ".htm": langHtml
  of ".py", ".pyw": langPython
  of ".rs": langRust
  of ".md", ".markdown": langMarkdown
  else: langNone

func strToLanguage*(language: string): SourceLanguage =
  case language.toLowerAscii()
  of "nim", "nims", "nimble": langNim
  of "c": langC
  of "cpp", "cxx", "c++", "cc", "hpp", "hxx": langCpp
  of "cs", "csharp", "c#": langCsharp
  of "java": langJava
  of "js", "javascript", "jsx": langJs
  of "py", "python": langPython
  of "rs", "rust": langRust
  of "xml": langXml
  of "html", "htm": langHtml
  of "md", "markdown": langMarkdown
  else: langNone

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

func isHighlightWhitespace(ch: char): bool =
  ch in {' ', '\t', '\n', '\v', '\f', '\r'}

func isKeyword(word: string, keywords: openArray[string]): bool =
  for keyword in keywords:
    if word == keyword:
      return true

func span(start, stop: int, token: SynEditTokenClass): SynEditTokenSpan =
  SynEditTokenSpan(range: initTextRange(start, max(stop - start, 0)), token: token)

type
  SynEditHighlightCell = object
    c: char
    token: SynEditTokenClass

  SynEditHighlightBuffer = object
    cells: seq[SynEditHighlightCell]

  GeneralTokenizer = object
    kind: SynEditTokenClass
    start, length: int
    buf: ptr SynEditHighlightBuffer
    pos: int
    state: SynEditTokenClass

proc len(buffer: ptr SynEditHighlightBuffer): int {.inline.} =
  buffer[].cells.len

proc `[]`(buffer: ptr SynEditHighlightBuffer, index: int): char {.inline.} =
  if index < 0 or index >= buffer.len:
    '\L'
  else:
    buffer[].cells[index].c

proc setCellStyle(
    buffer: var SynEditHighlightBuffer, index: int, token: SynEditTokenClass
) =
  if index >= 0 and index < buffer.cells.len:
    buffer.cells[index].token = token

proc initHighlightBuffer(text: string): SynEditHighlightBuffer =
  result.cells = newSeqOfCap[SynEditHighlightCell](text.len)
  for ch in text:
    if ch != '\C':
      result.cells.add SynEditHighlightCell(c: ch, token: SynEditTokenClass.None)

proc nimKeywordToken(identifier: string): SynEditTokenClass =
  if identifier.isKeyword(NimKeywords):
    SynEditTokenClass.Keyword
  else:
    SynEditTokenClass.Identifier

proc nimMultilineComment(
    tokenizer: var GeneralTokenizer, position: int, isDoc: bool
): int =
  var
    pos = position
    nesting = 0
  while pos < tokenizer.buf.len:
    case tokenizer.buf[pos]
    of '#':
      if isDoc:
        if tokenizer.buf[pos + 1] == '#' and tokenizer.buf[pos + 2] == '[':
          inc nesting
      elif tokenizer.buf[pos + 1] == '[':
        inc nesting
      inc pos
    of ']':
      if isDoc:
        if tokenizer.buf[pos + 1] == '#' and tokenizer.buf[pos + 2] == '#':
          if nesting == 0:
            pos += 3
            break
          dec nesting
      elif tokenizer.buf[pos + 1] == '#':
        if nesting == 0:
          pos += 2
          break
        dec nesting
      inc pos
    else:
      inc pos
  pos

proc nimNumberPostfix(tokenizer: var GeneralTokenizer, position: int): int =
  var pos = position
  if tokenizer.buf[pos] == '\'':
    inc pos
  case tokenizer.buf[pos]
  of 'd', 'D':
    tokenizer.kind = SynEditTokenClass.FloatNumber
    inc pos
  of 'f', 'F':
    tokenizer.kind = SynEditTokenClass.FloatNumber
    inc pos
    if tokenizer.buf[pos] in {'0' .. '9'}:
      inc pos
    if tokenizer.buf[pos] in {'0' .. '9'}:
      inc pos
  of 'i', 'I', 'u', 'U':
    inc pos
    if tokenizer.buf[pos] in {'0' .. '9'}:
      inc pos
    if tokenizer.buf[pos] in {'0' .. '9'}:
      inc pos
  else:
    discard
  pos

proc nimNumber(tokenizer: var GeneralTokenizer, position: int): int =
  const DecChars = {'0' .. '9', '_'}
  var pos = position
  tokenizer.kind = SynEditTokenClass.DecNumber
  while tokenizer.buf[pos] in DecChars:
    inc pos
  if tokenizer.buf[pos] == '.':
    if tokenizer.buf[pos + 1] == '.':
      return pos
    tokenizer.kind = SynEditTokenClass.FloatNumber
    inc pos
    while tokenizer.buf[pos] in DecChars:
      inc pos
  if tokenizer.buf[pos] in {'e', 'E'}:
    tokenizer.kind = SynEditTokenClass.FloatNumber
    inc pos
    if tokenizer.buf[pos] in {'+', '-'}:
      inc pos
    while tokenizer.buf[pos] in DecChars:
      inc pos
  tokenizer.nimNumberPostfix(pos)

proc nextNimToken(tokenizer: var GeneralTokenizer) =
  const
    HexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f', '_'}
    OctChars = {'0' .. '7', '_'}
    BinChars = {'0', '1', '_'}
    SymChars = {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '\x80' .. '\xFF'}
  var pos = tokenizer.pos
  tokenizer.start = tokenizer.pos
  if tokenizer.state == SynEditTokenClass.StringLit:
    tokenizer.kind = SynEditTokenClass.StringLit
    while pos < tokenizer.buf.len:
      case tokenizer.buf[pos]
      of '\\':
        tokenizer.kind = SynEditTokenClass.EscapeSequence
        inc pos
        case tokenizer.buf[pos]
        of 'x', 'X':
          inc pos
          if tokenizer.buf[pos] in HexChars:
            inc pos
          if tokenizer.buf[pos] in HexChars:
            inc pos
        of '0' .. '9':
          while tokenizer.buf[pos] in {'0' .. '9'}:
            inc pos
        else:
          inc pos
        break
      of '\L', '\C':
        tokenizer.state = SynEditTokenClass.None
        break
      of '"':
        inc pos
        tokenizer.state = SynEditTokenClass.None
        break
      else:
        inc pos
  elif tokenizer.state == SynEditTokenClass.LongStringLit:
    tokenizer.kind = SynEditTokenClass.LongStringLit
    while pos < tokenizer.buf.len:
      if tokenizer.buf[pos] == '"':
        inc pos
        if tokenizer.buf[pos] == '"' and tokenizer.buf[pos + 1] == '"' and
            tokenizer.buf[pos + 2] != '"':
          pos += 2
          break
      else:
        inc pos
    tokenizer.state = SynEditTokenClass.None
  elif tokenizer.state in {SynEditTokenClass.LongComment, SynEditTokenClass.Comment}:
    tokenizer.kind = tokenizer.state
    pos = tokenizer.nimMultilineComment(
      pos, tokenizer.kind == SynEditTokenClass.LongComment
    )
    tokenizer.state = SynEditTokenClass.None
  else:
    case tokenizer.buf[pos]
    of ' ', '\t', '\n', '\v', '\f', '\r':
      tokenizer.kind = SynEditTokenClass.Whitespace
      while pos < tokenizer.buf.len and tokenizer.buf[pos].isHighlightWhitespace():
        inc pos
    of '#':
      if tokenizer.buf[pos + 1] == '#':
        tokenizer.kind = SynEditTokenClass.LongComment
        inc pos
      else:
        tokenizer.kind = SynEditTokenClass.Comment
      if tokenizer.buf[pos + 1] == '[':
        tokenizer.state = tokenizer.kind
        pos = tokenizer.nimMultilineComment(
          pos + 2, tokenizer.kind == SynEditTokenClass.LongComment
        )
        tokenizer.state = SynEditTokenClass.None
      else:
        while tokenizer.buf[pos] != '\L':
          inc pos
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var identifier = ""
      while tokenizer.buf[pos] in SymChars + {'_'}:
        identifier.add tokenizer.buf[pos]
        inc pos
      if tokenizer.buf[pos] == '"':
        if tokenizer.buf[pos + 1] == '"' and tokenizer.buf[pos + 2] == '"':
          pos += 3
          tokenizer.kind = SynEditTokenClass.LongStringLit
          while pos < tokenizer.buf.len:
            if tokenizer.buf[pos] == '"':
              inc pos
              if tokenizer.buf[pos] == '"' and tokenizer.buf[pos + 1] == '"' and
                  tokenizer.buf[pos + 2] != '"':
                pos += 2
                break
            else:
              inc pos
        else:
          tokenizer.kind = SynEditTokenClass.RawData
          inc pos
          while tokenizer.buf[pos] != '\L':
            if tokenizer.buf[pos] == '"' and tokenizer.buf[pos + 1] != '"':
              break
            inc pos
          if tokenizer.buf[pos] == '"':
            inc pos
      else:
        tokenizer.kind = nimKeywordToken(identifier)
    of '0':
      inc pos
      case tokenizer.buf[pos]
      of 'b', 'B':
        tokenizer.kind = SynEditTokenClass.BinNumber
        inc pos
        while tokenizer.buf[pos] in BinChars:
          inc pos
        pos = tokenizer.nimNumberPostfix(pos)
      of 'x', 'X':
        tokenizer.kind = SynEditTokenClass.HexNumber
        inc pos
        while tokenizer.buf[pos] in HexChars:
          inc pos
        pos = tokenizer.nimNumberPostfix(pos)
      of 'o', 'O':
        tokenizer.kind = SynEditTokenClass.OctNumber
        inc pos
        while tokenizer.buf[pos] in OctChars:
          inc pos
        pos = tokenizer.nimNumberPostfix(pos)
      else:
        pos = tokenizer.nimNumber(pos)
    of '1' .. '9':
      pos = tokenizer.nimNumber(pos)
    of '\'':
      inc pos
      tokenizer.kind = SynEditTokenClass.CharLit
      while true:
        case tokenizer.buf[pos]
        of '\L':
          break
        of '\'':
          inc pos
          break
        of '\\':
          pos += 2
        else:
          inc pos
    of '"':
      inc pos
      if tokenizer.buf[pos] == '"' and tokenizer.buf[pos + 1] == '"':
        pos += 2
        tokenizer.kind = SynEditTokenClass.LongStringLit
        while pos < tokenizer.buf.len:
          if tokenizer.buf[pos] == '"':
            inc pos
            if tokenizer.buf[pos] == '"' and tokenizer.buf[pos + 1] == '"' and
                tokenizer.buf[pos + 2] != '"':
              pos += 2
              break
          else:
            inc pos
      else:
        tokenizer.kind = SynEditTokenClass.StringLit
        while true:
          case tokenizer.buf[pos]
          of '\L':
            break
          of '"':
            inc pos
            break
          of '\\':
            tokenizer.state = tokenizer.kind
            break
          else:
            inc pos
    of '(', '[', '{':
      inc pos
      tokenizer.kind = SynEditTokenClass.Punctuation
      if tokenizer.buf[pos] == '.' and tokenizer.buf[pos + 1] != '.':
        inc pos
    of ')', ']', '}', '`', ':', ',', ';':
      inc pos
      tokenizer.kind = SynEditTokenClass.Punctuation
    of '.':
      if tokenizer.buf[pos + 1] in {')', ']', '}'}:
        pos += 2
        tokenizer.kind = SynEditTokenClass.Punctuation
      else:
        tokenizer.kind = SynEditTokenClass.Operator
        inc pos
    else:
      if tokenizer.buf[pos].isOperatorChar():
        tokenizer.kind = SynEditTokenClass.Operator
        while tokenizer.buf[pos].isOperatorChar():
          inc pos
      else:
        if pos < tokenizer.buf.len:
          inc pos
        tokenizer.kind = SynEditTokenClass.None
  tokenizer.length = pos - tokenizer.pos
  tokenizer.pos = pos

proc nextCLikeToken(tokenizer: var GeneralTokenizer, keywords: openArray[string]) =
  const
    HexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    OctChars = {'0' .. '7'}
    BinChars = {'0', '1'}
    SymChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  var pos = tokenizer.pos
  tokenizer.start = tokenizer.pos
  if tokenizer.state == SynEditTokenClass.StringLit:
    tokenizer.kind = SynEditTokenClass.StringLit
    while true:
      case tokenizer.buf[pos]
      of '\\':
        tokenizer.kind = SynEditTokenClass.EscapeSequence
        inc pos
        case tokenizer.buf[pos]
        of 'x', 'X':
          inc pos
          if tokenizer.buf[pos] in HexChars:
            inc pos
          if tokenizer.buf[pos] in HexChars:
            inc pos
        of '0' .. '9':
          while tokenizer.buf[pos] in {'0' .. '9'}:
            inc pos
        else:
          inc pos
        break
      of '\L':
        tokenizer.state = SynEditTokenClass.None
        break
      of '"':
        inc pos
        tokenizer.state = SynEditTokenClass.None
        break
      else:
        inc pos
  elif tokenizer.state == SynEditTokenClass.LongComment:
    tokenizer.kind = SynEditTokenClass.LongComment
    while pos < tokenizer.buf.len:
      case tokenizer.buf[pos]
      of '*':
        inc pos
        if tokenizer.buf[pos] == '/':
          inc pos
          break
      of '/':
        inc pos
      else:
        inc pos
    tokenizer.state = SynEditTokenClass.None
  else:
    case tokenizer.buf[pos]
    of ' ', '\t', '\n', '\v', '\f', '\r':
      tokenizer.kind = SynEditTokenClass.Whitespace
      while pos < tokenizer.buf.len and tokenizer.buf[pos].isHighlightWhitespace():
        inc pos
    of '/':
      inc pos
      if tokenizer.buf[pos] == '/':
        tokenizer.kind = SynEditTokenClass.Comment
        while tokenizer.buf[pos] != '\L':
          inc pos
      elif tokenizer.buf[pos] == '*':
        tokenizer.kind = SynEditTokenClass.LongComment
        inc pos
        while pos < tokenizer.buf.len:
          case tokenizer.buf[pos]
          of '*':
            inc pos
            if tokenizer.buf[pos] == '/':
              inc pos
              break
          else:
            inc pos
      else:
        tokenizer.kind = SynEditTokenClass.Operator
    of '#':
      inc pos
      tokenizer.kind = SynEditTokenClass.Preprocessor
      while tokenizer.buf[pos] in {' ', '\t'}:
        inc pos
      while tokenizer.buf[pos] in SymChars:
        inc pos
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var identifier = ""
      while tokenizer.buf[pos] in SymChars:
        identifier.add tokenizer.buf[pos]
        inc pos
      tokenizer.kind =
        if identifier.isKeyword(keywords):
          SynEditTokenClass.Keyword
        else:
          SynEditTokenClass.Identifier
    of '0':
      inc pos
      case tokenizer.buf[pos]
      of 'b', 'B':
        inc pos
        while tokenizer.buf[pos] in BinChars:
          inc pos
        tokenizer.kind = SynEditTokenClass.BinNumber
      of 'x', 'X':
        inc pos
        while tokenizer.buf[pos] in HexChars:
          inc pos
        tokenizer.kind = SynEditTokenClass.HexNumber
      of '0' .. '7':
        inc pos
        while tokenizer.buf[pos] in OctChars:
          inc pos
        tokenizer.kind = SynEditTokenClass.OctNumber
      else:
        tokenizer.kind = SynEditTokenClass.DecNumber
        while tokenizer.buf[pos] in {'0' .. '9'}:
          inc pos
    of '1' .. '9':
      tokenizer.kind = SynEditTokenClass.DecNumber
      while tokenizer.buf[pos] in {'0' .. '9'}:
        inc pos
    of '\'':
      tokenizer.kind = SynEditTokenClass.CharLit
      inc pos
      while tokenizer.buf[pos] notin {'\L', '\''}:
        inc pos
      if tokenizer.buf[pos] == '\'':
        inc pos
    of '"':
      inc pos
      tokenizer.kind = SynEditTokenClass.StringLit
      while pos < tokenizer.buf.len:
        case tokenizer.buf[pos]
        of '"':
          inc pos
          break
        of '\\':
          tokenizer.state = tokenizer.kind
          break
        else:
          inc pos
    of '(', ')', '[', ']', '{', '}', ':', ',', ';', '.':
      inc pos
      tokenizer.kind = SynEditTokenClass.Punctuation
    else:
      if tokenizer.buf[pos].isOperatorChar():
        tokenizer.kind = SynEditTokenClass.Operator
        while tokenizer.buf[pos].isOperatorChar():
          inc pos
      else:
        if pos < tokenizer.buf.len:
          inc pos
        tokenizer.kind = SynEditTokenClass.None
  tokenizer.length = pos - tokenizer.pos
  tokenizer.pos = pos

proc nextPythonToken(tokenizer: var GeneralTokenizer) =
  const
    HexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    SymChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  var pos = tokenizer.pos
  tokenizer.start = tokenizer.pos
  if tokenizer.state == SynEditTokenClass.StringLit:
    tokenizer.kind = SynEditTokenClass.StringLit
    while true:
      case tokenizer.buf[pos]
      of '\\':
        tokenizer.kind = SynEditTokenClass.EscapeSequence
        inc pos
        case tokenizer.buf[pos]
        of 'x', 'X':
          inc pos
          if tokenizer.buf[pos] in HexChars:
            inc pos
          if tokenizer.buf[pos] in HexChars:
            inc pos
        of '0' .. '9':
          while tokenizer.buf[pos] in {'0' .. '9'}:
            inc pos
        else:
          inc pos
        break
      of '\L':
        tokenizer.state = SynEditTokenClass.None
        break
      of '"', '\'':
        inc pos
        tokenizer.state = SynEditTokenClass.None
        break
      else:
        inc pos
  else:
    case tokenizer.buf[pos]
    of ' ', '\t', '\n', '\v', '\f', '\r':
      tokenizer.kind = SynEditTokenClass.Whitespace
      while pos < tokenizer.buf.len and tokenizer.buf[pos].isHighlightWhitespace():
        inc pos
    of '#':
      tokenizer.kind = SynEditTokenClass.Comment
      while tokenizer.buf[pos] != '\L':
        inc pos
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var identifier = ""
      while tokenizer.buf[pos] in SymChars:
        identifier.add tokenizer.buf[pos]
        inc pos
      tokenizer.kind =
        if identifier.isKeyword(PythonKeywords):
          SynEditTokenClass.Keyword
        else:
          SynEditTokenClass.Identifier
    of '0':
      inc pos
      case tokenizer.buf[pos]
      of 'x', 'X':
        inc pos
        while tokenizer.buf[pos] in HexChars:
          inc pos
        tokenizer.kind = SynEditTokenClass.HexNumber
      else:
        tokenizer.kind = SynEditTokenClass.DecNumber
        while tokenizer.buf[pos] in {'0' .. '9'}:
          inc pos
    of '1' .. '9':
      tokenizer.kind = SynEditTokenClass.DecNumber
      while tokenizer.buf[pos] in {'0' .. '9'}:
        inc pos
    of '"', '\'':
      inc pos
      tokenizer.kind = SynEditTokenClass.StringLit
      while pos < tokenizer.buf.len:
        case tokenizer.buf[pos]
        of '"', '\'':
          inc pos
          break
        of '\\':
          tokenizer.state = tokenizer.kind
          break
        else:
          inc pos
    of '(', ')', '[', ']', '{', '}', ':', ',', ';', '.':
      inc pos
      tokenizer.kind = SynEditTokenClass.Punctuation
    else:
      if tokenizer.buf[pos].isOperatorChar():
        tokenizer.kind = SynEditTokenClass.Operator
        while tokenizer.buf[pos].isOperatorChar():
          inc pos
      else:
        if pos < tokenizer.buf.len:
          inc pos
        tokenizer.kind = SynEditTokenClass.None
  tokenizer.length = pos - tokenizer.pos
  tokenizer.pos = pos

proc nextRustToken(tokenizer: var GeneralTokenizer) =
  const
    HexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
    SymChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}
  var pos = tokenizer.pos
  tokenizer.start = tokenizer.pos
  if tokenizer.state == SynEditTokenClass.StringLit:
    tokenizer.kind = SynEditTokenClass.StringLit
    while true:
      case tokenizer.buf[pos]
      of '\\':
        tokenizer.kind = SynEditTokenClass.EscapeSequence
        inc pos
        case tokenizer.buf[pos]
        of 'x', 'X':
          inc pos
          if tokenizer.buf[pos] in HexChars:
            inc pos
          if tokenizer.buf[pos] in HexChars:
            inc pos
        of '0' .. '9':
          while tokenizer.buf[pos] in {'0' .. '9'}:
            inc pos
        else:
          inc pos
        break
      of '\L':
        tokenizer.state = SynEditTokenClass.None
        break
      of '"':
        inc pos
        tokenizer.state = SynEditTokenClass.None
        break
      else:
        inc pos
  else:
    case tokenizer.buf[pos]
    of ' ', '\t', '\n', '\v', '\f', '\r':
      tokenizer.kind = SynEditTokenClass.Whitespace
      while pos < tokenizer.buf.len and tokenizer.buf[pos].isHighlightWhitespace():
        inc pos
    of '/':
      inc pos
      if tokenizer.buf[pos] == '/':
        tokenizer.kind = SynEditTokenClass.Comment
        while tokenizer.buf[pos] != '\L':
          inc pos
      elif tokenizer.buf[pos] == '*':
        tokenizer.kind = SynEditTokenClass.LongComment
        inc pos
        while pos < tokenizer.buf.len:
          case tokenizer.buf[pos]
          of '*':
            inc pos
            if tokenizer.buf[pos] == '/':
              inc pos
              break
          else:
            inc pos
      else:
        tokenizer.kind = SynEditTokenClass.Operator
    of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
      var identifier = ""
      while tokenizer.buf[pos] in SymChars:
        identifier.add tokenizer.buf[pos]
        inc pos
      tokenizer.kind =
        if identifier.isKeyword(RustKeywords):
          SynEditTokenClass.Keyword
        else:
          SynEditTokenClass.Identifier
    of '0':
      inc pos
      case tokenizer.buf[pos]
      of 'x', 'X':
        tokenizer.kind = SynEditTokenClass.HexNumber
        inc pos
        while tokenizer.buf[pos] in HexChars:
          inc pos
      else:
        tokenizer.kind = SynEditTokenClass.DecNumber
        while tokenizer.buf[pos] in {'0' .. '9'}:
          inc pos
    of '1' .. '9':
      tokenizer.kind = SynEditTokenClass.DecNumber
      while tokenizer.buf[pos] in {'0' .. '9'}:
        inc pos
    of '\'':
      tokenizer.kind = SynEditTokenClass.CharLit
      inc pos
      while tokenizer.buf[pos] notin {'\L', '\''}:
        inc pos
      if tokenizer.buf[pos] == '\'':
        inc pos
    of '"':
      inc pos
      tokenizer.kind = SynEditTokenClass.StringLit
      while pos < tokenizer.buf.len:
        case tokenizer.buf[pos]
        of '"':
          inc pos
          break
        of '\\':
          tokenizer.state = tokenizer.kind
          break
        else:
          inc pos
    of '(', ')', '[', ']', '{', '}', ':', ',', ';', '.':
      inc pos
      tokenizer.kind = SynEditTokenClass.Punctuation
    else:
      if tokenizer.buf[pos].isOperatorChar():
        tokenizer.kind = SynEditTokenClass.Operator
        while tokenizer.buf[pos].isOperatorChar():
          inc pos
      else:
        if pos < tokenizer.buf.len:
          inc pos
        tokenizer.kind = SynEditTokenClass.None
  tokenizer.length = pos - tokenizer.pos
  tokenizer.pos = pos

proc nextToken(tokenizer: var GeneralTokenizer, language: SourceLanguage) =
  case language
  of langNone, langConsole:
    tokenizer.start = tokenizer.pos
    if tokenizer.pos < tokenizer.buf.len:
      inc tokenizer.pos
    tokenizer.kind = SynEditTokenClass.None
    tokenizer.length = tokenizer.pos - tokenizer.start
  of langNim:
    tokenizer.nextNimToken()
  of langCpp:
    tokenizer.nextCLikeToken(CppKeywords)
  of langC:
    tokenizer.nextCLikeToken(CKeywords)
  of langJs, langJava:
    tokenizer.nextCLikeToken(JsKeywords)
  of langCsharp:
    tokenizer.nextCLikeToken(CppKeywords)
  of langPython:
    tokenizer.nextPythonToken()
  of langRust:
    tokenizer.nextRustToken()
  of langXml, langHtml:
    tokenizer.start = tokenizer.pos
    if tokenizer.pos < tokenizer.buf.len:
      inc tokenizer.pos
    tokenizer.kind = SynEditTokenClass.None
    tokenizer.length = tokenizer.pos - tokenizer.start
  of langMarkdown:
    tokenizer.start = tokenizer.pos
    if tokenizer.pos < tokenizer.buf.len:
      inc tokenizer.pos
    tokenizer.kind = SynEditTokenClass.Text
    tokenizer.length = tokenizer.pos - tokenizer.start

proc highlightRange(
    buffer: var SynEditHighlightBuffer,
    first, last: int,
    language: SourceLanguage,
    initialState = SynEditTokenClass.None,
) =
  var tokenizer = GeneralTokenizer(
    buf: addr buffer,
    kind: SynEditTokenClass.None,
    start: first,
    state: initialState,
    pos: first,
  )
  while tokenizer.pos <= last:
    tokenizer.nextToken(language)
    if tokenizer.length == 0:
      break
    for index in 0 ..< tokenizer.length:
      buffer.setCellStyle(tokenizer.start + index, tokenizer.kind)

proc highlightMarkdown(buffer: var SynEditHighlightBuffer, first, last: int) =
  var
    insideFence = false
    fenceLanguage = langNone
    pos = first
  while pos > 0 and buffer.cells[pos - 1].c != '\L':
    dec pos
  while pos <= last:
    let lineStart = pos
    var lineEnd = pos
    while lineEnd <= last and buffer.cells[lineEnd].c != '\L':
      inc lineEnd

    var lineText = ""
    for index in lineStart ..< lineEnd:
      lineText.add buffer.cells[index].c

    let stripped = lineText.strip(leading = true, trailing = false)
    if stripped.startsWith("```") or stripped.startsWith("~~~"):
      for index in lineStart ..< min(lineEnd, last + 1):
        buffer.setCellStyle(index, SynEditTokenClass.MarkdownFence)
      let rest = stripped[3 .. ^1].strip()
      if rest.len > 0 and not insideFence:
        fenceLanguage = strToLanguage(rest)
        insideFence = true
      elif insideFence:
        insideFence = false
        fenceLanguage = langNone
    elif insideFence and fenceLanguage != langNone:
      buffer.highlightRange(lineStart, lineEnd - 1, fenceLanguage)
      if lineEnd <= last:
        buffer.setCellStyle(lineEnd, SynEditTokenClass.None)
    else:
      let token = if insideFence: SynEditTokenClass.RawData else: SynEditTokenClass.Text
      for index in lineStart ..< min(lineEnd, last + 1):
        buffer.setCellStyle(index, token)
      if lineEnd <= last:
        buffer.setCellStyle(lineEnd, SynEditTokenClass.None)

    pos = lineEnd + 1

proc byteRuneMap(text: string): seq[int] =
  result = newSeq[int](text.len + 1)
  var
    byteIndex = 0
    runeIndex = 0
  while byteIndex < text.len:
    let nextByte = min(byteIndex + max(runeLenAt(text, byteIndex), 1), text.len)
    for index in byteIndex ..< nextByte:
      result[index] = runeIndex
    byteIndex = nextByte
    inc runeIndex
  result[text.len] = runeIndex

proc addByteSpan(
    spans: var seq[SynEditTokenSpan],
    byteToRune: openArray[int],
    startByte, stopByte: int,
    token: SynEditTokenClass,
) =
  if stopByte <= startByte or byteToRune.len == 0:
    return
  let
    start = max(0, min(startByte, byteToRune.high))
    stop = max(start, min(stopByte, byteToRune.high))
    startRune = byteToRune[start]
    stopRune = byteToRune[stop]
  if stopRune > startRune:
    spans.add span(startRune, stopRune, token)

proc tokenSpans(buffer: SynEditHighlightBuffer, text: string): seq[SynEditTokenSpan] =
  if buffer.cells.len == 0:
    return
  let byteToRune = byteRuneMap(text)
  var
    start = 0
    token = buffer.cells[0].token
  for index in 1 .. buffer.cells.len:
    if index == buffer.cells.len or buffer.cells[index].token != token:
      result.addByteSpan(byteToRune, start, index, token)
      if index < buffer.cells.len:
        start = index
        token = buffer.cells[index].token

proc synEditTokenSpans*(text: string, language: SourceLanguage): seq[SynEditTokenSpan] =
  if text.len == 0:
    return
  var buffer = initHighlightBuffer(text)
  if language == langMarkdown:
    buffer.highlightMarkdown(0, buffer.cells.high)
  elif language != langNone:
    buffer.highlightRange(0, buffer.cells.high, language)
  buffer.tokenSpans(text)

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
  view.xEditor

proc textView*(view: SynEditView): TextView =
  if view.xEditor.isNil:
    nil
  else:
    view.xEditor.textView()

proc scrollView*(view: SynEditView): ScrollView =
  if view.xEditor.isNil:
    nil
  else:
    view.xEditor.scrollView()

proc gutterView*(view: SynEditView): View =
  View(view.xGutter)

proc stringValue*(view: SynEditView): string =
  if view.xEditor.isNil:
    ""
  else:
    view.xEditor.stringValue()

proc applySyntaxHighlighting*(view: SynEditView) =
  if view.xEditor.isNil or view.xApplyingHighlight:
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
  if view.xEditor.isNil:
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
  view.xLanguage

proc `language=`*(view: SynEditView, language: SourceLanguage) =
  if view.xLanguage == language:
    return
  view.xLanguage = language
  view.applySyntaxHighlighting()

proc theme*(view: SynEditView): SynEditTheme =
  view.xTheme

proc `theme=`*(view: SynEditView, theme: SynEditTheme) =
  view.xTheme = theme
  view.applySynEditTheme()
  view.applySyntaxHighlighting()
  view.setNeedsDisplay(true)

proc showLineNumbers*(view: SynEditView): bool =
  view.xShowLineNumbers

proc `showLineNumbers=`*(view: SynEditView, showLineNumbers: bool) =
  if view.xShowLineNumbers == showLineNumbers:
    return
  view.xShowLineNumbers = showLineNumbers
  view.updateGutter()

proc lineNumberWidth*(view: SynEditView): float32 =
  view.xLineNumberWidth

proc `lineNumberWidth=`*(view: SynEditView, width: float32) =
  let normalized = max(width, 0.0'f32)
  if view.xLineNumberWidth == normalized:
    return
  view.xLineNumberWidth = normalized
  view.updateGutter()

proc fontSize*(view: SynEditView): float32 =
  view.xFontSize

proc `fontSize=`*(view: SynEditView, fontSize: float32) =
  let normalized = max(fontSize, 1.0'f32)
  if view.xFontSize == normalized:
    return
  view.xFontSize = normalized
  view.applySynEditTheme()
  view.applySyntaxHighlighting()
  view.updateGutter()

proc editable*(view: SynEditView): bool =
  (not view.xEditor.isNil) and view.xEditor.editable()

proc `editable=`*(view: SynEditView, editable: bool) =
  if not view.xEditor.isNil:
    view.xEditor.editable = editable

proc lineCount*(view: SynEditView): int =
  view.stringValue().lineCountOf()

proc effectiveLineNumberWidth(view: SynEditView): float32 =
  if not view.xShowLineNumbers:
    return 0.0'f32
  let digits = max(($max(view.lineCount(), 1)).len, 2)
  max(view.xLineNumberWidth, digits.float32 * view.xFontSize * 0.65'f32 + 18.0'f32)

proc synEditLineHeight(view: SynEditView): float32 =
  max(view.xFontSize * 1.32'f32, view.xFontSize + 4.0'f32)

proc updateGutter(view: SynEditView) =
  if view.xEditor.isNil:
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
  if view.xEditor.isNil:
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
  if view.xApplyingHighlight:
    return
  view.updateGutter()
  view.applySyntaxHighlighting()

proc synEditGutterNeedsDisplay(view: SynEditView) {.slot.} =
  if not view.xGutter.isNil:
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
