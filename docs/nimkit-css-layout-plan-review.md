# CSS layout extension review

**Approval recommendation: approve the completed implementation.** The six
required contracts below are implemented, the review findings are corrected,
and final local validation passed on unchanged source. No known blocking finding
remains. Parent approval remains the gate for committing, pushing and marking
the PR ready. This review covers the extension in
`nimkit-css-layout-plan.md`, not the already approved CSS styling scope recorded
in `nimkit-css-plan-review.md`.

The architecture is appropriate: immutable value specifications compile
to generated native constraints, CSS never edits authored constraints or widget
backing fields, and container layout remains native. The plan-stage contracts
below record the original static source traces and required corrections. Runtime
evidence is recorded separately in the implementation review and final validation.

## Required contracts

1. **Keep CSS anchors in authored coordinate space.** Existing generated terms
   use the local-coordinate `expressionFor` path
   (`view/viewconstraints.nim:1356`), whereas authored anchors use
   `constraintExpressionFor` (`view/viewconstraints.nim:1207`) to account for
   ancestor alignment insets, bounds origins and flipped coordinates. Give
   `lisCss` equations that authored-coordinate path explicitly. Do not change
   the expression semantics of native autoresizing equations. Percentages use
   the corresponding parent alignment dimension. Test nested origins and
   flipped parents, sibling baselines and parent resizing against equivalent
   native anchors.

2. **Reconstruct CSS participation on every solve and invalidate dependent
   caches.** `collectConstraintItems` reconstructs only authored participation;
   intrinsic and autoresizing generators use that participation to choose which
   equations exist. Replaying cached CSS equations alone is insufficient.
   Resolve or replay eligible CSS subjects before those generators. Only the
   equation's styled left-hand subject becomes CSS-controlled; a named sibling
   on the right retains its native autoresizing. Define CSS participation from
   eligible, target-resolved, nonempty specifications, including the case where
   required equations later conflict. Missing targets, `auto`/`none`, and
   container/root exclusions must not accidentally suppress native geometry.
   A changed subject set must rebuild dependent autoresizing/intrinsic inputs.
   `sourceFor` currently maps appearance and container metrics only to
   `lisIntrinsic` (`view/viewgeometry.nim:115`); add explicit CSS dirty-source
   propagation for identity, classes, effective states, appearance, hierarchy,
   target identity, relevant geometry and managed-child membership. Cached
   references must use the existing weak ownership model. Preserve native cache
   behavior when no CSS layout is present.

3. **Specify admission, conflicts and budgets.** Install native root geometry,
   authored constraints and nonnegative-size invariants before CSS. The existing
   `addSolverConstraint` swallows `UnsatisfiableConstraintError`
   (`view/viewconstraints.nim:1299`), so CSS needs a narrow admission path that
   returns a conflict diagnostic without changing native failure behavior or
   swallowing budget exceptions. Standard width/height should be preferred
   equalities at priority 999; min/max dimensions and pins are required. This
   makes `width: 25%; min-width: 120px` clamp and allows opposing pins to determine
   size. Explicit constraint-list entries default to required and retain their
   declared priority. CSS importance selects declarations independently of
   solver strength. Document deterministic admission order between bounds,
   pins, preferred sizes and explicit list entries; never depend on table order.
   Define whether a runtime-invalid list entry skips only itself; compile-time
   malformed lists should be rejected atomically. Check time and allocation
   budgets during target resolution and equation generation, as well as solver
   admission: the current memory estimate counts admitted constraints, not an
   arbitrarily large pending generated-input list. Preserve rollback of caches
   and frames on budget failure.

4. **Isolate fitting and layout semantics.** `fittingSize` shares the root's
   generated-input cache and retains changes on success
   (`view/viewconstraints.nim:1700`); the cache is not keyed by solve mode. Root
   dimension declarations may participate in fitting but are excluded during
   layout. Make eligibility and subject participation correct in both modes,
   using scratch generation, mode-aware caching, or an equally explicit bounded
   mechanism. Test both layout-then-fitting and fitting-then-layout, including
   clean caches, CSS removal and repeated measurements. A fitting root cannot
   target a parent/sibling outside the collected solve tree. Specify diagnostic
   ownership and lifetime: fitting must not unexpectedly erase the last layout
   diagnostics, and a failed/budgeted attempt must not publish partial success.

