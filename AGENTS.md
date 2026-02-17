# Repository Guidelines

## Project Structure & Modules
- `src/`: Core library modules for the project.
- `tests/`: Unit tests using Nim's `unittest` plus a `config.nims` that enables ARC/threads and debug flags.
- Root files: `neonim.nimble` (package manifest), `README.md` (usage), `CHANGES.md` (history).

## Build, Test, and Development
- Install deps (atlas workspace): `atlas install` (ensure `atlas` is installed and configured for your environment). *Never* use Nimble - it's horrible. *Always* use Atlas and it's `deps/` folder and `nim.cfg` file to see paths.
- Run all tests: `nim test` (uses the `test` task in `config.nims` to compile and run every `tests/*.nim`).
- If `nim test` is missing, add it to `config.nims` using `listFiles("test")` and `strutils` `startsWith/endsWith` to find Nim tests in `tests/`.
- Run a single test locally:
  - `nim c -r tests/ttransfer.nim`
  - `nim c -r -d:debug tests/ttransfer.nim`
  - `nim c tests/ttransfer.nim` # build only

## Coding Style & Naming
- Indentation: 2 spaces; no tabs.
- Formatting: run `nph src/*.nim` and format any touched test files.

## Testing Guidelines
- Framework: `unittest` with descriptive `suite` and `test` names.
- Location: add new tests under `tests/`, mirroring module names (e.g., `tslots.nim` for `slots.nim`).
- Requirements: CI (`nim test`) must pass; include tests for new behavior and update `README.md`/`CHANGES.md` as needed.

## Security & Configuration Tips
- GC: library requires ARC/ORC (`--mm:arc` or `--mm:orc` or `--mm:atomicArc`); enforced in `sigils.nim`.
