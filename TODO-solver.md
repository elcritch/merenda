# TODO: Bound and reduce NimKit layout solver work

## Why this matters

The layout solver can make the application unresponsive when a large view
subtree enters one solve. A captured Kosmo process reached roughly 31,858 views,
249,000 solver rows/constraints, and more than 120,000 variables while the main
thread remained in `addConstraint`, `substitute`, and `optimize`. The temporary
solver also retained large sorted sequences and repeatedly scanned the whole
tableau.

The solver must fail safely under excessive work, and ordinary layouts should
avoid putting unrelated views into the same problem.

Relevant code:

- `src/merenda/nimkit/view/viewconstraints.nim`
- `src/merenda/nimkit/view/viewgeometry.nim`
- `src/merenda/nimkit/view/views.nim`
- `deps/kiwiberry/src/kiwiberry/solver.nim`
- `deps/kiwiberry/src/kiwiberry/internal/rows.nim`
- `deps/kiwiberry/src/kiwiberry/internal/cellmaps.nim`

## 1. Add a bounded layout solve

### Solver budget

Introduce a private or public budget object shared by one complete layout
attempt. It should contain:

- a monotonic deadline or elapsed-time limit;
- a maximum number of participating views or variables;
- a maximum number of input and generated constraints;
- a maximum number of stored row coefficients;
- operation counters for row visits, coefficient operations, and pivots;
- the owning subtree or diagnostic name for reporting.

Use counters on hot paths and check the deadline periodically. Check inside
large row substitutions and row merges as well as between pivots. A check only
between calls to `addConstraint` is insufficient because one substitution can
visit the entire tableau.

Do not choose universal limits without measurements. Instrument representative
windows first, then provide conservative interactive defaults and a way for
tests to use deterministic tiny budgets.

### Abort semantics

Add a catchable `SolverBudgetExceededError` (or an equivalent structured
outcome) separate from unsatisfiable-constraint errors. The budget failure must
include the limit that fired and useful counts.

Treat an interrupted solver as invalid. Do not resume it after an interruption:
the solver may be midway through a pivot, substitution, or artificial-variable
operation.

`applyConstraintsForSubtree` already builds a temporary `LayoutSolveState` and
only applies frames after `updateVariables`. Preserve that transaction shape:

1. collect and validate the solve inputs;
2. build and solve temporary state;
3. collect solved frames without mutating views;
4. commit all frames only after the solve succeeds;
5. update layout caches only after the commit succeeds.

On budget failure:

- discard the temporary solver;
- leave all existing view frames unchanged;
- leave generated-input caches and autoresizing references in a consistent
  pre-solve state, or explicitly invalidate them for a later retry;
- record a diagnostic with the subtree, counts, and limit;
- avoid turning the same failed input revision into a busy retry loop.

`fittingSize` needs the same budget. It must return an explicit failure or a
documented cached measurement; silently returning zero can collapse a layout.

### Suppress repeated failed attempts

Record the input revision that exceeded its budget, separately from the layout
pass generation. If the same hierarchy, constraints, and size inputs are
requested again, skip the expensive retry and retain the last successful frames.
Clear the suppression when relevant inputs change or the budget changes.

Make sure a suppressed solve does not leave `xNeedsLayout` or constraint-dirty
state permanently driving every frame. Keep enough state to distinguish a
pending legitimate change from an unchanged failed attempt.

### Diagnostics and tests

Expose a debug diagnostic containing at least:

- participating view count;
- authored, generated, and total constraint counts;
- variable count;
- row/coefficient count and peak row size;
- row visits, coefficient operations, and pivots;
- elapsed time and the limit that fired;
- the root and largest participating subtrees.

Add deterministic tests for:

- timeout and count-limit interruption;
- unchanged frames after interruption;
- no repeated retry for an unchanged failed revision;
- retry after a relevant hierarchy or constraint change;
- `fittingSize` failure behavior;
- unsatisfiable constraints remaining distinct from budget exhaustion.

## 2. Reduce the solve problem before optimizing the solver

### Replace repeated view searches with an index

`ensureSolverView`, `hasSolverView`, and `addConstraintItem` currently scan
sequences of views. At tens of thousands of views this turns input collection
into repeated linear work.

Keep the sequence for stable iteration, but add a temporary identity index from
`View` identity to solver-view index. Use it for all membership and lookup
operations. Keep a separate indexed set or flag for constraint participants.

The index is valid only for the lifetime of a temporary solve unless the
ownership and removal rules for a persistent cache are designed explicitly.

### Give containers an explicit layout ownership boundary

Every descendant currently receives solver variables, nonnegative-size
constraints, and weak geometry stays. This is unnecessary for views whose
container already computes their frames directly.

Add a container policy that distinguishes:

- children positioned by the container’s own layout code;
- children participating in authored constraints;
- children contributing intrinsic size to the container;
- children whose geometry is exported to another constraint group.

