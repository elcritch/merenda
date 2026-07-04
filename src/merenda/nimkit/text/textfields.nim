import std/unicode

import sigils/core

import ../accessibility/accessibility
import ../controls/controls
import ../foundation/objectvalues
import ../foundation/selectors
import ../foundation/events
import ../foundation/types
import ../app/windows
import ../themes
import ../drawing

import ./fieldeditors
import ./textstorage
import ./texttypes
import ./textviews
export controls
export texttypes

type
  LabelStyle* = enum
    lsBody
    lsTitle
    lsHeading
    lsStatus
    lsForm

  TextFieldCell* = ref object of ActionCell

  TextFieldFlag = enum
    tfEditable
    tfSelectable
    tfEditing

  TextFieldFlags = set[TextFieldFlag]

  TextField* = ref object of Control
    xStringValue: string
    xAlignment: TextAlignment
    xTextColor: Color
    xFlags: TextFieldFlags
    xInsertionPoint: int
    xSelectionAnchor: int
    xLayoutStorage: TextStorage
    xLayoutManager: TextLayoutManager

  Label* = ref object of TextField
    xLabelStyle: LabelStyle

proc setEditedString(
  textField: TextField, value: string, cursor: int, anchor: int, notify = true
)

proc selectAllText(textField: TextField)
proc activeFieldEditor(textField: TextField): FieldEditor
proc layoutFieldEditor(textField: TextField)
proc textFieldStyleContext(textField: TextField): StyleContext
proc textFieldStyle(textField: TextField): TextFieldStyle
proc syncLayout(textField: TextField)
proc syncLayout(textField: TextField, style: TextFieldStyle)
proc validateEditedObjectText(textField: TextField, value: string): bool
proc commitEditedObjectText(textField: TextField, value: string, cursor, anchor: int)

func toAccessibilityTextRange(range: TextRange): AccessibilityTextRange =
  initAccessibilityTextRange(int(range.location), int(range.length))

func toTextRange(range: AccessibilityTextRange): TextRange =
  initTextRange(int(range.location), int(range.length))

proc currentAccessibilitySelection(textField: TextField): TextRange =
  if textField.isNil:
    return initTextRange(0, 0)
  let editor = textField.activeFieldEditor()
  if not editor.isNil:
    return textviews.selectedRange(TextView(editor))
  let
    start = min(textField.xSelectionAnchor, textField.xInsertionPoint)
    stop = max(textField.xSelectionAnchor, textField.xInsertionPoint)
  initTextRange(start, stop - start)

proc postSelectionChanged(textField: TextField, before: TextRange) =
  if not textField.isNil and textField.currentAccessibilitySelection() != before:
    textField.postAccessibilityNotification(anSelectionChanged)

protocol TextFieldEvents:
  proc textDidChange*(textField: TextField, sender: DynamicAgent) {.signal.}

protocol TextFieldProtocol from TextField:
  property stringValue -> string
  property alignment -> TextAlignment
  property textColor -> Color
  property selectedRange -> TextRange

  method stringValue(textField: TextField): string =
    let editor = textField.activeFieldEditor()
    if not editor.isNil:
      return textviews.stringValue(TextView(editor))
    textField.xStringValue

  method setStringValue(textField: TextField, value: string) =
    if textField.xStringValue == value:
      Control(textField).setObjectValue(toObj(value))
      return
    let cursor = min(textField.xInsertionPoint, value.runeLen)
    let anchor = min(textField.xSelectionAnchor, value.runeLen)
    textField.setEditedString(value, cursor, anchor)
    Control(textField).setObjectValue(toObj(value))
    let editor = textField.activeFieldEditor()
    if not editor.isNil:
      textviews.setStringValue(TextView(editor), value)

  method alignment(textField: TextField): TextAlignment =
    textField.xAlignment

  method setAlignment(textField: TextField, alignment: TextAlignment) =
    if textField.xAlignment == alignment:
      return
    textField.xAlignment = alignment
    textField.setNeedsDisplay(true)

  method textColor(textField: TextField): Color =
    if textField.xTextColor.a > 0.0:
      return textField.xTextColor

    textField
    .effectiveAppearance()
    .resolveTextFieldStyle(textField.textFieldStyleContext()).text.color

  method setTextColor(textField: TextField, color: Color) =
    if textField.xTextColor == color:
      return
    textField.xTextColor = color
    textField.setNeedsDisplay(true)

  method isEditable*(textField: TextField): bool =
    tfEditable in textField.xFlags

  method setEditable*(textField: TextField, editable: bool) =
    if (tfEditable in textField.xFlags) == editable:
      return
    if editable:
      textField.xFlags.incl(tfEditable)
    else:
      textField.xFlags.excl(tfEditable)
    textField.setAcceptsFirstResponder(editable or textField.isSelectable())
    textField.invalidateIntrinsicContentSize()

  method isSelectable*(textField: TextField): bool =
    tfSelectable in textField.xFlags

  method setSelectable*(textField: TextField, selectable: bool) =
    if (tfSelectable in textField.xFlags) == selectable:
      return
    if selectable:
      textField.xFlags.incl(tfSelectable)
    else:
      textField.xFlags.excl(tfSelectable)
    textField.setAcceptsFirstResponder(selectable or textField.isEditable)
    textField.invalidateIntrinsicContentSize()

  method isEditing*(textField: TextField): bool =
    tfEditing in textField.xFlags

  method selectedRange(textField: TextField): TextRange =
    let editor = textField.activeFieldEditor()
    if not editor.isNil:
      return textviews.selectedRange(TextView(editor))
    let
      start = min(textField.xSelectionAnchor, textField.xInsertionPoint)
      stop = max(textField.xSelectionAnchor, textField.xInsertionPoint)
    initTextRange(start, stop - start)

  method setSelectedRange(textField: TextField, value: TextRange) =
    let previousSelection = textField.selectedRange()
    let editor = textField.activeFieldEditor()
    if not editor.isNil:
      textviews.setSelectedRange(TextView(editor), value)
    let
      total = textField.xStringValue.runeLen
      start = max(0, min(int(value.location), total))
      length = max(0, min(int(value.length), total - start))
    textField.xSelectionAnchor = start
    textField.xInsertionPoint = start + length
    textField.setNeedsDisplay(true)
    textField.postSelectionChanged(previousSelection)

  method insertionPoint*(textField: TextField): int =
    let editor = textField.activeFieldEditor()
    if not editor.isNil:
      return textviews.insertionPoint(TextView(editor))
    textField.xInsertionPoint

  method selectionAnchor*(textField: TextField): int =
    let editor = textField.activeFieldEditor()
    if not editor.isNil:
      return textviews.selectionAnchor(TextView(editor))
    textField.xSelectionAnchor

  method becomeFirstResponder(textField: TextField): bool =
    if not textField.isEnabled or
        (not textField.isEditable() and not textField.isSelectable()):
      return false
    textField.xFlags.incl(tfEditing)
    textField.selectAllText()
    true

  method resignFirstResponder(textField: TextField): bool =
    textField.xFlags.excl(tfEditing)
    textField.setNeedsDisplay(true)
    true

