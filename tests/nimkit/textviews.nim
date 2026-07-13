import std/[sequtils, strutils, unittest]

import merenda/nimkit

const TextGeometryEpsilon = 0.01'f32

type TestPasteboardProvider = ref object of DynamicAgent
  text: string
  clearCount: int
  writtenText: seq[string]

type TextViewDelegateSpy = ref object of DynamicAgent
  allowBegin: bool
  allowChange: bool
  beginRequests: int
  didBegin: int
  didEnd: int
  shouldChanges: int
  didChanges: int
  selections: seq[seq[TextRange]]
  completions: seq[string]
  clickedLinks: seq[string]
  validation: bool
  hasValidation: bool
  serviceRequests: seq[TextServiceRequest]
  serviceResponse: TextServiceResponse

type TextViewCheckerSpy = ref object of DynamicAgent
  checkingResults: seq[TextCheckingResult]
  dataResults: seq[TextCheckingResult]

type TextCommandSpy = ref object of DynamicAgent
  selectors: seq[string]
  handled: seq[bool]

proc checkClose(actual, expected: float32) =
  check abs(actual - expected) <= TextGeometryEpsilon

proc caretPoint(textView: TextView, index: int): Point =
  let caret = textView.layoutManager().caretRect(index)
  initPoint(caret.origin.x, caret.origin.y + caret.size.height * 0.5'f32)

proc rememberTextCommand(
    spy: TextCommandSpy, selector: CommandSelector, handled: bool
) {.slot.} =
  spy.selectors.add $selector.name
  spy.handled.add handled

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

protocol TextViewDelegateSpyProtocol of TextViewDelegateProtocol:
  method tvShouldBeginEdit(spy: TextViewDelegateSpy, textView: TextView): bool =
    discard textView
    inc spy.beginRequests
    spy.allowBegin

  method tvDidBeginEdit(spy: TextViewDelegateSpy, textView: TextView) =
    discard textView
    inc spy.didBegin

  method tvDidEndEdit(spy: TextViewDelegateSpy, textView: TextView) =
    discard textView
    inc spy.didEnd

  method tvShouldChange(
      spy: TextViewDelegateSpy,
      textView: TextView,
      range: TextRange,
      replacement: TextStorage,
  ): bool =
    discard textView
    discard range
    discard replacement
    inc spy.shouldChanges
    spy.allowChange

  method tvDidChange(spy: TextViewDelegateSpy, textView: TextView, range: TextRange) =
    discard textView
    discard range
    inc spy.didChanges

  method tvSelectionChanged(
      spy: TextViewDelegateSpy, textView: TextView, ranges: seq[TextRange]
  ) =
    discard textView
    spy.selections.add ranges

  method tvCompletions(
      spy: TextViewDelegateSpy, textView: TextView, prefix: string, range: TextRange
  ): seq[string] =
    discard textView
    discard prefix
    discard range
    spy.completions

  method tvClickedLink(
      spy: TextViewDelegateSpy, textView: TextView, link: string, range: TextRange
  ): bool =
    discard textView
    discard range
    spy.clickedLinks.add link
    true

  method tvValidateCommand(
      spy: TextViewDelegateSpy, textView: TextView, action: ActionSelector
  ): bool =
    discard textView
    discard action
    if spy.hasValidation:
      return spy.validation
    false

  method tvPerformService(
      spy: TextViewDelegateSpy, textView: TextView, request: TextServiceRequest
  ): TextServiceResponse =
    discard textView
    spy.serviceRequests.add request
    spy.serviceResponse

protocol TextViewCheckerSpyProtocol of TextViewCheckingProtocol:
  method tvCheckingResults(
      spy: TextViewCheckerSpy, textView: TextView, range: TextRange
  ): seq[TextCheckingResult] =
    discard textView
    discard range
    spy.checkingResults

  method tvDataDetections(
      spy: TextViewCheckerSpy, textView: TextView, range: TextRange
  ): seq[TextCheckingResult] =
    discard textView
    discard range
    spy.dataResults

proc newTextViewDelegateSpy(
    allowBegin = true, allowChange = true
): TextViewDelegateSpy =
  result = TextViewDelegateSpy(allowBegin: allowBegin, allowChange: allowChange)
  discard result.withProtocol(TextViewDelegateSpyProtocol)

proc newTextViewCheckerSpy(): TextViewCheckerSpy =
  result = TextViewCheckerSpy()
  discard result.withProtocol(TextViewCheckerSpyProtocol)

suite "nimkit text views":
  test "text view inserts and replaces selected text":
    let textView = newTextView("abcdef", frame = rect(0, 0, 160, 24))

    textView.selectedRange = initTextRange(2, 2)
    discard textView.send(insertText(), "XY")

    check textView.stringValue == "abXYef"
    check textView.selectedRange == initTextRange(4, 0)

  test "text view delete and movement commands update selection":
    let textView = newTextView("one two", frame = rect(0, 0, 160, 24))

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
      textView = newTextView("abc", frame = rect(0, 0, 160, 24))
      accent = defaultTextAttributes(color(0.9, 0.1, 0.1))

    textView.textStorage().setAttributes(initTextRange(0, 3), accent)
    textView.selectedRange = initTextRange(1, 1)
    discard textView.send(insertText(), "Z")

    check textView.stringValue == "aZc"
    check textView.textStorage().attributesAt(1) == accent

  test "text view uses explicit typing attributes for inserted text":
    let
      textView = newTextView("abc", frame = rect(0, 0, 160, 24))
      accent = TextAttributes(
        foregroundColor: color(0.2, 0.4, 0.8), fontSize: 15.0, underline: true
      )

    textView.selectedRange = initTextRange(1, 0)
    textView.typingAttributes = accent
    discard textView.send(insertText(), "Z")

    check textView.stringValue == "aZbc"
    check textView.textStorage().attributesAt(1) == accent

  test "text view insertion at styled run end inherits previous attributes":
    let
      textView = newTextView("Title\nBody", frame = rect(0, 0, 200, 80))
      titleAttributes = defaultTextAttributes(color(0.95, 0.42, 0.78), 18.0)

    textView.textStorage().setAttributes(initTextRange(0, 5), titleAttributes)
    textView.selectedRange = initTextRange(5, 0)
    textView.insertTextValue("!")

    check textView.stringValue == "Title!\nBody"
    check textView.textStorage().attributesAt(5) == titleAttributes

  test "text view marked text replaces selection and commits through insert text":
    let textView = newTextView("abcd", frame = rect(0, 0, 160, 24))

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

  test "text view exposes text input client marked text geometry":
    let
      textView = newTextView("abcd", frame = rect(12, 18, 180, 48))
      accent = defaultTextAttributes(color(0.1, 0.3, 0.8), 14.0)

    textView.textStorage().setAttributes(initTextRange(1, 2), accent)
    textView.selectedRange = initTextRange(1, 2)
    textView.setMarkedTextValue("XY", initTextRange(1, 0), initTextRange(0, 0))

    let
      substring = textView.attributedSubstringForRange(initTextRange(1, 2))
      firstRect = textView.firstRectForCharacterRange(initTextRange(1, 1))
      index = textView.characterIndexForPoint(
        initPoint(
          firstRect.origin.x + firstRect.size.width * 0.5'f32,
          firstRect.origin.y + firstRect.size.height * 0.5'f32,
        )
      )

    check textView.hasMarkedText
    check textView.markedRange == initTextRange(1, 2)
    check textView.selectedRange == initTextRange(2, 0)
    check textView.send(textInputHasMarkedText(), ()) == true
    check textView.send(textInputSelectedRange(), ()) == initTextRange(2, 0)
    check substring.stringValue() == "XY"
    check textView
    .send(textInputAttributedSubstringForRange(), initTextRange(1, 2))
    .stringValue() == "XY"
    check substring.attributesAt(0).foregroundColor == accent.foregroundColor
    check "foregroundColor" in textView.validAttributesForMarkedText()
    check not firstRect.isEmpty
    check index == 1

  test "text view undo and redo restore text and selection":
    let textView = newTextView("abc", frame = rect(0, 0, 160, 24))

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

  test "text view delegate gates edits and receives lifecycle callbacks":
    let
      textView = newTextView("ab", frame = rect(0, 0, 160, 24))
      delegate = newTextViewDelegateSpy(allowBegin = true, allowChange = false)

    textView.delegate = DynamicAgent(delegate)
    textView.selectedRange = initTextRange(2, 0)
    textView.insertTextValue("x")

    check textView.stringValue == "ab"
    check delegate.beginRequests == 1
    check delegate.didBegin == 1
    check delegate.shouldChanges == 1
    check delegate.didChanges == 0

    delegate.allowChange = true
    textView.insertTextValue("x")
    textView.endEditing()

    check textView.stringValue == "abx"
    check delegate.didChanges == 1
    check delegate.didEnd == 1

  test "text view supports multiple and rectangular selection hooks":
    let textView = newTextView("alpha\nbeta\ngamma", frame = rect(0, 0, 240, 120))

    textView.selectionGranularity = tsgWord
    textView.selectRange(1, textView.selectionGranularity)
    check textView.selectedRange == initTextRange(0, 5)

    textView.allowsMultipleSelectedRanges = true
    textView.selectedRanges = @[initTextRange(0, 5), initTextRange(6, 4)]
    check textView.selectedRanges.len == 2

    textView.allowsRectangularSelection = true
    let rectSelection = textView.setRectangularSelection(
      textView.caretPoint(0), initPoint(200.0, textView.caretPoint(11).y)
    )
    check rectSelection.ranges.len >= 2
    textView.allowsRectangularSelection = false
    check textView.rectangularSelection.ranges.len == 0

  test "text view smart insert substitution and undo grouping are reusable":
    let textView = newTextView("helloworld", frame = rect(0, 0, 180, 24))

    textView.smartInsertDeleteEnabled = true
    textView.selectedRange = initTextRange(5, 0)
    textView.insertTextValue("big")
    check textView.stringValue == "hello big world"

    textView.stringValue = ""
    textView.substitutionOptions = {tsoSmartDashes}
    textView.insertTextValue("--")
    check textView.stringValue == "\226\128\148"

    textView.stringValue = ""
    textView.smartInsertDeleteEnabled = false
    textView.substitutionOptions = {}
    textView.beginUndoGrouping()
    textView.insertTextValue("a")
    textView.insertTextValue("b")
    textView.endUndoGrouping()
    check textView.stringValue == "ab"
    check textView.undoText()
    check textView.stringValue == ""

  test "text view find indicators checking and completion use pure contracts":
    let
      textView = newTextView(
        "alpha beta alpha https://example.test", frame = rect(0, 0, 260, 80)
      )
      replaceView = newTextView("one two one", frame = rect(0, 0, 200, 40))
      checker = newTextViewCheckerSpy()
      delegate = newTextViewDelegateSpy()

    let found = textView.showFindIndicators("alpha")
    check found == @[initTextRange(0, 5), initTextRange(11, 5)]
    check textView.findIndicators.len == 2

    check replaceView.replaceFirstText("one", "1")
    check replaceView.stringValue == "1 two one"
    check replaceView.replaceAllText("one", "1") == 1
    check replaceView.stringValue == "1 two 1"

    checker.checkingResults =
      @[initTextCheckingResult(tckSpelling, initTextRange(6, 4), "spelling")]
    textView.textChecker = DynamicAgent(checker)
    textView.substitutionOptions = {tsoDataDetection}
    let checks = textView.checkText()
    textView.applyTextCheckingResults(checks)

    check checks.len == 2
    check textView.textStorage().attributesAt(6).underline
    check textView.textStorage().attributesAt(17).link == "https://example.test"

    textView.stringValue = "alp"
    textView.selectedRange = initTextRange(3, 0)
    delegate.completions = @["alphabet"]
    textView.delegate = DynamicAgent(delegate)
    let panel = textView.completeText()
    check panel.visible
    check textView.acceptCompletion()
    check textView.stringValue == "alphabet"

  test "text view exposes caret selection and paragraph editing attributes":
    let
      textView = newTextView("abc", frame = rect(0, 0, 160, 24))
      selectedAttributes = defaultTextAttributes(color(1.0, 1.0, 1.0, 1.0), 14.0)
      caretColor = color(0.9, 0.1, 0.2, 1.0)
      tabStop = initTextTabStop(48.0)
    var paragraph = initTextParagraphStyle(tabStops = [tabStop])

    paragraph.lineSpacing = 2.0
    textView.selectedTextAttributes = selectedAttributes
    textView.insertionPointColor = caretColor
    textView.insertionPointVisible = false
    textView.insertionPointBlinkPeriod = 0.25
    textView.markedTextAttributes = selectedAttributes
    textView.setParagraphStyle(initTextRange(0, 3), paragraph)
    textView.defaultParagraphStyle = paragraph
    textView.usesRuler = true
    textView.rulerVisible = true

    check textView.selectedTextAttributes == selectedAttributes
    check textView.insertionPointColor == caretColor
    check not textView.insertionPointVisible
    check textView.insertionPointBlinkPeriod == 0.25'f32
    check textView.markedTextAttributes == selectedAttributes
    check textView.paragraphStyleAt(1).tabStops.len == 1
    check textView.typingAttributes.paragraphStyle == paragraph
    check textView.rulerVisible

    textView.usesRuler = false
    check not textView.rulerVisible

  test "text view exposes accessibility parameterized text attributes":
    let textView = newTextView("Title\nBody", frame = rect(0, 0, 220, 90))
    var attributes = textView.textStorage().attributesAt(0)
    attributes.link = "https://example.test"
    attributes.fontSize = 18.0
    textView.textStorage().setAttributes(initTextRange(0, 5), attributes)
    textView.allowsMultipleSelectedRanges = true
    textView.selectedRanges = @[initTextRange(0, 5), initTextRange(6, 4)]

    let
      selectedRanges = textView.accessibilitySelectedTextRanges()
      visibleRange = textView.accessibilityVisibleCharacterRange()
      attributed =
        textView.accessibilityAttributedStringForRange(initAccessibilityTextRange(0, 5))
      rangeValue =
        textView.accessibilityAttributeValue(AccessibilityAttributeSelectedTextRanges)
      visibleValue = textView.accessibilityAttributeValue(
        AccessibilityAttributeVisibleCharacterRange
      )
      insertionLine =
        textView.accessibilityAttributeValue(AccessibilityAttributeInsertionPointLine)

    check selectedRanges ==
      @[initAccessibilityTextRange(0, 5), initAccessibilityTextRange(6, 4)]
    check visibleRange.length > 0
    check attributed.stringValue == "Title"
    check attributed.runs.len == 1
    check attributed.runs[0].attributes.anyIt(
      it.name == "link" and it.value == "https://example.test"
    )
    check rangeValue.kind == avTextRanges
    check visibleValue.kind == avTextRange
    check insertionLine.kind == avInt
    check insertionLine.intValue == textView.lineForIndex(5)

  test "text view pagination ruler and stability snapshots are deterministic":
    let textView =
      newTextView("One\nTwo\nThree\nFour\nFive", frame = rect(0, 0, 140, 80))
    let tabStop = initTextTabStop(42.0)
    var paragraph = initTextParagraphStyle(tabStops = [tabStop])
    paragraph.firstLineHeadIndent = 12.0
    paragraph.headIndent = 8.0
    textView.setParagraphStyle(initTextRange(0, textView.textStorage().len), paragraph)

    let
      pageOptions = initTextPageLayoutOptions(
        pageSize = initSize(200.0, 36.0),
        contentInsets = insets(0.0),
        firstPageNumber = 1,
        displayScale = 1.0,
      )
      pages = textView.paginateTextView(pageOptions)
      ruler = textView.rulerMetrics(initTextRange(0, 3))
      scaleOne = textView.layoutStabilitySnapshot(
        TextLayoutStabilityOptions(
          displayScale: 1.0, fontSize: 12.0, pageOptions: pageOptions
        )
      )
      scaleTwo = textView.layoutStabilitySnapshot(
        TextLayoutStabilityOptions(
          displayScale: 2.0, fontSize: 12.0, pageOptions: pageOptions
        )
      )
      largerFont = textView.layoutStabilitySnapshot(
        TextLayoutStabilityOptions(
          displayScale: 1.0, fontSize: 18.0, pageOptions: pageOptions
        )
      )

    check pages.len >= 2
    check pages[0].pageNumber == 1
    check pages[0].lineFragments.len > 0
    check ruler.firstLineHeadIndent == 12.0'f32
    check ruler.headIndent == 8.0'f32
    check ruler.tabStops == @[tabStop]
    check scaleOne.lineFragments.len == scaleTwo.lineFragments.len
    check scaleOne.lineFragments[0].textRange == scaleTwo.lineFragments[0].textRange
    check largerFont.contentSize.height >= scaleOne.contentSize.height

  test "text view validates commands and dispatches clicked links":
    let
      textView = newTextView("link", frame = rect(0, 0, 160, 24))
      delegate = newTextViewDelegateSpy()
    var attributes = textView.textStorage().attributesAt(0)

    check not textView.validateTextCommand(actionSelector("copy"))
    textView.selectedRange = initTextRange(0, 4)
    check textView.validateTextCommand(actionSelector("copy"))
    check textView.validateTextCommand(actionSelector("cut"))

    textView.selectedRange = initTextRange(4, 0)
    textView.insertTextValue("!")
    check textView.validateTextCommand(actionSelector("undo"))

    attributes.link = "https://example.test"
    textView.textStorage().setAttributes(initTextRange(0, 4), attributes)
    delegate.hasValidation = true
    delegate.validation = true
    textView.delegate = DynamicAgent(delegate)
    check textView.clickTextAtPoint(textView.caretPoint(1))
    check delegate.clickedLinks == @["https://example.test"]

    delegate.hasValidation = true
    delegate.validation = false
    check not textView.validateTextCommand(actionSelector("paste"))
    delegate.validation = true
    check textView.validateTextCommand(actionSelector("paste"))

  test "text view copy cut and paste use the general pasteboard":
    let
      pasteboard = generalPasteboard()
      source = newTextView("abcd", frame = rect(0, 0, 160, 24))
      target = newTextView("zz", frame = rect(0, 0, 160, 24))

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

  test "text view services can replace selected attributed text":
    let
      textView = newTextView("abcdef", frame = rect(0, 0, 180, 40))
      delegate = newTextViewDelegateSpy()
      replacementAttributes = defaultTextAttributes(color(0.7, 0.1, 0.2), 13.0)

    delegate.serviceResponse = TextServiceResponse(
      handled: true,
      replacementRange: initTextRange(1, 3),
      replacement: newAttributedString("XYZ", replacementAttributes),
    )
    textView.delegate = DynamicAgent(delegate)
    textView.selectedRange = initTextRange(1, 3)

    let response = textView.performSelectedTextService()

    check response.handled
    check delegate.serviceRequests.len == 1
    check delegate.serviceRequests[0].stringValue == "bcd"
    check delegate.serviceRequests[0].attributedString.stringValue == "bcd"
    check textView.stringValue == "aXYZef"
    check textView.textStorage().attributesAt(1).foregroundColor ==
      replacementAttributes.foregroundColor

  test "text view rich transfer dragging and attachments use pure contracts":
    let
      source = newTextView("link image end", frame = rect(0, 0, 260, 80))
      target = newTextView("drop", frame = rect(0, 0, 260, 80))
      pasteboard = pasteboardWithUniqueName()

    var linkAttributes = source.textStorage().attributesAt(0)
    linkAttributes.link = "https://example.test"
    linkAttributes.underlineStyle = tldsSingle
    source.textStorage().setAttributes(initTextRange(0, 4), linkAttributes)

    var imageAttributes = source.textStorage().attributesAt(5)
    imageAttributes.attachment = initTextAttachment(
      identifier = "image-1",
      contentType = "image/png",
      fileName = "image.png",
      fileUrl = "file:///tmp/image.png",
    )
    source.textStorage().setAttributes(initTextRange(5, 5), imageAttributes)
    source.selectedRange = initTextRange(0, source.textStorage().len)

    check source.writeSelectionToPasteboard(
      pasteboard, [ttfPlainText, ttfAttributedText, ttfHTML, ttfURL, ttfFilePromise]
    )
    check pasteboard.stringForType(PasteboardTypeString) == "link image end"
    check pasteboard.attributedString().attributesAt(0).link == "https://example.test"
    check pasteboard.html().contains("link image end")
    check pasteboard.urlForType(PasteboardTypeUrl) == "https://example.test"
    check pasteboard.fileForType(PasteboardTypeFilePromise) == "image.png"

    let
      attachments = source.selectedAttachmentPresentations()
      images = source.selectedImageAttachments()
      promised = source.selectedFilePromiseAttachments()
    check attachments.len == 1
    check attachments[0].cell.attachment.identifier == "image-1"
    check images.len == 1
    check promised.len == 1

    let session = source.beginDraggingSelectedText(
      {dgoCopy}, pasteboardWithUniqueName().pasteboardName()
    )
    check not session.isNil
    check session.items().len >= 3
    check session.promisedFileItems().len == 1

    target.selectedRange = initTextRange(target.textStorage().len, 0)
    check session.performDraggingOperation(DynamicAgent(target), target.caretPoint(4))
    check target.stringValue == "droplink image end"

  test "text view contextual menu routes open link through selector commands":
    let
      textView = newTextView("link", frame = rect(0, 0, 180, 40))
      delegate = newTextViewDelegateSpy()
    var attributes = textView.textStorage().attributesAt(0)
    attributes.link = "https://example.test"
    textView.textStorage().setAttributes(initTextRange(0, 4), attributes)
    delegate.hasValidation = true
    delegate.validation = true
    textView.delegate = DynamicAgent(delegate)

    let
      menu = textView.contextualMenuForText(textView.caretPoint(1))
      item = menu[0]

    check item.title == "Open Link"
    check item.validate(Responder(textView))
    check item.perform(Responder(textView))
    check delegate.clickedLinks == @["https://example.test"]

  test "text view document controller helper opens attachment documents":
    let
      app = newApplication()
      controller = newDocumentController(app)
      document = newDocument("file:///tmp/image.png", "png")
      attachment = initTextAttachment(
        identifier = "image-1",
        contentType = "image/png",
        fileName = "image.png",
        fileUrl = "file:///tmp/image.png",
      )

    controller.addDocument(document)
    check controller.openAttachmentDocument(attachment, app) == document

  test "general pasteboard is named and can sync string data through a provider":
    let
      pasteboard = generalPasteboard()
      previousProvider = pasteboard.provider
      provider = newTestPasteboardProvider()
      target = newTextView("zz", frame = rect(0, 0, 160, 24))
      source = newTextView("abcd", frame = rect(0, 0, 160, 24))

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
    let textView = newTextView("ab", frame = rect(0, 0, 160, 24))

    textView.selectedRange = initTextRange(1, 0)
    discard textView.send(insertNewline(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.stringValue == "a\nb"
    check textView.selectedRange == initTextRange(2, 0)

    discard textView.send(insertTab(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.stringValue == "a\n\tb"
    check textView.selectedRange == initTextRange(3, 0)

  test "text view dispatches key bindings and IME commands through selectors":
    let
      window = newWindow("Text command dispatch", frame = rect(0, 0, 260, 120))
      root = newView(frame = rect(0, 0, 260, 120))
      textView = newTextView("alpha\nbeta", frame = rect(12, 12, 180, 80))
      spy = TextCommandSpy()

    textView.connect(textCommandDispatched, spy, rememberTextCommand)
    root.addSubview(textView)
    window.setContentView(root)
    window.setKeyBindingProfile(kbpMacOS)

    textView.selectedRange = initTextRange(textView.textStorage().len, 0)
    check window.makeFirstResponder(textView)
    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord, modifiers: {kmCommand})
    )
    check textView.selectedRange == initTextRange(0, 0)

    doCommandBySelector(
      Responder(textView), moveToEndOfDocument(), DynamicAgent(textView)
    )
    check textView.selectedRange == initTextRange(textView.textStorage().len, 0)
    check spy.selectors[^2] == "moveToBeginningOfDocument"
    check spy.selectors[^1] == "moveToEndOfDocument"
    check spy.handled[^2] and spy.handled[^1]

  test "macOS control p and n move between visual lines":
    let
      window = newWindow("Text control line movement", frame = rect(0, 0, 260, 120))
      root = newView(frame = rect(0, 0, 260, 120))
      textView = newTextView("abc\ndef\nghi", frame = rect(12, 12, 180, 90))

    root.addSubview(textView)
    window.setContentView(root)
    window.setKeyBindingProfile(kbpMacOS)
    check window.makeFirstResponder(textView)

    textView.selectedRange = initTextRange(1, 0)
    check window.dispatchKeyDown(
      KeyEvent(key: keyN, keyCode: keyN.ord, modifiers: {kmControl})
    )
    check textView.selectedRange == initTextRange(5, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyP, keyCode: keyP.ord, modifiers: {kmControl})
    )
    check textView.selectedRange == initTextRange(1, 0)

  test "text view line deletion and document movement selectors work":
    let textView = newTextView("alpha\nbeta", frame = rect(0, 0, 180, 80))

    textView.selectedRange = initTextRange(8, 0)
    discard textView.send(
      deleteToBeginningOfLine(), ActionArgs(sender: DynamicAgent(textView))
    )
    check textView.stringValue == "alpha\nta"
    check textView.selectedRange == initTextRange(6, 0)

    discard textView.send(
      insertParagraphSeparator(), ActionArgs(sender: DynamicAgent(textView))
    )
    check textView.stringValue == "alpha\n\nta"
    discard
      textView.send(moveToEndOfDocument(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(textView.textStorage().len, 0)

  test "text view caret after newline starts on the next visual line":
    let
      textRect = rect(0, 0, 200, 100)
      layout = textLayout(textRect, newTextStorage("A\nB"), taLeft, wrap = false)
      firstLineStart = caretRect(textRect, layout, 0)
      firstLineEnd = caretRect(textRect, layout, 1)
      afterNewline = caretRect(textRect, layout, 2)

    checkClose(afterNewline.origin.x, firstLineStart.origin.x)
    check afterNewline.origin.y > firstLineEnd.origin.y

  test "text view caret supports blank lines between newline characters":
    let
      textRect = rect(0, 0, 200, 140)
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
    let textView = newTextView("abcdef", frame = rect(0, 0, 240, 80))

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
    let textView = newTextView("abcdef", frame = rect(0, 0, 240, 80))

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
    let textView = newTextView("Title\nSecond", frame = rect(0, 0, 240, 120))
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
    let textView = newTextView("abc\ndef\nghi", frame = rect(0, 0, 200, 120))

    textView.selectedRange = initTextRange(1, 0)
    discard textView.send(moveDown(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(5, 0)

    discard textView.send(moveDown(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(9, 0)

    discard textView.send(moveUp(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(5, 0)

  test "text view up and down commands move through blank lines":
    let textView = newTextView("ab\n\ncd", frame = rect(0, 0, 200, 120))

    textView.selectedRange = initTextRange(1, 0)
    discard textView.send(moveDown(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(3, 0)

    discard textView.send(moveDown(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(4, 0)

    discard textView.send(moveUp(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(3, 0)

  test "text view shift up and down extends selection":
    let textView = newTextView("abc\ndef", frame = rect(0, 0, 200, 90))

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
