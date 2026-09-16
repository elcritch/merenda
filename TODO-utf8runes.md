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

This is not complete yet. Merenda still has several old sequence-shaped
helpers and full-text `toRunes()` allocations outside the retained
`GlyphArrangement` path.

## Remaining migration work

### 1. Remove full-text allocations from base `TextStorage`

The base implementations of `storageLineRange` and
`storageParagraphRange` decode the entire string on every call:

- `src/merenda/nimkit/text/textstorage.nim:233`
- `src/merenda/nimkit/text/textstorage.nim:260`

These are reached through the public `lineRange` and
`paragraphRangeForRange` APIs and can run during normal editing and attribute
fix-up. `TextGapStorage` already overrides these methods with its byte-backed
gap-buffer index, so preserve that implementation.

TODO:

- Replace the base `toRunes()` calls with a UTF-8-backed indexed view or a
  direct UTF-8 scan.
- Prefer a shared/revision-aware index if line and paragraph queries are
  frequent; do not retain both an unnecessary decoded sequence and the
  `GlyphArrangement` copy.
- Keep all returned ranges in rune coordinates.

### 2. Convert text-view search and word helpers

`TextView` still defines `runesOf(text: string): seq[Rune]` and then passes the
result through `openArray[Rune]` helpers:

- `src/merenda/nimkit/text/textviews.nim:417`
- `src/merenda/nimkit/text/textviews.nim:1202`
- `src/merenda/nimkit/text/textviews.nim:1212`
- `src/merenda/nimkit/text/textviews.nim:1225`

This affects word-boundary movement, smart insertion, find/replace, and URL
detection. `findTextRanges` currently creates full decoded haystack and needle
sequences at `src/merenda/nimkit/text/textviews.nim:1302`.

`TextField` has a duplicate sequence-based `runesOf` and word-boundary
implementation at `src/merenda/nimkit/text/textfields.nim:492`.

TODO:

- Make these helpers operate on `Utf8Runes` or on generic values providing
  `len`, rune indexing, and iteration.
- Replace `runesOf` with an explicit UTF-8 view construction at the boundary;
  do not rely on FigDraw's implicit `toRuneSequence` converter.
- Share the word-boundary implementation between `TextView` and `TextField`.
- Consider streaming or byte-oriented implementations for operations that do
  not need random access. `Utf8Runes` indexing is bounded by its sparse
  checkpoint stride, but repeatedly indexing every rune can still be more
  expensive than one forward scan.

The public functions can continue to accept `string`; that is an input API,
not a retained decoded representation.

### 3. Remove layout-adjacent `toRunes()` calls

Two places are close to the layout path and should be reviewed first:

- `defaultGlyphProperties` materializes the whole text storage at
  `src/merenda/nimkit/text/textlayout.nim:1615`. It is used as the fallback
  for individual glyph-property queries, so this can repeat a full allocation.
  Use the valid retained arrangement's `sourceRunes`, or another UTF-8 view,
  while preserving the early-layout behavior when no arrangement exists.
- `currentVisualLineBounds` materializes the text view string at
  `src/merenda/nimkit/text/textviews.nim:2321`. The method has already updated
  the text container and obtained a line fragment, so it should be possible
  to use the corresponding retained layout source text instead of decoding a
  second copy.

`TextLayoutManager.lineRange` and `lineForIndex` already iterate the UTF-8
`string.runes` iterator without creating a `seq[Rune]`; they are not equivalent
allocation bugs and need not be changed solely for naming consistency.

### 4. Remove avoidable temporary sequences in Markdown and UI glue

These are not retained `GlyphArrangement` fields, but they still decode plain
UTF-8 text into sequences:

- Markdown table construction at `src/merenda/nimkit/text/markdownviews.nim:946`.
- Block-quote remapping at `src/merenda/nimkit/text/markdownviews.nim:1343`.
- Terminal search query normalization at `src/merenda/kosmo/terminalsearch.nim:62`.
- Command-bar cell construction at `src/merenda/kosmo/application_editor.nim:534`.

TODO:

- Use `Utf8Runes` or direct UTF-8 iteration for the source text in these
  operations.
- Keep `seq[MarkdownTableRune]`, `seq[TerminalSearchGlyph]`, and
  `seq[MonoTextCell]` where the element includes attributes, coordinates, or
  other per-rune state. Those are not replacements for a plain text backing.
- Keep `GapTextBuffer` byte sequences and its own index cache: it is mutable
  editing storage, whereas `Utf8Runes` is immutable read-oriented storage.

### 5. Fix the stale native render-scene branch

`isolateGlyphArrangement` has the correct static branch:

```nim
result.sourceRunes = layout.sourceRunes.copyUtf8Runes()
result.runes = layout.runes.copyUtf8Runes()
```

However, its `useNativeDynlib` branch still calls `isolateSequence()` at
`src/merenda/nimkit/drawing/renderscenes.nim:205`. That is the old sequence-
shaped operation. If this branch is enabled, it can force the compatibility
conversion to `seq[Rune]` (or fail to type-check instead of copying native
UTF-8 storage directly).

At present this is latent rather than an active runtime path: the public
NimKit render-scene modules are excluded for `useNativeDynlib`, and managed
render resources explicitly reject that build. Before native scene support is
restored, make the copy operation unconditional or use the native facade's
`copyUtf8Runes` in both branches.

### 6. Validate the native facade

The tests run so far report `nativeDynlib=false`. No generated native FigDraw
ABI module or native library is currently present in the workspace, so the
Merenda native path has not been validated by these suites.

TODO:

- Generate/build the FigDraw native ABI and run the relevant NimKit and
  integration suites with `useNativeDynlib`.
- Verify that `len`, indexing, slicing, equality, and `items`/`pairs` all stay
  in UTF-8 storage through the native facade.
- Add a native compile check for every layout helper changed in the migration.

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

## Tests and measurements to add

- Unicode layout tests that exercise multi-byte source text through line
  fragments, slicing, equality, and glyph properties.
- Tests covering base `TextStorage` line and paragraph queries without a
  decoded-sequence compatibility path.
- Static and native compile/test coverage for all layout-facing helpers.
- A benchmark or allocation measurement comparing long ASCII/Unicode
  arrangements before and after the remaining migration, including render
  scene isolation and repeated glyph-property queries.

