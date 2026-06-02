import std/unittest

import merenda/nimkit

suite "nimkit text fields":
  test "text fields default to editable selectable first-responder controls":
    let field = newTextField("abc", frame = initRect(0, 0, 120, 24))

    check field.isEditable
    check field.isSelectable
    check field.acceptsFirstResponder
    check field.clipsToBounds
    check field.selectedRange == initTextRange(3, 0)
    check field.insertionPoint == 3

    field.text = "abcd"
    field.alignment = taCenter
    field.editable = false
    field.selectable = false

    check field.text == "abcd"
    check field.stringValue == "abcd"
    check field.alignment == taCenter
    check not field.editable
    check not field.selectable

  test "labels are styled non-editable text fields":
    let
      body = newLabel("Body")
      title = newTitleLabel("Title")
      heading = newHeadingLabel("Heading")
      status = newStatusLabel("Status")
      form = newFormLabel("Name")

    for label in [body, title, heading, status, form]:
      check not label.editable
      check not label.selectable
      check not label.acceptsFirstResponder
      check label.clipsToBounds

    check body.labelStyle == lsBody
    check body.styleClasses == @[LabelStyleClass]
    check body.alignment == taLeft
    check title.labelStyle == lsTitle
    check title.styleClasses == @[LabelStyleClass, LabelTitleStyleClass]
    check title.alignment == taCenter
    check heading.labelStyle == lsHeading
    check heading.styleClasses == @[LabelStyleClass, LabelHeadingStyleClass]
    check status.labelStyle == lsStatus
    check status.styleClasses == @[LabelStyleClass, LabelStatusStyleClass]
    check form.labelStyle == lsForm
    check form.styleClasses == @[LabelStyleClass, LabelFormStyleClass]
    check form.alignment == taRight

    title.labelStyle = lsForm
    check title.labelStyle == lsForm
    check title.styleClasses == @[LabelStyleClass, LabelFormStyleClass]
    check title.alignment == taRight

  test "first responder text input replaces the current selection":
    let
      window = newWindow("Text input", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abc", frame = initRect(10, 10, 140, 24))

    root.addSubview(field)
    window.setContentView(root)

    check window.makeFirstResponder(field)
    check field.isEditing
    check field.selectedRange == initTextRange(0, 3)

    check window.dispatchKeyDown(KeyEvent(text: "X", key: keyX, keyCode: keyX.ord))
    check field.stringValue == "X"
    check field.selectedRange == initTextRange(1, 0)

    check window.dispatchKeyDown(KeyEvent(text: "y", key: keyY, keyCode: keyY.ord))
    check field.stringValue == "Xy"
    check field.selectedRange == initTextRange(2, 0)

  test "insertText respects text field editability":
    let field = newTextField("abc", frame = initRect(0, 0, 120, 24))

    field.editable = false
    discard field.send(insertText(), "x")
    check field.stringValue == "abc"
    check field.selectedRange == initTextRange(3, 0)

    field.editable = true
    discard field.send(insertText(), "x")
    check field.stringValue == "abcx"
    check field.selectedRange == initTextRange(4, 0)

  test "default edit commands move and delete text":
    let
      window = newWindow("Text commands", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abcdef", frame = initRect(10, 10, 140, 24))

    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)

    field.selectedRange = initTextRange(3, 0)
    check window.dispatchKeyDown(KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord))
    check field.stringValue == "abdef"
    check field.selectedRange == initTextRange(2, 0)

    check window.dispatchKeyDown(KeyEvent(key: keyDelete, keyCode: keyDelete.ord))
    check field.stringValue == "abef"
    check field.selectedRange == initTextRange(2, 0)

    check window.dispatchKeyDown(KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord))
    check field.selectedRange == initTextRange(1, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmShift})
    )
    check field.selectedRange == initTextRange(1, 1)

    check window.dispatchKeyDown(KeyEvent(text: "Z", key: keyZ, keyCode: keyZ.ord))
    check field.stringValue == "aZef"
    check field.selectedRange == initTextRange(2, 0)

  test "macOS profile moves and deletes by word":
    let
      window = newWindow("Text word commands", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("one two three", frame = initRect(10, 10, 180, 24))

    window.setKeyBindingProfile(kbpMacOS)
    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)

    field.selectedRange = initTextRange(0, 0)
    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmOption})
    )
    check field.selectedRange == initTextRange(3, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmOption})
    )
    check field.selectedRange == initTextRange(7, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord, modifiers: {kmOption})
    )
    check field.selectedRange == initTextRange(4, 0)

    check window.dispatchKeyDown(
      KeyEvent(
        key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmShift, kmOption}
      )
    )
    check field.selectedRange == initTextRange(4, 3)

    field.selectedRange = initTextRange(field.stringValue.len, 0)
    check window.dispatchKeyDown(
      KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord, modifiers: {kmOption})
    )
    check field.stringValue == "one two "
    check field.selectedRange == initTextRange(8, 0)

  test "windows profile uses control arrows for word movement":
    let
      window = newWindow("Text windows word commands", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("one two", frame = initRect(10, 10, 180, 24))

    window.setKeyBindingProfile(kbpWindows)
    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)

    field.selectedRange = initTextRange(0, 0)
    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmControl})
    )
    check field.selectedRange == initTextRange(3, 0)

    check window.dispatchKeyDown(
      KeyEvent(
        key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmShift, kmControl}
      )
    )
    check field.selectedRange == initTextRange(3, 4)

  test "control character text input after command shortcuts is ignored":
    let
      window = newWindow("Text control input", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abcdef", frame = initRect(10, 10, 180, 24))

    window.setKeyBindingProfile(kbpMacOS)
    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)
    field.selectedRange = initTextRange(6, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl})
    )
    check field.selectedRange == initTextRange(0, 0)

    discard window.dispatchKeyDown(KeyEvent(text: "\x01", keyCode: 0))
    check field.stringValue == "abcdef"
    check field.selectedRange == initTextRange(0, 0)

  test "select all shortcut selects and replaces the full value":
    let
      window = newWindow("Text select all", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abcdef", frame = initRect(10, 10, 140, 24))

    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)
    field.selectedRange = initTextRange(2, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: shortcutModifiers())
    )
    check field.selectedRange == initTextRange(0, 6)

    check window.dispatchKeyDown(KeyEvent(text: "q", key: keyQ, keyCode: keyQ.ord))
    check field.stringValue == "q"
    check field.selectedRange == initTextRange(1, 0)

  test "mouse down focuses text field and places caret at the end":
    let
      window = newWindow("Text mouse", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abcdef", frame = initRect(10, 10, 140, 24))

    root.addSubview(field)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(20, 20))
    check window.firstResponder == field
    check field.isFocused
    check not field.isFocusVisible
    check field.isEditing
    check field.selectedRange == initTextRange(6, 0)
