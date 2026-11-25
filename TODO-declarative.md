# DirectView roadmap

DirectView is the declarative API we intend to stabilize. A body composes actual
NimKit widgets. Documents and controllers own application state, and each mounted
component owns its bindings. Applications opt in with
`import merenda/nimkit/directviews`. The API is experimental and ready for a
pilot on one application screen. [Usage guide](docs/declarative-direct-views.md) ·
[Editable list example](examples/direct_views_demo.nim)

## 1. Reproduced correctness issues

- [x] A body evaluates its receiver once and finishes the update on the same
  node. A regression uses two hosts and verifies that both remain usable.
  [Composition tests](tests/nimkit/directviews.nim)
- [x] A binding flush attempts the other pending bindings when a callback
  raises. The failed binding stays pending for an explicit retry or a later
  notification. A failed GUI drain preserves other scopes' queued work.
  [Binding tests](tests/nimkit/directbindings.nim)
- [x] Clearing collection selection, toggling the last row off, and changing
  the controller's selection mode keep the view and controller in sync.
  Signal-time teardown and adapter replacement have regression coverage.
  [Virtualized row tests](tests/nimkit/directcollectiondemo.nim)

## 2. Recovery from an interrupted body

- [x] Preserve the body error during unwinding and keep partially composed
  and unvisited mounts reachable for teardown. A caller can catch the error,
  clear the host, and compose a valid body from its model.
- [x] Exercise a late duplicate key and a nested setter failure in a mounted
  tree. After clearing and rebuilding, the retired button ignores clicks and
  its queued binding cannot update the old widget.
  [Recovery tests](tests/nimkit/directlifetimes.nim) ·
  [Recovery contract](docs/declarative-direct-views.md#recovering-from-an-error)

## 3. Validate one shipping screen

Use one bounded screen, such as a Kosmo settings pane, to test the API in a
real application before promising compatibility. Pick a screen with editable
state and an ordinary close/reopen path. Use the existing collection fixture
for large-list workloads.

| Existing evidence | Remaining pilot check |
| --- | --- |
| Keyed rows retain an active field editor across insertion, reorder and scrolling. A 5,000-item fixture mounted 24 buffered rows plus the offscreen editor in the middle of the list. [Row tests](tests/nimkit/directcollectiondemo.nim) · [Measurements](docs/benchmarks/intrinsic-buffered/README.md) | Repeat scrolling, editing, removal and reopening. Record mounted rows, subscriptions and memory over repeated cycles, including after teardown. |
| Cocoa integration covers marked text, selection, caret geometry and committing after scrolling. A Japanese input-method test is available with `MERENDA_TEST_JAPANESE_IME=1`. [Native tests](tests/integrations/nativecomposition.nim) | Exercise keyboard traversal, IME composition, accessibility focus and announcements on the pilot's supported platforms. Include hiding, switching windows, closing and reopening. Record which platform and input method ran. |
| In the buffered Metal fixture, median synthetic edit and scroll times were 24.20 ms and 28.47 ms from dispatch to render submission. [Native benchmark](docs/benchmarks/intrinsic-buffered/README.md#native-renderer) | Agree on an interaction budget for the pilot and measure p50/p95 input-to-presentation latency for editing, scrolling and resizing. Record hardware, backend and timing endpoints. |
| Form and two-document examples cover drafts, undo, document switches, closure, same-ID reopening and stale queued results. [Forms](docs/declarative-forms.md) · [Two documents](docs/declarative-two-documents.md) | Exercise the pilot's actual apply/cancel and close policy. Verify that queued work from the previous screen cannot change the reopened screen. |

- [ ] Publish the pilot results with the tested revision.
- [ ] Use the results to name the supported composition, binding and container
  APIs. Document recovery, platform limits and any experimental adapters that
  still require opt-in. Run the shared suites, ownership sanitizers and example
  builds on the release candidate, and verify the pilot's shipping build.

## Feature-specific follow-up

Prioritize these when a screen needs the feature or a measurement identifies a
bottleneck.

- **Large eager layouts and dragging.** In the 100-row headless editor, a live
  edit with persistent layout took about 61 ms, rising to 181 ms with a fresh
  preview. Reorder rebuilt the solver. Profile the full gesture across all
  candidates, define a gesture budget, and reject candidates whose layout
  failed before scoring their geometry. [Layout measurements](docs/benchmarks/persistent-layout/README.md) ·
  [Dragging roadmap](TODO-dragology.md)
- **Collection publication.** Per-item observation limits which bindings wake
  up. Single-item assignment still copies and validates a collection snapshot.
  Measure publication time and allocations at the pilot's data sizes before
  changing the model API. [Collection contracts](docs/collection-sigils.md)
- **Document policy.** For a multi-field form, make Apply one undoable command
  and test Cancel, external edits and field-level conflicts. For a persistent
  document, define atomic save, recovery and cancellation. These decisions
  belong to the document or controller. [Form and save experiment](docs/declarative-forms.md)

The design history records earlier approaches in the [earlier roadmap](https://github.com/elcritch/merenda/blob/2d673d0d/TODO-declarative.md).
