import std/unittest

import merenda/nimkit

const TextGeometryEpsilon = 0.01'f32

type TestPasteboardProvider = ref object of DynamicAgent
  text: string
  clearCount: int
  writtenText: seq[string]

proc checkClose(actual, expected: float32) =
  check abs(actual - expected) <= TextGeometryEpsilon

proc caretPoint(textView: TextView, index: int): Point =
  let caret = textView.layoutManager().caretRect(index)
  initPoint(caret.origin.x, caret.origin.y + caret.size.height * 0.5'f32)

protocol TestPasteboardProviderProtocol of PasteboardProviderProtocol:
  method pasteboardTypes(
      provider: TestPasteboardProvider, pasteboard: Pasteboard
  ): seq[string] =
    if provider.text.len > 0:
      result.add PasteboardTypeString

  method stringForPasteboardType(
      provider: TestPasteboardProvider, request: PasteboardTypeRequest
  ): string =
    if request.kind == PasteboardTypeString: provider.text else: ""

  method setStringForPasteboardType(
      provider: TestPasteboardProvider, request: PasteboardStringRequest
  ): bool =
    if request.kind != PasteboardTypeString:
      return false
    provider.text = request.value
    provider.writtenText.add request.value
    true

  method clearPasteboardContents(
      provider: TestPasteboardProvider, pasteboard: Pasteboard
  ): bool =
    provider.text = ""
    inc provider.clearCount
    true

proc newTestPasteboardProvider(text = ""): TestPasteboardProvider =
  result = TestPasteboardProvider(text: text)
  discard result.withProtocol(TestPasteboardProviderProtocol)

suite "nimkit text views":
  test "text view inserts and replaces selected text":
    let textView = newTextView("abcdef", frame = initRect(0, 0, 160, 24))

    textView.selectedRange = initTextRange(2, 2)
    discard textView.send(insertText(), "XY")

    check textView.stringValue == "abXYef"
    check textView.selectedRange == initTextRange(4, 0)

  test "text view delete and movement commands update selection":
    let textView = newTextView("one two", frame = initRect(0, 0, 160, 24))

    textView.selectedRange = initTextRange(7, 0)
    discard textView.send(moveWordLeft(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(4, 0)

    discard
      textView.send(deleteWordForward(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.stringValue == "one "
    check textView.selectedRange == initTextRange(4, 0)

    discard textView.send(deleteBackward(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.stringValue == "one"
    check textView.selectedRange == initTextRange(3, 0)

  test "text view keeps attributed storage":
    let
      textView = newTextView("abc", frame = initRect(0, 0, 160, 24))
      accent = defaultTextAttributes(initColor(0.9, 0.1, 0.1))

    textView.textStorage().setAttributes(initTextRange(0, 3), accent)
    textView.selectedRange = initTextRange(1, 1)
    discard textView.send(insertText(), "Z")

    check textView.stringValue == "aZc"
    check textView.textStorage().attributesAt(1) == accent

  test "text view uses explicit typing attributes for inserted text":
    let
      textView = newTextView("abc", frame = initRect(0, 0, 160, 24))
      accent = TextAttributes(
        foregroundColor: initColor(0.2, 0.4, 0.8), fontSize: 15.0, underline: true
      )

    textView.selectedRange = initTextRange(1, 0)
    textView.typingAttributes = accent
    discard textView.send(insertText(), "Z")

    check textView.stringValue == "aZbc"
    check textView.textStorage().attributesAt(1) == accent

  test "text view insertion at styled run end inherits previous attributes":
    let
      textView = newTextView("Title\nBody", frame = initRect(0, 0, 200, 80))
      titleAttributes = defaultTextAttributes(initColor(0.95, 0.42, 0.78), 18.0)

    textView.textStorage().setAttributes(initTextRange(0, 5), titleAttributes)
    textView.selectedRange = initTextRange(5, 0)
    textView.insertTextValue("!")

    check textView.stringValue == "Title!\nBody"
    check textView.textStorage().attributesAt(5) == titleAttributes

  test "text view marked text replaces selection and commits through insert text":
    let textView = newTextView("abcd", frame = initRect(0, 0, 160, 24))

    textView.selectedRange = initTextRange(1, 2)
    textView.setMarkedTextValue("XY", initTextRange(1, 0), initTextRange(0, 0))

    check textView.hasMarkedText
    check textView.markedRange == initTextRange(1, 2)
    check textView.selectedRange == initTextRange(2, 0)
    check textView.stringValue == "aXYd"

    textView.insertTextValue("Z")
    check not textView.hasMarkedText
    check textView.stringValue == "aZd"
    check textView.selectedRange == initTextRange(2, 0)
    check textView.undoText()
    check textView.stringValue == "abcd"
    check textView.selectedRange == initTextRange(1, 2)

  test "text view undo and redo restore text and selection":
    let textView = newTextView("abc", frame = initRect(0, 0, 160, 24))

    textView.selectedRange = initTextRange(3, 0)
    textView.insertTextValue("d")

    check textView.stringValue == "abcd"
    check textView.selectedRange == initTextRange(4, 0)
    check textView.undoText()
    check textView.stringValue == "abc"
    check textView.selectedRange == initTextRange(3, 0)
    check textView.redoText()
    check textView.stringValue == "abcd"
    check textView.selectedRange == initTextRange(4, 0)

  test "text view copy cut and paste use the general pasteboard":
    let
      pasteboard = generalPasteboard()
      source = newTextView("abcd", frame = initRect(0, 0, 160, 24))
      target = newTextView("zz", frame = initRect(0, 0, 160, 24))

    pasteboard.clearContents()
    source.selectedRange = initTextRange(1, 2)

    check source.copyText()
    check pasteboard.stringForType(PasteboardTypeString) == "bc"

    target.selectedRange = initTextRange(1, 0)
    check target.pasteText()
    check target.stringValue == "zbcz"
    check target.selectedRange == initTextRange(3, 0)

    check source.cutText()
    check source.stringValue == "ad"
    check source.selectedRange == initTextRange(1, 0)

  test "general pasteboard is named and can sync string data through a provider":
    let
      pasteboard = generalPasteboard()
      previousProvider = pasteboard.provider
      provider = newTestPasteboardProvider()
      target = newTextView("zz", frame = initRect(0, 0, 160, 24))
      source = newTextView("abcd", frame = initRect(0, 0, 160, 24))

    pasteboard.provider = nil
    pasteboard.clearContents()
    pasteboard.provider = provider
    check pasteboard == pasteboardWithName(GeneralPasteboardName)
    check pasteboardWithName(FindPasteboardName) ==
      pasteboardWithName(FindPasteboardName)
    check pasteboardWithUniqueName() != pasteboardWithUniqueName()

    provider.text = "clip"
    target.selectedRange = initTextRange(1, 0)
    check target.pasteText()
    check target.stringValue == "zclipz"
    check target.selectedRange == initTextRange(5, 0)

    source.selectedRange = initTextRange(1, 2)
    check source.copyText()
    check provider.writtenText[^1] == "bc"
    check pasteboard.availableTypeFromArray(
      [PasteboardTypeTextStorage, PasteboardTypeString]
    ) == PasteboardTypeTextStorage

    pasteboard.provider = nil
    pasteboard.clearContents()
    pasteboard.provider = previousProvider

  test "text view newline and tab commands insert text":
    let textView = newTextView("ab", frame = initRect(0, 0, 160, 24))

    textView.selectedRange = initTextRange(1, 0)
    discard textView.send(insertNewline(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.stringValue == "a\nb"
    check textView.selectedRange == initTextRange(2, 0)

    discard textView.send(insertTab(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.stringValue == "a\n\tb"
    check textView.selectedRange == initTextRange(3, 0)

  test "text view caret after newline starts on the next visual line":
    let
      textRect = initRect(0, 0, 200, 100)
      layout = textLayout(textRect, newTextStorage("A\nB"), taLeft, wrap = false)
      firstLineStart = caretRect(textRect, layout, 0)
      firstLineEnd = caretRect(textRect, layout, 1)
      afterNewline = caretRect(textRect, layout, 2)

    checkClose(afterNewline.origin.x, firstLineStart.origin.x)
    check afterNewline.origin.y > firstLineEnd.origin.y

  test "text view caret supports blank lines between newline characters":
    let
      textRect = initRect(0, 0, 200, 140)
      layout = textLayout(textRect, newTextStorage("A\n\nB"), taLeft, wrap = false)
      firstLineStart = caretRect(textRect, layout, 0)
      firstLineEnd = caretRect(textRect, layout, 1)
      blankLineStart = caretRect(textRect, layout, 2)
      finalLineStart = caretRect(textRect, layout, 3)

    checkClose(blankLineStart.origin.x, firstLineStart.origin.x)
    checkClose(finalLineStart.origin.x, firstLineStart.origin.x)
    check blankLineStart.origin.y > firstLineEnd.origin.y
    check finalLineStart.origin.y > blankLineStart.origin.y

  test "text view hit testing line starts returns indexes after newlines":
    let manager = newTextLayoutManager(
      newTextStorage("A\nB"),
      initTextContainer(initSize(200, 100), insets(0.0), wraps = false),
    )
    let afterNewline = manager.caretRect(2)

    check manager.textIndexAtPoint(
      initPoint(
        afterNewline.origin.x + 0.5'f32,
        afterNewline.origin.y + afterNewline.size.height * 0.5'f32,
      )
    ) == 2

  test "text view hit testing blank lines returns newline boundary indexes":
    let manager = newTextLayoutManager(
      newTextStorage("A\n\nB"),
      initTextContainer(initSize(200, 140), insets(0.0), wraps = false),
    )
    let
      blankLineStart = manager.caretRect(2)
      finalLineStart = manager.caretRect(3)

    check manager.textIndexAtPoint(
      initPoint(
        blankLineStart.origin.x + 0.5'f32,
        blankLineStart.origin.y + blankLineStart.size.height * 0.5'f32,
      )
    ) == 2
    check manager.textIndexAtPoint(
      initPoint(
        finalLineStart.origin.x + 0.5'f32,
        finalLineStart.origin.y + finalLineStart.size.height * 0.5'f32,
      )
    ) == 3
    check manager.textIndexAtPoint(
      initPoint(
        blankLineStart.origin.x + 0.5'f32,
        max(blankLineStart.origin.y, finalLineStart.origin.y - 1.0'f32),
      )
    ) == 2

  test "text view hit testing beyond line end clamps to that visual line":
    let manager = newTextLayoutManager(
      newTextStorage("Title\nSecond"),
      initTextContainer(initSize(240, 120), insets(8.0), wraps = false),
    )
    let
      firstLineEnd = manager.caretRect(5)
      secondLineStart = manager.caretRect(6)

    check manager.textIndexAtPoint(
      initPoint(
        firstLineEnd.origin.x + 80.0'f32,
        firstLineEnd.origin.y + firstLineEnd.size.height * 0.5'f32,
      )
    ) == 5
    check manager.textIndexAtPoint(
      initPoint(
        secondLineStart.origin.x + 80.0'f32,
        secondLineStart.origin.y + secondLineStart.size.height * 0.5'f32,
      )
    ) > 5

  test "text view mouse drag selects text from the mouse down anchor":
    let textView = newTextView("abcdef", frame = initRect(0, 0, 240, 80))

    check textView.mouseDown(
      MouseEvent(location: textView.caretPoint(1), button: mbPrimary)
    )
    check textView.mouseDragged(
      MouseEvent(location: textView.caretPoint(4), button: mbPrimary)
    )
    check textView.selectedRange == initTextRange(1, 3)
    check textView.selectionAnchor == 1
    check textView.insertionPoint == 4
    check textView.mouseUp(
      MouseEvent(location: textView.caretPoint(4), button: mbPrimary)
    )

  test "text view reverse mouse drag keeps a normalized selected range":
    let textView = newTextView("abcdef", frame = initRect(0, 0, 240, 80))

    check textView.mouseDown(
      MouseEvent(location: textView.caretPoint(4), button: mbPrimary)
    )
    check textView.mouseDragged(
      MouseEvent(location: textView.caretPoint(1), button: mbPrimary)
    )
    check textView.selectedRange == initTextRange(1, 3)
    check textView.selectionAnchor == 4
    check textView.insertionPoint == 1
    check textView.mouseUp(
      MouseEvent(location: textView.caretPoint(1), button: mbPrimary)
    )

  test "text view mouse drag beyond a line end selects to that visual line end":
    let textView = newTextView("Title\nSecond", frame = initRect(0, 0, 240, 120))
    let
      firstLineStart = textView.caretPoint(0)
      firstLineEnd = textView.layoutManager().caretRect(5)
      dragPoint = initPoint(
        firstLineEnd.origin.x + 80.0'f32,
        firstLineEnd.origin.y + firstLineEnd.size.height * 0.5'f32,
      )

    check textView.mouseDown(MouseEvent(location: firstLineStart, button: mbPrimary))
    check textView.mouseDragged(MouseEvent(location: dragPoint, button: mbPrimary))
    check textView.selectedRange == initTextRange(0, 5)
    check textView.mouseUp(MouseEvent(location: dragPoint, button: mbPrimary))

  test "text view up and down commands move between visual lines":
    let textView = newTextView("abc\ndef\nghi", frame = initRect(0, 0, 200, 120))

    textView.selectedRange = initTextRange(1, 0)
    discard textView.send(moveDown(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(5, 0)

    discard textView.send(moveDown(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(9, 0)

    discard textView.send(moveUp(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(5, 0)

  test "text view up and down commands move through blank lines":
    let textView = newTextView("ab\n\ncd", frame = initRect(0, 0, 200, 120))

    textView.selectedRange = initTextRange(1, 0)
    discard textView.send(moveDown(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(3, 0)

    discard textView.send(moveDown(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(4, 0)

    discard textView.send(moveUp(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(3, 0)

  test "text view shift up and down extends selection":
    let textView = newTextView("abc\ndef", frame = initRect(0, 0, 200, 90))

    textView.selectedRange = initTextRange(1, 0)
    discard textView.send(
      moveDownAndModifySelection(), ActionArgs(sender: DynamicAgent(textView))
    )
    check textView.selectedRange == initTextRange(1, 4)

    discard textView.send(
      moveUpAndModifySelection(), ActionArgs(sender: DynamicAgent(textView))
    )
    check textView.selectedRange == initTextRange(1, 0)

  test "field editor ignoring commands insert literal newline and tab":
    let editor = newFieldEditor()

    TextView(editor).stringValue = "ab"
    TextView(editor).selectedRange = initTextRange(1, 0)
    discard editor.send(
      insertNewlineIgnoringFieldEditor(), ActionArgs(sender: DynamicAgent(editor))
    )
    discard editor.send(
      insertTabIgnoringFieldEditor(), ActionArgs(sender: DynamicAgent(editor))
    )

    check TextView(editor).stringValue == "a\n\tb"
    check TextView(editor).selectedRange == initTextRange(3, 0)
