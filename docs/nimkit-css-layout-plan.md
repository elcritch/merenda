# Extended CSS control styling and layout

Status: Implemented and locally validated on PR #152; final Astra review recorded
in `nimkit-css-layout-plan-review.md`. Stylus remains exactly 0.1.5; the original
theme/cascade contract remains in force.

## Existing APIs and scope

NimKit has a Kiwi-based constraint solver, typed horizontal/vertical/dimension
anchors, equality and inequality relations, priorities, alignment rectangles,
intrinsic sizes, autoresizing inputs and generated-input caches. `pinEdges`
already expresses edge constraints. StackView and GridView arrange child frames
in their own layout callbacks; their spacing, insets and alignment are ordinary
backing fields behind validated setters. Theme styles already expose many more
control-specific keys than the initial CSS parser does.

Extend those existing mechanisms. Keep parser/layout specifications as plain
values and immutable Theme data. Do not create a browser layout engine or mutate
widget backing fields when an appearance is installed. Existing property setters
retain their hooks and provide fallbacks for styled values.

## CSS syntax

Standard `width`, `height`, `min-width`, `min-height`, `max-width`, `max-height`
generate dimension equality/inequality constraints. Width/height are preferred
equalities at priority 999; min/max bounds and edge pins are required. Thus a
percentage width clamps to its minimum and opposing pins can determine the size.
Width/height literals
also accept percentages relative to the parent's corresponding dimension.
`auto` clears that property. Literal lengths and `var(--length)` use logical
pixels. Percentages are supported only for width/height, not min/max bounds or general
token substitution, padding or font sizes.

`top`, `right`, `bottom`, `left` pin matching parent edges; right/bottom use
negative inset constants, as `pinEdges` does. `inset` and `-nimkit-pin-edges`
expand 1–4 lengths or mixed `auto` components in CSS top/right/bottom/left order.
Each edge accepts `auto` to release it. Insets permit signed lengths; sizes do
not. Zero percent is valid and becomes a constant zero dimension. Coordinates follow
NimKit's anchors/alignment rectangles, including bounds offsets and flipped
coordinate spaces. They do not introduce browser positioning modes.

```css
.content { -nimkit-pin-edges: 12px 20px; }
#toolbar { left: 16px; right: 16px; top: 12px; height: 36px; }
#sidebar { left: 16px; top: 60px; bottom: 16px; width: 25%; min-width: 120px; }
#editor {
  right: 16px; bottom: 16px;
  -nimkit-constraints: left == #sidebar.right + 12px,
                       top == #toolbar.bottom + 12px,
                       width >= 180px priority(750);
}
.preview { -nimkit-constraints: width == self.height * 1.5; }
```

`-nimkit-constraints` is a comma-separated list. `none` clears the list. Each
entry has this bounded grammar:

```
attribute (== | = | >= | <=)
  (length | target.attribute [* number] [(+ | -) length])
  [priority(required | high | low | fitting | number)]
```

Attributes: left/right/leading/trailing/center-x, top/bottom/center-y,
first-baseline/last-baseline, width/height. Targets: `parent`, `self`, and
`#styleId` among direct siblings in the same superview. IDs are case sensitive;
missing or duplicate siblings are diagnosed rather than choosing an arbitrary
view. Constant RHS values require a dimension LHS. Axis categories must match;
dimension-to-dimension ratios are allowed. Multipliers must be finite and
positive and only apply to dimensions. Priority numbers must be within 1–1000;
named priorities map to the existing native constants. Default priority is
required. `!important` controls the CSS cascade independently of solver priority.
Root variables work for scalar size/inset declarations; expressions inside the
constraint list use literal terms in this increment and reject `var()`/`calc()`.
A winning constraint-list declaration replaces the previous list; individual
width/edge properties participate in their own per-key cascade.

## Representation and runtime integration

Add plain `StyleLayoutConstraint`/target enum data and an `svConstraints`
StyleValue variant in themecore. Specifications contain attributes, relation,
target/id, multiplier, constant and priority, never View refs. Scalar layout
declarations compile to per-property keys with this value; `svLength` variables
coerce to one specification according to the key. Empty lists represent `auto`
or `none`. Cloning must deep-copy lists and target IDs; public defensive rule
accessors and builder round trips retain independent snapshot ownership.

Add a narrow optional `layoutStyleContext` protocol hook. Default Views use
srView/id/classes/current widget states; concrete widgets provide their own
semantic role and effective states in their owning module. Add srStackView and
srGridView roles. No central subclass checks and no ref-wrapped property state.

