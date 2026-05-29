import std/tables

import pkg/chroma
import pkg/bumpy

import figdraw/commons
import figdraw/common/typefaces
import figdraw/fignodes

import ./buttons
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

proc addNode(list: var RenderList, parent: FigIdx, node: Fig): FigIdx =
  if parent == (-1).FigIdx:
    list.addRoot(node)
  else:
    list.addChild(parent, node)

proc renderViewInto(list: var RenderList, view: View, parent = (-1).FigIdx) =
  if view.visibleRect.isEmpty:
    return

  let absoluteFrame = view.rectToWindow(view.bounds)
  let rootIdx = list.addNode(parent, rectangleNode(absoluteFrame, view.backgroundColor))

  if view of Button:
    let button = Button(view)
    var fillColor = initColor(0.20, 0.48, 0.86, 1.0)
    if not button.isEnabled:
      fillColor = initColor(0.58, 0.62, 0.68, 1.0)
    elif button.isHighlighted:
      fillColor = initColor(0.12, 0.34, 0.68, 1.0)
    discard list.addChild(rootIdx, rectangleNode(absoluteFrame, fillColor))
    let textRect = initRect(
      absoluteFrame.origin.x + 8.0'f32,
      absoluteFrame.origin.y,
      max(absoluteFrame.size.width - 16.0'f32, 0.0'f32),
      absoluteFrame.size.height,
    )
    discard list.addChild(rootIdx, textNode(textRect, button.title, initColor(1, 1, 1)))
  elif view of TextField:
    let textField = TextField(view)
    discard list.addChild(
      rootIdx,
      textNode(
        absoluteFrame, textField.stringValue, textField.textColor, textField.alignment
      ),
    )

  for child in view.subviews:
    renderViewInto(list, child, rootIdx)

proc buildRenders*(root: View): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  if root.isNil:
    return
  var list = RenderList()
  renderViewInto(list, root)
  result.layers[0.ZLevel] = list
  root.clearNeedsDisplayTree()
