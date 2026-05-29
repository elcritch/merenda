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
import ./theme
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

proc cornerRadii(radius: float32): array[DirectionCorners, uint16] =
  let clamped = max(radius, 0.0'f32)
  for corner in DirectionCorners:
    result[corner] = clamped.round().uint16

proc rectangleNode(
    rect: types.Rect,
    color: types.Color,
    strokeColor = initColor(0.0, 0.0, 0.0, 0.0),
    strokeWidth = 0.0'f32,
    cornerRadius = 0.0'f32,
): Fig =
  Fig(
    kind: nkRectangle,
    screenBox: rect.toFigRect,
    flags: {NfClipContent},
    fill: fill(color.rgba),
    corners: cornerRadii(cornerRadius),
    stroke: RenderStroke(weight: strokeWidth, fill: fill(strokeColor.rgba)),
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

proc renderBuiltInView(
    context: DrawContext, view: View, rootIdx: FigIdx, appearance: Appearance
) =
  let absoluteFrame = view.rectToWindow(view.bounds)

  if view of Button:
    let button = Button(view)
    let style = appearance.resolveButtonStyle(
      initControlStyleContext(
        srButton, enabled = button.isEnabled, highlighted = button.isHighlighted
      )
    )
    discard context.addFig(
      rootIdx,
      rectangleNode(
        absoluteFrame, style.box.fill, style.box.borderColor, style.box.borderWidth,
        style.box.cornerRadius,
      ),
    )
    context.addText(style.buttonTextRect(view.bounds), button.title, style.text.color)
  elif view of TextField:
    let textField = TextField(view)
    let style = appearance.resolveTextFieldStyle(
      initControlStyleContext(srTextField, enabled = textField.isEnabled),
      textField.textColor,
    )
    discard context.addFig(
      rootIdx,
      rectangleNode(
        absoluteFrame, style.box.fill, style.box.borderColor, style.box.borderWidth,
        style.box.cornerRadius,
      ),
    )
    context.addText(
      style.textFieldTextRect(view.bounds),
      textField.stringValue,
      style.text.color,
      textField.alignment,
    )

proc renderViewInto(
    context: DrawContext, view: View, appearance: Appearance, parent = (-1).FigIdx
) =
  if view.visibleRect.isEmpty:
    return

  let absoluteFrame = view.rectToWindow(view.bounds)
  let rootIdx =
    context.addFig(parent, rectangleNode(absoluteFrame, view.backgroundColor))
  context.beginDraw(view, rootIdx)

  if not view.sendIfHandled(draw(), context):
    renderBuiltInView(context, view, rootIdx, appearance)

  for child in view.subviews:
    renderViewInto(context, child, appearance, rootIdx)

proc buildRenders*(root: View, appearance: Appearance): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  if root.isNil:
    return
  let context = initDrawContext()
  renderViewInto(context, root, appearance)
  result.layers[0.ZLevel] = context.renderList
  root.clearNeedsDisplayTree()

proc buildRenders*(root: View, theme: Theme): Renders =
  buildRenders(root, initAppearance(theme))

proc buildRenders*(root: View): Renders =
  buildRenders(root, initAppearance())