5. **Cover managed subjects and managed targets.** The constraint solve precedes
   container callbacks (`view/views.nim:310`), so a container-managed sibling
   used as a right-hand target can move after the CSS solve just as a managed
   subject can. Reject those targets with a diagnostic for this increment, or
   supply an explicit same-pass ordering contract. The bounded rejection is
   sufficient. The ownership hook must cover each existing owner that actually
   assigns child frames, including Stack/Grid arranged children, Box content,
   ScrollView internal children/document geometry, TabView selected content and
   tab bar, SplitView panes, and any composite control layout found in the audit.
   Ordinary additional subviews remain eligible. Define the policy for measuring
   a managed child as a fitting root. Thread one plain resolved container-style
   value through both natural sizing and actual arrangement; existing Stack/Grid
   helpers read backing fields throughout, and their `sizeThatFits` calls do not
   invoke the constraint solver. Resolve row/column gap using physical axes after
   Stack orientation, with documented shorthand precedence. Do not introduce a
   solver call from intrinsic measurement to compensate for managed geometry.

6. **Keep syntax and expanded properties concrete.** Specify percentages as
   literal width/height values only, including valid zero percent; scalar
   variables retain typed provenance and are converted per target key. State
   whether mixed `auto` components are accepted by inset shorthands. Retain
   immutable deep copies for constraint lists and IDs, native override layering,
   and invalid-variable fallback across stylesheet appends. Publish an exact
   property-to-StyleKey/consumer table for the additional NimKit declarations,
   with their keyword sets, ranges and metric-state dependencies. Cover list
   delimiters, operators, signed values, priorities, unsupported functions and
   malformed nested input in the Stylus safety-adapter termination tests. Keep
   unsupported constructs diagnosed rather than partially accepted. New protocol
   implementations must leave unused named parameters unused, without dummy
   `discard parameter` statements, as requested by the user.

## Acceptance checks

- Pins and percentage sizes agree with equivalent native anchors; required
  native constraints remain installed, CSS conflicts are deterministic, and
  negative size expressions cannot displace nonnegative invariants.
- Styles added, replaced and removed change only generated CSS inputs. Repeated
  clean solves settle; native source generations and autoresizing behavior stay
  unchanged in unstyled trees. Renaming/removing/reparenting a target and changing
  managed membership invalidates the correct equations without retaining Views.
- Cached CSS subjects continue suppressing their own default autoresizing;
  referenced unstyled siblings keep theirs. Invalid or cleared declarations
  leave native fallback geometry available under the documented policy.
- Fitting/layout order, root exclusions, target errors, diagnostic defensive
  copies and budget rollback are exercised through the shared NimKit runner.
- Stack/Grid styled natural sizes and arranged frames agree after orientation,
  gap and inset changes; replacing CSS restores current native setter values.
  Managed-subject and managed-target behavior is tested against actual owners.
- Newly exposed feature keys are exercised through real resolver/render/layout
  consumers. Parser tests run under an external deadline. The demo and shared
  example bundle compile, and the coordinated shared-runner validation records
  actual local results without implying CI has passed.

No browser positioning model, generic tree selector engine, global ID search or
new reactive scalar state is required. The added contracts keep the extension
within NimKit's existing layout model and preserve the earlier CSS approval.

## Revised-plan decision

The revised plan generates CSS inputs from scratch on each actual solve and
rebuilds dependent native inputs whenever current or previously accepted CSS
geometry requires it. Cached CSS equations are inspection records rather than
mode-dependent input. Diagnostics are separated by solve mode. When all CSS
equations for a subject are rejected, admission retries monotonically remove
that subject and rebuild native participation under the same overall deadline
and budgets. This is an explicit, bounded way to preserve native fallback
geometry without changing authored constraints or backing fields.

