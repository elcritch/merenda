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
    .commandFor(KeyEvent(key: keyP, keyCode: keyP.ord, modifiers: {kmControl}))
    .get() == moveUp()
    check bindings
    .commandFor(KeyEvent(key: keyN, keyCode: keyN.ord, modifiers: {kmControl}))
    .get() == moveDown()
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

  test "shortcut descriptions parse command keys and shifted braces":
    let
      save = parseKeyStroke("cmd-s")
      previous = parseKeyStroke("cmd-{")
      alternate = parseKeyStroke("ctrl-option-shift-p")

    check save.key == keyS
    check save.modifiers == {kmCommand}
    check previous.key == keyLeftBracket
    check previous.modifiers == {kmCommand, kmShift}
    check alternate.key == keyP
    check alternate.modifiers == {kmControl, kmOption, kmShift}
    expect ValueError:
      discard parseKeyStroke("cmd-mystery")

  test "shortcut descriptions parse multi-stroke sequences":
    let sequence = parseKeySequence("ctrl-w ctrl-s")
    let
      prefixEvent = KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
      commandEvent = KeyEvent(key: keyS, keyCode: keyS.ord, modifiers: {kmControl})
      action = actionSelector("demo.split")
    var bindings: KeyBindingTable
    bindings.add(sequence, action)

    check sequence.strokes.len == 2
    check sequence.strokes[0] == initKeyStroke(keyW, {kmControl})
    check sequence.strokes[1] == initKeyStroke(keyS, {kmControl})
    check bindings.match([prefixEvent]).kind == kbmPrefix
    let commandMatch = bindings.match([prefixEvent, commandEvent])
    check commandMatch.kind == kbmCommand
    check commandMatch.selector == action
    check bindings.commandFor(prefixEvent).isNone

  test "bindings reject a command that is also a sequence prefix":
    var bindings: KeyBindingTable
    bindings.add(parseKeySequence("ctrl-w ctrl-s"), actionSelector("demo.split"))

    expect ValueError:
      bindings.add(parseKeySequence("ctrl-w"), actionSelector("demo.close"))

  test "conflicting JSON sequences leave existing bindings unchanged":
    let
      saveAction = actionSelector("demo.save")
      leaderAction = actionSelector("demo.leader")
    var bindings: KeyBindingTable
    bindings.bindKey(keyS, {kmCommand}, saveAction)
    bindings.bindKey(keyW, {kmControl}, leaderAction)

    let outcome = bindings.applyKeyBindingOverridesJson(
      """{"demo.save": "ctrl-w ctrl-s"}""", ["demo.save"]
    )

    check not outcome.succeeded
    check bindings
    .commandFor(KeyEvent(key: keyS, keyCode: keyS.ord, modifiers: {kmCommand}))
    .get() == saveAction
    check bindings
    .commandFor(KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl}))
    .get() == leaderAction

  test "JSON key binding overrides support shortcut sequences":
    let action = actionSelector("demo.split")
    var bindings: KeyBindingTable

    let outcome = bindings.applyKeyBindingOverridesJson(
      """{"demo.split": "ctrl-w ctrl-s"}""", ["demo.split"]
    )
    let bindingMatch = bindings.match(
      [
        KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl}),
        KeyEvent(key: keyS, keyCode: keyS.ord, modifiers: {kmControl}),
      ]
    )

    check outcome.succeeded
    check bindingMatch.kind == kbmCommand
    check bindingMatch.selector == action

  test "JSON key binding overrides replace and disable commands":
    let
      nextAction = actionSelector("demo.next")
      closeAction = actionSelector("demo.close")
    var bindings: KeyBindingTable
    bindings.bindKey(keyN, {kmCommand}, nextAction)
    bindings.bindKey(keyW, {kmCommand}, closeAction)

    let outcome = bindings.applyKeyBindingOverridesJson(
      """
      {
        "demo.next": ["cmd-}", "cmd-j"],
        "demo.close": null
      }
      """,
      ["demo.next", "demo.close"],
    )

    check outcome.succeeded
    check outcome.applied == 2
    check bindings.commandFor(
      KeyEvent(key: keyN, keyCode: keyN.ord, modifiers: {kmCommand})
    ).isNone
    check bindings
    .commandFor(
      KeyEvent(
        key: keyRightBracket,
        keyCode: keyRightBracket.ord,
        modifiers: {kmCommand, kmShift},
      )
    )
    .get() == nextAction
    check bindings
    .commandFor(KeyEvent(key: keyJ, keyCode: keyJ.ord, modifiers: {kmCommand}))
    .get() == nextAction
    check bindings.commandFor(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmCommand})
    ).isNone

  test "invalid JSON overrides leave the existing command binding intact":
    let action = actionSelector("demo.save")
    var bindings: KeyBindingTable
    bindings.bindKey(keyS, {kmCommand}, action)

    let outcome = bindings.applyKeyBindingOverridesJson(
      """{"demo.save": "cmd-unknown"}""", ["demo.save"]
    )

    check not outcome.succeeded
    check outcome.errors.len == 1
    check bindings
    .commandFor(KeyEvent(key: keyS, keyCode: keyS.ord, modifiers: {kmCommand}))
    .get() == action
