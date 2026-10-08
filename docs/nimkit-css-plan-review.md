# CSS theme plan review

Reviewed the proposed plan against NimKit, the local Figuro integration and
the installed Stylus 0.1.5 sources. The architecture and bounded feature set are
appropriate. **Approval recommendation: approve the revised plan for implementation.**
The revised `nimkit-css-plan.md` incorporates all five required contracts below.
No browser layout engine, tree selector matcher or watcher is needed. Parent
approval remains the implementation gate; this review does not approve code that
has not yet been written or verified.

These are plan corrections supported by static source traces, not claims that
the unimplemented feature has already failed runtime tests.

## Required corrections incorporated into the revised plan

1. **Document the Stylus safety adapter and termination tests.** The stock
   `tokenizer.nim` does not advance for `[` or unrecognized punctuation such as
   `!`; `consumeName` loops on backslash/NUL. In addition,
   `consumeQuotedString` does not advance over an apostrophe inside a
   double-quoted string: `font-family: "D'Angelo"` enters an internal loop.
   Checking progress only after `nextToken` returns cannot guard the latter
   cases. Preflight unsupported inputs or use narrowly scoped adapters before
   calling the affected routines, retaining Stylus 0.1.5 unchanged. Preserve
   original source locations and safe declaration/rule recovery. Cover
   `!important`, attribute syntax, apostrophes, backslash/NUL, EOF strings and
   comments, unmatched delimiters and nested unsupported functions. A bounded
   input must return diagnostics rather than hang or leak a tokenizer defect.

2. **Specify provenance per changed native key and across stylesheet appends.**
   `themecore.nim:904` merges a native write into the first identical-selector
   patch. Merely promoting that patch to the override layer also promotes all
   its untouched base keys. After CSS sets background and text color, a native
   text-color write must leave the CSS background in force. Append or isolate
   the changed keys. Define the order of source-order and inherited-role rank
   explicitly, and preserve source ordering when a later stylesheet is compiled
   from an existing CSS snapshot. Keep an already-created programmatic override
   above subsequently appended CSS, consistent with the proposed layer order.
   Root-variable importance must also survive builder/finish round trips:
   an ordinary token table alone cannot remember that an earlier `--x` was
   important. Preserve that metadata or narrow the append contract explicitly.

3. **Choose one coherent typed-variable contract.** A single `svToken` works for
   `font-size`, but `padding: var(--gap)` must convert a resolved length to
   `svInsets`; `insetsRule` currently accepts only `svInsets`. The same issue
   applies to composite targets such as radius expansion. Either perform
   property-directed conversion when compiling and document what is frozen
   across appends, or retain enough declaration information to recompute those
   conversions after root-variable changes. Do not imply arbitrary CSS token
   substitution. At minimum, expressly support or diagnose each composite use.
   Specify `parseCssTheme(newSource, previous.theme)` when `newSource` changes
   the type or removes the validity of a variable used by previous rules.
   Existing `ruleValue` selects a resolved wrong-type value before the typed
   accessor rejects it, losing lower-priority valid rules. Revalidate affected
   declarations or define a bounded alternative that preserves the promised
   fallback behavior. Test valid lower declarations followed by invalid literals,
   missing variables, cycles and wrong-type variables. Document the existing
   16-step resolver limit; report excessive depth separately from an actual
   cycle if diagnostics identify the reason.

4. **Complete shorthand and font expansion.** Always expand `border-radius`
   to all four corner keys, including its one-value form. Native per-corner
   values otherwise defeat a later CSS uniform radius because
   `cornerRadiiRule` uses the uniform key only as its fallback. Preserve CSS
   corner ordering and rank for every expanded key; test four values followed
   by one value and a configured base with explicit corners. A CSS `font-family`
   declaration must also clear the exact regular/italic/bold/bold-italic face
   keys at the same rank. Drawing prefers an exact face over `fontName`
   (`drawing/drawing.nim:186`), so changing only the name may have no visible
   effect. Test a base configured with exact faces. Allow negative shadow spread
   and focus-ring inset when exposing those toolkit fields; reject negative
   blur, border width and ordinary padding.

5. **Resolve the same effective state for sizing and drawing.** State-based
   invalidation is necessary but insufficient. `buttonCellStates` removes
   `ssActive` and adds `ssPressed` from highlighted, whereas direct Button draw
   starts from the raw view state set. Explicitly map every supported pseudo
   class and use coherent effective states in the relevant measurement and draw
   paths. Additionally, `pushButtonStyle`/`mixButtonStyle` keeps all noncolor
   fields from the base style until hover animation completes, while cell sizing
   already uses the hovered metrics. Apply current-state geometry/text metrics
   during color interpolation. Test hover padding/font size and active/pressed
   metrics during entry and exit, not just at completed animation endpoints.
   Include `setFirstResponderFocusState`, mirrored cell highlighting/enabling
   and retained appearance changes in invalidation coverage. Keep existing
   native behavior where no CSS metric state dependency exists.

## Bounded recommendations and acceptance checks

- Keep the proposed subset. Add a small role/property coverage table to user
  documentation: ordinary Views gain background painting but do not suddenly
  acquire control borders, text or CSS layout. Compound controls expose semantic
  roles, not arbitrary descendant DOM nodes. Unsupported features must be
  diagnosed without accepting a broader selector accidentally.
