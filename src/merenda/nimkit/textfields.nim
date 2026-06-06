import std/unicode

import sigils/core

import ./controls
import ./selectors
import ./theme
import ./types

export controls

type
  LabelStyle* = enum
    lsBody
    lsTitle
    lsHeading
    lsStatus
    lsForm

  TextRange* = object
    location*: Natural
    length*: Natural

  TextFieldCell* = ref object of ActionCell

  TextField* = ref object of Control
    xStringValue: string
    xAlignment: TextAlignment
    xTextColor: Color
    xEditable: bool
    xSelectable: bool
    xFocused: bool
    xInsertionPoint: int
    xSelectionAnchor: int

  Label* = ref object of TextField
    xLabelStyle: LabelStyle

proc setEditedString(
  textField: TextField, value: string, cursor: int, anchor: int, notify = true
)

proc selectAllText(textField: TextField)

proc initTextRange*(location, length: int): TextRange =
  TextRange(location: max(location, 0).Natural, length: max(length, 0).Natural)

protocol TextFieldEvents:
  proc textDidChange*(textField: TextField, sender: DynamicAgent) {.signal.}

protocol TextFieldProtocol from TextField:
  property stringValue -> string
  property alignment -> TextAlignment
  property textColor -> Color
  property selectedRange -> TextRange

  method stringValue(textField: TextField): string =
    textField.xStringValue

  method setStringValue(textField: TextField, value: string) =
    if textField.xStringValue == value:
      return
    let cursor = min(textField.xInsertionPoint, value.runeLen)
    let anchor = min(textField.xSelectionAnchor, value.runeLen)
    textField.setEditedString(value, cursor, anchor)

  method alignment(textField: TextField): TextAlignment =
    textField.xAlignment

  method setAlignment(textField: TextField, alignment: TextAlignment) =
    if textField.xAlignment == alignment:
      return
    textField.xAlignment = alignment
    textField.setNeedsDisplay(true)

  method textColor(textField: TextField): Color =
    textField.xTextColor

  method setTextColor(textField: TextField, color: Color) =
    if textField.xTextColor == color:
      return
    textField.xTextColor = color
    textField.setNeedsDisplay(true)

  method isEditable*(textField: TextField): bool =
    textField.xEditable

  method setEditable*(textField: TextField, editable: bool) =
    if textField.xEditable == editable:
      return
    textField.xEditable = editable
    textField.setAcceptsFirstResponder(editable or textField.xSelectable)
    textField.invalidateIntrinsicContentSize()

  method isSelectable*(textField: TextField): bool =
    textField.xSelectable

  method setSelectable*(textField: TextField, selectable: bool) =
    if textField.xSelectable == selectable:
      return
    textField.xSelectable = selectable
    textField.setAcceptsFirstResponder(selectable or textField.isEditable)
    textField.invalidateIntrinsicContentSize()

  method isEditing*(textField: TextField): bool =
    textField.xFocused

  method selectedRange(textField: TextField): TextRange =
    if textField.isNil:
      return initTextRange(0, 0)
    let
      start = min(textField.xSelectionAnchor, textField.xInsertionPoint)
      stop = max(textField.xSelectionAnchor, textField.xInsertionPoint)
    initTextRange(start, stop - start)

  method setSelectedRange(textField: TextField, value: TextRange) =
    if textField.isNil:
      return
    let
      total = textField.xStringValue.runeLen
      start = max(0, min(value.location.int, total))
      length = max(0, min(value.length.int, total - start))
    textField.xSelectionAnchor = start
    textField.xInsertionPoint = start + length
    textField.setNeedsDisplay(true)

  method insertionPoint*(textField: TextField): int =
    textField.xInsertionPoint

  method selectionAnchor*(textField: TextField): int =
    textField.xSelectionAnchor

  method becomeFirstResponder(textField: TextField): bool =
    if not textField.isEnabled or (
      not textField.xEditable and not textField.xSelectable
    ):
      return false
    textField.xFocused = true
    textField.selectAllText()
    true

  method resignFirstResponder(textField: TextField): bool =
    textField.xFocused = false
    textField.setNeedsDisplay(true)
    true

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
  let cursor = clampIndex(textField.runeCount, index)
  textField.xInsertionPoint = cursor
  if not extending:
    textField.xSelectionAnchor = cursor
  textField.setNeedsDisplay(true)

