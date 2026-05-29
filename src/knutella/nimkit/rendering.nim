import std/tables

import pkg/chroma
import pkg/bumpy

import figdraw/commons
import figdraw/common/typefaces
import figdraw/fignodes

import ./buttons
import ./drawing
import ./selectors
import ./textfields
import ./types
import ./views

var defaultTypefaceId {.threadvar.}: TypefaceId
var defaultTypefaceReady {.threadvar.}: bool

proc toFigRect(rect: types.Rect): bumpy.Rect =
  bumpy.rect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)

proc defaultFont(size: float32): FigFont =
  if not defaultTypefaceReady:
    defaultTypefaceId = loadTypeface("Ubuntu.ttf", ["HackNerdFont-Regular.ttf"])
    defaultTypefaceReady = true
  defaultTypefaceId.fontWithSize(size)

proc rectangleNode(rect: types.Rect, color: types.Color): Fig =
  Fig(
    kind: nkRectangle,
    screenBox: rect.toFigRect,
    flags: {NfClipContent},
    fill: fill(color.rgba),
    stroke: RenderStroke(weight: 0.0, fill: fill(rgba(0, 0, 0, 0))),
  )

proc toFontHorizontal(alignment: TextAlignment): FontHorizontal =
  case alignment
  of taLeft: Left
  of taCenter: Center
  of taRight: Right

proc textNode(
    rect: types.Rect, text: string, color: types.Color, alignment = taLeft
): Fig =
  let
    font = defaultFont(13.0'f32)
    style = fs(font, fill(color.rgba))
    layout = typeset(
      rect.toFigRect,
      [(style, text)],
      hAlign = alignment.toFontHorizontal,
      vAlign = Middle,
      minContent = false,
      wrap = false,
    )
  Fig(kind: nkText, screenBox: rect.toFigRect, textLayout: layout)

proc beginDraw(context: DrawContext, view: View, parent: FigIdx) =
  context.beginDraw(
    parent, view.pointToWindow(initPoint(0.0, 0.0)), view.bounds, view.visibleRect
  )

proc addRectangle*(
    context: DrawContext, rect: types.Rect, color: types.Color
): FigIdx {.discardable.} =
  context.addFig(rectangleNode(context.localRectToWindow(rect), color))

proc addText*(
    context: DrawContext,
    rect: types.Rect,
    text: string,
    color: types.Color,
    alignment = taLeft,
): FigIdx {.discardable.} =
  context.addFig(textNode(context.localRectToWindow(rect), text, color, alignment))

proc renderBuiltInView(context: DrawContext, view: View, rootIdx: FigIdx) =
  let absoluteFrame = view.rectToWindow(view.bounds)

  if view of Button:
    let button = Button(view)
    var fillColor = initColor(0.20, 0.48, 0.86, 1.0)
    if not button.isEnabled:
      fillColor = initColor(0.58, 0.62, 0.68, 1.0)
    elif button.isHighlighted:
      fillColor = initColor(0.12, 0.34, 0.68, 1.0)
    discard context.addFig(rootIdx, rectangleNode(absoluteFrame, fillColor))
    let textRect = initRect(
      view.bounds.origin.x + 8.0'f32,
      view.bounds.origin.y,
      max(view.bounds.size.width - 16.0'f32, 0.0'f32),
      view.bounds.size.height,
    )
    context.addText(textRect, button.title, initColor(1, 1, 1))
  elif view of TextField:
    let textField = TextField(view)
    context.addText(
      view.bounds, textField.stringValue, textField.textColor, textField.alignment
    )

proc renderViewInto(context: DrawContext, view: View, parent = (-1).FigIdx) =
  if view.visibleRect.isEmpty:
    return

  let absoluteFrame = view.rectToWindow(view.bounds)
  let rootIdx =
    context.addFig(parent, rectangleNode(absoluteFrame, view.backgroundColor))
  context.beginDraw(view, rootIdx)

  if not view.sendIfHandled(draw(), context):
    renderBuiltInView(context, view, rootIdx)

  for child in view.subviews:
    renderViewInto(context, child, rootIdx)

proc buildRenders*(root: View): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  if root.isNil:
    return
  let context = initDrawContext()
  renderViewInto(context, root)
  result.layers[0.ZLevel] = context.renderList
  root.clearNeedsDisplayTree()
