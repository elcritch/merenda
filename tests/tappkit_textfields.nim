import std/unittest
import std/unicode

import knutella/appkit
import figdraw/fignodes
import siwin/window as siwin

proc sendKey(
    window: NSWindow,
    key: siwin.Key,
    repeated = false,
    pressed = true,
    generated = false,
    modifiers: set[siwin.ModifierKey] = {},
) =
  let event = keyEventFromSiwin(
    window.windowNumber(),
    nsPoint(12, 12),
    siwin.KeyEvent(
      key: key,
      pressed: pressed,
      repeated: repeated,
      generated: generated,
      modifiers: modifiers,
    ),
  )
  window.sendEvent(event)

proc sendText(window: NSWindow, text: string, repeated = false) =
  let event = textInputEventFromSiwin(
    window.windowNumber(),
    nsPoint(12, 12),
    siwin.TextInputEvent(text: text, repeated: repeated),
  )
  window.sendEvent(event)

proc functionKeyString(code: int): NSString =
  var value = ""
  value.add Rune(code)
  ns(value)

proc sendAppKey(
    app: NSApplication,
    window: NSWindow,
    key: siwin.Key,
    repeated = false,
    pressed = true,
    modifiers: set[siwin.ModifierKey] = {},
) =
  let event = keyEventFromSiwin(
    window.windowNumber(),
    nsPoint(12, 12),
    siwin.KeyEvent(
      key: key,
      pressed: pressed,
      repeated: repeated,
      generated: false,
      modifiers: modifiers,
    ),
  )
  app.sendEvent(event)

proc sendAppText(app: NSApplication, window: NSWindow, text: string, repeated = false) =
  let event = textInputEventFromSiwin(
    window.windowNumber(),
    nsPoint(12, 12),
    siwin.TextInputEvent(text: text, repeated: repeated),
  )
  app.sendEvent(event)

proc newTextHarness(
    initial = "abcd"
): tuple[window: NSWindow, root: NSView, field: NSTextField] =
  result.window = newWindow(0, 0, 240, 100, "Text Harness")
  result.root = newView(0, 0, 240, 100)
  result.field = newTextField(10, 10, 180, 24, initial)
  result.root.addSubview(result.field)
  result.window.setContentView(result.root)
  doAssert result.window.makeFirstResponder(result.field)
  result.field.setSelectedRange(NSMakeRange(initial.runeLen.uint, 0))

proc disposeTextHarness(
    window: var NSWindow, root: var NSView, field: var NSTextField
) =
  field.value = nil
  root.value = nil
  window.value = nil

proc checkSelection(field: NSTextField, location: int, length: int) =
  let selected = field.selectedRange()
  check selected.location.int == location
  check selected.length.int == length