proc setEditedString(
    textField: TextField, value: string, cursor: int, anchor: int, notify = true
) =
  if textField.isNil:
    return
  let changed = textField.xStringValue != value
  textField.xStringValue = value
  let total = textField.runeCount
  textField.xInsertionPoint = clampIndex(total, cursor)
  textField.xSelectionAnchor = clampIndex(total, anchor)
  if changed:
    textField.invalidateIntrinsicContentSize()
  textField.setNeedsDisplay(true)
  if changed and notify:
    emit textField.textDidChange(DynamicAgent(textField))

proc selectAllText(textField: TextField) =
  if textField.isNil:
    return
  textField.xSelectionAnchor = 0
  textField.xInsertionPoint = textField.runeCount
  textField.setNeedsDisplay(true)

proc replaceSelectedText(textField: TextField, insertion: string) =
  if textField.isNil or not textField.xEditable:
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
  if textField.isNil or not textField.xEditable:
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
  if textField.isNil or not textField.xEditable:
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
  if textField.isNil or not textField.xEditable:
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
  if textField.isNil or not textField.xEditable:
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

proc isControlInput(rune: Rune): bool =
  let code = rune.int
  code < 32 or (code >= 127 and code <= 159)

proc isInsertableText(text: string): bool =
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

protocol DefaultTextFieldInput of TextInputProtocol:
  method insertText(textField: TextField, text: string) =
    if textField.xEditable and text.isInsertableText:
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

  method moveLeft(textField: TextField, args: ActionArgs) =
    if not textField.xEditable and not textField.xSelectable:
      return
    let selected = textField.currentSelection()
    if selected.stop > selected.start:
      textField.setCursor(selected.start)
    else:
      textField.setCursor(selected.start - 1)

  method moveRight(textField: TextField, args: ActionArgs) =
    if not textField.xEditable and not textField.xSelectable:
      return
    let selected = textField.currentSelection()
    if selected.stop > selected.start:
      textField.setCursor(selected.stop)
    else:
      textField.setCursor(selected.stop + 1)

  method moveWordLeft(textField: TextField, args: ActionArgs) =
    if not textField.xEditable and not textField.xSelectable:
      return
    let selected = textField.currentSelection()
    if selected.stop > selected.start:
      textField.setCursor(selected.start)
    else:
      textField.setCursor(textField.xStringValue.previousWordBoundary(selected.start))

  method moveWordRight(textField: TextField, args: ActionArgs) =
    if not textField.xEditable and not textField.xSelectable:
      return
    let selected = textField.currentSelection()
    if selected.stop > selected.start:
      textField.setCursor(selected.stop)
    else:
      textField.setCursor(textField.xStringValue.nextWordBoundary(selected.stop))

  method moveToBeginningOfLine(textField: TextField, args: ActionArgs) =
    if textField.xEditable or textField.xSelectable:
      textField.setCursor(0)

  method moveToEndOfLine(textField: TextField, args: ActionArgs) =
    if textField.xEditable or textField.xSelectable:
      textField.setCursor(textField.runeCount)

  method moveLeftAndModifySelection(textField: TextField, args: ActionArgs) =
    if textField.xEditable or textField.xSelectable:
      textField.setCursor(textField.xInsertionPoint - 1, extending = true)

  method moveRightAndModifySelection(textField: TextField, args: ActionArgs) =
    if textField.xEditable or textField.xSelectable:
      textField.setCursor(textField.xInsertionPoint + 1, extending = true)

  method moveWordLeftAndModifySelection(textField: TextField, args: ActionArgs) =
    if textField.xEditable or textField.xSelectable:
      textField.setCursor(
        textField.xStringValue.previousWordBoundary(textField.xInsertionPoint),
        extending = true,
      )

  method moveWordRightAndModifySelection(textField: TextField, args: ActionArgs) =
    if textField.xEditable or textField.xSelectable:
      textField.setCursor(
        textField.xStringValue.nextWordBoundary(textField.xInsertionPoint),
        extending = true,
      )

  method moveToBeginningOfLineAndModifySelection(
      textField: TextField, args: ActionArgs
  ) =
    if textField.xEditable or textField.xSelectable:
      textField.setCursor(0, extending = true)

  method moveToEndOfLineAndModifySelection(textField: TextField, args: ActionArgs) =
    if textField.xEditable or textField.xSelectable:
      textField.setCursor(textField.runeCount, extending = true)

