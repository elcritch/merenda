import ./controls
import ./selectors
import ./types

export controls

type TextField* = ref object of Control
  xStringValue: string
  xAlignment: TextAlignment
  xTextColor: Color
  xEditable: bool
  xSelectable: bool

protocol TextFieldProtocolInternal:
  required:
    method stringValue(): string
    method setStringValue(value: string)
    method alignment(): TextAlignment
    method setAlignment(alignment: TextAlignment)
    method textColor(): Color
    method setTextColor(color: Color)
    method isEditable(): bool
    method setEditable(editable: bool)
    method isSelectable(): bool
    method setSelectable(selectable: bool)

method textFieldStringValue(textField: TextField): string {.selector.} =
  textField.xStringValue

method textFieldSetStringValue(
    textField: TextField, value: string
): EmptyArgs {.selector.} =
  if textField.xStringValue == value:
    return
  textField.xStringValue = value
  textField.setNeedsDisplay(true)

method textFieldAlignment(textField: TextField): TextAlignment {.selector.} =
  textField.xAlignment

method textFieldSetAlignment(
    textField: TextField, alignment: TextAlignment
): EmptyArgs {.selector.} =
  if textField.xAlignment == alignment:
    return
  textField.xAlignment = alignment
  textField.setNeedsDisplay(true)

method textFieldTextColor(textField: TextField): Color {.selector.} =
  textField.xTextColor

method textFieldSetTextColor(
    textField: TextField, color: Color
): EmptyArgs {.selector.} =
  if textField.xTextColor == color:
    return
  textField.xTextColor = color
  textField.setNeedsDisplay(true)

method textFieldIsEditable(textField: TextField): bool {.selector.} =
  textField.xEditable

method textFieldSetEditable(
    textField: TextField, editable: bool
): EmptyArgs {.selector.} =
  textField.xEditable = editable
  textField.setAcceptsFirstResponder(editable or textField.xSelectable)

method textFieldIsSelectable(textField: TextField): bool {.selector.} =
  textField.xSelectable

method textFieldSetSelectable(
    textField: TextField, selectable: bool
): EmptyArgs {.selector.} =
  textField.xSelectable = selectable
  textField.setAcceptsFirstResponder(selectable or textField.isEditable)

proc installTextFieldMethods(textField: TextField) =
  discard textField.replaceMethod(stringValue, textFieldStringValue)
  discard textField.replaceMethod(setStringValue, textFieldSetStringValue)
  discard textField.replaceMethod(alignment, textFieldAlignment)
  discard textField.replaceMethod(setAlignment, textFieldSetAlignment)
  discard textField.replaceMethod(textColor, textFieldTextColor)
  discard textField.replaceMethod(setTextColor, textFieldSetTextColor)
  discard textField.replaceMethod(isEditable, textFieldIsEditable)
  discard textField.replaceMethod(setEditable, textFieldSetEditable)
  discard textField.replaceMethod(isSelectable, textFieldIsSelectable)
  discard textField.replaceMethod(setSelectable, textFieldSetSelectable)

proc initTextFieldFields*(textField: TextField, frame: Rect, value: string) =
  initControlFields(textField, frame)
  textField.xStringValue = value
  textField.xAlignment = taLeft
  textField.xTextColor = initColor(0.08, 0.09, 0.11)
  textField.installTextFieldMethods()

proc newTextField*(frame: Rect, value: string): TextField =
  result = TextField()
  initTextFieldFields(result, frame, value)

proc newTextField*(x, y, width, height: float32, value: string): TextField =
  newTextField(initRect(x, y, width, height), value)

proc stringValue*(textField: TextField): string =
  textField.send(stringValue, ())

proc setStringValue*(textField: TextField, value: string) =
  discard textField.send(setStringValue, value)

proc alignment*(textField: TextField): TextAlignment =
  textField.send(alignment, ())

proc setAlignment*(textField: TextField, alignment: TextAlignment) =
  discard textField.send(setAlignment, alignment)

proc textColor*(textField: TextField): Color =
  textField.send(textColor, ())

proc setTextColor*(textField: TextField, color: Color) =
  discard textField.send(setTextColor, color)

proc isEditable*(textField: TextField): bool =
  textField.send(isEditable, ())

proc setEditable*(textField: TextField, editable: bool) =
  discard textField.send(setEditable, editable)

proc isSelectable*(textField: TextField): bool =
  textField.send(isSelectable, ())

proc setSelectable*(textField: TextField, selectable: bool) =
  discard textField.send(setSelectable, selectable)

let TextFieldProtocol* = TextFieldProtocolInternal
