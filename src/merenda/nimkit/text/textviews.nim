import std/unicode

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

  TextView* = ref object of View
    xTextStorage: TextStorage
    xTextContainer: TextContainer
    xLayoutManager: TextLayoutManager
    xFlags: TextViewFlags
    xAlignment: TextAlignment
    xSelectionAnchor: int
    xInsertionPoint: int
    xTextColor: Color
    xSelectionColor: Color
    xTypingAttributes: TextAttributes
    xMarkedRange: TextRange
    xHasMarkedText: bool
    xMarkedUndoStorage: TextStorage
    xMarkedUndoSelection: TextRange
    xUndoStack: seq[TextUndoRecord]
    xRedoStack: seq[TextUndoRecord]
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

func toAccessibilityTextRange(range: TextRange): AccessibilityTextRange =
  initAccessibilityTextRange(int(range.location), int(range.length))

func toTextRange(range: AccessibilityTextRange): TextRange =
  initTextRange(int(range.location), int(range.length))

proc postSelectionChanged(textView: TextView, before: TextRange) =
  if not textView.isNil and textView.textViewSelectedRange() != before:
    textView.postAccessibilityNotification(anSelectionChanged)

protocol TextViewEvents:
  proc textDidChange*(textView: TextView, sender: DynamicAgent) {.signal.}

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

proc runesOf(text: string): seq[Rune] =
  for rune in text.runes:
    result.add rune

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
  if textView.textViewStringValue() == value:
    return
  let previousSelection = textView.textViewSelectedRange()
  textView.xTextStorage.stringValue = value
  let total = textView.xTextStorage.len
  textView.xInsertionPoint = total
  textView.xSelectionAnchor = total
  textView.clearMarkedText()
  textView.syncLayout()
  textView.invalidateIntrinsicContentSize()
  textView.setNeedsDisplay(true)
  emit textView.textDidChange(DynamicAgent(textView))
  textView.postAccessibilityNotification(anValueChanged)
  textView.postSelectionChanged(previousSelection)

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

proc typingAttributes*(textView: TextView): TextAttributes =
  if textView.isNil:
    defaultTextAttributes()
  else:
    textView.xTypingAttributes

proc `typingAttributes=`*(textView: TextView, attributes: TextAttributes) =
  if textView.isNil or textView.xTypingAttributes == attributes:
    return
  textView.xTypingAttributes = attributes

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
  let
    start = min(textView.xSelectionAnchor, textView.xInsertionPoint)
    stop = max(textView.xSelectionAnchor, textView.xInsertionPoint)
  initTextRange(start, stop - start)

proc setTextViewSelectedRange(textView: TextView, value: TextRange) =
  if textView.isNil:
    return
  let previousSelection = textView.textViewSelectedRange()
  let
    total = textView.xTextStorage.len
    start = max(0, min(int(value.location), total))
    length = max(0, min(int(value.length), total - start))
  textView.xSelectionAnchor = start
  textView.xInsertionPoint = start + length
  textView.updateTypingAttributesForSelection()
  textView.setNeedsDisplay(true)
  textView.postSelectionChanged(previousSelection)

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
  let previousSelection = textView.textViewSelectedRange()
  let clamped = textView.clampedRange(range)
  textView.xSelectionAnchor = int(clamped.location)
  textView.xInsertionPoint = clamped.maxIndex
  textView.updateTypingAttributesForSelection()
  textView.postSelectionChanged(previousSelection)

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

proc finishTextMutation(textView: TextView, valueChanged = true) =
  textView.syncLayout()
  textView.invalidateIntrinsicContentSize()
  textView.setNeedsDisplay(true)
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

  textView.xTextStorage.replace(clamped, inserted)
  if clearMark:
    textView.clearMarkedText()
  textView.setSelection(nextSelection)
  textView.finishTextMutation(textView.textViewStringValue() != beforeValue)
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

