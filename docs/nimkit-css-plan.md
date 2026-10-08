# CSS theming for NimKit

Status: implemented; Astra xhigh approved the revised plan and implementation
source, with runtime verification in progress. See `nimkit-css-plan-review.md`.

## Existing architecture and Figuro reference

NimKit already resolves role, id, class and widget-state selectors into typed
style patches. `ThemeBuilder.finish()` creates immutable snapshots with a cache
generation; `Appearance` propagates through applications, windows and view
subtrees. Controls consume these snapshots for rendering and intrinsic sizing.
This will remain the styling boundary. CSS will compile into this system.

Figuro's `common/nodes/cssparser.nim` imports Stylus and builds a CSS grammar on
its tokenizer; `ui/cssengine.nim` matches selectors and mutates node fields.
`runtime/utils/cssMonitor.nim` loads files and triggers refreshes. Reuse the
tokenizer approach, compound selectors, custom variables and state mapping, but
resolve NimKit styles without mutating widget backing fields. Figuro's checked
out dependency is 0.1.3. Merenda must use exactly Stylus **0.1.5**, upstream tag
`2da8f3c4d947c20078ae1b13960e8cefbeb32ea4`.

The parent completed dependency installation. The CSS agent owns implementation,
tests, README/CHANGES, the public example and full verification. All work lives in its own
`feat/nimkit-css-theming` branch and `/Volumes/projects/nims/merenda-css-theming`
worktree. Atlas installed `stylus == 0.1.5`; its generated `nim.cfg` supplies
`deps/stylus/src`. No Nimble commands or Atlas lockfiles are used.

## Public API and module boundaries

Add `nimkit/themes/cssthemes.nim` and export it through `nimkit/themes.nim`.
Use plain objects for parser data, selectors, declarations, diagnostics and
results. Do not add reactive properties or new identity-bearing stylesheet
objects.

```nim
type
  CssDiagnostic = object
    line, column: int
    message: string
  CssThemeResult = object
    theme: Theme
    diagnostics: seq[CssDiagnostic]

proc parseCssTheme(source: string, base: Theme = initTheme()): CssThemeResult
proc loadCssTheme(path: string, base: Theme = initTheme()): CssThemeResult
```

`parseCssTheme` returns usable declarations plus source-located diagnostics for
invalid or unsupported input. It never logs or replaces invalid values with
arbitrary colors. Skip one invalid declaration; discard an invalid selector
list's entire rule so unsupported combinators cannot broaden the rule. An
unclosed block is diagnosed and recovered where safe. File loading reports
filesystem errors through the usual `IOError`/`OSError` contract. Diagnostic lines
and columns are one based; columns count source bytes. The caller
decides whether diagnostics prevent installation. Installation is explicit:
`window.setAppearance(initAppearance(parsed.theme))`; use the existing view and
application appearance APIs for those scopes. Passing an existing base preserves
its chromes, tokens, rules and untouched control metrics. Rebuilding from the
original base replaces a stylesheet; passing the previous result appends it.

## Selector and cascade contract

Initial selectors are compound role selectors, `#id`, any number of `.classes`,
supported state pseudo classes, `*`, and comma-separated lists. Type names are
the `StyleRole` suffix converted to lowercase kebab case: `button`, `text-field`,
`scroll-view`, `document-tab`, etc. Type names are ASCII case insensitive; ids
and class names are case sensitive. Add aliases `checkbox` for `check-box`,
`radio` for `radio-button`, and `label` for `text-field.label`. Label's injected
class does not increase its CSS type-selector specificity. `.class`, `#id` and
`*` expand to each role at compile time without adding a fake type specificity.
An explicit type matches that semantic role and its existing inherited roles
(for example `button` styles `stepper`), consistent with native theme resolution.

Map `:hover`, `:active`, `:focus`, `:focus-visible`, `:focus-within`, `:disabled`,
`:selected`, `:checked`, `:open`, `:highlighted`, `:pressed`, `:accent`,
`:alternating` and `:invalid` to existing `WidgetState` values. `:checked` aliases
`:selected`. Unknown states are diagnosed and discard the rule. `:root` is
reserved for standalone theme-wide custom-property rules, not a view selector.
Mixed lists such as `button, :root` are invalid.

