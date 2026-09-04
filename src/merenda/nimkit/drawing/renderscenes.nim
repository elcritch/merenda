## Retained, per-view render scenes built on FigDraw fragment attachments.
##
## Each visible view owns stable placement and content transform fragments. They
## keep frame and bounds-origin movement separate from replaceable drawing::
##
##   placement transform
##   +-- background/clip shell
##   |   +-- clipped content transform
##   |       +-- self drawing
##   |       +-- child placement transform
##   +-- escaped content transform
##       +-- escaped drawing
##
## Scrolling or moving an ancestor updates only placement transform nodes. It does
## not rebuild a descendant's drawing unless that drawing read
## `DrawContext.visibleRect`; that dependency is recorded during capture. Explicit
## layers use equivalent layer-root transforms. Stable fragment IDs and nested
## attachments therefore survive placement-only updates.

import std/[hashes, tables]

import figdraw

import ./renderresources
import ../foundation/types

type
  RenderViewId* = distinct uint64
    ## Stable application-thread identity for a NimKit view.

  RenderViewCacheKey* = object
    ## Drawing and placement inputs for one stable view identity.
    displayRevision*: uint64
    appearanceGeneration*: uint64
    frame*: Rect
    placement*: Point
    bounds*: Rect
    visibleRect*: Rect
    level*: ZLevel
    isRoot*: bool

  RenderLayerContribution* = object
    ## Root drawing emitted explicitly onto a layer by one view.
    level*: ZLevel
    contents*: RenderList

  RenderViewSlotFrame* = object
    ## One ordered, independently replaceable part of a view's own drawing.
    slotId*: RenderSlotId
    position*: RenderSlotPosition
    revision*: uint64
    captured*: bool
    contents*: RenderList
    escapedContents*: RenderList
    extraLayers*: seq[RenderLayerContribution]
    resources*: RenderResourceManifest
    usesVisibleRect*: bool

  RenderViewFrame* = object
    ## One visible view's changed placement and optional drawing contribution.
    viewId*: RenderViewId
    parentViewId*: RenderViewId
    cacheKey*: RenderViewCacheKey
    placementChanged*: bool
    captured*: bool
    placement*: Fig
    shell*: Fig
    contentTransform*: Fig
    escapedTransform*: Fig
    slots*: seq[RenderViewSlotFrame]

  ViewPlacement = object
    viewId: RenderViewId
    parentViewId: RenderViewId
    level: ZLevel

  ViewRenderSlotEntry = object
    position: RenderSlotPosition
    revision: uint64
    contents: RenderList
    escapedContents: RenderList
    extraLayers: seq[RenderLayerContribution]
    resources: RenderResourceManifest
    usesVisibleRect: bool
    handle: RenderFragmentHandle
    escapedHandle: RenderFragmentHandle
    extraHandles: Table[ZLevel, RenderFragmentHandle]
    changeGeneration: uint64

  ViewRenderEntry = object
    cacheKey: RenderViewCacheKey
    placement: Fig
    shell: Fig
    contentTransform: Fig
    escapedTransform: Fig
    slots: Table[RenderSlotId, ViewRenderSlotEntry]
    slotOrder: seq[RenderSlotId]
    placementHandle: RenderFragmentHandle
    placementCursor: RenderCursor
    shellHandle: RenderFragmentHandle
    shellCursor: RenderCursor
    contentHandle: RenderFragmentHandle
    contentCursor: RenderCursor
    escapedTransformHandle: RenderFragmentHandle
    escapedTransformCursor: RenderCursor
    externalParent: RenderViewId
    captureGeneration: uint64
    changeGeneration: uint64
    captureChangeGeneration: uint64

  RenderSlotCacheState* = object
    ## Cached slot metadata used to plan a partial view recapture.
    slotId*: RenderSlotId
    position*: RenderSlotPosition
    revision*: uint64
    usesVisibleRect*: bool

  RetiredRenderResources = object
    releaseGeneration: uint64
    manifest: RenderResourceManifest

  RenderScene* = ref object
    ## Fragment-backed render state owned by one window/content render root.
    tree: RenderFragments
    rootLevels: seq[ZLevel]
    rootFragments: seq[RenderFragmentHandle]
    viewEntries: Table[RenderViewId, ViewRenderEntry]
    placements: seq[ViewPlacement]
    generation: uint64
    perViewMode: bool
    liveResources: RenderResourceManifest
    retiredResources: seq[RetiredRenderResources]
    identity: uint64
    baseLevel: ZLevel
    replicaMode: bool
    fullTransferGeneration: uint64

  RenderSceneUpdate* = object
    ## Move-only cumulative update for a renderer-owned scene replica.
    ##
    ## Every update contains the complete current placement order, but only
    ## contributions changed after `baseGeneration` carry drawing payloads.
    ## Placement-only changes carry cache keys and update retained transform nodes.
    ## A full update carries every payload and acts as an ordering barrier.
    sceneIdentity: uint64
    baseGeneration: uint64
    generation: uint64
    full: bool
    baseLevel: ZLevel
    frames: seq[RenderViewFrame]
    resources: RenderResourceSnapshot

var
  renderViewIdCounter: uint64
  renderSceneIdCounter: uint64

proc `=copy`*(destination: var RenderSceneUpdate, source: RenderSceneUpdate) {.error.}
proc `=dup`*(source: RenderSceneUpdate): RenderSceneUpdate {.error.}

func `==`*(a, b: RenderViewId): bool {.borrow.}
func hash*(id: RenderViewId): Hash {.borrow.}

proc advance(value: var uint64) =
  inc value
  if value == 0:
    value = 1

proc nextRenderViewId*(): RenderViewId =
  ## Allocates an identity on NimKit's application thread.
  renderViewIdCounter.advance()
  renderViewIdCounter.RenderViewId