proc displayTextStorage(textView: TextView): TextStorage =
  if textView.isNil:
    return newTextStorage()
  let shouldApplyPlainTextColor = (not textView.richText) or textView.isFieldEditor
  if shouldApplyPlainTextColor or
      (textView.xHasMarkedText and textView.xMarkedRange.length > 0):
    result = textView.xTextStorage.copyTextStorage()
  else:
    result = textView.xTextStorage
  if shouldApplyPlainTextColor and result.len > 0:
    let style = textView.textStyle()
    result.setAttributes(
      initTextRange(0, result.len), defaultTextAttributes(style.color, style.fontSize)
    )
  if textView.xHasMarkedText and textView.xMarkedRange.length > 0:
    var attributes = result.attributesAt(int(textView.xMarkedRange.location))
    attributes.underline = true
    result.setAttributes(textView.xMarkedRange, attributes)

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
  let previousSelection = textView.textViewSelectedRange()
  let cursor = clampIndex(textView.xTextStorage.len, index)
  textView.xInsertionPoint = cursor
  if not extending:
    textView.xSelectionAnchor = cursor
  textView.updateTypingAttributesForSelection()
  textView.setNeedsDisplay(true)
  textView.postSelectionChanged(previousSelection)

proc selectAllText*(textView: TextView) =
  if textView.isNil:
    return
  let previousSelection = textView.textViewSelectedRange()
  textView.xSelectionAnchor = 0
  textView.xInsertionPoint = textView.xTextStorage.len
  textView.updateTypingAttributesForSelection()
  textView.setNeedsDisplay(true)
  textView.postSelectionChanged(previousSelection)

proc replaceSelectedText*(textView: TextView, insertion: string) =
  if textView.isNil or not textView.editable:
    return
  let selected =
    if textView.xHasMarkedText:
      textView.xMarkedRange
    else:
      textView.textViewSelectedRange()
  textView.replaceRange(selected, insertion, textView.xTypingAttributes)

proc insertTextValue*(textView: TextView, insertion: string) =
  if textView.isNil or not textView.editable:
    return
  if textView.xHasMarkedText:
    let
      before = textView.xMarkedUndoStorage
      beforeSelection = textView.xMarkedUndoSelection
    textView.replaceRange(
      textView.xMarkedRange, insertion, textView.xTypingAttributes, record = false
    )
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
  textView.xTextStorage = storage.copyTextStorage()
  textView.clearMarkedText()
  textView.setSelection(selection)
  textView.finishTextMutation()
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
  let
    caret = textView.xLayoutManager.caretRect(textView.xInsertionPoint)
    caretY = caret.origin.y + caret.size.height * 0.5'f32
    total = textView.xTextStorage.len
  var found = false

  for index in 0 .. total:
    let
      candidate = textView.xLayoutManager.caretRect(index)
      lineHeight = max(candidate.size.height, defaultFontSize())
    if caretY < candidate.origin.y or caretY >= candidate.origin.y + lineHeight:
      continue
    if not found:
      result = (first: index, last: index)
      found = true
    else:
      result.first = min(result.first, index)
      result.last = max(result.last, index)

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
  textView.xTextContainer.size = textView.bounds.size
  textView.updateFieldEditorInsets()
  textView.syncLayout()

proc textIndexAtPoint*(textView: TextView, point: Point): int =
  if textView.isNil:
    return 0
  textView.updateTextContainer()
  textView.xLayoutManager.textIndexAtPoint(point)

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
  let selected = textView.textViewSelectedRange()
  if selected.length > 0:
    discard context.addSelectedText(
      textRect,
      layout,
      int(selected.location),
      int(selected.length),
      textView.selectionColor(),
    )
  else:
    discard context.addText(textRect, layout)
  if textView.editable and selected.length == 0 and textView.isFocused:
    context.addRectangle(
      textView.xLayoutManager.caretRect(textView.textViewInsertionPoint()),
      textView.textColor(),
    )

protocol DefaultTextViewDrawing of ViewDrawingProtocol:
  method draw(textView: TextView, context: DrawContext) =
    textView.drawTextViewContents(context)

