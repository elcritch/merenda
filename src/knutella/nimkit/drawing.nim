import figdraw/fignodes

import ./types as nimkitTypes

const
  DefaultDrawLevel* = 50.ZLevel
  PopupDrawLevel* = 100.ZLevel

type DrawContext* = ref object
  xRenders: Renders
  xParent: FigIdx
  xLocalOriginInWindow: nimkitTypes.Point
  xBounds: nimkitTypes.Rect
  xVisibleRect: nimkitTypes.Rect

proc initDrawContext*(): DrawContext =
  result =
    DrawContext(xRenders: Renders(layers: initOrderedTable[ZLevel, RenderList]()))
  result.xRenders.layers[DefaultDrawLevel] = RenderList()

proc beginDraw*(
    context: DrawContext,
    parent: FigIdx,
    localOriginInWindow: nimkitTypes.Point,
    bounds: nimkitTypes.Rect,
    visibleRect: nimkitTypes.Rect,
) =
  context.xParent = parent
  context.xLocalOriginInWindow = localOriginInWindow
  context.xBounds = bounds
  context.xVisibleRect = visibleRect

proc renderList*(context: DrawContext): RenderList =
  if DefaultDrawLevel in context.xRenders.layers:
    return context.xRenders.layers[DefaultDrawLevel]
  RenderList()

proc renders*(context: DrawContext): Renders =
  context.xRenders

proc localRectToWindow*(
    context: DrawContext, rect: nimkitTypes.Rect
): nimkitTypes.Rect =
  nimkitTypes.initRect(
    context.xLocalOriginInWindow.x + rect.origin.x,
    context.xLocalOriginInWindow.y + rect.origin.y,
    rect.size.width,
    rect.size.height,
  )

proc bounds*(context: DrawContext): nimkitTypes.Rect =
  context.xBounds

proc visibleRect*(context: DrawContext): nimkitTypes.Rect =
  context.xVisibleRect

proc addFig*(
    context: DrawContext, layer: ZLevel, parent: FigIdx, node: Fig
): FigIdx {.discardable.} =
  if parent == (-1).FigIdx:
    context.xRenders.addRoot(layer, node)
  else:
    context.xRenders.addChild(layer, parent, node)

proc addFig*(context: DrawContext, parent: FigIdx, node: Fig): FigIdx {.discardable.} =
  context.addFig(DefaultDrawLevel, parent, node)

proc addFig*(context: DrawContext, node: Fig): FigIdx {.discardable.} =
  context.addFig(context.xParent, node)