Layout solving resolves the effective appearance/context for each view and
creates temporary generated equations under a distinct `lisCss` source. Its
equation path explicitly uses `constraintExpressionFor`, accounting for ancestor
bounds origins, alignment insets and flipped spaces. Native generated equations
keep their local-coordinate path. Resolve only eligible, nonempty, target-valid
subjects; never mark RHS targets CSS-controlled. Do not change the native
autoresizing flag or authored constraint collections.

Keep the existing native insertion order: root geometry, authored constraints,
native generated inputs, then nonnegative-size invariants. Install CSS afterward. Generate intrinsic/autoresizing inputs with
the eligible CSS subject set. Admit CSS in this stable order: minimum width and
height, maximum width and height, left/top/right/bottom pins, preferred width and
height, then explicit list entries in their declared order. Use a narrow solver
insertion path that diagnoses UnsatisfiableConstraintError and propagates budget
exceptions; preserve the existing native insertion path. A runtime-invalid list
entry skips itself; a malformed list is rejected atomically by the compiler.

If every equation for a subject is rejected, restore native participation by
excluding that subject's CSS and rebuilding the temporary solve from scratch.
Repeat with a monotonically shrinking CSS subject set until it settles; use one
overall deadline and the existing solve budgets across retries. This preserves
native autoresizing for rejected subjects and referenced unstyled siblings,
including when restored native inputs invalidate a previously admitted CSS
relation. Retain actionable rejection diagnostics. No partially solved frames
or caches are committed during these admission retries.

CSS generation is scratch work on each actual solve, so fitting and layout do
not reuse mode-dependent CSS eligibility. Keep the last accepted layout CSS equations
in the generated-input inspector/cache only as a record, not as the source for
the next solve. Successful CSS fitting solves restore the layout cache, including
native generated inputs, so measurement never replaces that record. Rebuild native intrinsic/autoresizing inputs whenever scratch
CSS subjects are present or the previous CSS record was nonempty. Native trees
without current/previous CSS geometry keep their existing cache fast path.
Check time during each target lookup and spec iteration; check projected
constraint/coefficient/memory budgets before cloning a resolved constraint list
or allocating equations, then check normal insertion budgets as well. Roll
back caches and retain current frames if the overall attempt exceeds a budget.

Record plain `CssLayoutDiagnostic` values on the solve root and expose
`cssLayoutDiagnostics(view, fitting = false)` as a defensive value accessor.
Store the latest attempt's diagnostics separately for layout and fitting;
fitting never erases useful layout diagnostics. Failed/budgeted attempts report
their failure without presenting admitted partial inputs as success. Include the styled
view's id and property plus an actionable message. Compile-time syntax errors
remain ordinary source-located CssDiagnostics. Runtime diagnostics cover missing
parents/targets, duplicate IDs, and solver conflicts. Root geometry remains owned
by the solve root/window during layout; root geometry declarations are skipped
with diagnostics, while fitting solves may use root dimension constraints.
A container-managed child measured as a fitting root may use its own dimension
constraints; pins and references outside that collected solve tree are rejected.
Root positions remain fixed in both modes.

CSS inputs are regenerated when identity/classes/state/appearance, intrinsic
metrics, hierarchy, target identity, managed-child membership or geometry changes
trigger a solve through the existing dirty-input events. Scratch generation and
native-source rebuilds make this explicit rather than relying on adding lisCss
to the source enum alone. Extend metric-state
flags for layout and newly exposed metric properties, preserving the native fast
path without CSS. Removing/replacing CSS drops only generated inputs and lets
native autoresizing/intrinsic/stays resume from current geometry. It does not
restore pre-CSS frames; geometry is a result, not a backed-up mutable property.
Refreshes must settle without feedback loops or retaining target Views.

Arranging containers retain ownership of child frames. Add a narrow owner hook
looked up through ancestors that identifies the exact managed subviews and
internal descendants; skip CSS geometry on those children and report
it rather than solving a frame that a later container callback overwrites.
Reject managed RHS targets as well: they can move during later container layout
callbacks and would otherwise leave a stale relation. The ownership hook covers
the actual arranged/content/internal children of native container and composite
control owners identified in source. StackView/GridView constraints style the container itself; their arranged child
layout is controlled through the container properties below. Ordinary additional
subviews remain eligible. Apply the hook to existing native container owners as
appropriate after tracing their layout paths.

## Additional NimKit feature coverage

Expose the existing theme keys with descriptive `-nimkit-*` declarations:

