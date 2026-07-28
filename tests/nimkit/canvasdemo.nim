import std/[strutils, unittest]

import merenda/nimkit

import ../../examples/canvas_demo

proc drawGesture(canvas: CanvasDrawingView, start, stop: Point) =
  check canvas.mouseDown(MouseEvent(location: start, button: mbPrimary))
  check canvas.mouseDragged(MouseEvent(location: stop, button: mbPrimary))
  check canvas.mouseUp(MouseEvent(location: stop, button: mbPrimary))

suite "NimKit canvas demo":
  test "shape palette draws retained primitives and complex MTSDF fills":
    let
      demo = newCanvasDemo()
      context = demo.canvas.getContext2D()

    check demo.canvas.selectedTool == ctFreehand
    check context.len == 0
    check not demo.undoButton.enabled

    check demo.toolButtons[ctRectangle].sendAction()
    check demo.canvas.selectedTool == ctRectangle
    demo.canvas.drawGesture(initPoint(20, 30), initPoint(140, 100))

    check context.len == 2
    check context[0].kind == cokDrawable
    check context[1].kind == cokDrawable
    check demo.undoButton.enabled

    demo.canvas.undoLast()
    check context.len == 0
    check not demo.undoButton.enabled

    check demo.toolButtons[ctStar].sendAction()
    demo.canvas.drawGesture(initPoint(60, 30), initPoint(180, 150))

    check context.len == 2
    check context[0].kind == cokMtsdf
    check context[1].kind == cokDrawable
    check demo.statusLabel.text.contains("Star added")

  test "pencil color width image clear and keyboard undo stay interactive":
    let
      demo = newCanvasDemo()
      context = demo.canvas.getContext2D()

    check demo.fillWell.activateColorAtIndex(7)
    check demo.canvas.fillColor == demo.fillWell.color

    demo.widthSlider.value = 8.0
    check demo.widthSlider.sendAction()
    check demo.canvas.drawingLineWidth == 8.0
    check demo.widthLabel.text == "8 px"

    demo.canvas.drawGesture(initPoint(10, 10), initPoint(80, 55))
    check context.len == 1
    check context[0].kind == cokDrawable
    check context[0].drawableLineWidth == 8.0

    check demo.toolButtons[ctImageStamp].sendAction()
    check demo.canvas.mouseDown(
      MouseEvent(location: initPoint(160, 90), button: mbPrimary)
    )
    check context.len == 2
    check context[1].kind == cokImage

    check demo.canvas.keyDown(
      KeyEvent(key: keyZ, keyCode: keyZ.ord, modifiers: {kmCommand})
    )
    check context.len == 1

    check demo.clearButton.sendAction()
    check context.len == 0
    check demo.undoButton.enabled

    demo.canvas.undoLast()
    check context.len == 1
    check demo.canvas.itemCount == 1

  test "select tool edits moves deletes and restores existing items":
    let
      demo = newCanvasDemo()
      context = demo.canvas.getContext2D()

    check demo.toolButtons[ctRectangle].sendAction()
    demo.canvas.drawGesture(initPoint(20, 30), initPoint(140, 100))
    check demo.canvas.itemCount == 1

    check demo.toolButtons[ctSelect].sendAction()
    check demo.canvas.mouseDown(
      MouseEvent(location: initPoint(80, 65), button: mbPrimary)
    )
    check demo.canvas.mouseUp(
      MouseEvent(location: initPoint(80, 65), button: mbPrimary)
    )
    check demo.canvas.selectedItemIndex == 0
    check demo.deleteButton.enabled
    check context.len == 3

    check demo.canvas.mouseDown(
      MouseEvent(location: initPoint(80, 65), button: mbPrimary)
    )
    check demo.canvas.mouseDragged(
      MouseEvent(location: initPoint(110, 90), button: mbPrimary)
    )
    check demo.canvas.mouseUp(
      MouseEvent(location: initPoint(110, 90), button: mbPrimary)
    )
    check demo.canvas.selectedItemBounds == rect(50, 55, 120, 70)
    check demo.statusLabel.text.contains("Selected item moved")

    check demo.fillWell.activateColorAtIndex(7)
    check context[0].drawableFill == demo.fillWell.color

    demo.widthSlider.value = 9.0
    check demo.widthSlider.sendAction()
    check context[1].drawableLineWidth == 9.0

    check demo.deleteButton.sendAction()
    check demo.canvas.itemCount == 0
    check context.len == 0
    check not demo.deleteButton.enabled

    demo.canvas.undoLast()
    check demo.canvas.itemCount == 1
    check context.len == 2
    check context[0].drawableFill == demo.fillWell.color
    check context[1].drawableLineWidth == 9.0
