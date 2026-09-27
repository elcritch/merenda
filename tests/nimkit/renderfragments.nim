import std/[hashes, tables, unicode, unittest]

import figdraw
import pkg/pixie except draw
import threading/smartptrs

import merenda/nimkit
import merenda/nimkit/drawing/renderscenes as retainedScenes

type
  SceneDrawView = ref object of View
  ScenePopupView = ref object of View
  CountedSceneView = ref object of View
    drawCount: int
    drawColor: Color
    drawLevelValue: ZLevel
    invalidatesDuringDraw: bool

  SurfaceSceneView = ref object of View
    drawColor: Color

  VisibleRectSceneView = ref object of View
    drawCount: int

  BoundsSceneView = ref object of View
    namedSlots: bool
    boundsDrawCount: int
    staticDrawCount: int

  MultiOutputSceneView = ref object of View
    escapedRootCount: int
    drawsPopup: bool
    drawsTooltip: bool

  TransformedSceneView = ref object of View
    translation: Point

  ResourceSceneView = ref object of View
    image: ImageResource
    style: TextStyle

  SlottedSceneView = ref object of View
    drawsPopup: bool
    underlayRevision: uint64
    contentRevision: uint64
    overlayRevision: uint64
    underlayDrawCount: int
    contentDrawCount: int
    overlayDrawCount: int

  RenderOperationContext = ref object of BackendContext
    operations: seq[string]
    entries: Table[Hash, figdraw.Rect]
    entryMetadata: Table[Hash, AtlasEntryMeta]

  CanonicalRenderNode = object
    level: ZLevel
    depth: int
    node: string

var sceneDrawCount: int