protocol DefaultTextFieldCellEditing of CellEditingProtocol:
  method fieldEditorForView(cell: TextFieldCell, controlView: View): FieldEditor =
    nil

  method setUpFieldEditorAttributes(
      cell: TextFieldCell, editor: FieldEditor, controlView: View
  ) =
    if editor.isNil:
      return
    if controlView of TextField:
      let textField = TextField(controlView)
      let style = textField.effectiveAppearance().resolveTextFieldStyle(
          textField.textFieldStyleContext()
        )
      editor.editable = textField.isEditable()
      editor.selectable = textField.isSelectable()
      editor.alignment = textField.alignment()
      editor.textColor = style.text.color
      editor.typingAttributes =
        defaultTextAttributes(style.text.color, style.text.fontSize)
      editor.allowsUndo = true
      if editor.textStorage().len > 0:
        editor.textStorage().setAttributes(
          initTextRange(0, editor.textStorage().len),
          defaultTextAttributes(style.text.color, style.text.fontSize),
        )

  method editWithFrame(
      cell: TextFieldCell, frame: Rect, controlView: View, editor: FieldEditor
  ) =
    if editor.isNil:
      return
    cell.setUpFieldEditorAttributes(editor, controlView)
    editor.frame = frame
    editor.bounds = rect(0.0, 0.0, frame.size.width, frame.size.height)
    if not controlView.isNil and editor.superview() != controlView:
      controlView.addSubview(editor)

  method selectWithFrame(
      cell: TextFieldCell,
      frame: Rect,
      controlView: View,
      editor: FieldEditor,
      start, length: int,
  ) =
    cell.editWithFrame(frame, controlView, editor)
    if not editor.isNil:
      editor.selectedRange = initTextRange(start, length)

  method endEditing(cell: TextFieldCell, editor: FieldEditor, controlView: View) =
    if not editor.isNil and editor.superview() == controlView:
      editor.removeFromSuperview()

