import std/[options, strutils, unicode]

import sigils/core

import ../accessibility/accessibility
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
    xSelectionColor: Color
    xTypingAttributes: TextAttributes
    xSelectedTextAttributes: TextAttributes
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

proc syncLayout(textView: TextView)
proc clearMarkedText(textView: TextView)
proc textViewStringValue(textView: TextView): string
proc setTextViewStringValue(textView: TextView, value: string)
proc textViewSelectedRange(textView: TextView): TextRange
proc setTextViewSelectedRange(textView: TextView, value: TextRange)
proc textViewInsertionPoint(textView: TextView): int
proc textViewSelectionAnchor(textView: TextView): int
proc updateTextContainer(textView: TextView)
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
proc moveLeftText*(textView: TextView, extending = false)
proc moveRightText*(textView: TextView, extending = false)
proc moveUpText*(textView: TextView, extending = false)
proc moveDownText*(textView: TextView, extending = false)
proc moveWordLeftText*(textView: TextView, extending = false)
proc moveWordRightText*(textView: TextView, extending = false)
proc moveToBeginningOfLineText*(textView: TextView, extending = false)
proc moveToEndOfLineText*(textView: TextView, extending = false)
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
  if not textView.isNil:
    textView.dispatchSelectionChanged(@[before])

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
  if textView.isNil:
    return initTextRange(0, 0)
  let line = textView.lineForIndex(index)
  textView.lineRange(line)

proc paragraphRangeAtIndex(textView: TextView, index: int): TextRange =
  if textView.isNil:
    return initTextRange(0, 0)
  textView.xTextStorage.paragraphRangeForRange(initTextRange(index, 0))

proc selectionRangeForGranularity(
    textView: TextView, index: int, granularity: TextSelectionGranularity
): TextRange =
  if textView.isNil:
    return initTextRange(0, 0)
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
  if textView.isNil: nil else: textView.xTextStorage

proc `textStorage=`*(textView: TextView, storage: TextStorage) =
  if textView.isNil:
    return
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
  if textView.isNil: nil else: textView.xLayoutManager

proc textContainer*(textView: TextView): TextContainer =
  if textView.isNil:
    initTextContainer()
  else:
    textView.xTextContainer

proc `textContainer=`*(textView: TextView, container: TextContainer) =
  if textView.isNil:
    return
  textView.xTextContainer = container
  textView.syncLayout()
  textView.setNeedsDisplay(true)

proc textViewStringValue(textView: TextView): string =
  if textView.isNil:
    ""
  else:
    textView.xTextStorage.stringValue()

proc setTextViewStringValue(textView: TextView, value: string) =
  if textView.isNil:
    return
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
  textView.clearMarkedText()
  textView.finishTextMutation(initTextRange(0, total))
  textView.dispatchSelectionChanged(previousRanges)

proc editable*(textView: TextView): bool =
  (not textView.isNil) and tvEditable in textView.xFlags

proc `editable=`*(textView: TextView, editable: bool) =
  if textView.isNil or editable == textView.editable:
    return
  if editable:
    textView.xFlags.incl tvEditable
  else:
    textView.xFlags.excl tvEditable
  textView.setAcceptsFirstResponder(
    tvEditable in textView.xFlags or tvSelectable in textView.xFlags
  )

proc selectable*(textView: TextView): bool =
  (not textView.isNil) and tvSelectable in textView.xFlags

proc `selectable=`*(textView: TextView, selectable: bool) =
  if textView.isNil or selectable == textView.selectable:
    return
  if selectable:
    textView.xFlags.incl tvSelectable
  else:
    textView.xFlags.excl tvSelectable
  textView.setAcceptsFirstResponder(
    tvEditable in textView.xFlags or tvSelectable in textView.xFlags
  )

proc richText*(textView: TextView): bool =
  (not textView.isNil) and tvRichText in textView.xFlags

proc `richText=`*(textView: TextView, richText: bool) =
  if textView.isNil or richText == textView.richText:
    return
  if richText:
    textView.xFlags.incl tvRichText
  else:
    textView.xFlags.excl tvRichText

proc isFieldEditor*(textView: TextView): bool =
  (not textView.isNil) and tvFieldEditor in textView.xFlags

proc `fieldEditor=`*(textView: TextView, fieldEditor: bool) =
  if textView.isNil or fieldEditor == textView.isFieldEditor:
    return
  if fieldEditor:
    textView.xFlags.incl tvFieldEditor
  else:
    textView.xFlags.excl tvFieldEditor

