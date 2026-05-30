import std/tables

import figdraw/fignodes

import ./drawing
import ./selectors
import ./theme
import ./types
import ./views

proc beginDraw(
    context: DrawContext,
    view: View,
    rootIdx: FigIdx,
    viewParent: FigIdx,
    appearance: Appearance,
) =
  context.beginDraw(
    rootIdx,
    viewParent,
    view.pointToWindow(initPoint(0.0, 0.0)),
    view.bounds,
    view.visibleRect,
    appearance,
  )

proc renderViewInto(
    context: DrawContext,
    view: View,
    inheritedAppearance: Appearance,
    parent = (-1).FigIdx,
) =
  if view.visibleRect.isEmpty:
    return

  let
    appearance = view.resolvedAppearance(inheritedAppearance)
    absoluteFrame = view.rectToWindow(view.bounds)
    rootIdx = context.addWindowRectangle(
      parent, absoluteFrame, view.backgroundColor, clips = view.clipsToBounds
    )
  context.beginDraw(view, rootIdx, parent, appearance)
  discard view.sendIfHandled(draw(), context)

  for child in view.subviews:
    renderViewInto(context, child, appearance, rootIdx)

proc buildRenders*(root: View, appearance: Appearance): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  if root.isNil:
    return
  discard root.prepareDisplaySubtree()
  let context = initDrawContext()
  renderViewInto(context, root, appearance)
  result = context.renders
  root.finishDisplaySubtree()

proc buildRenders*(root: View, theme: Theme): Renders =
  buildRenders(root, initAppearance(theme))

proc buildRenders*(root: View): Renders =
  if root.isNil:
    buildRenders(root, initAppearance())
  else:
    buildRenders(root, root.effectiveAppearance())
