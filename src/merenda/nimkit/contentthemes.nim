## Shared text palettes and presentation adapters.
##
## Import this module to use one ContentTheme with MarkdownView, SynEditView,
## and TerminalView. Loading never changes a view; assignment applies the palette.
## Palette types, TOML loading, and discovery live in `contentthemepalettes`.

import ./contentthemepalettes
import ./text/[markdownviews, syneditviews, syntaxhighlighting]
import ./terminal/terminalviews

export contentthemepalettes

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