proc allowsUndo*(textView: TextView): bool =
  (not textView.isNil) and tvAllowsUndo in textView.xFlags

proc `allowsUndo=`*(textView: TextView, allowsUndo: bool) =
  if textView.isNil or allowsUndo == textView.allowsUndo:
    return
  if allowsUndo:
    textView.xFlags.incl tvAllowsUndo
  else:
    textView.xFlags.excl tvAllowsUndo
    textView.xUndoStack.setLen(0)
    textView.xRedoStack.setLen(0)

proc delegate*(textView: TextView): DynamicAgent =
  if textView.isNil: nil else: textView.xDelegate

proc `delegate=`*(textView: TextView, delegate: DynamicAgent) =
  if not textView.isNil:
    textView.xDelegate = delegate

proc textChecker*(textView: TextView): DynamicAgent =
  if textView.isNil: nil else: textView.xTextChecker

proc `textChecker=`*(textView: TextView, checker: DynamicAgent) =
  if not textView.isNil:
    textView.xTextChecker = checker

proc alignment*(textView: TextView): TextAlignment =
  if textView.isNil: taLeft else: textView.xAlignment

proc `alignment=`*(textView: TextView, alignment: TextAlignment) =
  if textView.isNil or textView.xAlignment == alignment:
    return
  textView.xAlignment = alignment
  textView.syncLayout()
  textView.setNeedsDisplay(true)

proc textColor*(textView: TextView): Color =
  if textView.isNil:
    initColor(0.08, 0.09, 0.11)
  elif textView.xTextColor.a > 0.0:
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
        controlStyle(srTextView), initColor(0.08, 0.09, 0.11), insets(0.0)
      )
  let role = if textView.isFieldEditor: srTextField else: srTextView
  result = textView.effectiveAppearance().resolveTextStyle(
      controlStyle(
        role,
        textView.widgetStateSet(),
        id = textView.styleId,
        classes = textView.styleClasses,
      ),
      initColor(0.08, 0.09, 0.11),
      insets(0.0),
    )
  if textView.xTextColor.a > 0.0:
    result.color = textView.xTextColor

proc `textColor=`*(textView: TextView, color: Color) =
  if textView.isNil or textView.xTextColor == color:
    return
  textView.xTextColor = color
  let style = textView.textStyle()
  textView.xTypingAttributes = defaultTextAttributes(style.color, style.fontSize)
  textView.setNeedsDisplay(true)

proc selectionColor*(textView: TextView): Color =
  if textView.isNil:
    initColor(0.24, 0.56, 1.0, 0.34)
  else:
    textView.xSelectionColor

proc `selectionColor=`*(textView: TextView, color: Color) =
  if textView.isNil or textView.xSelectionColor == color:
    return
  textView.xSelectionColor = color
  textView.setNeedsDisplay(true)

proc selectedTextAttributes*(textView: TextView): TextAttributes =
  if textView.isNil or not textView.xHasSelectedTextAttributes:
    defaultTextAttributes(initColor(1.0, 1.0, 1.0, 1.0))
  else:
    textView.xSelectedTextAttributes

proc `selectedTextAttributes=`*(textView: TextView, attributes: TextAttributes) =
  if textView.isNil:
    return
  textView.xSelectedTextAttributes = attributes
  textView.xHasSelectedTextAttributes = true
  textView.setNeedsDisplay(true)

proc clearSelectedTextAttributes*(textView: TextView) =
  if textView.isNil:
    return
  textView.xHasSelectedTextAttributes = false
  textView.setNeedsDisplay(true)

proc typingAttributes*(textView: TextView): TextAttributes =
  if textView.isNil:
    defaultTextAttributes()
  else:
    textView.xTypingAttributes

proc `typingAttributes=`*(textView: TextView, attributes: TextAttributes) =
  if textView.isNil or textView.xTypingAttributes == attributes:
    return
  textView.xTypingAttributes = attributes

proc insertionPointColor*(textView: TextView): Color =
  if textView.isNil:
    initColor(0.08, 0.09, 0.11, 1.0)
  elif textView.xInsertionPointColor.a > 0.0:
    textView.xInsertionPointColor
  else:
    textView.textColor()

proc `insertionPointColor=`*(textView: TextView, color: Color) =
  if textView.isNil or textView.xInsertionPointColor == color:
    return
  textView.xInsertionPointColor = color
  textView.setNeedsDisplay(true)

proc insertionPointVisible*(textView: TextView): bool =
  (not textView.isNil) and textView.xInsertionPointVisible

