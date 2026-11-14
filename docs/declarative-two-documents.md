# Two-document editor experiment

This experiment compares direct views (P7) with ViewSpec (P0) using the same
document, draft, undo, and delayed-validation policy. Direct views remain the
main candidate; ViewSpec remains the comparison baseline.

Run either example from the repository root with the existing Atlas dependencies:

```sh
nim ic -r examples/two_document_direct.nim
nim ic -r examples/two_document_spec.nim
```

Each window contains two instances of the same editor. Edit a draft, press its
**Validate** button, then press **Complete queued** to deliver the simulated
reply. The accepted-value label changes only after a successful validation.
Leave a request queued while editing again, switching documents, or closing one
to exercise stale-result rejection. **Reverse**, **Remove**, **Restore #1**, and
**Undo** exercise collection identity and document history.

## Ownership and editing policy

The shared implementation is [two_document_tasks.nim](../examples/two_document_tasks.nim).
`EditorDocument` extends NimKit's existing `Document`. It owns one
`CollectionSigil[int, EditorTask]`, retained drafts for removed rows, a revision,
and the inherited undo manager. Each row is a plain value containing accepted
text and provisional text. There is no second authoritative collection on the
editor controller.

Typing changes the draft, including blank or invalid input. Successful validation
commits accepted text through the document's undo path. Rejected or obsolete
validation does not commit text or create an undo entry. Undo changes accepted
values or collection structure while preserving the latest draft. Draft typing
itself is not grouped into document undo in this experiment.

Undo callbacks hold a weak document reference, so history remains usable by a new
editor controller after the original controller is released. A controller owns
one scope that observes its current document's order. Its structural signal
combines that order with a presentation generation; switching documents
reconfigures the scope. Views own their own component and property bindings.
Application code does not maintain a list of composition sessions.

Rows are keyed by presentation generation and task ID. Reordering within a
document retains the same widgets, field editor, selection, and marked text.
Switching documents replaces the editor even if the next document uses identical
task IDs. Row callbacks also capture the generation: an old field or button is
already inert after a switch, before queued view reconciliation runs.

Removing a row retires its widget and bindings. Its draft survives in the
document and is restored into a fresh widget on reinsertion. Selection, focus,
and marked-text composition do not survive destruction of the editor.

Actual `Document.close()` is observed by the controller and detaches its
presentation. Detaching an editor without closing its document is a separate
operation. Mutations are blocked for closed or detached documents; explicit
navigation can select another open document. Reopening a closed document uses
a fresh document instance, even when its external ID is reused.

## Delayed work

The queue is a deterministic fake validation service. Requests retain plain
input values and a weak controller reference, plus the presentation generation,
document ID, and document revision. Delivery checks those values before applying
the result. Changes, switches, closure, and same-ID reopen therefore invalidate
old replies even when the controller remains alive.

The revision is deliberately document-wide: an edit or structural change anywhere
in a document can invalidate another row's pending request. This is conservative,
not a per-row conflict-resolution policy. Invalidated requests remain queued
until delivery and are discarded then; the prototype does not cancel external
worker or network operations.

## Comparing the renderers

| Concern | Direct views | ViewSpec |
| --- | --- | --- |
| Reusable row | Ordinary `DirectNode` builder, composed with `component` | Ordinary helper returning a `ViewSpec` |
| Property access | Typed widget setters and scoped bindings inline | Description fields plus typed binding recipes |
| Structural changes | Independently observed row component | Rebuilds the affected editor host's description |
| Draft/accepted text change | Item bindings update the field and label | The same item bindings update the field and label |
| Second editor | Separate owned view tree | Separate owned mount tree |
| Domain policy | Shared document/controller implementation | The identical implementation |

The experiment's domain protections belong to MVC and the binding layer. They
do not require eliminating ViewSpec. Direct views avoid an additional property
description vocabulary and make nested observation explicit; ViewSpec retains
its inspectable structural description and duplicate-key preflight.

## Acceptance checks and limits

The implementation in `5ed1d43c` passes five paired tests per renderer in the
shared NimKit suite (1,577 tests). The full `nim integration` task passes, including
NimKit, Kosmo, integration, and Tekton tests. The full example bundle also compiles.
The property handoff fix is recorded separately in `071572ef`.

The same checks run for both renderers in
[twodocumenteditors.nim](../tests/nimkit/twodocumenteditors.nim), imported by the
shared NimKit runner:

- Independent mounted editors, drafts, history, and updates.
- Validated commits, rejected blank drafts, and visible undo results.
- Keyed reorder preserving field-editor identity, selection, and marked text.
- Removal/reinsertion restoring the draft into a fresh widget.
- Stale controls before and after queued document-switch reconciliation.
- Delayed replies after newer edits, document switches, actual closure, and
  reopening with the same external ID.
- Document undo after the original controller is released.
- Pending requests that do not retain a retired controller.
- Attempted navigation to a closed document leaving the current editor usable.

Both examples were also run as native macOS windows with development control,
using background presentation. Screenshots verified matching layouts and the
results of text input, validated commit, undo, delivery after switching, and
closing one document while the other stayed usable. This smoke check used the
ordinary control actions; it did not simulate native IME composition.

The tests pump GUI work against observable conditions with monotonic deadlines.
Marked-text coverage exercises NimKit's field editor APIs headlessly; it does not
establish native operating-system IME behavior. Validation is manually delivered
on the GUI thread, not performed by a network service or worker thread.

Rows remain eager, removed-row drafts remain retained for the document lifetime,
and undo/publication still uses collection snapshots. The experiment does not
establish virtualization, bounded history storage, general formatted-field
conflicts, undo grouping, arbitrary observer exception recovery, or native input
latency. It is a behavioral comparison, not a new performance benchmark.
The sample documents are in memory; file persistence and save-review UI are
outside this experiment.
