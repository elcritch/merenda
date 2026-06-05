# Repository Guidelines

## Project Structure & Modules
- `src/`: Core library modules for the project.
- `tests/`: Unit tests using Nim's `unittest` plus a `config.nims` that enables ARC/threads and debug flags.
- Root files: `merenda.nimble` (package manifest), `README.md` (usage), `CHANGES.md` (history).

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

## Merenda / Objective-C Coding Rules (!IMPORTANT!)
- Make sure to use `objcImpl` methods instead of Nim procs unless copying a C function when implementing OpenSTEP or Cocoa APIs.
- Every `NS*` object must be an Objective-C class or prototype unless the Cocoatron / Cocoa APIs use a C struct.
- ObjC fields (ivars) in `objcImpl` must use the `x` prefix (for example `xTitle`, `xFrame`) instead of `_` or ad-hoc prefixes.
- *Always* `xField {.set: setField, get: field.}` pragmas to create simple getters/setters methods.
- *DO NOT* use `ID(value: obj.value)` or `NSObject(value: obj.value)`! That causes ARC to over-release. Use Nim conversions instead, like `obj.NSObject.doSomething()`.
- Use Nim type conversion of `NSObject(obj)` instead of `ownFromId`.
- Base implmentation on `vendor/darling-cocotron/AppKit/` and match Cocoatrons implementation logic, but match our Nim style in existing modules (no extra nil checks, use `asWrapper`, etc)
    - Skip `retain` as it's a no-op in Nim
- Don't initialize "zero" value fields with `false`, `nil`, or `NSFoo(value: nil)` since these will be set by memory zeroing.
- Prefer public API names from AppKit headers over `*Id`-style hacks (for example `title`/`setTitle` rather than `titleId`).
- Convert `id` in Objective-C to concrete types where possible when porting Obj-C code, or failing that use `ID` not `IDPtr`.
- *Do not* use `discard argument` or prefix `_` for unused proc or method arguments
- *Do* use a lone `discard` for empty proc or method bodies.
- Never try to use global storage as a shortcut for implementing something unless absolutely needed.
- Don't use `ensure*` style crap for POJ's, instead make sure `init`, `new` configure storage properly.
- Prefer Nim backed storage for tables, seq's etc for internal obj-c storage. Only use NSDictionary where AppKit API needs it.

## NimKit Coding Rules
- Keep geometry, color, event, and option data as plain Nim value types (`object`, enums, sets). Do not wrap NSRect-like data or scalar widget state in `ref object`, Objective-C wrappers, or `Sigil`.
- Use `ref object` for identity-bearing GUI objects only: applications, windows, views, controls, widgets, responders, native handles, and target/action objects.
- Use plain fields for internal widget state such as frame, bounds, title, enabled, highlighted, state, text, colors, and flags. Only use `Sigil` when a property is actually observed, bound, or participates in a reactive graph.
- Keep mutation procs when setting a field has side effects such as display invalidation, responder updates, native window updates, or parent/child bookkeeping.
- Keep proc-based getter/setter boundaries for properties that may need swizzling, overriding, validation, layout hooks, or instrumentation to modify core GUI behavior. Use plain backing storage behind those procs; do not bypass the proc boundary just to expose fields. Do not add getter/setter pairs only for compatibility when direct Nim access is clearer and no future hook point is expected.
- For NimKit property APIs, prefer Nim assignment setters like `foo=` only for single-argument property updates, with the implementation body directly in that proc. More complex setters should keep a descriptive proc name unless an indexed assignment shape like `foo[]=` naturally fits. Avoid duplicated public `setFoo` wrappers unless the setter is specifically part of a protocol, selector, or AppKit/OpenSTEP-style API surface.

## Testing Guidelines
- Framework: `unittest` with descriptive `suite` and `test` names.
- Location: add new tests under `tests/`, mirroring module names (e.g., `tslots.nim` for `slots.nim`).
- Requirements: CI (`nim test`) must pass; include tests for new behavior and update `README.md`/`CHANGES.md` as needed.

## Security & Configuration Tips
- GC: library requires ARC/ORC (`--mm:arc` or `--mm:orc` or `--mm:atomicArc`); enforced in `sigils.nim`.

## Debugging Notes
- NSFont/NSFontDescriptor lifetime bug tracking: use Nim ARC expansion logging (`--expandArc:systemFontOfSize --expandArc:fontWithName --expandArc:initWithName --expandArc:main`) to trace second-font-construction ownership issues.
