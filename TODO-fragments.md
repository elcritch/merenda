# Incremental Render Fragments

## Implementation status

Implementation began with [FigDraw PR #72](https://github.com/elcritch/figdraw/pull/72)
and the initial NimKit scene foundation on `feature/incremental-render-fragments`.
Checked items below are covered by those branches; unchecked items remain follow-up
work, including per-view contribution caching and renderer-thread deltas.

## Recommendation

Modify FigDraw's fragment model first, then use fragments as NimKit's per-view
render cache.

- Fragments should be attachable as logical children of existing nodes, including
  nodes inside other fragments, and as roots of a layer.
- A fragment attachment must remain present when its contents have zero, one, or
  many roots.
- NimKit should cache vector/render-tree fragments at this stage. It should not
  add a separate rasterized-view or texture cache yet.
- Enable fragment-native rendering first on the direct static renderer.
- Preserve monolithic `Renders` through a flattening/materialization API for
  compatibility, diagnostics, and the initial renderer-thread implementation.
- Do not share a mutable fragment graph between the application and renderer
  threads.
- Dynlib integration is outside the scope of this work.

Fragments initially optimize render-tree construction: clean views avoid
running `draw`, laying out text, and rebuilding Fig nodes. They do not by
themselves reduce the number of GPU draw operations in a frame.

## FigDraw prerequisites

### Persistent fragment slots

The current `insertChildren` API can insert a fragment beneath a base node or a
node in another fragment. Keep that capability, but change its representation.

At present, a parent contains one `RenderChild` entry for every current root of
the inserted fragment. Replacing a fragment with an empty `RenderList` removes
all of those entries and therefore loses the fragment's insertion position.
Changing the number of roots also requires finding and rewriting references
throughout the graph.

Represent an attachment as one persistent fragment edge instead:

```text
parent children = [node A, fragment F, node B]
fragment F roots = [] | [root X] | [root X, root Y]
```

Traversal expands the roots of `F` in place. This preserves identity and sibling
order across empty and multi-root replacements and avoids graph-wide reference
rewrites.

- [x] Store one fragment edge per attachment rather than one edge per root.
- [x] Add equivalent persistent slots to each layer's root sequence.
- [x] Allow fragment edges beneath base nodes and nodes inside fragments.
- [ ] Detect attachment cycles.
- [x] Give each mutable fragment exactly one attachment. Reusing content in more
      than one location should require a distinct fragment instance.

### Explicit attachment APIs

The current names are easy to confuse: `insertChildren` creates a replaceable
fragment, while `addChildren` physically appends nodes to a `RenderList`. Make
the distinction explicit in the API.

The intended surface is approximately:

```nim
proc attachChildFragment*(
    tree: RenderFragments,
    parent: RenderNodeCursor,
    childPos: Natural,
    contents: sink RenderList,
): RenderFragmentHandle

proc attachRootFragment*(
    tree: RenderFragments,
    level: ZLevel,
    rootPos: Natural,
    contents: sink RenderList,
): RenderFragmentHandle

proc replaceFragment*(
    tree: RenderFragments,
    handle: RenderFragmentHandle,
    contents: sink RenderList,
): RenderFragmentHandle

proc moveFragment*(
    tree: RenderFragments,
    handle: RenderFragmentHandle,
    destination: RenderFragmentDestination,
    position: Natural,
): RenderFragmentHandle

proc removeFragment*(
    tree: RenderFragments,
    handle: RenderFragmentHandle,
)
```

- [x] Use explicit `attachChildFragment` and `attachRootFragment` naming.
- [x] Keep physical node/list insertion under separate, clearly named APIs.
- [ ] Support atomic movement/reordering without a transient detached state.
- [x] Return a refreshed handle from every operation that advances its version.

### Tree-owned, generation-stamped handles

`RenderCursor` currently combines a node location with an implicit fragment
reference. It does not identify the owning tree or the version of that tree or
fragment. Separate the concepts:

- `RenderFragmentHandle` identifies a persistent replacement slot.
- `RenderNodeCursor` identifies a node in a particular fragment/base version.

Both types should be opaque value types. A fragment handle should internally
carry the equivalent of:

```text
treeId
treeEpoch
layerEpoch
fragmentId
fragmentVersion
```

The `RenderFragments` tree should own a registry of fragment records, and graph
edges should reference registry IDs rather than externally mutable fragment
objects.

Generation scopes should remain independent:

- `clear` advances the tree epoch.
- Replacing a whole layer advances that layer's epoch and detaches its fragments.
- Replacing one fragment advances only that fragment's version.
- Removing a fragment marks it detached and invalidates its handle.
- Renderer target and atlas generations belong to renderer messages, not the UI
  fragment tree.

Do not use a single global version for ordinary fragment replacements; changing
one view must not invalidate every other view's handle.

- [x] Reject handles from another tree.
- [x] Reject stale tree, layer, and fragment generations.
- [x] Reject detached handles.
- [x] Reject node cursors from an older fragment version.
- [x] Return a structured rejection status for expected stale-message handling.
- [x] Do not rely on `assert` for public validation, because danger builds remove
      assertions.

### Controlled topology mutation

Raw access to `RenderList.nodes`, `rootIds`, `Renders.layers`, mutable fragment
layers, or mutable nodes can leave fragment traversal metadata stale.

- [x] Do not return `var RenderList` from a fragment tree.
- [x] Expose node reads as immutable values or lent read-only references.
- [x] Add a controlled `updateNode` operation for changing visual properties.
- [x] Preserve or reject changes to topology fields such as `parent`,
      `childCount`, and `zlevel` in `updateNode`.
- [x] Copy an existing `Renders` when wrapping it unless exclusive ownership can
      genuinely be enforced.
- [ ] Add debug validation for roots, parents, child ordering, attachment state,
      and cycles.

A controlled node update lets NimKit retain a stable view shell while changing
its frame, background, shadow, or clipping properties without detaching cached
child fragments.

### Monolithic materialization

Add a compatibility operation:

```nim
proc materialize*(tree: RenderFragments): Renders
```

It should produce a fresh monolithic tree by traversing logical fragment edges,
then recompute physical indexes, parents, roots, and child counts. It must
preserve exact layer, root, sibling, clipping, and transform order.

- [x] Make materialization deterministic.
- [x] Keep the returned tree independent of subsequent fragment mutations.
- [x] Use materialization for diagnostics, differential tests, public
      `buildRenders`, and initial threaded rendering.

## NimKit retained render scene

### Scene ownership

Introduce a `RenderScene` owned by a window/content render root. It should own:

- The FigDraw `RenderFragments` tree.
- A registry of cached view contributions.
- Frame and resource generations.
- Retired resource manifests awaiting safe release.

Give each `View` a stable monotonic `RenderViewId`. Store fragment handles in the
scene's `ViewRenderEntry`, not directly on the view: handles belong to one
fragment tree, while a view can move between windows or be rendered by a
diagnostic scene.

- [x] Assign stable view IDs without retaining removed views.
- [x] Mark entries encountered during each scene reconciliation.
- [x] Detach and sweep entries not encountered in the completed traversal.
- [ ] Reuse a view ID in a different scene by creating scene-local fragments.

### Composite view contribution

A view cannot be represented safely as one replaceable fragment. Current drawing
can produce normal children, escaped siblings, and roots on additional layers.
Use a composite entry:

```text
view slot
└── stable shell node              background, shadow, clipping
    ├── replaceable self fragment
    ├── child view slot
    ├── child view slot
    └── ...

escaped sibling fragment           exterior focus ring or chrome
layer-root fragments               popup, focus, tooltip, future overlays
```

The stable shell remains the structural and clipping parent. Its Fig can be
updated through the controlled node API. Rebuilding a view's own drawing replaces
the self fragment without disturbing its child-view slots.

Preserve these existing semantics:

- Normal view content and same-layer descendants are children of the shell and
  inherit its clipping and transform state.
- Exterior focus rings and similar content using `renderViewParent` remain
  siblings following the view slot, outside the view's own clip.
- A view whose effective draw level differs from its parent is a layer root.
- Popup, focus-ring, tooltip, and future accessibility-overlay roots retain
  depth-first view traversal order within their layers.
- Dynamic layer appearance and disappearance must not leave stale `OrderedTable`
  insertion order. Reconcile layer order explicitly each frame.

### DrawContext capture

`DrawContext` currently writes into one monolithic `Renders` and represents its
normal and escaped parents as `FigIdx`. Refactor the internal drawing target so a
single view draw can be captured into separate outputs:

- Normal content beneath the view shell.
- Escaped sibling content beneath the shell's parent.
- Root content grouped by explicit `ZLevel`.

Temporary internal anchor nodes are an acceptable first implementation if they
are removed while finalizing each captured `RenderList`. Existing public drawing
helpers should continue to return usable local `FigIdx` values during the draw.

- [ ] Build or reuse the shell during scene reconciliation.
- [ ] Run `view.draw` only when its local contribution is dirty or its render
      context changed.
- [ ] Replace each affected output fragment atomically after a successful draw.
- [ ] Reconcile child, sibling, root, and layer slots independently of redrawing
      clean view content.

### Display invalidation

Current descendant invalidation propagates `xNeedsDisplay` through every
ancestor. That would cause fragment caching to redraw the entire ancestor chain.
Separate:

- A view's local drawing revision.
- Aggregate descendant-dirty state.
- Damage rectangles used to schedule a frame.
- Structural and inherited render-context revisions.

Replace recursive blanket dirty-flag clearing with revision acknowledgement:
capture the revision before drawing and mark only that revision as rendered. An
invalidation raised during layout or drawing must remain pending.

- [ ] Make local invalidation advance only the target view's drawing revision.
- [ ] Propagate damage/descendant state without advancing ancestor drawing
      revisions.
- [ ] Include effective appearance, absolute origin, visible rectangle, draw
      level, and relevant geometry in the view cache key.
- [ ] Invalidate/reconcile descendants when an ancestor changes an inherited
      render context.

Keep absolute coordinates for the first implementation. Local coordinates and
view transforms may later reduce rebuilds when ancestors move, but combining that
change with initial fragment adoption would make equivalence substantially harder
to establish.

## Resource manifests

Each cached view contribution should retain the font and image resources used to
build it. At the frame boundary, create a fresh merged manifest from all live,
attached contributions rather than maintaining incremental resource reference
counts initially.

- [x] Add manifest merge support.
- [x] Associate fragment/resource versions with the scene frame generation.
- [ ] Exclude manifests belonging only to removed or replaced fragments from the
      new live merge.
- [x] Retain replaced manifests until the frame that could reference them has
      completed or been acknowledged.
- [ ] Replay the current merged live manifest after atlas recovery.
- [ ] Keep atlas generation separate from UI fragment-handle generations.

For direct synchronous rendering, old resources can be released after the frame
boundary. For threaded rendering, use the existing render-ID acknowledgement and
resource-lease mechanism.

## Renderer-thread boundary

Do not move a `RenderFragments` graph to the renderer thread while the UI scene
retains handles into it. That would alias mutable fragment objects and node
storage across threads.

Initial behavior:

- Direct static rendering consumes the scene's `RenderFragments` synchronously.
- Public/diagnostic `buildRenders` materializes a fresh monolithic value.
- The dedicated renderer continues receiving moved monolithic snapshots.
- The UI retains and incrementally updates its own scene after submission.

This path captures the main CPU benefit while retaining the existing safe thread
ownership boundary.

A later threaded fragment protocol should make the renderer own a separate graph
and accept move-only immutable replacement batches stamped with:

```text
hostId
targetGeneration
scene/tree epoch
layer epoch
fragmentId and version
frame/resource generation
```

- [ ] Bound and coalesce queued replacements by fragment and generation.
- [ ] Treat clear, layer replacement, target replacement, and full snapshots as
      ordering barriers.
- [ ] Reject obsolete target, scene, layer, atlas, and fragment generations.
- [ ] Acknowledge the applied frame/update generation before releasing payloads
      and resources.
- [ ] Send a full current snapshot after target replacement or when a delta chain
      cannot be applied safely.

## Tests

### FigDraw safety and structure

- [x] Reject a fragment handle used with a foreign tree.
- [x] Reject handles retained across `clear` and layer replacement.
- [x] Reject an older handle after a successful replacement.
- [x] Reject detached and removed fragment handles.
- [x] Replace a fragment with zero roots and later restore one or many roots at
      the same position.
- [x] Cover fragments beneath base nodes and beneath nodes in other fragments.
- [ ] Cover root fragments, multiple layers, physical node insertions, movement,
      removal, and reordering.
- [x] Ensure public APIs cannot make traversal metadata stale.

### NimKit equivalence

Build scenes through both the legacy monolithic path and the fragment path, then
compare a canonical traversal or renderer-operation stream rather than physical
Fig indexes.

- [x] Nested view updates and sibling ordering.
- [x] Same-layer versus cross-layer descendants.
- [ ] Clips, transforms, shadows, and inherited visibility.
- [ ] Exterior focus rings and other escaped sibling content.
- [ ] Inline popups, tooltip layers, focus-ring layers, and overlay ordering.
- [ ] Hidden, removed, reinserted, and reordered views.
- [ ] Appearance-generation and ancestor-geometry changes.
- [ ] Font and image replacement and removed-view resources.
- [ ] Atlas recovery using only the current live manifest.

### Operation counts and threads

- [ ] Initial frame draws every participating view once.
- [x] A clean frame invokes no view `draw` methods.
- [ ] A leaf display invalidation rebuilds only the leaf's own dirty fragments.
- [ ] Structural reconciliation does not redraw unaffected view content.
- [ ] Fragment-backed and monolithic rendering emit equivalent renderer
      operations.
- [ ] Coalesced thread updates apply the newest valid replacement.
- [ ] Clear and target-replacement barriers discard stale queued updates.
- [ ] Resource leases survive until the corresponding renderer acknowledgement.

## Delivery sequence

1. Add failing FigDraw tests for foreign, stale, detached, empty, and raw-mutation
   cases.
2. Implement persistent root/child slots, opaque handles, controlled mutation,
   scoped generations, and `materialize` in FigDraw.
3. Add NimKit `RenderScene`, stable view IDs, composite view entries, and
   revision-based invalidation behind a diagnostic/feature switch.
4. Build monolithic and fragment scenes side by side and establish canonical
   equivalence and operation-count tests.
5. Add per-contribution manifests, live-frame merging, and retirement by frame or
   acknowledgement.
6. Enable fragment-native rendering for the direct static renderer.
7. Keep the renderer thread on materialized snapshots until immutable fragment
   replacement batches and acknowledgements are complete.

## Deferred work

- Rasterized view/texture caching.
- Local-coordinate and transform-based movement optimization.
- Partial GPU redraw or damage-only rendering.
- Mutable fragment graphs shared across threads.
- Dynlib fragment integration.
