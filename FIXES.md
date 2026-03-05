# NSCell Behavioral/Logic Differences To Fix

Comparison target: `src/knutella/appkit/cells.nim` vs `vendor/darling-cocotron/AppKit/NSCell.m`.

## Medium Priority

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
