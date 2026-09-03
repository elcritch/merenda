import std/options

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw

import ./drawing
when not defined(useNativeDynlib):
  import ./renderscenes
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
    layer: ZLevel,
    parent: FigIdx,
    viewParent: FigIdx,
    contentOrigin: types.Point,
    appearance: Appearance,
) =
  context.beginDraw(
    parent, viewParent, contentOrigin, view.bounds, view.visibleRect, appearance, layer
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
    level = view.trySendLocal(drawLevel()).get(parentLevel)
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
    view, level, placement.contentParent, nodeParent, placement.contentOrigin,
    appearance,
  )
  discard view.sendLocalIfHandled(draw(), context)

  for child in view.subviews:
    renderViewInto(
      context, child, appearance, placement.contentParent, level,
      placement.contentOrigin,
    )

when not defined(useNativeDynlib):
  type DisplayRevisionSnapshot = object
    view: View
    revision: uint64

  proc appendSubtree(
      source: RenderList,
      sourceRoot: FigIdx,
      destination: var RenderList,
      parent = (-1).FigIdx,
  ) =
    var node = source.nodes[sourceRoot.int]
    node.childCount = 0
    let destinationRoot =
      if parent.int < 0:
        destination.addRoot(node)
      else:
        destination.addChild(parent, node)
    for child in source.nodes.childIndex(sourceRoot):
      source.appendSubtree(child, destination, destinationRoot)

  proc captureViewFrame(
      view: View,
      viewId: RenderViewId,
      parentViewId: RenderViewId,
      cacheKey: RenderViewCacheKey,
      appearance: Appearance,
  ): RenderViewFrame =
    let context = initDrawContext()
    let rootIdx = context.addRenderRectangle(
      cacheKey.level,
      (-1).FigIdx,
      cacheKey.frame,
      view.viewBackgroundFill(appearance, cacheKey.isRoot),
      shadows = view.shadow,
      clips = view.clipsToBounds,
    )

    if view.usesThemedRootBackground(cacheKey.isRoot):
      context.addRootBackgroundPinstripes(
        view, cacheKey.level, rootIdx, cacheKey.frame, appearance
      )

    let contentOrigin =
      cacheKey.frame.origin.addPoints(view.bounds().boundsTranslation())
    context.beginDraw(
      view, cacheKey.level, rootIdx, (-1).FigIdx, contentOrigin, appearance
    )
    discard view.sendLocalIfHandled(draw(), context)

    result = RenderViewFrame(
      viewId: viewId,
      parentViewId: parentViewId,
      cacheKey: cacheKey,
      captured: true,
      resources: context.resources,
    )
    let ownLayer = context.renders.layers[cacheKey.level]
    result.shell = ownLayer.nodes[rootIdx.int]
    result.shell.parent = (-1).FigIdx
    result.shell.childCount = 0
    for child in ownLayer.nodes.childIndex(rootIdx):
      ownLayer.appendSubtree(child, result.selfContents)
    for escapedRoot in ownLayer.rootIds:
      if escapedRoot != rootIdx:
        ownLayer.appendSubtree(escapedRoot, result.escapedContents)
    for level, list in context.renders.pairs():
      if level != cacheKey.level and list.nodes.len > 0:
        result.extraLayers.add RenderLayerContribution(level: level, contents: list)

  proc collectRenderFrames(
      scene: RenderScene,
      view: View,
      inheritedAppearance: Appearance,
      frames: var seq[RenderViewFrame],
      revisions: var seq[DisplayRevisionSnapshot],
      parentViewId = 0.RenderViewId,
      parentLevel = DefaultDrawLevel,
      parentOrigin = ZeroPoint,
  ) =
    if view.visibleRect.isEmpty:
      view.finishDisplaySubtree()
      return

    let
      appearance = view.resolvedAppearance(inheritedAppearance)
      level = view.trySendLocal(drawLevel()).get(parentLevel)
      viewId = view.renderViewId()
      absoluteFrame = view.renderFrameRect(parentOrigin)
      cacheKey = RenderViewCacheKey(
        displayRevision: view.xDisplayRevision,
        appearanceGeneration: uint64(appearance.theme.generation()),
        frame: absoluteFrame,
        bounds: view.bounds(),
        visibleRect: view.visibleRect(),
        level: level,
        isRoot: parentViewId.uint64 == 0,
      )

    if scene.needsViewCapture(viewId, cacheKey):
      frames.add view.captureViewFrame(viewId, parentViewId, cacheKey, appearance)
    else:
      frames.add RenderViewFrame(
        viewId: viewId, parentViewId: parentViewId, cacheKey: cacheKey
      )
    revisions.add DisplayRevisionSnapshot(
      view: view, revision: cacheKey.displayRevision
    )

    let contentOrigin =
      absoluteFrame.origin.addPoints(view.bounds().boundsTranslation())
    for child in view.subviews:
      scene.collectRenderFrames(
        child, appearance, frames, revisions, viewId, level, contentOrigin
      )

  proc updateRenderScene(root: View, appearance: Appearance): RenderScene =
    root.layoutSubtreeIfNeeded()
    if not root.xCachedRenderScene.isNil and root.xHasCachedRenders and
        not root.xNeedsDisplay and
        root.xCachedAppearance.sameAppearanceGeneration(appearance):
      return root.xCachedRenderScene
    if root.xCachedRenderScene.isNil:
      root.xCachedRenderScene = newRenderScene()

    var
      frames: seq[RenderViewFrame]
      revisions: seq[DisplayRevisionSnapshot]
    root.xCachedRenderScene.collectRenderFrames(root, appearance, frames, revisions)
    let changed = root.xCachedRenderScene.reconcile(frames, DefaultDrawLevel)
    for snapshot in revisions:
      snapshot.view.acknowledgeDisplayRevision(snapshot.revision)
    root.refreshDisplayStateSubtree()

    if changed or not root.xHasCachedRenders:
      root.xCachedRenders = root.xCachedRenderScene.materialize()
    root.xCachedRenderResources = root.xCachedRenderScene.renderResources()
    root.xCachedAppearance = appearance
    root.xHasCachedRenders = true
    root.xCachedRenderScene

