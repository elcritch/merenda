import ./controls
import ./types

export controls

type TextField* = ref object of Control
  xStringValue: string
  xAlignment: TextAlignment
  xTextColor: Color
  xEditable: bool
  xSelectable: bool

proc initTextFieldFields*(textField: TextField, frame: Rect, value: string) =
  initControlFields(textField, frame)
  textField.xStringValue = value
  textField.xAlignment = taLeft
  textField.xTextColor = initColor(0.08, 0.09, 0.11)

proc newTextField*(frame: Rect, value: string): TextField =
  result = TextField()
  initTextFieldFields(result, frame, value)

proc newTextField*(x, y, width, height: float32, value: string): TextField =
  newTextField(initRect(x, y, width, height), value)

proc stringValue*(textField: TextField): string =
  textField.xStringValue

proc setStringValue*(textField: TextField, value: string) =
  if textField.stringValue == value:
    return
  textField.xStringValue = value
  textField.setNeedsDisplay(true)

proc alignment*(textField: TextField): TextAlignment =
  textField.xAlignment

proc setAlignment*(textField: TextField, alignment: TextAlignment) =
  if textField.alignment == alignment:
    return
  textField.xAlignment = alignment
  textField.setNeedsDisplay(true)

proc textColor*(textField: TextField): Color =
  textField.xTextColor

proc setTextColor*(textField: TextField, color: Color) =
  if textField.textColor == color:
    return
  textField.xTextColor = color
  textField.setNeedsDisplay(true)

proc isEditable*(textField: TextField): bool =
  textField.xEditable

proc setEditable*(textField: TextField, editable: bool) =
  textField.xEditable = editable
  textField.setAcceptsFirstResponder(editable or textField.xSelectable)

proc isSelectable*(textField: TextField): bool =
  textField.xSelectable

proc setSelectable*(textField: TextField, selectable: bool) =
  textField.xSelectable = selectable
  textField.setAcceptsFirstResponder(selectable or textField.isEditable)
