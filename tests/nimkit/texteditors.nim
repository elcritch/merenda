import std/[strutils, unicode, unittest]

import figdraw

import merenda/nimkit

import ../../examples/texteditor_demo

let
  TitleColor = color(0.95, 0.42, 0.78, 1.0).rgba
  LinkColor = color(0.1, 0.58, 0.95, 1.0).rgba
  LeadColor = color(0.1, 0.58, 0.95, 1.0).rgba
  EmphasisColor = color(0.95, 0.56, 0.24, 1.0).rgba
  AttachmentColor = color(0.58, 0.27, 0.85, 1.0).rgba

proc demoSourceRange(needle: string): Slice[int] =
  let range = demoTextRange(needle)
  int(range.location) .. int(range.location + range.length - 1)

proc renderedText(node: Fig): string =
  for rune in node.textLayout.sourceRunes:
    result.add(rune)

proc hasFill(
    node: Fig, range: Slice[int], color: ColorRGBA
): tuple[matched, total: int] =
  for sourceIndex in range:
    inc result.total
    for glyphIndex, glyph in node.textLayout.arrangedGlyphs:
      if sourceIndex >= glyph.source.runeStart and sourceIndex < glyph.source.runeEnd:
        var matches = false
        for spanIndex, span in node.textLayout.spans:
          if glyphIndex in span:
            let fill = node.textLayout.spanColors[spanIndex]
            matches = fill.kind == flColor and fill.color == color
            break
        if matches:
          inc result.matched
        break

proc textNodeForDemo(nodes: openArray[Fig]): tuple[found: bool, node: Fig] =
  for node in nodes:
    if node.kind == nkText and node.renderedText() == IntroText:
      return (true, node)
  (false, Fig(kind: nkText))

proc layoutDemo(demo: TextEditorDemo) =
  discard demo.window.buildRenders()

proc centerPoint(view: View): Point =
  let bounds = view.bounds()
  initPoint(bounds.size.width / 2.0'f32, bounds.size.height / 2.0'f32)

proc windowPointFor(demo: TextEditorDemo, view: View, localPoint: Point): Point =
  demo.root.pointFromView(localPoint, view)

proc clickView(demo: TextEditorDemo, view: View): bool =
  demo.layoutDemo()
  let point = demo.windowPointFor(view, view.centerPoint())
  result = demo.window.clickAt(point)

proc clickComboItem(demo: TextEditorDemo, index: int): bool =
  demo.layoutDemo()
  let combo = demo.insetChoice
  if not demo.window.clickAt(demo.windowPointFor(combo, combo.centerPoint())):
    return false
  if not combo.popupOpen():
    return false
  let
    itemRect = combo.popupItemRect(combo.bounds(), index)
    itemPoint = initPoint(
      itemRect.origin.x + itemRect.size.width / 2.0'f32,
      itemRect.origin.y + itemRect.size.height / 2.0'f32,
    )
    windowPoint = demo.windowPointFor(combo, itemPoint)
  discard demo.window.mouseDownAt(windowPoint)
  result = demo.window.mouseUpAt(windowPoint)

suite "nimkit text editors":
  test "nowrap editor sizes document to chrome-adjusted viewport":
    let
      editor =
        newTextEditor("short\n".repeat(40), frame = rect(0, 0, 360, 120), wraps = false)
      gutter = newView(frame = rect(0, 0, 52, 1))
      scroll = editor.scrollView()

    scroll.verticalHeaderView = gutter
    editor.minimumDocumentSize = initSize(0, 0)
    editor.layoutSubtreeIfNeeded()

    check not scroll.verticalScrollerRect().isEmpty
    check scroll.horizontalScrollerRect().isEmpty
    check abs(scroll.maximumContentOffset().x) <= 0.001'f32
    check abs(scroll.documentSize().width - scroll.viewportSize().width) <= 0.001'f32

  test "text editor demo rich text reaches FigDraw glyph fills":
    let
      demo = newTextEditorDemo(newApplication())
      nodes = demo.window.buildRenders()[DefaultDrawLevel].nodes
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

      let lead = node.hasFill(demoSourceRange(LeadText), LeadColor)
      check lead.total == LeadText.runeLen
      check lead.matched == lead.total

      let emphasis = node.hasFill(demoSourceRange(EmphasisText), EmphasisColor)
      check emphasis.total == EmphasisText.runeLen
      check emphasis.matched == emphasis.total

      let attachment = node.hasFill(demoSourceRange(AttachmentText), AttachmentColor)
      check attachment.total == AttachmentText.runeLen
      check attachment.matched == attachment.total

  test "text editor demo editing controls dispatch from user mouse events":
    let demo = newTextEditorDemo(newApplication())

    check demo.summary.text.contains("Wrap: true")
    check demo.summary.text.contains("Rich text: true")

    check demo.clickView(demo.wrapCheck)
    check demo.wrapCheck.state == bsOff
    check not demo.editor.wraps
    check demo.summary.text.contains("Wrap: false")

    check demo.clickView(demo.richCheck)
    check demo.richCheck.state == bsOff
    check not demo.editor.richText
    check demo.summary.text.contains("Rich text: false")

    check demo.clickComboItem(2)
    check demo.insetChoice.indexOfSelectedItem() == 2
    check demo.editor.textInsets == insets(14.0, 18.0, 14.0, 18.0)

    demo.selectDemoRange(EmphasisText)
    let selected = demo.editor.selectedRange()
    check demo.clickView(demo.tintButton)
    let styled = demo.editor.textStorage().attributesAt(int(selected.location))
    check styled.foregroundColor == color(0.0, 0.85, 0.95, 1.0)
    check styled.underline

    check demo.clickView(demo.resetButton)
    check demo.editor.stringValue() == IntroText
    check demo.editor.selectedRange() == initTextRange(0, 0)
    check demo.featureStatus.text.startsWith("Ready:")

  test "text editor demo feature buttons dispatch from user mouse events":
    let demo = newTextEditorDemo(newApplication())

    check demo.clickView(demo.serviceButton)
    check demo.textDelegate.serviceCount == 1
    check demo.editor.stringValue().contains("IT SUPPORTS")
    check demo.featureStatus.text.startsWith("Service 1:")

    check demo.clickView(demo.copyButton)
    check not demo.lastPasteboard.isNil
    check PasteboardTypeString in demo.lastPasteboard.types()
    check PasteboardTypeTextStorage in demo.lastPasteboard.types()
    check demo.featureStatus.text.startsWith("Pasteboard:")

    check demo.clickView(demo.dragButton)
    check not demo.lastDraggingSession.isNil
    check demo.lastDraggingSession.items().len > 0
    check demo.lastDraggingSession.promisedFileItems().len > 0
    check demo.featureStatus.text.contains("promises:")

    check demo.clickView(demo.linkButton)
    check demo.editor.selectedRange() == demoTextRange(LinkText)
    check demo.featureStatus.text.startsWith("Opened link:")

    check demo.clickView(demo.pagesButton)
    check demo.featureStatus.text.startsWith("Pages:")
    check demo.featureStatus.text.contains("visible:")
    check demo.featureStatus.text.contains("line:")

    check demo.clickView(demo.documentButton)
    check demo.editor.selectedRange() == demoTextRange(AttachmentText)
    check demo.lastOpenedDocument == demo.attachmentDocument
    check demo.featureStatus.text == "Document hook: " & AttachmentUrl