protocol DefaultTextFieldDrawing of ViewDrawingProtocol:
  method draw(textField: TextField, context: DrawContext) =
    let
      absoluteFrame = textField.rectToWindow(textField.bounds)
      focused = textField.isEditing or textField.isFocused
      focusVisible = textField.isEditing or textField.isFocusVisible
      style = context.appearance.resolveTextFieldStyle(
        initControlStyleContext(
          srTextField,
          enabled = textField.isEnabled,
          hovered = textField.isHovered,
          active = textField.isActive,
          focused = focused,
          focusVisible = focusVisible,
          id = textField.styleId,
          classes = textField.styleClasses,
        ),
        textField.textColor,
      )

    discard context.addWindowRectangle(
      absoluteFrame, style.box.fill, style.box.borderColor, style.box.borderWidth,
      style.box.cornerRadius, style.box.shadows,
    )
    if focusVisible:
      context.addFocusRing(absoluteFrame, style.box)

    let
      textRect = style.textFieldTextRect(textField.bounds)
      layout = textLayout(
        textRect, textField.stringValue, style.text.color, textField.alignment
      )
      selectedRange = textField.selectedRange
    if textField.isEditing and selectedRange.length > 0:
      discard context.addSelectedText(
        textRect, layout, selectedRange.location.int, selectedRange.length.int,
        style.selectionColor,
      )
    else:
      discard context.addText(textRect, layout)

    if textField.isEditing and textField.isEditable and selectedRange.length == 0:
      context.addRectangle(
        textRect.caretRect(layout, textField.insertionPoint), style.text.color
      )

protocol DefaultTextFieldEvents of ResponderEventProtocol:
  method mouseDown(textField: TextField, event: MouseEvent) =
    if event.button == mbPrimary and (textField.xEditable or textField.xSelectable):
      textField.setCursor(textField.runeCount)

  method keyDown(textField: TextField, event: KeyEvent) =
    if textField.xEditable and event.shouldInsertText():
      textField.replaceSelectedText(event.text)

proc textFieldStyleContext(textField: TextField): StyleContext =
  initControlStyleContext(
    srTextField,
    enabled = textField.isEnabled,
    hovered = textField.isHovered,
    active = textField.isActive,
    focused = textField.isEditing or textField.isFocused,
    focusVisible = textField.isEditing or textField.isFocusVisible,
    id = textField.styleId,
    classes = textField.styleClasses,
  )

protocol DefaultTextFieldCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: TextFieldCell): IntrinsicSize =
    let view = cell.controlView()
    if view of TextField:
      let
        textField = TextField(view)
        style = textField.effectiveAppearance().resolveTextFieldStyle(
            textField.textFieldStyleContext(), textField.textColor()
          )
      return initIntrinsicSize(
        style.textFieldControlSize(textNaturalSize(textField.stringValue()))
      )

    let style =
      initAppearance().resolveTextFieldStyle(initControlStyleContext(srTextField))
    initIntrinsicSize(style.textFieldControlSize(textNaturalSize("")))

  method cellSizeForBounds(cell: TextFieldCell, bounds: Rect): Size =
    cell.cellSize().resolveIntrinsicSize(bounds.size)

proc initTextFieldCellFields*(cell: TextFieldCell) =
  initActionCellFields(cell)
  discard cell.withProtocol(DefaultTextFieldCellMeasurement)

proc newTextFieldCell*(): TextFieldCell =
  result = TextFieldCell()
  initTextFieldCellFields(result)

proc textFieldCell*(textField: TextField): TextFieldCell =
  if textField.isNil:
    return nil
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
  textField.xTextColor = initColor(0.08, 0.09, 0.11)
  textField.xEditable = true
  textField.xSelectable = true
  textField.xInsertionPoint = value.runeLen
  textField.xSelectionAnchor = textField.xInsertionPoint
  textField.setAcceptsFirstResponder(true)
  discard textField.withProto()
  discard textField.withProtocol(DefaultTextFieldInput)
  discard textField.withProtocol(DefaultTextFieldCommands)
  discard textField.withProtocol(DefaultTextFieldDrawing)
  discard textField.withProtocol(DefaultTextFieldEvents)
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
  if label.isNil:
    return
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
