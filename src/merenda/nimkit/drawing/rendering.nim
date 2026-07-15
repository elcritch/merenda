import std/options
import std/tables

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw

import ./drawing
import ../foundation/selectors
import ../themes
import ../foundation/types
import ../view/views

const ZeroPoint = types.Point(x: 0.0'f32, y: 0.0'f32)

type RenderPlacement = object
  rootRect: types.Rect
  contentOrigin: types.Point
  contentParent: FigIdx

proc addPoints(a, b: types.Point): types.Point =
  initPoint(a.x + b.x, a.y + b.y)

proc offsetPoint(point, offset: types.Point): types.Point =
  initPoint(point.x + offset.x, point.y + offset.y)

proc boundsTranslation(bounds: types.Rect): types.Point =
  initPoint(-bounds.origin.x, -bounds.origin.y)

proc viewBackgroundStyleContext(view: View): StyleContext =
  controlStyle(
    srView, view.widgetStateSet(), id = view.styleId, classes = view.styleClasses
  )

proc usesThemedRootBackground(view: View, isRoot: bool): bool =
  isRoot and view.usesThemedRootBackground() and view.backgroundColor.a <= 0.0'f32

proc renderFrameRect(view: View, parentOrigin: types.Point): types.Rect =
  let
    frame = view.frame()
    bounds = view.bounds()
    origin = parentOrigin.offsetPoint(frame.origin)
  rect(origin, bounds.size)

proc beginDraw(
    context: DrawContext,
    view: View,
    parent: FigIdx,
    viewParent: FigIdx,
    contentOrigin: types.Point,
    appearance: Appearance,
) =
  context.beginDraw(
    parent, viewParent, contentOrigin, view.bounds, view.visibleRect, appearance
  )

proc viewBackgroundFill(view: View, appearance: Appearance, isRoot: bool): Fill =
  var color = view.backgroundColor
  if view.usesThemedRootBackground(isRoot):
    let context = view.viewBackgroundStyleContext()
    let fallbackColor = appearance.resolveColor(
      context, StyleBackgroundColor, color(0.94, 0.95, 0.97, 1.0)
    )
    return appearance.resolveFill(context, fill(fallbackColor), StyleBackgroundFill)
  fill(color(color.r, color.g, color.b, color.a * view.alphaValue))

