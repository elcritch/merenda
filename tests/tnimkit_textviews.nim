import std/unittest

import merenda/nimkit

suite "nimkit text views":
  test "text view inserts and replaces selected text":
    let textView = newTextView("abcdef", frame = initRect(0, 0, 160, 24))

    textView.selectedRange = initTextRange(2, 2)
    discard textView.send(insertText(), "XY")

    check textView.stringValue == "abXYef"
    check textView.selectedRange == initTextRange(4, 0)

  test "text view delete and movement commands update selection":
    let textView = newTextView("one two", frame = initRect(0, 0, 160, 24))

    textView.selectedRange = initTextRange(7, 0)
    discard textView.send(moveWordLeft(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.selectedRange == initTextRange(4, 0)

    discard
      textView.send(deleteWordForward(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.stringValue == "one "
    check textView.selectedRange == initTextRange(4, 0)

    discard textView.send(deleteBackward(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.stringValue == "one"
    check textView.selectedRange == initTextRange(3, 0)

  test "text view keeps attributed storage":
    let
      textView = newTextView("abc", frame = initRect(0, 0, 160, 24))
      accent = defaultTextAttributes(initColor(0.9, 0.1, 0.1))

    textView.textStorage().setAttributes(initTextRange(0, 3), accent)
    textView.selectedRange = initTextRange(1, 1)
    discard textView.send(insertText(), "Z")

    check textView.stringValue == "aZc"
    check textView.textStorage().attributesAt(1) == accent

  test "text view newline and tab commands insert text":
    let textView = newTextView("ab", frame = initRect(0, 0, 160, 24))

    textView.selectedRange = initTextRange(1, 0)
    discard textView.send(insertNewline(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.stringValue == "a\nb"
    check textView.selectedRange == initTextRange(2, 0)

    discard textView.send(insertTab(), ActionArgs(sender: DynamicAgent(textView)))
    check textView.stringValue == "a\n\tb"
    check textView.selectedRange == initTextRange(3, 0)