proc cacheCanReuse(root: View, appearance: Appearance): bool =
  result =
    root.xHasCachedRenders and not root.needsDisplayInSubtree() and
    root.xCachedAppearance.sameAppearanceGeneration(appearance)

proc invalidateRenderCache*(root: View) =
  if root.isNil:
    return
  root.xCachedRenders = nil
  root.xCachedRenderResources = nil
  when not defined(useNativeDynlib):
    root.xCachedRenderScene = nil
  root.xHasCachedRenders = false

proc buildRenders*(root: View, appearance: Appearance): Renders =
  when not defined(useNativeDynlib):
    if not root.xCachedRenderScene.isNil:
      discard root.updateRenderScene(appearance)
      return root.xCachedRenders

  discard root.prepareDisplaySubtree()
  if root.cacheCanReuse(appearance):
    return root.xCachedRenders

  let context = initDrawContext()
  renderViewInto(context, root, appearance)
  result = context.renders
  root.xCachedRenders = result
  root.xCachedRenderResources = context.resources
  root.xCachedAppearance = appearance
  root.xHasCachedRenders = true
  root.finishDisplaySubtree()

proc buildRenders*(root: View, theme: Theme): Renders =
  buildRenders(root, initAppearance(theme))

proc buildRenders*(root: View): Renders =
  buildRenders(root, root.effectiveAppearance())

when not defined(useNativeDynlib):
  proc buildRenderScene*(root: View, appearance: Appearance): RenderScene =
    ## Builds or incrementally updates `root`'s scene-local per-view render cache.
    ## Clean view contributions retain their fragments and do not invoke `draw`.
    root.updateRenderScene(appearance)

  proc buildRenderScene*(root: View, theme: Theme): RenderScene =
    root.buildRenderScene(initAppearance(theme))

  proc buildRenderScene*(root: View): RenderScene =
    root.buildRenderScene(root.effectiveAppearance())

proc renderResources*(root: View): RenderResourceManifest =
  if root.isNil:
    return nil
  root.xCachedRenderResources