proc `insertionPointVisible=`*(textView: TextView, visible: bool) =
  if textView.isNil or textView.xInsertionPointVisible == visible:
    return
  textView.xInsertionPointVisible = visible
  textView.setNeedsDisplay(true)

proc insertionPointBlinkPeriod*(textView: TextView): float32 =
  if textView.isNil: 0.5'f32 else: textView.xInsertionPointBlinkPeriod

proc `insertionPointBlinkPeriod=`*(textView: TextView, period: float32) =
  if textView.isNil:
    return
  textView.xInsertionPointBlinkPeriod = max(period, 0.0'f32)

proc markedTextAttributes*(textView: TextView): TextAttributes =
  if textView.isNil:
    defaultTextAttributes()
  else:
    textView.xMarkedTextAttributes

proc `markedTextAttributes=`*(textView: TextView, attributes: TextAttributes) =
  if textView.isNil or textView.xMarkedTextAttributes == attributes:
    return
  textView.xMarkedTextAttributes = attributes
  textView.setNeedsDisplay(true)

proc selectionAffinity*(textView: TextView): TextAffinity =
  if textView.isNil: taDownstream else: textView.xSelectionAffinity

proc `selectionAffinity=`*(textView: TextView, affinity: TextAffinity) =
  if not textView.isNil:
    textView.xSelectionAffinity = affinity

proc selectionGranularity*(textView: TextView): TextSelectionGranularity =
  if textView.isNil: tsgCharacter else: textView.xSelectionGranularity

proc `selectionGranularity=`*(
    textView: TextView, granularity: TextSelectionGranularity
) =
  if textView.isNil or textView.xSelectionGranularity == granularity:
    return
  textView.xSelectionGranularity = granularity

proc allowsMultipleSelectedRanges*(textView: TextView): bool =
  (not textView.isNil) and textView.xAllowsMultipleSelectedRanges

proc `allowsMultipleSelectedRanges=`*(textView: TextView, value: bool) =
  if textView.isNil or textView.xAllowsMultipleSelectedRanges == value:
    return
  textView.xAllowsMultipleSelectedRanges = value
  if not value and textView.xSelectedRanges.len > 1:
    textView.setTextViewSelectedRange(textView.xSelectedRanges[0])

proc allowsRectangularSelection*(textView: TextView): bool =
  (not textView.isNil) and textView.xAllowsRectangularSelection

proc `allowsRectangularSelection=`*(textView: TextView, value: bool) =
  if textView.isNil:
    return
  textView.xAllowsRectangularSelection = value
  if not value:
    textView.xRectangularSelection = TextRectSelection()

proc rectangularSelection*(textView: TextView): TextRectSelection =
  if textView.isNil:
    TextRectSelection()
  else:
    textView.xRectangularSelection

proc findIndicators*(textView: TextView): seq[TextFindIndicator] =
  if textView.isNil:
    @[]
  else:
    textView.xFindIndicators

proc checkingResults*(textView: TextView): seq[TextCheckingResult] =
  if textView.isNil:
    @[]
  else:
    textView.xCheckingResults

proc completionPanel*(textView: TextView): TextCompletionPanel =
  if textView.isNil:
    TextCompletionPanel(selectedIndex: -1)
  else:
    textView.xCompletionPanel

proc substitutionOptions*(textView: TextView): TextSubstitutionOptions =
  if textView.isNil:
    {}
  else:
    textView.xSubstitutionOptions

proc `substitutionOptions=`*(textView: TextView, options: TextSubstitutionOptions) =
  if not textView.isNil:
    textView.xSubstitutionOptions = options

proc smartInsertDeleteEnabled*(textView: TextView): bool =
  (not textView.isNil) and textView.xSmartInsertDelete

proc `smartInsertDeleteEnabled=`*(textView: TextView, enabled: bool) =
  if not textView.isNil:
    textView.xSmartInsertDelete = enabled

proc defaultParagraphStyle*(textView: TextView): TextParagraphStyle =
  if textView.isNil:
    initTextParagraphStyle()
  else:
    textView.xDefaultParagraphStyle

proc `defaultParagraphStyle=`*(textView: TextView, style: TextParagraphStyle) =
  if textView.isNil:
    return
  textView.xDefaultParagraphStyle = style
  textView.xTypingAttributes.paragraphStyle = style

proc usesRuler*(textView: TextView): bool =
  (not textView.isNil) and textView.xUsesRuler

proc `usesRuler=`*(textView: TextView, value: bool) =
  if textView.isNil:
    return
  textView.xUsesRuler = value
  if not value:
    textView.xRulerVisible = false

proc rulerVisible*(textView: TextView): bool =
  (not textView.isNil) and textView.xUsesRuler and textView.xRulerVisible

proc `rulerVisible=`*(textView: TextView, value: bool) =
  if textView.isNil:
    return
  textView.xRulerVisible = value and textView.xUsesRuler

proc hasMarkedText*(textView: TextView): bool =
  (not textView.isNil) and textView.xHasMarkedText

proc markedRange*(textView: TextView): TextRange =
  if textView.hasMarkedText:
    textView.xMarkedRange
  else:
    initTextRange(0, 0)

proc textViewInsertionPoint(textView: TextView): int =
  if textView.isNil: 0 else: textView.xInsertionPoint

proc textViewSelectionAnchor(textView: TextView): int =
  if textView.isNil: 0 else: textView.xSelectionAnchor

proc updateTypingAttributesForSelection(textView: TextView) =
  if textView.isNil or textView.xTextStorage.len == 0:
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
  if textView.isNil:
    return initTextRange(0, 0)
  if textView.xSelectedRanges.len > 0:
    return textView.xSelectedRanges[0]
  let
    start = min(textView.xSelectionAnchor, textView.xInsertionPoint)
    stop = max(textView.xSelectionAnchor, textView.xInsertionPoint)
  initTextRange(start, stop - start)

proc normalizedSelectedRanges(
    textView: TextView, ranges: openArray[TextRange]
): seq[TextRange] =
  if textView.isNil:
    return
  for range in ranges:
    result.add textView.clampedRange(range)
    if not textView.xAllowsMultipleSelectedRanges:
      break
  if result.len == 0:
    result.add initTextRange(textView.xInsertionPoint, 0)

proc setTextViewSelectedRange(textView: TextView, value: TextRange) =
  if textView.isNil:
    return
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
  if textView.isNil:
    return @[]
  if textView.xSelectedRanges.len == 0:
    @[textView.textViewSelectedRange()]
  else:
    textView.xSelectedRanges

proc setSelectedRanges*(textView: TextView, ranges: openArray[TextRange]) =
  if textView.isNil:
    return
  let nextRanges = textView.normalizedSelectedRanges(ranges)
  if nextRanges.len == 0:
    return
  let previousRanges = textView.selectedRanges()
  textView.xSelectedRanges = nextRanges
  textView.xSelectionAnchor = int(nextRanges[0].location)
  textView.xInsertionPoint = nextRanges[0].maxIndex
  textView.updateTypingAttributesForSelection()
  textView.setNeedsDisplay(true)
  textView.dispatchSelectionChanged(previousRanges)

proc `selectedRanges=`*(textView: TextView, ranges: seq[TextRange]) =
  textView.setSelectedRanges(ranges)

proc selectRange*(textView: TextView, index: int, granularity = tsgCharacter) =
  if textView.isNil:
    return
  textView.setTextViewSelectedRange(
    textView.selectionRangeForGranularity(index, granularity)
  )

proc setRectangularSelection*(
    textView: TextView, anchor, focus: Point
): TextRectSelection =
  if textView.isNil or not textView.xAllowsRectangularSelection:
    return TextRectSelection()
  let
    x0 = min(anchor.x, focus.x)
    y0 = min(anchor.y, focus.y)
    x1 = max(anchor.x, focus.x)
    y1 = max(anchor.y, focus.y)
    bounds = initRect(x0, y0, x1 - x0, y1 - y0)
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
  if textView.isNil:
    return initTextRange(0, 0)
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
  textView.dispatchSelectionChanged(previousRanges)

proc clearMarkedText(textView: TextView) =
  if textView.isNil:
    return
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
  if textView.isNil or textView.xApplyingUndo or not textView.allowsUndo:
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
  if textView.isNil:
    return
  inc textView.xUndoGroupingDepth

proc endUndoGrouping*(textView: TextView) =
  if textView.isNil or textView.xUndoGroupingDepth == 0:
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
  if textView.isNil:
    return false
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
  if textView.isNil or not textView.xEditing:
    return
  textView.xEditing = false
  emit textView.textEditingDidEnd()
  if not textView.xDelegate.isNil:
    discard textView.xDelegate.trySendLocal(tvDidEndEdit(), textView)

proc shouldChangeText(
    textView: TextView, range: TextRange, replacement: TextStorage
): bool =
  if textView.isNil:
    return false
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
  if textView.isNil or not textView.editable:
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
  if textView.isNil:
    return
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
  if textView.isNil or not textView.xSmartInsertDelete or insertion.len == 0:
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
    color = initColor(1.0, 0.82, 0.24, 0.45),
) =
  if textView.isNil:
    return
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
  if textView.isNil or textView.xFindIndicators.len == 0:
    return
  textView.xFindIndicators.setLen(0)
  textView.setNeedsDisplay(true)

