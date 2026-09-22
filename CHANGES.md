# Changes

## 0.22.0

- Share immutable UTF-8 text snapshots across NimKit text storage and FigDraw
  layout while preserving rune-based public APIs.
- Store styled text as byte and rune ranges with compact style IDs and sparse
  rune and line checkpoints.
- Add diagnostic RSS output to the large NimKit styled-text regression test.