proc nextRenderSceneId(): uint64 =
  renderSceneIdCounter.advance()
  renderSceneIdCounter

proc initRenderScene(identity: uint64): RenderScene =
  RenderScene(
    tree: newRenderFragments(),
    viewEntries: initTable[RenderViewId, ViewRenderEntry](),
    identity: identity,
  )

proc newRenderScene*(): RenderScene =
  initRenderScene(nextRenderSceneId())

proc newRenderSceneReplica*(): RenderScene =
  ## Creates renderer-owned storage whose application identity comes from updates.
  result = initRenderScene(0)
  result.replicaMode = true

proc copyRenderList(list: RenderList): RenderList =
  result.nodes = newSeqOfCap[Fig](list.nodes.len)
  for node in list.nodes:
    result.nodes.add node
  result.rootIds = newSeqOfCap[FigIdx](list.rootIds.len)
  for root in list.rootIds:
    result.rootIds.add root

proc isolateSequence[T](values: openArray[T]): seq[T] =
  result = newSeqOfCap[T](values.len)
  for value in values:
    result.add value

proc isolateGlyphArrangement(layout: GlyphArrangement): GlyphArrangement =
  result = layout
  result.lines = layout.lines.isolateSequence()
  result.spans = layout.spans.isolateSequence()
  result.fonts = layout.fonts.isolateSequence()
  result.spanColors = layout.spanColors.isolateSequence()
  result.sourceRunes = layout.sourceRunes.isolateSequence()
  result.arrangedGlyphs = layout.arrangedGlyphs.isolateSequence()
  result.runes = layout.runes.isolateSequence()
  result.positions = layout.positions.isolateSequence()
  result.selectionRects = layout.selectionRects.isolateSequence()

proc isolateDrawableOp(operation: DrawableOp): DrawableOp =
  result = operation
  if operation.kind == dkBezier:
    result.controls = operation.controls.isolateSequence()

proc isolateFig(node: Fig): Fig =
  result = node
  case node.kind
  of nkText:
    result.textLayout = node.textLayout.isolateGlyphArrangement()
  of nkDrawable:
    result.drawOps = newSeqOfCap[DrawableOp](node.drawOps.len)
    for operation in node.drawOps:
      result.drawOps.add operation.isolateDrawableOp()
  else:
    discard

proc isolateRenderList(list: RenderList): RenderList =
  ## Clones nested glyph/drawable sequences as well as the outer node storage.
  ## Renderer updates must not share ARC-managed payloads with the UI scene.
  result.nodes = newSeqOfCap[Fig](list.nodes.len)
  for node in list.nodes:
    result.nodes.add node.isolateFig()
  result.rootIds = list.rootIds.isolateSequence()

proc nodeRenderList(node: Fig): RenderList =
  discard result.addRoot(node)

proc buildFragmentTree(
    renders: Renders
): tuple[tree: RenderFragments, levels: seq[ZLevel], roots: seq[RenderFragmentHandle]] =
  if renders.isNil:
    raise newException(ValueError, "cannot build a render scene from nil Renders")

  result.tree = newRenderFragments()
  for level, list in renders.pairs():
    result.levels.add level
    result.roots.add result.tree.attachRootFragment(level, 0, list.copyRenderList())

proc replaceContents*(
    scene: RenderScene,
    renders: Renders,
    resources: RenderResourceManifest,
    seenViews: openArray[RenderViewId],
) =
  ## Installs a validated monolithic build as a fragment snapshot.
  ##
  ## This compatibility path deliberately discards per-view cache entries. The
  ## next incremental reconciliation will capture scene-local contributions.
  if scene.isNil:
    raise newException(ValueError, "cannot update a nil render scene")

  let built = renders.buildFragmentTree()
  var nextGeneration = scene.generation
  nextGeneration.advance()

  var nextEntries = initTable[RenderViewId, ViewRenderEntry]()
  for id in seenViews:
    if id.uint64 == 0:
      raise newException(ValueError, "render scene received an invalid view identity")
    nextEntries[id] = ViewRenderEntry()

  if not scene.liveResources.isNil and scene.liveResources != resources:
    scene.retiredResources.add RetiredRenderResources(
      releaseGeneration: nextGeneration, manifest: scene.liveResources
    )

  if not scene.perViewMode and scene.rootLevels == built.levels and
      scene.rootFragments.len == built.roots.len:
    var nextRoots = newSeqOfCap[RenderFragmentHandle](scene.rootFragments.len)
    for index, level in built.levels:
      nextRoots.add scene.tree.replaceFragment(
        scene.rootFragments[index], renders.layers[level].copyRenderList()
      )
    scene.rootFragments = move nextRoots
  else:
    scene.tree = built.tree
    scene.rootLevels = built.levels
    scene.rootFragments = built.roots
  scene.viewEntries = move nextEntries
  scene.placements.setLen(0)
  scene.generation = nextGeneration
  scene.perViewMode = false
  scene.liveResources = resources

proc requiresFullViewCapture*(
    scene: RenderScene, viewId: RenderViewId, cacheKey: RenderViewCacheKey
): bool =
  ## Reports whether every drawing slot must be recaptured for this view.
  if scene.isNil or not scene.perViewMode or viewId notin scene.viewEntries:
    return true
  let cached = scene.viewEntries[viewId].cacheKey
  cached.appearanceGeneration != cacheKey.appearanceGeneration or
    cached.frame.size != cacheKey.frame.size or
    cached.bounds.size != cacheKey.bounds.size or cached.level != cacheKey.level or
    cached.isRoot != cacheKey.isRoot