proc findTextRanges*(
    textView: TextView, needle: string, caseSensitive = true
): seq[TextRange] =
  if textView.isNil or needle.len == 0:
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
  if textView.isNil or not textView.editable:
    return false
  let ranges = textView.findTextRanges(needle, caseSensitive)
  if ranges.len == 0:
    return false
  textView.replaceRange(ranges[0], replacement, textView.xTypingAttributes)
  true

proc replaceAllText*(
    textView: TextView, needle, replacement: string, caseSensitive = true
): int =
  if textView.isNil or not textView.editable:
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
  if textView.isNil:
    return
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
  if textView.isNil:
    return
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
  if textView.isNil:
    return
  textView.checkText(initTextRange(0, textView.xTextStorage.len))

proc clearTextCheckingResults*(textView: TextView) =
  if textView.isNil or textView.xCheckingResults.len == 0:
    return
  textView.xCheckingResults.setLen(0)
  textView.setNeedsDisplay(true)

proc applyTextCheckingResults*(
    textView: TextView, results: openArray[TextCheckingResult]
) =
  if textView.isNil or textView.xTextStorage.isNil:
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
  if textView.isNil:
    return initTextRange(0, 0)
  let selected = textView.textViewSelectedRange()
  if selected.length > 0:
    return selected
  textView.textViewStringValue().wordRangeAt(textView.xInsertionPoint)

