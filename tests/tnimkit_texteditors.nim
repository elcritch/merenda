import std/[unicode, unittest]

import figdraw/common/fontglyphs
import figdraw/fignodes

import merenda/nimkit

const
  IntroText =
    "NimKit Text Editor\n\n" &
    "This is a multi-line editor built like Cocoa: a scroll view owns a text view document.\n\n" &
    "It supports selection, undo, pasteboard rich text, wrapping, insets, and attributed runs. Try editing this text, toggling wrapping, and changing the highlighted range."
  TitleText = "NimKit Text Editor"
  LinkText = "view document."
  LeadText = "It supports"
  EmphasisText = "attributed runs"

let
  TitleColor = initColor(0.95, 0.42, 0.78, 1.0).rgba
  LinkColor = initColor(0.1, 0.58, 0.95, 1.0).rgba
  EmphasisColor = initColor(0.95, 0.56, 0.24, 1.0).rgba

proc runeIndexOf(text, needle: string): int =
  let
    total = text.runeLen
    length = needle.runeLen
  if length == 0:
    return 0
  if length > total:
    return -1
  for index in 0 .. total - length:
    if text.runeSubStr(index, length) == needle:
      return index
  -1

proc demoSourceRange(needle: string): Slice[int] =
  let start = runeIndexOf(IntroText, needle)
  doAssert start >= 0, "missing demo text fragment: " & needle
  start .. start + needle.runeLen - 1

proc demoTextRange(needle: string): TextRange =
  let source = demoSourceRange(needle)
  initTextRange(source.a, source.b - source.a + 1)

proc makeIntroStorage(): TextStorage =
  result = newTextStorage(IntroText)
  result.setAttributes(
    demoTextRange(TitleText),
    defaultTextAttributes(initColor(0.95, 0.42, 0.78, 1.0), 18.0),
  )
  result.setAttributes(
    demoTextRange(LinkText),
    defaultTextAttributes(initColor(0.1, 0.58, 0.95, 1.0), 13.0),
  )
  result.setAttributes(
    demoTextRange(LeadText),
    defaultTextAttributes(initColor(0.1, 0.58, 0.95, 1.0), 13.0),
  )
  var emphasis = defaultTextAttributes(initColor(0.95, 0.56, 0.24, 1.0), 13.0)
  emphasis.underline = true
  result.setAttributes(demoTextRange(EmphasisText), emphasis)

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add(rune)

proc hasFill(
    node: Fig, range: Slice[int], color: ColorRGBA
): tuple[matched, total: int] =
  let stop = range.b + 1
  for glyph in node.textLayout.glyphs:
    if glyph.source.runeStart < stop and range.a < glyph.source.runeEnd:
      inc result.total
      if glyph.fill.kind == flColor and glyph.fill.color == color:
        inc result.matched

proc textNodeForDemo(nodes: openArray[Fig]): tuple[found: bool, node: Fig] =
  for node in nodes:
    if node.kind == nkText and node.renderedText() == IntroText:
      return (true, node)
  (false, Fig(kind: nkText))

proc buildTextEditorDemoWindow(): Window =
  let
    window = newWindow("NimKit Text Editor Demo", frame = initRect(130, 110, 720, 520))
    root = newView()
    layout = newStackView(laVertical)
    header = newTitleLabel("Text Editor Demo")
    summary =
      newStatusLabel("Characters: 275 / Selection: 0:0 / Wrap: true / Rich text: true")
    editor = newTextEditor(frame = initRect(0, 0, 640, 280))
    controls = newStackView(laHorizontal)
    wrapCheck = newCheckBox("Wrap text")
    richCheck = newCheckBox("Rich text")
    insetChoice = newComboBox(["Compact inset", "Cocoa inset", "Roomy inset"])
    tintButton = newButton("Style Selection")
    resetButton = newButton("Reset Text")

  layout.spacing = 12.0
  layout.alignment = svaFill
  layout.edgeInsets = insets(22.0, 24.0)

  editor.wraps = true
  editor.richText = true
  editor.minimumDocumentSize = initSize(640.0, 280.0)
  editor.setHuggingPriority(LayoutPriorityLow, laVertical)
  editor.setCompressionPriority(LayoutPriorityRequired, laVertical)
  editor.attributedText = makeIntroStorage()
  editor.selectedRange = initTextRange(0, 0)

  wrapCheck.state = bsOn
  richCheck.state = bsOn
  insetChoice.selectItemAtIndex(1)

  controls.spacing = 8.0
  controls.alignment = svaCenter
  controls.distribution = svdNatural
  controls.setHuggingPriority(LayoutPriorityRequired, laVertical)
  controls.setCompressionPriority(LayoutPriorityRequired, laVertical)

  controls.addArrangedSubview(
    wrapCheck, richCheck, insetChoice, tintButton, resetButton
  )
  controls.addFlexibleSpacer()
  layout.addArrangedSubview(header, summary, editor, controls)
  layout.addFlexibleSpacer()
  root.addSubview(layout)
  discard layout.pinEdges(
    toGuide = root.contentLayoutGuide(insets(0.0)),
    edges = {leLeft, leTop, leRight, leBottom},
  )

  window.setContentView(root)
  discard window.makeFirstResponder(editor)
  window

suite "nimkit text editors":
  test "text editor demo rich text reaches FigDraw glyph fills":
    let
      window = buildTextEditorDemoWindow()
      nodes = window.buildRenders()[DefaultDrawLevel].nodes
      found = nodes.textNodeForDemo()

    check found.found
    if found.found:
      let node = found.node
      check node.textLayout.sourceRuneCount == IntroText.runeLen
      check node.textLayout.glyphCount > 0
      check node.textLayout.spanColors.len == node.textLayout.spans.len

      let title = node.hasFill(demoSourceRange(TitleText), TitleColor)
      check title.total == TitleText.runeLen
      check title.matched == title.total

      let link = node.hasFill(demoSourceRange(LinkText), LinkColor)
      check link.total == LinkText.runeLen
      check link.matched == link.total

      let lead = node.hasFill(demoSourceRange(LeadText), LinkColor)
      check lead.total == LeadText.runeLen
      check lead.matched == lead.total

      let emphasis = node.hasFill(demoSourceRange(EmphasisText), EmphasisColor)
      check emphasis.total == EmphasisText.runeLen
      check emphasis.matched == emphasis.total