proc viewSlotCacheStates*(
    scene: RenderScene, viewId: RenderViewId
): seq[RenderSlotCacheState] =
  ## Returns slot revisions in their current drawing order.
  if scene.isNil or not scene.perViewMode or viewId notin scene.viewEntries:
    return
  let entry = addr scene.viewEntries[viewId]
  result = newSeqOfCap[RenderSlotCacheState](entry[].slotOrder.len)
  for slotId in entry[].slotOrder:
    let slot = addr entry[].slots[slotId]
    result.add RenderSlotCacheState(
      slotId: slotId,
      position: slot[].position,
      revision: slot[].revision,
      usesVisibleRect: slot[].usesVisibleRect,
    )

proc forcedVisibleRectSlots*(
    scene: RenderScene, viewId: RenderViewId, visibleRect: Rect
): seq[RenderSlotId] =
  ## Returns cached slots whose drawing depends on a changed visible rectangle.
  if scene.isNil or not scene.perViewMode or viewId notin scene.viewEntries:
    return
  let entry = addr scene.viewEntries[viewId]
  if entry[].cacheKey.visibleRect == visibleRect:
    return
  for slotId in entry[].slotOrder:
    if entry[].slots[slotId].usesVisibleRect:
      result.add slotId

proc needsViewCapture*(
    scene: RenderScene, viewId: RenderViewId, cacheKey: RenderViewCacheKey
): bool =
  ## Reports whether this scene needs at least one current drawing slot.
  if scene.requiresFullViewCapture(viewId, cacheKey):
    return true
  let entry = addr scene.viewEntries[viewId]
  entry[].cacheKey.displayRevision != cacheKey.displayRevision or (
    entry[].cacheKey.visibleRect != cacheKey.visibleRect and
    scene.forcedVisibleRectSlots(viewId, cacheKey.visibleRect).len > 0
  )

proc needsViewPlacementUpdate*(
    scene: RenderScene, viewId: RenderViewId, cacheKey: RenderViewCacheKey
): bool =
  ## Reports whether the view's retained transform placement changed.
  scene.isNil or not scene.perViewMode or viewId notin scene.viewEntries or
    scene.viewEntries[viewId].cacheKey != cacheKey

proc externalParent(
    frame: RenderViewFrame, levels: Table[RenderViewId, ZLevel]
): RenderViewId =
  if frame.parentViewId.uint64 == 0 or levels[frame.parentViewId] != frame.cacheKey.level:
    return 0.RenderViewId
  frame.parentViewId

proc validateFrames(frames: openArray[RenderViewFrame]) =
  var levels = initTable[RenderViewId, ZLevel]()
  for frame in frames:
    if frame.viewId.uint64 == 0:
      raise newException(ValueError, "render frame received an invalid view identity")
    if frame.viewId in levels:
      raise newException(ValueError, "render frame contains a duplicate view identity")
    if frame.parentViewId.uint64 != 0 and frame.parentViewId notin levels:
      raise newException(ValueError, "render frame parent must precede its child")
    var slots = initTable[RenderSlotId, bool]()
    for slot in frame.slots:
      if slot.slotId in slots:
        raise newException(ValueError, "render frame contains a duplicate slot")
      slots[slot.slotId] = true
    levels[frame.viewId] = frame.cacheKey.level

proc nextPlacements(frames: openArray[RenderViewFrame]): seq[ViewPlacement] =
  result = newSeqOfCap[ViewPlacement](frames.len)
  for frame in frames:
    result.add ViewPlacement(
      viewId: frame.viewId,
      parentViewId: frame.parentViewId,
      level: frame.cacheKey.level,
    )

proc containsLevel(levels: openArray[ZLevel], level: ZLevel): bool =
  for candidate in levels:
    if candidate == level:
      return true

proc sameLayerShape(
    cached: openArray[RenderLayerContribution],
    captured: openArray[RenderLayerContribution],
): bool =
  if cached.len != captured.len:
    return false
  for index, layer in cached:
    if layer.level != captured[index].level:
      return false
  true

proc desiredLevels(
    scene: RenderScene, frames: openArray[RenderViewFrame], baseLevel: ZLevel
): seq[ZLevel] =
  result.add baseLevel
  for frame in frames:
    if not result.containsLevel(frame.cacheKey.level):
      result.add frame.cacheKey.level
    let entry = addr scene.viewEntries[frame.viewId]
    for slotId in entry[].slotOrder:
      for extra in entry[].slots[slotId].extraLayers:
        if not result.containsLevel(extra.level):
          result.add extra.level

proc attachRoot(
    scene: RenderScene, level: ZLevel, contents: var RenderList
): RenderFragmentHandle =
  if scene.replicaMode:
    scene.tree.attachRootFragment(level, 0, move contents)
  else:
    scene.tree.attachRootFragment(level, 0, contents.copyRenderList())

proc attachChild(
    scene: RenderScene, parent: RenderCursor, contents: var RenderList
): RenderFragmentHandle =
  if scene.replicaMode:
    scene.tree.attachChildFragment(parent, 0, move contents)
  else:
    scene.tree.attachChildFragment(parent, 0, contents.copyRenderList())

