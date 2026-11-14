## Detached layout and drawing capture for declarative drag hosts.
import std/[sets, tables]
import figdraw as fd
import ../drawing/[drawing, rendering, renderscenes]
import ../foundation/types
import ../themes
import ../view/views
import ./dragbehaviors

type
  DragEnvironment* = object
    bounds*: Rect
    appearance*: Appearance

  DragDrawing = object
    renders: Renders
    resources: RenderResourceManifest

  DragElementPreview* = object
    id*: string
    frame*: Rect
    clip*: Rect
    drawing: DragDrawing
    drawingOrigin: Point

  DragPreview* = object
    elements*: seq[DragElementPreview]
    backdrop: DragDrawing
    backdropOrigin: Point

proc capture(
    view: View, appearance: Appearance, excluded: seq[View] = @[]
): DragDrawing =
  let scene = captureRenderScene(view, appearance, excluded)
  DragDrawing(renders: scene.materialize(), resources: scene.renderResources())

proc find*(preview: DragPreview, id: string): int =
  for i, element in preview.elements:
    if element.id == id:
      return i
  -1

proc captureDragPreview*(root: View, environment: DragEnvironment): DragPreview =
  ## Every nonempty `dragId` marks an independently draggable subtree.
  ## Ordinary view identifiers do not opt views into dragging.
  ## IDs must be unique and non-nested. Builders must return fresh detached trees
  ## without timers, actions, subscriptions to live models, or native resources.
  if root.isNil or not root.superview.isNil or not root.window.isNil:
    raise newException(ValueError, "drag preview requires a detached root")
  root.frame = rect(0, 0, environment.bounds.size.width, environment.bounds.size.height)
  root.bounds = environment.bounds
  root.setInheritedAppearance(environment.appearance)
  root.layoutSubtreeIfNeeded()
  var nodes: seq[View]
  var ids = initHashSet[string]()
  proc visit(view: View, insideElement: bool) =
    if view.dragId.len > 0:
      if insideElement or view == root or view.dragId in ids:
        raise newException(
          ValueError, "dragId must identify unique, non-nested descendants"
        )
      ids.incl view.dragId
      if not view.isHiddenOrHasHiddenAncestor():
        nodes.add view
    for child in view.subviews:
      visit(child, insideElement or view.dragId.len > 0)

  visit(root, false)
  for node in nodes:
    # An extracted subtree is still content, not a new themed window root.
    node.usesThemedRootBackground = false
    let frame = root.rectFromView(node.bounds, node)
    if not frame.origin.finite or
        not initPoint(frame.size.width, frame.size.height).finite:
      raise newException(ValueError, "non-finite drag preview geometry")
    var clip = environment.bounds
    var ancestor = node.superview
    while not ancestor.isNil and ancestor != root:
      if ancestor.clipsToBounds:
        clip = clip.intersection(root.rectFromView(ancestor.bounds, ancestor))
      ancestor = ancestor.superview
    result.elements.add DragElementPreview(
      id: node.dragId,
      frame: frame,
      clip: clip,
      drawingOrigin: node.frame.origin,
      drawing: capture(node, environment.appearance),
    )
  result.backdrop = capture(root, environment.appearance, nodes)
  result.backdropOrigin = environment.bounds.origin

proc appendNode(context: DrawContext, list: RenderList, index, parent: FigIdx) =
  var node = list.nodes[index.int]
  node.childCount = 0
  let dest = context.addFig(parent, node)
  for child in list.nodes.childIndex(index):
    context.appendNode(list, child, dest)

proc draw(drawing: DragDrawing, context: DrawContext, offset: Point, parent: FigIdx) =
  if drawing.renders.isNil:
    return
  let transform = context.addFig(
    parent,
    Fig(
      kind: nkTransform,
      transform: TransformStyle(translation: vec2(offset.x, offset.y)),
    ),
  )
  # Flatten the snapshot's ordered layers beneath the host's own clip and level.
  for _, list in drawing.renders.layers:
    for root in list.rootIds:
      context.appendNode(list, root, transform)
  var resources = context.resources()
  resources.addResources(drawing.resources)

proc drawBackdrop*(preview: DragPreview, context: DrawContext) =
  preview.backdrop.draw(context, preview.backdropOrigin, context.renderParent)

proc drawElement*(
    element: DragElementPreview, context: DrawContext, origin: Point, clipped = true
) =
  let parent =
    if clipped:
      context.addRenderRectangle(
        context.renderLayer,
        context.renderParent,
        element.clip,
        fd.fill(color(0, 0, 0, 0).rgba),
        clips = true,
      )
    else:
      context.renderParent
  element.drawing.draw(
    context,
    initPoint(origin.x - element.drawingOrigin.x, origin.y - element.drawingOrigin.y),
    parent,
  )
