## Shared text palettes, TOML discovery, and presentation adapters.
##
## Import this module to use one ContentTheme with MarkdownView, SynEditView,
## and TerminalView. Loading never changes a view; assignment applies the palette.
## TOML files contain a [Colors] table with RGB hex strings and optional
## { fg = "#rrggbb", bg = "#rrggbb" } color pairs.

import std/[algorithm, os, strutils]
import parsetoml
import ./foundation/types
import ./text/[markdownviews, syneditviews, syntaxhighlighting]
import ./terminal/terminalviews
import ./themes/private/contentthemeassets

export contentthemeassets

type
  ContentThemeKind* = enum
    ctkDefault
    ctkFile
    ctkPalette

  ContentThemeColor* = object ## An RGB color independent of any editor engine.
    red*, green*, blue*: uint8

  ContentThemePalette* = object
    ## Shared colors for text, syntax highlighting, readers, and terminals.
    background*: ContentThemeColor
    foreground*: ContentThemeColor
    keyword*: ContentThemeColor
    functionName*: ContentThemeColor
    stringLiteral*: ContentThemeColor
    comment*: ContentThemeColor
    red*, yellow*, cyan*, selection*: ContentThemeColor

  ContentTheme* = object ## A named content palette, optionally loaded from a TOML file.
    kind*: ContentThemeKind
    identifier*: string
    name*: string
    path*: string
    palette*: ContentThemePalette

const DefaultContentThemeIdentifier* = "default"

func initContentPalette*(): ContentThemePalette =
  ## A complete dark palette used for the default theme and omitted color keys.
  ContentThemePalette(
    background: ContentThemeColor(),
    foreground: ContentThemeColor(red: 218, green: 218, blue: 218),
    keyword: ContentThemeColor(red: 95, green: 215, blue: 255),
    functionName: ContentThemeColor(red: 97, green: 175, blue: 239),
    stringLiteral: ContentThemeColor(red: 152, green: 195, blue: 121),
    comment: ContentThemeColor(red: 92, green: 103, blue: 115),
    red: ContentThemeColor(red: 224, green: 108, blue: 117),
    yellow: ContentThemeColor(red: 229, green: 192, blue: 123),
    cyan: ContentThemeColor(red: 137, green: 221, blue: 255),
    selection: ContentThemeColor(red: 92, green: 61, blue: 110),
  )

proc initContentTheme*(
    name = "Default", palette = initContentPalette(), identifier = ""
): ContentTheme =
  ## Create an in-memory theme for any NimKit text surface.
  ContentTheme(kind: ctkPalette, name: name, identifier: identifier, palette: palette)

proc parseContentColor(
    value: TomlValueRef, fallback: ContentThemeColor
): ContentThemeColor =
  if value.kind != TomlValueKind.String:
    raise newException(ValueError, "A content color must be an RGB hex string")
  let text = value.getStr()
  if text == "termDefault":
    return fallback
  if text.len != 7 or text[0] != '#':
    raise newException(ValueError, "Invalid content color: " & text)
  for character in text[1 .. ^1]:
    if character notin {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}:
      raise newException(ValueError, "Invalid content color: " & text)
  ContentThemeColor(
    red: parseHexInt(text[1 .. 2]).uint8,
    green: parseHexInt(text[3 .. 4]).uint8,
    blue: parseHexInt(text[5 .. 6]).uint8,
  )

proc parseContentPalette*(content: string): ContentThemePalette =
  ## Parse a [Colors] palette. Missing entries retain the default palette.
  ## Malformed TOML and invalid recognized color values raise catchable errors.
  let document = parsetoml.parseString(content)
  if not document.hasKey("Colors") or document["Colors"].kind != TomlValueKind.Table:
    raise newException(ValueError, "Content theme requires a [Colors] table")
  let colors = document["Colors"]
  result = initContentPalette()
  template readColor(key: string, field: untyped, component: string) =
    if colors.hasKey(key):
      let entry = colors[key]
      if component.len == 0:
        result.field = parseContentColor(entry, result.field)
      elif entry.kind == TomlValueKind.Table and entry.hasKey(component):
        result.field = parseContentColor(entry[component], result.field)
      elif entry.kind != TomlValueKind.Table:
        raise newException(ValueError, "Expected a color pair for " & key)

  readColor("foreground", foreground, "")
  readColor("background", background, "")
  readColor("keyword", keyword, "fg")
  readColor("functionName", functionName, "fg")
  readColor("stringLit", stringLiteral, "fg")
  readColor("comment", comment, "fg")
  readColor("errorMessage", red, "fg")
  readColor("warnMessage", yellow, "fg")
  readColor("operator", cyan, "fg")
  readColor("selectArea", selection, "bg")

