import std/unittest

import merenda/nimkit

suite "nimkit text fields":
  test "text fields default to editable selectable first-responder controls":
    let field = newTextField(0, 0, 120, 24, "abc")

    check field.isEditable
    check field.isSelectable
    check field.acceptsFirstResponder
    check field.clipsToBounds
    check field.selectedRange == initTextRange(3, 0)
    check field.insertionPoint == 3

  test "first responder text input replaces the current selection":
    let
      window = newWindow(0, 0, 240, 120, "Text input")
      root = newView(0, 0, 240, 120)
      field = newTextField(10, 10, 140, 24, "abc")

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

  test "default edit commands move and delete text":
    let
      window = newWindow(0, 0, 240, 120, "Text commands")
      root = newView(0, 0, 240, 120)
      field = newTextField(10, 10, 140, 24, "abcdef")

    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)

    field.setSelectedRange(initTextRange(3, 0))
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
      window = newWindow(0, 0, 240, 120, "Text word commands")
      root = newView(0, 0, 240, 120)
      field = newTextField(10, 10, 180, 24, "one two three")

    window.setKeyBindingProfile(kbpMacOS)
    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)

    field.setSelectedRange(initTextRange(0, 0))
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

    field.setSelectedRange(initTextRange(field.stringValue.len, 0))
    check window.dispatchKeyDown(
      KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord, modifiers: {kmOption})
    )
    check field.stringValue == "one two "
    check field.selectedRange == initTextRange(8, 0)

  test "windows profile uses control arrows for word movement":
    let
      window = newWindow(0, 0, 240, 120, "Text windows word commands")
      root = newView(0, 0, 240, 120)
      field = newTextField(10, 10, 180, 24, "one two")

    window.setKeyBindingProfile(kbpWindows)
    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)

    field.setSelectedRange(initTextRange(0, 0))
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
      window = newWindow(0, 0, 240, 120, "Text control input")
      root = newView(0, 0, 240, 120)
      field = newTextField(10, 10, 180, 24, "abcdef")

    window.setKeyBindingProfile(kbpMacOS)
    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)
    field.setSelectedRange(initTextRange(6, 0))

    check window.dispatchKeyDown(
      KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl})
    )
    check field.selectedRange == initTextRange(0, 0)

    discard window.dispatchKeyDown(KeyEvent(text: "\x01", keyCode: 0))
    check field.stringValue == "abcdef"
    check field.selectedRange == initTextRange(0, 0)

  test "select all shortcut selects and replaces the full value":
    let
      window = newWindow(0, 0, 240, 120, "Text select all")
      root = newView(0, 0, 240, 120)
      field = newTextField(10, 10, 140, 24, "abcdef")

    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)
    field.setSelectedRange(initTextRange(2, 0))

    check window.dispatchKeyDown(
      KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: shortcutModifiers())
    )
    check field.selectedRange == initTextRange(0, 6)

    check window.dispatchKeyDown(KeyEvent(text: "q", key: keyQ, keyCode: keyQ.ord))
    check field.stringValue == "q"
    check field.selectedRange == initTextRange(1, 0)

  test "mouse down focuses text field and places caret at the end":
    let
      window = newWindow(0, 0, 240, 120, "Text mouse")
      root = newView(0, 0, 240, 120)
      field = newTextField(10, 10, 140, 24, "abcdef")

    root.addSubview(field)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(20, 20))
    check window.firstResponder == field
    check field.isFocused
    check not field.isFocusVisible
    check field.isEditing
    check field.selectedRange == initTextRange(6, 0)
