import std/unittest

import figdraw
import pkg/pixie except draw

import merenda/nimkit

type
  SceneDrawView = ref object of View
  ScenePopupView = ref object of View

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

proc newSceneDrawView(frame: Rect): SceneDrawView =
  result = SceneDrawView()
  result.initViewFields(frame)
  discard result.withProtocol(SceneDrawing)

proc newScenePopupView(frame: Rect): ScenePopupView =
  result = ScenePopupView()
  result.initViewFields(frame)
  discard result.withProtocol(ScenePopupDrawing)

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