proc attachViewEntry(
    scene: RenderScene, entry: var ViewRenderEntry, parent: RenderViewId
) =
  var placementList = entry.placement.nodeRenderList()
  if parent.uint64 == 0:
    entry.placementHandle = scene.attachRoot(entry.cacheKey.level, placementList)
  else:
    entry.placementHandle =
      scene.attachChild(scene.viewEntries[parent].contentCursor, placementList)

  let roots = scene.tree.fragmentRoots(entry.placementHandle)
  if roots.len != 1:
    raise newException(
      ValueError, "a view placement fragment must contain exactly one root"
    )
  entry.placementCursor = roots[0]

  var shellList = entry.shell.nodeRenderList()
  entry.shellHandle = scene.attachChild(entry.placementCursor, shellList)
  let shellRoots = scene.tree.fragmentRoots(entry.shellHandle)
  if shellRoots.len != 1:
    raise
      newException(ValueError, "a view shell fragment must contain exactly one root")
  entry.shellCursor = shellRoots[0]

  var contentList = entry.contentTransform.nodeRenderList()
  entry.contentHandle = scene.attachChild(entry.shellCursor, contentList)
  let contentRoots = scene.tree.fragmentRoots(entry.contentHandle)
  if contentRoots.len != 1:
    raise
      newException(ValueError, "a view content fragment must contain exactly one root")
  entry.contentCursor = contentRoots[0]

  var escapedTransformList = entry.escapedTransform.nodeRenderList()
  entry.escapedTransformHandle =
    scene.attachChild(entry.placementCursor, escapedTransformList)
  let escapedTransformRoots = scene.tree.fragmentRoots(entry.escapedTransformHandle)
  if escapedTransformRoots.len != 1:
    raise newException(
      ValueError, "an escaped content fragment must contain exactly one root"
    )
  entry.escapedTransformCursor = escapedTransformRoots[0]
  for slotId in entry.slotOrder:
    let slot = addr entry.slots[slotId]
    slot[].handle = scene.attachChild(entry.contentCursor, slot[].contents)
    slot[].escapedHandle =
      scene.attachChild(entry.escapedTransformCursor, slot[].escapedContents)
    slot[].extraHandles = initTable[ZLevel, RenderFragmentHandle]()
    for extra in slot[].extraLayers.mitems:
      slot[].extraHandles[extra.level] = scene.attachRoot(extra.level, extra.contents)
  entry.externalParent = parent

proc detachEntry(scene: RenderScene, entry: ViewRenderEntry) =
  for slotId in entry.slotOrder:
    let slot = entry.slots[slotId]
    for _, handle in slot.extraHandles:
      if scene.tree.isValid(handle):
        scene.tree.removeFragment(handle)
  if scene.tree.isValid(entry.placementHandle):
    scene.tree.removeFragment(entry.placementHandle)

proc rebuildTree(
    scene: RenderScene, frames: openArray[RenderViewFrame], levels: seq[ZLevel]
) =
  scene.tree = newRenderFragments()
  scene.rootLevels = levels
  scene.rootFragments.setLen(0)

  var viewLevels = initTable[RenderViewId, ZLevel]()
  for frame in frames:
    viewLevels[frame.viewId] = frame.cacheKey.level
  for frame in frames:
    let entry = addr scene.viewEntries[frame.viewId]
    scene.attachViewEntry(entry[], frame.externalParent(viewLevels))

proc refreshPlacementNodes(entry: var ViewRenderEntry, cacheKey: RenderViewCacheKey) =
  entry.cacheKey = cacheKey
  entry.placement.transform.translation =
    vec2(cacheKey.placement.x, cacheKey.placement.y)
  let contentTranslation = cacheKey.bounds.origin
  entry.contentTransform.transform.translation =
    vec2(-contentTranslation.x, -contentTranslation.y)
  entry.escapedTransform.transform.translation =
    entry.contentTransform.transform.translation
  for slotId in entry.slotOrder:
    for extra in entry.slots[slotId].extraLayers.mitems:
      if extra.contents.rootIds.len != 1:
        raise newException(ValueError, "an extra-layer placement must have one root")
      let root = extra.contents.rootIds[0]
      if extra.contents.nodes[root.int].kind != nkTransform:
        raise
          newException(ValueError, "an extra-layer placement root must be a transform")
      extra.contents.nodes[root.int].transform.translation = vec2(
        cacheKey.frame.origin.x - cacheKey.bounds.origin.x,
        cacheKey.frame.origin.y - cacheKey.bounds.origin.y,
      )

proc updatePlacementEntry(scene: RenderScene, entry: var ViewRenderEntry) =
  scene.tree.updateNode(entry.placementCursor, entry.placement)
  scene.tree.updateNode(entry.contentCursor, entry.contentTransform)
  scene.tree.updateNode(entry.escapedTransformCursor, entry.escapedTransform)
  for slotId in entry.slotOrder:
    let slot = addr entry.slots[slotId]
    for extra in slot[].extraLayers:
      let roots = scene.tree.fragmentRoots(slot[].extraHandles[extra.level])
      if roots.len != 1:
        raise newException(ValueError, "an extra-layer fragment must have one root")
      scene.tree.updateNode(
        roots[0], extra.contents.nodes[extra.contents.rootIds[0].int]
      )

proc updateCapturedSlot(scene: RenderScene, slot: var ViewRenderSlotEntry) =
  if scene.replicaMode:
    slot.handle = scene.tree.replaceFragment(slot.handle, move slot.contents)
    slot.escapedHandle =
      scene.tree.replaceFragment(slot.escapedHandle, move slot.escapedContents)
  else:
    slot.handle =
      scene.tree.replaceFragment(slot.handle, slot.contents.copyRenderList())
    slot.escapedHandle = scene.tree.replaceFragment(
      slot.escapedHandle, slot.escapedContents.copyRenderList()
    )

  var retained = initTable[ZLevel, bool]()
  for extra in slot.extraLayers.mitems:
    retained[extra.level] = true
    if extra.level in slot.extraHandles:
      if scene.replicaMode:
        slot.extraHandles[extra.level] = scene.tree.replaceFragment(
          slot.extraHandles[extra.level], move extra.contents
        )
      else:
        slot.extraHandles[extra.level] = scene.tree.replaceFragment(
          slot.extraHandles[extra.level], extra.contents.copyRenderList()
        )
    else:
      slot.extraHandles[extra.level] = scene.attachRoot(extra.level, extra.contents)

  var removed: seq[ZLevel]
  for level in slot.extraHandles.keys:
    if level notin retained:
      removed.add level
  for level in removed:
    let handle = slot.extraHandles[level]
    if scene.tree.isValid(handle):
      scene.tree.removeFragment(handle)
    slot.extraHandles.del(level)

