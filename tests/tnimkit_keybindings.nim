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

  test "macOS key binding profile includes Cocoa text shortcuts":
    let bindings = initMacOSKeyBindings()

    check bindings
    .commandFor(KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl}))
    .get() == moveToBeginningOfLine()
    check bindings
    .commandFor(KeyEvent(key: keyE, keyCode: keyE.ord, modifiers: {kmControl}))
    .get() == moveToEndOfLine()
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
      KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord, modifiers: {kmOption})
    )
    .get() == deleteWordBackward()
    check bindings
    .commandFor(KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmCommand}))
    .get() == selectAll()

  test "windows key binding profile includes platform text shortcuts":
    let bindings = initWindowsKeyBindings()

    check bindings
    .commandFor(KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl}))
    .get() == selectAll()
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

  test "linux and bsd key binding profile includes platform text shortcuts":
    let bindings = initLinuxBsdKeyBindings()

    check bindings
    .commandFor(KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl}))
    .get() == selectAll()
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

  test "windows can switch key binding profiles at runtime":
    let window = newWindow("Key profile", frame = initRect(0, 0, 120, 80))

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