proc completeText*(textView: TextView): TextCompletionPanel =
  if textView.isNil:
    return TextCompletionPanel(selectedIndex: -1)
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
  if textView.isNil:
    return
  textView.xCompletionPanel.visible = false
  textView.setNeedsDisplay(true)

proc acceptCompletion*(textView: TextView, index = -1): bool =
  if textView.isNil or not textView.editable or not textView.xCompletionPanel.visible:
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

proc linkRangeAtIndex(textView: TextView, index: int, link: string): TextRange =
  if textView.isNil or link.len == 0:
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
  if textView.isNil:
    return initTextRange(index, 0)
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

proc clickTextAtPoint*(textView: TextView, point: Point): bool =
  if textView.isNil:
    return false
  let index = textView.textIndexAtPoint(point)
  if index < 0 or index >= textView.xTextStorage.len:
    return false
  let attributes = textView.xTextStorage.attributesAt(index)
  if attributes.hasLink:
    let range = textView.linkRangeAtIndex(index, attributes.link)
    if textView.xDelegate.isNil:
      return true
    return textView.xDelegate
      .trySendLocal(
        tvClickedLink(), (textView: textView, link: attributes.link, range: range)
      )
      .get(true)
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
  if textView.isNil or textView.xTextStorage.len == 0:
    return textView.defaultParagraphStyle()
  textView.xTextStorage.attributesAt(index).paragraphStyle

proc setParagraphStyle*(
    textView: TextView, range: TextRange, style: TextParagraphStyle
) =
  if textView.isNil or textView.xTextStorage.isNil:
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
  if textView.isNil:
    return
  var style = textView.paragraphStyleAt(int(range.location))
  style.tabStops = @tabStops
  textView.setParagraphStyle(range, style)

proc displayTextStorage(textView: TextView): TextStorage =
  if textView.isNil:
    return newTextStorage()
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
      initTextRange(0, result.len), defaultTextAttributes(style.color, style.fontSize)
    )
  if hasMarkedOverlay:
    result.setAttributes(textView.xMarkedRange, textView.xMarkedTextAttributes)
  if hasSelectedOverlay:
    for range in textView.selectedRanges():
      if range.length > 0:
        result.setAttributes(range, textView.xSelectedTextAttributes)

proc syncLayout(textView: TextView) =
  if textView.isNil or textView.xLayoutManager.isNil:
    return
  textView.xLayoutManager.textStorage = textView.xTextStorage
  textView.xLayoutManager.textContainer = textView.xTextContainer
  textView.xLayoutManager.textStyle = textView.textStyle()
  textView.xLayoutManager.alignment = textView.xAlignment

proc setCursor*(textView: TextView, index: int, extending = false) =
  if textView.isNil:
    return
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
  textView.setNeedsDisplay(true)
  textView.dispatchSelectionChanged(previousRanges)

