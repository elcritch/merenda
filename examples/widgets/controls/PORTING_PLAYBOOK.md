# AppKit Controls Porting Playbook

This document captures the process used to port the Cocoa `Button` control demo into Nutella AppKit with close behavioral and layout parity.

## Goal

For each control demo in `tests/widgets/controls/*.m`:

1. Port demo structure to Nim (`tests/widgets/controls/` or test harness).
2. Port missing AppKit APIs from `vendor/` into `src/nutella/appkit/*.nim`.
3. Match Cocoa behavior and layout as closely as possible.
4. Keep regression tests passing.

## Core Workflow

### 1. Start from ObjC baseline (instrument first)

- Add temporary dump helpers in the ObjC demo:
  - window frame/content rect
  - each control frame/bounds/autoresize mask
  - style/state/text/font/alignment details
- Trigger dumps:
  - once at init
  - on each interaction callback (click/change)

Command pattern:

```sh
clang -framework Cocoa tests/widgets/controls/<Control>.m -o tests/widgets/controls/<Control>
<ENV_TO_EXIT_QUICKLY>=1 tests/widgets/controls/<control>
```

### 2. Port demo structure 1:1

- Prefer ObjC-style setup in Nim:
  - subclass `NSWindow` in `objcImpl`
  - implement `init`, action methods, `windowShouldClose`, `dealloc`
  - allocate controls with `alloc` + `initWithFrame`
  - set `target`/`action` selectors
- Keep original literal geometry and strings first, then iterate.

### 3. Port missing API surface from `vendor/`

For each missing call in the ObjC demo, add header-aligned Nim methods/constants in AppKit modules.

Typical files:

- `src/nutella/appkit/types.nim` (constants/masks/enums)
- `src/nutella/appkit/windows.nim` (window init/close/visibility APIs)
- `src/nutella/appkit/controls.nim` (target/action/sendAction)
- `src/nutella/appkit/<control>.nim` (control-specific init and behavior)

Rule of thumb:

- Add ObjC method names directly (`initWithFrame`, `performClose`, etc.).
- Avoid helper-only APIs when parity requires real selector-compatible methods.

### 4. Match behavior before visuals

Examples from button parity:

- Mouse-down should set active/highlighted state.
- Mouse-up should clear active state.
- Click should dispatch control `sendAction:to:` and callback path.
- Labels must show exact initial strings and update counts.

### 5. Match visuals/layout

- Align default font sizes/colors with Cocoa outputs.
- Match bezel style differences (rounded vs regular square).
- Ensure text fitting does not hide expected labels.
- Keep exact frame coordinates from ObjC dump.

### 6. Handle coordinate-system parity explicitly

Important: AppKit view coordinates are bottom-left by default (`isFlipped == false`), but rendering backends may behave top-left.

Use parent-aware conversion in render tree + hit testing:

- convert child `y` based on parent `isFlipped()`
- apply the same transform for interaction hit tests

This prevents “visually inverted order” bugs while keeping click targets aligned.

### 7. Validate in tight loop

Use all three checks each iteration:

1. ObjC dump output
2. Nim render/debug dump
3. Nim tests

Command pattern:

```sh
nim c tests/widgets/controls/<example>.nim
NUTELLA_EXAMPLE_FRAMES=1 NUTELLA_APPKIT_DEBUG_RENDER=1 ./tests/widgets/controls//<example>
nim c -r tests/tappkit_hello.nim
```

## Practical Checklist Per Control

- [ ] ObjC demo instrumented (`dumpLayout`, per-event dumps).
- [ ] Nim demo uses ObjC-like window subclass + init path.
- [ ] All ObjC calls compile in Nim with equivalent method names.
- [ ] Missing constants/methods ported from `vendor/`.
- [ ] Target/action and responder dispatch verified.
- [ ] Active/pressed/hover/change behavior matches Cocoa.
- [ ] Frame positions and sizes match dump values.
- [ ] Text labels, fonts, alignments match dump values.
- [ ] Coordinate conversion checked for non-flipped/flipped views.
- [ ] `tests/tappkit_hello.nim` updated only where coordinate expectations intentionally changed.
- [ ] Full test run for touched behavior passes.

## Pitfalls We Hit (and how to avoid)

- Parallel Nim builds can collide in `.nimcache` (missing object at link time).
  - Run heavy compile/test commands serially when this appears.
- Fixing render coordinates can break clip/scroll tests.
  - Re-check clip node and document node expected screen positions after conversion changes.
- A visually correct layout with incorrect hit-test coordinates will regress interaction.
  - Always patch render + hit-test transforms together.

## Keep/Clean Policy

- Keep ObjC instrumentation while actively porting a control.
- Remove temporary ad-hoc probe files/scripts before finalizing.
- Keep regression-test expectation updates minimal and explained by coordinate/model changes.