proc updateCapturedEntry(
    scene: RenderScene,
    entry: var ViewRenderEntry,
    capturedSlots: openArray[RenderSlotId],
) =
  scene.tree.updateNode(entry.placementCursor, entry.placement)
  scene.tree.updateNode(entry.shellCursor, entry.shell)
  scene.tree.updateNode(entry.contentCursor, entry.contentTransform)
  scene.tree.updateNode(entry.escapedTransformCursor, entry.escapedTransform)
  for slotId in capturedSlots:
    scene.updateCapturedSlot(entry.slots[slotId])

proc moveViewEntry(
    scene: RenderScene, entry: var ViewRenderEntry, parent: RenderViewId
) =
  if entry.externalParent == parent:
    return
  if parent.uint64 == 0:
    entry.placementHandle =
      scene.tree.moveFragmentToRoot(entry.placementHandle, entry.cacheKey.level, 0)
  else:
    let parentCursor = scene.viewEntries[parent].contentCursor
    entry.placementHandle =
      scene.tree.moveFragment(entry.placementHandle, parentCursor, 0)
  entry.externalParent = parent

proc reconcileOrders(
    scene: RenderScene, frames: openArray[RenderViewFrame], levels: openArray[ZLevel]
) =
  var
    viewLevels = initTable[RenderViewId, ZLevel]()
    childOrders = initTable[RenderViewId, seq[RenderFragmentHandle]]()
    rootOrders = initTable[ZLevel, seq[RenderFragmentHandle]]()

  for level in levels:
    rootOrders[level] = @[]
  for frame in frames:
    viewLevels[frame.viewId] = frame.cacheKey.level
    childOrders[frame.viewId] = @[]
    let entry = addr scene.viewEntries[frame.viewId]
    for slotId in entry[].slotOrder:
      if entry[].slots[slotId].position == rspBeforeSubviews:
        childOrders[frame.viewId].add entry[].slots[slotId].handle

  for frame in frames:
    let
      entry = addr scene.viewEntries[frame.viewId]
      parent = frame.externalParent(viewLevels)
    if parent.uint64 == 0:
      rootOrders[frame.cacheKey.level].add entry[].placementHandle
    else:
      childOrders[parent].add entry[].placementHandle
    for slotId in entry[].slotOrder:
      let slot = addr entry[].slots[slotId]
      for extra in slot[].extraLayers:
        rootOrders[extra.level].add slot[].extraHandles[extra.level]

  for frame in frames:
    let entry = addr scene.viewEntries[frame.viewId]
    var escapedOrder: seq[RenderFragmentHandle]
    for slotId in entry[].slotOrder:
      let slot = addr entry[].slots[slotId]
      if slot[].position == rspAfterSubviews:
        childOrders[frame.viewId].add slot[].handle
      escapedOrder.add slot[].escapedHandle
    scene.tree.reorderChildFragments(
      entry[].placementCursor, [entry[].shellHandle, entry[].escapedTransformHandle]
    )
    scene.tree.reorderChildFragments(entry[].shellCursor, [entry[].contentHandle])
    scene.tree.reorderChildFragments(entry[].contentCursor, childOrders[frame.viewId])
    scene.tree.reorderChildFragments(entry[].escapedTransformCursor, escapedOrder)
  scene.rootFragments.setLen(0)
  for level in levels:
    scene.tree.reorderRootFragments(level, rootOrders[level])
    scene.rootFragments.add rootOrders[level]

proc mergeEntryResources(
    scene: RenderScene, frames: openArray[RenderViewFrame]
): RenderResourceManifest =
  result = initRenderResourceManifest()
  for frame in frames:
    let entry = addr scene.viewEntries[frame.viewId]
    for slotId in entry[].slotOrder:
      result.addResources(entry[].slots[slotId].resources)

proc detachSlot(scene: RenderScene, slot: ViewRenderSlotEntry) =
  for _, handle in slot.extraHandles:
    if scene.tree.isValid(handle):
      scene.tree.removeFragment(handle)
  if scene.tree.isValid(slot.handle):
    scene.tree.removeFragment(slot.handle)
  if scene.tree.isValid(slot.escapedHandle):
    scene.tree.removeFragment(slot.escapedHandle)

proc attachEmptySlot(
    scene: RenderScene, entry: var ViewRenderEntry, slotId: RenderSlotId
) =
  let slot = addr entry.slots[slotId]
  var contents = RenderList()
  slot[].handle = scene.attachChild(entry.contentCursor, contents)
  var escaped = RenderList()
  slot[].escapedHandle = scene.attachChild(entry.escapedTransformCursor, escaped)
  slot[].extraHandles = initTable[ZLevel, RenderFragmentHandle]()

proc frameSlotIds(frame: RenderViewFrame): seq[RenderSlotId] =
  result = newSeqOfCap[RenderSlotId](frame.slots.len)
  for slot in frame.slots:
    result.add slot.slotId

proc capturedSlotIds(frame: RenderViewFrame): seq[RenderSlotId] =
  for slot in frame.slots:
    if slot.captured:
      result.add slot.slotId