Keep native theme resolution unchanged when CSS is absent. Add minimal rule
metadata in `themecore.nim` to distinguish native base rules, CSS rules and
explicit native overrides added after CSS. Each CSS declaration compiles to its
own patch/rule, retaining its `!important`, lexicographic `(ids, classes + pseudo
classes, types)` specificity and source order. Shorthand expansion retains the
same importance and order on each expanded key. This avoids applying one
declaration's importance to its neighbors and prevents later rules from
rewriting earlier identical-selector records.

Precedence is native base, CSS declarations, then explicit programmatic theme
or appearance overrides made after CSS. Each later native write changes only
its own key in a separate override patch; untouched keys retain their original
base provenance. Explicit overrides remain above subsequently appended CSS.
Within CSS, importance wins first, then lexicographic specificity, then last
declaration (source order), then inherited-role rank. CSS specificity has no
overflow-prone weighted encoding. Additional stylesheets participate in the same
CSS cascade; later low-specificity rules do not beat earlier ids. Native role
inheritance uses its existing rank only to break otherwise identical scores.
Snapshot cloning, builder round trips and defensive rule accessors preserve
metadata and independent ownership.

## Values and properties

Support fixed lengths in `px` and unitless numbers interpreted as NimKit logical
pixels. Reject nonfinite values and unsupported units. Sign validation is per
property: reject negative blur, border width, font size and padding while allowing
signed shadow offsets/spread and focus-ring inset. Colors support named/hex values,
`transparent`, `rgb()` and `rgba()` with number/percentage components. Use Chroma
for recognized color parsing and validate complete token consumption.

Initial standard properties map to existing keys:

| CSS property | NimKit target |
| --- | --- |
| `color` | `StyleTextColor` |
| `background`, `background-color` | `StyleFill`, overlaying the native root background |
| `border-color`, `border-width` | corresponding border keys |
| `border-radius` | uniform radius plus all four corner keys using CSS ordering |
| `font-family` | font name plus clearing all four exact face keys at the same rank |
| `font-size`, `font-style` | existing font size/slant keys |
| `padding` | `StyleTextInsets` and `StylePadding` with CSS 1–4 value ordering |
| `box-shadow` | `StyleBoxShadows`, drop/inset shadows, comma-separated |

Expose focused NimKit extensions `-nimkit-chrome`, `-nimkit-minimum-size`,
`-nimkit-focus-ring-color`, `-nimkit-focus-ring-width`, and
`-nimkit-focus-ring-inset`. These express existing toolkit concepts instead of
inventing browser geometry. Reject unknown properties with diagnostics. Border
shorthand, padding longhands, gradients and browser font fallback lists are
deferred unless the reviewer identifies a small necessary addition.

`:root { --accent: #79b8ff; --gap: 8px; }` defines theme-wide typed custom
properties. Retain CSS variable names including the `--` prefix. Initial variable
values support colors, a single length, a keyword/string, and direct variable
aliases. `var(--accent)` retains a token reference and resolves after all root
declarations, so forward references work. Property-directed conversion turns a
single resolved length into uniform padding Insets and all four radius values.
Other multi-token substitution is unsupported. Reject unsupported
fallback arguments and variable expressions explicitly. Cycles, missing names
and wrong types produce declaration diagnostics; ignore the invalid declaration
during resolution so a valid lower CSS declaration or native base remains usable.
Retain token references so appended root definitions can restore validity or
invalidate earlier declarations. Revalidate retained CSS token declarations
against the updated root store on append, including target-type coercion.
Reuse the existing 16-step token resolver; report unresolved reference chains
without falsely classifying the depth limit as a cycle.
Custom properties on non-root rules are diagnosed. Multiple root declarations
use last declaration with `!important` precedence, consistent with the CSS layer;
persist root importance/provenance through snapshots and builder round trips.