The Git diff document is an important use case: it positions rows manually, so
collapsed or manually laid-out file sections should not enter the window-wide
constraint system merely because they are descendants.

The boundary must have a precise contract. A child can remain outside the
parent solve only when no active authored or generated equation requires that
child’s geometry to be solved by the parent. A cross-boundary constraint must
pull both endpoints into a shared group or turn the boundary geometry into an
explicit input.

Do not use `hidden` as the only participation rule. Hidden views can still be
constraint endpoints or affect intrinsic sizing according to container policy.

### Build independent constraint groups

After collecting actual authored and generated equations, build a dependency
graph over solver variables. Variables appearing in one equation belong to the
same connected component. Solve each component independently when possible.

Account for the ancestor terms introduced by `constraintExpressionFor`; grouping
by view hierarchy alone will miss cross-container dependencies. During ordinary
layout, fixed parent geometry can be folded into constants. During fitting-size
calculation, unresolved parent dimensions must remain variables.

Independent groups provide three benefits:

- smaller tableaux and lower peak memory;
- dirty updates limited to affected groups;
- one pathological group cannot prevent unrelated groups from laying out.

If a group exceeds its budget, retain successful frames from other groups and
report the failed group.

### Avoid unconditional geometry stays

`addGeometryStays` adds four weak constraints for every non-root solver view.
Replace this with a policy:

- add a stay only for a view whose prior geometry is a required fallback;
- omit stays for views with enough required equations to determine the axis;
- omit them for container-owned frames that are already committed;
- preserve stays where they are needed to make under-constrained behavior
  stable.

Measure the resulting behavior carefully. Stays affect the chosen solution, so
this is a semantic change and needs layout regression tests.

### Make generated inputs participate selectively

Intrinsic-size and autoresizing equations are currently collected over the full
subtree. Generate them only for views that can affect the current group. Cache
the generated input revision per view and invalidate only the affected group
when intrinsic metrics, container metrics, or hierarchy changes.

Do not clear every descendant cache after every solve unless the dependency
model requires it. The current broad reset in `refreshLayoutInputCaches` can
force later full regeneration.

## 3. Improve Kiwiberry’s hot operations

### Index rows by symbol

`Solver.substitute` currently walks every row to find rows containing the
substituted symbol. Maintain a reverse index:

```text
symbol -> rows containing that symbol
```

Update it whenever a coefficient is inserted, changes to zero, or is removed,
and whenever a row is pivoted or deleted. Include the objective and artificial
objective in the accounting where applicable.

Then substitution can visit only affected rows. The same index can narrow
leaving-row searches, but it must preserve deterministic pivot selection.

Use compact storage for small membership lists; a heavyweight set per symbol
could trade CPU savings for more memory.

### Merge sorted coefficient sequences

`CellMap` and `AssocMap` keep sorted sequences, while insertion repeatedly
searches and shifts elements. Row insertion currently adds each coefficient
individually.

Add a bulk merge operation for two sorted coefficient lists. Combine duplicate
symbols and remove near-zero coefficients during the merge. This makes row
substitution proportional to the input and output row sizes rather than paying
for repeated sequence shifts.

Preserve the existing ordering and pivot tie-breaking rules. Add solver tests
for duplicate terms, near-zero cancellation, and deterministic dumps.

### Track useful size metadata

Maintain row coefficient counts and peak row size in the solver budget and
diagnostic path. This makes dense-row blowups visible and allows the budget to
stop before allocator growth becomes the dominant cost.

## 4. Consider persistent incremental solver state after the guards

Kiwiberry supports adding/removing constraints and edit-variable suggestions,
but NimKit currently rebuilds a solver for every dirty subtree.

After participation boundaries and group construction are stable, retain a
solver context per group:

- keep variable and constraint handles for stable views;
- replace only the intrinsic or autoresizing constraints whose inputs changed;
- update boundary geometry through a small set of edit values or replacement
  constraints;
- rebuild a group when its hierarchy or cross-group edges change.

Do not store a persistent state that strongly owns every view through its
`SolverView` entries without a removal strategy. It could keep detached view
trees alive. Use explicit group membership cleanup and release variables for
detached views.

If an incremental update exceeds its budget, invalidate that group’s solver,
keep its last committed frames, and rebuild it during a later permitted
attempt.

## Suggested implementation order

1. Add instrumentation and deterministic budgets to Kiwiberry.
2. Add NimKit failure handling, frame commit staging, diagnostics, and retry
   suppression.
3. Replace linear view lookup with an identity index.
4. Add layout ownership boundaries and exclude container-owned descendants where
   the contract permits.
5. Build dependency groups and solve them independently.
6. Remove unnecessary geometry stays and narrow generated-input invalidation.
7. Add the reverse row index and bulk coefficient merges in Kiwiberry.
8. Evaluate persistent incremental solver contexts after measurements show the
   rebuild cost is still material.

Each stage should compare solved frames against the existing fresh full solve,
record peak memory and operation counts, and run focused layout tests plus the
full Atlas test suite.
