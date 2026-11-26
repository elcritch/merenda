# Form drafts and MVC experiment

Run `nim ic -r examples/form_editors/form_editors_protocol.nim` to try a form with DirectView buttons
that send protocol selectors such as `this.onAction(panel, apply())`.

Run `nim ic -r examples/form_editors/form_editors_procs.nim` to compare named callbacks such
as `this.onAction(panel, apply)`. Both examples use the same layout and actions.
Two panels share an editing owner, and a third has an independent draft of the
same document. All three use DirectView toolbars around DirectView-owned forms.

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

Validation is not a network or worker cancellation implementation. It does not provide
per-field concurrent merging, draft persistence, native operating-system IME
coverage or a universal Save/Close policy. It establishes the smaller contracts
before exposing a toolkit-wide form abstraction.

The two-document example uses `this.onAction(owner, context)` and ActionTarget's
existing weak receiver ownership. Their controller methods share one predicate
that checks the editor and document are open, the captured generation still
matches, and the task still exists before editing, removing or queuing validation.
This rejects stale actions even before queued view reconciliation runs. Context
follows Nim value semantics, so embedded references retain their usual ownership.
The controller checks neither own requests nor cancel document work; delayed
results still check their own captured revision before applying.

The separate [visibility example](../examples/direct_lifetimes_demo.nim) wires
controller appearance signals to explicit DirectView suspension/resumption.
The toolkit does not automatically equate hiding with suspension or disposal.

## Document-owned asynchronous save

**Async Save** captures the document's accepted value and revision and sends them
to a Sigils actor on NimKit's worker pool. The demo writes into its own temporary
directory, shown in the window. Only one write per document can be in flight.
Completion returns to the document's owning thread; no initiating view or editor
is retained. A successful write marks history clean only if the captured revision
is still current. A newer edit remains dirty. Errors are reported without marking
the document clean.

Closing the document suppresses late result publication and clean-state changes;
it does not cancel an already submitted file write. The completion clears only
the in-flight bookkeeping for a closed document. This is a real worker/write
example, distinct from the manually delivered validation queue. It is not a
production persistence layer: atomic file replacement, recovery, external file
conflicts and cancellation are outside its scope. **Save / Close** remains the
separate in-memory checkpoint policy described above.

Tests release the initiating DirectView before delivery, verify saved bytes and
worker/owning thread identities, preserve dirty state after newer edits, and cover
write failure and closure. They wait on observable state with monotonic deadlines.

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

After simplifying the controller actions, the shared NimKit suite passes all
1,621 tests and the complete example bundle compiles. The preceding broader work
also passed 49 Tekton tests. Widget editing coverage dispatches keys
through a headless NimKit window; it does not establish native OS IME behavior or
input-to-display latency.

The broader integration attempts were not clean: one hit a Git subprocess bad-file-
descriptor error; a retry passed Kosmo but failed a native window-key assertion
and a shutdown assertion. The native activation and shutdown tests subsequently
passed in isolated runs. These results do not constitute a passing full integration
run; those failures remain recorded separately from the feature-suite results.
