import std/[math, options, strutils, unicode]

import sigils/core

import ../accessibility/accessibility
import ../app/dragging
import ../drawing
import ../foundation/events
import ../app/pasteboards
import ../foundation/selectors
import ./textlayout
import ./textstorage
import ./texttypes
import ../themes
import ../foundation/types
import ../view/views

export views
export textlayout
export textstorage
export texttypes

type
  TextViewFlag = enum
    tvEditable
    tvSelectable
    tvRichText
    tvFieldEditor
    tvAllowsUndo

  TextViewFlags = set[TextViewFlag]

  TextUndoRecord = object
    storageBefore: TextStorage
    storageAfter: TextStorage
    selectionBefore: TextRange
    selectionAfter: TextRange

  TextSelectionGranularity* = enum
    tsgCharacter
    tsgWord
    tsgLine
    tsgParagraph
    tsgDocument

  TextSubstitutionOption* = enum
    tsoSmartQuotes
    tsoSmartDashes
    tsoDataDetection

  TextSubstitutionOptions* = set[TextSubstitutionOption]

  TextCheckingKind* = enum
    tckSpelling
    tckGrammar
    tckLink
    tckData

  TextCheckingResult* = object
    kind*: TextCheckingKind
    range*: TextRange
    message*: string
    replacement*: string
    link*: string
    attributes*: TextAttributes

  TextRectSelection* = object
    anchor*: Point
    focus*: Point
    bounds*: Rect
    ranges*: seq[TextRange]

  TextFindIndicator* = object
    range*: TextRange
    rects*: seq[Rect]
    color*: Color
    visible*: bool

  TextCompletionPanel* = object
    prefix*: string
    range*: TextRange
    completions*: seq[string]
    selectedIndex*: int
    visible*: bool

  TextServiceRequest* = object
    range*: TextRange
    selectedRanges*: seq[TextRange]
    stringValue*: string
    attributedString*: TextStorage

  TextServiceResponse* = object
    handled*: bool
    replacementRange*: TextRange
    replacement*: TextStorage

  TextAttachmentCell* = object
    attachment*: TextAttachment
    range*: TextRange
    frame*: Rect

  TextAttachmentPresentation* = object
    attachment*: TextAttachment
    range*: TextRange
    frame*: Rect
    cell*: TextAttachmentCell
    view*: View

  TextPageLayoutOptions* = object
    pageSize*: Size
    contentInsets*: EdgeInsets
    firstPageNumber*: Natural
    displayScale*: float32

  TextPageFragment* = object
    pageIndex*: Natural
    pageNumber*: Natural
    containerIndex*: TextContainerIndex
    textRange*: TextRange
    pageRect*: Rect
    contentRect*: Rect
    usedRect*: Rect
    lineFragments*: seq[TextLineFragment]

  TextRulerMetrics* = object
    range*: TextRange
    paragraphStyle*: TextParagraphStyle
    rulerRect*: Rect
    firstLineHeadIndent*: float32
    headIndent*: float32
    tailIndent*: float32
    tabStops*: seq[TextTabStop]

  TextLayoutStabilityOptions* = object
    displayScale*: float32
    fontSize*: float32
    pageOptions*: TextPageLayoutOptions

  TextLayoutStabilitySnapshot* = object
    textHash*: int
    layoutHash*: int
    displayScale*: float32
    fontSize*: float32
    containerRect*: Rect
    usedRect*: Rect
    contentSize*: Size
    lineFragments*: seq[TextLineFragment]
    pageFragments*: seq[TextPageFragment]

  TextView* = ref object of View
    xTextStorage: TextStorage
    xTextContainer: TextContainer
    xLayoutManager: TextLayoutManager
    xDelegate: DynamicAgent
    xTextChecker: DynamicAgent
    xFlags: TextViewFlags
    xAlignment: TextAlignment
    xSelectionAnchor: int
    xInsertionPoint: int
    xSelectionAffinity: TextAffinity
    xSelectionGranularity: TextSelectionGranularity
    xAllowsMultipleSelectedRanges: bool
    xSelectedRanges: seq[TextRange]
    xAllowsRectangularSelection: bool
    xRectangularSelection: TextRectSelection
    xTextColor: Color
    xTextStyleOverride: TextStyle
    xSelectionColor: Color
    xTypingAttributes: TextAttributes
    xSelectedTextAttributes: TextAttributes
    xHasTextStyleOverride: bool
    xHasSelectedTextAttributes: bool
    xInsertionPointColor: Color
    xInsertionPointVisible: bool
    xInsertionPointBlinkPeriod: float32
    xMarkedTextAttributes: TextAttributes
    xFindIndicators: seq[TextFindIndicator]
    xCheckingResults: seq[TextCheckingResult]
    xCompletionPanel: TextCompletionPanel
    xSubstitutionOptions: TextSubstitutionOptions
    xSmartInsertDelete: bool
    xDefaultParagraphStyle: TextParagraphStyle
    xUsesRuler: bool
    xRulerVisible: bool
    xEditing: bool
    xMarkedRange: TextRange
    xHasMarkedText: bool
    xMarkedUndoStorage: TextStorage
    xMarkedUndoSelection: TextRange
    xUndoStack: seq[TextUndoRecord]
    xRedoStack: seq[TextUndoRecord]
    xUndoGroupingDepth: Natural
    xGroupedUndoBefore: TextStorage
    xGroupedUndoSelection: TextRange
    xHasGroupedUndo: bool
    xApplyingUndo: bool
    xSelectingWithMouse: bool
    xDraggingSession: DraggingSession

proc syncLayout(textView: TextView)
proc clearMarkedText(textView: TextView)
proc textViewStringValue(textView: TextView): string
proc setTextViewStringValue(textView: TextView, value: string)
proc textViewSelectedRange(textView: TextView): TextRange
proc setTextViewSelectedRange(textView: TextView, value: TextRange)
proc textViewInsertionPoint(textView: TextView): int
proc textViewSelectionAnchor(textView: TextView): int
proc updateTextContainer(textView: TextView)
proc currentVisualLineBounds(textView: TextView): tuple[first, last: int]
proc clampedRange(textView: TextView, range: TextRange): TextRange
proc setCursor*(textView: TextView, index: int, extending = false)
proc selectAllText*(textView: TextView)
proc replaceSelectedText*(textView: TextView, insertion: string)
proc insertTextValue*(textView: TextView, insertion: string)
proc setMarkedTextValue*(
  textView: TextView, text: string, selectedRange, replacementRange: TextRange
)

proc unmarkMarkedText*(textView: TextView)
proc copyText*(textView: TextView): bool
proc cutText*(textView: TextView): bool
proc pasteText*(textView: TextView): bool
proc undoText*(textView: TextView): bool
proc redoText*(textView: TextView): bool
proc deleteBackwardText*(textView: TextView)
proc deleteForwardText*(textView: TextView)
proc deleteWordBackwardText*(textView: TextView)
proc deleteWordForwardText*(textView: TextView)
proc deleteToBeginningOfLineText*(textView: TextView)
proc deleteToEndOfLineText*(textView: TextView)
proc insertLineBreakText*(textView: TextView)
proc insertParagraphSeparatorText*(textView: TextView)
proc moveLeftText*(textView: TextView, extending = false)
proc moveRightText*(textView: TextView, extending = false)
proc moveUpText*(textView: TextView, extending = false)
proc moveDownText*(textView: TextView, extending = false)
proc moveWordLeftText*(textView: TextView, extending = false)
proc moveWordRightText*(textView: TextView, extending = false)
proc moveToBeginningOfLineText*(textView: TextView, extending = false)
proc moveToEndOfLineText*(textView: TextView, extending = false)
proc moveToBeginningOfDocumentText*(textView: TextView, extending = false)
proc moveToEndOfDocumentText*(textView: TextView, extending = false)
proc attributedSubstringForRange*(
  textView: TextView, range: TextRange
): AttributedString

proc validAttributesForMarkedText*(textView: TextView): seq[string]
proc firstRectForCharacterRange*(textView: TextView, range: TextRange): Rect
proc characterIndexForPoint*(textView: TextView, point: Point): int
proc performTextInputCommand*(
  textView: TextView, selector: CommandSelector, sender: DynamicAgent = nil
): bool

proc textIndexAtPoint*(textView: TextView, point: Point): int
proc selectionRects*(textView: TextView, range: TextRange): seq[Rect]
proc characterRect*(textView: TextView, index: int): Rect
proc lineRange*(textView: TextView, line: int): TextRange
proc lineForIndex*(textView: TextView, index: int): int
proc lineBounds*(textView: TextView, line: int): Rect
proc selectedRanges*(textView: TextView): seq[TextRange]
proc beginEditing*(textView: TextView): bool
proc endEditing*(textView: TextView)
proc shouldChangeText(
  textView: TextView, range: TextRange, replacement: TextStorage
): bool

proc finishTextMutation(
  textView: TextView, changedRange: TextRange, valueChanged = true
)

func toAccessibilityTextRange(range: TextRange): AccessibilityTextRange =
  initAccessibilityTextRange(int(range.location), int(range.length))

func toTextRange(range: AccessibilityTextRange): TextRange =
  initTextRange(int(range.location), int(range.length))

protocol TextViewEvents:
  proc textWillChange*(textView: TextView, range: TextRange) {.signal.}
  proc textDidChange*(textView: TextView, sender: DynamicAgent) {.signal.}
  proc textSelectionDidChange*(textView: TextView, ranges: seq[TextRange]) {.signal.}
  proc textCommandDispatched*(
    textView: TextView, selector: CommandSelector, handled: bool
  ) {.signal.}

  proc textEditingDidBegin*(textView: TextView) {.signal.}
  proc textEditingDidEnd*(textView: TextView) {.signal.}

protocol TextViewDelegateProtocol:
  method tvShouldBeginEdit*(textView: TextView): bool {.optional.}
  method tvDidBeginEdit*(textView: TextView) {.optional.}
  method tvDidEndEdit*(textView: TextView) {.optional.}
  method tvShouldChange*(
    textView: TextView, range: TextRange, replacement: TextStorage
  ): bool {.optional.}

  method tvDidChange*(textView: TextView, range: TextRange) {.optional.}
  method tvSelectionChanged*(textView: TextView, ranges: seq[TextRange]) {.optional.}

  method tvClickedLink*(
    textView: TextView, link: string, range: TextRange
  ): bool {.optional.}

  method tvClickedAttachment*(
    textView: TextView, attachment: TextAttachment, range: TextRange
  ): bool {.optional.}

  method tvCompletions*(
    textView: TextView, prefix: string, range: TextRange
  ): seq[string] {.optional.}

  method tvValidateCommand*(
    textView: TextView, action: ActionSelector
  ): bool {.optional.}

  method tvPerformService*(
    textView: TextView, request: TextServiceRequest
  ): TextServiceResponse {.optional.}

  method tvAttachmentView*(
    textView: TextView, attachment: TextAttachment, range: TextRange, frame: Rect
  ): View {.optional.}

  method tvAttachmentCell*(
    textView: TextView, attachment: TextAttachment, range: TextRange, frame: Rect
  ): TextAttachmentCell {.optional.}

protocol TextViewCheckingProtocol:
  method tvCheckingResults*(
    textView: TextView, range: TextRange
  ): seq[TextCheckingResult] {.optional.}

  method tvDataDetections*(
    textView: TextView, range: TextRange
  ): seq[TextCheckingResult] {.optional.}

proc dispatchSelectionChanged(textView: TextView, before: seq[TextRange]) =
  if textView.isNil:
    return
  let after = textView.selectedRanges()
  if after == before:
    return
  emit textView.textSelectionDidChange(after)
  if not textView.xDelegate.isNil:
    discard textView.xDelegate.trySendLocal(
      tvSelectionChanged(), (textView: textView, ranges: after)
    )
  textView.postAccessibilityNotification(anSelectionChanged)

proc postSelectionChanged(textView: TextView, before: TextRange) =
  textView.dispatchSelectionChanged(@[before])

proc showInsertionPoint(textView: TextView) =
  if textView.xInsertionPointVisible:
    return
  textView.xInsertionPointVisible = true
  textView.setNeedsDisplay(true)

proc isControlInput(rune: Rune): bool =
  let code = rune.int
  code < 32 or (code >= 127 and code <= 159)

proc isInsertableText*(text: string): bool =
  if text.len == 0:
    return false
  for rune in text.runes:
    if rune.isControlInput:
      return false
  true

proc shouldInsertText(event: KeyEvent): bool =
  if event.modifiers - {kmShift} != {}:
    return false
  event.text.isInsertableText()

proc clampIndex(total, index: int): int {.inline.} =
  max(0, min(index, total))

const ValidMarkedTextAttributes* = [
  "foregroundColor", "fontName", "fontSize", "language", "paragraphStyle",
  "baselineOffset", "kerning", "ligatureLevel", "expansion", "backgroundColor",
  "shadow", "link", "underlineStyle", "strikethroughStyle", "attachment", "underline",
  "strikethrough",
]

proc initTextCheckingResult*(
    kind: TextCheckingKind,
    range: TextRange,
    message = "",
    replacement = "",
    link = "",
    attributes = defaultTextAttributes(),
): TextCheckingResult =
  TextCheckingResult(
    kind: kind,
    range: range,
    message: message,
    replacement: replacement,
    link: link,
    attributes: attributes,
  )

proc runesOf(text: string): seq[Rune] =
  for rune in text.runes:
    result.add rune

func isWordRune(rune: Rune): bool =
  let code = rune.int
  (code >= int('a') and code <= int('z')) or (code >= int('A') and code <= int('Z')) or
    (code >= int('0') and code <= int('9')) or code == int('_')

proc previousWordBoundary(text: string, index: int): int =
  let runes = text.runesOf()
  result = clampIndex(runes.len, index)
  while result > 0 and runes[result - 1].isWhiteSpace:
    dec result
  while result > 0 and not runes[result - 1].isWhiteSpace:
    dec result

proc nextWordBoundary(text: string, index: int): int =
  let runes = text.runesOf()
  result = clampIndex(runes.len, index)
  while result < runes.len and runes[result].isWhiteSpace:
    inc result
  while result < runes.len and not runes[result].isWhiteSpace:
    inc result