protocol DefaultTextFieldFieldEditorClient of FieldEditorClient:
  method fieldEditorForClient(
      textField: TextField, defaultEditor: FieldEditor
  ): FieldEditor =
    let editor = textField.textFieldCell().fieldEditorForView(textField)
    if editor.isNil: defaultEditor else: editor

  method usesFieldEditor(textField: TextField, editor: FieldEditor): bool =
    textField.isEnabled and (textField.isEditable() or textField.isSelectable())

  method stringForFieldEditor(textField: TextField, editor: FieldEditor): string =
    textField.xStringValue

  method setStringFromFieldEditor(
      textField: TextField, editor: FieldEditor, value: string
  ) =
    textField.setEditedString(
      value,
      textviews.insertionPoint(TextView(editor)),
      textviews.selectionAnchor(TextView(editor)),
      notify = true,
    )
    Control(textField).clearValidationError()

  method didChangeTextInEditor(textField: TextField, editor: FieldEditor) =
    textField.setNeedsDisplay(true)

  method shouldBeginEditing(textField: TextField, editor: FieldEditor): bool =
    textField.isEnabled and (textField.isEditable() or textField.isSelectable())

  method didBeginEditing(textField: TextField, editor: FieldEditor) =
    let previousSelection = textField.selectedRange()
    textField.setCurrentEditor(editor)
    textField.xFlags.incl(tfEditing)
    textField.focused = true
    textField.focusVisible = editor.isFocusVisible()
    textField.textFieldCell().selectWithFrame(
      textField.fieldEditorFrame(), textField, editor, 0, editor.textStorage().len
    )
    textField.setNeedsDisplay(true)
    textField.postSelectionChanged(previousSelection)

  method didChangeFocusInEditor(textField: TextField, editor: FieldEditor) =
    if editor == textField.activeFieldEditor():
      textField.focused = editor.isFocused()
      textField.focusVisible = editor.isFocusVisible()

  method shouldEndEditing(textField: TextField, editor: FieldEditor): bool =
    textField.validateEditedObjectText(textviews.stringValue(TextView(editor)))

  method didEndEditing(textField: TextField, editor: FieldEditor) =
    textField.commitEditedObjectText(
      textviews.stringValue(TextView(editor)),
      textviews.insertionPoint(TextView(editor)),
      textviews.selectionAnchor(TextView(editor)),
    )
    textField.textFieldCell().endEditing(editor, textField)
    textField.setCurrentEditor(nil)
    textField.xFlags.excl(tfEditing)
    textField.focused = false
    textField.focusVisible = false
    textField.setNeedsDisplay(true)

  method validationErrorForEditor(
      textField: TextField, editor: FieldEditor
  ): ObjectValidationError =
    Control(textField).validationError()

  method didEndEditingMovement(
      textField: TextField, editor: FieldEditor, movement: TextEditMovement
  ) =
    let owner = textField.window()
    let ownerWindow =
      if owner of Window:
        Window(owner)
      else:
        nil
    case movement
    of temTab:
      if textField.textFieldCell().sendsActionOnEndEditing():
        discard textField.sendAction()
      if not ownerWindow.isNil:
        if not ownerWindow.selectKeyViewFollowingView(textField) and
            ownerWindow.firstResponder() == editor:
          discard ownerWindow.makeFirstResponder(nil)
    of temBacktab:
      if textField.textFieldCell().sendsActionOnEndEditing():
        discard textField.sendAction()
      if not ownerWindow.isNil:
        if not ownerWindow.selectKeyViewPrecedingView(textField) and
            ownerWindow.firstResponder() == editor:
          discard ownerWindow.makeFirstResponder(nil)
    of temReturn:
      discard textField.sendAction()
      if not ownerWindow.isNil and ownerWindow.firstResponder() == editor and
          editor.client().isNil:
        discard ownerWindow.makeFirstResponder(nil)
    of temNone:
      if textField.textFieldCell().sendsActionOnEndEditing():
        discard textField.sendAction()

proc clampIndex(total, index: int): int {.inline.} =
  max(0, min(index, total))

proc runeCount(textField: TextField): int {.inline.} =
  textField.xStringValue.runeLen

proc selectionBounds(total, anchor, cursor: int): tuple[start, stop: int] =
  let
    clampedAnchor = clampIndex(total, anchor)
    clampedCursor = clampIndex(total, cursor)
  result.start = min(clampedAnchor, clampedCursor)
  result.stop = max(clampedAnchor, clampedCursor)

proc currentSelection(textField: TextField): tuple[start, stop: int] =
  selectionBounds(
    textField.runeCount, textField.xSelectionAnchor, textField.xInsertionPoint
  )

proc activeFieldEditor(textField: TextField): FieldEditor =
  if textField.isNil:
    return nil
  activeEditor(Control(textField))

proc currentEditor*(textField: TextField): FieldEditor =
  currentEditor(Control(textField))

proc validateEditedObjectText(textField: TextField, value: string): bool =
  if textField.isNil:
    return true
  let parsed = Control(textField).parseEditedObjectValue(value, ovrTextField)
  if parsed.failed():
    return Control(textField).rejectObjectValueEdit(parsed.error)
  Control(textField).validateObjectValueForWriteback(parsed.value)

proc commitEditedObjectText(textField: TextField, value: string, cursor, anchor: int) =
  if textField.isNil:
    return
  let committed = Control(textField).commitEditedObjectText(value, ovrTextField)
  let displayValue =
    if committed:
      Control(textField).formattedObjectValue(ovrTextField)
    else:
      value
  textField.setEditedString(displayValue, cursor, anchor)

proc setObjectValue*(textField: TextField, value: ObjectValue, notify = false) =
  if textField.isNil:
    return
  Control(textField).setObjectValue(value, notify)
  let displayValue = Control(textField).formattedObjectValue(ovrTextField)
  let cursor = min(textField.xInsertionPoint, displayValue.runeLen)
  let anchor = min(textField.xSelectionAnchor, displayValue.runeLen)
  textField.setEditedString(displayValue, cursor, anchor)

proc `objectValue=`*(textField: TextField, value: ObjectValue) =
  textField.setObjectValue(value)

proc textFieldStyle(textField: TextField): TextFieldStyle =
  if textField.isNil:
    return initAppearance().resolveTextFieldStyle(controlStyle(srTextField))
  textField.effectiveAppearance().resolveTextFieldStyle(
    textField.textFieldStyleContext(), textField.textColor()
  )

