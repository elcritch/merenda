import std/unicode

import sigils/core

import ./drawing
import ./events
import ./pasteboards
import ./selectors
import ./textlayout
import ./textstorage
import ./texttypes
import ./theme
import ./types
import ./views

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

proc syncLayout(textView: TextView)
proc clearMarkedText(textView: TextView)
proc textViewStringValue(textView: TextView): string
proc setTextViewStringValue(textView: TextView, value: string)
proc textViewSelectedRange(textView: TextView): TextRange
proc setTextViewSelectedRange(textView: TextView, value: TextRange)
proc textViewInsertionPoint(textView: TextView): int
proc textViewSelectionAnchor(textView: TextView): int
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
proc moveWordLeftText*(textView: TextView, extending = false)
proc moveWordRightText*(textView: TextView, extending = false)
proc moveToBeginningOfLineText*(textView: TextView, extending = false)
proc moveToEndOfLineText*(textView: TextView, extending = false)

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
  textView.xTextStorage.stringValue = value
  let total = textView.xTextStorage.len
  textView.xInsertionPoint = total
  textView.xSelectionAnchor = total
  textView.clearMarkedText()
  textView.syncLayout()
  textView.invalidateIntrinsicContentSize()
  textView.setNeedsDisplay(true)

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
  else:
    textView.xTextColor

proc `textColor=`*(textView: TextView, color: Color) =
  if textView.isNil or textView.xTextColor == color:
    return
  textView.xTextColor = color
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
    index = max(0, min(min(anchor, cursor), total - 1))
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
  let
    total = textView.xTextStorage.len
    start = max(0, min(int(value.location), total))
    length = max(0, min(int(value.length), total - start))
  textView.xSelectionAnchor = start
  textView.xInsertionPoint = start + length
  textView.updateTypingAttributesForSelection()
  textView.setNeedsDisplay(true)

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
  let clamped = textView.clampedRange(range)
  textView.xSelectionAnchor = int(clamped.location)
  textView.xInsertionPoint = clamped.maxIndex
  textView.updateTypingAttributesForSelection()

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

proc finishTextMutation(textView: TextView) =
  textView.syncLayout()
  textView.invalidateIntrinsicContentSize()
  textView.setNeedsDisplay(true)

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
    beforeSelection = textView.textViewSelectedRange()
    clamped = textView.clampedRange(range)
    insertedLength = inserted.len
    nextSelection = initTextRange(int(clamped.location) + insertedLength, 0)

  textView.xTextStorage.replace(clamped, inserted)
  if clearMark:
    textView.clearMarkedText()
  textView.setSelection(nextSelection)
  textView.finishTextMutation()
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
  result = textView.xTextStorage
  if textView.xHasMarkedText and textView.xMarkedRange.length > 0:
    result = textView.xTextStorage.copyTextStorage()
    var attributes = result.attributesAt(int(textView.xMarkedRange.location))
    attributes.underline = true
    result.setAttributes(textView.xMarkedRange, attributes)

proc syncLayout(textView: TextView) =
  if textView.isNil or textView.xLayoutManager.isNil:
    return
  textView.xLayoutManager.textStorage = textView.xTextStorage
  textView.xLayoutManager.textContainer = textView.xTextContainer
  textView.xLayoutManager.alignment = textView.xAlignment
  textView.xLayoutManager.invalidateLayout()

proc setCursor*(textView: TextView, index: int, extending = false) =
  if textView.isNil:
    return
  let cursor = clampIndex(textView.xTextStorage.len, index)
  textView.xInsertionPoint = cursor
  if not extending:
    textView.xSelectionAnchor = cursor
  textView.updateTypingAttributesForSelection()
  textView.setNeedsDisplay(true)

proc selectAllText*(textView: TextView) =
  if textView.isNil:
    return
  textView.xSelectionAnchor = 0
  textView.xInsertionPoint = textView.xTextStorage.len
  textView.updateTypingAttributesForSelection()
  textView.setNeedsDisplay(true)

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

proc moveToBeginningOfLineText*(textView: TextView, extending = false) =
  if textView.isNil or (not textView.editable and not textView.selectable):
    return
  textView.setCursor(0, extending)

proc moveToEndOfLineText*(textView: TextView, extending = false) =
  if textView.isNil or (not textView.editable and not textView.selectable):
    return
  textView.setCursor(textView.xTextStorage.len, extending)

proc updateTextContainer(textView: TextView) =
  if textView.isNil:
    return
  textView.xTextContainer.size = textView.bounds.size
  textView.syncLayout()

proc textIndexAtPoint*(textView: TextView, point: Point): int =
  if textView.isNil:
    return 0
  textView.updateTextContainer()
  textView.xLayoutManager.textIndexAtPoint(point)

protocol DefaultTextViewDrawing of ViewDrawingProtocol:
  method draw(textView: TextView, context: DrawContext) =
    textView.updateTextContainer()
    let layout = textLayout(
      textView.bounds,
      textView.displayTextStorage(),
      textView.alignment(),
      textView.xTextContainer.wraps,
    )
    let selected = textView.textViewSelectedRange()
    if selected.length > 0:
      discard context.addSelectedText(
        textView.bounds,
        layout,
        int(selected.location),
        int(selected.length),
        textView.selectionColor(),
      )
    else:
      discard context.addText(textView.bounds, layout)
    if textView.editable and selected.length == 0 and textView.isFocused:
      context.addRectangle(
        textView.xLayoutManager.caretRect(textView.textViewInsertionPoint()),
        textView.textColor(),
      )

protocol DefaultTextViewEvents of ResponderEventProtocol:
  method mouseDown(textView: TextView, event: MouseEvent): bool =
    if event.button == mbPrimary and (textView.editable or textView.selectable):
      textView.setCursor(textView.textIndexAtPoint(event.location))
      return true
    false

  method keyDown(textView: TextView, event: KeyEvent) =
    if textView.editable and event.shouldInsertText():
      textView.insertTextValue(event.text)

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
  textView.xTextColor = initColor(0.08, 0.09, 0.11)
  textView.xSelectionColor = initColor(0.24, 0.56, 1.0, 0.34)
  textView.xTypingAttributes = defaultTextAttributes(textView.xTextColor)
  textView.setAcceptsFirstResponder(true)
  if installDefaultProtocols:
    discard textView.withProtocol(DefaultTextViewDrawing)
    discard textView.withProtocol(DefaultTextViewEvents)
    discard textView.withProtocol(DefaultTextViewInput)
    discard textView.withProtocol(DefaultTextViewCommands)
    discard textView.withProtocol(DefaultTextViewKeyCommands)
  textView.applyInitialFrame(frame)

proc newTextView*(value = "", frame: Rect = AutoRect): TextView =
  result = TextView()
  initTextViewFields(result, value, frame)
