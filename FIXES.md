# NSCell Behavioral/Logic Differences To Fix

Comparison target: `src/knutella/appkit/cells.nim` vs `vendor/darling-cocotron/AppKit/NSCell.m`.

## High Priority

- `trackMouse:inRect:ofView:untilMouseUp:` is heavily simplified in Nim.
  - Missing event loop, drag/up polling, continuous action dispatch, and window flushing.
  - Impact: incorrect mouse tracking behavior for controls/cells.
  - Nim: `cells.nim:563`
  - Cocotron: `NSCell.m:1079`

- Field editor setup/edit/select flow is mostly stubbed in Nim.
  - `setUpFieldEditorAttributes` returns editor unchanged.
  - `editWithFrame`/`selectWithFrame` do not perform setup, delegate wiring, selection range, or mouse-down.
  - Impact: text editing behavior diverges significantly.
  - Nim: `cells.nim:588`, `cells.nim:591`, `cells.nim:604`
  - Cocotron: `NSCell.m:1148`, `NSCell.m:1222`, `NSCell.m:1243`

## Medium Priority

- `attributedStringValue` only returns non-nil when object value is already attributed.
  - Cocotron synthesizes attributes (font/color/paragraph style) for plain values.
  - Impact: callers expecting attributed output get `nil` in Nim.
  - Nim: `cells.nim:269`
  - Cocotron: `NSCell.m:644`

- `setObjectValue` and `setAttributedStringValue` semantics differ.
  - Cocotron copies assigned object (`copyWithZone:`) and routes attributed values through `setObjectValue`.
  - Nim directly assigns and `setAttributedStringValue` bypasses the `setObjectValue` path.
  - Impact: mutability/KVO/update consistency differences.
  - Nim: `cells.nim:404`, `cells.nim:457`
  - Cocotron: `NSCell.m:903`, `NSCell.m:961`

- `stringValue` fallback path is narrower in Nim.
  - Cocotron uses `descriptionWithLocale:`/`description` when value is neither string nor attributed string.
  - Nim only checks a custom wrapper path, else returns empty string.
  - Impact: non-string object values stringify differently (often empty in Nim).
  - Nim: `cells.nim:210`
  - Cocotron: `NSCell.m:561`

- Update/display fallback is missing in Nim.
  - Cocotron calls `setNeedsDisplay:YES` if controlView does not respond to `updateCell:`.
  - Nim always assumes `updateCell` wrapper availability.
  - Impact: stale UI when control view lacks `updateCell`.
  - Nim: `cells.nim:346`, `cells.nim:404`, `cells.nim:466`
  - Cocotron: `NSCell.m:787`, `NSCell.m:903`, `NSCell.m:971`

## Low Priority / Consistency

- Font sizes differ from Cocotron defaults.
  - `setType(NSTextCellType)` uses `systemFontOfSize(15.0)` in Nim vs `12.0` in Cocotron.
  - `setControlSize` uses `16 - controlSize*2` in Nim vs `13 - controlSize*2` in Cocotron.
  - Impact: visual/metric mismatches.
  - Nim: `cells.nim:306`, `cells.nim:466`
  - Cocotron: `NSCell.m:699`, `NSCell.m:971`

- `setFloatingPointFormat:left:right:` is unimplemented in Nim.
  - Cocotron installs/configures an `NSNumberFormatter`.
  - Nim: `cells.nim:399`
  - Cocotron: `NSCell.m:882`

- `take*ValueFrom:` mismatch in failure mode.
  - Nim silently no-ops when sender lacks the provider concept.
  - Cocotron sends selectors directly (runtime exception if missing).
  - Nim: `cells.nim:471`-`cells.nim:505`
  - Cocotron: `NSCell.m:991`-`NSCell.m:1012`
