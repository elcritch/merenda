## Window input dispatch, field editors, and text layout must agree on caret hits.
import std/unittest

import merenda/nimkit

template clickCaret(window: Window, view: TextView, point: Point, expected: int) =
  checkpoint "click=" & $point & ", expected caret=" & $expected
  let windowPoint = view.pointToWindow(point)
  check window.clickAt(windowPoint)
  check window.firstResponder() == Responder(view)
  check view.selectedRange == initTextRange(expected, 0)

suite "caret click integration":
  test "field editor clicks agree with text input client geometry":
    let
      window = newWindow("Caret clicks", frame = rect(0, 0, 360, 160))
      root = newView(frame = rect(0, 0, 360, 160))
      field = newTextField("abcdef", frame = rect(37, 29, 240, 34))
    defer:
      window.close()
    root.addSubview(field)
    window.setContentView(root)
    require window.makeFirstResponder(field)
    let
      editor = TextView(window.fieldEditor())
      first = editor.layoutManager().caretRect(3)
      second = editor.layoutManager().caretRect(4)
      y = first.origin.y + first.size.height / 2
      center = (first.origin.x + second.origin.x) / 2
      glyph = editor.firstRectForCharacterRange(initTextRange(3, 1))
      glyphCenter = initPoint(
        glyph.origin.x + glyph.size.width / 2, glyph.origin.y + glyph.size.height / 2
      )
    check editor.characterIndexForPoint(glyphCenter) == 3
    check window.clickAt(glyphCenter)
    check field.selectedRange == initTextRange(3, 0)
    for index, x in [
      first.origin.x, center - 0.25'f32, center, center + 0.25'f32, second.origin.x
    ]:
      window.clickCaret(editor, initPoint(x, y), [3, 3, 3, 4, 4][index])

  test "text view clicks choose the nearest caret after translating the container":
    for origin in [0.0'f32, 100000.0'f32, 1000000.0'f32]:
      for text in ["abcdef", "אבגדהו"]:
        checkpoint "origin=" & $origin & ", text=" & text
        let
          size = initSize(origin + 300, 100)
          window =
            newWindow("Translated caret clicks", frame = rect(initPoint(0, 0), size))
          view = newTextView(text, frame = rect(initPoint(0, 0), size))
        defer:
          window.close()
        window.setContentView(view)
        view.textContainer =
          initTextContainer(initSize(240, 80), origin = initPoint(origin, 0))
        require window.makeFirstResponder(view)
        let
          first = view.layoutManager().caretRect(3)
          second = view.layoutManager().caretRect(4)
          midpoint = (first.origin.x + second.origin.x) / 2
          y = first.origin.y + first.size.height / 2
          direction = if second.origin.x > first.origin.x: 1.0'f32 else: -1.0'f32
        require abs(first.origin.x - second.origin.x) > 1
        window.clickCaret(view, initPoint(first.origin.x, y), 3)
        window.clickCaret(view, initPoint(second.origin.x, y), 4)
        window.clickCaret(view, initPoint(midpoint, y), 3)
        for index in [3, 4]:
          let x = midpoint + (if index == 3: -direction else: direction) * 0.25'f32
          # Establish that float rounding still leaves an unambiguous nearest caret.
          let
            firstDistance = abs(x - first.origin.x)
            secondDistance = abs(x - second.origin.x)
          require (
            if index == 3: firstDistance < secondDistance
            else: secondDistance < firstDistance
          )
          window.clickCaret(view, initPoint(x, y), index)
