import std/unittest

import figdraw
import pkg/pixie except draw

import merenda/nimkit

type
  SceneDrawView = ref object of View
  ScenePopupView = ref object of View
  CountedSceneView = ref object of View
    drawCount: int
    drawColor: Color
    invalidatesDuringDraw: bool

  MultiOutputSceneView = ref object of View
    escapedRootCount: int
    drawsPopup: bool
    drawsTooltip: bool

  CanonicalRenderNode = object
    level: ZLevel
    depth: int
    node: string

var sceneDrawCount: int

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
  method draw(view: CountedSceneView, context: DrawContext) =
    inc view.drawCount
    context.addRectangle(rect(1, 2, 9, 7), view.drawColor)
    if view.invalidatesDuringDraw:
      view.invalidatesDuringDraw = false
      view.needsDisplay = true

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

proc newMultiOutputSceneView(frame: Rect): MultiOutputSceneView =
  result = MultiOutputSceneView()
  result.initViewFields(frame)
  discard result.withProtocol(MultiOutputSceneDrawing)

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

proc testImage(width, height: int): Image =
  result = newImage(width, height)
  result.fill(rgba(64, 128, 192, 255))

suite "NimKit render fragments":
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

    check sceneDrawCount == 2
    check materialized.renderLevels() == monolithic.renderLevels()
    check materialized.canonicalNodes() == monolithic.canonicalNodes()
    check scene.viewEntryCount() == 4
    check scene.containsView(root.renderViewId())
    check scene.containsView(custom.renderViewId())

    let cachedScene = root.buildRenderScene()
    check cachedScene == scene
    check cachedScene.frameGeneration() == firstGeneration
    check sceneDrawCount == 2

    custom.needsDisplay = true
    let updatedScene = root.buildRenderScene()
    check updatedScene == scene
    check updatedScene.frameGeneration() == firstGeneration + 1
    check updatedScene.rootFragmentIds() == firstFragmentIds
    check sceneDrawCount == 3
    check updatedScene.materialize().canonicalNodes() ==
      root.buildRenders().canonicalNodes()

    let removedId = custom.renderViewId()
    custom.removeFromSuperview()
    discard root.buildRenderScene()
    check not scene.containsView(removedId)
    check scene.viewEntryCount() == 3

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