Use a narrow safety adapter around Stylus 0.1.5 without editing the dependency.
The installed tokenizer can stall on punctuation/`[` and internally on unquoted
backslash/NUL or double-quoted strings containing apostrophes. A safe quoted
string scanner runs before the affected routine; preflight unsupported unquoted
escaped identifiers/NUL and guard progress before/after other token calls.
Preserve source positions, diagnose EOF strings/comments and unmatched blocks,
and consume unsupported nested constructs with bounded iterative scanning.

## Inheritance, runtime integration and limits

Existing `Appearance` inheritance remains the scope mechanism. Installing CSS
on a window affects its inherited subtree; a view's explicit appearance still
overrides that inherited appearance. Custom variables are theme-wide, and CSS
properties do not gain browser-style per-view inheritance. Document these limits
clearly rather than claiming a full browser CSS engine. Descendant/child/sibling
combinators, attribute selectors, functional pseudo classes, media/import/font
rules, animation, percentages for layout, `em`/`rem`, `calc`, browser display,
position and margin are diagnosed and deferred.

Ensure backgrounds also work on ordinary child Views: their `StyleFill` falls
back to the plain `backgroundColor`, preserving native root-only background
rules and existing alpha behavior. Controls keep drawing through their existing
style resolvers and chrome delegates. Existing explicit background/field
properties retain their current role as resolver fallbacks.

CSS identity/class setters already invalidate display and intrinsic sizing.
State setters currently only repaint; compile metric-sensitive state dependency
flags into Theme snapshots and invalidate intrinsic size/layout when those states
change. Include focus transitions through the responder hook and the highlighted
to pressed mapping used by button cells. Use a narrow button style hook so sizing
and drawing use the same effective active/highlighted/pressed states for CSS
metric-dependent rules. During hover color interpolation, use the current state's
text/geometry metrics immediately on entry and exit. Native themes without CSS should retain
their existing fast path. Changing a CSS appearance uses the existing subtree
invalidation and theme generation cache, with no filesystem watcher or new
event-loop lifecycle in this first increment.

## Verification

Add `tests/nimkit/cssthemes.nim`, imported by the shared `tests/tnimkit.nim` runner.
Cover:

- Actual Stylus tokenization with comments, quotes, functions and source locations,
  including apostrophes, punctuation, attributes, backslash/NUL, EOF strings and
  comments, unmatched delimiters and nested unsupported functions. Run parser
  verification with an explicit external process deadline.
- Roles, aliases, compound ids/classes/states, universal selectors and lists;
  unsupported selectors never broaden a match.
- Declaration order, same-selector rules, class/pseudo specificity equality,
  id precedence, type versus universal, importance per declaration and shorthand.
- Root variables, forward references, aliases, missing/cyclic/wrong-type values,
  diagnostics and safe partial recovery; external file loading in a temp directory.
- Fixed lengths, colors, padding/radius ordering, shadow lists, finite validation
  and unsupported unit/property behavior.
- Immutable base preservation, builder round trips, important roots across appends,
  later programmatic overrides changing only their own keys,
  appearance subtree scoping and native themes unchanged.
- A real View/Button/TextField workflow: class/id and hover/focus/disabled changes,
  metric-state relayout and measurement/draw coherence during hover entry/exit
  and active/pressed changes, render output changes and stylesheet replacement restoring
  original metrics without corrupting input/action behavior.

Format all touched Nim files with `nph`, including the required `nph src/*.nim`.
Use the repository's IC-capable compiler through Atlas:

```sh
atlas-run --nim:/Volumes/projects/nims/Nim-ic-semantic/bin/nim tests --backend:ic nimkit
atlas-run --nim:/Volumes/projects/nims/Nim-ic-semantic/bin/nim tests --backend:ic
atlas-run --nim:/Volumes/projects/nims/Nim-ic-semantic/bin/nim tests --backend:ic --compile-only examples/all_compile.nim
```

Do not change jobs or nimcache settings, create individual top-level runners,
alter CI backends, or use fixed sleeps for event-driven assertions. The CSS agent
owns the broad runs, example and end-user documentation. After final Astra
review and passing checks, the CSS agent commits the isolated branch and opens
a pull request to `main`, as subsequently requested by the user.