proc reconcile*(
    scene: RenderScene, frames: var seq[RenderViewFrame], baseLevel: ZLevel
): bool {.discardable.} =
  ## Reconciles one frame while retaining clean per-view drawing fragments.
  ##
  ## `frames` must be in depth-first view order, with parents before children.
  ## A captured entry atomically updates only its changed named slots. Placement-
  ## only entries update retained transforms. Clean entries only participate in
  ## ordering.
  if scene.isNil:
    raise newException(ValueError, "cannot update a nil render scene")
  frames.validateFrames()

  let placements = frames.nextPlacements()
  var
    topologyChanged = not scene.perViewMode or placements != scene.placements
    changed = topologyChanged
    levelChanged = false
    seen = initTable[RenderViewId, bool]()
    changedViews: seq[RenderViewId]
    capturedViews: seq[RenderViewId]
    addedSlots = initTable[RenderViewId, seq[RenderSlotId]]()
    removedSlots = initTable[RenderViewId, seq[RenderSlotId]]()

  for frame in frames.mitems:
    seen[frame.viewId] = true
    let existed = frame.viewId in scene.viewEntries and scene.perViewMode
    if not existed and not frame.captured:
      raise newException(ValueError, "a new render view must include a capture")
    if frame.captured and not frame.placementChanged:
      raise newException(ValueError, "a captured render view must include placement")
    if not existed:
      topologyChanged = true
    if existed and scene.viewEntries[frame.viewId].cacheKey.level != frame.cacheKey.level:
      levelChanged = true

    if not existed:
      scene.viewEntries[frame.viewId] =
        ViewRenderEntry(slots: initTable[RenderSlotId, ViewRenderSlotEntry]())
    let entry = addr scene.viewEntries[frame.viewId]
    if frame.captured:
      let nextSlotOrder = frame.frameSlotIds()
      if existed and entry[].slotOrder != nextSlotOrder:
        topologyChanged = true
      if existed:
        for slotId in entry[].slotOrder:
          if slotId notin nextSlotOrder:
            removedSlots.mgetOrPut(frame.viewId, @[]).add slotId
        for slot in frame.slots:
          if slot.slotId notin entry[].slots:
            if not slot.captured:
              raise newException(ValueError, "a new render slot must include a capture")
            addedSlots.mgetOrPut(frame.viewId, @[]).add slot.slotId
          else:
            let cachedSlot = addr entry[].slots[slot.slotId]
            if cachedSlot[].position != slot.position or
                slot.captured and
                not cachedSlot[].extraLayers.sameLayerShape(slot.extraLayers):
              topologyChanged = true
      else:
        for slot in frame.slots:
          if not slot.captured:
            raise newException(ValueError, "a new render view needs every slot capture")

      entry[].cacheKey = frame.cacheKey
      entry[].placement = move frame.placement
      entry[].shell = move frame.shell
      entry[].contentTransform = move frame.contentTransform
      entry[].escapedTransform = move frame.escapedTransform
      entry[].slotOrder = nextSlotOrder
      for slot in frame.slots.mitems:
        if slot.slotId notin entry[].slots:
          entry[].slots[slot.slotId] =
            ViewRenderSlotEntry(extraHandles: initTable[ZLevel, RenderFragmentHandle]())
        let cachedSlot = addr entry[].slots[slot.slotId]
        cachedSlot[].position = slot.position
        cachedSlot[].revision = slot.revision
        if slot.captured:
          cachedSlot[].contents = move slot.contents
          cachedSlot[].escapedContents = move slot.escapedContents
          cachedSlot[].extraLayers = move slot.extraLayers
          cachedSlot[].resources = move slot.resources
          cachedSlot[].usesVisibleRect = slot.usesVisibleRect
      entry[].captureGeneration.advance()
      capturedViews.add frame.viewId
      changedViews.add frame.viewId
      changed = true
    elif frame.placementChanged:
      entry[].refreshPlacementNodes(frame.cacheKey)
      changedViews.add frame.viewId
      changed = true
    elif entry[].cacheKey != frame.cacheKey:
      raise newException(ValueError, "a changed render view must include an update")

  var removed: seq[RenderViewId]
  for viewId in scene.viewEntries.keys:
    if viewId notin seen:
      removed.add viewId
  if removed.len > 0:
    changed = true
    topologyChanged = true

  let levels = scene.desiredLevels(frames, baseLevel)
  let rebuild = not scene.perViewMode or levelChanged or levels != scene.rootLevels
  if not changed and not rebuild:
    return false

  var nextGeneration = scene.generation
  nextGeneration.advance()

  for viewId in changedViews:
    scene.viewEntries[viewId].changeGeneration = nextGeneration
  for viewId in capturedViews:
    scene.viewEntries[viewId].captureChangeGeneration = nextGeneration
  for frame in frames:
    if frame.captured:
      for slot in frame.slots:
        if slot.captured:
          scene.viewEntries[frame.viewId].slots[slot.slotId].changeGeneration =
            nextGeneration
  if rebuild:
    scene.fullTransferGeneration = nextGeneration

  if rebuild:
    for viewId, slotIds in removedSlots:
      for slotId in slotIds:
        scene.viewEntries[viewId].slots.del(slotId)
    for viewId in removed:
      scene.viewEntries.del(viewId)
    scene.rebuildTree(frames, levels)
  else:
    for viewId, slotIds in removedSlots:
      for slotId in slotIds:
        scene.detachSlot(scene.viewEntries[viewId].slots[slotId])
        scene.viewEntries[viewId].slots.del(slotId)
    for viewId, slotIds in addedSlots:
      for slotId in slotIds:
        scene.attachEmptySlot(scene.viewEntries[viewId], slotId)

    if topologyChanged:
      var viewLevels = initTable[RenderViewId, ZLevel]()
      for frame in frames:
        viewLevels[frame.viewId] = frame.cacheKey.level
      for frame in frames:
        let entry = addr scene.viewEntries[frame.viewId]
        if not scene.tree.isValid(entry[].placementHandle):
          scene.attachViewEntry(entry[], frame.externalParent(viewLevels))
        else:
          scene.moveViewEntry(entry[], frame.externalParent(viewLevels))
          if frame.captured:
            scene.updateCapturedEntry(entry[], frame.capturedSlotIds())
          elif frame.placementChanged:
            scene.updatePlacementEntry(entry[])
    else:
      for frame in frames:
        if frame.captured:
          scene.updateCapturedEntry(
            scene.viewEntries[frame.viewId], frame.capturedSlotIds()
          )
        elif frame.placementChanged:
          scene.updatePlacementEntry(scene.viewEntries[frame.viewId])

    for viewId in removed:
      scene.detachEntry(scene.viewEntries[viewId])
      scene.viewEntries.del(viewId)

  if rebuild or topologyChanged:
    scene.reconcileOrders(frames, levels)
  let resources = scene.mergeEntryResources(frames)
  if not scene.liveResources.isNil:
    scene.retiredResources.add RetiredRenderResources(
      releaseGeneration: nextGeneration, manifest: scene.liveResources
    )
  scene.liveResources = resources
  scene.placements = placements
  scene.rootLevels = levels
  scene.baseLevel = baseLevel
  scene.generation = nextGeneration
  scene.perViewMode = true
  true

