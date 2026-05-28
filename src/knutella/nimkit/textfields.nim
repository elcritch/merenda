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

protocol TextFieldProtocolInternal from TextField:
  method stringValue*(textField: TextField): string =
    textField.xStringValue

  method setStringValue*(textField: TextField, value: string) =
    if textField.xStringValue == value:
      return
    textField.xStringValue = value
    textField.setNeedsDisplay(true)

  method alignment*(textField: TextField): TextAlignment =
    textField.xAlignment

  method setAlignment*(textField: TextField, alignment: TextAlignment) =
    if textField.xAlignment == alignment:
      return
    textField.xAlignment = alignment
    textField.setNeedsDisplay(true)

  method textColor*(textField: TextField): Color =
    textField.xTextColor

  method setTextColor*(textField: TextField, color: Color) =
    if textField.xTextColor == color:
      return
    textField.xTextColor = color
    textField.setNeedsDisplay(true)

  method isEditable*(textField: TextField): bool =
    textField.xEditable

  method setEditable*(textField: TextField, editable: bool) =
    textField.xEditable = editable
    textField.setAcceptsFirstResponder(editable or textField.xSelectable)

  method isSelectable*(textField: TextField): bool =
    textField.xSelectable

  method setSelectable*(textField: TextField, selectable: bool) =
    textField.xSelectable = selectable
    textField.setAcceptsFirstResponder(selectable or textField.isEditable)

proc initTextFieldFields*(textField: TextField, frame: Rect, value: string) =
  initControlFields(textField, frame)
  textField.xStringValue = value
  textField.xAlignment = taLeft
  textField.xTextColor = initColor(0.08, 0.09, 0.11)
  discard textField.withProto()

proc newTextField*(frame: Rect, value: string): TextField =
  result = TextField()
  initTextFieldFields(result, frame, value)

proc newTextField*(x, y, width, height: float32, value: string): TextField =
  newTextField(initRect(x, y, width, height), value)

let TextFieldProtocol* = TextFieldProtocolInternal
