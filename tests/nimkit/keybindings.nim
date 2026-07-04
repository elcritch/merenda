import std/unittest

import std/options

import merenda/nimkit

suite "nimkit key bindings":
  test "text helpers normalize printable keys":
    check keyForText("K") == keyK
    check keyForText(" ") == keySpace
    check keyForText("\n") == keyEnter
    check keyCodeForText("k") == keyK.ord

  test "key code helpers preserve native fallback":
    check keyForCode(keyArrowDown.ord) == keyArrowDown
    check keyForCode(-1) == keyUnknown

  test "shortcut modifiers resolve to platform primary modifier":
    check toKeyModifiers({smShortcut, smShift}) == shortcutModifiers() + {kmShift}

  test "text bindings match key events without text":
    let stroke = initKeyStroke("k", {kmCommand})
    check stroke.matches(KeyEvent(key: keyK, keyCode: keyK.ord, modifiers: {kmCommand}))
    check not stroke.matches(
      KeyEvent(key: keyK, keyCode: keyK.ord, modifiers: {kmControl})
    )

  test "default key bindings include basic text editing commands":
    let bindings = initDefaultKeyBindings()

    check bindings
    .commandFor(KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord))
    .get() == deleteBackward()
    check bindings.commandFor(KeyEvent(key: keyDelete, keyCode: keyDelete.ord)).get() ==
      deleteForward()
    check bindings
    .commandFor(KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord))
    .get() == moveLeft()
    check bindings
    .commandFor(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmShift})
    )
    .get() == moveRightAndModifySelection()
    check bindings
    .commandFor(KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: shortcutModifiers()))
    .get() == selectAll()
    check bindings.commandFor(KeyEvent(key: keyTab, keyCode: keyTab.ord)).get() ==
      insertTab()
    check bindings
    .commandFor(KeyEvent(key: keyTab, keyCode: keyTab.ord, modifiers: {kmShift}))
    .get() == insertBacktab()
    check bindings.commandFor(KeyEvent(key: keySpace, keyCode: keySpace.ord)).get() ==
      performClick()
    check bindings.commandFor(KeyEvent(key: keyEnter, keyCode: keyEnter.ord)).get() ==
      insertNewline()

  test "macOS key binding profile includes Cocoa text shortcuts":
    let bindings = initMacOSKeyBindings()

    check bindings
    .commandFor(KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl}))
    .get() == moveToBeginningOfLine()
    check bindings
    .commandFor(KeyEvent(key: keyE, keyCode: keyE.ord, modifiers: {kmControl}))
    .get() == moveToEndOfLine()
    check bindings
    .commandFor(KeyEvent(key: keyK, keyCode: keyK.ord, modifiers: {kmControl}))
    .get() == deleteToEndOfLine()
    check bindings
    .commandFor(
      KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord, modifiers: {kmOption})
    )
    .get() == moveWordLeft()
    check bindings
    .commandFor(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmOption})
    )
    .get() == moveWordRight()
    check bindings
    .commandFor(
      KeyEvent(
        key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmShift, kmOption}
      )
    )
    .get() == moveWordRightAndModifySelection()
    check bindings
    .commandFor(
      KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord, modifiers: {kmCommand})
    )
    .get() == moveToBeginningOfDocument()
    check bindings
    .commandFor(
      KeyEvent(
        key: keyArrowDown, keyCode: keyArrowDown.ord, modifiers: {kmCommand, kmShift}
      )
    )
    .get() == moveToEndOfDocumentAndModifySelection()
    check bindings
    .commandFor(
      KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord, modifiers: {kmOption})
    )
    .get() == deleteWordBackward()
    check bindings
    .commandFor(
      KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord, modifiers: {kmCommand})
    )
    .get() == deleteToBeginningOfLine()
    check bindings
    .commandFor(KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmCommand}))
    .get() == selectAll()
    check bindings
    .commandFor(KeyEvent(key: keyC, keyCode: keyC.ord, modifiers: {kmCommand}))
    .get() == copy()
    check bindings
    .commandFor(KeyEvent(key: keyX, keyCode: keyX.ord, modifiers: {kmCommand}))
    .get() == cut()
    check bindings
    .commandFor(KeyEvent(key: keyV, keyCode: keyV.ord, modifiers: {kmCommand}))
    .get() == paste()
    check bindings
    .commandFor(KeyEvent(key: keyZ, keyCode: keyZ.ord, modifiers: {kmCommand}))
    .get() == undo()
    check bindings
    .commandFor(KeyEvent(key: keyZ, keyCode: keyZ.ord, modifiers: {kmCommand, kmShift}))
    .get() == redo()

  test "windows key binding profile includes platform text shortcuts":
    let bindings = initWindowsKeyBindings()

    check bindings
    .commandFor(KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl}))
    .get() == selectAll()
    check bindings
    .commandFor(KeyEvent(key: keyC, keyCode: keyC.ord, modifiers: {kmControl}))
    .get() == copy()
    check bindings
    .commandFor(KeyEvent(key: keyX, keyCode: keyX.ord, modifiers: {kmControl}))
    .get() == cut()
    check bindings
    .commandFor(KeyEvent(key: keyV, keyCode: keyV.ord, modifiers: {kmControl}))
    .get() == paste()
    check bindings
    .commandFor(KeyEvent(key: keyZ, keyCode: keyZ.ord, modifiers: {kmControl}))
    .get() == undo()
    check bindings
    .commandFor(KeyEvent(key: keyY, keyCode: keyY.ord, modifiers: {kmControl}))
    .get() == redo()
    check bindings
    .commandFor(
      KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord, modifiers: {kmControl})
    )
    .get() == moveWordLeft()
    check bindings
    .commandFor(
      KeyEvent(
        key: keyArrowLeft, keyCode: keyArrowLeft.ord, modifiers: {kmShift, kmControl}
      )
    )
    .get() == moveWordLeftAndModifySelection()
    check bindings
    .commandFor(
      KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord, modifiers: {kmControl})
    )
    .get() == deleteWordBackward()
    check bindings
    .commandFor(KeyEvent(key: keyHome, keyCode: keyHome.ord, modifiers: {kmControl}))
    .get() == moveToBeginningOfDocument()
    check bindings
    .commandFor(
      KeyEvent(key: keyEnd, keyCode: keyEnd.ord, modifiers: {kmShift, kmControl})
    )
    .get() == moveToEndOfDocumentAndModifySelection()

  test "linux and bsd key binding profile includes platform text shortcuts":
    let bindings = initLinuxBsdKeyBindings()

    check bindings
    .commandFor(KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl}))
    .get() == selectAll()
    check bindings
    .commandFor(KeyEvent(key: keyC, keyCode: keyC.ord, modifiers: {kmControl}))
    .get() == copy()
    check bindings
    .commandFor(KeyEvent(key: keyX, keyCode: keyX.ord, modifiers: {kmControl}))
    .get() == cut()
    check bindings
    .commandFor(KeyEvent(key: keyV, keyCode: keyV.ord, modifiers: {kmControl}))
    .get() == paste()
    check bindings
    .commandFor(KeyEvent(key: keyZ, keyCode: keyZ.ord, modifiers: {kmControl}))
    .get() == undo()
    check bindings
    .commandFor(KeyEvent(key: keyY, keyCode: keyY.ord, modifiers: {kmControl}))
    .get() == redo()
    check bindings
    .commandFor(KeyEvent(key: keyE, keyCode: keyE.ord, modifiers: {kmControl}))
    .get() == moveToEndOfLine()
    check bindings
    .commandFor(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmControl})
    )
    .get() == moveWordRight()
    check bindings
    .commandFor(
      KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord, modifiers: {kmOption})
    )
    .get() == moveWordLeft()
    check bindings
    .commandFor(KeyEvent(key: keyHome, keyCode: keyHome.ord, modifiers: {kmControl}))
    .get() == moveToBeginningOfDocument()

  test "windows can switch key binding profiles at runtime":
    let window = newWindow("Key profile", frame = rect(0, 0, 120, 80))

    window.setKeyBindingProfile(kbpMacOS)
    check window
    .keyBindings()
    .commandFor(KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl}))
    .get() == moveToBeginningOfLine()

    window.setKeyBindingProfile(kbpWindows)
    check window
    .keyBindings()
    .commandFor(KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl}))
    .get() == selectAll()