proc selectAllText*(textView: TextView) =
  if textView.isNil:
    return
  let previousRanges = textView.selectedRanges()
  textView.xSelectionAnchor = 0
  textView.xInsertionPoint = textView.xTextStorage.len
  textView.xSelectedRanges = @[initTextRange(0, textView.xTextStorage.len)]
  textView.updateTypingAttributesForSelection()
  textView.setNeedsDisplay(true)
  textView.dispatchSelectionChanged(previousRanges)

proc replaceSelectedText*(textView: TextView, insertion: string) =
  if textView.isNil or not textView.editable:
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
  if textView.isNil or not textView.editable:
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
  if textView.isNil or not textView.editable:
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
  if textView.isNil:
    return
  textView.clearMarkedText()
  textView.setNeedsDisplay(true)

proc copyText*(textView: TextView): bool =
  if textView.isNil or not textView.selectable:
    return false
  let selected = textView.textViewSelectedRange()
  if selected.length == 0:
    return false
  let pasteboard = generalPasteboard()
  pasteboard.declareTypes([PasteboardTypeTextStorage, PasteboardTypeString])
  discard pasteboard.setTextStorage(
    PasteboardTypeTextStorage, textView.xTextStorage.sliceTextStorage(selected)
  )
  discard pasteboard.setString(
    PasteboardTypeString, textView.xTextStorage.substring(selected)
  )
  true

proc cutText*(textView: TextView): bool =
  if textView.isNil or not textView.editable or not textView.copyText():
    return false
  textView.replaceSelectedText("")
  true

proc pasteText*(textView: TextView): bool =
  if textView.isNil or not textView.editable:
    return false
  let
    pasteboard = generalPasteboard()
    kind = pasteboard.availableTypeFromArray(
      [PasteboardTypeTextStorage, PasteboardTypeString]
    )
  case kind
  of PasteboardTypeTextStorage:
    let storage = pasteboard.textStorageForType(PasteboardTypeTextStorage)
    if storage.isNil:
      return false
    let selected =
      if textView.xHasMarkedText:
        textView.xMarkedRange
      else:
        textView.textViewSelectedRange()
    textView.replaceRange(selected, storage)
    true
  of PasteboardTypeString:
    textView.insertTextValue(pasteboard.stringForType(PasteboardTypeString))
    true
  else:
    false

proc applyUndoRecord(textView: TextView, storage: TextStorage, selection: TextRange) =
  textView.xApplyingUndo = true
  let changedRange = initTextRange(0, textView.xTextStorage.len)
  textView.xTextStorage = storage.copyTextStorage()
  textView.clearMarkedText()
  textView.setSelection(selection)
  textView.finishTextMutation(changedRange)
  textView.xApplyingUndo = false

proc undoText*(textView: TextView): bool =
  if textView.isNil or textView.xUndoStack.len == 0:
    return false
  let record = textView.xUndoStack.pop()
  textView.applyUndoRecord(record.storageBefore, record.selectionBefore)
  textView.xRedoStack.add record
  true

proc redoText*(textView: TextView): bool =
  if textView.isNil or textView.xRedoStack.len == 0:
    return false
  let record = textView.xRedoStack.pop()
  textView.applyUndoRecord(record.storageAfter, record.selectionAfter)
  textView.xUndoStack.add record
  true

proc deleteBackwardText*(textView: TextView) =
  if textView.isNil or not textView.editable:
    return
  let selected = textView.currentSelection()
  if selected.stop > selected.start:
    textView.replaceSelectedText("")
  elif selected.start > 0:
    textView.replaceRange(
      initTextRange(selected.start - 1, 1), "", textView.xTypingAttributes
    )

proc deleteForwardText*(textView: TextView) =
  if textView.isNil or not textView.editable:
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
  if textView.isNil or not textView.editable:
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
  if textView.isNil or not textView.editable:
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

proc moveLeftText*(textView: TextView, extending = false) =
  if textView.isNil or (not textView.editable and not textView.selectable):
    return
  let selected = textView.currentSelection()
  if selected.stop > selected.start and not extending:
    textView.setCursor(selected.start)
  else:
    textView.setCursor(textView.xInsertionPoint - 1, extending)

proc moveRightText*(textView: TextView, extending = false) =
  if textView.isNil or (not textView.editable and not textView.selectable):
    return
  let selected = textView.currentSelection()
  if selected.stop > selected.start and not extending:
    textView.setCursor(selected.stop)
  else:
    textView.setCursor(textView.xInsertionPoint + 1, extending)

