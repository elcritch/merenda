# NimKit test coverage

Run the complete shared runner with `atlas-run tests nimkit`; do not add a
top-level runner for each widget. Process-lifecycle tests belong under
`tests/integrations/` and are imported by `tests/tintegrations.nim`.

## Test the feature boundary

For widget behavior, assemble the actual view hierarchy in a window, lay it
out, deliver input through that window, and check the result the caller or user
can observe. A successful setter, action callback, or nonempty render list alone
does not prove the feature works.

- Exercise the whole transition: open → interact → accept/cancel → reopen,
  edit → commit/cancel → continue editing, or resize → interact again.
- Verify both positive and negative outcomes: changed model values, unchanged
  values on cancellation, dispatched responses, focus, visible content, and
  restoration after dismissal/removal.
- Find controls by identifiers and choices by their model identity or label.
  Avoid menu/tab indexes unless ordering itself is the tested contract.
- Use explicit fixture colors, sizes, and metrics to test styling. Assert
  propagation, containment, growth/shrinkage, and precedence; do not duplicate
  the palette, font names, font sizes, or decorative layers of a shipped theme.
- Inspect rendered content or the relevant resource/geometry, not an arbitrary
  number of draw nodes. Rendering representation can change without changing
  the visible result.
- Wait for an observable asynchronous result with a monotonic deadline, pump
  the owning event loop non-blockingly, and assert completion after the wait.
  Fixed sleeps and polling-iteration counts are not completion conditions.

`fixtures/widgetflows.nim` sends pointer/keyboard events to attached, laid-out
controls. It sends both halves of a click: text fields can consume mouse-down
without consuming mouse-up. Its return value only reports handled input;
each test must still assert the actual outcome. `fixtures/rendergeometry.nim`
provides content and render-coordinate inspection without depending on retained
wrapper ordering.

## Review decisions

The September 2026 review covered all 85 test modules in the shared NimKit
runner, including screening test bodies for preset literals, setter-only checks,
render-node counts, private implementation checks, and asynchronous waits.
Changes concentrate on the gaps rather than mechanically rewriting every file:

| Area | Coverage emphasized |
| --- | --- |
| Themes, font faces, labels | Existing controls remain editable across theme/font changes; actual text and chosen faces render. |
| Settings | Visible theme choices, keyboard changes, Apply, saved defaults, Reset, autosave, and reopening. |
| File browsers and dialogs | Location entry, invalid paths, history buttons, typed save names, navigation, validation, and the final dialog response. |
| Modal sheets | Prepared completion callbacks receive choices; dismissal restores the owner and permits further editing. |
| Color/tree/window-effect demos | Input reaches the displayed controls, updates the result, and dismisses or restores state. |
| Dock/split/tab views | Content remains editable after resizing, removing/replacing panes, and moving tabs; rendered dividers follow layout. |
| Rendering and selection | Visible content changes, popup layers appear/disappear, and uninstalling selection hooks restores behavior. |
| Animation and process lifetime | Real completion, shared-user lifetime, resource cleanup, timeout recovery, and reaping. |

These regressions also exposed two small fixes: bottom-positioned tab bars now
stay inside the view instead of depending on a theme's panel overlap, and popup
color wells report their color name without visual swatch-padding spaces to
accessibility clients.

Keep precise lower-level coverage where it expresses a real contract:

- Geometry and solver equations use explicitly supplied dimensions and
  priorities. Unicode/rune indexing, parsing, serialization, date arithmetic,
  and undo inverses need exact answers.
- Selector/protocol interception, ownership/backlinks, renderer acknowledgments,
  resource leases, cache invalidation, bounded work, and thread affinity are
  intentional internal contracts, not cosmetic snapshots.
- Tables, text editors, scroll views, menus, model controllers, accessibility,
  and document/controller suites already contain substantial user-input and
  lifecycle coverage. Preserve focused edge-case regressions alongside those
  workflows rather than replacing them with one broad smoke test.

Unresolved failures needing architectural or dependency work stay enabled and
are recorded in [PLAN.md](../../PLAN.md), with their reproduction and validation
requirements. Do not skip them or widen tolerances just to obtain a green run.
