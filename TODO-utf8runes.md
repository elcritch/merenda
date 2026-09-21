# TODO: Complete Merenda's `Utf8Runes` migration

## Goal

Merenda is partway through the migration from retained `seq[Rune]` text to
FigDraw's `Utf8Runes`. The target is to keep ordinary UTF-8 text compact while
preserving rune-indexed APIs. A `GlyphArrangement` should retain UTF-8 text and
its sparse rune index, not a UTF-32-sized sequence for every source or display
rune.

The migration should not replace every sequence containing a `Rune` blindly.
Sequences that carry per-rune metadata, terminal positions, or mutable editing
state are different data structures and may remain sequences. The important
rule is that plain text should not be decoded into `seq[Rune]` merely to read,
index, or iterate it.

## Current status

FigDraw `>= 0.39.0` is selected in `merenda.nimble`. Its
`GlyphArrangement.sourceRunes` and `.runes` fields are now `Utf8Runes`.

The retained FigDraw layout path is mostly migrated:

- `TextLayoutManager.currentLineFragments` reads and iterates
  `manager.xLayout.sourceRunes` directly.
- `containsHardBreak`, `lineFragment`, and `paragraphIndices` were made
  collection-generic so they accept `Utf8Runes` without invoking FigDraw's
  compatibility conversion.
- Layout revision hashing, glyph-line slicing, and glyph-count fallback use
  `len`, indexing, and UTF-8-backed slicing directly.
- Static render-scene isolation uses `copyUtf8Runes` for both retained text
  fields.
- The public layout-facing functions return `GlyphArrangement`; they do not
  expose `seq[Rune]`. Text input remains `string` or `TextStorage`, which is
  consistent with FigDraw's typesetting API.

The static generated C confirms that the migrated layout helpers receive
`Utf8Runes` and call the UTF-8 operators rather than materializing rune
sequences. The focused static suites also pass:

```text
atlas-run tests --compile-only tnimkit tintegrations
atlas-run tests tnimkit tintegrations
```

The first migration pass is now complete for the plain-text paths in NimKit
and Kosmo. The old sequence-shaped helpers and full-text `toRunes()` calls
have been removed from those modules. UTF-8 operators are imported explicitly
so `Utf8Runes` does not fall back through FigDraw's compatibility converter.
The remaining work is native-facade verification, allocation measurement, and
any optional indexing optimization that benchmarks show is worthwhile.

## Remaining migration work

### 1. Base `TextStorage` range queries — implemented

The base implementations of `storageLineRange` and
`storageParagraphRange` now scan the UTF-8 string directly while keeping all
returned ranges in rune coordinates. `TextGapStorage` continues to use its
byte-backed gap-buffer index.

If profiling shows that ordinary storage receives frequent repeated range
queries, add a revision-aware line index; do not retain a decoded rune
sequence alongside the source string.

### 2. Text-view search and word helpers — implemented

`TextView` and `TextField` now share `textruneutils.nim` helpers backed by
`Utf8Runes`. String inputs explicitly construct a UTF-8-backed view at the
helper boundary, while search, word movement, smart insertion, URL detection,
and find/replace use rune indexing without decoded sequences.

`utf8RunesForText` normalizes malformed input through Nim's replacement-rune
iterator before building the indexed view, keeping trailing bytes from being
swallowed by the indexed decoder.

Consider streaming or byte-oriented implementations for operations that do
not need random access if profiling shows repeated indexed reads are costly.

The public functions can continue to accept `string`; that is an input API,
not a retained decoded representation.

### 3. Layout-adjacent `toRunes()` calls — implemented

Both layout-adjacent paths now use retained or explicitly constructed
`Utf8Runes` values:

- `defaultGlyphProperties` reads the valid arrangement's `sourceRunes` and
  falls back to an explicit UTF-8 view before the first layout or while edits
  are pending.
- `TextLayoutManager.sourceRunes` returns the retained source view without
  copying the complete glyph arrangement.
- `currentVisualLineBounds` reads that source view.

`TextLayoutManager.lineRange` and `lineForIndex` already iterate the UTF-8
`string.runes` iterator without creating a `seq[Rune]`; they are not equivalent
allocation bugs and need not be changed solely for naming consistency.

### 4. Avoidable temporary sequences in Markdown and UI glue — implemented

Markdown table and block-quote source text, terminal search normalization, and
command-bar source text now use `Utf8Runes` directly. Rich per-rune records
remain sequences where they carry attributes, coordinates, or other state:

- `seq[MarkdownTableRune]`
- `seq[TerminalSearchGlyph]`
- `seq[MonoTextCell]`

`GapTextBuffer` byte sequences and its own index cache remain unchanged because
it is mutable editing storage, whereas `Utf8Runes` is immutable read-oriented
storage.

### 5. Fixed: stale native render-scene branch

`isolateGlyphArrangement` has the correct static branch:

```nim
result.sourceRunes = layout.sourceRunes.copyUtf8Runes()
result.runes = layout.runes.copyUtf8Runes()
```

The obsolete `useNativeDynlib` `isolateSequence()` branch has been removed.
Both retained fields now use `copyUtf8Runes()` directly. Public retained-scene
modules remain excluded from the dynlib build because Figdraw's client-side
`RenderFragments` implementation is intentionally outside the native ABI.

### 6. Native facade validation

The generated Figdraw ABI and native library now build through Merenda's
`build_dynlib` task. The shared NimKit runner also compiles with
`useNativeDynlib`, covering the migrated text-layout helpers through the native
facade.

TODO:

- Verify that `len`, indexing, slicing, equality, and `items`/`pairs` all stay
  in UTF-8 storage through the native facade.

## API rules for the finished migration

Use the following as the compatibility boundary:

- Keep `textLayout`/`addText` string overloads and `TextStorage` APIs. FigDraw
  typesets spans of strings, and editable text needs a mutable representation.
- Expose or pass `Utf8Runes` when a read-only rune-indexed text value is part
  of an API. Prefer `len`, `[]`, `items`, `pairs`, and UTF-8-backed slices.
- Make internal collection helpers generic where both `seq[Rune]` and
  `Utf8Runes` are genuinely supported, rather than accepting `openArray[Rune]`
  and triggering an implicit conversion.
- Treat `toRunes()` and `toRuneSequence` as explicit compatibility escape
  hatches. New code should make every such call intentional and local.
- Do not replace sequences that contain richer per-rune records or mutable
  editing state merely because they contain a `Rune` field.

## Upstream boundary

FigDraw itself still uses temporary decoded sequences in some shaping and
legacy glyph-building helpers, including Harfbuzzy's decoded shaping input and
`fontglyphs.buildArrangedGlyphs`. Those sequences are converted into
`Utf8Runes` for the final arrangement. Removing those transient allocations
entirely would be a separate FigDraw optimization; the Merenda TODO here is to
avoid reintroducing them after the arrangement reaches Merenda.

## Tests and measurements

- Added Unicode coverage for base `TextStorage` line and paragraph queries,
  text-view search, URL rune offsets, malformed UTF-8 search, and deferred
  glyph-property queries.
- Added a source-view accessor check for layout managers.
- Existing Unicode layout coverage remains in the NimKit test suite; extend it
  with explicit `Utf8Runes` slicing/equality checks if the native-facade work
  exposes a regression.
- Native compile/test coverage still needs explicit verification of `len`,
  indexing, slicing, equality, and `items`/`pairs` through the facade.
- A benchmark or allocation measurement comparing long ASCII/Unicode
  arrangements before and after the remaining migration is still useful,
  including render-scene isolation and repeated glyph-property queries.
