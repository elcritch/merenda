import std/[hashes, tables]

import figdraw

import ./renderresources

type
  RenderViewId* = distinct uint64
    ## Stable application-thread identity for a NimKit view.

  ViewRenderEntry = object
    lastSeenGeneration: uint64

  RetiredRenderResources = object
    releaseGeneration: uint64
    manifest: RenderResourceManifest

  RenderScene* = ref object
    ## Fragment-backed render state owned by one window/content render root.
    tree: RenderFragments
    rootLevels: seq[ZLevel]
    rootFragments: seq[RenderFragmentHandle]
    viewEntries: Table[RenderViewId, ViewRenderEntry]
    generation: uint64
    liveResources: RenderResourceManifest
    retiredResources: seq[RetiredRenderResources]

var renderViewIdCounter: uint64

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

proc newRenderScene*(): RenderScene =
  RenderScene(
    tree: newRenderFragments(), viewEntries: initTable[RenderViewId, ViewRenderEntry]()
  )

proc copyRenderList(list: RenderList): RenderList =
  result.nodes = newSeqOfCap[Fig](list.nodes.len)
  for node in list.nodes:
    result.nodes.add node
  result.rootIds = newSeqOfCap[FigIdx](list.rootIds.len)
  for root in list.rootIds:
    result.rootIds.add root

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
  ## This first implementation uses one persistent root fragment per layer;
  ## later reconciliation will subdivide those roots into per-view entries.
  if scene.isNil:
    raise newException(ValueError, "cannot update a nil render scene")

  let built = renders.buildFragmentTree()
  var nextGeneration = scene.generation
  nextGeneration.advance()

  var nextEntries = initTable[RenderViewId, ViewRenderEntry]()
  for id in seenViews:
    if id.uint64 == 0:
      raise newException(ValueError, "render scene received an invalid view identity")
    nextEntries[id] = ViewRenderEntry(lastSeenGeneration: nextGeneration)

  if not scene.liveResources.isNil and scene.liveResources != resources:
    scene.retiredResources.add RetiredRenderResources(
      releaseGeneration: nextGeneration, manifest: scene.liveResources
    )

  if scene.rootLevels == built.levels and scene.rootFragments.len == built.roots.len:
    var nextRoots = newSeqOfCap[RenderFragmentHandle](scene.rootFragments.len)
    for idx, level in built.levels:
      nextRoots.add scene.tree.replaceFragment(
        scene.rootFragments[idx], renders.layers[level].copyRenderList()
      )
    scene.rootFragments = move nextRoots
  else:
    scene.tree = built.tree
    scene.rootLevels = built.levels
    scene.rootFragments = built.roots
  scene.viewEntries = move nextEntries
  scene.generation = nextGeneration
  scene.liveResources = resources

proc materialize*(scene: RenderScene): Renders =
  ## Returns an independent monolithic snapshot for diagnostics and transfer.
  if scene.isNil:
    raise newException(ValueError, "cannot materialize a nil render scene")
  scene.tree.materialize()

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
