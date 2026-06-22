# Repository Guidelines

## Project Structure & Modules
- `src/`: Core library modules for the project.
- `tests/`: Unit tests using Nim's `unittest` plus a `config.nims` that enables ARC/threads and debug flags.
- Root files: `merenda.nimble` (package manifest), `README.md` (usage), `CHANGES.md` (history).

## Build, Test, and Development
- Install deps (atlas workspace): `atlas install` (ensure `atlas` is installed and configured for your environment). *Never* use Nimble - it's horrible. *Always* use Atlas and it's `deps/` folder and `nim.cfg` file to see paths.
- Run tests through Atlas: `atlas-run tests [test-selections]`. Omit selections to run the full suite, or pass one or more test selectors to run focused tests. Selectors match as `foo` -> `tests/tfoo*.nim`, `foo.nim` -> `tests/tfoo.nim`, and `examples/foo*.nim` -> `examples/foo*.nim`. Do not adjust the `--jobs` count or the `--nimcache`.
- If the Atlas test runner is missing, add it to `config.nims` using `listFiles("test")` and `strutils` `startsWith/endsWith` to find Nim tests in `tests/`.
- Run a single test locally:
  - `atlas-run tests tests/ttransfer.nim`
  - `atlas-run tests tests/ttransfer.nim -d:debug`

## Coding Style & Naming
- Indentation: 2 spaces; no tabs.
- Formatting: run `nph src/*.nim` and format any touched test files.
- Rely on Nim's zero-initialization for default result values. For example, a `bool` result already defaults to `false`, so do not assign `result = false` or return a final explicit `false` unless the branch needs to make that value clear or override earlier state.

## NimKit Coding Rules
- Keep geometry, color, event, and option data as plain Nim value types (`object`, enums, sets). Do not wrap scalar widget state in `ref object` or `Sigil`.
- Use `ref object` for identity-bearing GUI objects only: applications, windows, views, controls, widgets, responders, native handles, and target/action objects.
- Use plain fields for internal widget state such as frame, bounds, title, enabled, highlighted, state, text, colors, and flags. Only use `Sigil` when a property is actually observed, bound, or participates in a reactive graph.
- Keep mutation procs when setting a field has side effects such as display invalidation, responder updates, native window updates, or parent/child bookkeeping.
- Keep proc-based getter/setter boundaries for properties that may need swizzling, overriding, validation, layout hooks, or instrumentation to modify core GUI behavior. Use plain backing storage behind those procs; do not bypass the proc boundary just to expose fields. Do not add getter/setter pairs only for compatibility when direct Nim access is clearer and no future hook point is expected.
- For NimKit property APIs, prefer Nim assignment setters like `foo=` only for single-argument property updates, with the implementation body directly in that proc. More complex setters should keep a descriptive proc name unless an indexed assignment shape like `foo[]=` naturally fits. Avoid duplicated public `setFoo` wrappers unless the setter is specifically part of a protocol or selector-style API surface.

## Testing Guidelines
- Framework: `unittest` with descriptive `suite` and `test` names.
- Location: add new tests under `tests/`, mirroring module names (e.g., `tslots.nim` for `slots.nim`).
- Requirements: CI (`atlas-run tests`) must pass; include tests for new behavior and update `README.md`/`CHANGES.md` as needed.

## Security & Configuration Tips
- GC: library requires ARC/ORC (`--mm:arc` or `--mm:orc` or `--mm:atomicArc`); enforced in `sigils.nim`.