- State that `:root` permits only standalone theme-variable rules in this
  increment; do not accidentally allow `button, :root` to install global tokens.
  Define diagnostic line/column bases and whether columns count bytes.
- Add regressions for selector repetition/source ordering, class versus pseudo
  equality, type versus universal through inherited roles, important root values
  across appends, untouched keys after native overrides, invalid-variable
  fallback, snapshot defensive copies and unchanged-base generations.
- Keep real View/Button/TextField render and intrinsic-size coverage in the
  shared `tests/tnimkit.nim` runner. For parser termination regressions, ensure
  the verification process itself has a deadline so a regression cannot hang
  the entire run. Preserve existing tests as the native-behavior guard.

The plan also handles immutable snapshots, explicit appearance
installation, partial diagnostics, source-level specificity, no tree inheritance,
Atlas-only dependencies, and the shared test runner well. Implementation can
proceed within the revised scope, with the concrete regression cases above used
to verify these contracts.

## Implementation review

**Source review recommendation: approve the corrected implementation, subject to
the required tests and example compilation passing.** All findings below have
been corrected and rechecked in source. The implementation follows the intended
immutable snapshot/cascade architecture, including atomic shorthand validation
and retained variable references. The findings are retained here as the review
record, with their original evidence classification.

1. **CONFIRMED — Stylus function opening tokens need normalization.** Stock
   Stylus emits `tkFunction, tkParenBlock, tkIdent, tkCloseParen` for
   `var(--gap)`. The new parser expects the function token to include its opener;
   without an adapter it counts two openings, reports unclosed rules and rejects
   variable/RGB values. A minimal `nim ic -r` tokenizer probe confirmed the token
   sequence. The implementer has added opener consumption; shared regressions
   still need to pass.
2. **CONFIRMED — Stylus unitless numbers need normalization.** The same probe
   shows `1;` emits `tkDimension(value=1, unit=";")` followed by `tkSemicolon`;
   `1 2;` has a space pseudo-unit, and `rgb(1, 2, 3)` has comma/close-parenthesis
   pseudo-units. The adapter must distinguish these unconsumed delimiters from
   actual dimension suffixes. Otherwise supported unitless lengths/RGB values
   are rejected. Regression coverage must include adjacent delimiters and
   whitespace, while unsupported real units stay invalid.
3. **TRACED — Focus-ring inset is a size dependency.** `finish` initially omitted
   `focus.ring.inset` from CSS metric-state flags. Negative insets feed
   `controlChromeOutset`, then button/text-field intrinsic size and box content
   geometry. A hover rule changing inset must invalidate layout and use current
   geometry during interpolation. The metric key has now been added; its
   regression is pending verification.
4. **TRACED — Read-after-write accessors ignore the new override layer.**
   `ThemeBuilder.[]`, `Theme.[]` and `stylePatch` initially search the first base
   patch, whereas post-CSS writes now live in separate override patches. Thus a
   native setter can change rendering while its matching getter reports the old
   value. Preserve the exact-selector/raw-value accessor contract while merging
   per-key provenance. Cover builder, frozen theme and appearance accessors.
5. **TRACED — Generic CSS backgrounds leak behind rounded control chrome.**
   `viewBackgroundFill` resolves `srView` for all View subclasses, and a
   class/id/universal background declaration expands to that role as well as
   `srButton`. `captureViewFrame` paints the generic shell as a square rectangle,
   then Button paints its rounded face. A class-styled red button therefore has
   opaque red corners outside its rounded face. Restrict generic background
   styling through an owned background-role/drawing hook; avoid central subclass
   checks. Verify actual render nodes for a styled rounded control and an
   ordinary child View.
6. **TRACED — Invalid literal syntax is not consistently diagnosed.** RGB parsing
   initially skipped arbitrary commas, accepting `rgb(,1,,2,3,)`. Empty literal
   font/chrome strings produced a patch that failed later validation silently,
   because diagnostic emission only inspected variable references. Reject
   malformed separators and diagnose invalid literal values before installation.

The corrected lexer consumes function openers and normalizes dimensions using
their consumed source span. The metric dependency list includes focus-ring
inset, exact-selector accessors merge per-key provenance, malformed literals are
diagnosed, and styled-background ownership uses an optional drawing hook. CSS
background declarations now target `StyleFill`; ordinary Views resolve it over
the existing root background fallback, while controls with owned chrome keep
their existing root fallback. This preserves native root rendering and avoids
square CSS shells on rounded controls, including controls rendered as roots.

A followup diagnostic issue was also corrected: retained declarations from
different appended sources may have identical line/column coordinates, so
diagnostics now deduplicate by persistent declaration source order. Tests cover
both declarations independently.

The shared CSS tests now include getter read-after-write checks, invalid literal
syntax, root/child rounded shells, focus-inset relayout, appended diagnostic
identity, variable invalidation/recovery, and the approved cascade/snapshot
contracts. `git diff --check` passed during this source review. The tokenizer
probe at `/tmp/nimkit_css_review_tokens.nim` uses only installed Stylus and was
compiled with the repository's IC-capable compiler. The shared NimKit suite and
example compilation are still being run by the implementation agent; this
review does not claim those checks have passed yet.
