# Merenda Work Plan

Updated **2026-09-25**. Focus on reliable long-running Kosmo sessions and bounded
memory use, then extend Tekton's authoring workflow.

Architecture and API decisions live in [design](docs/design.md) and
[layout](docs/layout.md). Test procedures, ownership contracts, and memory
measurements live in [reliability](docs/reliability.md); workspace behavior is
covered in [Kosmo workspace](docs/kosmo-workspace.md).

## 1. Lifecycle and platform reliability — active

The bounded multi-window/terminal regression passes, and dedicated rendering
works with ARC and ORC. The remaining work is to close platform lifecycle gaps
and verify extended use.

- [ ] Add an earlier close barrier in Siwin's Windows/X11 OS-close paths so GPU
  completion and renderer destruction finish before native window teardown.
  Cover OS-driven close, runtime shutdown, and repeated close in integration tests.
- [ ] Run extended sessions with multiple windows, terminals, Git activity, and
  Markdown. Track children, descriptors, owned workers, and memory after warmup;
  investigate growth and turn reproducible failures into bounded regressions.
- [ ] Verify dmon's Linux recursion fix before removing Kosmo's forced polling
  fallback. Exercise deep trees, multiple windows, missed events, and shutdown.
- [ ] Replace the temporary FigDraw `fix/acyclic-render-ownership` dependency with
  a release containing [PR #96](https://github.com/elcritch/figdraw/pull/96).

**Completion evidence:** supported close paths preserve window lifetime through
render cleanup, and repeated sessions return owned resources to their warmed
baseline. Native Windows/Linux behavior needs validation beyond macOS results.

## 2. Memory and responsiveness — next

Downloads are bounded and incremental render updates are compact. The next step
is to measure retained memory across the whole workspace and budget its caches.

- [ ] Profile representative workspaces using `tests/benchmark_memory.nim` and
  longer sessions. Separate live allocations and cache contents from allocator
  retention; measure decoded images, Markdown, Git diffs, and downloaded files.
- [ ] Set aggregate cache budgets and eviction policies from those measurements.
  Verify that closing documents releases their working sets and that reopening
  evicted content recovers correctly.
- [ ] Profile editing and scrolling with UTF-8 gap storage, worker layout, and
  retained rendering together. Use the fragment/snapshot benchmarks to identify
  remaining costs. Add general visible-range text layout only if profiling
  shows it is needed.

**Completion evidence:** cache growth is bounded under the chosen workload, with
before/after memory and latency measurements and coverage for eviction/recovery.

## 3. Tekton authoring — next feature work

View editing and preview reconciliation are established. Extend that workflow
through typed document operations while preserving invalid drafts, undo/redo,
selection, and compatible preview identities.

- [ ] Start non-view editing with constraints and guides: typed insert, remove,
  move, and replace operations, including grouped transactions and validation.
- [ ] Add structured inspectors for those resources and the property metadata
  they need, using runtime descriptors for enum choices.
- [ ] Connect inspectors to direct layout authoring: guide overlays, anchor
  handles, and constraint constant, priority, and activation editing. Surface
  conflicts and ambiguity in the same workflow.

**Completion evidence:** a user can create, edit, undo, save, and reload a
constrained layout, including recovery from invalid input, without losing the
last valid preview or selection.

## Validation

For each code increment, run the relevant shared runner and `atlas-run tests`.
Compile examples with `atlas-run tests --compile-only examples/all_compile.nim`.
Ownership changes also need ARC/ORC sanitizer coverage from the reliability
guide. Record platform limitations and measured outcomes with the change;
keep this plan focused on unfinished work.
