## Retained, per-view render scenes built on FigDraw fragment attachments.
##
## Each visible view owns a stable shell fragment, a replaceable self-drawing
## fragment, an escaped-sibling fragment, and zero or more extra-layer root
## fragments. Child view shells attach beneath their parent's shell, so replacing
## one view's self drawing cannot detach descendant or sibling identities.

import std/[hashes, tables]

import figdraw

import ./renderresources
import ../foundation/types

type
  RenderViewId* = distinct uint64
    ## Stable application-thread identity for a NimKit view.

  RenderViewCacheKey* = object
    ## Inputs that can change one view's captured drawing without changing its ID.
    displayRevision*: uint64
    appearanceGeneration*: uint64
    frame*: Rect
    bounds*: Rect
    visibleRect*: Rect
    level*: ZLevel
    isRoot*: bool

  RenderLayerContribution* = object
    ## Root drawing emitted explicitly onto a layer by one view.
    level*: ZLevel
    contents*: RenderList

  RenderViewFrame* = object
    ## One visible view's placement and optional freshly captured contribution.
    viewId*: RenderViewId
    parentViewId*: RenderViewId
    cacheKey*: RenderViewCacheKey
    captured*: bool
    shell*: Fig
    selfContents*: RenderList
    escapedContents*: RenderList
    extraLayers*: seq[RenderLayerContribution]
    resources*: RenderResourceManifest

  ViewPlacement = object
    viewId: RenderViewId
    parentViewId: RenderViewId
    level: ZLevel

  ViewRenderEntry = object
    cacheKey: RenderViewCacheKey
    shell: Fig
    selfContents: RenderList
    escapedContents: RenderList
    extraLayers: seq[RenderLayerContribution]
    resources: RenderResourceManifest
    shellHandle: RenderFragmentHandle
    shellCursor: RenderCursor
    selfHandle: RenderFragmentHandle
    escapedHandle: RenderFragmentHandle
    extraHandles: Table[ZLevel, RenderFragmentHandle]
    externalParent: RenderViewId
    captureGeneration: uint64
    changeGeneration: uint64

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
    ## contributions changed after `baseGeneration` carry node payloads. A full
    ## update carries every payload and acts as an ordering barrier.
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

proc shellRenderList(node: Fig): RenderList =
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

proc needsViewCapture*(
    scene: RenderScene, viewId: RenderViewId, cacheKey: RenderViewCacheKey
): bool =
  ## Reports whether this scene lacks a current contribution for `viewId`.
  if scene.isNil or not scene.perViewMode or viewId notin scene.viewEntries:
    return true
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
    for extra in scene.viewEntries[frame.viewId].extraLayers:
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
  var shellList = entry.shell.shellRenderList()
  if parent.uint64 == 0:
    entry.shellHandle = scene.attachRoot(entry.cacheKey.level, shellList)
  else:
    entry.shellHandle =
      scene.attachChild(scene.viewEntries[parent].shellCursor, shellList)

  let roots = scene.tree.fragmentRoots(entry.shellHandle)
  if roots.len != 1:
    raise
      newException(ValueError, "a view shell fragment must contain exactly one root")
  entry.shellCursor = roots[0]
  entry.selfHandle = scene.attachChild(entry.shellCursor, entry.selfContents)

  if parent.uint64 == 0:
    entry.escapedHandle = scene.attachRoot(entry.cacheKey.level, entry.escapedContents)
  else:
    entry.escapedHandle =
      scene.attachChild(scene.viewEntries[parent].shellCursor, entry.escapedContents)

  entry.extraHandles = initTable[ZLevel, RenderFragmentHandle]()
  for extra in entry.extraLayers.mitems:
    entry.extraHandles[extra.level] = scene.attachRoot(extra.level, extra.contents)
  entry.externalParent = parent