proc copyLayerContributions(
    layers: openArray[RenderLayerContribution]
): seq[RenderLayerContribution] =
  result = newSeqOfCap[RenderLayerContribution](layers.len)
  for layer in layers:
    result.add RenderLayerContribution(
      level: layer.level, contents: layer.contents.isolateRenderList()
    )

proc transferFrame(
    entry: ViewRenderEntry,
    placement: ViewPlacement,
    placementChanged: bool,
    acknowledgedGeneration: uint64,
    full: bool,
): RenderViewFrame =
  let captured = full or entry.captureChangeGeneration > acknowledgedGeneration
  result = RenderViewFrame(
    viewId: placement.viewId,
    parentViewId: placement.parentViewId,
    cacheKey: entry.cacheKey,
    placementChanged: placementChanged,
    captured: captured,
  )
  if captured:
    result.placement = entry.placement.isolateFig()
    result.shell = entry.shell.isolateFig()
    result.contentTransform = entry.contentTransform.isolateFig()
    result.escapedTransform = entry.escapedTransform.isolateFig()
    result.slots = newSeqOfCap[RenderViewSlotFrame](entry.slotOrder.len)
    for slotId in entry.slotOrder:
      let slot = entry.slots[slotId]
      let slotCaptured = full or slot.changeGeneration > acknowledgedGeneration
      var frameSlot = RenderViewSlotFrame(
        slotId: slotId,
        position: slot.position,
        revision: slot.revision,
        captured: slotCaptured,
        usesVisibleRect: slot.usesVisibleRect,
      )
      if slotCaptured:
        frameSlot.contents = slot.contents.isolateRenderList()
        frameSlot.escapedContents = slot.escapedContents.isolateRenderList()
        frameSlot.extraLayers = slot.extraLayers.copyLayerContributions()
      result.slots.add move frameSlot

proc newRenderSceneUpdate*(
    scene: RenderScene,
    acknowledgedSceneIdentity: uint64,
    acknowledgedGeneration: uint64,
    forceFull = false,
): RenderSceneUpdate =
  ## Builds a self-contained cumulative update from an acknowledged baseline.
  ##
  ## The update owns independent node sequences. It can therefore be moved to a
  ## renderer thread without sharing the mutable application scene or its
  ## FigDraw fragment handles.
  if scene.isNil:
    raise newException(ValueError, "cannot transfer a nil render scene")
  if not scene.perViewMode:
    raise newException(ValueError, "only reconciled per-view scenes can be transferred")

  let full =
    forceFull or acknowledgedSceneIdentity != scene.identity or
    acknowledgedGeneration == 0 or acknowledgedGeneration > scene.generation or
    scene.fullTransferGeneration > acknowledgedGeneration
  result.sceneIdentity = scene.identity
  result.baseGeneration = if full: 0 else: acknowledgedGeneration
  result.generation = scene.generation
  result.full = full
  result.baseLevel = scene.baseLevel
  result.frames = newSeqOfCap[RenderViewFrame](scene.placements.len)
  for placement in scene.placements:
    let entry = addr scene.viewEntries[placement.viewId]
    result.frames.add entry[].transferFrame(
      placement,
      full or entry[].changeGeneration > acknowledgedGeneration,
      acknowledgedGeneration,
      full,
    )
  result.resources = scene.liveResources.snapshot()

func sceneIdentity*(scene: RenderScene): uint64 =
  if scene.isNil: 0 else: scene.identity

func sceneIdentity*(update: RenderSceneUpdate): uint64 =
  update.sceneIdentity

func baseGeneration*(update: RenderSceneUpdate): uint64 =
  update.baseGeneration

func generation*(update: RenderSceneUpdate): uint64 =
  update.generation

func fullSnapshot*(update: RenderSceneUpdate): bool =
  update.full

func capturedViewCount*(update: RenderSceneUpdate): Natural =
  for frame in update.frames:
    if frame.captured:
      inc result

func capturedRenderSlotCount*(update: RenderSceneUpdate): Natural =
  ## Counts independently transferred view slots in this update.
  for frame in update.frames:
    for slot in frame.slots:
      if slot.captured:
        inc result

func viewCount*(update: RenderSceneUpdate): Natural =
  update.frames.len.Natural

func canApply*(
    update: RenderSceneUpdate, currentSceneIdentity, currentGeneration: uint64
): bool =
  ## Checks ordering without consulting renderer-local fragment generations.
  ##
  ## Cumulative updates can apply to a renderer newer than their baseline, but
  ## never to an older one. Full updates establish a new ordering epoch.
  if update.sceneIdentity == 0 or update.generation == 0:
    return false
  if update.full:
    return
      update.sceneIdentity != currentSceneIdentity or
      update.generation >= currentGeneration
  update.sceneIdentity == currentSceneIdentity and
    update.baseGeneration <= currentGeneration and update.generation >= currentGeneration