const
  TestUnderlaySlot = initRenderSlotId(0x54455354'u32, 1)
  TestContentSlot = initRenderSlotId(0x54455354'u32, 2)
  TestOverlaySlot = initRenderSlotId(0x54455354'u32, 3)

protocol SceneDrawing of ViewDrawingProtocol:
  method draw(view: SceneDrawView, context: DrawContext) =
    inc sceneDrawCount
    context.addRectangle(rect(2, 3, 12, 8), color(0.8, 0.1, 0.1))

protocol ScenePopupDrawing of ViewDrawingProtocol:
  method drawLevel(view: ScenePopupView): ZLevel =
    PopupDrawLevel

  method draw(view: ScenePopupView, context: DrawContext) =
    context.addRectangle(rect(1, 1, 8, 6), color(0.2, 0.5, 0.9))

protocol CountedSceneDrawing of ViewDrawingProtocol:
  method drawLevel(view: CountedSceneView): ZLevel =
    view.drawLevelValue

  method draw(view: CountedSceneView, context: DrawContext) =
    inc view.drawCount
    context.addRectangle(rect(1, 2, 9, 7), view.drawColor)
    if view.invalidatesDuringDraw:
      view.invalidatesDuringDraw = false
      view.needsDisplay = true

protocol SurfaceSceneDrawing of ViewDrawingProtocol:
  method draw(view: SurfaceSceneView, context: DrawContext) =
    discard context.addRenderRectangle(
      context.renderRectFor(rect(1, 2, 9, 7)), fill(view.drawColor)
    )

protocol VisibleRectSceneDrawing of ViewDrawingProtocol:
  method draw(view: VisibleRectSceneView, context: DrawContext) =
    inc view.drawCount
    discard context.visibleRect()
    context.addRectangle(rect(1, 2, 9, 7), color(0.2, 0.4, 0.8))

protocol BoundsSceneDrawing of ViewDrawingProtocol:
  method draw(view: BoundsSceneView, context: DrawContext) =
    if not view.namedSlots or context.beginRenderSlot(TestContentSlot, 1):
      inc view.boundsDrawCount
      context.addRectangle(context.bounds(), color(0.2, 0.4, 0.8))
    if view.namedSlots and context.beginRenderSlot(TestOverlaySlot, 1):
      inc view.staticDrawCount
      context.addRectangle(rect(1, 2, 9, 7), color(0.8, 0.2, 0.1))

protocol MultiOutputSceneDrawing of ViewDrawingProtocol:
  method draw(view: MultiOutputSceneView, context: DrawContext) =
    context.addRectangle(rect(1, 1, 10, 8), color(0.3, 0.4, 0.5))
    for index in 0 ..< view.escapedRootCount:
      discard context.addRenderRectangle(
        context.renderLayer,
        context.renderViewParent,
        context.renderRectFor(rect(index.float32, 12, 4, 3)),
        color(0.8, 0.2, 0.1),
      )
    if view.drawsTooltip:
      discard context.addRenderRectangle(
        TooltipDrawLevel,
        (-1).FigIdx,
        context.renderRectFor(rect(2, 18, 15, 5)),
        color(0.2, 0.7, 0.3),
      )
    if view.drawsPopup:
      discard context.addRenderRectangle(
        PopupDrawLevel,
        (-1).FigIdx,
        context.renderRectFor(rect(3, 24, 18, 7)),
        color(0.2, 0.3, 0.8),
      )

protocol TransformedSceneDrawing of ViewDrawingProtocol:
  method draw(view: TransformedSceneView, context: DrawContext) =
    let transform = context.addFig(
      context.renderLayer,
      context.renderParent,
      Fig(
        kind: nkTransform,
        screenBox: figdraw.rect(1, 2, 20, 18),
        transform: TransformStyle(
          translation: vec2(view.translation.x, view.translation.y),
          matrix: scale(vec3(1.25'f32, 0.75'f32, 1.0'f32)),
          useMatrix: true,
        ),
      ),
    )
    discard context.addRenderRectangle(
      context.renderLayer,
      transform,
      context.renderRectFor(rect(3, 4, 12, 9)),
      color(0.6, 0.2, 0.8),
    )

protocol ResourceSceneDrawing of ViewDrawingProtocol:
  method draw(view: ResourceSceneView, context: DrawContext) =
    discard context.addImage(rect(2, 3, 10, 8), view.image)
    discard context.addText(rect(2, 14, 50, 18), "cached", view.style)

protocol SlottedSceneDrawing of ViewDrawingProtocol:
  method drawUnderlay(view: SlottedSceneView, context: DrawContext) =
    if context.beginRenderSlot(TestUnderlaySlot, view.underlayRevision):
      inc view.underlayDrawCount
      context.addRectangle(rect(1, 1, 20, 10), color(0.8, 0.1, 0.1))

  method draw(view: SlottedSceneView, context: DrawContext) =
    if context.beginRenderSlot(TestContentSlot, view.contentRevision):
      inc view.contentDrawCount
      context.addRectangle(rect(1, 12, 20, 10), color(0.1, 0.8, 0.1))

  method drawOverlay(view: SlottedSceneView, context: DrawContext) =
    if context.beginRenderSlot(TestOverlaySlot, view.overlayRevision, rspAfterSubviews):
      inc view.overlayDrawCount
      context.addRectangle(rect(1, 23, 20, 10), color(0.1, 0.1, 0.8))
      if view.drawsPopup:
        discard context.addRenderRectangle(
          PopupDrawLevel, (-1).FigIdx, rect(2, 18, 15, 5), color(0.2, 0.7, 0.3)
        )

method drawRoundedRectSdf*(
    context: RenderOperationContext,
    rect: figdraw.Rect,
    colors: array[4, ColorRGBA],
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    factor: float32,
    spread: float32,
    shapeSize: Vec2,
) =
  context.operations.add(
    "rectangle:" & repr((rect, colors, radii, mode, factor, spread, shapeSize))
  )

method beginMask*(
    context: RenderOperationContext,
    clipRect: figdraw.Rect,
    radii: CornerRadii2D[float32],
) =
  context.operations.add("beginMask:" & repr((clipRect, radii)))

method endMask*(context: RenderOperationContext) =
  context.operations.add("endMask")

method popMask*(context: RenderOperationContext) =
  context.operations.add("popMask")

method saveTransform*(context: RenderOperationContext) =
  context.operations.add("saveTransform")

method restoreTransform*(context: RenderOperationContext) =
  context.operations.add("restoreTransform")

method translate*(context: RenderOperationContext, value: Vec2) =
  context.operations.add("translate:" & repr(value))

method applyTransform*(context: RenderOperationContext, value: Mat4) =
  context.operations.add("applyTransform:" & repr(value))

method supportsAtlasUsage*(context: RenderOperationContext): bool =
  discard context

method entriesPtr*(context: RenderOperationContext): ptr Table[Hash, figdraw.Rect] =
  context.entries.addr

method atlasEntryMetaPtr*(
    context: RenderOperationContext
): var Table[Hash, AtlasEntryMeta] =
  context.entryMetadata

method atlasSize*(context: RenderOperationContext): int =
  discard context
  64

method atlasPackedArea*(context: RenderOperationContext): int =
  discard context

method putImage*(context: RenderOperationContext, key: Hash, image: Image) =
  context.entries[key] = figdraw.rect(
    0,
    0,
    image.width.float32 / context.atlasSize().float32,
    image.height.float32 / context.atlasSize().float32,
  )

method putImage*(context: RenderOperationContext, image: ImgObj) =
  case image.kind
  of PixieImg:
    context.putImage(image.id.Hash, image.pimg)
  of FlippyImg:
    if image.flippy.mipmaps.len > 0:
      let pixels = image.flippy.mipmaps[0]
      context.entries[image.id.Hash] = figdraw.rect(
        0,
        0,
        pixels.width.float32 / context.atlasSize().float32,
        pixels.height.float32 / context.atlasSize().float32,
      )

proc newSceneDrawView(frame: Rect): SceneDrawView =
  result = SceneDrawView()
  result.initViewFields(frame)
  discard result.withProtocol(SceneDrawing)

proc newScenePopupView(frame: Rect): ScenePopupView =
  result = ScenePopupView()
  result.initViewFields(frame)
  discard result.withProtocol(ScenePopupDrawing)

proc newCountedSceneView(frame: Rect, drawColor: Color): CountedSceneView =
  result = CountedSceneView(drawColor: drawColor)
  result.initViewFields(frame)
  discard result.withProtocol(CountedSceneDrawing)

proc newSurfaceSceneView(frame: Rect, drawColor: Color): SurfaceSceneView =
  result = SurfaceSceneView(drawColor: drawColor)
  result.initViewFields(frame)
  discard result.withProtocol(SurfaceSceneDrawing)

proc newVisibleRectSceneView(frame: Rect): VisibleRectSceneView =
  result = VisibleRectSceneView()
  result.initViewFields(frame)
  discard result.withProtocol(VisibleRectSceneDrawing)

proc newBoundsSceneView(frame: Rect, namedSlots: bool): BoundsSceneView =
  result = BoundsSceneView(namedSlots: namedSlots)
  result.initViewFields(frame)
  discard result.withProtocol(BoundsSceneDrawing)

proc newMultiOutputSceneView(frame: Rect): MultiOutputSceneView =
  result = MultiOutputSceneView()
  result.initViewFields(frame)
  discard result.withProtocol(MultiOutputSceneDrawing)

proc newTransformedSceneView(frame: Rect, translation: Point): TransformedSceneView =
  result = TransformedSceneView(translation: translation)
  result.initViewFields(frame)
  discard result.withProtocol(TransformedSceneDrawing)

proc newResourceSceneView(
    frame: Rect, image: ImageResource, style: TextStyle
): ResourceSceneView =
  result = ResourceSceneView(image: image, style: style)
  result.initViewFields(frame)
  discard result.withProtocol(ResourceSceneDrawing)

proc newSlottedSceneView(frame: Rect): SlottedSceneView =
  result = SlottedSceneView(underlayRevision: 1, contentRevision: 1, overlayRevision: 1)
  result.initViewFields(frame)
  discard result.withProtocol(SlottedSceneDrawing)

proc renderedOperations(renders: var Renders): seq[string] =
  let context = RenderOperationContext(
    entries: initTable[Hash, figdraw.Rect](),
    entryMetadata: initTable[Hash, AtlasEntryMeta](),
  )
  context.renderRoot(renders)
  context.operations

proc renderedOperations(scene: RenderScene): seq[string] =
  let context = RenderOperationContext(
    entries: initTable[Hash, figdraw.Rect](),
    entryMetadata: initTable[Hash, AtlasEntryMeta](),
  )
  retainedScenes.renderRoot(scene, context)
  context.operations

proc renderLevels(renders: Renders): seq[ZLevel] =
  for level, _ in renders.pairs():
    result.add level

proc appendCanonicalNodes(
    renders: Renders,
    level: ZLevel,
    cursor: RenderCursor,
    depth: int,
    nodes: var seq[CanonicalRenderNode],
) =
  var node = renders[cursor]
  node.parent = (-1).FigIdx
  node.childCount = 0
  nodes.add CanonicalRenderNode(level: level, depth: depth, node: repr(node))
  for child in renders.children(cursor):
    renders.appendCanonicalNodes(level, child, depth + 1, nodes)

proc canonicalNodes(renders: Renders): seq[CanonicalRenderNode] =
  for level, _ in renders.pairs():
    for root in renders.roots(level):
      renders.appendCanonicalNodes(level, root, 0, result)

proc renderedText(scene: RenderScene): string =
  for _, layer in scene.materialize().pairs():
    for node in layer.nodes:
      if node.kind == nkText:
        for glyphIndex in 0 ..< node.textLayout.glyphCount():
          result.add node.textLayout.displayRune(glyphIndex)

proc testImage(width, height: int): Image =
  result = newImage(width, height)
  result.fill(rgba(64, 128, 192, 255))

suite "NimKit render fragments":
  test "cumulative scene updates apply after coalescing and reject stale baselines":
    let
      root = newView(frame = rect(0, 0, 180, 120))
      first = newCountedSceneView(rect(5, 6, 50, 30), color(0.2, 0.3, 0.4))
      second = newCountedSceneView(rect(62, 6, 50, 30), color(0.5, 0.6, 0.7))
    root.addSubview(first)
    root.addSubview(second)

    let scene = root.buildRenderScene()
    let
      sceneIdentity = retainedScenes.sceneIdentity(scene)
      acknowledgedGeneration = scene.frameGeneration()
      replica = retainedScenes.newRenderSceneReplica()
    var full = retainedScenes.newRenderSceneUpdate(scene, 0, 0)
    let fullBytes = retainedScenes.estimatedTransferBytes(full)
    check fullBytes > 0
    check retainedScenes.fullSnapshot(full)
    check retainedScenes.baseGeneration(full) == 0
    check retainedScenes.capturedViewCount(full) == 3
    check retainedScenes.canApply(full, 0, 0)
    retainedScenes.apply(replica, full)
    check replica.materialize().canonicalNodes() == scene.materialize().canonicalNodes()

    first.drawColor = color(0.8, 0.1, 0.2)
    first.needsDisplay = true
    discard root.buildRenderScene()
    let skippedGeneration = scene.frameGeneration()

    second.drawColor = color(0.1, 0.8, 0.3)
    second.needsDisplay = true
    discard root.buildRenderScene()
    let latestGeneration = scene.frameGeneration()
    var cumulative =
      retainedScenes.newRenderSceneUpdate(scene, sceneIdentity, acknowledgedGeneration)

    check retainedScenes.estimatedTransferBytes(cumulative) < fullBytes
    check not retainedScenes.fullSnapshot(cumulative)
    check retainedScenes.baseGeneration(cumulative) == acknowledgedGeneration
    check retainedScenes.generation(cumulative) == latestGeneration
    check skippedGeneration > acknowledgedGeneration
    check latestGeneration > skippedGeneration
    check retainedScenes.capturedViewCount(cumulative) == 2
    check retainedScenes.canApply(cumulative, sceneIdentity, acknowledgedGeneration)
    retainedScenes.apply(replica, cumulative)
    check replica.frameGeneration() == latestGeneration
    check replica.materialize().canonicalNodes() == scene.materialize().canonicalNodes()
    check not retainedScenes.canApply(full, sceneIdentity, latestGeneration)
    expect ValueError:
      retainedScenes.apply(replica, full)

    let replacement = newView(frame = rect(0, 0, 180, 120)).buildRenderScene()
    var barrier =
      retainedScenes.newRenderSceneUpdate(replacement, sceneIdentity, latestGeneration)
    check retainedScenes.fullSnapshot(barrier)
    check retainedScenes.canApply(barrier, sceneIdentity, latestGeneration)

  test "layer changes force a full renderer-scene ordering barrier":
    let
      root = newView(frame = rect(0, 0, 180, 120))
      child = newCountedSceneView(rect(5, 6, 50, 30), color(0.2, 0.3, 0.4))
    root.addSubview(child)

    let scene = root.buildRenderScene()
    let
      sceneIdentity = retainedScenes.sceneIdentity(scene)
      acknowledgedGeneration = scene.frameGeneration()

    child.drawLevelValue = PopupDrawLevel
    child.needsDisplay = true
    discard root.buildRenderScene()
    var barrier =
      retainedScenes.newRenderSceneUpdate(scene, sceneIdentity, acknowledgedGeneration)

    check retainedScenes.fullSnapshot(barrier)
    check retainedScenes.baseGeneration(barrier) == 0
    check retainedScenes.capturedViewCount(barrier) == 2

  test "scene materializes monolithic order and sweeps removed views":
    let
      root = newView(frame = rect(0, 0, 160, 120))
      container = newView(frame = rect(8, 10, 90, 70))
      custom = newSceneDrawView(rect(3, 4, 40, 24))
      popup = newScenePopupView(rect(100, 12, 40, 30))
    root.clipsToBounds = true
    container.clipsToBounds = true
    container.addSubview(custom)
    root.addSubview(container)
    root.addSubview(popup)

    sceneDrawCount = 0
    let
      monolithic = root.buildRenders()
      scene = root.buildRenderScene()
      firstGeneration = scene.frameGeneration()
      firstFragmentIds = scene.rootFragmentIds()
      materialized = scene.materialize()

    check sceneDrawCount == 1
    check materialized.renderLevels() == monolithic.renderLevels()
    check materialized.canonicalNodes() == monolithic.canonicalNodes()
    check scene.viewEntryCount() == 4
    check scene.containsView(root.renderViewId())
    check scene.containsView(custom.renderViewId())

    let cachedScene = root.buildRenderScene()
    check cachedScene == scene
    check cachedScene.frameGeneration() == firstGeneration
    check sceneDrawCount == 1

    custom.needsDisplay = true
    let updatedScene = root.buildRenderScene()
    check updatedScene == scene
    check updatedScene.frameGeneration() == firstGeneration + 1
    check updatedScene.rootFragmentIds() == firstFragmentIds
    check sceneDrawCount == 2
    check updatedScene.materialize().canonicalNodes() ==
      root.buildRenders().canonicalNodes()

    let removedId = custom.renderViewId()
    custom.removeFromSuperview()
    discard root.buildRenderScene()
    check not scene.containsView(removedId)
    check scene.viewEntryCount() == 3

  test "first implicit slot node stays before subviews":
    let
      surfaceColor = color(0.74, 0.12, 0.18)
      childColor = color(0.16, 0.68, 0.28)
      root = newSurfaceSceneView(rect(0, 0, 120, 80), surfaceColor)
      child = newSurfaceSceneView(rect(8, 9, 40, 24), childColor)
    root.addSubview(child)

    let nodes = root.buildRenderScene().materialize()[DefaultDrawLevel].nodes
    var
      surfaceIndex = -1
      childIndex = -1
    for index, node in nodes:
      if node.kind == nkRectangle and node.fill == fill(surfaceColor):
        surfaceIndex = index
      elif node.kind == nkRectangle and node.fill == fill(childColor):
        childIndex = index

    check surfaceIndex >= 0
    check childIndex >= 0
    check surfaceIndex < childIndex

  test "leaf invalidation preserves ancestor and sibling contributions":
    let
      root = newCountedSceneView(rect(0, 0, 180, 120), color(0.1, 0.1, 0.1))
      parent = newCountedSceneView(rect(8, 9, 100, 80), color(0.2, 0.3, 0.4))
      leaf = newCountedSceneView(rect(4, 5, 30, 20), color(0.7, 0.2, 0.1))
      sibling = newCountedSceneView(rect(42, 5, 30, 20), color(0.1, 0.6, 0.2))
    parent.addSubview(leaf)
    parent.addSubview(sibling)
    root.addSubview(parent)

    let scene = root.buildRenderScene()
    let
      rootIds = scene.viewFragmentIds(root.renderViewId())
      parentIds = scene.viewFragmentIds(parent.renderViewId())
      leafIds = scene.viewFragmentIds(leaf.renderViewId())
      siblingIds = scene.viewFragmentIds(sibling.renderViewId())
      firstOutput = scene.materialize().canonicalNodes()

    check root.drawCount == 1
    check parent.drawCount == 1
    check leaf.drawCount == 1
    check sibling.drawCount == 1

    leaf.drawColor = color(0.9, 0.5, 0.2)
    leaf.needsDisplay = true
    discard root.buildRenderScene()

    check root.drawCount == 1
    check parent.drawCount == 1
    check leaf.drawCount == 2
    check sibling.drawCount == 1
    check scene.viewCaptureGeneration(root.renderViewId()) == 1
    check scene.viewCaptureGeneration(parent.renderViewId()) == 1
    check scene.viewCaptureGeneration(leaf.renderViewId()) == 2
    check scene.viewCaptureGeneration(sibling.renderViewId()) == 1
    check scene.viewFragmentIds(root.renderViewId()) == rootIds
    check scene.viewFragmentIds(parent.renderViewId()) == parentIds
    check scene.viewFragmentIds(leaf.renderViewId()) == leafIds
    check scene.viewFragmentIds(sibling.renderViewId()) == siblingIds
    check scene.materialize().canonicalNodes() != firstOutput

  test "child reordering keeps view fragments and cached drawing":
    let
      root = newView(frame = rect(0, 0, 140, 90))
      first = newCountedSceneView(rect(4, 5, 30, 20), color(0.8, 0.1, 0.1))
      second = newCountedSceneView(rect(40, 5, 30, 20), color(0.1, 0.2, 0.8))
    root.addSubview(first)
    root.addSubview(second)

    let scene = root.buildRenderScene()
    let
      firstIds = scene.viewFragmentIds(first.renderViewId())
      secondIds = scene.viewFragmentIds(second.renderViewId())
    root.insertSubview(second, 0)
    discard root.buildRenderScene()

    check first.drawCount == 1
    check second.drawCount == 2
    check scene.viewFragmentIds(first.renderViewId()) == firstIds
    check scene.viewFragmentIds(second.renderViewId()) == secondIds
    check scene.materialize().canonicalNodes() == root.buildRenders().canonicalNodes()

  test "ancestor geometry changes recapture affected descendant contexts":
    let
      root = newCountedSceneView(rect(0, 0, 180, 120), color(0.1, 0.1, 0.1))
      parent = newCountedSceneView(rect(8, 9, 100, 80), color(0.2, 0.3, 0.4))
      child = newCountedSceneView(rect(4, 5, 30, 20), color(0.7, 0.2, 0.1))
    parent.addSubview(child)
    root.addSubview(parent)
    let scene = root.buildRenderScene()

    parent.frame = rect(20, 18, 100, 80)
    discard root.buildRenderScene()

    check root.drawCount == 1
    check parent.drawCount == 2
    check child.drawCount == 2
    check scene.viewCaptureGeneration(root.renderViewId()) == 1
    check scene.viewCaptureGeneration(parent.renderViewId()) == 2
    check scene.viewCaptureGeneration(child.renderViewId()) == 2

  test "bounds-origin scrolling preserves drawing that does not read the visible rect":
    let
      root = newView(frame = rect(0, 0, 180, 120))
      viewport = newCountedSceneView(rect(0, 0, 100, 80), color(0.2, 0.3, 0.4))
      document = newCountedSceneView(rect(0, 0, 100, 240), color(0.7, 0.2, 0.1))
    viewport.clipsToBounds = true
    viewport.addSubview(document)
    root.addSubview(viewport)
    let scene = root.buildRenderScene()
    let
      sceneIdentity = retainedScenes.sceneIdentity(scene)
      initialGeneration = scene.frameGeneration()
      documentFragments = scene.viewFragmentIds(document.renderViewId())
      replica = retainedScenes.newRenderSceneReplica()
    var initial = retainedScenes.newRenderSceneUpdate(scene, 0, 0)
    retainedScenes.apply(replica, initial)

    viewport.bounds = rect(0, 24, 100, 80)
    discard root.buildRenderScene()
    var update =
      retainedScenes.newRenderSceneUpdate(scene, sceneIdentity, initialGeneration)

    check viewport.drawCount == 1
    check document.drawCount == 1
    check scene.viewCaptureGeneration(viewport.renderViewId()) == 1
    check scene.viewCaptureGeneration(document.renderViewId()) == 1
    check scene.viewFragmentIds(document.renderViewId()) == documentFragments
    check retainedScenes.capturedViewCount(update) == 0
    retainedScenes.apply(replica, update)
    check replica.materialize().canonicalNodes() == scene.materialize().canonicalNodes()

  test "scroll transfers only the changed viewport among one thousand children":
    for childCount in [1, 10, 100, 1000]:
      let
        root = newView(rect(0, 0, 800, 600))
        viewport = newView(rect(0, 0, 800, 600))
        document = newView(rect(0, 0, 800, 10000))
      viewport.clipsToBounds = true
      root.addSubview(viewport)
      viewport.addSubview(document)
      for index in 0 ..< childCount:
        let child = newCountedSceneView(
          rect((10 + index mod 100 * 5).float32, (10 + index div 100 * 5).float32, 4, 5),
          color(0.2, 0.3, 0.4),
        )
        child.drawLevelValue = DefaultDrawLevel
        document.addSubview(child)
      let
        scene = root.buildRenderScene()
        identity = retainedScenes.sceneIdentity(scene)
        generation = scene.frameGeneration()
        replica = retainedScenes.newRenderSceneReplica()
        resources = scene.renderResources()
      var initial = retainedScenes.newRenderSceneUpdate(scene, 0, 0)
      retainedScenes.apply(replica, initial)
      let unchanged = retainedScenes.newRenderSceneUpdate(scene, identity, generation)
      check unchanged.estimatedTransferBytes() == 0

      viewport.setBoundsOriginFromLayout(initPoint(0, 0.25))
      discard root.buildRenderScene()
      var update = retainedScenes.newRenderSceneUpdate(scene, identity, generation)
      check update.viewCount() == childCount + 3
      check update.capturedViewCount() == 0
      check update.estimatedTransferBytes() == sizeof(RenderViewFrame)
      check scene.renderResources() == resources
      check scene.retiredResourceCount() == 0
      retainedScenes.apply(replica, update)
      check replica.materialize().canonicalNodes() ==
        scene.materialize().canonicalNodes()

  test "cumulative scroll updates preserve changed placement order":
    let
      root = newView(rect(0, 0, 300, 200))
      viewport = newView(rect(0, 0, 300, 200))
      document = newView(rect(0, 0, 300, 800))
      first = newSceneDrawView(rect(5, 10, 30, 20))
      second = newSceneDrawView(rect(40, 10, 30, 20))
      added = newSceneDrawView(rect(75, 10, 30, 20))
    viewport.clipsToBounds = true
    root.addSubview(viewport)
    viewport.addSubview(document)
    document.addSubview(first)
    document.addSubview(second)
    let
      scene = root.buildRenderScene()
      identity = retainedScenes.sceneIdentity(scene)
      baseline = scene.frameGeneration()
      replica = retainedScenes.newRenderSceneReplica()
      intermediateReplica = retainedScenes.newRenderSceneReplica()
    var initial = retainedScenes.newRenderSceneUpdate(scene, 0, 0)
    var otherInitial = retainedScenes.newRenderSceneUpdate(scene, 0, 0)
    retainedScenes.apply(replica, initial)
    retainedScenes.apply(intermediateReplica, otherInitial)

    document.addSubview(added)
    document.insertSubview(second, 0)
    discard root.buildRenderScene()
    var intermediate = retainedScenes.newRenderSceneUpdate(scene, identity, baseline)
    retainedScenes.apply(intermediateReplica, intermediate)
    first.removeFromSuperview()
    discard root.buildRenderScene()
    viewport.setBoundsOriginFromLayout(initPoint(0, 1.25))
    discard root.buildRenderScene()
    var cumulative = retainedScenes.newRenderSceneUpdate(scene, identity, baseline)
    var cumulativeAfterIntermediate =
      retainedScenes.newRenderSceneUpdate(scene, identity, baseline)
    check not cumulative.fullSnapshot()
    check cumulative.viewCount() == 5
    retainedScenes.apply(replica, cumulative)
    retainedScenes.apply(intermediateReplica, cumulativeAfterIntermediate)
    check replica.materialize().canonicalNodes() == scene.materialize().canonicalNodes()
    check intermediateReplica.materialize().canonicalNodes() ==
      scene.materialize().canonicalNodes()

    let acknowledged = scene.frameGeneration()
    viewport.setBoundsOriginFromLayout(initPoint(0, 2.5))
    discard root.buildRenderScene()
    var scroll = retainedScenes.newRenderSceneUpdate(scene, identity, acknowledged)
    check scroll.estimatedTransferBytes() == sizeof(RenderViewFrame)
    retainedScenes.apply(replica, scroll)
    check replica.materialize().canonicalNodes() == scene.materialize().canonicalNodes()

  test "scroll updates explicit layer transforms on renderer replicas":
    let
      root = newView(rect(0, 0, 180, 120))
      viewport = newView(rect(0, 0, 100, 80))
      document = newMultiOutputSceneView(rect(0, 0, 100, 240))
    document.drawsPopup = true
    viewport.clipsToBounds = true
    root.addSubview(viewport)
    viewport.addSubview(document)
    let
      scene = root.buildRenderScene()
      identity = retainedScenes.sceneIdentity(scene)
      replica = retainedScenes.newRenderSceneReplica()
    var initial = retainedScenes.newRenderSceneUpdate(scene, 0, 0)
    retainedScenes.apply(replica, initial)
    for offset in [0.25'f32, 8.5'f32, 0.0'f32]:
      let baseline = scene.frameGeneration()
      viewport.setBoundsOriginFromLayout(initPoint(0, offset))
      discard root.buildRenderScene()
      var update = retainedScenes.newRenderSceneUpdate(scene, identity, baseline)
      check update.capturedViewCount() == 0
      check update.estimatedTransferBytes() == 2 * sizeof(RenderViewFrame)
      retainedScenes.apply(replica, update)
      check replica.materialize().canonicalNodes() ==
        scene.materialize().canonicalNodes()

  test "partial captures keep retained explicit layers aligned while scrolling":
    let
      root = newView(rect(0, 0, 180, 120))
      viewport = newView(rect(0, 0, 100, 80))
      document = newSlottedSceneView(rect(0, 0, 100, 240))
    document.drawsPopup = true
    viewport.clipsToBounds = true
    root.addSubview(viewport)
    viewport.addSubview(document)
    let
      scene = root.buildRenderScene()
      identity = retainedScenes.sceneIdentity(scene)
      baseline = scene.frameGeneration()
      replica = retainedScenes.newRenderSceneReplica()
    var initial = retainedScenes.newRenderSceneUpdate(scene, 0, 0)
    retainedScenes.apply(replica, initial)
    viewport.setBoundsOriginFromLayout(initPoint(0, 8.5))
    document.contentRevision = 2
    document.setNeedsDisplayInRenderSlot(TestContentSlot)
    discard root.buildRenderScene()
    var update = retainedScenes.newRenderSceneUpdate(scene, identity, baseline)
    check document.contentDrawCount == 2
    check document.overlayDrawCount == 1
    check update.capturedRenderSlotCount() == 1
    retainedScenes.apply(replica, update)
    let retained = scene.materialize().canonicalNodes()
    check replica.materialize().canonicalNodes() == retained
    root.invalidateRenderCache()
    check root.buildRenderScene().materialize().canonicalNodes() == retained

  test "bounds changes recapture only drawing slots that read the bounds":
    for namedSlots in [false, true]:
      let root = newBoundsSceneView(rect(0, 0, 100, 80), namedSlots)
      let
        scene = root.buildRenderScene()
        identity = retainedScenes.sceneIdentity(scene)
        baseline = scene.frameGeneration()
        staticGeneration =
          scene.viewRenderSlotChangeGeneration(root.renderViewId(), TestOverlaySlot)
        replica = retainedScenes.newRenderSceneReplica()
      var initial = retainedScenes.newRenderSceneUpdate(scene, 0, 0)
      retainedScenes.apply(replica, initial)
      root.setBoundsOriginFromLayout(initPoint(3.25, 8.5))
      discard root.buildRenderScene()
      var update = retainedScenes.newRenderSceneUpdate(scene, identity, baseline)
      check root.boundsDrawCount == 2
      check update.capturedRenderSlotCount() == 1
      if namedSlots:
        check root.staticDrawCount == 1
        check scene.viewRenderSlotChangeGeneration(root.renderViewId(), TestOverlaySlot) ==
          staticGeneration
      retainedScenes.apply(replica, update)
      let retained = scene.materialize().canonicalNodes()
      check replica.materialize().canonicalNodes() == retained
      root.invalidateRenderCache()
      check root.buildRenderScene().materialize().canonicalNodes() == retained

  test "named view slots update independently around child content":
    let
      root = newView(frame = rect(0, 0, 180, 120))
      slotted = newSlottedSceneView(rect(4, 5, 80, 70))
      child = newSceneDrawView(rect(25, 20, 30, 20))
    slotted.addSubview(child)
    root.addSubview(slotted)

    let scene = root.buildRenderScene()
    let
      sceneIdentity = retainedScenes.sceneIdentity(scene)
      initialGeneration = scene.frameGeneration()
      underlayId =
        scene.viewRenderSlotFragmentId(slotted.renderViewId(), TestUnderlaySlot)
      contentId =
        scene.viewRenderSlotFragmentId(slotted.renderViewId(), TestContentSlot)
      overlayId =
        scene.viewRenderSlotFragmentId(slotted.renderViewId(), TestOverlaySlot)
      underlayGeneration =
        scene.viewRenderSlotChangeGeneration(slotted.renderViewId(), TestUnderlaySlot)
      overlayGeneration =
        scene.viewRenderSlotChangeGeneration(slotted.renderViewId(), TestOverlaySlot)
      replica = retainedScenes.newRenderSceneReplica()
    var initial = retainedScenes.newRenderSceneUpdate(scene, 0, 0)
    retainedScenes.apply(replica, initial)

    check slotted.underlayDrawCount == 1
    check slotted.contentDrawCount == 1
    check slotted.overlayDrawCount == 1

    slotted.contentRevision = 2
    slotted.setNeedsDisplayInRenderSlot(TestContentSlot)
    discard root.buildRenderScene()
    var update =
      retainedScenes.newRenderSceneUpdate(scene, sceneIdentity, initialGeneration)

    check slotted.underlayDrawCount == 1
    check slotted.contentDrawCount == 2
    check slotted.overlayDrawCount == 1
    check scene.viewRenderSlotFragmentId(slotted.renderViewId(), TestUnderlaySlot) ==
      underlayId
    check scene.viewRenderSlotFragmentId(slotted.renderViewId(), TestContentSlot) ==
      contentId
    check scene.viewRenderSlotFragmentId(slotted.renderViewId(), TestOverlaySlot) ==
      overlayId
    check scene.viewRenderSlotChangeGeneration(slotted.renderViewId(), TestUnderlaySlot) ==
      underlayGeneration
    check scene.viewRenderSlotChangeGeneration(slotted.renderViewId(), TestContentSlot) ==
      scene.frameGeneration()
    check scene.viewRenderSlotChangeGeneration(slotted.renderViewId(), TestOverlaySlot) ==
      overlayGeneration
    check retainedScenes.capturedViewCount(update) == 1
    check retainedScenes.capturedRenderSlotCount(update) == 1

    retainedScenes.apply(replica, update)
    check replica.materialize().canonicalNodes() == scene.materialize().canonicalNodes()
    check scene.materialize().canonicalNodes() == root.buildRenders().canonicalNodes()

  test "color edits replace only affected line renders and share glyph geometry":
    let
      root = newView(frame = rect(0, 0, 260, 140))
      textView = newTextView("αβγ\nsecond\nthird", frame = rect(0, 0, 240, 120))
    root.addSubview(textView)
    let
      scene = root.buildRenderScene()
      original = scene.materialize()
      source = textView.layoutManager().glyphArrangementResource()[].sourceRunes
      firstGeneration = scene.viewRenderSlotChangeGeneration(
        textView.renderViewId(), textLineRenderSlotId(0)
      )
      secondGeneration = scene.viewRenderSlotChangeGeneration(
        textView.renderViewId(), textLineRenderSlotId(1)
      )
    var attributes = textView.textStorage().attributesAt(0)
    let originalColor = attributes.foregroundColor
    attributes.foregroundColor = color(0.9, 0.1, 0.2)
    textView.textStorage().setAttributes(initTextRange(0, 1), attributes)
    check textView.layoutManager().hasValidLayout()
    check textView.needsDisplay
    discard root.buildRenderScene()
    check scene.viewRenderSlotChangeGeneration(
      textView.renderViewId(), textLineRenderSlotId(0)
    ) > firstGeneration
    check scene.viewRenderSlotChangeGeneration(
      textView.renderViewId(), textLineRenderSlotId(1)
    ) == secondGeneration
    var foundColor = false
    for node in scene.materialize()[DefaultDrawLevel].nodes:
      if node.kind == nkText:
        check node.textLayout.shared[].sourceRunes.sameUtf8Runes(source)
        check node.textLayout.arrangedGlyphs.len == 0
        if node.textLayout.sourceRuneRange(0).a == 0:
          require node.textLayout.spanColors.len >= 2
          check node.textLayout.spanColors[0].color == attributes.foregroundColor.rgba
          check node.textLayout.spanColors[1].color == originalColor.rgba
          foundColor = true
    check foundColor
    for node in original[DefaultDrawLevel].nodes:
      if node.kind == nkText:
        check node.textLayout.spanColors[0].color == originalColor.rgba

  test "dirty text updates retain unaffected visual-line fragments":
    let
      root = newView(frame = rect(0, 0, 260, 140))
      textView = newTextView("alpha\nbeta\ngamma", frame = rect(0, 0, 240, 120))
    root.addSubview(textView)

    let scene = root.buildRenderScene()
    let layoutSource = textView.layoutManager().glyphArrangementResource()[].sourceRunes
    var sharedLines = 0
    for node in scene.materialize()[DefaultDrawLevel].nodes:
      if node.kind == nkText:
        check node.textLayout.isGlyphView()
        check node.textLayout.arrangedGlyphs.len == 0
        check node.textLayout.positions.len == 0
        check node.textLayout.selectionRects.len == 0
        check node.textLayout.shared[].sourceRunes.sameUtf8Runes(layoutSource)
        inc sharedLines
    check sharedLines == 3
    let
      sceneIdentity = retainedScenes.sceneIdentity(scene)
      firstGeneration = scene.frameGeneration()
      firstLine = textLineRenderSlotId(0)
      secondLine = textLineRenderSlotId(1)
      thirdLine = textLineRenderSlotId(2)
      firstLineGeneration =
        scene.viewRenderSlotChangeGeneration(textView.renderViewId(), firstLine)
      secondLineGeneration =
        scene.viewRenderSlotChangeGeneration(textView.renderViewId(), secondLine)
      thirdLineGeneration =
        scene.viewRenderSlotChangeGeneration(textView.renderViewId(), thirdLine)

    textView.stringValue = "alpha\nBeta\ngamma"
    discard root.buildRenderScene()
    var dirtyUpdate =
      retainedScenes.newRenderSceneUpdate(scene, sceneIdentity, firstGeneration)

    check scene.viewRenderSlotChangeGeneration(textView.renderViewId(), firstLine) ==
      firstLineGeneration
    check scene.viewRenderSlotChangeGeneration(textView.renderViewId(), secondLine) >
      secondLineGeneration
    check scene.viewRenderSlotChangeGeneration(textView.renderViewId(), thirdLine) ==
      thirdLineGeneration
    check retainedScenes.capturedRenderSlotCount(dirtyUpdate) == 3

    var renderedLines: seq[string]
    for node in scene.materialize()[DefaultDrawLevel].nodes:
      if node.kind == nkText:
        var renderedLine: string
        for glyphIndex in 0 ..< node.textLayout.glyphCount():
          renderedLine.add node.textLayout.displayRune(glyphIndex)
        renderedLines.add renderedLine
    check renderedLines == @["alpha\n", "Beta\n", "gamma"]

    let replica = retainedScenes.newRenderSceneReplica()
    var fullUpdate = retainedScenes.newRenderSceneUpdate(scene, 0, 0)
    retainedScenes.apply(replica, fullUpdate)
    let
      liveNodes = scene.materialize()[DefaultDrawLevel].nodes
      replicaNodes = replica.materialize()[DefaultDrawLevel].nodes
    check liveNodes.len == replicaNodes.len
    for index, live in liveNodes:
      if live.kind == nkText:
        let isolated = replicaNodes[index]
        check isolated.textLayout.isGlyphView()
        check isolated.textLayout.arrangedGlyphs.len == 0
        check isolated.textLayout.shared[].sourceRunes.sameUtf8Runes(
          live.textLayout.shared[].sourceRunes
        )

    let
      secondGeneration = scene.frameGeneration()
      firstLineAfterEdit =
        scene.viewRenderSlotChangeGeneration(textView.renderViewId(), firstLine)
      secondLineAfterEdit =
        scene.viewRenderSlotChangeGeneration(textView.renderViewId(), secondLine)
      thirdLineAfterEdit =
        scene.viewRenderSlotChangeGeneration(textView.renderViewId(), thirdLine)
    textView.selectedRange = initTextRange(1, 2)
    discard root.buildRenderScene()
    var selectionUpdate =
      retainedScenes.newRenderSceneUpdate(scene, sceneIdentity, secondGeneration)

    check scene.viewRenderSlotChangeGeneration(textView.renderViewId(), firstLine) ==
      firstLineAfterEdit
    check scene.viewRenderSlotChangeGeneration(textView.renderViewId(), secondLine) ==
      secondLineAfterEdit
    check scene.viewRenderSlotChangeGeneration(textView.renderViewId(), thirdLine) ==
      thirdLineAfterEdit
    check retainedScenes.capturedRenderSlotCount(selectionUpdate) == 2

  test "mono text rendering retains unchanged rows and isolates cursor updates":
    let
      root = newView(frame = rect(0, 0, 240, 120))
      monoView = newMonoTextViewer("alpha\nbeta\ngamma", frame = rect(0, 0, 240, 120))
    root.addSubview(monoView)

    let scene = root.buildRenderScene()
    let
      sceneIdentity = retainedScenes.sceneIdentity(scene)
      firstGeneration = scene.frameGeneration()
      row0 = monoTextRowRenderSlotId(0)
      row1 = monoTextRowRenderSlotId(1)
      row2 = monoTextRowRenderSlotId(2)
      row0Generation =
        scene.viewRenderSlotChangeGeneration(monoView.renderViewId(), row0)
      row1Generation =
        scene.viewRenderSlotChangeGeneration(monoView.renderViewId(), row1)
      row2Generation =
        scene.viewRenderSlotChangeGeneration(monoView.renderViewId(), row2)

    monoView.replaceCells(1, 0, [initMonoTextCell("B")])
    discard root.buildRenderScene()
    var rowUpdate =
      retainedScenes.newRenderSceneUpdate(scene, sceneIdentity, firstGeneration)

    check scene.viewRenderSlotChangeGeneration(monoView.renderViewId(), row0) ==
      row0Generation
    check scene.viewRenderSlotChangeGeneration(monoView.renderViewId(), row1) >
      row1Generation
    check scene.viewRenderSlotChangeGeneration(monoView.renderViewId(), row2) ==
      row2Generation
    check retainedScenes.capturedRenderSlotCount(rowUpdate) == 3

    let secondGeneration = scene.frameGeneration()
    monoView.setCursorPosition(2, 2)
    discard root.buildRenderScene()
    var cursorUpdate =
      retainedScenes.newRenderSceneUpdate(scene, sceneIdentity, secondGeneration)
    check retainedScenes.capturedRenderSlotCount(cursorUpdate) == 1

  test "horizontal mono text scrolling refreshes column coverage and retains fractional moves":
    const source = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    let
      root = newView(rect(0, 0, 300, 100))
      viewport = newView(rect(0, 0, 120, 70))
      document = newMonoTextViewer(source, frame = rect(0, 0, 900, 70))
    viewport.clipsToBounds = true
    root.addSubview(viewport)
    viewport.addSubview(document)
    let
      cellWidth = document.monoTextMetrics().cellWidth
      rowSlot = monoTextRowRenderSlotId(0)
    viewport.frame = rect(0, 0, cellWidth * 10, 70)
    let scene = root.buildRenderScene()
    let original = scene.renderedText()

    for column in [20.25'f32, 0.0'f32, 40.25'f32, 0.0'f32]:
      let before =
        scene.viewRenderSlotChangeGeneration(document.renderViewId(), rowSlot)
      viewport.setBoundsOriginFromLayout(
        initPoint(document.padding + column * cellWidth, 0)
      )
      discard root.buildRenderScene()
      check scene.viewRenderSlotChangeGeneration(document.renderViewId(), rowSlot) >
        before
      let
        freshViewport = newView(viewport.frame)
        freshDocument = newMonoTextViewer(source, frame = document.frame)
      freshViewport.clipsToBounds = true
      freshViewport.addSubview(freshDocument)
      freshViewport.bounds = viewport.bounds
      check scene.renderedText() == freshViewport.buildRenderScene().renderedText()
      if column > 0:
        check scene.renderedText() != original

    viewport.setBoundsOriginFromLayout(
      initPoint(document.padding + 20.25 * cellWidth, 0)
    )
    discard root.buildRenderScene()
    let beforeFraction =
      scene.viewRenderSlotChangeGeneration(document.renderViewId(), rowSlot)
    viewport.setBoundsOriginFromLayout(
      initPoint(document.padding + 20.5 * cellWidth, 0)
    )
    discard root.buildRenderScene()
    check scene.viewRenderSlotChangeGeneration(document.renderViewId(), rowSlot) ==
      beforeFraction

    let beforeResize = scene.renderedText()
    viewport.frame = rect(0, 0, cellWidth * 14, 70)
    discard root.buildRenderScene()
    check scene.renderedText().len > beforeResize.len
    check scene.viewRenderSlotChangeGeneration(document.renderViewId(), rowSlot) >
      beforeFraction

  test "visible-rect drawing recaptures when scrolling changes its clip":
    let
      root = newView(frame = rect(0, 0, 180, 120))
      viewport = newCountedSceneView(rect(0, 0, 100, 80), color(0.2, 0.3, 0.4))
      document = newVisibleRectSceneView(rect(0, 0, 100, 240))
    viewport.clipsToBounds = true
    viewport.addSubview(document)
    root.addSubview(viewport)
    let scene = root.buildRenderScene()

    viewport.setBoundsOriginFromLayout(initPoint(0, 24))
    discard root.buildRenderScene()

    check viewport.drawCount == 1
    check document.drawCount == 2
    check scene.viewCaptureGeneration(document.renderViewId()) == 2

  test "appearance generation changes recapture inherited contributions":
    let
      root = newCountedSceneView(rect(0, 0, 100, 70), color(0.1, 0.1, 0.1))
      child = newCountedSceneView(rect(4, 5, 30, 20), color(0.7, 0.2, 0.1))
    root.addSubview(child)
    let
      firstAppearance = initAppearance(initTheme())
      scene = root.buildRenderScene(firstAppearance)
      secondAppearance = initAppearance(initTheme())

    discard root.buildRenderScene(secondAppearance)

    check root.drawCount == 2
    check child.drawCount == 2
    check scene.viewCaptureGeneration(root.renderViewId()) == 2
    check scene.viewCaptureGeneration(child.renderViewId()) == 2

  test "invalidation raised during draw remains pending":
    let view = newCountedSceneView(rect(0, 0, 100, 70), color(0.1, 0.2, 0.3))
    view.invalidatesDuringDraw = true

    let scene = view.buildRenderScene()
    let firstGeneration = scene.frameGeneration()
    check view.drawCount == 1
    check view.needsDisplay

    discard view.buildRenderScene()
    check view.drawCount == 2
    check not view.needsDisplay
    check scene.frameGeneration() == firstGeneration + 1

  test "hidden views are swept and recaptured with the same view identity":
    let
      root = newView(frame = rect(0, 0, 100, 70))
      child = newCountedSceneView(rect(4, 5, 30, 20), color(0.7, 0.2, 0.1))
      childId = child.renderViewId()
    root.addSubview(child)
    let scene = root.buildRenderScene()
    check scene.containsView(childId)

    child.hidden = true
    discard root.buildRenderScene()
    check not scene.containsView(childId)
    check child.drawCount == 1

    child.hidden = false
    discard root.buildRenderScene()
    check scene.containsView(childId)
    check child.drawCount == 2

  test "a moved view receives independent fragments in its new scene":
    let
      firstRoot = newView(frame = rect(0, 0, 100, 70))
      secondRoot = newView(frame = rect(0, 0, 100, 70))
      child = newCountedSceneView(rect(4, 5, 30, 20), color(0.7, 0.2, 0.1))
      childId = child.renderViewId()
    firstRoot.addSubview(child)
    let firstScene = firstRoot.buildRenderScene()

    child.removeFromSuperview()
    secondRoot.addSubview(child)
    let
      secondScene = secondRoot.buildRenderScene()
      secondOutput = secondScene.materialize().canonicalNodes()

    check firstScene.containsView(childId)
    check secondScene.containsView(childId)
    discard firstRoot.buildRenderScene()
    check not firstScene.containsView(childId)
    check secondScene.containsView(childId)
    check secondScene.materialize().canonicalNodes() == secondOutput

  test "escaped fragment attachment survives zero one and many roots":
    let
      root = newView(frame = rect(0, 0, 120, 80))
      output = newMultiOutputSceneView(rect(5, 6, 60, 40))
    root.addSubview(output)
    let scene = root.buildRenderScene()
    let
      fragmentIds = scene.viewFragmentIds(output.renderViewId())
      baseNodes = scene.materialize().canonicalNodes().len

    output.escapedRootCount = 1
    output.needsDisplay = true
    discard root.buildRenderScene()
    check scene.materialize().canonicalNodes().len == baseNodes + 1
    check scene.viewFragmentIds(output.renderViewId()) == fragmentIds

    output.escapedRootCount = 3
    output.needsDisplay = true
    discard root.buildRenderScene()
    check scene.materialize().canonicalNodes().len == baseNodes + 3
    check scene.viewFragmentIds(output.renderViewId()) == fragmentIds

    output.escapedRootCount = 0
    output.needsDisplay = true
    discard root.buildRenderScene()
    check scene.materialize().canonicalNodes().len == baseNodes
    check scene.viewFragmentIds(output.renderViewId()) == fragmentIds

  test "dynamic explicit layers retain depth-first insertion order":
    let
      root = newView(frame = rect(0, 0, 120, 80))
      output = newMultiOutputSceneView(rect(5, 6, 60, 40))
    root.addSubview(output)
    output.drawsTooltip = true
    output.drawsPopup = true

    let scene = root.buildRenderScene()
    check scene.materialize().renderLevels() ==
      @[DefaultDrawLevel, TooltipDrawLevel, PopupDrawLevel]

    output.drawsTooltip = false
    output.needsDisplay = true
    discard root.buildRenderScene()
    check scene.materialize().renderLevels() == @[DefaultDrawLevel, PopupDrawLevel]

    output.drawsPopup = false
    output.needsDisplay = true
    discard root.buildRenderScene()
    check scene.materialize().renderLevels() == @[DefaultDrawLevel]

  test "fragment traversal preserves clips transforms and shadows":
    let
      root = newView(frame = rect(0, 0, 120, 80))
      transformed = newTransformedSceneView(rect(8, 9, 60, 40), initPoint(6, -3))
      firstShadow = dropShadow(color(0, 0, 0, 0.4), y = 3.0, blur = 7.0)
    root.clipsToBounds = true
    transformed.shadow = @[firstShadow]
    root.addSubview(transformed)

    var monolithic = root.buildRenders()
    let scene = root.buildRenderScene()
    check scene.renderedOperations() == monolithic.renderedOperations()

    transformed.translation = initPoint(-2, 5)
    transformed.shadow = @[dropShadow(color(0.1, 0.2, 0.3, 0.5), x = 2.0, blur = 4.0)]
    transformed.needsDisplay = true
    discard root.buildRenderScene()

    let
      expectedRoot = newView(frame = rect(0, 0, 120, 80))
      expectedTransformed =
        newTransformedSceneView(rect(8, 9, 60, 40), initPoint(-2, 5))
    expectedRoot.clipsToBounds = true
    expectedTransformed.shadow =
      @[dropShadow(color(0.1, 0.2, 0.3, 0.5), x = 2.0, blur = 4.0)]
    expectedRoot.addSubview(expectedTransformed)
    monolithic = expectedRoot.buildRenders()
    check scene.renderedOperations() == monolithic.renderedOperations()

  test "font and image replacement updates the live manifest":
    clearImageCache()
    let
      firstImage = newImageResource(testImage(5, 5))
      secondImage = newImageResource(testImage(7, 6))
      firstStyle = TextStyle(
        color: color(0.1, 0.2, 0.3), fontName: defaultFontName(), fontSize: 11.0
      )
      secondStyle = TextStyle(
        color: color(0.7, 0.2, 0.1), fontName: defaultFontName(), fontSize: 17.0
      )
      firstFont = firstStyle.textFont()
      secondFont = secondStyle.textFont()
      view = newResourceSceneView(rect(0, 0, 80, 40), firstImage, firstStyle)
    var monolithic = view.buildRenders()
    let scene = view.buildRenderScene()

    check scene.materialize().canonicalNodes() == monolithic.canonicalNodes()
    check scene.renderResources().containsImage(firstImage.imageId())
    check not scene.renderResources().containsImage(secondImage.imageId())
    check scene.renderResources().containsFont(firstFont.fontId())
    check not scene.renderResources().containsFont(secondFont.fontId())

    view.image = secondImage
    view.style = secondStyle
    view.needsDisplay = true
    discard view.buildRenderScene()

    let expected = newResourceSceneView(rect(0, 0, 80, 40), secondImage, secondStyle)
    monolithic = expected.buildRenders()

    check scene.materialize().canonicalNodes() == monolithic.canonicalNodes()
    check not scene.renderResources().containsImage(firstImage.imageId())
    check scene.renderResources().containsImage(secondImage.imageId())
    check not scene.renderResources().containsFont(firstFont.fontId())
    check scene.renderResources().containsFont(secondFont.fontId())
    check scene.retiredResourceCount() == 1

  test "resource manifests merge and retain their union":
    clearImageCache()
    let
      first = newImageResource(testImage(5, 5))
      second = newImageResource(testImage(6, 6))
    var
      firstManifest = initRenderResourceManifest()
      secondManifest = initRenderResourceManifest()
    firstManifest.addImage(first)
    secondManifest.addImage(second)

    var merged = mergeRenderResources([firstManifest, nil, secondManifest])
    check merged.imageCount() == 2
    firstManifest = nil
    secondManifest = nil
    check hasImage(first.imageId())
    check hasImage(second.imageId())

    merged = nil
    check not hasImage(first.imageId())
    check not hasImage(second.imageId())

  test "removed view resources leave the live manifest at the frame boundary":
    clearImageCache()
    let
      image = newImageResource(testImage(7, 5))
      root = newView(frame = rect(0, 0, 80, 50))
      imageView = newImageView(image, frame = rect(3, 4, 20, 15))
    root.addSubview(imageView)

    let scene = root.buildRenderScene()
    check scene.renderResources().imageCount() == 1
    check hasImage(image.imageId())

    imageView.removeFromSuperview()
    discard root.buildRenderScene()
    check scene.renderResources().imageCount() == 0
    check scene.retiredResourceCount() == 1
    check hasImage(image.imageId())

    scene.acknowledgeRenderGeneration(scene.frameGeneration())
    check scene.retiredResourceCount() == 0
    check not hasImage(image.imageId())

  test "scene retains replaced manifests until acknowledgement":
    clearImageCache()
    let
      first = newImageResource(testImage(3, 3))
      second = newImageResource(testImage(4, 4))
      scene = newRenderScene()
    var
      firstManifest = initRenderResourceManifest()
      secondManifest = initRenderResourceManifest()
    firstManifest.addImage(first)
    secondManifest.addImage(second)

    scene.replaceContents(newRenders(), firstManifest, newSeq[RenderViewId]())
    firstManifest = nil
    scene.replaceContents(newRenders(), secondManifest, newSeq[RenderViewId]())
    secondManifest = nil

    check scene.frameGeneration() == 2
    check scene.retiredResourceCount() == 1
    check hasImage(first.imageId())
    scene.acknowledgeRenderGeneration(1)
    check scene.retiredResourceCount() == 1
    check hasImage(first.imageId())
    scene.acknowledgeRenderGeneration(2)
    check scene.retiredResourceCount() == 0
    check not hasImage(first.imageId())
    check hasImage(second.imageId())

    var emptyFrame: seq[RenderViewFrame]
    discard scene.reconcile(emptyFrame, DefaultDrawLevel)
    check scene.renderResources().imageCount() == 0
    check scene.retiredResourceCount() == 1
    check hasImage(second.imageId())
    scene.acknowledgeRenderGeneration(scene.frameGeneration())
    check not hasImage(second.imageId())
