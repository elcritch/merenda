# Declarative dragging in NimKit

NimKit's `newDeclarativeDragView` ports the discrete model-driven interaction from
[Declarative Dragging (D2)](https://declarative-dragging.github.io/) and
[Dragology](https://github.com/declarative-dragging/dragology). Describe the states
an element can reach; NimKit lays out each state to discover its destinations.
You do not write drop-coordinate calculations.

Try the two-column, variable-height card example:

```sh
nim ic -r examples/declarative_drag_demo.nim
```

Use `nim c -r` with compilers that do not provide `ic`. Drag cards within or
between columns. Other cards animate into position while the grabbed card follows
the pointer. Escape or releasing outside the host cancels. Undo and Redo operate
on completed model changes.

## Application contract

```nim
let host = newDeclarativeDragView(
  initialModel,
  build = buildView,       # (model, DragEnvironment) -> fresh detached View
  successors = outcomes,  # (model, elementId) -> seq[Model]
  commit = acceptChange,  # optional (previous, next) -> bool
  frame = rect(0, 0, 600, 400),
)
```

Mark each draggable subtree explicitly in the builder:

```nim
let card = newStackView(laVertical)
card.identifier = itemId
card[vpDraggable] = true
```

The whole card, including its child views, moves together. An identifier alone
does not make a view draggable; add `vpDraggable` to its properties. Builders
written against the earlier `dragId` API should assign the value to `identifier`
and add `vpDraggable`.

- Use plain value models, or immutable referenced data. A model containing mutable
  references needs an application-owned snapshot before it enters the host.
- The builder uses normal NimKit layout: views, labels, stacks, constraints and
  drawing protocols. It receives the host's bounds and immutable appearance.
  Return a **fresh detached tree** each time. Do not start timers, workers, native
  windows, actions, or subscriptions to live data inside the builder.
- Mark each independently moving subtree with `vpDraggable` and give it a
  nonempty `identifier`. Marked identifiers must be unique and stable across
  candidates. Marked subtrees cannot contain other marked subtrees; unmarked
  containers and child labels are fine, including those with identifiers. The
  root must be unmarked. Missing, duplicate, nested and root markers raise
  `ValueError`.
- Enumerate local successors, not all permutations. The current model is included
  automatically as the first candidate. Missing dragged IDs make an outcome
  ineligible. Empty successors safely leave the original model unchanged.
- The host owns the displayed model. `host.model` reads it; `host.model = value`
  cancels any interaction and rebuilds the display. Call `refreshDragView()` when
  other builder inputs change. Resizing invalidates the current drag.
- `commit` runs once for a changed eligible drop. Return `false` to reject it,
  for example if the application's revision changed. Register one undo operation
  here. A click, cancellation, unchanged model, or rejected proposal creates no
  automatic undo entry. Replacing `host.model` inside this callback invalidates
  the proposal, so newer data is not overwritten.
- An optional `clicked(id)` callback handles presses released below the threshold.
  Preview controls are inert drawings; their ordinary widget actions and focus
  handling are not installed on the host.

The example uses `UndoManager.registerValueChange` to make commit, undo and redo
explicit. The host deliberately leaves application transactions to its caller.

## Selection and presentation

`initDragOptions()` defaults to a four-pixel threshold, six-pixel stickiness,
unlimited snapping distance inside the host, floating, and 160 ms transitions.
Change a copy of these options and pass it to the constructor. A finite
`snapRadius` allows gaps with no eligible drop. Distances are logical coordinates.

The geometry-only `closest` function selects eligible `DragTarget` values. Ties
use input order; stickiness favors the previous choice. NaN/infinite positions
and missing targets cannot win. The actual grabbed offset is preserved, including
through nested frame and bounds-origin conversions.

Speculation never attaches candidate views to the live window. Independent render
scenes retain fonts and images; cached drawing is composed under the host's clip.
The live model stays unchanged while preview placements animate. Interrupted
transitions start from their current displayed origins. Floating renders the
original dragged subtree once, above the selected preview. On release or cancel,
it settles to the final layout.

Window capture cancellation, host removal, Escape, outside release, and model
replacement discard candidates. The host uses the existing window animation
scheduler. Geometry tests and pointer-dispatch tests are part of `tests/tnimkit.nim`.

## Port scope

This is the first native, discrete milestone from [the roadmap](../TODO-dragology.md).
It supports single-pointer, single-window finite alternatives, nearest selection,
floating, and translation transitions. It does not yet implement Dragology's
continuous `vary` optimizer, `between` interpolation, behavior chaining, creation
or explicit deletion targets, arbitrary path morphing, or native pasteboard DnD.
Existing NimKit pasteboard dragging remains a separate API.

The presentation surface is intended for model-driven diagrams and cards, not
cloning arbitrary interactive controls. Candidate layers are flattened under the
host. Parent clipping uses the destination layout; cross-parent motion can cross
those clip edges. Resized or changed content switches to the selected drawing,
while matching origins interpolate. Added/removed elements appear/disappear
immediately. Large candidate sets need application limits; no virtualization or
speculation budget is implemented yet.

D2 is by Joshua Horowitz, Andrew Blinn, and Jeffrey Heer. Dragology's original
implementation is MIT licensed; its notice is retained in
[docs/licenses/dragology.txt](licenses/dragology.txt). This Nim adaptation uses
NimKit's layout and renderer rather than the original React/SVG runtime.