The plan also now specifies authored-coordinate equations, deterministic
admission, preferred width/height at priority 999, generation-budget checks,
managed-target rejection, atomic malformed-list rejection, mixed `auto` insets,
zero percent, resolved container-style values, and the required acceptance tests.
No architectural blocker remains.

Two implementation cautions were sent with approval: preserve the existing
native-only insertion order when CSS is absent; placing invariants before CSS
does not require changing how contradictory authored native constraints are
handled. State percentage support explicitly as width/height only, excluding
min/max, to match the chosen bounded syntax. Implementation review will verify
these details alongside the contracts above. No implementation or runtime test
results are claimed by this plan approval.

## Implementation review decision

The source, consumer corrections, guide and demo have been rechecked, with no
remaining known source blocker. Final validation is complete as recorded below.
The initial source review found the following issues and sent
them directly to the worker. These are traced findings; no new runtime
reproduction claim is made here.

1. Admission retries recreated `LayoutSolveState` and retained only its start
   time, resetting constraint/coefficient accounting on every retry. Preserve
   cumulative work counters across fresh solvers while keeping active-memory
   accounting meaningful. Exercise a conflict that requires a retry with a
   budget small enough to distinguish cumulative from per-pass accounting.
2. `layoutConstraintCount` called the full `ruleValue` resolver before checking
   the projected budget, copying/validating the list it purported to count
   before allocation. Select borrowed immutable declaration metadata, guard its
   count, then copy/validate with deadline checks. Successful fitting should
   restore the previous layout cache so fitting-native inputs do not leak into
   later layout cache reuse.
3. `-nimkit-selection-indicator-radius` used the key
   `selection.indicator.cornerRadius`, whereas the exported key and DocumentTabs
   renderer use `selection.indicator.corner.radius`. The accepted declaration
   therefore had no effect on its intended consumer.
4. MenuBar's layout callback assigns its internal button frames, but the new
   ownership hooks initially omitted MenuBar. Its own semantic layout context
   and PopupMenuButton's drawing roles were also missing. TableView's ownership
   hook replaces the base Control hook and must retain ownership of its current
   field editor, including editors hosted in an internal row. Audit concrete
   owners and contexts; do not substitute a shared subclass switch.
5. `scrollViewRole=` and `collectionRole=` initially invalidated display only.
   These setters now change `layoutStyleContext`, so they must invalidate the
   appropriate layout/metric inputs. Similarly, exported native state layout
   rules are consumed by the solver, but the initial dependency flags considered
   only CSS-origin rules. Track layout-key state dependencies across origins
   (including the new container metric keys) without broadening unrelated native
   styling behavior.
6. **Confirmed by the implementation worker's regression:** finite parser inputs
   can overflow the final float32 geometry after Kiwi's
   float64 solve: a 400-pixel parent with `width: 1e38%`, for example, requests a
   width above float32's finite range. The initial `solvedFloat`/fitting path
   converted directly and only clamped negative dimensions. CSS attempts must
   reject nonfinite solved geometry with diagnostics and preserve prior finite
   frames/fitting fallback, without altering the native-only path.
7. The borrowed selection path deliberately rejected CSS scalar variables that
   resolved to native constraint-list tokens, but compile-time typed validation
   initially accepted them. Align the two paths: CSS scalar variables diagnose
   this wrong type, while native constraint-list tokens remain supported.

The worker owns test compilation and execution. Fixture corrections were also
sent: count equations in the aggregated CSS input summary, and keep Grid inset
expectations in top/right/bottom/left order. No broad local test build was started
by the reviewer during this parallel review.

The corrected source now separates cumulative work budgets from active-memory
estimates, borrows list metadata before allocation, restores fitting caches,
preserves native layout/container state dependencies, and includes the missing
roles, ownership hooks and role-setter invalidation. Radius mapping matches its
DocumentTabs consumer. Finite-result guards validate raw dimensions and derived
frame edges, roll back failed attempts and retain actionable diagnostics. The
scalar-variable/list-token mismatch is corrected as well. `git diff --check`
passed during this source review.

The final focused run passed all 54 CSS cases (22 original styling cases and 32
layout/control cases), with exit status 0 under an external 60-second process
deadline. This includes overflow rollback, live Table metrics, delegate-backed
row-height/offset cache updates and bounded pinstripe rendering. The reviewer
checked the worker's log and confirmed 54 `[OK]` results and no failures.

