# Incremental Render Fragments

## Implementation status

Implementation began with [FigDraw PR #72](https://github.com/elcritch/figdraw/pull/72)
and the initial NimKit scene foundation on `feature/incremental-render-fragments`.
FigDraw support shipped in 0.36.0, and the initial NimKit scene foundation was
merged on `feature/incremental-render-fragments`. Per-view contribution caching,
direct fragment rendering, and the dedicated-renderer update protocol are complete
on `feature/per-view-render-fragment-cache`. The unchecked FigDraw validator and
items under Deferred Work are not part of the NimKit implementation.

## Recommendation

Modify FigDraw's fragment model first, then use fragments as NimKit's per-view
render cache.

- Fragments should be attachable as logical children of existing nodes, including
  nodes inside other fragments, and as roots of a layer.
- A fragment attachment must remain present when its contents have zero, one, or
  many roots.
- NimKit should cache vector/render-tree fragments at this stage. It should not
  add a separate rasterized-view or texture cache yet.
- Enable fragment-native rendering on both direct and dedicated static renderers.
- Preserve monolithic `Renders` through a flattening/materialization API for
  compatibility and diagnostics.
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
- [x] Detect attachment cycles.
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
- [x] Support atomic movement/reordering without a transient detached state.
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
      `buildRenders`, and compatibility rendering.

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
- [x] Reuse a view ID in a different scene by creating scene-local fragments.

### Composite view contribution

A view cannot be represented safely as one replaceable fragment. Current drawing
can produce normal children, escaped siblings, and roots on additional layers.
Use a composite entry:

```text
view slot
└── stable placement transform fragment
    ├── stable shell fragment      background, shadow, clipping
    │   ├── replaceable self fragment
    │   ├── child view slot
    │   └── child view slot
    └── escaped fragment           exterior focus ring or chrome

layer-root transform fragments     popup, focus, tooltip, future overlays
```

The placement fragment contains one `nkTransform` node updated through the
controlled node API. Its fragment ID, shell, self drawing, escaped drawing, and
child slots remain attached when a view or ancestor moves. The shell remains the
background and clipping parent. Rebuilding a view's own drawing replaces the self
fragment without disturbing its child-view slots.

Preserve these existing semantics:

- Normal view content and same-layer descendants are children of the shell and
  inherit its clipping and placement transform.
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

- [x] Build or reuse the shell during scene reconciliation.
- [x] Run `view.draw` only when its local contribution is dirty or its render
      context changed.
- [x] Replace each affected output fragment atomically after a successful draw.
- [x] Reconcile child, sibling, root, and layer slots independently of redrawing
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

- [x] Make local invalidation advance only the target view's drawing revision.
- [x] Propagate damage/descendant state without advancing ancestor drawing
      revisions.
- [x] Include effective appearance, local placement, draw level, and relevant
      geometry in the view cache key. Include the visible rectangle only for
      drawing that reads it.
- [x] Invalidate/reconcile descendants when an ancestor changes an inherited
      render context.

The completed implementation captures drawing in view-local coordinates and keeps
placement in the stable transform fragment. `DrawContext.visibleRect` records a
dependency when drawing reads it, so virtualized drawing is recaptured as its clip
moves while ordinary drawing remains cached. Explicit-layer output is rooted under
an equivalent absolute placement transform.

## Resource manifests

Each cached view contribution should retain the font and image resources used to
build it. At the frame boundary, create a fresh merged manifest from all live,
attached contributions rather than maintaining incremental resource reference
counts initially.

- [x] Add manifest merge support.
- [x] Associate fragment/resource versions with the scene frame generation.
- [x] Exclude manifests belonging only to removed or replaced fragments from the
      new live merge.
- [x] Retain replaced manifests until the frame that could reference them has
      completed or been acknowledged.
- [x] Replay the current merged live manifest after atlas recovery.
- [x] Keep atlas generation separate from UI fragment-handle generations.

For direct synchronous rendering, old resources can be released after the frame
boundary. For threaded rendering, use the existing render-ID acknowledgement and
resource-lease mechanism.

## Renderer-thread boundary

Do not move a `RenderFragments` graph to the renderer thread while the UI scene
retains handles into it. That would alias mutable fragment objects and node
storage across threads.

Implemented behavior:

- Direct static rendering reconciles and renders the mutable application-thread
  fragment graph synchronously without materializing `Renders`.
- Public/diagnostic `buildRenders` retains compatibility by materializing lazily
  and caching the monolithic result until the scene changes.
- The application scene builds a cumulative update from the last acknowledged
  scene generation. Every update contains the complete view placement order and
  node payloads only for contributions changed after that baseline.
- Updates are move-only and carry copied dirty node sequences plus font/image IDs.
  Placement-only updates carry value-type cache keys and mutate the renderer's
  retained transform nodes. They never carry application-thread resource handles
  or FigDraw fragment handles.
- The dedicated renderer owns a separate `RenderScene` and moves received node
  payloads into its own fragment graph before rendering it directly.
- The bounded two-entry channel coalesces superseded frames. Because the newest
  update is cumulative from the acknowledged generation, dropping an intermediate
  update cannot omit one of its fragment replacements.
- Target, render, scene, and baseline generations are checked before mutating the
  renderer replica. New scenes, changed layer sets, target replacement, and an
  explicitly forced recovery are full-update ordering barriers.
- Render acknowledgement advances the application's cumulative baseline and
  releases retired fragment resource manifests. Rejection clears that baseline,
  drops rejected leases, and forces the next update to be full.
- Atlas recovery uses the transferred live font/image ID set to replay and retain
  only resources referenced by the accepted scene.
- No mutable fragment graph crosses the renderer-thread boundary.

The complete threaded update is stamped with the equivalent of:

```text
targetGeneration
renderId
scene identity
acknowledged base generation
current scene/resource generation
```

- [x] Bound and coalesce queued replacements by fragment and generation.
- [x] Treat clear, layer replacement, target replacement, and full snapshots as
      ordering barriers.
- [x] Reject obsolete target, scene, layer, atlas, and fragment generations.
- [x] Acknowledge the applied frame/update generation before releasing payloads
      and resources.
- [x] Send a full current snapshot after target replacement or when a delta chain
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
- [x] Cover root fragments, multiple layers, physical node insertions, movement,
      removal, and reordering.
- [x] Ensure public APIs cannot make traversal metadata stale.

### NimKit equivalence

Build scenes through both the legacy monolithic path and the fragment path, then
compare a canonical traversal or renderer-operation stream rather than physical
Fig indexes.

- [x] Nested view updates and sibling ordering.
- [x] Same-layer versus cross-layer descendants.
- [x] Clips, transforms, shadows, and inherited visibility.
- [x] Exterior focus rings and other escaped sibling content.
- [x] Inline popups, tooltip layers, focus-ring layers, and overlay ordering.
- [x] Hidden, removed, reinserted, and reordered views.
- [x] Appearance-generation and ancestor-geometry changes.
- [x] Scrolling updates placement transforms without recapturing drawing that does
      not read `visibleRect`, while visibility-dependent drawing is recaptured.
- [x] Font and image replacement and removed-view resources.
- [x] Atlas recovery using only the current live manifest.

### Operation counts and threads

- [x] Initial frame draws every participating view once.
- [x] A clean frame invokes no view `draw` methods.
- [x] A leaf display invalidation rebuilds only the leaf's own dirty fragments.
- [x] Structural reconciliation does not redraw unaffected view content.
- [x] Fragment-backed and monolithic rendering emit equivalent renderer
      operations.
- [x] Coalesced thread updates apply the newest valid replacement.
- [x] Clear and target-replacement barriers discard stale queued updates.
- [x] Resource leases survive until the corresponding renderer acknowledgement.

## Performance baseline

`tests/benchmark_render_fragments.nim` is a release-mode diagnostic benchmark,
not a timing-threshold test. It measures flat trees from 100 through 10,000
views, uses the median of seven samples, and separately exercises clean frames,
root-dirty frames, leaf-dirty frames, scene materialization, layer replacement,
and fragment reordering.

On an Apple M3 Pro (12 cores), macOS 15.6, Nim 2.2.10, ARC with threads enabled,
the following medians were observed. Times are microseconds per operation:

| Views | monolithic cached | monolithic root dirty | monolithic leaf dirty | scene cached | scene root dirty | scene leaf dirty | materialize |
|------:|------------------:|----------------------:|----------------------:|-------------:|-----------------:|-----------------:|------------:|
| 100 | 13.87 | 471.83 | 467.30 | 2.97 | 411.43 | 413.58 | 12.35 |
| 1,000 | 114.31 | 5,002.16 | 4,761.46 | 4.73 | 4,190.01 | 4,207.23 | 109.66 |
| 5,000 | 725.07 | 29,584.12 | 29,409.19 | 28.18 | 26,306.13 | 25,819.05 | 629.54 |
| 10,000 | 1,527.02 | 61,390.76 | 61,047.55 | 55.23 | 54,694.61 | 55,140.80 | 1,383.33 |

The completed direct-renderer path keeps the same linear reconciliation cost
while narrowing `draw` calls and fragment replacement to dirty contributions.
Scene-update timings no longer include monolithic materialization.

The root- and leaf-dirty timings remain similar for these deliberately empty
views because both still traverse the view hierarchy and merge live manifests.
The leaf path runs `draw` only for the leaf, so views with text layout, images,
SVGs, or other meaningful draw work avoid rebuilding those clean contributions.
The benchmark shows no new complexity cliff through 10,000 view fragments,
remains in the same order of magnitude as monolithic rebuilding, and removes the
71--138 ns/node materialization pass from normal synchronous rendering.

On this run, replacing a 10,000-node compatibility scene took 1.10 ms with one
layer and 0.84 ms with 32 layers. Materializing 10,000 independent fragment
slots took 1.24 ms, a 5,000-deep nested fragment chain took 0.80 ms, and replacing
one leaf remained 0.14--0.20 us across populations of 100 through 10,000.

The benchmark exposed two FigDraw usage cliffs and drove API changes before the
dependency pin was advanced:

- Materialization had accidentally copied the fragment-entry table once per
  visited node. It now traverses borrowed internal topology and is linear.
- Reversing every sibling with individual `moveFragment` calls is quadratic,
  because each isolated move performs a linear sequence edit. At 5,000 slots a
  two-way reversal took 1,169.11 ms. The new `reorderChildFragments` and
  `reorderRootFragments` operations reconcile the complete sibling order in a
  single linear pass; the same 5,000-slot two-way reversal took 0.94 ms.

NimKit reconciliation should therefore use an isolated move for isolated
changes and the bulk APIs whenever it already knows a complete sibling order.

`tests/benchmark_markdown_scroll.nim` profiles a more realistic dirty-frame
workload: the repository's 35,919-byte README in a 760 x 540 `MarkdownView`,
scrolled bidirectionally over 240 measured frames after 20 warmup frames. It
measures CPU-side view drawing/reconciliation, bounded-channel handoff,
renderer-replica application, and acknowledgement; GPU execution is deliberately
excluded. The renderer stages are serialized in the diagnostic so its CPU total
is comparable even though production runs them on separate threads.

On the same Apple M3 Pro, the pre-PR monolithic path and completed fragment-native
path measured:

| Pipeline | wall median | wall p95 | CPU median | CPU p95 | prepare median | transfer median | apply/ack median |
|---|---:|---:|---:|---:|---:|---:|---:|
| pre-PR monolithic | 11.439 ms | 12.165 ms | 11.437 ms | 12.144 ms | 11.366 ms | 0.001 ms | 0.001 ms |
| fragment-native | 15.182 ms | 16.573 ms | 15.181 ms | 16.571 ms | 12.414 ms | 2.245 ms | 0.478 ms |

The median CPU cost is 32.7% higher and p95 is 36.4% higher in this continuously
dirty scrolling workload. View preparation itself is 9.2% higher; including the
deep, ARC-isolated transfer clone, total application-thread preparation is 29.0%
higher.
Of 1,200 view placements, 714 (59.5%) carried changed contributions; the other
40.5% reused retained fragments. The result remains in the same order of
magnitude, and the flat 10,000-view benchmark above confirms linear scaling with
no population-dependent cliff. The remaining constant-factor cost is primarily
the independent cross-thread clone of nested text/drawable data plus
renderer-replica application.

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
7. Send cumulative move-only fragment updates to a renderer-owned scene and
   acknowledge applied generations before releasing resources.

## Deferred work

- Rasterized view/texture caching.
- Mutable fragment graphs shared across threads.
- Dynlib fragment integration.