proc detachEntry(scene: RenderScene, entry: ViewRenderEntry) =
  for _, handle in entry.extraHandles:
    if scene.tree.isValid(handle):
      scene.tree.removeFragment(handle)
  if scene.tree.isValid(entry.escapedHandle):
    scene.tree.removeFragment(entry.escapedHandle)
  if scene.tree.isValid(entry.shellHandle):
    scene.tree.removeFragment(entry.shellHandle)

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
    var entry = scene.viewEntries[frame.viewId]
    scene.attachViewEntry(entry, frame.externalParent(viewLevels))
    scene.viewEntries[frame.viewId] = entry

proc updateCapturedEntry(scene: RenderScene, entry: var ViewRenderEntry) =
  scene.tree.updateNode(entry.shellCursor, entry.shell)
  if scene.replicaMode:
    entry.selfHandle =
      scene.tree.replaceFragment(entry.selfHandle, move entry.selfContents)
    entry.escapedHandle =
      scene.tree.replaceFragment(entry.escapedHandle, move entry.escapedContents)
  else:
    entry.selfHandle =
      scene.tree.replaceFragment(entry.selfHandle, entry.selfContents.copyRenderList())
    entry.escapedHandle = scene.tree.replaceFragment(
      entry.escapedHandle, entry.escapedContents.copyRenderList()
    )

  var retained = initTable[ZLevel, bool]()
  for extra in entry.extraLayers.mitems:
    retained[extra.level] = true
    if extra.level in entry.extraHandles:
      if scene.replicaMode:
        entry.extraHandles[extra.level] = scene.tree.replaceFragment(
          entry.extraHandles[extra.level], move extra.contents
        )
      else:
        entry.extraHandles[extra.level] = scene.tree.replaceFragment(
          entry.extraHandles[extra.level], extra.contents.copyRenderList()
        )
    else:
      entry.extraHandles[extra.level] = scene.attachRoot(extra.level, extra.contents)

  var removed: seq[ZLevel]
  for level in entry.extraHandles.keys:
    if level notin retained:
      removed.add level
  for level in removed:
    let handle = entry.extraHandles[level]
    if scene.tree.isValid(handle):
      scene.tree.removeFragment(handle)
    entry.extraHandles.del(level)

proc moveViewEntry(
    scene: RenderScene, entry: var ViewRenderEntry, parent: RenderViewId
) =
  if entry.externalParent == parent:
    return
  if parent.uint64 == 0:
    entry.shellHandle =
      scene.tree.moveFragmentToRoot(entry.shellHandle, entry.cacheKey.level, 0)
    entry.escapedHandle =
      scene.tree.moveFragmentToRoot(entry.escapedHandle, entry.cacheKey.level, 0)
  else:
    let parentCursor = scene.viewEntries[parent].shellCursor
    entry.shellHandle = scene.tree.moveFragment(entry.shellHandle, parentCursor, 0)
    entry.escapedHandle = scene.tree.moveFragment(entry.escapedHandle, parentCursor, 0)
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
    childOrders[frame.viewId] = @[scene.viewEntries[frame.viewId].selfHandle]

  for frame in frames:
    let
      entry = scene.viewEntries[frame.viewId]
      parent = frame.externalParent(viewLevels)
    if parent.uint64 == 0:
      rootOrders[frame.cacheKey.level].add entry.shellHandle
      rootOrders[frame.cacheKey.level].add entry.escapedHandle
    else:
      childOrders[parent].add entry.shellHandle
      childOrders[parent].add entry.escapedHandle
    for extra in entry.extraLayers:
      rootOrders[extra.level].add entry.extraHandles[extra.level]

  for frame in frames:
    let entry = scene.viewEntries[frame.viewId]
    scene.tree.reorderChildFragments(entry.shellCursor, childOrders[frame.viewId])
  scene.rootFragments.setLen(0)
  for level in levels:
    scene.tree.reorderRootFragments(level, rootOrders[level])
    scene.rootFragments.add rootOrders[level]