proc apply*(scene: RenderScene, update: var RenderSceneUpdate) =
  ## Applies an accepted update to renderer-owned scene storage.
  if scene.isNil:
    raise newException(ValueError, "cannot update a nil renderer scene")
  if not update.canApply(scene.identity, scene.generation):
    raise
      newException(ValueError, "render-scene update is stale or has a generation gap")
  if update.full:
    for frame in update.frames:
      if not frame.captured:
        raise
          newException(ValueError, "a full render-scene update must capture every view")
      for slot in frame.slots:
        if not slot.captured:
          raise newException(
            ValueError, "a full render-scene update must capture every view slot"
          )
  discard scene.reconcile(update.frames, update.baseLevel)
  scene.identity = update.sceneIdentity
  scene.generation = update.generation

proc takeResources*(update: var RenderSceneUpdate): RenderResourceSnapshot =
  ## Moves the update's thread-safe live-resource identities to its receiver.
  result = move update.resources

proc materialize*(scene: RenderScene): Renders =
  ## Returns an independent monolithic snapshot for diagnostics and transfer.
  if scene.isNil:
    raise newException(ValueError, "cannot materialize a nil render scene")
  scene.tree.materialize()

proc renderRoot*(scene: RenderScene, context: BackendContext) =
  ## Sends the retained fragment graph directly through FigDraw's renderer traversal.
  if scene.isNil:
    raise newException(ValueError, "cannot render a nil render scene")
  context.renderRoot(scene.tree)

proc countTraversalNodes(tree: RenderFragments, cursor: RenderCursor): Natural =
  result = 1
  for child in tree.children(cursor):
    result += tree.countTraversalNodes(child)

proc traversalNodeCount*(scene: RenderScene): Natural =
  ## Traverses retained fragment edges without materializing a render tree.
  if scene.isNil:
    return
  for level in scene.tree.levels():
    for root in scene.tree.roots(level):
      result += scene.tree.countTraversalNodes(root)

proc renderFrame*[BackendState](
    scene: RenderScene,
    renderer: FigRenderer[BackendState],
    frameSize: Vec2,
    clearMain = true,
    clearFrameColor = color(1.0, 1.0, 1.0, 1.0),
) =
  ## Renders the retained fragment graph without creating a monolithic snapshot.
  if scene.isNil:
    raise newException(ValueError, "cannot render a nil render scene")
  renderer.renderFrame(
    scene.tree, frameSize, clearMain = clearMain, clearColor = clearFrameColor
  )

proc frameGeneration*(scene: RenderScene): uint64 =
  if not scene.isNil:
    result = scene.generation

proc rootFragmentIds*(scene: RenderScene): seq[uint64] =
  ## Returns tree-local identities for equivalence and operation-count diagnostics.
  if scene.isNil:
    return
  result = newSeqOfCap[uint64](scene.rootFragments.len)
  for handle in scene.rootFragments:
    result.add handle.fragmentId()

proc viewCaptureGeneration*(scene: RenderScene, id: RenderViewId): uint64 =
  ## Returns how many contributions this scene has captured for one view identity.
  if not scene.isNil and id in scene.viewEntries:
    result = scene.viewEntries[id].captureGeneration

proc viewFragmentIds*(scene: RenderScene, id: RenderViewId): seq[uint64] =
  ## Returns stable transform and ordered slot IDs for diagnostics.
  if scene.isNil or id notin scene.viewEntries:
    return
  let entry = addr scene.viewEntries[id]
  for handle in [
    entry[].placementHandle,
    entry[].shellHandle,
    entry[].contentHandle,
    entry[].escapedTransformHandle,
  ]:
    if scene.tree.isValid(handle):
      result.add handle.fragmentId()
  for slotId in entry[].slotOrder:
    for handle in [entry[].slots[slotId].handle, entry[].slots[slotId].escapedHandle]:
      if scene.tree.isValid(handle):
        result.add handle.fragmentId()

proc viewRenderSlotFragmentId*(
    scene: RenderScene, id: RenderViewId, slotId: RenderSlotId
): uint64 =
  ## Returns the stable normal-content fragment identity for one view slot.
  if scene.isNil or id notin scene.viewEntries or
      slotId notin scene.viewEntries[id].slots:
    return
  let handle = scene.viewEntries[id].slots[slotId].handle
  if scene.tree.isValid(handle):
    result = handle.fragmentId()

proc viewRenderSlotChangeGeneration*(
    scene: RenderScene, id: RenderViewId, slotId: RenderSlotId
): uint64 =
  ## Returns the scene generation that most recently replaced one slot.
  if not scene.isNil and id in scene.viewEntries and
      slotId in scene.viewEntries[id].slots:
    result = scene.viewEntries[id].slots[slotId].changeGeneration

proc viewEntryCount*(scene: RenderScene): Natural =
  if not scene.isNil:
    result = scene.viewEntries.len.Natural

proc containsView*(scene: RenderScene, id: RenderViewId): bool =
  not scene.isNil and id in scene.viewEntries

proc renderResources*(scene: RenderScene): RenderResourceManifest =
  if not scene.isNil:
    result = scene.liveResources

proc retiredResourceCount*(scene: RenderScene): Natural =
  if not scene.isNil:
    result = scene.retiredResources.len.Natural

proc acknowledgeRenderGeneration*(scene: RenderScene, generation: uint64) =
  ## Releases manifests that cannot be referenced after `generation`.
  if scene.isNil:
    return
  var idx = scene.retiredResources.len
  while idx > 0:
    dec idx
    if scene.retiredResources[idx].releaseGeneration <= generation:
      scene.retiredResources.delete(idx)