proc loadContentPalette(path: string): ContentThemePalette =
  parseContentPalette(readFile(path))

proc normalizedThemePath*(path: string): string =
  normalizedPath(absolutePath(path.expandTilde()))

proc contentThemeIdentifier*(path: string): string =
  "config:" & path.normalizedThemePath()

func contentThemeName(path: string): string =
  let baseName = splitFile(path).name
  if baseName == "shades-of-purple":
    return "Shades of Purple"
  var capitalizeNext = true
  for character in baseName:
    if character in {'-', '_'}:
      if result.len > 0 and result[^1] != ' ':
        result.add ' '
      capitalizeNext = true
    elif capitalizeNext:
      result.add character.toUpperAscii()
      capitalizeNext = false
    else:
      result.add character

proc loadContentTheme*(path: string): ContentTheme =
  ## Load a palette file, recording its absolute path and stable identifier.
  let normalizedPath = path.normalizedThemePath()
  ContentTheme(
    kind: ctkFile,
    identifier: normalizedPath.contentThemeIdentifier(),
    name: normalizedPath.contentThemeName(),
    path: normalizedPath,
    palette: normalizedPath.loadContentPalette(),
  )

proc sortConfigThemes(themes: var seq[ContentTheme]) =
  themes.sort do(left, right: ContentTheme) -> int:
    result = cmp(left.name.toLowerAscii(), right.name.toLowerAscii())
    if result == 0:
      result = cmp(left.identifier, right.identifier)

proc discoverContentThemes*(themesDirectory: string): seq[ContentTheme] =
  ## Discover content palette TOML files in `themesDirectory`.
  result.add ContentTheme(
    kind: ctkDefault,
    identifier: DefaultContentThemeIdentifier,
    name: "Default",
    palette: initContentPalette(),
  )
  if not dirExists(themesDirectory):
    return
  var configThemes: seq[ContentTheme]
  try:
    for path in walkFiles(themesDirectory / "*.toml"):
      try:
        configThemes.add path.loadContentTheme()
      except CatchableError:
        discard
  except OSError:
    discard
  configThemes.sortConfigThemes()
  result.add configThemes

proc mergeContentThemes*(
    themes: var seq[ContentTheme], additions: openArray[ContentTheme]
) =
  ## Merge additions by name, retaining the leading default entry.
  for addition in additions:
    if addition.kind != ctkDefault:
      var matchingIndex = -1
      for index in 1 ..< themes.len:
        if themes[index].name.toLowerAscii() == addition.name.toLowerAscii():
          matchingIndex = index
          break
      if matchingIndex >= 0:
        themes[matchingIndex] = addition
      else:
        themes.add addition

proc sortContentThemes*(themes: var seq[ContentTheme]) =
  ## Sort named themes while retaining the leading default entry.
  if themes.len > 2:
    var configThemes = themes[1 ..^ 1]
    configThemes.sortConfigThemes()
    themes.setLen(1)
    themes.add configThemes

proc validContentTheme*(theme: ContentTheme): bool =
  ## Check that a theme's palette can be loaded without changing any view.
  if theme.kind in {ctkDefault, ctkPalette}:
    return true
  try:
    discard loadContentPalette(theme.path)
    result = true
  except CatchableError:
    discard

func toColor*(value: ContentThemeColor): Color =
  ## Convert an RGB palette entry to a NimKit drawing color.
  color(
    value.red.float32 / 255, value.green.float32 / 255, value.blue.float32 / 255, 1.0
  )

