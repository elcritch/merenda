# Form drafts and MVC experiment

Run `nim ic -r examples/form_editors.nim`. Two panels share an editing owner;
a third has an independent draft of the same document. The first and third use
DirectView actions. The second compares ViewSpec actions around the same
DirectView-owned form: ViewSpec has no custom FormView leaf adapter yet.

The example deliberately uses ordinary helpers instead of introducing a public
form DSL. `newDraftForm` composes an actual FormView whose rows are created through
`addRow`. Its DirectNode owns the binding scope. Removing that node releases the
subscriptions without destroying the draft. The form is not a second description
of its widget properties and needs no separate composition session.

## Editing and acceptance

The document owns accepted integer data, a revision and undo. `FormDraft` is an
identity-bearing editing owner containing observed raw text and status. Creating
another owner gives an independent draft; passing the same owner shares edits.
The existing object-value parser and TextField editing pipeline handle formatting
and invalid input. An incomplete `-` remains provisional. Ending editing can
normalize `0042` to `42` without accepting a document change. **Apply** is the
explicit domain operation that accepts a valid, non-conflicting draft and adds
document history. Control value notifications alone never mean document acceptance.

**Cancel** reloads the current accepted value. An external accepted update or an
undo changes the document revision, so an older draft must cancel/reload before
applying. The external-update example clears old history rather than replaying
inverses against an unrelated accepted state. This is a conservative example
policy, not a general merge algorithm.

**Save / Close** validates and applies the draft, records an in-memory saved value
and clean undo checkpoint, then retires that editing owner. When panels share the
owner, they share this closure too. It does not write a file or close the document.
Invalid or conflicting drafts prevent this operation. Independent drafts remain
independent; a real document-close workflow would need to review all valuable
drafts according to application policy.

## Lifetimes and delayed validation

Queued validation captures plain input, document revision and editing generation,
with a weak reference to its editing owner. **Complete** delivers it deterministically.
Changes, owner disposal and actual document closure invalidate it. Hiding a retained
view does not dispose the owner or cancel its validation. Clearing a form disconnects
its view bindings while leaving durable draft state intact.

This is not a network or worker cancellation implementation. It does not provide
per-field concurrent merging, draft persistence, native operating-system IME
coverage or a universal Save/Close policy. It establishes the smaller contracts
before exposing a toolkit-wide form abstraction.

The generation and weak-owner checks remain explicit example code. A reusable
guarded-command helper, hidden-view suspension/resume and a document-owned
asynchronous save example have not been implemented. Existing controller
appearance hooks are not wired to an automatic suspension policy.

## History and layout

The experiment uses existing document inverses. The separate
[undo improvements](undo-history.md) add opt-in typed coalescing and a total group
limit; they do not automatically merge form typing into accepted history.

DirectViews now batch StackView ordering, and FormView reuses child measurements
within a layout pass. [The layout measurements](benchmarks/layout/README.md)
separate these operations from native presentation and the remaining solver work.

Behavioral coverage is in [formdrafts.nim](../tests/nimkit/formdrafts.nim) and
[directlifetimes.nim](../tests/nimkit/directlifetimes.nim), imported by the shared
NimKit runner. The former separates domain policy from widget editing checks;
the latter checks hidden observation, queued work retirement and rebuilding.

The frozen shared NimKit suite passes all 1,594 tests, and the complete example
bundle compiles. Widget editing coverage dispatches keys through a headless NimKit
window; it does not establish native OS IME behavior or input-to-display latency.
