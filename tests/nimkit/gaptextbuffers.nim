import std/[strutils, unicode, unittest]

import merenda/nimkit

suite "nimkit gap text buffers":
  test "buffer replaces and slices by rune range":
    var buffer = initGapTextBuffer("alpha\nβeta\nomega")

    check buffer.len == "alpha\nβeta\nomega".runeLen
    check buffer.substring(initTextRange(0, 5)) == "alpha"

    buffer.replace(initTextRange(6, 4), "delta")
    check buffer.stringValue() == "alpha\ndelta\nomega"
    check buffer.substring(initTextRange(6, 5)) == "delta"

    buffer.replace(initTextRange(buffer.len, 0), "\nশেষ")
    check buffer.stringValue().endsWith("\nশেষ")

  test "buffer reports line and paragraph ranges":
    let buffer = initGapTextBuffer("one\ntwo\nthree")

    check buffer.lineCount() == 3
    check buffer.substring(buffer.lineRange(0)) == "one\n"
    check buffer.substring(buffer.lineRange(1)) == "two\n"
    check buffer.substring(buffer.lineRange(2)) == "three"
    check buffer.substring(buffer.paragraphRange(initTextRange(5, 0))) == "two\n"

  test "gap backed text storage preserves text storage behavior":
    let storage: TextStorage = newTextGapStorage("alpha\nβeta")

    check storage of TextGapStorage
    check storage.usesGapTextBuffer()
    check storage.len == "alpha\nβeta".runeLen
    check storage.substring(initTextRange(6, 4)) == "βeta"

    let attributes = defaultTextAttributes(color(1.0, 0.0, 0.0, 1.0), 15.0)
    storage.replace(initTextRange(6, 4), "delta", attributes)

    check storage.stringValue() == "alpha\ndelta"
    check storage.len == "alpha\ndelta".runeLen
    check storage.attributesAt(6).foregroundColor == attributes.foregroundColor

    let copy = storage.copyTextStorage()
    check copy of TextGapStorage
    check copy.usesGapTextBuffer()
    check copy.stringValue() == storage.stringValue()
    storage.replace(initTextRange(0, 5), "ALPHA")
    check copy.stringValue() == "alpha\ndelta"

    let slice = storage.sliceTextStorage(initTextRange(0, 5))
    check slice.stringValue() == "ALPHA"
    check storage.lineCount() == 2
    check storage.substring(storage.lineRange(1)) == "delta"

  test "text editor can use gap backed text storage":
    let
      storage = newTextGapStorage("hello")
      editor = newTextEditor(frame = rect(0, 0, 240, 80))

    editor.textStorage = storage
    check editor.textStorage().usesGapTextBuffer()
    check editor.stringValue() == "hello"

    editor.textStorage().replace(initTextRange(5, 0), " world")
    check editor.stringValue() == "hello world"

    editor.stringValue = "reset"
    check editor.textStorage().usesGapTextBuffer()
    check editor.stringValue() == "reset"