- Colors/fills: selection, cursor, text highlight/shadow, mark, knob face/border,
  highlight/maximum highlight, alternating rows, indicator/drop/insertion,
  column selection/hover, selection indicator, root background pinstripes.
- Metrics: indicator size/spacing, width factor, knob size/inset/size factor/tint,
  edge inset, item gap/overlap, live row/header height,
  resize handle width, drag threshold, autoscroll edge, title height/gap,
  separator thickness, pinstripe period/height.
- Compound values: maximum size, segment size, selection indicator insets,
  knob shadows. Keyword enums: selection indicator position and close button
  position; language strings. Validate documented keywords, finiteness, signs,
  and ranges appropriate to each target. Preserve per-declaration shorthand
  importance and typed-variable fallback/revalidation.

StackView/GridView gain CSS resolution without mutating their backing fields:
`gap`, `row-gap`, `column-gap`, `-nimkit-content-insets`, `-nimkit-orientation`
(horizontal/vertical), `-nimkit-alignment` (fill/leading/center/trailing), and
`-nimkit-distribution` (fill/fill-equally/natural/equal-spacing) for StackView;
GridView supports gap directions, insets and per-axis alignment extensions.
Resolve one plain container-style object and pass it through all helpers for
each natural-size or arrangement operation. These values feed both
natural/intrinsic sizing and actual layout. `gap` expands to row/column keys;
longhand precedence follows the normal declaration cascade. Physical row gap
is vertical, column gap horizontal; StackView chooses its main-axis gap after
resolving orientation. Existing
native getter/setter values remain the fallbacks, so replacing CSS restores them.

Table row/header defaults resolve live through their getter boundaries until a
native setter explicitly supplies a value; per-row overrides and delegate values
keep precedence. A cache stamp tracks default-row-height changes. Column
width/min/max properties are deliberately rejected in this increment because
their constructor/model/resizing paths store native state. Root pinstripe
rendering bounds pitch and count to prevent tiny metrics causing unbounded work.

Other controls consume their existing resolved keys; no CSS event/actions,
bindings, resources, content, accessibility identity or model mutation is added.
The guide includes property-to-consumer tables so unsupported widget behavior
is not implied. Ordinary Views gain constraint geometry but not control chrome.

## Implementation organization and verification

Keep tokenization/parsing in cssthemes. Extract declaration value parsing into
one cohesive helper module if necessary to share tokens and avoid growing the
existing parser driver; keep internal token types private to the parser package.
Put layout resolution and generated equation orchestration beside the existing
constraint solver, with explicit state passed by var. New structs are plain
objects; only Views and native LayoutConstraints have identity.

Add meaningful cases to the shared tests/nimkit/cssthemes.nim module (or a second
NimKit test module imported by tests/tnimkit.nim if the layout fixture merits it):
pins/1–4 inset expansion, auto/none release, dimensions/percentages/min/max,
sibling anchors/ratios/priorities/baselines, authored-constraint preservation,
runtime target/conflict diagnostics, variable coercion/fallback/appends,
state/appearance/class/id changes, parent resize/bounds offsets/flipping,
reparenting, CSS removal, cache settling and target lifetime. Verify Stack/Grid
styled intrinsic and arranged geometry plus original native setter fallbacks.
Exercise the new extension keys through concrete resolver/render/layout consumers
and malformed values with process deadlines for parser tests. Add both
fitting→layout and layout→fitting checks, root exclusion/measurement policy,
required-conflict fallback, managed RHS rejection, per-mode diagnostic lifetime,
projected generation-budget and failed-solve rollback cases.

Extend the public demo to show a CSS-pinned toolbar/sidebar/editor and styled
Stack/Grid controls, plus existing live reload and visible diagnostics. Update
the guide, README and CHANGES. Format touched Nim files with nph. Prefer IC for
focused checks, document/reuse the known compiler-scheduler fallback if needed.
Coordinate the broad Atlas shared-runner and compile-only example validation
with the terminal worker to avoid concurrent integration process tests. Get the
existing Astra xhigh reviewer to approve this plan, then review implementation
and corrected findings before committing/pushing and marking PR #152 ready.
Leave unused named parameters unused; do not add dummy `discard parameter`
statements. This user convention also applies to protocol hooks and examples.

## Completed validation

- Stable Nim 2.2.12 compiled the shared NimKit runner. A focused run under an
  external 60-second deadline passed all 54 CSS cases: 22 original theme cases
  and 32 new layout/control cases. This includes real Table row/header geometry,
  native setter precedence, delegate-backed row-height/offset cache updates,
  bounded pinstripe rendering, and parsing/layout of the checked-in demo CSS.
