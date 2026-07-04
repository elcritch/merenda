import sigils/selectors

import ../drawing
import ../themes
import ../foundation/selectors as nimkitSelectors
import ../foundation/types
import ../view/views

type
  SelectionRingStyle* = object
    fillColor*: Color
    strokeColor*: Color
    lineWidth*: float32
    cornerRadius*: float32
    insets*: EdgeInsets

  SelectionRing* = object
    xView: View
    xToken: SwizzleToken
    xInstalled: bool

func initSelectionRingStyle*(
    strokeColor = color(0.0, 0.45, 1.0, 0.95),
    fillColor = color(0.0, 0.0, 0.0, 0.0),
    lineWidth = 3.0'f32,
    cornerRadius = 8.0'f32,
    insets = insets(2.0'f32),
): SelectionRingStyle =
  SelectionRingStyle(
    fillColor: fillColor,
    strokeColor: strokeColor,
    lineWidth: lineWidth,
    cornerRadius: cornerRadius,
    insets: insets,
  )

proc view*(ring: SelectionRing): View =
  ring.xView

proc installed*(ring: SelectionRing): bool =
  ring.xInstalled

proc drawSelectionRing*(
    context: DrawContext, bounds: Rect, style = initSelectionRingStyle()
) =
  if context.isNil:
    return
  let ringRect = bounds.inset(style.insets)
  if ringRect.isEmpty:
    return
  discard context.addRenderRectangle(
    context.renderRectFor(ringRect),
    style.fillColor,
    style.strokeColor,
    style.lineWidth,
    style.cornerRadius,
  )

proc installSelectionRing*(
    view: View, style = initSelectionRingStyle()
): SelectionRing =
  if view.isNil:
    return

  let ringStyle = style
  let ringWrapper: AroundMethod = proc(
      self: DynamicAgent, invocation: var Invocation, next: DynamicMethod
  ) =
    if not next.isNil:
      next(self, invocation)

    let
      context = invocation.argsAs(DrawContext)
      selectedView = View(self)
    context.drawSelectionRing(selectedView.bounds, ringStyle)

    if not invocation.handled:
      invocation.setResult(())

  result.xView = view
  result.xInstalled = true
  result.xToken = DynamicAgent(view).pushMethod(nimkitSelectors.draw(), ringWrapper)
  view.setNeedsDisplay(true)

proc uninstall*(ring: var SelectionRing): bool {.discardable.} =
  if not ring.xInstalled:
    return

  let view = ring.xView
  result = ring.xToken.popMethod()
  ring.xView = nil
  ring.xInstalled = false
  if not view.isNil:
    view.setNeedsDisplay(true)