proc moveVerticalText(textView: TextView, direction: int, extending = false) =
  if textView.isNil or (not textView.editable and not textView.selectable):
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
  if textView.isNil or (not textView.editable and not textView.selectable):
    return
  textView.setCursor(
    textView.textViewStringValue().previousWordBoundary(textView.xInsertionPoint),
    extending,
  )

proc moveWordRightText*(textView: TextView, extending = false) =
  if textView.isNil or (not textView.editable and not textView.selectable):
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
  if textView.isNil or (not textView.editable and not textView.selectable):
    return
  textView.setCursor(textView.currentVisualLineBounds().first, extending)

proc moveToEndOfLineText*(textView: TextView, extending = false) =
  if textView.isNil or (not textView.editable and not textView.selectable):
    return
  textView.setCursor(textView.currentVisualLineBounds().last, extending)

proc updateFieldEditorInsets(textView: TextView) =
  if textView.isNil or not textView.isFieldEditor:
    return
  let
    lineHeight = textNaturalSize("", textView.textStyle()).height
    extraHeight = max(textView.bounds.size.height - lineHeight, 0.0'f32)
    topInset = extraHeight / 2.0'f32
  textView.xTextContainer.insets.top = topInset
  textView.xTextContainer.insets.bottom = extraHeight - topInset

proc updateTextContainer(textView: TextView) =
  if textView.isNil:
    return
  if textView.xTextContainer.widthTracksTextView:
    textView.xTextContainer.size.width = textView.bounds.size.width
  if textView.xTextContainer.heightTracksTextView:
    textView.xTextContainer.size.height = textView.bounds.size.height
  textView.updateFieldEditorInsets()
  textView.syncLayout()

proc textIndexAtPoint*(textView: TextView, point: Point): int =
  if textView.isNil:
    return 0
  textView.updateTextContainer()
  textView.xLayoutManager.textIndexAtPoint(point)

proc selectionRects*(textView: TextView, range: TextRange): seq[Rect] =
  if textView.isNil:
    return
  textView.updateTextContainer()
  textView.xLayoutManager.selectionRects(range)

proc characterRect*(textView: TextView, index: int): Rect =
  if textView.isNil:
    return initRect(0, 0, 0, 0)
  textView.updateTextContainer()
  textView.xLayoutManager.characterRect(index)

proc lineRange*(textView: TextView, line: int): TextRange =
  if textView.isNil:
    return initTextRange(0, 0)
  textView.updateTextContainer()
  textView.xLayoutManager.lineRange(line)

proc lineForIndex*(textView: TextView, index: int): int =
  if textView.isNil:
    return -1
  textView.updateTextContainer()
  textView.xLayoutManager.lineForIndex(index)

proc lineBounds*(textView: TextView, line: int): Rect =
  if textView.isNil:
    return initRect(0, 0, 0, 0)
  textView.updateTextContainer()
  textView.xLayoutManager.lineBounds(line)

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
  if textView.isNil:
    return false
  for range in textView.selectedRanges():
    if range.length > 0:
      return true

proc validateTextCommand*(textView: TextView, action: ActionSelector): bool =
  let actionName = $action.name
  if textView.isNil or actionName.len == 0:
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
      "insertText", "insertNewline", "insertTab", "insertBacktab",
      "insertNewlineIgnoringFieldEditor", "insertTabIgnoringFieldEditor":
    textView.editable
  of "selectText", "selectAll", "moveLeft", "moveRight", "moveUp", "moveDown",
      "moveWordLeft", "moveWordRight", "moveToBeginningOfLine", "moveToEndOfLine",
      "moveLeftAndModifySelection", "moveRightAndModifySelection",
      "moveUpAndModifySelection", "moveDownAndModifySelection",
      "moveWordLeftAndModifySelection", "moveWordRightAndModifySelection",
      "moveToBeginningOfLineAndModifySelection", "moveToEndOfLineAndModifySelection":
    textView.editable or textView.selectable
  of "complete":
    textView.editable
  else:
    textView.respondsTo(action.name)

protocol DefaultTextViewValidation of UserInterfaceValidations:
  method validateUserInterfaceItem(textView: TextView, args: ValidationArgs): bool =
    textView.validateTextCommand(args.action)

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

  method moveToBeginningOfLine(textView: TextView, args: ActionArgs) =
    textView.moveToBeginningOfLineText()

  method moveToEndOfLine(textView: TextView, args: ActionArgs) =
    textView.moveToEndOfLineText()

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

  method moveToBeginningOfLineAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveToBeginningOfLineText(extending = true)

  method moveToEndOfLineAndModifySelection(textView: TextView, args: ActionArgs) =
    textView.moveToEndOfLineText(extending = true)

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
    if textView.isNil: nil else: textView.xTextStorage

  method textLayoutContainer(
      textView: TextView, manager: TextLayoutManager
  ): TextContainer =
    discard manager
    if textView.isNil:
      initTextContainer()
    else:
      textView.xTextContainer

  method textLayoutStyle(textView: TextView, manager: TextLayoutManager): TextStyle =
    discard manager
    textView.textStyle()

  method textLayoutAlignment(
      textView: TextView, manager: TextLayoutManager
  ): TextAlignment =
    discard manager
    if textView.isNil: taLeft else: textView.xAlignment

protocol DefaultTextViewLayoutEventSlots of TextLayoutEvents:
  proc layoutDidInvalidate(textView: TextView, ranges: seq[TextRange]) {.slot.} =
    discard ranges
    if not textView.isNil:
      textView.setNeedsDisplay(true)

  proc containersDidChange(
      textView: TextView, containers: seq[TextContainer]
  ) {.slot.} =
    discard containers
    if not textView.isNil:
      textView.invalidateIntrinsicContentSize()
      textView.setNeedsDisplay(true)

  proc containerDidInvalidate(
      textView: TextView, index: TextContainerIndex, container: TextContainer
  ) {.slot.} =
    discard index
    discard container
    if not textView.isNil:
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
    if not textView.isNil:
      textView.invalidateIntrinsicContentSize()
      textView.setNeedsDisplay(true)

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
    if textView.isNil or textView.xTextStorage.isNil: 0 else: textView.xTextStorage.len

  method accessibilitySelectedTextRange(textView: TextView): AccessibilityTextRange =
    textView.textViewSelectedRange().toAccessibilityTextRange()

  method setAccessibilitySelectedTextRange(
      textView: TextView, range: AccessibilityTextRange
  ): bool =
    if textView.isNil or (not textView.editable() and not textView.selectable()):
      return false
    textView.setTextViewSelectedRange(range.toTextRange())
    true

  method accessibilityInsertionPoint(textView: TextView): int =
    textView.textViewInsertionPoint()

  method setAccessibilityInsertionPoint(textView: TextView, index: int): bool =
    if textView.isNil or (not textView.editable() and not textView.selectable()):
      return false
    textView.setCursor(index)
    true

  method accessibilityBoundsForTextRange(
      textView: TextView, range: AccessibilityTextRange
  ): seq[Rect] =
    if textView.isNil:
      return
    for rect in textView.selectionRects(range.toTextRange()):
      result.add textView.rectToWindow(rect)

  method accessibilityBoundsForCharacter(textView: TextView, index: int): Rect =
    if textView.isNil:
      return initRect(0, 0, 0, 0)
    textView.rectToWindow(textView.characterRect(index))

  method accessibilityCharacterIndexAtPoint(textView: TextView, point: Point): int =
    if textView.isNil:
      return -1
    textView.textIndexAtPoint(textView.pointFromWindow(point))

  method accessibilityLineRange(textView: TextView, line: int): AccessibilityTextRange =
    if textView.isNil:
      return initAccessibilityTextRange(0, 0)
    textView.lineRange(line).toAccessibilityTextRange()

  method accessibilityLineForCharacter(textView: TextView, index: int): int =
    if textView.isNil:
      -1
    else:
      textView.lineForIndex(index)

  method accessibilityBoundsForLine(textView: TextView, line: int): Rect =
    if textView.isNil:
      return initRect(0, 0, 0, 0)
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
  textView.xTextColor = initColor(0.0, 0.0, 0.0, 0.0)
  textView.xSelectionColor = initColor(0.24, 0.56, 1.0, 0.34)
  textView.xTypingAttributes = defaultTextAttributes()
  textView.xSelectedTextAttributes =
    defaultTextAttributes(initColor(1.0, 1.0, 1.0, 1.0))
  textView.xInsertionPointVisible = true
  textView.xInsertionPointBlinkPeriod = 0.5'f32
  textView.xMarkedTextAttributes = defaultTextAttributes()
  textView.xMarkedTextAttributes.underline = true
  textView.xMarkedTextAttributes.underlineStyle = tldsSingle
  textView.xDefaultParagraphStyle = initTextParagraphStyle()
  textView.xCompletionPanel = TextCompletionPanel(selectedIndex: -1)
  textView.setAcceptsFirstResponder(true)
  discard textView.withProtocol(DefaultTextViewLayoutClient)
  discard textView.withProtocol(DefaultTextViewLayoutEventSlots)
  discard textView.withProtocol(DefaultTextViewAccessibility)
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