proc wordRangeAt(text: string, index: int): TextRange =
  let runes = text.runesOf()
  if runes.len == 0:
    return initTextRange(0, 0)
  var
    start = clampIndex(runes.len, index)
    stop = start
  if start == runes.len and start > 0:
    dec start
    stop = runes.len
  while start > 0 and runes[start - 1].isWordRune:
    dec start
  while stop < runes.len and runes[stop].isWordRune:
    inc stop
  initTextRange(start, stop - start)

proc lineRangeAtIndex(textView: TextView, index: int): TextRange =
  let line = textView.lineForIndex(index)
  textView.lineRange(line)

proc paragraphRangeAtIndex(textView: TextView, index: int): TextRange =
  textView.xTextStorage.paragraphRangeForRange(initTextRange(index, 0))

proc selectionRangeForGranularity(
    textView: TextView, index: int, granularity: TextSelectionGranularity
): TextRange =
  case granularity
  of tsgCharacter:
    initTextRange(index, 0)
  of tsgWord:
    textView.textViewStringValue().wordRangeAt(index)
  of tsgLine:
    textView.lineRangeAtIndex(index)
  of tsgParagraph:
    textView.paragraphRangeAtIndex(index)
  of tsgDocument:
    initTextRange(0, textView.xTextStorage.len)

proc textStorage*(textView: TextView): TextStorage =
  textView.xTextStorage

proc `textStorage=`*(textView: TextView, storage: TextStorage) =
  let
    previousValue = textView.textViewStringValue()
    previousSelection = textView.textViewSelectedRange()
  textView.xTextStorage =
    if storage.isNil:
      newTextStorage()
    else:
      storage
  textView.syncLayout()
  let total = textView.xTextStorage.len
  textView.xInsertionPoint = clampIndex(total, textView.xInsertionPoint)
  textView.xSelectionAnchor = clampIndex(total, textView.xSelectionAnchor)
  let
    selectionStart = min(textView.xSelectionAnchor, textView.xInsertionPoint)
    selectionStop = max(textView.xSelectionAnchor, textView.xInsertionPoint)
  textView.xSelectedRanges =
    @[initTextRange(selectionStart, selectionStop - selectionStart)]
  textView.clearMarkedText()
  textView.invalidateIntrinsicContentSize()
  textView.setNeedsDisplay(true)
  if textView.textViewStringValue() != previousValue:
    textView.postAccessibilityNotification(anValueChanged)
  textView.postSelectionChanged(previousSelection)

proc layoutManager*(textView: TextView): TextLayoutManager =
  textView.xLayoutManager

proc textContainer*(textView: TextView): TextContainer =
  textView.xTextContainer

proc `textContainer=`*(textView: TextView, container: TextContainer) =
  textView.xTextContainer = container
  textView.syncLayout()
  textView.setNeedsDisplay(true)

proc textViewStringValue(textView: TextView): string =
  textView.xTextStorage.stringValue()

proc setTextViewStringValue(textView: TextView, value: string) =
  let previousValue = textView.textViewStringValue()
  if previousValue == value:
    return
  let
    previousRanges = textView.selectedRanges()
    replacement = newTextStorage(value, textView.xTypingAttributes)
    changedRange = initTextRange(0, previousValue.runeLen)
  if not textView.shouldChangeText(changedRange, replacement):
    return
  emit textView.textWillChange(changedRange)
  textView.xTextStorage.stringValue = value
  let total = textView.xTextStorage.len
  textView.xInsertionPoint = total
  textView.xSelectionAnchor = total
  textView.xSelectedRanges = @[initTextRange(total, 0)]
  textView.showInsertionPoint()
  textView.clearMarkedText()
  textView.finishTextMutation(initTextRange(0, total))
  textView.dispatchSelectionChanged(previousRanges)

proc editable*(textView: TextView): bool =
  tvEditable in textView.xFlags

proc `editable=`*(textView: TextView, editable: bool) =
  if editable == textView.editable:
    return
  if editable:
    textView.xFlags.incl tvEditable
  else:
    textView.xFlags.excl tvEditable
  textView.setAcceptsFirstResponder(
    tvEditable in textView.xFlags or tvSelectable in textView.xFlags
  )

proc selectable*(textView: TextView): bool =
  tvSelectable in textView.xFlags

proc `selectable=`*(textView: TextView, selectable: bool) =
  if selectable == textView.selectable:
    return
  if selectable:
    textView.xFlags.incl tvSelectable
  else:
    textView.xFlags.excl tvSelectable
  textView.setAcceptsFirstResponder(
    tvEditable in textView.xFlags or tvSelectable in textView.xFlags
  )

proc richText*(textView: TextView): bool =
  tvRichText in textView.xFlags

proc `richText=`*(textView: TextView, richText: bool) =
  if richText == textView.richText:
    return
  if richText:
    textView.xFlags.incl tvRichText
  else:
    textView.xFlags.excl tvRichText

proc isFieldEditor*(textView: TextView): bool =
  tvFieldEditor in textView.xFlags

proc `fieldEditor=`*(textView: TextView, fieldEditor: bool) =
  if fieldEditor == textView.isFieldEditor:
    return
  if fieldEditor:
    textView.xFlags.incl tvFieldEditor
  else:
    textView.xFlags.excl tvFieldEditor

proc allowsUndo*(textView: TextView): bool =
  tvAllowsUndo in textView.xFlags

proc `allowsUndo=`*(textView: TextView, allowsUndo: bool) =
  if allowsUndo == textView.allowsUndo:
    return
  if allowsUndo:
    textView.xFlags.incl tvAllowsUndo
  else:
    textView.xFlags.excl tvAllowsUndo
    textView.xUndoStack.setLen(0)
    textView.xRedoStack.setLen(0)

proc delegate*(textView: TextView): DynamicAgent =
  textView.xDelegate

proc `delegate=`*(textView: TextView, delegate: DynamicAgent) =
  textView.xDelegate = delegate

proc textChecker*(textView: TextView): DynamicAgent =
  textView.xTextChecker

proc `textChecker=`*(textView: TextView, checker: DynamicAgent) =
  textView.xTextChecker = checker

proc alignment*(textView: TextView): TextAlignment =
  textView.xAlignment

proc `alignment=`*(textView: TextView, alignment: TextAlignment) =
  if textView.xAlignment == alignment:
    return
  textView.xAlignment = alignment
  textView.syncLayout()
  textView.setNeedsDisplay(true)

proc textColor*(textView: TextView): Color =
  if textView.xTextColor.a > 0.0:
    textView.xTextColor
  else:
    textView
    .effectiveAppearance()
    .resolveTextFieldStyle(
      controlStyle(
        if textView.isFieldEditor: srTextField else: srTextView,
        textView.widgetStateSet(),
        id = textView.styleId,
        classes = textView.styleClasses,
      )
    ).text.color

proc textStyle(textView: TextView): TextStyle =
  if textView.isNil:
    return initAppearance().resolveTextStyle(
        controlStyle(srTextView), color(0.08, 0.09, 0.11), insets(0.0)
      )
  if textView.xHasTextStyleOverride:
    result = textView.xTextStyleOverride
    if textView.xTextColor.a > 0.0:
      result.color = textView.xTextColor
    return
  let role = if textView.isFieldEditor: srTextField else: srTextView
  result = textView.effectiveAppearance().resolveTextStyle(
      controlStyle(
        role,
        textView.widgetStateSet(),
        id = textView.styleId,
        classes = textView.styleClasses,
      ),
      color(0.08, 0.09, 0.11),
      insets(0.0),
    )
  if textView.xTextColor.a > 0.0:
    result.color = textView.xTextColor

proc setTextStyleOverride*(textView: TextView, style: TextStyle) =
  textView.xTextStyleOverride = style
  textView.xHasTextStyleOverride = true
  textView.xTypingAttributes =
    defaultTextAttributes(style.color, style.fontSize, style.fontName, style.language)
  textView.syncLayout()
  textView.setNeedsDisplay(true)

proc clearTextStyleOverride*(textView: TextView) =
  if not textView.xHasTextStyleOverride:
    return
  textView.xHasTextStyleOverride = false
  let style = textView.textStyle()
  textView.xTypingAttributes =
    defaultTextAttributes(style.color, style.fontSize, style.fontName, style.language)
  textView.syncLayout()
  textView.setNeedsDisplay(true)

proc `textColor=`*(textView: TextView, color: Color) =
  if textView.xTextColor == color:
    return
  textView.xTextColor = color
  let style = textView.textStyle()
  textView.xTypingAttributes =
    defaultTextAttributes(style.color, style.fontSize, style.fontName, style.language)
  textView.setNeedsDisplay(true)

proc selectionColor*(textView: TextView): Color =
  textView.xSelectionColor

proc `selectionColor=`*(textView: TextView, color: Color) =
  if textView.xSelectionColor == color:
    return
  textView.xSelectionColor = color
  textView.setNeedsDisplay(true)

proc selectedTextAttributes*(textView: TextView): TextAttributes =
  if not textView.xHasSelectedTextAttributes:
    defaultTextAttributes(color(1.0, 1.0, 1.0, 1.0))
  else:
    textView.xSelectedTextAttributes

proc `selectedTextAttributes=`*(textView: TextView, attributes: TextAttributes) =
  textView.xSelectedTextAttributes = attributes
  textView.xHasSelectedTextAttributes = true
  textView.setNeedsDisplay(true)

proc clearSelectedTextAttributes*(textView: TextView) =
  textView.xHasSelectedTextAttributes = false
  textView.setNeedsDisplay(true)

proc typingAttributes*(textView: TextView): TextAttributes =
  textView.xTypingAttributes

proc `typingAttributes=`*(textView: TextView, attributes: TextAttributes) =
  if textView.xTypingAttributes == attributes:
    return
  textView.xTypingAttributes = attributes

proc insertionPointColor*(textView: TextView): Color =
  if textView.xInsertionPointColor.a > 0.0:
    textView.xInsertionPointColor
  else:
    textView.textColor()

proc `insertionPointColor=`*(textView: TextView, color: Color) =
  if textView.xInsertionPointColor == color:
    return
  textView.xInsertionPointColor = color
  textView.setNeedsDisplay(true)

proc insertionPointVisible*(textView: TextView): bool =
  textView.xInsertionPointVisible

proc `insertionPointVisible=`*(textView: TextView, visible: bool) =
  if textView.xInsertionPointVisible == visible:
    return
  textView.xInsertionPointVisible = visible
  textView.setNeedsDisplay(true)

proc insertionPointBlinkPeriod*(textView: TextView): float32 =
  textView.xInsertionPointBlinkPeriod