protocol DefaultTextViewEvents of ResponderEventProtocol:
  method mouseDown(textView: TextView, event: MouseEvent): bool =
    if event.button == mbPrimary and (textView.editable or textView.selectable):
      textView.xSelectingWithMouse = true
      textView.setCursor(textView.textIndexAtPoint(event.location))
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

  method layoutInvalidated(
      textView: TextView, manager: TextLayoutManager, ranges: seq[TextRange]
  ) =
    discard manager
    discard ranges
    if not textView.isNil:
      textView.setNeedsDisplay(true)

  method layoutCompleted(
      textView: TextView, manager: TextLayoutManager, snapshot: TextLayoutSnapshot
  ) =
    discard textView
    discard manager
    discard snapshot

  method geometryChanged(
      textView: TextView,
      manager: TextLayoutManager,
      oldUsedRect: Rect,
      oldContentSize: Size,
      snapshot: TextLayoutSnapshot,
  ) =
    discard manager
    discard oldUsedRect
    discard oldContentSize
    discard snapshot
    if not textView.isNil:
      textView.invalidateIntrinsicContentSize()
      textView.setNeedsDisplay(true)

  method contentSizeChanged(
      textView: TextView, manager: TextLayoutManager, oldSize, newSize: Size
  ) =
    discard manager
    discard oldSize
    discard newSize
    if not textView.isNil:
      textView.invalidateIntrinsicContentSize()

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
    textView.updateTextContainer()
    for rect in textView.xLayoutManager.selectionRects(range.toTextRange()):
      result.add textView.rectToWindow(rect)

  method accessibilityBoundsForCharacter(textView: TextView, index: int): Rect =
    if textView.isNil:
      return initRect(0, 0, 0, 0)
    textView.updateTextContainer()
    textView.rectToWindow(textView.xLayoutManager.characterRect(index))

  method accessibilityCharacterIndexAtPoint(textView: TextView, point: Point): int =
    if textView.isNil:
      return -1
    textView.updateTextContainer()
    textView.xLayoutManager.textIndexAtPoint(textView.pointFromWindow(point))

  method accessibilityLineRange(textView: TextView, line: int): AccessibilityTextRange =
    if textView.isNil:
      return initAccessibilityTextRange(0, 0)
    textView.xLayoutManager.lineRange(line).toAccessibilityTextRange()

  method accessibilityLineForCharacter(textView: TextView, index: int): int =
    if textView.isNil:
      -1
    else:
      textView.xLayoutManager.lineForIndex(index)

  method accessibilityBoundsForLine(textView: TextView, line: int): Rect =
    if textView.isNil:
      return initRect(0, 0, 0, 0)
    textView.updateTextContainer()
    textView.rectToWindow(textView.xLayoutManager.lineBounds(line))

proc initTextViewFields*(
    textView: TextView,
    value = "",
    frame: Rect = AutoRect,
    installDefaultProtocols = true,
) =
  initViewFields(textView, frame)
  textView.xTextStorage = newTextStorage(value)
  textView.xTextContainer = initTextContainer()
  textView.xLayoutManager =
    newTextLayoutManager(textView.xTextStorage, textView.xTextContainer)
  textView.xFlags = {tvEditable, tvSelectable, tvRichText, tvAllowsUndo}
  textView.xAlignment = taLeft
  textView.xInsertionPoint = textView.xTextStorage.len
  textView.xSelectionAnchor = textView.xInsertionPoint
  textView.xTextColor = initColor(0.0, 0.0, 0.0, 0.0)
  textView.xSelectionColor = initColor(0.24, 0.56, 1.0, 0.34)
  textView.xTypingAttributes = defaultTextAttributes()
  textView.setAcceptsFirstResponder(true)
  if installDefaultProtocols:
    discard textView.withProtocol(DefaultTextViewDrawing)
    discard textView.withProtocol(DefaultTextViewEvents)
    discard textView.withProtocol(DefaultTextViewInput)
    discard textView.withProtocol(DefaultTextViewCommands)
    discard textView.withProtocol(DefaultTextViewKeyCommands)
    discard textView.withProtocol(DefaultTextViewLayoutClient)
    discard textView.withProtocol(DefaultTextViewAccessibility)
    textView.xLayoutManager.layoutClient = DynamicAgent(textView)
  textView.applyInitialFrame(frame)

proc newTextView*(value = "", frame: Rect = AutoRect): TextView =
  result = TextView()
  initTextViewFields(result, value, frame)
