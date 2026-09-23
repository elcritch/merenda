# Changes

## 0.22.0

- Share immutable UTF-8 text snapshots across NimKit text storage and FigDraw
  layout while preserving rune-based public APIs.
- Store styled text as byte and rune ranges with compact style IDs and sparse
  rune and line checkpoints.
- Add diagnostic RSS output to the large NimKit styled-text regression test.
- Avoid storage and TextView undo snapshots when undo is disabled; retain one
  prepared snapshot per grouped edit and report undo-mode RSS diagnostics.
- Apply syntax colors in one compact run-table edit, retokenize safe single-line
  changes locally, and use endpoint cursors instead of dense highlighting maps.
- Expose explicit UTF-8 byte ranges and allocation-free rune iteration on text
  snapshots while keeping rune-based editing ranges.
- Pack MonoText viewport rows into UTF-8 buffers and interned styles, and stream
  Moe and terminal rows into the viewport without full temporary cell grids.
  Grid replacement and scrolling now take row providers instead of owned cell
  arrays.
