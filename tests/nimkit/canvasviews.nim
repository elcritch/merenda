import std/[math, unittest]

import figdraw
import pkg/pixie as pixie

import merenda/nimkit

func hasKind(operation: CanvasOperation, kind: DrawableKind): bool =
  if operation.kind != cokDrawable:
    return false
  for drawOp in operation.drawOps:
    if drawOp.kind == kind:
      return true

suite "canvas views":
  test "canvas exposes a browser-style 2d context":
    let
      canvas = newCanvasView(rect(0, 0, 320, 200))
      context = canvas.getContext("2D")

    check context == canvas.getContext2D()
    check context.canvas == canvas
    expect CanvasContextError:
      discard canvas.getContext("webgl")

  test "drawing state supports CSS colors save and restore":
    let context = newCanvasView().getContext2D()

    context.fillStyle = "rebeccapurple"
    context.strokeStyle = "rgb(10, 20, 30)"
    context.globalAlpha = 2.0
    context.lineWidth = 4.0
    context.save()
    context.fillStyle = "#ff0000"
    context.lineWidth = 7.0
    context.restore()

    check context.fillStyle.toHtmlRgba() == "rgba(102, 51, 153, 1.0)"
    check context.strokeStyle.toHtmlRgba() == "rgba(10, 20, 30, 1.0)"
    check context.globalAlpha == 1.0
    check context.lineWidth == 4.0

  test "rectangle operations remain FigDraw drawables":
    let context = newCanvasView(rect(0, 0, 320, 200)).getContext2D()

    context.fillStyle = "#4f8fe8"
    context.fillRect(12, 18, 80, 44)
    context.strokeStyle = "#102030"
    context.lineWidth = 3.0
    context.strokeRect(110, 18, 90, 44)

    check context.len == 2
    check context[0].kind == cokDrawable
    check context[0].hasKind(dkRectangle)
    check context[1].kind == cokDrawable
    check context[1].hasKind(dkRectangle)
    check context[1].drawableLineWidth == 3.0

  test "stroked paths preserve FigDraw line curve and arc operations":
    let context = newCanvasView(rect(0, 0, 320, 200)).getContext2D()

    context.beginPath()
    context.moveTo(10, 10)
    context.lineTo(30, 20)
    context.quadraticCurveTo(45, 5, 60, 20)
    context.bezierCurveTo(70, 30, 85, 0, 100, 20)
    context.arc(120, 20, 14, PI.float32, 0.0)
    context.stroke()

    check context.len == 1
    check context[0].hasKind(dkLine)
    check context[0].hasKind(dkBezier)
    check context[0].hasKind(dkArc)

  test "simple circles remain drawables and complex fills use MTSDF":
    let context = newCanvasView(rect(0, 0, 320, 200)).getContext2D()

    context.beginPath()
    context.arc(50, 50, 20, 0.0, PI.float32 * 2.0)
    context.fill()

    context.beginPath()
    context.moveTo(120, 20)
    context.lineTo(155, 85)
    context.lineTo(90, 55)
    context.closePath()
    context.fill(cfrEvenOdd)

    check context.len == 2
    check context[0].kind == cokDrawable
    check context[0].hasKind(dkCircle)
    check context[1].kind == cokMtsdf
    check context[1].mtsdf.elementCount > 0
    check context[1].target.size.width > 0.0
    check context[1].target.size.height > 0.0

  test "images stay image operations and rendering retains their resource":
    let
      canvas = newCanvasView(rect(0, 0, 320, 200))
      context = canvas.getContext2D()
      pixels = pixie.newImage(8, 6)
      image = newImageResource(pixels, name = "canvas-stamp")

    context.drawImage(image, 20, 30)

    check context.len == 1
    check context[0].kind == cokImage
    check context[0].image == image
    check context[0].target == rect(20, 30, 8, 6)

    let renders = buildRenders(canvas)[DefaultDrawLevel]
    check renderResources(canvas).imageCount == 1
    check renders.nodes.len > 0

  test "retained operations can be cleared or truncated for live previews":
    let context = newCanvasView(rect(0, 0, 320, 200)).getContext2D()

    context.fillRect(0, 0, 10, 10)
    context.fillRect(20, 20, 10, 10)
    context.truncateOperations(1)
    check context.len == 1

    context.clear()
    check context.len == 0