## Documentation, demo and consumer audit

The expanded guide describes the geometry syntax, cascade, container ownership,
fitting isolation and budget contracts accurately. The subsequent consumer audit
identified these additional corrections, now rechecked in source and covered by
the final passing runtime validation:

- The demo stylesheet used `switch-button`, but the supported role is `switch`.
  Validate the checked-in stylesheet through the parser; compiling the Nim demo
  alone does not exercise its runtime CSS file. The status label also needs
  padding/height consistent with its font so diagnostics remain readable.
- Tiny positive pinstripe period and height values are accepted by the new CSS
  properties, while `addRootBackgroundPinstripes` uses an unbounded floating-point
  increment loop. A normal root with `1e-12px` stripe metrics can generate
  excessive nodes and eventually cease advancing. Bound rendering work and
  numeric progress, and exercise it under a process deadline. Document that these
  properties affect themed root backgrounds.
- Table row/header heights and column width/min/max are copied from theme
  defaults into backing fields only during construction. The new CSS properties
  initially changed resolver values without changing actual Table geometry after
  installation/reload. Either provide real resolved fallbacks with explicit
  native precedence and cache tests, or diagnose those properties as unsupported
  and remove the live-widget claims. Resolver-only tests do not establish the
  advertised behavior.

These findings were sent to both the worker and parent before final approval.

The demo now uses `switch`, gives the status label suitable padding/font size,
and has a fixture that parses the checked-in stylesheet and exercises its panel
constraints. Pinstripe rendering uses a minimum/adaptive pitch, a maximum of
4096 bands and a numeric progress check; the guide documents this bound and
root-background scope.

The final Table contract supports live row/header defaults while explicit native
setters remain authoritative, including same-value assignments. Plain flags
record that precedence, and a resolved-default stamp invalidates the variable
row-height cache after stylesheet/state changes. Native per-row/delegate heights
retain precedence. The column width/min/max properties are deliberately excluded
and diagnosed rather than accepted without an effect; their full model/sizing
precedence is outside this increment. This is an approved bounded scope correction
to the original property list. Actual row/header geometry, reload and native
precedence tests accompany it. The added delegate-backed fixture checks actual
row heights and later-row offsets across initial CSS, hover and stylesheet reload
while preserving an explicit delegate height for the first row. It exercises the
variable-height cache rather than only the fixed-height fast path.

The final guide also states the minimum accepted width/knob factors and makes
clear that deterministic CSS admission order applies within each subject visited
in solve-tree traversal order. The latest reviewed diff passes `git diff --check`.

## Final validation and approval

The worker completed validation without further source changes. The reviewer
inspected the focused, shared-runner, example and IC-attempt logs and checked the
final validation section of the plan:

- Focused CSS coverage: 54/54 cases passed under an external 60-second deadline.
- `atlas-run tests --stats`: all four shared runners passed in one run, with
  1772 cases and zero failures (NimKit 1206, Kosmo 371, integrations 153,
  Tekton 42). The existing resource-lifetime integration test passed on this run.
- `atlas-run tests --compile-only --stats examples/css_theme_demo.nim
  examples/all_compile.nim`: both examples compiled successfully; neither was
  executed. The log records compile-only commands and `2/2 compiled`.
- Touched Nim files were formatted with nph; `git diff --check` passed. The
  worker's final audit reports no added dummy argument discards or lockfiles;
  Stylus remains exactly 0.1.5 and the named tokenizer character set is retained.

The final passing results use stable Nim's C backend. The preferred Atlas IC
demo compile-only attempt did not complete within its external 120-second
deadline; the worker terminated its process group. Its log has no source
diagnostic. Earlier IC scheduler errors are recorded in the original CSS plan.
This limitation is disclosed rather than counted as a successful IC check; CI's
backend and Atlas job/cache settings were not changed.

On this evidence, the expanded implementation is approved for the parent's final
commit/push/readiness decision. These are local results, not a claim that GitHub
checks have passed for the expanded commit.
