import std/unittest

import knutella/nimkit

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