func textFieldTextContainer(bounds, textRect: Rect): TextContainer =
  let textInsets = insets(
    textRect.origin.y,
    textRect.origin.x,
    max(bounds.size.height - textRect.maxY, 0.0'f32),
    max(bounds.size.width - textRect.maxX, 0.0'f32),
  )
  initTextContainer(bounds.size, textInsets)

proc hasUniformAttributes(storage: TextStorage, attributes: TextAttributes): bool =
  if storage.isNil:
    return false
  if storage.len == 0:
    return true
  var covered = 0
  for run in storage.runs:
    if run.attributes != attributes:
      return false
    covered += int(run.range.length)
  covered == storage.len

proc syncLayout(textField: TextField, style: TextFieldStyle) =
  if textField.isNil:
    return
  let
    textRect = style.textFieldTextRect(textField.bounds)
    attributes = defaultTextAttributes(style.text.color, style.text.fontSize)
  if textField.xLayoutStorage.isNil:
    textField.xLayoutStorage = newTextStorage(textField.xStringValue, attributes)
  elif textField.xLayoutStorage.stringValue() != textField.xStringValue:
    textField.xLayoutStorage.stringValue = textField.xStringValue
  if textField.xLayoutStorage.len > 0 and
      not textField.xLayoutStorage.hasUniformAttributes(attributes):
    textField.xLayoutStorage.setAttributes(
      initTextRange(0, textField.xLayoutStorage.len), attributes
    )

  if textField.xLayoutManager.isNil:
    textField.xLayoutManager = newTextLayoutManager(textField.xLayoutStorage)
  textField.xLayoutManager.textStorage = textField.xLayoutStorage
  textField.xLayoutManager.textContainer =
    textFieldTextContainer(textField.bounds, textRect)
  textField.xLayoutManager.textStyle = style.text
  textField.xLayoutManager.alignment = textField.xAlignment

proc syncLayout(textField: TextField) =
  if textField.isNil:
    return
  textField.syncLayout(textField.textFieldStyle())

proc layoutManager*(textField: TextField): TextLayoutManager =
  if textField.isNil:
    return nil
  textField.syncLayout()
  textField.xLayoutManager

proc fieldEditorFrame(textField: TextField): Rect =
  if textField.isNil:
    rect(0, 0, 0, 0)
  else:
    textField.layoutManager().layoutBounds()

proc layoutFieldEditor(textField: TextField) =
  let editor = textField.activeFieldEditor()
  if editor.isNil:
    return
  let frame = textField.fieldEditorFrame()
  editor.frame = frame
  editor.bounds = rect(0.0, 0.0, frame.size.width, frame.size.height)

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

proc setCursor(textField: TextField, index: int, extending = false) =
  if textField.isNil:
    return
  let previousSelection = textField.selectedRange()
  let cursor = clampIndex(textField.runeCount, index)
  textField.xInsertionPoint = cursor
  if not extending:
    textField.xSelectionAnchor = cursor
  textField.setNeedsDisplay(true)
  textField.postSelectionChanged(previousSelection)

proc setEditedString(
    textField: TextField, value: string, cursor: int, anchor: int, notify = true
) =
  let
    changed = textField.xStringValue != value
    previousSelection = textField.selectedRange()
  textField.xStringValue = value
  let total = textField.runeCount
  textField.xInsertionPoint = clampIndex(total, cursor)
  textField.xSelectionAnchor = clampIndex(total, anchor)
  if changed:
    textField.invalidateIntrinsicContentSize()
  textField.setNeedsDisplay(true)
  if changed and notify:
    emit textField.textDidChange(DynamicAgent(textField))
  if changed:
    textField.postAccessibilityNotification(anValueChanged)
  textField.postSelectionChanged(previousSelection)

proc selectAllText(textField: TextField) =
  if textField.isNil:
    return
  let previousSelection = textField.selectedRange()
  textField.xSelectionAnchor = 0
  textField.xInsertionPoint = textField.runeCount
  textField.setNeedsDisplay(true)
  textField.postSelectionChanged(previousSelection)

proc replaceSelectedText(textField: TextField, insertion: string) =
  if textField.isNil or not textField.isEditable():
    return
  let
    current = textField.xStringValue
    selected = textField.currentSelection()
    value =
      current.runeSubStr(0, selected.start) & insertion &
      current.runeSubStr(selected.stop)
    cursor = selected.start + insertion.runeLen
  textField.setEditedString(value, cursor, cursor)

proc deleteBackwardText(textField: TextField) =
  if textField.isNil or not textField.isEditable():
    return
  let
    current = textField.xStringValue
    selected = textField.currentSelection()
  if selected.stop > selected.start:
    textField.replaceSelectedText("")
    return
  if selected.start <= 0:
    return
  let
    cursor = selected.start - 1
    value = current.runeSubStr(0, cursor) & current.runeSubStr(selected.start)
  textField.setEditedString(value, cursor, cursor)

proc deleteForwardText(textField: TextField) =
  if textField.isNil or not textField.isEditable():
    return
  let
    current = textField.xStringValue
    total = textField.runeCount
    selected = textField.currentSelection()
  if selected.stop > selected.start:
    textField.replaceSelectedText("")
    return
  if selected.start >= total:
    return
  let value =
    current.runeSubStr(0, selected.start) & current.runeSubStr(selected.start + 1)
  textField.setEditedString(value, selected.start, selected.start)

proc deleteWordBackwardText(textField: TextField) =
  if textField.isNil or not textField.isEditable():
    return
  let
    current = textField.xStringValue
    selected = textField.currentSelection()
  if selected.stop > selected.start:
    textField.replaceSelectedText("")
    return
  let cursor = current.previousWordBoundary(selected.start)
  if cursor == selected.start:
    return
  let value = current.runeSubStr(0, cursor) & current.runeSubStr(selected.start)
  textField.setEditedString(value, cursor, cursor)

proc deleteWordForwardText(textField: TextField) =
  if textField.isNil or not textField.isEditable():
    return
  let
    current = textField.xStringValue
    selected = textField.currentSelection()
  if selected.stop > selected.start:
    textField.replaceSelectedText("")
    return
  let cursor = current.nextWordBoundary(selected.start)
  if cursor == selected.start:
    return
  let value = current.runeSubStr(0, selected.start) & current.runeSubStr(cursor)
  textField.setEditedString(value, selected.start, selected.start)

proc deleteToBeginningOfLineText(textField: TextField) =
  if textField.isNil or not textField.isEditable():
    return
  let selected = textField.currentSelection()
  if selected.stop > selected.start:
    textField.replaceSelectedText("")
    return
  if selected.start > 0:
    textField.setEditedString(textField.xStringValue.runeSubStr(selected.start), 0, 0)

proc deleteToEndOfLineText(textField: TextField) =
  if textField.isNil or not textField.isEditable():
    return
  let selected = textField.currentSelection()
  if selected.stop > selected.start:
    textField.replaceSelectedText("")
    return
  if selected.start < textField.runeCount:
    let value = textField.xStringValue.runeSubStr(0, selected.start)
    textField.setEditedString(value, selected.start, selected.start)

proc text*(textField: TextField): string =
  textField.stringValue()

proc `text=`*(textField: TextField, value: string) =
  textField.setStringValue(value)

proc `stringValue=`*(textField: TextField, value: string) =
  textField.setStringValue(value)

proc `alignment=`*(textField: TextField, alignment: TextAlignment) =
  textField.setAlignment(alignment)

proc `textColor=`*(textField: TextField, color: Color) =
  textField.setTextColor(color)

proc editable*(textField: TextField): bool =
  (not textField.isNil) and textField.isEditable()

proc `editable=`*(textField: TextField, editable: bool) =
  if not textField.isNil:
    textField.setEditable(editable)

proc selectable*(textField: TextField): bool =
  (not textField.isNil) and textField.isSelectable()

proc `selectable=`*(textField: TextField, selectable: bool) =
  if not textField.isNil:
    textField.setSelectable(selectable)

proc editing*(textField: TextField): bool =
  (not textField.isNil) and textField.isEditing()

proc `selectedRange=`*(textField: TextField, value: TextRange) =
  textField.setSelectedRange(value)

method textFieldInputHasMarkedText(textField: TextField): bool {.selector.} =
  discard textField
  false

method textFieldInputMarkedRange(textField: TextField): TextRange {.selector.} =
  discard textField
  initTextRange(0, 0)

method textFieldInputSelectedRange(textField: TextField): TextRange {.selector.} =
  if textField.isNil:
    return initTextRange(0, 0)
  let editor = textField.activeFieldEditor()
  if not editor.isNil:
    return textviews.selectedRange(TextView(editor))
  let
    start = min(textField.xSelectionAnchor, textField.xInsertionPoint)
    stop = max(textField.xSelectionAnchor, textField.xInsertionPoint)
  initTextRange(start, stop - start)

method textFieldInputAttributedSubstringForRange(
    textField: TextField, range: TextRange
): AttributedString {.selector.} =
  if textField.isNil:
    return newTextStorage()
  discard textField.layoutManager()
  textField.xLayoutStorage.sliceTextStorage(range)

method textFieldInputValidAttributesForMarkedText(
    textField: TextField
): seq[string] {.selector.} =
  discard textField
  @ValidMarkedTextAttributes

method textFieldInputFirstRectForCharacterRange(
    textField: TextField, range: TextRange
): Rect {.selector.} =
  if textField.isNil:
    return rect(0, 0, 0, 0)
  let clamped = initTextRange(
    min(int(range.location), textField.runeCount),
    min(int(range.length), max(textField.runeCount - int(range.location), 0)),
  )
  if clamped.length > 0:
    let rects = textField.layoutManager().selectionRects(clamped)
    if rects.len > 0:
      return textField.rectToWindow(rects[0])
  textField.rectToWindow(textField.layoutManager().characterRect(int(clamped.location)))

method textFieldInputCharacterIndexForPoint(
    textField: TextField, point: Point
): int {.selector.} =
  if textField.isNil:
    return -1
  textField.layoutManager().textIndexAtPoint(textField.pointFromWindow(point))

proc installTextFieldInputClientMethods(textField: TextField) =
  if textField.isNil:
    return
  discard
    textField.addMethod(selectors.textInputHasMarkedText, textFieldInputHasMarkedText)
  discard textField.addMethod(selectors.textInputMarkedRange, textFieldInputMarkedRange)
  discard
    textField.addMethod(selectors.textInputSelectedRange, textFieldInputSelectedRange)
  discard textField.addMethod(
    selectors.textInputAttributedSubstringForRange,
    textFieldInputAttributedSubstringForRange,
  )
  discard textField.addMethod(
    selectors.textInputValidAttributesForMarkedText,
    textFieldInputValidAttributesForMarkedText,
  )
  discard textField.addMethod(
    selectors.textInputFirstRectForCharacterRange,
    textFieldInputFirstRectForCharacterRange,
  )
  discard textField.addMethod(
    selectors.textInputCharacterIndexForPoint, textFieldInputCharacterIndexForPoint
  )

protocol DefaultTextFieldInput of TextInputProtocol:
  method insertText(textField: TextField, text: string) =
    if textField.isEditable() and text.isInsertableText:
      textField.replaceSelectedText(text)

protocol DefaultTextFieldCommands of TextEditingCommandProtocol:
  method selectText(textField: TextField, args: ActionArgs) =
    textField.selectAllText()

  method selectAll(textField: TextField, args: ActionArgs) =
    textField.selectAllText()

  method deleteBackward(textField: TextField, args: ActionArgs) =
    textField.deleteBackwardText()

  method deleteForward(textField: TextField, args: ActionArgs) =
    textField.deleteForwardText()

  method deleteWordBackward(textField: TextField, args: ActionArgs) =
    textField.deleteWordBackwardText()

  method deleteWordForward(textField: TextField, args: ActionArgs) =
    textField.deleteWordForwardText()

  method deleteToBeginningOfLine(textField: TextField, args: ActionArgs) =
    textField.deleteToBeginningOfLineText()

  method deleteToEndOfLine(textField: TextField, args: ActionArgs) =
    textField.deleteToEndOfLineText()

  method moveLeft(textField: TextField, args: ActionArgs) =
    if not textField.isEditable() and not textField.isSelectable():
      return
    let selected = textField.currentSelection()
    if selected.stop > selected.start:
      textField.setCursor(selected.start)
    else:
      textField.setCursor(selected.start - 1)

  method moveRight(textField: TextField, args: ActionArgs) =
    if not textField.isEditable() and not textField.isSelectable():
      return
    let selected = textField.currentSelection()
    if selected.stop > selected.start:
      textField.setCursor(selected.stop)
    else:
      textField.setCursor(selected.stop + 1)

  method moveWordLeft(textField: TextField, args: ActionArgs) =
    if not textField.isEditable() and not textField.isSelectable():
      return
    let selected = textField.currentSelection()
    if selected.stop > selected.start:
      textField.setCursor(selected.start)
    else:
      textField.setCursor(textField.xStringValue.previousWordBoundary(selected.start))

  method moveWordRight(textField: TextField, args: ActionArgs) =
    if not textField.isEditable() and not textField.isSelectable():
      return
    let selected = textField.currentSelection()
    if selected.stop > selected.start:
      textField.setCursor(selected.stop)
    else:
      textField.setCursor(textField.xStringValue.nextWordBoundary(selected.stop))

  method moveWordBackward(textField: TextField, args: ActionArgs) =
    textField.moveWordLeft(args)

  method moveWordForward(textField: TextField, args: ActionArgs) =
    textField.moveWordRight(args)

  method moveToBeginningOfLine(textField: TextField, args: ActionArgs) =
    if textField.isEditable() or textField.isSelectable():
      textField.setCursor(0)

  method moveToEndOfLine(textField: TextField, args: ActionArgs) =
    if textField.isEditable() or textField.isSelectable():
      textField.setCursor(textField.runeCount)

  method moveToBeginningOfDocument(textField: TextField, args: ActionArgs) =
    textField.moveToBeginningOfLine(args)

  method moveToEndOfDocument(textField: TextField, args: ActionArgs) =
    textField.moveToEndOfLine(args)

  method moveLeftAndModifySelection(textField: TextField, args: ActionArgs) =
    if textField.isEditable() or textField.isSelectable():
      textField.setCursor(textField.xInsertionPoint - 1, extending = true)

  method moveRightAndModifySelection(textField: TextField, args: ActionArgs) =
    if textField.isEditable() or textField.isSelectable():
      textField.setCursor(textField.xInsertionPoint + 1, extending = true)

  method moveWordLeftAndModifySelection(textField: TextField, args: ActionArgs) =
    if textField.isEditable() or textField.isSelectable():
      textField.setCursor(
        textField.xStringValue.previousWordBoundary(textField.xInsertionPoint),
        extending = true,
      )

  method moveWordRightAndModifySelection(textField: TextField, args: ActionArgs) =
    if textField.isEditable() or textField.isSelectable():
      textField.setCursor(
        textField.xStringValue.nextWordBoundary(textField.xInsertionPoint),
        extending = true,
      )

  method moveWordBackwardAndModifySelection(textField: TextField, args: ActionArgs) =
    textField.moveWordLeftAndModifySelection(args)

  method moveWordForwardAndModifySelection(textField: TextField, args: ActionArgs) =
    textField.moveWordRightAndModifySelection(args)

  method moveToBeginningOfLineAndModifySelection(
      textField: TextField, args: ActionArgs
  ) =
    if textField.isEditable() or textField.isSelectable():
      textField.setCursor(0, extending = true)

  method moveToEndOfLineAndModifySelection(textField: TextField, args: ActionArgs) =
    if textField.isEditable() or textField.isSelectable():
      textField.setCursor(textField.runeCount, extending = true)

  method moveToBeginningOfDocumentAndModifySelection(
      textField: TextField, args: ActionArgs
  ) =
    textField.moveToBeginningOfLineAndModifySelection(args)

  method moveToEndOfDocumentAndModifySelection(textField: TextField, args: ActionArgs) =
    textField.moveToEndOfLineAndModifySelection(args)

protocol DefaultTextFieldDrawing of ViewDrawingProtocol:
  method draw(textField: TextField, context: DrawContext) =
    let absoluteFrame = context.renderRectFor(textField.bounds)
    let states: set[WidgetState] = textField.widgetStateSet()

    let style = context.appearance.resolveTextFieldStyle(
      controlStyle(
        srTextField, states, id = textField.styleId, classes = textField.styleClasses
      ),
      textField.textColor,
    )

    discard context.addRenderRectangle(
      absoluteFrame, style.box.fill, style.box.borderColor, style.box.borderWidth,
      style.box.cornerRadius, style.box.shadows,
    )
    if ssFocusVisible in states:
      context.addFocusRing(absoluteFrame, style.box)

    let editor = textField.activeFieldEditor()
    if not editor.isNil:
      return

    textField.syncLayout(style)
    let
      manager = textField.xLayoutManager
      textRect = manager.layoutBounds()
      textValue = clippedText(textField.stringValue, textRect.size.width, style.text)
      layout = textLayout(textRect, textValue, style.text, textField.alignment)
      selectedRange = textField.selectedRange
    if textField.isEditing and selectedRange.length > 0:
      for rect in manager.selectionRects(selectedRange):
        discard context.addRectangle(rect, style.selectionColor)
    discard context.addText(textRect, layout)

    if textField.isEditing and textField.isEditable and selectedRange.length == 0:
      context.addRectangle(
        manager.caretRect(textField.insertionPoint), style.text.color
      )

protocol DefaultTextFieldEvents of ResponderEventProtocol:
  method mouseDown(textField: TextField, event: MouseEvent): bool =
    if event.button == mbPrimary and (
      textField.isEditable() or textField.isSelectable()
    ):
      let owner = textField.window()
      if owner of Window:
        discard Window(owner).makeFirstResponder(textField, focusVisible = false)
      let editor = textField.activeFieldEditor()
      if not editor.isNil:
        var editorEvent = event
        editorEvent.location = editor.pointFromView(event.location, textField)
        discard editor.handleMouse(mouseDown(), editorEvent)
      else:
        textField.selectedRange = initTextRange(textField.runeCount, 0)
      return true

  method keyDown(textField: TextField, event: KeyEvent): bool =
    if textField.isEditable() and event.modifiers - {kmShift} == {} and
        event.text.isInsertableText():
      textField.replaceSelectedText(event.text)
      return true

proc textFieldStyleContext(textField: TextField): StyleContext =
  let states: set[WidgetState] = textField.widgetStateSet()
  controlStyle(
    srTextField, states, id = textField.styleId, classes = textField.styleClasses
  )

protocol DefaultTextFieldLayout of ViewLayoutProtocol:
  method layoutSubviews(textField: TextField) =
    textField.syncLayout()
    textField.layoutFieldEditor()

protocol DefaultTextFieldAccessibility of AccessibilityProtocol:
  method accessibilityRole(textField: TextField): AccessibilityRole =
    if textField of Label: arStaticText else: arTextField

  method accessibilityLabel(textField: TextField): string =
    if textField.xAccessibilityLabel.len > 0:
      textField.xAccessibilityLabel
    elif textField of Label:
      textField.stringValue()
    else:
      textField.identifier()

  method accessibilityValue(textField: TextField): string =
    if textField of Label:
      ""
    else:
      textField.stringValue()

  method accessibilityTraits(textField: TextField): AccessibilityTraits =
    result = textField.xAccessibilityTraits
    if not textField.isEnabled():
      result.incl atDisabled
    if textField.focused():
      result.incl atFocused
    if textField.isEditable():
      result.incl atEditable
    if textField.isSelectable():
      result.incl atSelectable
    if textField of Label and Label(textField).xLabelStyle in {lsTitle, lsHeading}:
      result.incl atHeader

  method isAccessibilityElement(textField: TextField): bool =
    true

  method accessibilityTextLength(textField: TextField): int =
    if textField.isNil:
      return 0
    if textField of Label:
      textField.stringValue().runeLen
    else:
      textField.stringValue().runeLen

  method accessibilitySelectedTextRange(textField: TextField): AccessibilityTextRange =
    if textField of Label:
      return initAccessibilityTextRange(0, 0)
    textField.selectedRange().toAccessibilityTextRange()

  method setAccessibilitySelectedTextRange(
      textField: TextField, range: AccessibilityTextRange
  ): bool =
    if textField.isNil or (not textField.isEditable() and not textField.isSelectable()):
      return false
    textField.setSelectedRange(range.toTextRange())
    true

  method accessibilityInsertionPoint(textField: TextField): int =
    if textField of Label:
      0
    else:
      textField.insertionPoint()

  method setAccessibilityInsertionPoint(textField: TextField, index: int): bool =
    if textField.isNil or (not textField.isEditable() and not textField.isSelectable()):
      return false
    textField.setCursor(index)
    true

  method accessibilityBoundsForTextRange(
      textField: TextField, range: AccessibilityTextRange
  ): seq[Rect] =
    if textField.isNil:
      return
    let editor = textField.activeFieldEditor()
    if not editor.isNil:
      return TextView(editor).accessibilityBoundsForTextRange(range)
    for rect in textField.layoutManager().selectionRects(range.toTextRange()):
      result.add textField.rectToWindow(rect)

  method accessibilityBoundsForCharacter(textField: TextField, index: int): Rect =
    if textField.isNil:
      return rect(0, 0, 0, 0)
    let editor = textField.activeFieldEditor()
    if not editor.isNil:
      return TextView(editor).accessibilityBoundsForCharacter(index)
    textField.rectToWindow(textField.layoutManager().characterRect(index))

  method accessibilityCharacterIndexAtPoint(textField: TextField, point: Point): int =
    if textField.isNil:
      return -1
    let editor = textField.activeFieldEditor()
    if not editor.isNil:
      return TextView(editor).accessibilityCharacterIndexAtPoint(point)
    textField.layoutManager().textIndexAtPoint(textField.pointFromWindow(point))

  method accessibilityLineRange(
      textField: TextField, line: int
  ): AccessibilityTextRange =
    if textField.isNil:
      return initAccessibilityTextRange(0, 0)
    textField.layoutManager().lineRange(line).toAccessibilityTextRange()

  method accessibilityLineForCharacter(textField: TextField, index: int): int =
    if textField.isNil:
      return -1
    textField.layoutManager().lineForIndex(index)

  method accessibilityBoundsForLine(textField: TextField, line: int): Rect =
    if textField.isNil:
      return rect(0, 0, 0, 0)
    textField.rectToWindow(textField.layoutManager().lineBounds(line))

protocol DefaultTextFieldCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: TextFieldCell): IntrinsicSize =
    let view = cell.controlView()
    if view of TextField:
      let
        textField = TextField(view)
        style = textField.effectiveAppearance().resolveTextFieldStyle(
            textField.textFieldStyleContext(), textField.textColor()
          )
        textSize =
          if textField.isEditable() or textField.isSelectable():
            textNaturalSize("", style.text)
          else:
            textNaturalSize(textField.stringValue(), style.text)
      return initIntrinsicSize(style.textFieldControlSize(textSize))

    let style = initAppearance().resolveTextFieldStyle(controlStyle(srTextField))
    initIntrinsicSize(style.textFieldControlSize(textNaturalSize("", style.text)))

  method cellSizeForBounds(cell: TextFieldCell, bounds: Rect): Size =
    cell.cellSize().resolveIntrinsicSize(bounds.size)

proc initTextFieldCellFields*(cell: TextFieldCell) =
  initActionCellFields(cell)
  discard cell.withProtocol(DefaultTextFieldCellMeasurement)
  discard cell.withProtocol(DefaultTextFieldCellEditing)

proc newTextFieldCell*(): TextFieldCell =
  result = TextFieldCell()
  initTextFieldCellFields(result)

proc textFieldCell*(textField: TextField): TextFieldCell =
  let controlCell = textField.cell()
  if controlCell of TextFieldCell:
    return TextFieldCell(controlCell)
  let replacement = newTextFieldCell()
  textField.setCell(replacement)
  replacement

proc initTextFieldFields*(textField: TextField, value = "", frame: Rect = AutoRect) =
  initControlFields(textField, frame, newTextFieldCell())
  textField.setClipsToBounds(true)
  textField.xStringValue = value
  textField.xAlignment = taLeft
  textField.xTextColor = color(0.0, 0.0, 0.0, 0.0)
  textField.xFlags = {tfEditable, tfSelectable}
  textField.xInsertionPoint = value.runeLen
  textField.xSelectionAnchor = textField.xInsertionPoint
  textField.xLayoutStorage = newTextStorage(value)
  textField.xLayoutManager = newTextLayoutManager(textField.xLayoutStorage)
  Control(textField).setObjectValue(toObj(value))
  textField.setAcceptsFirstResponder(true)
  discard textField.withProto()
  discard textField.withProtocol(DefaultTextFieldInput)
  discard textField.withProtocol(DefaultTextFieldCommands)
  discard textField.withProtocol(DefaultTextFieldFieldEditorClient)
  discard textField.withProtocol(DefaultTextFieldDrawing)
  discard textField.withProtocol(DefaultTextFieldEvents)
  discard textField.withProtocol(DefaultTextFieldLayout)
  discard textField.withProtocol(DefaultTextFieldAccessibility)
  textField.installTextFieldInputClientMethods()
  textField.applyInitialFrame(frame)

proc newTextField*(value = "", frame: Rect = AutoRect): TextField =
  result = TextField()
  initTextFieldFields(result, value, frame)

func labelStyleClass(style: LabelStyle): string =
  case style
  of lsBody: LabelStyleClass
  of lsTitle: LabelTitleStyleClass
  of lsHeading: LabelHeadingStyleClass
  of lsStatus: LabelStatusStyleClass
  of lsForm: LabelFormStyleClass

func labelStyleClasses(style: LabelStyle): seq[string] =
  if style == lsBody:
    @[LabelStyleClass]
  else:
    @[LabelStyleClass, style.labelStyleClass]

func defaultAlignment(style: LabelStyle): TextAlignment =
  case style
  of lsTitle: taCenter
  of lsForm: taRight
  else: taLeft

proc labelStyle*(label: Label): LabelStyle =
  if label.isNil: lsBody else: label.xLabelStyle

proc `labelStyle=`*(label: Label, style: LabelStyle) =
  label.xLabelStyle = style
  label.styleClasses = style.labelStyleClasses()
  label.alignment = style.defaultAlignment()

proc initLabelFields*(
    label: Label, value = "", style: LabelStyle = lsBody, frame: Rect = AutoRect
) =
  initTextFieldFields(label, value, frame)
  label.editable = false
  label.selectable = false
  label.labelStyle = style

proc newLabel*(value = "", style: LabelStyle = lsBody, frame: Rect = AutoRect): Label =
  result = Label()
  initLabelFields(result, value, style, frame)

proc newTitleLabel*(value = "", frame: Rect = AutoRect): Label =
  newLabel(value, lsTitle, frame)

proc newHeadingLabel*(value = "", frame: Rect = AutoRect): Label =
  newLabel(value, lsHeading, frame)

proc newStatusLabel*(value = "", frame: Rect = AutoRect): Label =
  newLabel(value, lsStatus, frame)

proc newFormLabel*(value = "", frame: Rect = AutoRect): Label =
  newLabel(value, lsForm, frame)