proc mergeEntryResources(
    scene: RenderScene, frames: openArray[RenderViewFrame]
): RenderResourceManifest =
  result = initRenderResourceManifest()
  for frame in frames:
    result.addResources(scene.viewEntries[frame.viewId].resources)

proc reconcile*(
    scene: RenderScene, frames: var seq[RenderViewFrame], baseLevel: ZLevel
): bool {.discardable.} =
  ## Reconciles one frame while retaining clean per-view drawing fragments.
  ##
  ## `frames` must be in depth-first view order, with parents before children.
  ## A captured entry atomically updates its shell, self, escaped, and extra-layer
  ## outputs. Clean entries only participate in placement and ordering.
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

  for frame in frames.mitems:
    seen[frame.viewId] = true
    let existed = frame.viewId in scene.viewEntries and scene.perViewMode
    if not existed and not frame.captured:
      raise newException(ValueError, "a new render view must include a capture")
    if not existed:
      topologyChanged = true
    if existed and scene.viewEntries[frame.viewId].cacheKey.level != frame.cacheKey.level:
      levelChanged = true

    var entry =
      if existed:
        scene.viewEntries[frame.viewId]
      else:
        ViewRenderEntry(extraHandles: initTable[ZLevel, RenderFragmentHandle]())
    if frame.captured:
      if existed and not entry.extraLayers.sameLayerShape(frame.extraLayers):
        topologyChanged = true
      entry.cacheKey = frame.cacheKey
      entry.shell = move frame.shell
      entry.selfContents = move frame.selfContents
      entry.escapedContents = move frame.escapedContents
      entry.extraLayers = move frame.extraLayers
      entry.resources = move frame.resources
      entry.captureGeneration.advance()
      changedViews.add frame.viewId
      changed = true
    elif entry.cacheKey != frame.cacheKey:
      raise newException(ValueError, "a changed render view must include a capture")
    if frame.captured:
      scene.viewEntries[frame.viewId] = entry

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
  if rebuild:
    scene.fullTransferGeneration = nextGeneration

  if rebuild:
    for viewId in removed:
      scene.viewEntries.del(viewId)
    scene.rebuildTree(frames, levels)
  else:
    var viewLevels = initTable[RenderViewId, ZLevel]()
    for frame in frames:
      viewLevels[frame.viewId] = frame.cacheKey.level

    if topologyChanged:
      for frame in frames:
        var entry = scene.viewEntries[frame.viewId]
        if not scene.tree.isValid(entry.shellHandle):
          scene.attachViewEntry(entry, frame.externalParent(viewLevels))
        else:
          scene.moveViewEntry(entry, frame.externalParent(viewLevels))
          if frame.captured:
            scene.updateCapturedEntry(entry)
        scene.viewEntries[frame.viewId] = entry
    else:
      for frame in frames:
        if frame.captured:
          var entry = scene.viewEntries[frame.viewId]
          scene.updateCapturedEntry(entry)
          scene.viewEntries[frame.viewId] = entry

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
    entry: ViewRenderEntry, placement: ViewPlacement, captured: bool
): RenderViewFrame =
  result = RenderViewFrame(
    viewId: placement.viewId,
    parentViewId: placement.parentViewId,
    cacheKey: entry.cacheKey,
    captured: captured,
  )
  if captured:
    result.shell = entry.shell.isolateFig()
    result.selfContents = entry.selfContents.isolateRenderList()
    result.escapedContents = entry.escapedContents.isolateRenderList()
    result.extraLayers = entry.extraLayers.copyLayerContributions()

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
    let entry = scene.viewEntries[placement.viewId]
    result.frames.add entry.transferFrame(
      placement, full or entry.changeGeneration > acknowledgedGeneration
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
  ## Returns the stable shell, self, and escaped fragment IDs for diagnostics.
  if scene.isNil or id notin scene.viewEntries:
    return
  let entry = scene.viewEntries[id]
  for handle in [entry.shellHandle, entry.selfHandle, entry.escapedHandle]:
    if scene.tree.isValid(handle):
      result.add handle.fragmentId()

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
