import std/unittest

import merenda/nimkit

type TestPasteboardProvider = ref object of DynamicAgent
  text: string
  clearCount: int
  writtenText: seq[string]

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
