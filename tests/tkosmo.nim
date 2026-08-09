import std/[strutils, unittest]

import merenda/kosmo/moe

proc renderedText(buffer: RenderBuffer): string =
  for row in 0 ..< buffer.height:
    for column in 0 ..< buffer.width:
      result.add buffer.cell(column, row).symbol
    result.add '\n'

suite "Kosmo":
  test "renders initial text into a cell grid":
    let editor = newKosmoEditor(text = "hello")
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    check "hello" in buffer.renderedText
    editor.close()

  test "text input and physical keys use Moe's frontend API":
    let editor = newKosmoEditor()
    var buffer = newRenderBuffer(24, 8)

    check editor.handleKey("i")
    check editor.handleTextInput("λ")
    check editor.handleKey("Esc")
    editor.render(buffer)

    check "λ" in buffer.renderedText
    editor.close()

  test "scroll input reports a frontend-neutral outcome":
    let editor = newKosmoEditor(text = "one\ntwo\nthree")
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    let outcome = editor.handleScrollInput(initScrollInput(2, 2, 1))
    check outcome.requestedRows == 1
    check outcome.region.rows >= 0
    check outcome.region.columns >= 0
    editor.close()