proc `insertionPointBlinkPeriod=`*(textView: TextView, period: float32) =
  textView.xInsertionPointBlinkPeriod = max(period, 0.0'f32)

proc markedTextAttributes*(textView: TextView): TextAttributes =
  textView.xMarkedTextAttributes

proc `markedTextAttributes=`*(textView: TextView, attributes: TextAttributes) =
  if textView.xMarkedTextAttributes == attributes:
    return
  textView.xMarkedTextAttributes = attributes
  textView.setNeedsDisplay(true)

proc selectionAffinity*(textView: TextView): TextAffinity =
  textView.xSelectionAffinity

proc `selectionAffinity=`*(textView: TextView, affinity: TextAffinity) =
  textView.xSelectionAffinity = affinity

proc selectionGranularity*(textView: TextView): TextSelectionGranularity =
  textView.xSelectionGranularity

proc `selectionGranularity=`*(
    textView: TextView, granularity: TextSelectionGranularity
) =
  if textView.xSelectionGranularity == granularity:
    return
  textView.xSelectionGranularity = granularity

proc allowsMultipleSelectedRanges*(textView: TextView): bool =
  textView.xAllowsMultipleSelectedRanges

proc `allowsMultipleSelectedRanges=`*(textView: TextView, value: bool) =
  if textView.xAllowsMultipleSelectedRanges == value:
    return
  textView.xAllowsMultipleSelectedRanges = value
  if not value and textView.xSelectedRanges.len > 1:
    textView.setTextViewSelectedRange(textView.xSelectedRanges[0])

proc allowsRectangularSelection*(textView: TextView): bool =
  textView.xAllowsRectangularSelection

proc `allowsRectangularSelection=`*(textView: TextView, value: bool) =
  textView.xAllowsRectangularSelection = value
  if not value:
    textView.xRectangularSelection = TextRectSelection()

proc rectangularSelection*(textView: TextView): TextRectSelection =
  textView.xRectangularSelection

proc findIndicators*(textView: TextView): seq[TextFindIndicator] =
  textView.xFindIndicators

proc checkingResults*(textView: TextView): seq[TextCheckingResult] =
  textView.xCheckingResults

proc completionPanel*(textView: TextView): TextCompletionPanel =
  textView.xCompletionPanel

proc substitutionOptions*(textView: TextView): TextSubstitutionOptions =
  textView.xSubstitutionOptions

proc `substitutionOptions=`*(textView: TextView, options: TextSubstitutionOptions) =
  textView.xSubstitutionOptions = options

proc smartInsertDeleteEnabled*(textView: TextView): bool =
  textView.xSmartInsertDelete

proc `smartInsertDeleteEnabled=`*(textView: TextView, enabled: bool) =
  textView.xSmartInsertDelete = enabled

proc defaultParagraphStyle*(textView: TextView): TextParagraphStyle =
  textView.xDefaultParagraphStyle

proc `defaultParagraphStyle=`*(textView: TextView, style: TextParagraphStyle) =
  textView.xDefaultParagraphStyle = style
  textView.xTypingAttributes.paragraphStyle = style

proc usesRuler*(textView: TextView): bool =
  textView.xUsesRuler

proc `usesRuler=`*(textView: TextView, value: bool) =
  textView.xUsesRuler = value
  if not value:
    textView.xRulerVisible = false

proc rulerVisible*(textView: TextView): bool =
  textView.xUsesRuler and textView.xRulerVisible

proc `rulerVisible=`*(textView: TextView, value: bool) =
  textView.xRulerVisible = value and textView.xUsesRuler

proc hasMarkedText*(textView: TextView): bool =
  textView.xHasMarkedText

proc markedRange*(textView: TextView): TextRange =
  if textView.hasMarkedText:
    textView.xMarkedRange
  else:
    initTextRange(0, 0)

proc attributedSubstringForRange*(
    textView: TextView, range: TextRange
): AttributedString =
  if textView.xTextStorage.isNil:
    return newTextStorage()
  textView.xTextStorage.sliceTextStorage(textView.clampedRange(range))

proc validAttributesForMarkedText*(textView: TextView): seq[string] =
  discard textView
  @ValidMarkedTextAttributes

proc firstRectForCharacterRange*(textView: TextView, range: TextRange): Rect =
  let clamped = textView.clampedRange(range)
  if clamped.length > 0:
    let rects = textView.selectionRects(clamped)
    if rects.len > 0:
      return textView.rectToWindow(rects[0])
  textView.rectToWindow(textView.characterRect(int(clamped.location)))

proc characterIndexForPoint*(textView: TextView, point: Point): int =
  textView.textIndexAtPoint(textView.pointFromWindow(point))

proc textViewInsertionPoint(textView: TextView): int =
  textView.xInsertionPoint

proc textViewSelectionAnchor(textView: TextView): int =
  textView.xSelectionAnchor

proc updateTypingAttributesForSelection(textView: TextView) =
  if textView.xTextStorage.len == 0:
    return
  let
    total = textView.xTextStorage.len
    anchor = clampIndex(total, textView.xSelectionAnchor)
    cursor = clampIndex(total, textView.xInsertionPoint)
    selectedStart = min(anchor, cursor)
    index =
      if anchor == cursor and cursor > 0:
        min(cursor - 1, total - 1)
      else:
        max(0, min(selectedStart, total - 1))
  textView.xTypingAttributes = textView.xTextStorage.attributesAt(index)

proc textViewSelectedRange(textView: TextView): TextRange =
  if textView.xSelectedRanges.len > 0:
    return textView.xSelectedRanges[0]
  let
    start = min(textView.xSelectionAnchor, textView.xInsertionPoint)
    stop = max(textView.xSelectionAnchor, textView.xInsertionPoint)
  initTextRange(start, stop - start)

proc normalizedSelectedRanges(
    textView: TextView, ranges: openArray[TextRange]
): seq[TextRange] =
  for range in ranges:
    result.add textView.clampedRange(range)
    if not textView.xAllowsMultipleSelectedRanges:
      break
  if result.len == 0:
    result.add initTextRange(textView.xInsertionPoint, 0)

proc setTextViewSelectedRange(textView: TextView, value: TextRange) =
  let previousRanges = textView.selectedRanges()
  let
    total = textView.xTextStorage.len
    start = max(0, min(int(value.location), total))
    length = max(0, min(int(value.length), total - start))
    clamped = initTextRange(start, length)
  textView.xSelectionAnchor = start
  textView.xInsertionPoint = start + length
  textView.xSelectedRanges = @[clamped]
  textView.updateTypingAttributesForSelection()
  textView.showInsertionPoint()
  textView.setNeedsDisplay(true)
  textView.dispatchSelectionChanged(previousRanges)

proc stringValue*(textView: TextView): string =
  textView.textViewStringValue()

proc `stringValue=`*(textView: TextView, value: string) =
  textView.setTextViewStringValue(value)

proc setStringValue*(textView: TextView, value: string) =
  textView.setTextViewStringValue(value)

proc selectedRange*(textView: TextView): TextRange =
  textView.textViewSelectedRange()

proc `selectedRange=`*(textView: TextView, value: TextRange) =
  textView.setTextViewSelectedRange(value)

proc setSelectedRange*(textView: TextView, value: TextRange) =
  textView.setTextViewSelectedRange(value)

proc selectedRanges*(textView: TextView): seq[TextRange] =
  if textView.xSelectedRanges.len == 0:
    @[textView.textViewSelectedRange()]
  else:
    textView.xSelectedRanges

proc setSelectedRanges*(textView: TextView, ranges: openArray[TextRange]) =
  let nextRanges = textView.normalizedSelectedRanges(ranges)
  if nextRanges.len == 0:
    return
  let previousRanges = textView.selectedRanges()
  textView.xSelectedRanges = nextRanges
  textView.xSelectionAnchor = int(nextRanges[0].location)
  textView.xInsertionPoint = nextRanges[0].maxIndex
  textView.updateTypingAttributesForSelection()
  textView.showInsertionPoint()
  textView.setNeedsDisplay(true)
  textView.dispatchSelectionChanged(previousRanges)

proc `selectedRanges=`*(textView: TextView, ranges: seq[TextRange]) =
  textView.setSelectedRanges(ranges)

proc selectRange*(textView: TextView, index: int, granularity = tsgCharacter) =
  textView.setTextViewSelectedRange(
    textView.selectionRangeForGranularity(index, granularity)
  )

proc setRectangularSelection*(
    textView: TextView, anchor, focus: Point
): TextRectSelection =
  if not textView.xAllowsRectangularSelection:
    return TextRectSelection()
  let
    x0 = min(anchor.x, focus.x)
    y0 = min(anchor.y, focus.y)
    x1 = max(anchor.x, focus.x)
    y1 = max(anchor.y, focus.y)
    bounds = rect(x0, y0, x1 - x0, y1 - y0)
  var ranges: seq[TextRange]
  textView.updateTextContainer()
  for fragment in textView.xLayoutManager.lineFragments():
    if fragment.fragmentRect.intersection(bounds).isEmpty:
      discard
    else:
      ranges.add fragment.textRange
  textView.xRectangularSelection =
    TextRectSelection(anchor: anchor, focus: focus, bounds: bounds, ranges: ranges)
  if ranges.len > 0:
    textView.setSelectedRanges(ranges)
  textView.xRectangularSelection

proc insertionPoint*(textView: TextView): int =
  textView.textViewInsertionPoint()

proc selectionAnchor*(textView: TextView): int =
  textView.textViewSelectionAnchor()

proc currentSelection(textView: TextView): tuple[start, stop: int] =
  let
    total = textView.xTextStorage.len
    anchor = clampIndex(total, textView.xSelectionAnchor)
    cursor = clampIndex(total, textView.xInsertionPoint)
  result.start = min(anchor, cursor)
  result.stop = max(anchor, cursor)

proc clampedRange(textView: TextView, range: TextRange): TextRange =
  let
    total = textView.xTextStorage.len
    start = clampIndex(total, int(range.location))
    length = max(0, min(int(range.length), total - start))
  initTextRange(start, length)

proc setSelection(textView: TextView, range: TextRange) =
  let previousRanges = textView.selectedRanges()
  let clamped = textView.clampedRange(range)
  textView.xSelectionAnchor = int(clamped.location)
  textView.xInsertionPoint = clamped.maxIndex
  textView.xSelectedRanges = @[clamped]
  textView.updateTypingAttributesForSelection()
  textView.showInsertionPoint()
  textView.dispatchSelectionChanged(previousRanges)

proc clearMarkedText(textView: TextView) =
  textView.xHasMarkedText = false
  textView.xMarkedRange = initTextRange(0, 0)
  textView.xMarkedUndoStorage = nil
  textView.xMarkedUndoSelection = initTextRange(0, 0)

proc recordUndo(
    textView: TextView,
    before: TextStorage,
    beforeSelection: TextRange,
    afterSelection: TextRange,
) =
  if textView.xApplyingUndo or not textView.allowsUndo:
    return
  if textView.xUndoGroupingDepth > 0:
    if not textView.xHasGroupedUndo:
      textView.xGroupedUndoBefore = before.copyTextStorage()
      textView.xGroupedUndoSelection = beforeSelection
      textView.xHasGroupedUndo = true
    return
  let after = textView.xTextStorage.copyTextStorage()
  if before.stringValue() == after.stringValue() and beforeSelection == afterSelection:
    return
  textView.xUndoStack.add TextUndoRecord(
    storageBefore: before,
    storageAfter: after,
    selectionBefore: beforeSelection,
    selectionAfter: afterSelection,
  )
  textView.xRedoStack.setLen(0)

proc beginUndoGrouping*(textView: TextView) =
  inc textView.xUndoGroupingDepth

proc endUndoGrouping*(textView: TextView) =
  if textView.xUndoGroupingDepth == 0:
    return
  dec textView.xUndoGroupingDepth
  if textView.xUndoGroupingDepth > 0 or not textView.xHasGroupedUndo:
    return
  let
    before = textView.xGroupedUndoBefore
    beforeSelection = textView.xGroupedUndoSelection
    afterSelection = textView.textViewSelectedRange()
  textView.xHasGroupedUndo = false
  textView.xGroupedUndoBefore = nil
  textView.recordUndo(before, beforeSelection, afterSelection)

proc beginEditing*(textView: TextView): bool =
  if textView.xEditing:
    return true
  if not textView.xDelegate.isNil:
    let shouldBegin =
      textView.xDelegate.trySendLocal(tvShouldBeginEdit(), textView).get(true)
    if not shouldBegin:
      return false
  textView.xEditing = true
  emit textView.textEditingDidBegin()
  if not textView.xDelegate.isNil:
    discard textView.xDelegate.trySendLocal(tvDidBeginEdit(), textView)
  true

proc endEditing*(textView: TextView) =
  if not textView.xEditing:
    return
  textView.xEditing = false
  emit textView.textEditingDidEnd()
  if not textView.xDelegate.isNil:
    discard textView.xDelegate.trySendLocal(tvDidEndEdit(), textView)

proc shouldChangeText(
    textView: TextView, range: TextRange, replacement: TextStorage
): bool =
  if not textView.beginEditing():
    return false
  if textView.xDelegate.isNil:
    return true

  textView.xDelegate
  .trySendLocal(
    tvShouldChange(), (textView: textView, range: range, replacement: replacement)
  )
  .get(true)

proc finishTextMutation(
    textView: TextView, changedRange: TextRange, valueChanged: bool
) =
  textView.syncLayout()
  textView.invalidateIntrinsicContentSize()
  textView.setNeedsDisplay(true)
  if not textView.xDelegate.isNil:
    discard textView.xDelegate.trySendLocal(
      tvDidChange(), (textView: textView, range: changedRange)
    )
  emit textView.textDidChange(DynamicAgent(textView))
  if valueChanged:
    textView.postAccessibilityNotification(anValueChanged)

proc replaceRange(
    textView: TextView,
    range: TextRange,
    inserted: TextStorage,
    record = true,
    clearMark = true,
) =
  if not textView.editable:
    return
  let
    before = textView.xTextStorage.copyTextStorage()
    beforeValue = before.stringValue()
    beforeSelection = textView.textViewSelectedRange()
    clamped = textView.clampedRange(range)
    insertedLength = inserted.len
    nextSelection = initTextRange(int(clamped.location) + insertedLength, 0)

  if not textView.shouldChangeText(clamped, inserted):
    return
  emit textView.textWillChange(clamped)
  textView.xTextStorage.replace(clamped, inserted)
  if clearMark:
    textView.clearMarkedText()
  textView.setSelection(nextSelection)
  textView.finishTextMutation(
    initTextRange(int(clamped.location), insertedLength),
    textView.textViewStringValue() != beforeValue,
  )
  if record:
    textView.recordUndo(before, beforeSelection, textView.textViewSelectedRange())

proc replaceRange(
    textView: TextView,
    range: TextRange,
    insertion: string,
    attributes: TextAttributes,
    record = true,
    clearMark = true,
) =
  textView.replaceRange(
    range, newTextStorage(insertion, attributes), record = record, clearMark = clearMark
  )

proc runeString(runes: openArray[Rune], start, stop: int): string =
  let
    first = max(0, min(start, runes.len))
    last = max(first, min(stop, runes.len))
  for index in first ..< last:
    result.add runes[index].toUTF8()

func foldedRune(rune: Rune): string =
  rune.toUTF8().toLowerAscii()

proc runesMatchAt(
    haystack, needle: openArray[Rune], index: int, caseSensitive: bool
): bool =
  if needle.len == 0 or index < 0 or index + needle.len > haystack.len:
    return false
  for offset in 0 ..< needle.len:
    if caseSensitive:
      if haystack[index + offset] != needle[offset]:
        return false
    elif haystack[index + offset].foldedRune() != needle[offset].foldedRune():
      return false
  true

proc textStartsWithAt(runes: openArray[Rune], index: int, prefix: string): bool =
  let prefixRunes = prefix.runesOf()
  runes.runesMatchAt(prefixRunes, index, caseSensitive = true)

proc applyTextSubstitutions(textView: TextView, insertion: string): string =
  result = insertion
  if tsoSmartDashes in textView.xSubstitutionOptions:
    result = result.replace("--", "\226\128\148")
  if tsoSmartQuotes in textView.xSubstitutionOptions:
    var
      converted = ""
      openDoubleQuote = true
    for rune in result.runes:
      case rune
      of Rune('"'):
        if openDoubleQuote:
          converted.add "\226\128\156"
        else:
          converted.add "\226\128\157"
        openDoubleQuote = not openDoubleQuote
      of Rune('\''):
        converted.add "\226\128\153"
      else:
        converted.add rune.toUTF8()
    result = converted

proc applySmartInsert(
    textView: TextView, selected: TextRange, insertion: string
): string =
  result = insertion
  if not textView.xSmartInsertDelete or insertion.len == 0:
    return
  let insertedRunes = insertion.runesOf()
  if insertedRunes.len == 0:
    return
  let
    textRunes = textView.textViewStringValue().runesOf()
    start = int(selected.location)
    stop = selected.maxIndex
  var
    prefix = ""
    suffix = ""
  if start > 0 and start <= textRunes.len and textRunes[start - 1].isWordRune and
      insertedRunes[0].isWordRune:
    prefix = " "
  if stop < textRunes.len and insertedRunes[^1].isWordRune and textRunes[stop].isWordRune:
    suffix = " "
  result = prefix & insertion & suffix

proc preparedInsertion(
    textView: TextView, selected: TextRange, insertion: string
): string =
  textView.applySmartInsert(selected, textView.applyTextSubstitutions(insertion))

proc setFindIndicators*(
    textView: TextView,
    ranges: openArray[TextRange],
    color = color(1.0, 0.82, 0.24, 0.45),
) =
  textView.xFindIndicators.setLen(0)
  for range in ranges:
    let clamped = textView.clampedRange(range)
    if clamped.length > 0:
      textView.xFindIndicators.add TextFindIndicator(
        range: clamped,
        rects: textView.selectionRects(clamped),
        color: color,
        visible: true,
      )
  textView.setNeedsDisplay(true)

proc clearFindIndicators*(textView: TextView) =
  if textView.xFindIndicators.len == 0:
    return
  textView.xFindIndicators.setLen(0)
  textView.setNeedsDisplay(true)

proc findTextRanges*(
    textView: TextView, needle: string, caseSensitive = true
): seq[TextRange] =
  if needle.len == 0:
    return
  let
    haystack = textView.textViewStringValue().runesOf()
    needleRunes = needle.runesOf()
  if needleRunes.len == 0 or needleRunes.len > haystack.len:
    return
  var index = 0
  while index + needleRunes.len <= haystack.len:
    if haystack.runesMatchAt(needleRunes, index, caseSensitive):
      result.add initTextRange(index, needleRunes.len)
      index += max(needleRunes.len, 1)
    else:
      inc index

proc showFindIndicators*(
    textView: TextView, needle: string, caseSensitive = true
): seq[TextRange] =
  result = textView.findTextRanges(needle, caseSensitive)
  textView.setFindIndicators(result)

proc replaceFirstText*(
    textView: TextView, needle, replacement: string, caseSensitive = true
): bool =
  if not textView.editable:
    return false
  let ranges = textView.findTextRanges(needle, caseSensitive)
  if ranges.len == 0:
    return false
  textView.replaceRange(ranges[0], replacement, textView.xTypingAttributes)
  true

proc replaceAllText*(
    textView: TextView, needle, replacement: string, caseSensitive = true
): int =
  if not textView.editable:
    return 0
  let ranges = textView.findTextRanges(needle, caseSensitive)
  if ranges.len == 0:
    return 0
  textView.beginUndoGrouping()
  for index in countdown(ranges.len - 1, 0):
    let before = textView.textViewStringValue()
    textView.replaceRange(ranges[index], replacement, textView.xTypingAttributes)
    if textView.textViewStringValue() != before:
      inc result
  textView.endUndoGrouping()

proc detectUrlRanges(textView: TextView, range: TextRange): seq[TextCheckingResult] =
  let
    clamped = textView.clampedRange(range)
    source = textView.xTextStorage.substring(clamped)
    runes = source.runesOf()
  var index = 0
  while index < runes.len:
    if runes.textStartsWithAt(index, "http://") or
        runes.textStartsWithAt(index, "https://"):
      let start = index
      while index < runes.len and not runes[index].isWhiteSpace:
        inc index
      let link = runes.runeString(start, index)
      result.add initTextCheckingResult(
        tckLink,
        initTextRange(int(clamped.location) + start, index - start),
        link = link,
      )
    else:
      inc index

proc checkText*(textView: TextView, range: TextRange): seq[TextCheckingResult] =
  let clamped = textView.clampedRange(range)
  if not textView.xTextChecker.isNil:
    result.add textView.xTextChecker
    .trySendLocal(tvCheckingResults(), (textView: textView, range: clamped))
    .get(@[])
  if tsoDataDetection in textView.xSubstitutionOptions:
    result.add textView.detectUrlRanges(clamped)
  if not textView.xTextChecker.isNil:
    result.add textView.xTextChecker
    .trySendLocal(tvDataDetections(), (textView: textView, range: clamped))
    .get(@[])
  textView.xCheckingResults = result

proc checkText*(textView: TextView): seq[TextCheckingResult] =
  textView.checkText(initTextRange(0, textView.xTextStorage.len))

proc clearTextCheckingResults*(textView: TextView) =
  if textView.xCheckingResults.len == 0:
    return
  textView.xCheckingResults.setLen(0)
  textView.setNeedsDisplay(true)

proc applyTextCheckingResults*(
    textView: TextView, results: openArray[TextCheckingResult]
) =
  if textView.xTextStorage.isNil:
    return
  textView.xTextStorage.beginEditing()
  for checking in results:
    let clamped = textView.clampedRange(checking.range)
    if clamped.length > 0:
      var attributes = textView.xTextStorage.attributesAt(int(clamped.location))
      if checking.attributes != defaultTextAttributes():
        attributes = checking.attributes
      else:
        case checking.kind
        of tckSpelling:
          attributes.underline = true
          attributes.underlineStyle = tldsSingle
        of tckGrammar:
          attributes.underline = true
          attributes.underlineStyle = tldsDouble
        of tckLink, tckData:
          attributes.link =
            if checking.link.len > 0:
              checking.link
            else:
              textView.xTextStorage.substring(clamped)
      textView.xTextStorage.setAttributes(clamped, attributes)
  textView.xTextStorage.endEditing()
  textView.xCheckingResults = @results
  textView.syncLayout()
  textView.invalidateIntrinsicContentSize()
  textView.setNeedsDisplay(true)

proc checkSpellingAndGrammar*(textView: TextView): seq[TextCheckingResult] =
  result = textView.checkText()
  textView.applyTextCheckingResults(result)

proc completionPrefixRange*(textView: TextView): TextRange =
  let selected = textView.textViewSelectedRange()
  if selected.length > 0:
    return selected
  textView.textViewStringValue().wordRangeAt(textView.xInsertionPoint)

proc completeText*(textView: TextView): TextCompletionPanel =
  let
    range = textView.completionPrefixRange()
    prefix = textView.xTextStorage.substring(range)
    completions =
      if textView.xDelegate.isNil:
        @[]
      else:
        textView.xDelegate
        .trySendLocal(
          tvCompletions(), (textView: textView, prefix: prefix, range: range)
        )
        .get(@[])
  textView.xCompletionPanel = TextCompletionPanel(
    prefix: prefix,
    range: range,
    completions: completions,
    selectedIndex: if completions.len > 0: 0 else: -1,
    visible: completions.len > 0,
  )
  textView.setNeedsDisplay(true)
  textView.xCompletionPanel

proc dismissCompletionPanel*(textView: TextView) =
  textView.xCompletionPanel.visible = false
  textView.setNeedsDisplay(true)

proc acceptCompletion*(textView: TextView, index = -1): bool =
  if not textView.editable or not textView.xCompletionPanel.visible:
    return false
  let selectedIndex = if index >= 0: index else: textView.xCompletionPanel.selectedIndex
  if selectedIndex < 0 or selectedIndex >= textView.xCompletionPanel.completions.len:
    return false
  let replacement = textView.xCompletionPanel.completions[selectedIndex]
  textView.replaceRange(
    textView.xCompletionPanel.range, replacement, textView.xTypingAttributes
  )
  textView.dismissCompletionPanel()
  true

func overlapRange(a, b: TextRange): TextRange =
  let
    start = max(int(a.location), int(b.location))
    stop = min(a.maxIndex, b.maxIndex)
  initTextRange(start, max(stop - start, 0))

func unionRange(a, b: TextRange): TextRange =
  if a.length == 0:
    return b
  if b.length == 0:
    return a
  let
    start = min(int(a.location), int(b.location))
    stop = max(a.maxIndex, b.maxIndex)
  initTextRange(start, stop - start)

func nonEmptyRanges(ranges: openArray[TextRange]): seq[TextRange] =
  for range in ranges:
    if range.length > 0:
      result.add range

func escapedHtml(text: string): string =
  for ch in text:
    case ch
    of '&':
      result.add "&amp;"
    of '<':
      result.add "&lt;"
    of '>':
      result.add "&gt;"
    of '"':
      result.add "&quot;"
    else:
      result.add ch

func escapedRtf(text: string): string =
  for ch in text:
    case ch
    of '\\':
      result.add "\\\\"
    of '{':
      result.add "\\{"
    of '}':
      result.add "\\}"
    of '\n':
      result.add "\\par "
    else:
      result.add ch

func roundToScale(value, scale: float32): float32 =
  if scale <= 0.0'f32:
    value
  else:
    round(value * scale) / scale

func roundRectToScale(rect: Rect, scale: float32): Rect =
  if rect.isEmpty or scale <= 0.0'f32:
    return rect
  rect(
    rect.origin.x.roundToScale(scale),
    rect.origin.y.roundToScale(scale),
    rect.size.width.roundToScale(scale),
    rect.size.height.roundToScale(scale),
  )

func roundLineFragmentToScale(
    fragment: TextLineFragment, scale: float32
): TextLineFragment =
  result = fragment
  result.fragmentRect = result.fragmentRect.roundRectToScale(scale)
  result.usedRect = result.usedRect.roundRectToScale(scale)
  result.baseline = result.baseline.roundToScale(scale)
  result.ascent = result.ascent.roundToScale(scale)
  result.descent = result.descent.roundToScale(scale)
  result.leading = result.leading.roundToScale(scale)

proc unionRects(rects: openArray[Rect]): Rect =
  for rect in rects:
    if rect.isEmpty:
      continue
    if result.isEmpty:
      result = rect
    else:
      result = result.union(rect)

proc selectedTextRangesForTransfer(textView: TextView): seq[TextRange] =
  result = textView.selectedRanges().nonEmptyRanges()
  if result.len == 0:
    let selected = textView.textViewSelectedRange()
    if selected.length > 0:
      result.add selected

proc selectedTextStorage*(textView: TextView): TextStorage =
  result = newTextStorage()
  if textView.xTextStorage.isNil:
    return
  for range in textView.selectedTextRangesForTransfer():
    result.replace(
      initTextRange(result.len, 0), textView.xTextStorage.sliceTextStorage(range)
    )

proc selectedText*(textView: TextView): string =
  if textView.xTextStorage.isNil:
    return ""
  for range in textView.selectedTextRangesForTransfer():
    result.add textView.xTextStorage.substring(range)

proc selectedTextServiceRequest*(textView: TextView): TextServiceRequest =
  let selected = textView.textViewSelectedRange()
  TextServiceRequest(
    range: selected,
    selectedRanges: textView.selectedRanges(),
    stringValue: textView.selectedText(),
    attributedString: textView.selectedTextStorage(),
  )

proc performSelectedTextService*(textView: TextView): TextServiceResponse =
  if textView.xDelegate.isNil:
    return
  let request = textView.selectedTextServiceRequest()
  result = textView.xDelegate
    .trySendLocal(tvPerformService(), (textView: textView, request: request))
    .get(TextServiceResponse())
  if result.handled and not result.replacement.isNil and textView.editable:
    let replacementRange =
      if result.replacementRange.length > 0:
        textView.clampedRange(result.replacementRange)
      else:
        textView.clampedRange(request.range)
    if textView.shouldChangeText(replacementRange, result.replacement):
      textView.replaceRange(replacementRange, result.replacement)

proc firstSelectedLink(textView: TextView): tuple[link: string, range: TextRange] =
  if textView.xTextStorage.isNil:
    return
  for selected in textView.selectedTextRangesForTransfer():
    for run in textView.xTextStorage.runs:
      let overlap = run.range.overlapRange(selected)
      if overlap.length > 0 and run.attributes.hasLink:
        return (run.attributes.link, overlap)

proc selectedAttachmentPresentations*(
    textView: TextView
): seq[TextAttachmentPresentation] =
  if textView.xTextStorage.isNil:
    return
  for selected in textView.selectedTextRangesForTransfer():
    for run in textView.xTextStorage.runs:
      let overlap = run.range.overlapRange(selected)
      if overlap.length == 0 or not run.attributes.hasAttachment:
        continue
      let rect = textView.selectionRects(overlap).unionRects()
      let frame =
        if rect.isEmpty:
          textView.characterRect(int(overlap.location))
        else:
          rect
      let delegateView =
        if textView.xDelegate.isNil:
          nil
        else:
          textView.xDelegate
          .trySendLocal(
            tvAttachmentView(),
            (
              textView: textView,
              attachment: run.attributes.attachment,
              range: overlap,
              frame: frame,
            ),
          )
          .get(nil)
      let delegateCell =
        if textView.xDelegate.isNil:
          TextAttachmentCell()
        else:
          textView.xDelegate
          .trySendLocal(
            tvAttachmentCell(),
            (
              textView: textView,
              attachment: run.attributes.attachment,
              range: overlap,
              frame: frame,
            ),
          )
          .get(TextAttachmentCell())
      let cell =
        if delegateCell.attachment.identifier.len > 0 or
            delegateCell.attachment.contentType.len > 0 or
            delegateCell.attachment.fileName.len > 0 or
            delegateCell.attachment.fileUrl.len > 0:
          delegateCell
        else:
          TextAttachmentCell(
            attachment: run.attributes.attachment, range: overlap, frame: frame
          )
      result.add TextAttachmentPresentation(
        attachment: run.attributes.attachment,
        range: overlap,
        frame: frame,
        cell: cell,
        view: delegateView,
      )

proc attachmentPresentations*(textView: TextView): seq[TextAttachmentPresentation] =
  if textView.xTextStorage.isNil:
    return
  for run in textView.xTextStorage.runs:
    if not run.attributes.hasAttachment:
      continue
    let rect = textView.selectionRects(run.range).unionRects()
    let frame =
      if rect.isEmpty:
        textView.characterRect(int(run.range.location))
      else:
        rect
    result.add TextAttachmentPresentation(
      attachment: run.attributes.attachment,
      range: run.range,
      frame: frame,
      cell: TextAttachmentCell(
        attachment: run.attributes.attachment, range: run.range, frame: frame
      ),
    )

func isImageAttachment*(attachment: TextAttachment): bool =
  let
    contentType = attachment.contentType.toLowerAscii()
    name = attachment.fileName.toLowerAscii()
  contentType.startsWith("image/") or name.endsWith(".png") or name.endsWith(".jpg") or
    name.endsWith(".jpeg") or name.endsWith(".gif") or name.endsWith(".webp") or
    name.endsWith(".tif") or name.endsWith(".tiff")

func promisedFileName*(attachment: TextAttachment): string =
  if attachment.fileName.len > 0:
    attachment.fileName
  elif attachment.fileUrl.len > 0:
    attachment.fileUrl
  else:
    ""

proc selectedImageAttachments*(textView: TextView): seq[TextAttachmentPresentation] =
  for presentation in textView.selectedAttachmentPresentations():
    if presentation.attachment.isImageAttachment():
      result.add presentation

proc selectedFilePromiseAttachments*(
    textView: TextView
): seq[TextAttachmentPresentation] =
  for presentation in textView.selectedAttachmentPresentations():
    if presentation.attachment.promisedFileName().len > 0:
      result.add presentation

proc writeSelectionToPasteboard*(
    textView: TextView,
    pasteboard: Pasteboard,
    formats: openArray[TextTransferFormat] =
      [ttfAttributedText, ttfPlainText, ttfURL, ttfFilePromise],
): bool =
  if textView.isNil or pasteboard.isNil or not textView.selectable:
    return false
  let ranges = textView.selectedTextRangesForTransfer()
  if ranges.len == 0:
    return false

  var types: seq[string]
  for format in formats:
    let pasteboardType = pasteboardTypeForTextFormat(format)
    if pasteboardType.len > 0 and pasteboardType notin types:
      types.add pasteboardType
  if PasteboardTypeString notin types:
    types.add PasteboardTypeString
  if PasteboardTypeTextStorage notin types:
    types.add PasteboardTypeTextStorage
  pasteboard.declareTypes(types)

  let
    text = textView.selectedText()
    storage = textView.selectedTextStorage()
  for format in formats:
    case format
    of ttfPlainText:
      discard pasteboard.setPlainText(text)
      discard pasteboard.setString(PasteboardTypeString, text)
    of ttfAttributedText:
      discard pasteboard.setAttributedString(storage)
      discard pasteboard.setTextStorage(PasteboardTypeTextStorage, storage)
    of ttfRTF:
      discard pasteboard.setRtfData("{\\rtf1 " & text.escapedRtf() & "}")
    of ttfRTFD:
      discard pasteboard.setRtfdData("NimKit-RTFD\n" & text)
    of ttfHTML:
      discard pasteboard.setHtml("<pre>" & text.escapedHtml() & "</pre>")
    of ttfURL:
      let link = textView.firstSelectedLink()
      if link.link.len > 0:
        discard pasteboard.setUrl(PasteboardTypeUrl, link.link)
    of ttfFilePromise:
      for presentation in textView.selectedFilePromiseAttachments():
        let fileName = presentation.attachment.promisedFileName()
        if fileName.len > 0:
          discard pasteboard.setFile(PasteboardTypeFilePromise, fileName)
          break
  true

proc insertTextFromPasteboard*(textView: TextView, pasteboard: Pasteboard): bool =
  if pasteboard.isNil or not textView.editable:
    return false
  let selected =
    if textView.xHasMarkedText:
      textView.xMarkedRange
    else:
      textView.textViewSelectedRange()
  let kind =
    pasteboard.availableTypeFromArray([PasteboardTypeTextStorage, PasteboardTypeString])
  case kind
  of PasteboardTypeTextStorage:
    let storage = pasteboard.textStorageForType(PasteboardTypeTextStorage)
    if storage.isNil:
      return false
    textView.replaceRange(selected, storage)
    true
  of PasteboardTypeString:
    textView.insertTextValue(pasteboard.stringForType(PasteboardTypeString))
    true
  else:
    false

proc selectedTextDraggingItems*(textView: TextView): seq[DraggingItem] =
  if textView.selectedTextRangesForTransfer().len == 0:
    return
  let
    storage = textView.selectedTextStorage()
    text = textView.selectedText()
    frame = textView.selectionRects(textView.textViewSelectedRange()).unionRects()
  if storage.len > 0:
    result.add initDraggingItem(
      PasteboardTypeTextStorage, initPasteboardTextStorageItem(storage), frame
    )
    result.add initDraggingItem(
      PasteboardTypeString, initPasteboardStringItem(text), frame
    )
  let link = textView.firstSelectedLink()
  if link.link.len > 0:
    result.add initDraggingItem(
      PasteboardTypeUrl,
      initPasteboardUrlItem(link.link),
      textView.selectionRects(link.range).unionRects(),
    )
  for presentation in textView.selectedFilePromiseAttachments():
    let
      fileName = presentation.attachment.promisedFileName()
      item =
        if presentation.attachment.fileUrl.len > 0:
          initPasteboardFileItem(presentation.attachment.fileUrl)
        else:
          initPasteboardFileItem(fileName)
    if fileName.len > 0:
      result.add initPromisedFileDraggingItem(fileName, item, presentation.frame)

proc beginDraggingSelectedText*(
    textView: TextView,
    allowedOperations: DragOperations = {dgoCopy, dgoMove},
    pasteboardName = DragPasteboardName,
): DraggingSession =
  if not textView.selectable:
    return nil
  let items = textView.selectedTextDraggingItems()
  if items.len == 0:
    return nil
  result = beginDraggingSession(
    DynamicAgent(textView), items, allowedOperations, pasteboardName
  )
  textView.xDraggingSession = result

proc acceptsTextDrop*(textView: TextView, info: DraggingInfo): DragOperations =
  if not textView.editable or info.pasteboard.isNil:
    return NoDragOperations
  let accepted = info.pasteboard.availableTypeFromArray(
    [PasteboardTypeTextStorage, PasteboardTypeString]
  )
  if accepted.len == 0:
    NoDragOperations
  else:
    info.allowedOperations * {dgoCopy, dgoMove}

proc performTextDrop*(textView: TextView, info: DraggingInfo): bool =
  if textView.acceptsTextDrop(info) == NoDragOperations:
    return false
  if not info.location.hasAutoMetric:
    textView.setCursor(textView.textIndexAtPoint(info.location))
  textView.insertTextFromPasteboard(info.pasteboard)

proc linkRangeAtIndex(textView: TextView, index: int, link: string): TextRange =
  if link.len == 0:
    return initTextRange(index, 0)
  let total = textView.xTextStorage.len
  var
    start = clampIndex(total, index)
    stop = start
  while start > 0 and textView.xTextStorage.attributesAt(start - 1).link == link:
    dec start
  while stop < total and textView.xTextStorage.attributesAt(stop).link == link:
    inc stop
  initTextRange(start, stop - start)

proc attachmentRangeAtIndex(
    textView: TextView, index: int, attachment: TextAttachment
): TextRange =
  let total = textView.xTextStorage.len
  var
    start = clampIndex(total, index)
    stop = start
  while start > 0 and
      textView.xTextStorage.attributesAt(start - 1).attachment == attachment:
    dec start
  while stop < total and
      textView.xTextStorage.attributesAt(stop).attachment == attachment:
    inc stop
  initTextRange(start, stop - start)

proc linkAtIndex*(
    textView: TextView, index: int
): tuple[link: string, range: TextRange] =
  if index < 0 or index >= textView.xTextStorage.len:
    return
  let attributes = textView.xTextStorage.attributesAt(index)
  if attributes.hasLink:
    result = (attributes.link, textView.linkRangeAtIndex(index, attributes.link))

proc linkAtPoint*(
    textView: TextView, point: Point
): tuple[link: string, range: TextRange] =
  textView.linkAtIndex(textView.textIndexAtPoint(point))

proc attachmentAtIndex*(
    textView: TextView, index: int
): tuple[attachment: TextAttachment, range: TextRange] =
  if index < 0 or index >= textView.xTextStorage.len:
    return
  let attributes = textView.xTextStorage.attributesAt(index)
  if attributes.hasAttachment:
    result = (
      attributes.attachment,
      textView.attachmentRangeAtIndex(index, attributes.attachment),
    )

proc attachmentAtPoint*(
    textView: TextView, point: Point
): tuple[attachment: TextAttachment, range: TextRange] =
  textView.attachmentAtIndex(textView.textIndexAtPoint(point))

proc openLinkAtIndex*(textView: TextView, index: int): bool =
  let link = textView.linkAtIndex(index)
  if link.link.len == 0:
    return false
  if textView.xDelegate.isNil:
    return true

  textView.xDelegate
  .trySendLocal(
    tvClickedLink(), (textView: textView, link: link.link, range: link.range)
  )
  .get(true)

proc openLinkAtPoint*(textView: TextView, point: Point): bool =
  textView.openLinkAtIndex(textView.textIndexAtPoint(point))

proc activeLinkForCommand(textView: TextView): tuple[link: string, range: TextRange] =
  let selected = textView.textViewSelectedRange()
  if selected.length > 0:
    result = textView.linkAtIndex(int(selected.location))
    if result.link.len > 0:
      return
  let insertionPoint = textView.textViewInsertionPoint()
  result = textView.linkAtIndex(insertionPoint)
  if result.link.len == 0 and insertionPoint > 0:
    result = textView.linkAtIndex(insertionPoint - 1)

proc clickTextAtPoint*(textView: TextView, point: Point): bool =
  let index = textView.textIndexAtPoint(point)
  if index < 0 or index >= textView.xTextStorage.len:
    return false
  let attributes = textView.xTextStorage.attributesAt(index)
  if attributes.hasLink:
    return textView.openLinkAtIndex(index)
  if attributes.hasAttachment:
    let range = textView.attachmentRangeAtIndex(index, attributes.attachment)
    if textView.xDelegate.isNil:
      return true
    return textView.xDelegate
      .trySendLocal(
        tvClickedAttachment(),
        (textView: textView, attachment: attributes.attachment, range: range),
      )
      .get(true)

proc paragraphStyleAt*(textView: TextView, index: int): TextParagraphStyle =
  if textView.xTextStorage.len == 0:
    return textView.defaultParagraphStyle()
  textView.xTextStorage.attributesAt(index).paragraphStyle

proc setParagraphStyle*(
    textView: TextView, range: TextRange, style: TextParagraphStyle
) =
  if textView.xTextStorage.isNil:
    return
  let paragraphRange = textView.xTextStorage.paragraphRangeForRange(range)
  if paragraphRange.length == 0:
    textView.xDefaultParagraphStyle = style
    textView.xTypingAttributes.paragraphStyle = style
    return
  textView.xTextStorage.beginEditing()
  textView.xTextStorage.setParagraphStyle(paragraphRange, style)
  textView.xTextStorage.endEditing()
  textView.xDefaultParagraphStyle = style
  textView.xTypingAttributes.paragraphStyle = style
  textView.syncLayout()
  textView.invalidateIntrinsicContentSize()
  textView.setNeedsDisplay(true)

proc setTabStops*(
    textView: TextView, range: TextRange, tabStops: openArray[TextTabStop]
) =
  var style = textView.paragraphStyleAt(int(range.location))
  style.tabStops = @tabStops
  textView.setParagraphStyle(range, style)

proc displayTextStorage(textView: TextView): TextStorage =
  let shouldApplyPlainTextColor = (not textView.richText) or textView.isFieldEditor
  let hasMarkedOverlay = textView.xHasMarkedText and textView.xMarkedRange.length > 0
  var hasSelectedOverlay = false
  if textView.xHasSelectedTextAttributes:
    for range in textView.selectedRanges():
      if range.length > 0:
        hasSelectedOverlay = true
        break
  if shouldApplyPlainTextColor or hasMarkedOverlay or hasSelectedOverlay:
    result = textView.xTextStorage.copyTextStorage()
  else:
    result = textView.xTextStorage
  if shouldApplyPlainTextColor and result.len > 0:
    let style = textView.textStyle()
    result.setAttributes(
      initTextRange(0, result.len),
      defaultTextAttributes(style.color, style.fontSize, style.fontName, style.language),
    )
  if hasMarkedOverlay:
    result.setAttributes(textView.xMarkedRange, textView.xMarkedTextAttributes)
  if hasSelectedOverlay:
    for range in textView.selectedRanges():
      if range.length > 0:
        result.setAttributes(range, textView.xSelectedTextAttributes)

proc syncLayout(textView: TextView) =
  if textView.xLayoutManager.isNil:
    return
  textView.xLayoutManager.textStorage = textView.xTextStorage
  textView.xLayoutManager.textContainer = textView.xTextContainer
  textView.xLayoutManager.textStyle = textView.textStyle()
  textView.xLayoutManager.alignment = textView.xAlignment

proc setCursor*(textView: TextView, index: int, extending = false) =
  let previousRanges = textView.selectedRanges()
  let cursor = clampIndex(textView.xTextStorage.len, index)
  textView.xInsertionPoint = cursor
  if not extending:
    textView.xSelectionAnchor = cursor
  let
    start = min(textView.xSelectionAnchor, textView.xInsertionPoint)
    stop = max(textView.xSelectionAnchor, textView.xInsertionPoint)
  textView.xSelectedRanges = @[initTextRange(start, stop - start)]
  textView.updateTypingAttributesForSelection()
  textView.showInsertionPoint()
  textView.setNeedsDisplay(true)
  textView.dispatchSelectionChanged(previousRanges)

proc selectAllText*(textView: TextView) =
  let previousRanges = textView.selectedRanges()
  textView.xSelectionAnchor = 0
  textView.xInsertionPoint = textView.xTextStorage.len
  textView.xSelectedRanges = @[initTextRange(0, textView.xTextStorage.len)]
  textView.updateTypingAttributesForSelection()
  textView.showInsertionPoint()
  textView.setNeedsDisplay(true)
  textView.dispatchSelectionChanged(previousRanges)

proc replaceSelectedText*(textView: TextView, insertion: string) =
  if not textView.editable:
    return
  let selected =
    if textView.xHasMarkedText:
      textView.xMarkedRange
    else:
      textView.textViewSelectedRange()
  textView.replaceRange(
    selected,
    textView.preparedInsertion(selected, insertion),
    textView.xTypingAttributes,
  )

proc insertTextValue*(textView: TextView, insertion: string) =
  if not textView.editable:
    return
  if textView.xHasMarkedText:
    let
      before = textView.xMarkedUndoStorage
      beforeSelection = textView.xMarkedUndoSelection
      selected = textView.xMarkedRange
      value = textView.preparedInsertion(selected, insertion)
    textView.replaceRange(selected, value, textView.xTypingAttributes, record = false)
    if not before.isNil:
      textView.recordUndo(before, beforeSelection, textView.textViewSelectedRange())
  else:
    textView.replaceSelectedText(insertion)

proc setMarkedTextValue*(
    textView: TextView, text: string, selectedRange, replacementRange: TextRange
) =
  if not textView.editable:
    return
  let target =
    if textView.xHasMarkedText:
      textView.xMarkedRange
    elif replacementRange.length > 0:
      replacementRange
    else:
      textView.textViewSelectedRange()
  let clamped = textView.clampedRange(target)
  if not textView.xHasMarkedText:
    textView.xMarkedUndoStorage = textView.xTextStorage.copyTextStorage()
    textView.xMarkedUndoSelection = textView.textViewSelectedRange()
  textView.replaceRange(
    clamped, text, textView.xTypingAttributes, record = false, clearMark = false
  )
  let
    markedStart = int(clamped.location)
    markedLength = text.runeLen
    selectedStart = markedStart + max(0, min(int(selectedRange.location), markedLength))
    selectedLength = max(0, min(int(selectedRange.length), markedLength))
  textView.xHasMarkedText = true
  textView.xMarkedRange = initTextRange(markedStart, markedLength)
  textView.setSelection(initTextRange(selectedStart, selectedLength))
  textView.setNeedsDisplay(true)

proc unmarkMarkedText*(textView: TextView) =
  textView.clearMarkedText()
  textView.setNeedsDisplay(true)

proc copyText*(textView: TextView): bool =
  if not textView.selectable:
    return false
  textView.writeSelectionToPasteboard(
    generalPasteboard(),
    [ttfAttributedText, ttfPlainText, ttfRTF, ttfHTML, ttfURL, ttfFilePromise],
  )

proc cutText*(textView: TextView): bool =
  if not textView.editable or not textView.copyText():
    return false
  textView.replaceSelectedText("")
  true

proc pasteText*(textView: TextView): bool =
  if not textView.editable:
    return false
  textView.insertTextFromPasteboard(generalPasteboard())

proc applyUndoRecord(textView: TextView, storage: TextStorage, selection: TextRange) =
  textView.xApplyingUndo = true
  let changedRange = initTextRange(0, textView.xTextStorage.len)
  textView.xTextStorage = storage.copyTextStorage()
  textView.clearMarkedText()
  textView.setSelection(selection)
  textView.finishTextMutation(changedRange)
  textView.xApplyingUndo = false

proc undoText*(textView: TextView): bool =
  if textView.xUndoStack.len == 0:
    return false
  let record = textView.xUndoStack.pop()
  textView.applyUndoRecord(record.storageBefore, record.selectionBefore)
  textView.xRedoStack.add record
  true

proc redoText*(textView: TextView): bool =
  if textView.xRedoStack.len == 0:
    return false
  let record = textView.xRedoStack.pop()
  textView.applyUndoRecord(record.storageAfter, record.selectionAfter)
  textView.xUndoStack.add record
  true

proc deleteBackwardText*(textView: TextView) =
  if not textView.editable:
    return
  let selected = textView.currentSelection()
  if selected.stop > selected.start:
    textView.replaceSelectedText("")
  elif selected.start > 0:
    textView.replaceRange(
      initTextRange(selected.start - 1, 1), "", textView.xTypingAttributes
    )

proc deleteForwardText*(textView: TextView) =
  if not textView.editable:
    return
  let
    selected = textView.currentSelection()
    total = textView.xTextStorage.len
  if selected.stop > selected.start:
    textView.replaceSelectedText("")
  elif selected.start < total:
    textView.replaceRange(
      initTextRange(selected.start, 1), "", textView.xTypingAttributes
    )

proc deleteWordBackwardText*(textView: TextView) =
  if not textView.editable:
    return
  let selected = textView.currentSelection()
  if selected.stop > selected.start:
    textView.replaceSelectedText("")
  else:
    let cursor = textView.textViewStringValue().previousWordBoundary(selected.start)
    if cursor != selected.start:
      textView.replaceRange(
        initTextRange(cursor, selected.start - cursor), "", textView.xTypingAttributes
      )

proc deleteWordForwardText*(textView: TextView) =
  if not textView.editable:
    return
  let selected = textView.currentSelection()
  if selected.stop > selected.start:
    textView.replaceSelectedText("")
  else:
    let cursor = textView.textViewStringValue().nextWordBoundary(selected.start)
    if cursor != selected.start:
      textView.replaceRange(
        initTextRange(selected.start, cursor - selected.start),
        "",
        textView.xTypingAttributes,
      )

proc deleteToBeginningOfLineText*(textView: TextView) =
  if not textView.editable:
    return
  let selected = textView.currentSelection()
  if selected.stop > selected.start:
    textView.replaceSelectedText("")
    return
  let first = textView.currentVisualLineBounds().first
  if first < selected.start:
    textView.replaceRange(
      initTextRange(first, selected.start - first), "", textView.xTypingAttributes
    )

proc deleteToEndOfLineText*(textView: TextView) =
  if not textView.editable:
    return
  let selected = textView.currentSelection()
  if selected.stop > selected.start:
    textView.replaceSelectedText("")
    return
  let last = textView.currentVisualLineBounds().last
  if last > selected.start:
    textView.replaceRange(
      initTextRange(selected.start, last - selected.start),
      "",
      textView.xTypingAttributes,
    )

proc insertLineBreakText*(textView: TextView) =
  textView.insertTextValue("\n")

proc insertParagraphSeparatorText*(textView: TextView) =
  textView.insertTextValue("\n")

proc moveLeftText*(textView: TextView, extending = false) =
  if (not textView.editable and not textView.selectable):
    return
  let selected = textView.currentSelection()
  if selected.stop > selected.start and not extending:
    textView.setCursor(selected.start)
  else:
    textView.setCursor(textView.xInsertionPoint - 1, extending)

proc moveRightText*(textView: TextView, extending = false) =
  if (not textView.editable and not textView.selectable):
    return
  let selected = textView.currentSelection()
  if selected.stop > selected.start and not extending:
    textView.setCursor(selected.stop)
  else:
    textView.setCursor(textView.xInsertionPoint + 1, extending)

proc moveVerticalText(textView: TextView, direction: int, extending = false) =
  if (not textView.editable and not textView.selectable):
    return

  let selected = textView.currentSelection()
  if selected.stop > selected.start and not extending:
    textView.setCursor(if direction < 0: selected.start else: selected.stop)
    return

  textView.updateTextContainer()
  let
    caret = textView.xLayoutManager.caretRect(textView.xInsertionPoint)
    lineHeight = max(caret.size.height, defaultFontSize())
    target = initPoint(
      caret.origin.x,
      caret.origin.y + caret.size.height * 0.5'f32 + float32(direction) * lineHeight,
    )
    index = textView.xLayoutManager.textIndexAtPoint(target)
  textView.setCursor(index, extending)

proc moveUpText*(textView: TextView, extending = false) =
  textView.moveVerticalText(-1, extending)

proc moveDownText*(textView: TextView, extending = false) =
  textView.moveVerticalText(1, extending)

proc moveWordLeftText*(textView: TextView, extending = false) =
  if (not textView.editable and not textView.selectable):
    return
  textView.setCursor(
    textView.textViewStringValue().previousWordBoundary(textView.xInsertionPoint),
    extending,
  )

proc moveWordRightText*(textView: TextView, extending = false) =
  if (not textView.editable and not textView.selectable):
    return
  textView.setCursor(
    textView.textViewStringValue().nextWordBoundary(textView.xInsertionPoint), extending
  )

proc currentVisualLineBounds(textView: TextView): tuple[first, last: int] =
  result = (first: textView.xInsertionPoint, last: textView.xInsertionPoint)
  textView.updateTextContainer()
  let fragment =
    textView.xLayoutManager.lineFragmentForTextIndex(textView.xInsertionPoint)
  if fragment.isNone:
    return

  let
    line = fragment.get()
    runes = textView.textViewStringValue().toRunes()
  result.first = int(line.textRange.location)
  result.last = line.textRange.maxIndex
  if line.hardBreak and result.last > result.first and result.last - 1 < runes.len and
      runes[result.last - 1] == Rune('\n'):
    dec result.last
  result.last = max(result.first, result.last)

proc moveToBeginningOfLineText*(textView: TextView, extending = false) =
  if (not textView.editable and not textView.selectable):
    return
  textView.setCursor(textView.currentVisualLineBounds().first, extending)

proc moveToEndOfLineText*(textView: TextView, extending = false) =
  if (not textView.editable and not textView.selectable):
    return
  textView.setCursor(textView.currentVisualLineBounds().last, extending)

proc moveToBeginningOfDocumentText*(textView: TextView, extending = false) =
  if (not textView.editable and not textView.selectable):
    return
  textView.setCursor(0, extending)

proc moveToEndOfDocumentText*(textView: TextView, extending = false) =
  if (not textView.editable and not textView.selectable):
    return
  textView.setCursor(textView.xTextStorage.len, extending)

proc updateFieldEditorInsets(textView: TextView) =
  if not textView.isFieldEditor:
    return
  let
    lineHeight = textNaturalSize("", textView.textStyle()).height
    extraHeight = max(textView.bounds.size.height - lineHeight, 0.0'f32)
    topInset = extraHeight / 2.0'f32
  textView.xTextContainer.insets.top = topInset
  textView.xTextContainer.insets.bottom = extraHeight - topInset

proc updateTextContainer(textView: TextView) =
  if textView.xTextContainer.widthTracksTextView:
    textView.xTextContainer.size.width = textView.bounds.size.width
  if textView.xTextContainer.heightTracksTextView:
    textView.xTextContainer.size.height = textView.bounds.size.height
  textView.updateFieldEditorInsets()
  textView.syncLayout()

proc textIndexAtPoint*(textView: TextView, point: Point): int =
  textView.updateTextContainer()
  textView.xLayoutManager.textIndexAtPoint(point)

proc selectionRects*(textView: TextView, range: TextRange): seq[Rect] =
  textView.updateTextContainer()
  textView.xLayoutManager.selectionRects(range)

proc characterRect*(textView: TextView, index: int): Rect =
  textView.updateTextContainer()
  textView.xLayoutManager.characterRect(index)

proc lineRange*(textView: TextView, line: int): TextRange =
  textView.updateTextContainer()
  textView.xLayoutManager.lineRange(line)

proc lineForIndex*(textView: TextView, index: int): int =
  textView.updateTextContainer()
  textView.xLayoutManager.lineForIndex(index)

proc lineBounds*(textView: TextView, line: int): Rect =
  textView.updateTextContainer()
  textView.xLayoutManager.lineBounds(line)

proc initTextPageLayoutOptions*(
    pageSize = initSize(612.0, 792.0),
    contentInsets = insets(72.0),
    firstPageNumber = 1,
    displayScale = 1.0'f32,
): TextPageLayoutOptions =
  TextPageLayoutOptions(
    pageSize: initSize(max(pageSize.width, 1.0'f32), max(pageSize.height, 1.0'f32)),
    contentInsets: contentInsets,
    firstPageNumber: max(firstPageNumber, 0).Natural,
    displayScale: max(displayScale, 0.0'f32),
  )

proc normalizedPageOptions(
    textView: TextView, options: TextPageLayoutOptions
): TextPageLayoutOptions =
  result = options
  if result.pageSize.width <= 0.0'f32 or result.pageSize.width.isAutoMetric:
    result.pageSize.width = max(textView.bounds.size.width, 1.0'f32)
  if result.pageSize.height <= 0.0'f32 or result.pageSize.height.isAutoMetric:
    result.pageSize.height = max(textView.bounds.size.height, 1.0'f32)
  if result.firstPageNumber == 0:
    result.firstPageNumber = 1
  if result.displayScale <= 0.0'f32:
    result.displayScale = 1.0'f32

proc pageContentRect(options: TextPageLayoutOptions, pageIndex: int): Rect =
  rect(
    0.0'f32,
    float32(pageIndex) * options.pageSize.height,
    options.pageSize.width,
    options.pageSize.height,
  )
  .inset(options.contentInsets)

proc addLineToPage(
    pages: var seq[TextPageFragment],
    pageIndex: int,
    options: TextPageLayoutOptions,
    fragment: TextLineFragment,
) =
  while pages.len <= pageIndex:
    let next = pages.len
    let
      pageRect = rect(
        0.0'f32,
        float32(next) * options.pageSize.height,
        options.pageSize.width,
        options.pageSize.height,
      )
      contentRect = options.pageContentRect(next)
    pages.add TextPageFragment(
      pageIndex: next.Natural,
      pageNumber: options.firstPageNumber + next.Natural,
      containerIndex: fragment.containerIndex,
      pageRect: pageRect.roundRectToScale(options.displayScale),
      contentRect: contentRect.roundRectToScale(options.displayScale),
    )
  var page = pages[pageIndex]
  let rounded = fragment.roundLineFragmentToScale(options.displayScale)
  page.lineFragments.add rounded
  page.textRange = page.textRange.unionRange(rounded.textRange)
  if page.usedRect.isEmpty:
    page.usedRect = rounded.usedRect
  else:
    page.usedRect = page.usedRect.union(rounded.usedRect)
  page.usedRect = page.usedRect.roundRectToScale(options.displayScale)
  pages[pageIndex] = page

proc paginateLineFragments(
    fragments: openArray[TextLineFragment],
    originY: float32,
    options: TextPageLayoutOptions,
): seq[TextPageFragment] =
  let contentHeight =
    max(options.pageSize.height - options.contentInsets.vertical, 1.0'f32)
  for fragment in fragments:
    let pageIndex =
      max(0, int(floor((fragment.fragmentRect.origin.y - originY) / contentHeight)))
    result.addLineToPage(pageIndex, options, fragment)

proc paginateTextView*(
    textView: TextView, options = initTextPageLayoutOptions()
): seq[TextPageFragment] =
  textView.updateTextContainer()
  let
    resolved = textView.normalizedPageOptions(options)
    snapshot = textView.xLayoutManager.layoutSnapshot()
  result = paginateLineFragments(
    snapshot.lineFragments, snapshot.containerRect.origin.y, resolved
  )
  if result.len == 0:
    let emptyFragment = textView.xLayoutManager.extraLineFragment()
    result.addLineToPage(0, resolved, emptyFragment)

proc rulerMetrics*(textView: TextView, range: TextRange): TextRulerMetrics =
  let
    clamped = textView.clampedRange(range)
    style = textView.paragraphStyleAt(int(clamped.location))
    rulerHeight = max(defaultFontSize() * 1.5'f32, 18.0'f32)
  TextRulerMetrics(
    range: clamped,
    paragraphStyle: style,
    rulerRect: rect(
      textView.bounds.origin.x, textView.bounds.origin.y, textView.bounds.size.width,
      rulerHeight,
    ),
    firstLineHeadIndent: style.firstLineHeadIndent,
    headIndent: style.headIndent,
    tailIndent: style.tailIndent,
    tabStops: style.tabStops,
  )

proc visibleCharacterRange*(textView: TextView): TextRange =
  if textView.xTextStorage.isNil:
    return initTextRange(0, 0)
  textView.updateTextContainer()
  let visible = textView.bounds
  var hasVisible = false
  for fragment in textView.xLayoutManager.lineFragments():
    if fragment.fragmentRect.intersection(visible).isEmpty:
      continue
    if hasVisible:
      result = result.unionRange(fragment.textRange)
    else:
      result = fragment.textRange
      hasVisible = true
  if not hasVisible:
    result = initTextRange(0, textView.xTextStorage.len)

proc copyStorageForSnapshot(storage: TextStorage, fontSize: float32): TextStorage =
  result = storage.copyTextStorage()
  if fontSize <= 0.0'f32:
    return
  let runs = result.attributeRuns()
  result.beginEditing()
  for run in runs:
    var attributes = run.attributes
    attributes.fontSize = fontSize
    result.setAttributes(run.range, attributes)
  result.endEditing()

proc layoutStabilitySnapshot*(
    textView: TextView, options: TextLayoutStabilityOptions
): TextLayoutStabilitySnapshot =
  textView.updateTextContainer()
  let
    scale =
      if options.displayScale > 0.0'f32:
        options.displayScale
      elif options.pageOptions.displayScale > 0.0'f32:
        options.pageOptions.displayScale
      else:
        1.0'f32
    storage = textView.xTextStorage.copyStorageForSnapshot(options.fontSize)
    container = textView.xTextContainer
    manager = newTextLayoutManager(storage, container)
  var style = textView.textStyle()
  if options.fontSize > 0.0'f32:
    style.fontSize = options.fontSize
  manager.textStyle = style
  manager.alignment = textView.xAlignment
  let
    snapshot = manager.layoutSnapshot()
    pageOptions = textView.normalizedPageOptions(
      TextPageLayoutOptions(
        pageSize: options.pageOptions.pageSize,
        contentInsets: options.pageOptions.contentInsets,
        firstPageNumber: options.pageOptions.firstPageNumber,
        displayScale: scale,
      )
    )
  result = TextLayoutStabilitySnapshot(
    textHash: int(snapshot.textHash),
    layoutHash: int(snapshot.layoutHash),
    displayScale: scale,
    fontSize: style.fontSize,
    containerRect: snapshot.containerRect.roundRectToScale(scale),
    usedRect: snapshot.usedRect.roundRectToScale(scale),
    contentSize: initSize(
      snapshot.contentSize.width.roundToScale(scale),
      snapshot.contentSize.height.roundToScale(scale),
    ),
    pageFragments: paginateLineFragments(
      snapshot.lineFragments, snapshot.containerRect.origin.y, pageOptions
    ),
  )
  for fragment in snapshot.lineFragments:
    result.lineFragments.add fragment.roundLineFragmentToScale(scale)

proc drawTextViewContents*(textView: TextView, context: DrawContext) =
  textView.updateTextContainer()
  let
    textRect = textView.bounds.inset(textView.xTextContainer.insets)
    layout = textLayout(
      textRect,
      textView.displayTextStorage(),
      textView.textStyle(),
      textView.alignment(),
      textView.xTextContainer.wraps,
    )
  for indicator in textView.xFindIndicators:
    if indicator.visible:
      let rects =
        if indicator.rects.len > 0:
          indicator.rects
        else:
          textView.xLayoutManager.selectionRects(indicator.range)
      for rect in rects:
        discard context.addRectangle(rect, indicator.color)
  for selected in textView.selectedRanges():
    if selected.length > 0:
      for rect in textView.xLayoutManager.selectionRects(selected):
        discard context.addRectangle(rect, textView.selectionColor())
  let selected = textView.textViewSelectedRange()
  discard context.addText(textRect, layout)
  if textView.editable and selected.length == 0 and textView.isFocused and
      textView.xInsertionPointVisible:
    context.addRectangle(
      textView.xLayoutManager.caretRect(textView.textViewInsertionPoint()),
      textView.insertionPointColor(),
    )

proc hasSelectedText(textView: TextView): bool =
  for range in textView.selectedRanges():
    if range.length > 0:
      return true

proc validateTextCommand*(textView: TextView, action: ActionSelector): bool =
  let actionName = $action.name
  if actionName.len == 0:
    return false
  if not textView.xDelegate.isNil:
    let validation = textView.xDelegate.trySendLocal(
      tvValidateCommand(), (textView: textView, action: action)
    )
    if validation.isSome:
      return validation.get()
  case actionName
  of "copy":
    textView.selectable and textView.hasSelectedText()
  of "cut":
    textView.editable and textView.hasSelectedText()
  of "paste":
    textView.editable
  of "undo":
    textView.allowsUndo and textView.xUndoStack.len > 0
  of "redo":
    textView.allowsUndo and textView.xRedoStack.len > 0
  of "deleteBackward", "deleteForward", "deleteWordBackward", "deleteWordForward",
      "deleteToBeginningOfLine", "deleteToEndOfLine", "insertText", "insertLineBreak",
      "insertParagraphSeparator", "insertNewlineIgnoringFieldEditor",
      "insertTabIgnoringFieldEditor":
    textView.editable
  of "insertNewline", "insertTab", "insertBacktab":
    textView.editable or textView.isFieldEditor
  of "selectText", "selectAll", "moveLeft", "moveRight", "moveUp", "moveDown",
      "moveWordLeft", "moveWordRight", "moveWordBackward", "moveWordForward",
      "moveToBeginningOfLine", "moveToEndOfLine", "moveToBeginningOfDocument",
      "moveToEndOfDocument", "moveLeftAndModifySelection",
      "moveRightAndModifySelection", "moveUpAndModifySelection",
      "moveDownAndModifySelection", "moveWordLeftAndModifySelection",
      "moveWordRightAndModifySelection", "moveWordBackwardAndModifySelection",
      "moveWordForwardAndModifySelection", "moveToBeginningOfLineAndModifySelection",
      "moveToEndOfLineAndModifySelection",
      "moveToBeginningOfDocumentAndModifySelection",
      "moveToEndOfDocumentAndModifySelection":
    textView.editable or textView.selectable
  of "complete":
    textView.editable
  of "openLink":
    textView.activeLinkForCommand().link.len > 0
  else:
    textView.respondsTo(action.name)

proc performTextInputCommand*(
    textView: TextView, selector: CommandSelector, sender: DynamicAgent = nil
): bool =
  let effectiveSender =
    if sender.isNil:
      DynamicAgent(textView)
    else:
      sender
  if textView.validateTextCommand(selector):
    result = textView.sendLocalIfHandled(selector, ActionArgs(sender: effectiveSender))
  emit textView.textCommandDispatched(selector, result)

protocol DefaultTextViewValidation of UserInterfaceValidations:
  method validateUserInterfaceItem(textView: TextView, args: ValidationArgs): bool =
    textView.validateTextCommand(args.action)

protocol DefaultTextViewCommandDispatch of ResponderCommandDispatchProtocol:
  method dispatchCommand(textView: TextView, args: TryToPerformArgs): bool =
    textView.performTextInputCommand(args.selector, args.sender)

protocol DefaultTextViewDrawing of ViewDrawingProtocol:
  method draw(textView: TextView, context: DrawContext) =
    textView.drawTextViewContents(context)

protocol DefaultTextViewEvents of ResponderEventProtocol:
  method mouseDown(textView: TextView, event: MouseEvent): bool =
    if event.button == mbPrimary and (textView.editable or textView.selectable):
      if textView.clickTextAtPoint(event.location):
        return true
      textView.xSelectingWithMouse = true
      let index = textView.textIndexAtPoint(event.location)
      if textView.xSelectionGranularity == tsgCharacter:
        textView.setCursor(index)
      else:
        textView.selectRange(index, textView.xSelectionGranularity)
      return true

  method mouseDragged(textView: TextView, event: MouseEvent): bool =
    if event.button == mbPrimary and textView.xSelectingWithMouse and
        (textView.editable or textView.selectable):
      textView.setCursor(textView.textIndexAtPoint(event.location), extending = true)
      return true

  method mouseUp(textView: TextView, event: MouseEvent): bool =
    if event.button == mbPrimary and textView.xSelectingWithMouse:
      textView.xSelectingWithMouse = false
      return true

  method keyDown(textView: TextView, event: KeyEvent): bool =
    if textView.editable and event.shouldInsertText():
      textView.insertTextValue(event.text)
      return true

protocol DefaultTextViewDraggingSource of DraggingSourceProtocol:
  method draggingSourceOperationMask(
      textView: TextView, info: DraggingInfo
  ): DragOperations =
    info.allowedOperations * {dgoCopy, dgoMove}

  method draggingSessionEnded(textView: TextView, info: DraggingInfo) =
    if textView.xDraggingSession == info.session:
      textView.xDraggingSession = nil

  method writePromisedFile(
      textView: TextView, request: DraggingPromisedFileRequest
  ): bool =
    discard textView
    if request.item.pasteboardItem.kind != pikNone:
      return request.session.pasteboard().setItem(
          PasteboardTypePromisedFile, request.item.pasteboardItem
        )
    false

protocol DefaultTextViewDraggingDestination of DraggingDestinationProtocol:
  method draggingEntered(textView: TextView, info: DraggingInfo): DragOperations =
    textView.acceptsTextDrop(info)

  method draggingUpdated(textView: TextView, info: DraggingInfo): DragOperations =
    textView.acceptsTextDrop(info)

  method prepareForDragOperation(textView: TextView, info: DraggingInfo): bool =
    textView.acceptsTextDrop(info) != NoDragOperations

  method performDragOperation(textView: TextView, info: DraggingInfo): bool =
    textView.performTextDrop(info)

method textViewInputHasMarkedText(textView: TextView): bool {.selector.} =
  textView.xHasMarkedText

method textViewInputMarkedRange(textView: TextView): TextRange {.selector.} =
  if textView.xHasMarkedText:
    textView.xMarkedRange
  else:
    initTextRange(0, 0)

method textViewInputSelectedRange(textView: TextView): TextRange {.selector.} =
  textView.textViewSelectedRange()

method textViewInputAttributedSubstringForRange(
    textView: TextView, range: TextRange
): AttributedString {.selector.} =
  if textView.xTextStorage.isNil:
    return newTextStorage()
  textView.xTextStorage.sliceTextStorage(textView.clampedRange(range))

method textViewInputValidAttributesForMarkedText(
    textView: TextView
): seq[string] {.selector.} =
  discard textView
  @ValidMarkedTextAttributes

method textViewInputFirstRectForCharacterRange(
    textView: TextView, range: TextRange
): Rect {.selector.} =
  let clamped = textView.clampedRange(range)
  if clamped.length > 0:
    let rects = textView.selectionRects(clamped)
    if rects.len > 0:
      return textView.rectToWindow(rects[0])
  textView.rectToWindow(textView.characterRect(int(clamped.location)))

method textViewInputCharacterIndexForPoint(
    textView: TextView, point: Point
): int {.selector.} =
  textView.textIndexAtPoint(textView.pointFromWindow(point))

method textViewOpenLinkCommand(textView: TextView, args: ActionArgs) {.selector.} =
  discard args
  let link = textView.activeLinkForCommand()
  if link.link.len > 0:
    discard textView.openLinkAtIndex(int(link.range.location))

proc installTextInputClientMethods(textView: TextView) =
  discard
    textView.addMethod(selectors.textInputHasMarkedText, textViewInputHasMarkedText)
  discard textView.addMethod(selectors.textInputMarkedRange, textViewInputMarkedRange)
  discard
    textView.addMethod(selectors.textInputSelectedRange, textViewInputSelectedRange)
  discard textView.addMethod(
    selectors.textInputAttributedSubstringForRange,
    textViewInputAttributedSubstringForRange,
  )
  discard textView.addMethod(
    selectors.textInputValidAttributesForMarkedText,
    textViewInputValidAttributesForMarkedText,
  )
  discard textView.addMethod(
    selectors.textInputFirstRectForCharacterRange,
    textViewInputFirstRectForCharacterRange,
  )
  discard textView.addMethod(
    selectors.textInputCharacterIndexForPoint, textViewInputCharacterIndexForPoint
  )
  discard textView.addMethod(selectors.openLink, textViewOpenLinkCommand)

protocol DefaultTextViewInput of TextInputProtocol:
  method insertText(textView: TextView, text: string) =
    if text.isInsertableText():
      textView.insertTextValue(text)

  method setMarkedText(
      textView: TextView, text: string, selectedRange, replacementRange: TextRange
  ) =
    textView.setMarkedTextValue(text, selectedRange, replacementRange)

  method unmarkText(textView: TextView) =
    textView.unmarkMarkedText()

protocol DefaultTextViewCommands of TextEditingCommandProtocol:
  method selectText(textView: TextView, args: ActionArgs) =
    textView.selectAllText()

  method selectAll(textView: TextView, args: ActionArgs) =
    textView.selectAllText()

  method copy(textView: TextView, args: ActionArgs) =
    discard textView.copyText()

  method cut(textView: TextView, args: ActionArgs) =
    discard textView.cutText()

  method paste(textView: TextView, args: ActionArgs) =
    discard textView.pasteText()

  method undo(textView: TextView, args: ActionArgs) =
    discard textView.undoText()

  method redo(textView: TextView, args: ActionArgs) =
    discard textView.redoText()

  method deleteBackward(textView: TextView, args: ActionArgs) =
    textView.deleteBackwardText()

  method deleteForward(textView: TextView, args: ActionArgs) =
    textView.deleteForwardText()

  method deleteWordBackward(textView: TextView, args: ActionArgs) =
    textView.deleteWordBackwardText()

  method deleteWordForward(textView: TextView, args: ActionArgs) =
    textView.deleteWordForwardText()

  method deleteToBeginningOfLine(textView: TextView, args: ActionArgs) =
    textView.deleteToBeginningOfLineText()

  method deleteToEndOfLine(textView: TextView, args: ActionArgs) =
    textView.deleteToEndOfLineText()

  method insertLineBreak(textView: TextView, args: ActionArgs) =
    textView.insertLineBreakText()

  method insertParagraphSeparator(textView: TextView, args: ActionArgs) =
    textView.insertParagraphSeparatorText()

  method moveLeft(textView: TextView, args: ActionArgs) =
    textView.moveLeftText()

  method moveRight(textView: TextView, args: ActionArgs) =
    textView.moveRightText()

  method moveUp(textView: TextView, args: ActionArgs) =
    textView.moveUpText()

  method moveDown(textView: TextView, args: ActionArgs) =
    textView.moveDownText()

  method moveWordLeft(textView: TextView, args: ActionArgs) =
    textView.moveWordLeftText()

  method moveWordRight(textView: TextView, args: ActionArgs) =
    textView.moveWordRightText()

  method moveWordBackward(textView: TextView, args: ActionArgs) =
    textView.moveWordLeftText()

  method moveWordForward(textView: TextView, args: ActionArgs) =
    textView.moveWordRightText()

  method moveToBeginningOfLine(textView: TextView, args: ActionArgs) =
    textView.moveToBeginningOfLineText()

  method moveToEndOfLine(textView: TextView, args: ActionArgs) =
    textView.moveToEndOfLineText()

  method moveToBeginningOfDocument(textView: TextView, args: ActionArgs) =
    textView.moveToBeginningOfDocumentText()

  method moveToEndOfDocument(textView: TextView, args: ActionArgs) =
    textView.moveToEndOfDocumentText()

  method moveLeftAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveLeftText(extending = true)

  method moveRightAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveRightText(extending = true)

  method moveUpAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveUpText(extending = true)

  method moveDownAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveDownText(extending = true)

  method moveWordLeftAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveWordLeftText(extending = true)

  method moveWordRightAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveWordRightText(extending = true)

  method moveWordBackwardAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveWordLeftText(extending = true)

  method moveWordForwardAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveWordRightText(extending = true)

  method moveToBeginningOfLineAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveToBeginningOfLineText(extending = true)

  method moveToEndOfLineAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveToEndOfLineText(extending = true)

  method moveToBeginningOfDocumentAndModifySelection(
      textView: TextView, args: ActionArgs
  ) =
    textView.moveToBeginningOfDocumentText(extending = true)

  method moveToEndOfDocumentAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveToEndOfDocumentText(extending = true)

protocol DefaultTextViewKeyCommands of KeyViewCommandProtocol:
  method insertNewline(textView: TextView, args: ActionArgs) =
    textView.insertTextValue("\n")

  method insertTab(textView: TextView, args: ActionArgs) =
    textView.insertTextValue("\t")

  method insertBacktab(textView: TextView, args: ActionArgs) =
    textView.insertTextValue("\t")

  method insertNewlineIgnoringFieldEditor(textView: TextView, args: ActionArgs) =
    textView.insertTextValue("\n")

  method insertTabIgnoringFieldEditor(textView: TextView, args: ActionArgs) =
    textView.insertTextValue("\t")

protocol DefaultTextViewMenuCommands of MenuCommandProtocol:
  method openLink(textView: TextView, args: ActionArgs) =
    discard args
    let link = textView.activeLinkForCommand()
    if link.link.len > 0:
      discard textView.openLinkAtIndex(int(link.range.location))

  method complete(textView: TextView, args: ActionArgs) =
    discard args
    let panel = textView.completeText()
    if panel.visible and panel.completions.len == 1:
      discard textView.acceptCompletion(0)

protocol DefaultTextViewLayoutClient of TextLayoutClientProtocol:
  method textLayoutStorage(
      textView: TextView, manager: TextLayoutManager
  ): TextStorage =
    discard manager
    textView.xTextStorage

  method textLayoutContainer(
      textView: TextView, manager: TextLayoutManager
  ): TextContainer =
    discard manager
    textView.xTextContainer

  method textLayoutStyle(textView: TextView, manager: TextLayoutManager): TextStyle =
    discard manager
    textView.textStyle()

  method textLayoutAlignment(
      textView: TextView, manager: TextLayoutManager
  ): TextAlignment =
    discard manager
    textView.xAlignment

protocol DefaultTextViewLayoutEventSlots of TextLayoutEvents:
  proc layoutDidInvalidate(textView: TextView, ranges: seq[TextRange]) {.slot.} =
    discard ranges
    textView.setNeedsDisplay(true)

  proc containersDidChange(
      textView: TextView, containers: seq[TextContainer]
  ) {.slot.} =
    discard containers
    textView.invalidateIntrinsicContentSize()
    textView.setNeedsDisplay(true)

  proc containerDidInvalidate(
      textView: TextView, index: TextContainerIndex, container: TextContainer
  ) {.slot.} =
    discard index
    discard container
    textView.invalidateIntrinsicContentSize()
    textView.setNeedsDisplay(true)

  proc layoutGeometryDidChange(
      textView: TextView,
      oldUsedRect: Rect,
      oldContentSize: Size,
      snapshot: TextLayoutSnapshot,
  ) {.slot.} =
    discard oldUsedRect
    discard oldContentSize
    discard snapshot
    textView.invalidateIntrinsicContentSize()
    textView.setNeedsDisplay(true)

func accessibilityColorValue(color: Color): string =
  $color.r & "," & $color.g & "," & $color.b & "," & $color.a

func accessibilityAttributesFor(
    attributes: TextAttributes
): seq[AccessibilityTextAttribute] =
  result.add initAccessibilityTextAttribute(
    "foregroundColor", attributes.foregroundColor.accessibilityColorValue()
  )
  result.add initAccessibilityTextAttribute("fontSize", $attributes.fontSize)
  if attributes.fontName.len > 0:
    result.add initAccessibilityTextAttribute("fontName", attributes.fontName)
  if not attributes.language.isAutomatic:
    result.add initAccessibilityTextAttribute("language", $attributes.language)
  if attributes.hasBackgroundColor:
    result.add initAccessibilityTextAttribute(
      "backgroundColor", attributes.backgroundColor.accessibilityColorValue()
    )
  if attributes.hasLink:
    result.add initAccessibilityTextAttribute("link", attributes.link)
  if attributes.hasAttachment:
    if attributes.attachment.identifier.len > 0:
      result.add initAccessibilityTextAttribute(
        "attachmentIdentifier", attributes.attachment.identifier
      )
    if attributes.attachment.fileName.len > 0:
      result.add initAccessibilityTextAttribute(
        "attachmentFileName", attributes.attachment.fileName
      )
    if attributes.attachment.contentType.len > 0:
      result.add initAccessibilityTextAttribute(
        "attachmentContentType", attributes.attachment.contentType
      )
  if attributes.hasUnderline:
    result.add initAccessibilityTextAttribute("underline", $attributes.underlineStyle)
  if attributes.hasStrikethrough:
    result.add initAccessibilityTextAttribute(
      "strikethrough", $attributes.strikethroughStyle
    )

proc accessibilityAttributedText(
    storage: TextStorage, range: TextRange
): AccessibilityAttributedString =
  let
    start = max(0, min(int(range.location), storage.len))
    clamped = initTextRange(start, max(0, min(int(range.length), storage.len - start)))
    slice = storage.sliceTextStorage(clamped)
  var runs: seq[AccessibilityTextAttributeRun]
  for run in slice.runs:
    runs.add initAccessibilityTextAttributeRun(
      run.range.toAccessibilityTextRange(), accessibilityAttributesFor(run.attributes)
    )
  initAccessibilityAttributedString(slice.stringValue(), runs)

protocol DefaultTextViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(textView: TextView): AccessibilityRole =
    arTextArea

  method accessibilityLabel(textView: TextView): string =
    if textView.xAccessibilityLabel.len > 0:
      textView.xAccessibilityLabel
    else:
      textView.identifier()

  method accessibilityValue(textView: TextView): string =
    textView.stringValue()

  method accessibilityTraits(textView: TextView): AccessibilityTraits =
    result = textView.xAccessibilityTraits
    if textView.focused():
      result.incl atFocused
    if textView.editable():
      result.incl atEditable
    if textView.selectable():
      result.incl atSelectable

  method isAccessibilityElement(textView: TextView): bool =
    true

  method accessibilityTextLength(textView: TextView): int =
    if textView.xTextStorage.isNil: 0 else: textView.xTextStorage.len

  method accessibilitySelectedTextRange(textView: TextView): AccessibilityTextRange =
    textView.textViewSelectedRange().toAccessibilityTextRange()

  method accessibilitySelectedTextRanges(
      textView: TextView
  ): seq[AccessibilityTextRange] =
    for range in textView.selectedRanges():
      result.add range.toAccessibilityTextRange()

  method accessibilityVisibleCharacterRange(
      textView: TextView
  ): AccessibilityTextRange =
    textView.visibleCharacterRange().toAccessibilityTextRange()

  method setAccessibilitySelectedTextRange(
      textView: TextView, range: AccessibilityTextRange
  ): bool =
    if (not textView.editable() and not textView.selectable()):
      return false
    textView.setTextViewSelectedRange(range.toTextRange())
    true

  method accessibilityInsertionPoint(textView: TextView): int =
    textView.textViewInsertionPoint()

  method accessibilityInsertionPointLine(textView: TextView): int =
    textView.lineForIndex(textView.textViewInsertionPoint())

  method setAccessibilityInsertionPoint(textView: TextView, index: int): bool =
    if (not textView.editable() and not textView.selectable()):
      return false
    textView.setCursor(index)
    true

  method accessibilityAttributedStringForRange(
      textView: TextView, range: AccessibilityTextRange
  ): AccessibilityAttributedString =
    textView.xTextStorage.accessibilityAttributedText(range.toTextRange())

  method accessibilityBoundsForTextRange(
      textView: TextView, range: AccessibilityTextRange
  ): seq[Rect] =
    for rect in textView.selectionRects(range.toTextRange()):
      result.add textView.rectToWindow(rect)

  method accessibilityBoundsForCharacter(textView: TextView, index: int): Rect =
    textView.rectToWindow(textView.characterRect(index))

  method accessibilityCharacterIndexAtPoint(textView: TextView, point: Point): int =
    int(
      textView
      .layoutManager()
      .textRangeAtPoint(textView.pointFromWindow(point)).location
    )

  method accessibilityLineRange(textView: TextView, line: int): AccessibilityTextRange =
    textView.lineRange(line).toAccessibilityTextRange()

  method accessibilityLineForCharacter(textView: TextView, index: int): int =
    textView.lineForIndex(index)

  method accessibilityBoundsForLine(textView: TextView, line: int): Rect =
    textView.rectToWindow(textView.lineBounds(line))

proc initTextViewFields*(
    textView: TextView,
    value = "",
    frame: Rect = AutoRect,
    installDefaultProtocols = true,
) =
  initViewFields(textView, frame)
  textView.xTextStorage = newTextStorage(value)
  textView.xTextContainer =
    initTextContainer(widthTracksTextView = true, heightTracksTextView = true)
  textView.xLayoutManager =
    newTextLayoutManager(textView.xTextStorage, textView.xTextContainer)
  textView.xFlags = {tvEditable, tvSelectable, tvRichText, tvAllowsUndo}
  textView.xAlignment = taLeft
  textView.xInsertionPoint = textView.xTextStorage.len
  textView.xSelectionAnchor = textView.xInsertionPoint
  textView.xSelectionAffinity = taDownstream
  textView.xSelectionGranularity = tsgCharacter
  textView.xSelectedRanges = @[initTextRange(textView.xInsertionPoint, 0)]
  textView.xTextColor = color(0.0, 0.0, 0.0, 0.0)
  textView.xSelectionColor = color(0.24, 0.56, 1.0, 0.34)
  textView.xTypingAttributes = defaultTextAttributes()
  textView.xSelectedTextAttributes = defaultTextAttributes(color(1.0, 1.0, 1.0, 1.0))
  textView.xInsertionPointVisible = true
  textView.xInsertionPointBlinkPeriod = 1.0'f32
  textView.xMarkedTextAttributes = defaultTextAttributes()
  textView.xMarkedTextAttributes.underline = true
  textView.xMarkedTextAttributes.underlineStyle = tldsSingle
  textView.xDefaultParagraphStyle = initTextParagraphStyle()
  textView.xCompletionPanel = TextCompletionPanel(selectedIndex: -1)
  textView.setAcceptsFirstResponder(true)
  discard textView.withProtocol(DefaultTextViewLayoutClient)
  discard textView.withProtocol(DefaultTextViewLayoutEventSlots)
  discard textView.withProtocol(DefaultTextViewAccessibility)
  discard textView.withProtocol(DefaultTextViewCommandDispatch)
  discard textView.withProtocol(DefaultTextViewDraggingSource)
  discard textView.withProtocol(DefaultTextViewDraggingDestination)
  textView.installTextInputClientMethods()
  textView.registerForDraggedTypes(
    [
      PasteboardTypeTextStorage, PasteboardTypeAttributedText, PasteboardTypeString,
      PasteboardTypePlainText,
    ]
  )
  textView.observeProtocol(textView.xLayoutManager, TextLayoutEvents)
  textView.xLayoutManager.layoutClient = DynamicAgent(textView)
  if installDefaultProtocols:
    discard textView.withProtocol(DefaultTextViewDrawing)
    discard textView.withProtocol(DefaultTextViewEvents)
    discard textView.withProtocol(DefaultTextViewInput)
    discard textView.withProtocol(DefaultTextViewCommands)
    discard textView.withProtocol(DefaultTextViewKeyCommands)
    discard textView.withProtocol(DefaultTextViewMenuCommands)
    discard textView.withProtocol(DefaultTextViewValidation)
  textView.applyInitialFrame(frame)

proc newTextView*(value = "", frame: Rect = AutoRect): TextView =
  result = TextView()
  initTextViewFields(result, value, frame)