proc addRootBackgroundPinstripes(
    context: DrawContext,
    view: View,
    level: ZLevel,
    parent: FigIdx,
    frame: types.Rect,
    appearance: Appearance,
) =
  let
    style = view.viewBackgroundStyleContext()
    rawPeriod = appearance.resolveLength(style, StyleBackgroundPinstripePeriod, 0.0'f32)
    stripeHeight =
      appearance.resolveLength(style, StyleBackgroundPinstripeHeight, 1.0'f32)

  if rawPeriod <= 0.0'f32 or stripeHeight <= 0.0'f32 or frame.size.width <= 0.0'f32 or
      frame.size.height <= 0.0'f32:
    return

  let
    highlightColor = appearance.resolveColor(
      style, StyleBackgroundPinstripeHighlightColor, color(0.0, 0.0, 0.0, 0.0)
    )
    stripeColor = appearance.resolveColor(
      style, StyleBackgroundPinstripeColor, color(0.0, 0.0, 0.0, 0.0)
    )

  if highlightColor.a <= 0.0'f32 and stripeColor.a <= 0.0'f32:
    return

  let
    period = max(rawPeriod, stripeHeight * 2.0'f32)
    bottom = frame.origin.y + frame.size.height

  var y = frame.origin.y
  while y < bottom:
    let highlightHeight = min(stripeHeight, bottom - y)
    if highlightColor.a > 0.0'f32 and highlightHeight > 0.0'f32:
      discard context.addRenderRectangle(
        level,
        parent,
        rect(frame.origin.x, y, frame.size.width, highlightHeight),
        fill(highlightColor),
      )

    let stripeY = y + stripeHeight
    let darkHeight = min(stripeHeight, bottom - stripeY)
    if stripeColor.a > 0.0'f32 and darkHeight > 0.0'f32:
      discard context.addRenderRectangle(
        level,
        parent,
        rect(frame.origin.x, stripeY, frame.size.width, darkHeight),
        fill(stripeColor),
      )

    y += period

proc renderViewInto(
    context: DrawContext,
    view: View,
    inheritedAppearance: Appearance,
    parent = (-1).FigIdx,
    parentLevel = DefaultDrawLevel,
    parentOrigin = ZeroPoint,
) =
  if view.visibleRect.isEmpty:
    return

  let
    appearance = view.resolvedAppearance(inheritedAppearance)
    level = view.trySendLocal(drawLevel()).get(DefaultDrawLevel)
    parentedInCurrentLayer = parent != (-1).FigIdx and level == parentLevel
    isRoot = parent == (-1).FigIdx
    absoluteFrame = view.renderFrameRect(parentOrigin)
    nodeParent =
      if parent == (-1).FigIdx or parentedInCurrentLayer:
        parent
      else:
        (-1).FigIdx
    rootIdx = context.addRenderRectangle(
      level,
      nodeParent,
      absoluteFrame,
      view.viewBackgroundFill(appearance, isRoot),
      shadows = view.shadow,
      clips = view.clipsToBounds,
    )

  if view.usesThemedRootBackground(isRoot):
    context.addRootBackgroundPinstripes(view, level, rootIdx, absoluteFrame, appearance)

  var placement = RenderPlacement(
    rootRect: absoluteFrame,
    contentOrigin: absoluteFrame.origin.addPoints(view.bounds().boundsTranslation()),
    contentParent: rootIdx,
  )

  context.beginDraw(
    view, placement.contentParent, nodeParent, placement.contentOrigin, appearance
  )
  discard view.sendLocalIfHandled(draw(), context)

  for child in view.subviews:
    renderViewInto(
      context, child, appearance, placement.contentParent, level,
      placement.contentOrigin,
    )

proc emptyRenders(): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[DefaultDrawLevel] = RenderList()

proc sameStyleValue(a, b: StyleValue): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of svMissing:
    true
  of svColor:
    a.color == b.color
  of svFill:
    a.fill == b.fill
  of svLength:
    a.length == b.length
  of svSize:
    a.size == b.size
  of svInsets:
    a.insets == b.insets
  of svShadows:
    a.shadows == b.shadows
  of svToken:
    a.token == b.token
  of svKeyword:
    a.keyword == b.keyword

proc sameStyleValues(a, b: Table[string, StyleValue]): bool =
  if a.len != b.len:
    return false
  for key, value in a.pairs:
    if key notin b or not value.sameStyleValue(b[key]):
      return false
  true

proc sameTokenStore(a, b: StyleTokenStore): bool =
  if a.isNil or b.isNil:
    return a.isNil and b.isNil
  a.values.sameStyleValues(b.values) and a.parent.sameTokenStore(b.parent)

proc sameStylePatch(a, b: StylePatch): bool =
  if a.isNil or b.isNil:
    return a.isNil and b.isNil
  a.values.sameStyleValues(b.values)

proc sameStyleRule(a, b: StyleRule): bool =
  a.selector == b.selector and a.patch.sameStylePatch(b.patch)

proc sameChromes(a, b: Table[string, Chrome]): bool =
  if a.len != b.len:
    return false
  for name, chrome in a.pairs:
    if name notin b or b[name] != chrome:
      return false
  true

proc sameTheme(a, b: Theme): bool =
  if not a.tokens.sameTokenStore(b.tokens) or not a.chromes.sameChromes(b.chromes) or
      a.rules.len != b.rules.len:
    return false
  for idx in 0 ..< a.rules.len:
    if not a.rules[idx].sameStyleRule(b.rules[idx]):
      return false
  true

proc sameAppearance(a, b: Appearance): bool =
  a.theme.sameTheme(b.theme)

proc cacheCanReuse(root: View, appearance: Appearance): bool =
  root.xHasCachedRenders and not root.needsDisplayInSubtree() and
    root.xCachedAppearance.sameAppearance(appearance)

proc buildRenders*(root: View, appearance: Appearance): Renders =
  discard root.prepareDisplaySubtree()
  if root.cacheCanReuse(appearance):
    return root.xCachedRenders

  let context = initDrawContext()
  renderViewInto(context, root, appearance)
  result = context.renders
  root.xCachedRenders = result
  root.xCachedRenderResources = context.resources
  root.xCachedAppearance = initAppearance(appearance.theme)
  root.xHasCachedRenders = true
  root.finishDisplaySubtree()

proc buildRenders*(root: View, theme: Theme): Renders =
  buildRenders(root, initAppearance(theme))

proc buildRenders*(root: View): Renders =
  buildRenders(root, root.effectiveAppearance())

proc renderResources*(root: View): RenderResourceManifest =
  if root.isNil:
    return nil
  root.xCachedRenderResources
