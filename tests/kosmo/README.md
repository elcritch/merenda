# Kosmo tests

Run these tests through the shared runner: `atlas-run tests kosmo`.

## Choose assertions around the behavior

- Start with an action and its expected result: opening selects the right file,
  typing changes its text, saving writes those changes, and switching tabs
  preserves the reader's position.
- Find controls by their action, identifier, or accessible label. Check that
  controls are visible, fit their container, and avoid overlap. Compare resize
  and zoom results with the initial size.
- Give each test one coherent scenario. Settings scenarios live in `settings.nim`;
  search scenarios live in `search.nim`. Shared UI lookup and visibility helpers
  live in `fixtures/ui.nim`.
- Use `require` for prerequisites so a missing control, selection, or asynchronous
  result fails before dependent assertions run. Wait for observable readiness
  with a monotonic deadline while pumping the owning event loop.
- Keep exact assertions for public data contracts: CLI parsing, saved file
  contents, shortcut mappings, grammar validation, and search locations.

Some focused regressions need internal observations. Workspace watch limits,
queued-work lifetimes, highlighting cache accounting, and idle layout tests
explicitly cover resource usage or ownership. Keep those assertions focused on
the invariant named by the test.

Live shell, background launch, and process cancellation scenarios live in
`../integrations/kosmoprocesses.nim`, imported by `../tintegrations.nim`. Run them
with `atlas-run tests integrations`. Component tests can use terminal sessions
fed with synthetic output when they only need to exercise UI behavior.