proc applyContentTheme*(style: var MarkdownStyle, theme: ContentTheme) =
  ## Apply colors while preserving the reader's fonts and layout settings.
  let p = theme.palette
  style.backgroundColor = p.background.toColor()
  style.textColor = p.foreground.toColor()
  style.headingColor = p.functionName.toColor()
  style.strongColor = p.foreground.toColor()
  style.emphasisColor = p.keyword.toColor()
  style.linkColor = p.cyan.toColor()
  style.codeColor = p.stringLiteral.toColor()
  style.quoteColor = p.comment.toColor()
  style.mutedColor = p.comment.toColor()
  style.ruleColor = p.comment.toColor()
  style.codeBlockStyle.backgroundColor = p.background.toColor()
  style.codeBlockStyle.outlineColor = p.comment.toColor()
  for token in SyntaxTokenClass:
    style.syntaxTokenColors[token] = style.textColor
  style.syntaxTokenColors[stcKeyword] = p.keyword.toColor()
  style.syntaxTokenColors[stcIdentifier] = p.functionName.toColor()
  style.syntaxTokenColors[stcString] = p.stringLiteral.toColor()
  style.syntaxTokenColors[stcNumber] = p.yellow.toColor()
  style.syntaxTokenColors[stcComment] = p.comment.toColor()
  style.syntaxTokenColors[stcOperator] = p.cyan.toColor()
  style.syntaxTokenColors[stcPreprocessor] = p.keyword.toColor()

proc toSynEditTheme*(theme: ContentTheme): SynEditTheme =
  ## Build the built-in editor's colors from a shared palette.
  let p = theme.palette
  for token in SyntaxTokenClass:
    result.foreground[token] = p.foreground.toColor()
  result.foreground[stcKeyword] = p.keyword.toColor()
  result.foreground[stcIdentifier] = p.functionName.toColor()
  result.foreground[stcString] = p.stringLiteral.toColor()
  result.foreground[stcNumber] = p.yellow.toColor()
  result.foreground[stcComment] = p.comment.toColor()
  result.foreground[stcOperator] = p.cyan.toColor()
  result.foreground[stcPreprocessor] = p.keyword.toColor()
  result.background = p.background.toColor()
  result.selectionBackground = p.selection.toColor()
  result.bracketBackground = p.selection.toColor()
  result.cursorColor = p.foreground.toColor()
  result.lineNumberColor = p.comment.toColor()
  result.markerBackground = p.selection.toColor()
  result.scrollBarColor = p.comment.toColor()
  result.scrollBarActiveColor = p.foreground.toColor()
  result.scrollTrackColor = p.background.toColor()

proc toTerminalPalette*(theme: ContentTheme): TerminalPalette =
  ## Build ANSI colors, selection, cursor, and background from a shared palette.
  result = initTerminalPalette()
  let p = theme.palette
  result.background = p.background.toColor()
  result.foreground = p.foreground.toColor()
  result.cursor = result.foreground
  result.selection = p.selection.toColor()
  result.colors[0] = result.background
  result.colors[1] = p.red.toColor()
  result.colors[2] = p.stringLiteral.toColor()
  result.colors[3] = p.yellow.toColor()
  result.colors[4] = p.functionName.toColor()
  result.colors[5] = p.keyword.toColor()
  result.colors[6] = p.cyan.toColor()
  result.colors[7] = result.foreground
  result.colors[8] = p.comment.toColor()
  for index in 1 .. 7:
    result.colors[index + 8] = result.colors[index]

proc `contentTheme=`*(view: MarkdownView, theme: ContentTheme) =
  var style = view.markdownStyle()
  style.applyContentTheme(theme)
  view.markdownStyle = style

proc `contentTheme=`*(view: SynEditView, theme: ContentTheme) =
  view.theme = theme.toSynEditTheme()

proc `contentTheme=`*(view: TerminalView, theme: ContentTheme) =
  view.palette = theme.toTerminalPalette()