- `atlas-run tests --stats` passed all four shared runners in one run, with
  1772 cases and no failures: NimKit 1206, Kosmo 371, integrations 153, Tekton 42.
  The existing resource-lifetime integration test passed on this run.
- `atlas-run tests --compile-only --stats examples/css_theme_demo.nim
  examples/all_compile.nim` compiled both examples successfully. Neither program
  was executed by this check.
- The repository's IC compiler was attempted through Atlas for the CSS demo
  compile-only check. It did not complete before the external 120-second
  deadline and its process group was terminated; it emitted no source
  diagnostic. The original CSS plan records earlier repeated IC scheduler
  failures. Stable C validation supplies the final results above; jobs,
  nimcache settings and CI backends were unchanged.
- All touched Nim files were formatted with nph, and `git diff --check` passed.
  The named `StylusTokenStartCharacters` set remains intact. The full branch
  diff adds no dummy argument discard statements and no lockfiles.

These are local results. GitHub checks for the expanded commit are tracked
separately from the successful checks on the earlier CSS cleanup commit.

## CI follow-up

The expanded commit's shared CI runners exposed two defects. The examples
cleanup deleted the tracked demo stylesheet (and tracked SVG assets). Replace
the two cleanup commands with a shared helper that retains git-tracked root
example files and the existing Nim-source exemptions, while deleting generated
root files. Verify tracked CSS/SVG and filenames containing spaces in an
isolated filesystem fixture.

The flipped-coordinate test reproduces `InternalSolverError: The objective is
unbounded` with Linux Nim 2.2.10 and CI's `--opt:none` settings. A diagnostic-only
trace in the isolated Linux container shows Kiwi's by-value objective retaining
four cells and constant 24 after the live artificial row changes to six, then
one cell with constant zero. It subsequently selects a stale symbol. Fix this
at the dependency's optimizer by reading the live real/artificial objective
after each pivot. Keep the solver's exception semantics and the CSS regression
unchanged; do not catch or suppress the internal error in CSS.

Keep the dependency correction and a deterministic old-source-failing regression
in an isolated Kiwi branch/draft PR, review them with the existing Astra reviewer,
and pin the reviewed full commit in merenda.nimble through Atlas. Do not edit the
parent's dependency checkout, create lockfiles or change CI compiler settings.
Verify the reduced solver test, the original Linux CSS failure, focused CSS and
the full Linux NimKit runner with Nim 2.2.10, plus relevant stable-C shared
runner checks and dependency tests. Record exact results and distinguish local
validation from the new GitHub checks before committing/pushing the CSS follow-up.

### CI correction validation

The reviewed Kiwi correction and regression are published in
[Kiwi PR #2](https://github.com/elcritch/kiwiberry/pull/2). The manifest pins
`4d273da93f67d8e5d6317898851772b32fa635ec`. A clean Atlas resolution in the
isolated Linux checkout selected that exact commit and Stylus 0.1.5; the host's
linked parent dependency checkout was not changed. Kiwi's own GitHub CI passed.

- The identical new Kiwi regression fails on the old source and passes with
  the correction on Linux Nim 2.2.10, ARC, threads and `--opt:none`. It checks the
  unique optimum and every required equation. Native dependency tests pass on
  Linux and macOS; macOS also passes the JavaScript variables test.
- Rebuilding from the actual Atlas-pinned Linux checkout with CI's settings
  passes all 54 focused CSS cases and all 1200 cases in the Linux NimKit runner,
  with zero failures. The original flipped-coordinate fixture remains intact.
- Stable Nim 2.2.12/C on macOS passes all four shared runners with the fixed
  Kiwi source: 1772 cases, zero failures (NimKit 1206, Kosmo 371, integrations
  153, Tekton 42). The resource-lifetime integration test passes. The old linked
  Kiwi paths were explicitly excluded for this run; generated C confirms that
  the isolated fixed solver and its live-objective flag were selected.
- The CSS demo and example bundle both compile with the fixed dependency;
  neither program was executed. The earlier IC limitation remains documented
  above; the CI backend, Atlas jobs and nimcache settings remain unchanged.
- The cleanup helper passes shell syntax validation and an isolated git fixture:
  tracked CSS/SVG/assets and Nim-source exemptions survive, while generated
  files, including filenames with spaces, are removed. `git diff --check` passes.

These are local follow-up results. The expanded head `23659139` had ten successful
GitHub checks and two failed shared-runner checks; the new follow-up head's GitHub
checks must be reported separately after push.