suite "appkit text fields":
  test "becoming first responder selects all text":
    var window = newWindow(0, 0, 240, 100, "Text Harness")
    var root = newView(0, 0, 240, 100)
    var field = newTextField(10, 10, 180, 24, "abcdef")
    root.addSubview(field)
    window.setContentView(root)

    doAssert window.makeFirstResponder(field)
    checkSelection(field, 0, 6)

    field.value = nil
    root.value = nil
    window.value = nil

  test "left and right arrows move insertion point for single key presses":
    var (window, root, field) = newTextHarness("abcd")

    sendKey(window, siwin.Key.left)
    sendKey(window, siwin.Key.left)
    sendText(window, "Z")
    check(field.stringValue() == @ns"abZcd")

    sendKey(window, siwin.Key.right)
    sendText(window, "Y")
    check(field.stringValue() == @ns"abZcYd")

    disposeTextHarness(window, root, field)

  test "left arrow repeat events keep moving insertion point":
    var (window, root, field) = newTextHarness("abcd")

    sendKey(window, siwin.Key.left, repeated = true)
    sendKey(window, siwin.Key.left, repeated = true)
    sendKey(window, siwin.Key.left, repeated = true)
    sendText(window, "Q")
    check(field.stringValue() == @ns"aQbcd")

    disposeTextHarness(window, root, field)

  test "delete backward and delete forward edit around insertion point":
    var (window, root, field) = newTextHarness("abcd")

    sendKey(window, siwin.Key.left)
    sendKey(window, siwin.Key.backspace)
    check(field.stringValue() == @ns"abd")

    sendKey(window, siwin.Key.del)
    check(field.stringValue() == @ns"ab")

    disposeTextHarness(window, root, field)

  test "multi-step cursor movement and deletes keep editing state consistent":
    var (window, root, field) = newTextHarness("abcdef")

    # Start at end, move to between d and e.
    sendKey(window, siwin.Key.left)
    sendKey(window, siwin.Key.left)

    # Delete d and then c with backspace.
    sendKey(window, siwin.Key.backspace)
    check(field.stringValue() == @ns"abcef")
    sendKey(window, siwin.Key.backspace)
    check(field.stringValue() == @ns"abef")

    # Move right (between e and f), then delete forward (remove f).
    sendKey(window, siwin.Key.right)
    sendKey(window, siwin.Key.del)
    check(field.stringValue() == @ns"abe")

    # Move to beginning, delete a then b.
    sendKey(window, siwin.Key.home)
    sendKey(window, siwin.Key.del)
    check(field.stringValue() == @ns"be")
    sendKey(window, siwin.Key.del)
    check(field.stringValue() == @ns"e")

    # Move to end and backspace final character.
    sendKey(window, siwin.Key.End)
    sendKey(window, siwin.Key.backspace)
    check(field.stringValue() == @ns"")

    disposeTextHarness(window, root, field)

  test "home and end keys move insertion point to line boundaries":
    var (window, root, field) = newTextHarness("abcd")

    sendKey(window, siwin.Key.home)
    sendText(window, "^")
    check(field.stringValue() == @ns"^abcd")

    sendKey(window, siwin.Key.End)
    sendText(window, "$")
    check(field.stringValue() == @ns"^abcd$")

    disposeTextHarness(window, root, field)

  test "insert text at start middle and end positions":
    var (window, root, field) = newTextHarness("abcd")

    # Insert in the middle (between b and c).
    sendKey(window, siwin.Key.left)
    sendKey(window, siwin.Key.left)
    sendText(window, "MID")
    check(field.stringValue() == @ns"abMIDcd")

    # Insert at the start.
    sendKey(window, siwin.Key.home)
    sendText(window, "START-")
    check(field.stringValue() == @ns"START-abMIDcd")

    # Insert at the end.
    sendKey(window, siwin.Key.End)
    sendText(window, "-END")
    check(field.stringValue() == @ns"START-abMIDcd-END")

    disposeTextHarness(window, root, field)

  test "insertions remain correct after mixed movement and deletes":
    var (window, root, field) = newTextHarness("wxyz")

    sendKey(window, siwin.Key.left) # wxy|z
    sendKey(window, siwin.Key.backspace) # wx|z
    check(field.stringValue() == @ns"wxz")

    sendText(window, "Q") # wxQ|z
    check(field.stringValue() == @ns"wxQz")

    sendKey(window, siwin.Key.right) # wxQz|
    sendText(window, "R") # wxQzR|
    check(field.stringValue() == @ns"wxQzR")

    sendKey(window, siwin.Key.End) # wxQzR|
    sendText(window, "!")
    check(field.stringValue() == @ns"wxQzR!")

    disposeTextHarness(window, root, field)

  test "shift arrows create selection and insertion replaces selected text":
    var (window, root, field) = newTextHarness("abcdef")

    sendKey(window, siwin.Key.left, modifiers = {siwin.ModifierKey.shift})
    checkSelection(field, 5, 1)
    sendKey(window, siwin.Key.left, modifiers = {siwin.ModifierKey.shift})
    checkSelection(field, 4, 2)

    sendText(window, "!")
    check(field.stringValue() == @ns"abcd!")
    checkSelection(field, 5, 0)

    disposeTextHarness(window, root, field)

  test "selection delete then cursor move then delete again":
    var (window, root, field) = newTextHarness("abcdef")

    sendKey(window, siwin.Key.left, modifiers = {siwin.ModifierKey.shift})
    sendKey(window, siwin.Key.left, modifiers = {siwin.ModifierKey.shift})
    checkSelection(field, 4, 2)
    sendKey(window, siwin.Key.backspace)
    check(field.stringValue() == @ns"abcd")
    checkSelection(field, 4, 0)

    sendKey(window, siwin.Key.left)
    checkSelection(field, 3, 0)
    sendKey(window, siwin.Key.backspace)
    check(field.stringValue() == @ns"abd")
    checkSelection(field, 2, 0)

    sendKey(window, siwin.Key.del)
    check(field.stringValue() == @ns"ab")
    checkSelection(field, 2, 0)

    disposeTextHarness(window, root, field)

  test "programmatic selectedRange replacement works at various positions":
    var (window, root, field) = newTextHarness("abcdef")

    field.setSelectedRange(NSMakeRange(0, 2))
    sendText(window, "XY")
    check(field.stringValue() == @ns"XYcdef")
    checkSelection(field, 2, 0)

    field.setSelectedRange(NSMakeRange(2, 2))
    sendText(window, "M")
    check(field.stringValue() == @ns"XYMef")
    checkSelection(field, 3, 0)

    field.setSelectedRange(NSMakeRange(4, 1))
    sendText(window, "ZQ")
    check(field.stringValue() == @ns"XYMeZQ")
    checkSelection(field, 6, 0)

    disposeTextHarness(window, root, field)

  test "function-key character fallback routes move commands when siwin key is unknown":
    var (window, root, field) = newTextHarness("abcd")
    let leftFn = functionKeyString(NSLeftArrowFunctionKey.int)

    let leftFunctionEvent = newKeyEvent(
      NSKeyDown,
      nsPoint(12, 12),
      {},
      0.0,
      window.windowNumber().int,
      leftFn,
      leftFn,
      false,
      0'u16,
    )
    window.sendEvent(leftFunctionEvent)
    sendText(window, "Z")
    check(field.stringValue() == @ns"abcZd")

    disposeTextHarness(window, root, field)

  test "function-key fallback with shift extends selection":
    var (window, root, field) = newTextHarness("abcd")
    let leftFn = functionKeyString(NSLeftArrowFunctionKey.int)

    let shiftedLeftFunctionEvent = newKeyEvent(
      NSKeyDown,
      nsPoint(12, 12),
      {NSShiftKeyMask},
      0.0,
      window.windowNumber().int,
      leftFn,
      leftFn,
      false,
      0'u16,
    )
    window.sendEvent(shiftedLeftFunctionEvent)
    checkSelection(field, 3, 1)
    sendText(window, "Z")
    check(field.stringValue() == @ns"abcZ")

    disposeTextHarness(window, root, field)

  test "application event path handles arrow moves and insertion":
    var app = NSApplication.new()
    var (window, root, field) = newTextHarness("abcd")
    app.addWindow(window)

    sendAppKey(app, window, siwin.Key.left, pressed = true)
    sendAppKey(app, window, siwin.Key.left, pressed = false)
    sendAppText(app, window, "X")
    check(field.stringValue() == @ns"abcXd")

    sendAppKey(app, window, siwin.Key.left, pressed = true)
    sendAppKey(app, window, siwin.Key.left, pressed = false)
    sendAppText(app, window, "Y")
    check(field.stringValue() == @ns"abcYXd")

    sendAppKey(app, window, siwin.Key.right, pressed = true)
    sendAppKey(app, window, siwin.Key.right, pressed = false)
    sendAppText(app, window, "Z")
    check(field.stringValue() == @ns"abcYXZd")

    field.value = nil
    root.value = nil
    window.value = nil
    app.value = nil

  test "queued application events preserve cursor movement before text input":
    var app = NSApplication.new()
    var (window, root, field) = newTextHarness("abcd")
    app.addWindow(window)

    app.postEvent(
      keyEventFromSiwin(
        window.windowNumber(),
        nsPoint(12, 12),
        siwin.KeyEvent(
          key: siwin.Key.left, pressed: true, repeated: false, generated: false
        ),
      ),
      false,
    )
    app.postEvent(
      keyEventFromSiwin(
        window.windowNumber(),
        nsPoint(12, 12),
        siwin.KeyEvent(
          key: siwin.Key.left, pressed: true, repeated: true, generated: false
        ),
      ),
      false,
    )
    app.postEvent(
      textInputEventFromSiwin(
        window.windowNumber(),
        nsPoint(12, 12),
        siwin.TextInputEvent(text: "Q", repeated: false),
      ),
      false,
    )

    var safety = 0
    while safety < 10:
      let next =
        app.nextEventMatchingMask(NSAnyEventMask, 0.0, @ns"NSDefaultRunLoopMode", true)
      if next.isNil:
        break
      app.sendEvent(next)
      inc safety

    check(field.stringValue() == @ns"abQcd")

    field.value = nil
    root.value = nil
    window.value = nil
    app.value = nil

  test "text field selection uses figdraw text selection flags and range":
    var (window, root, field) = newTextHarness("abcdef")
    field.setSelectedRange(NSMakeRange(2, 3))

    let renders = debugBuildWindowRenders(window)
    check(not renders.isNil)

    var sawSelectedText = false
    for _, list in renders.layers.pairs:
      for node in list.nodes:
        if node.kind != nkText or node.textLayout.runes.len <= 0:
          continue
        sawSelectedText = true
        check(NfSelectText in node.flags)
        check(node.selectionRange.a.int == 2)
        check(node.selectionRange.b.int == 4)
    check(sawSelectedText)

    disposeTextHarness(window, root, field)
