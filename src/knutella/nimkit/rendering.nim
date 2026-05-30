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

proc textLayout(
    rect: types.Rect, text: string, color: types.Color, alignment = taLeft
): GlyphArrangement =
  let
    font = defaultFont(13.0'f32)
    style = fs(font, fill(color.rgba))
  typeset(
    rect.toFigRect,
    [(style, text)],
    hAlign = alignment.toFontHorizontal,
    vAlign = Middle,
    minContent = false,
    wrap = false,
  )

proc textNode(rect: types.Rect, layout: GlyphArrangement): Fig =
  Fig(kind: nkText, screenBox: rect.toFigRect, textLayout: layout)

proc selectTextNode(node: var Fig, selectedRange: TextRange, color: types.Color) =
  let count = node.textLayout.selectionRects.len
  if selectedRange.length == 0 or count == 0:
    return

  let
    first = min(selectedRange.location.int, count)
    last = min(first + selectedRange.length.int, count)
  if first >= last or first > high(int16).int:
    return

  node.flags.incl NfSelectText
  node.fill = fill(color.rgba)
  node.selectionRange = first.int16 .. min(last - 1, high(int16).int).int16

proc caretRect(
    textRect: types.Rect, layout: GlyphArrangement, insertionPoint: int
): types.Rect =
  let index = max(insertionPoint, 0)
  if layout.selectionRects.len > 0:
    let rect =
      if index <= 0:
        layout.selectionRects[0]
      else:
        layout.selectionRects[min(index - 1, layout.selectionRects.high)]
    let x =
      if index <= 0:
        rect.x
      else:
        min(rect.x + rect.w, textRect.size.width - 1.0'f32)
    return initRect(textRect.origin.x + x, textRect.origin.y + rect.y, 1.0, rect.h)

  let
    font = defaultFont(13.0'f32)
    lineHeight = max(13.0'f32, getLineHeightImpl(font))
  initRect(
    textRect.origin.x,
    textRect.origin.y + max((textRect.size.height - lineHeight) / 2.0'f32, 0.0),
    1.0,
    min(lineHeight, textRect.size.height),
  )

proc choiceRole(button: Button): StyleRole =
  if button.buttonType == btRadio: srRadioButton else: srCheckBox

proc selectedMarkRect(rect: types.Rect): types.Rect =
  let inset = max(rect.size.width * 0.28'f32, 3.0'f32)
  rect.inset(initEdgeInsets(inset))

proc mixedMarkRect(rect: types.Rect): types.Rect =
  let
    height = max(rect.size.height * 0.16'f32, 2.0'f32)
    inset = max(rect.size.width * 0.24'f32, 3.0'f32)
  initRect(
    rect.origin.x + inset,
    rect.origin.y + (rect.size.height - height) / 2.0'f32,
    rect.size.width - inset * 2.0'f32,
    height,
  )

proc addFocusRing(
    context: DrawContext, parent: FigIdx, rect: types.Rect, box: ControlBoxStyle
) =
  if box.focusRingWidth <= 0.0'f32:
    return
  let ringRect = rect.inset(initEdgeInsets(box.focusRingInset))
  if ringRect.isEmpty:
    return
  discard context.addFig(
    parent,
    rectangleNode(
      ringRect,
      initColor(0.0, 0.0, 0.0, 0.0),
      box.focusRingColor,
      box.focusRingWidth,
      box.cornerRadius,
    ),
  )

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
    if button.buttonType in {btCheckBox, btRadio}:
      let
        role = button.choiceRole()
        selected = button.state in {bsOn, bsMixed}
        style = appearance.resolveChoiceButtonStyle(
          initControlStyleContext(
            role,
            enabled = button.isEnabled,
            highlighted = button.isHighlighted,
            hovered = button.isHovered,
            active = button.isActive,
            focused = button.isFocused,
            focusVisible = button.isFocusVisible,
            selected = selected,
            id = button.styleId,
            classes = button.styleClasses,
          )
        )
        indicatorRect = style.choiceIndicatorRect(view.bounds)

      discard context.addFig(
        rootIdx,
        rectangleNode(
          view.rectToWindow(indicatorRect),
          style.indicator.fill,
          style.indicator.borderColor,
          style.indicator.borderWidth,
          style.indicator.cornerRadius,
        ),
      )
      if selected:
        let markRect =
          if button.state == bsMixed and button.buttonType == btCheckBox:
            indicatorRect.mixedMarkRect()
          else:
            indicatorRect.selectedMarkRect()
        discard context.addFig(
          rootIdx,
          rectangleNode(
            view.rectToWindow(markRect),
            style.markColor,
            style.markColor,
            0.0'f32,
            if button.buttonType == btRadio:
              markRect.size.width / 2.0'f32
            else:
              1.0'f32,
          ),
        )
      if button.isFocusVisible:
        context.addFocusRing(rootIdx, view.rectToWindow(indicatorRect), style.indicator)
      context.addText(style.choiceTextRect(view.bounds), button.title, style.text.color)
    else:
      let style = appearance.resolveButtonStyle(
        initControlStyleContext(
          srButton,
          enabled = button.isEnabled,
          highlighted = button.isHighlighted,
          hovered = button.isHovered,
          active = button.isActive,
          focused = button.isFocused,
          focusVisible = button.isFocusVisible,
          id = button.styleId,
          classes = button.styleClasses,
        )
      )
      discard context.addFig(
        rootIdx,
        rectangleNode(
          absoluteFrame, style.box.fill, style.box.borderColor, style.box.borderWidth,
          style.box.cornerRadius,
        ),
      )
      if button.isFocusVisible:
        context.addFocusRing(rootIdx, absoluteFrame, style.box)
      context.addText(style.buttonTextRect(view.bounds), button.title, style.text.color)
  elif view of TextField:
    let textField = TextField(view)
    let
      focused = textField.isEditing or textField.isFocused
      focusVisible = textField.isEditing or textField.isFocusVisible
    let style = appearance.resolveTextFieldStyle(
      initControlStyleContext(
        srTextField,
        enabled = textField.isEnabled,
        hovered = textField.isHovered,
        active = textField.isActive,
        focused = focused,
        focusVisible = focusVisible,
        id = textField.styleId,
        classes = textField.styleClasses,
      ),
      textField.textColor,
    )
    discard context.addFig(
      rootIdx,
      rectangleNode(
        absoluteFrame, style.box.fill, style.box.borderColor, style.box.borderWidth,
        style.box.cornerRadius,
      ),
    )
    if focusVisible:
      context.addFocusRing(rootIdx, absoluteFrame, style.box)
    let
      textRect = style.textFieldTextRect(view.bounds)
      layout = textLayout(
        textRect, textField.stringValue, style.text.color, textField.alignment
      )
      selectedRange = textField.selectedRange
      selectionColor = initColor(0.22, 0.46, 0.84, 0.32)
    if textField.isEditing and selectedRange.length > 0:
      var node = textNode(context.localRectToWindow(textRect), layout)
      node.selectTextNode(selectedRange, selectionColor)
      discard context.addFig(node)
    else:
      discard context.addFig(textNode(context.localRectToWindow(textRect), layout))

    if textField.isEditing and textField.isEditable and selectedRange.length == 0:
      context.addRectangle(
        textRect.caretRect(layout, textField.insertionPoint), style.text.color
      )

proc renderViewInto(
    context: DrawContext,
    view: View,
    inheritedAppearance: Appearance,
    parent = (-1).FigIdx,
) =
  if view.visibleRect.isEmpty:
    return

  let appearance = view.resolvedAppearance(inheritedAppearance)
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
  discard root.prepareDisplaySubtree()
  let context = initDrawContext()
  renderViewInto(context, root, appearance)
  result.layers[0.ZLevel] = context.renderList
  root.finishDisplaySubtree()

proc buildRenders*(root: View, theme: Theme): Renders =
  buildRenders(root, initAppearance(theme))

proc buildRenders*(root: View): Renders =
  if root.isNil:
    buildRenders(root, initAppearance())
  else:
    buildRenders(root, root.effectiveAppearance())
