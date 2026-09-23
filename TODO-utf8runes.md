# TODO: Reduce text memory in NimKit and Kosmo

Source review: 2026-09-23. Baseline: Sol's implementation plus the follow-up
commits Merenda `66e5cb15` and FigDraw `e742041`. Sections 1–3 were implemented
in Merenda `172eedf1` and profiled against its parent `dd933623` as described
below. Section 9 is implemented and profiled below. The remaining priorities
are source-based estimates.

Ordinary TextStorage now owns a shared immutable TextSnapshot, backed by
FigDraw's UTF-8 bytes and sparse rune checkpoints, with sparse line checkpoints
in NimKit. Stored attribute runs use compact style IDs. Normal Harfbuzzy layout
accepts source ranges without allocating text per style run or dense source
maps. Gap storage caches a snapshot until characters change. Build further
optimizations on these facilities rather than introducing another text index.

The follow-up commits also implement compact style IDs at the FigDraw boundary,
per-style font resolution, and Pixie source reuse/source-coordinate mapping.
Those implementation tasks are complete. Separate display text remains necessary
when case conversion or control filtering changes it.

## Priorities

| Priority | Work | Main benefit |
| --- | --- | --- |
| 1 | Stream Kosmo terminal search | Avoid expanding all scrollback into coordinate records |
| 2 | Preserve snapshots across layout worker requests | Avoid source copies and expanded attribute runs |
| 2 | Compact Markdown tables and share embedded text | Reduce render peaks and duplicate retained text |
| 2 | Reduce Kosmo Matter and Git Diff source duplication | Bound worker and document working sets |
| 3 | Use edit deltas/chunks and share layout geometry | Larger structural reductions for long documents |

Priorities are estimates from the code paths, not measured rankings. Distinguish
retained memory, transient peak memory, and allocation traffic when evaluating
each change.

## Profile: recent NimKit text changes

Standalone release/ARC processes on macOS with the static FigDraw path, both
built against the same Atlas dependency tree. Baseline `dd933623`, updated
`172eedf1`; each workload ran three times per build. Numbers are median current
RSS growth after the operation, so they include allocator retention and are not
an allocation count.

| Workload | Before | After | Change |
| --- | ---: | ---: | ---: |
| 8 MiB gap edit, undo disabled | 20,816 KiB | 4,384 KiB | 16,432 KiB less |
| 8 MiB gap edit, undo enabled | 20,864 KiB | 12,640 KiB | 8,224 KiB less |
| Tokenize 8 MiB of spaces with SynEdit | 81,968 KiB | 8,208 KiB | 73,760 KiB less |
| Apply 2,048 token styles over 1 MiB | 1,440 KiB | 1,312 KiB | 128 KiB less |

The style workload produced 4,096 final runs in both builds. Its measured
operation time fell from about 0.336 s to 0.006 s; keep the bulk update for
this speed benefit even though its RSS gain is small. The tokenizer produced
one final span in both builds. Gap undo registration produced zero records when
disabled and one when enabled in both builds. The process-isolated workload
avoids the resident page reuse that makes full-suite RSS diagnostics print
zero. It does not measure long-lived GUI layouts, worker copies, or allocation
traffic.

## Public text API review

Keep UTF-8 in `TextSnapshot` and rune-based `TextRange` for editing. Accept
`string` for insertion. `TextByteRange` is a separate public range type for
tokenizer and layout endpoints; a snapshot converts between it and `TextRange`.
Byte-to-rune conversion rejects endpoints inside a multibyte rune. A styled
span exposes its byte range while retaining its existing rune positions.

The snapshot also supports `len`, indexed rune reads, `items`/`pairs` iteration,
and an explicit `toRunes()` conversion. This lets callers use `seq[Rune]` when
they want a decoded sequence without making it the stored form. In isolated
release processes over 8 MiB of UTF-8 (`4,194,304` `é` runes), iterating the
snapshot added **0 KiB** current RSS in three runs; `toRunes()` added **16,432
KiB**. Both visited or produced the same rune count. These are current RSS
measurements after setup, not allocation counts; they show the expected cost of
retaining a decoded sequence. Grapheme-based caret movement is separate future
work: one visible emoji can contain multiple runes.

- [x] Expose a byte range type and snapshot conversions without replacing
  rune-based editing ranges or public `SyntaxTokenSpan`.
- [x] Expose allocation-free rune iteration and explicit sequence materialization.
- [ ] Decide later whether a byte-native highlighter callback would simplify
  external tokenizer adapters enough to justify a second callback surface.

## 1. Avoid snapshots when undo will not use them

Evidence: [textstorage.nim](src/merenda/nimkit/text/textstorage.nim),
replace, setAttributes, stringValue=, registerSnapshotUndo, and copyStorageTextTo;
[gaptextbuffers.nim](src/merenda/nimkit/text/gaptextbuffers.nim), copyGapTextBuffer;
[textviews.nim](src/merenda/nimkit/text/textviews.nim), replaceRange and recordUndo.

- [x] Gate storage undo snapshots on undo registration. Ordinary storage shares
  source bytes; gap storage copies its byte arrays only when undo needs them and
  retains a valid shared snapshot cache in the copy.
- [x] Transfer the prepared undo snapshot into the closure directly.
- [x] Capture TextView undo state after delegate approval and only when enabled.
  Compare the edited range for value-change notifications.
- [x] Avoid full-text equality strings and intermediate grouped-edit copies in
  the static path. Native facade byte access can still create an owned string;
  section 12 tracks a borrowed byte-range API for that boundary.

NimKit tests include RSS diagnostics and behavior checks for undo disabled,
enabled, grouped, and marked-text composition, with ordinary and gap storage.
The isolated profile above measures the largest gap-storage edit costs.

## 2. Apply highlighting as one compact run-table update

Evidence: [syneditviews.nim](src/merenda/nimkit/text/syneditviews.nim),
applyCachedHighlighting and applySyntaxHighlightingForEdit;
[textstorage.nim](src/merenda/nimkit/text/textstorage.nim), setAttributes,
styleId, and normalizeRuns.

- [x] Apply SynEdit's base and token styles in one ordered range update and one
  normalization pass, rather than one storage edit per token.
- [x] Compact an existing style table by remapping old IDs to new IDs, avoiding
  a full attribute comparison for every run during normalization.
- [x] Preserve complete/partial coverage, overlapping-range semantics, delegate
  hooks, and style-ID lifetime rules. styledSpans IDs currently refer to a
  mutable storage table only until its next edit.
- [x] Retokenize safe single-line built-in edits locally and compare the shifted
  old cache without allocating a second shifted copy.
- [ ] Extend incremental tokenization across multiline lexical state and custom
  highlighters. Those paths still use a full new token cache.

## 3. Remove dense highlighting maps and per-byte token storage

Evidence: [matterhighlighting.nim](src/merenda/nimkit/text/matterhighlighting.nim),
byteRuneMap; [syneditviews.nim](src/merenda/nimkit/text/syneditviews.nim),
byteRuneMap, SynEditHighlightBuffer, and tokenSpans;
[markdownviews.nim](src/merenda/nimkit/text/markdownviews.nim),
renderBlockquote and addHighlightedCode.

- [x] Replace whole-source byte-to-rune `seq[int]` maps with monotonic endpoint
  cursors; the removed map used roughly eight bytes per source byte.
- [x] Emit SynEdit token ranges directly instead of storing a token class for
  every byte. CR bytes remain in the source so CRLF positions stay aligned.
- [x] Convert Markdown highlighted-code endpoints without a per-rune offset
  array; map blockquotes with segments at inserted prefixes.
- [x] Keep public rune-based SyntaxTokenSpan APIs if needed. Validate emoji,
  multibyte boundaries, CRLF, malformed UTF-8, and nested blockquotes.
- [ ] Check whether `SynEditHighlightBuffer.source` still copies the input
  string. The 8 MiB tokenizer sample retains about 8 MiB after conversion;
  borrow the source through tokenizer parameters if this is the remaining copy,
  and remeasure without introducing an unsafe pointer lifetime.

## 4. Preserve compact input across background layout

Evidence: [textlayout.nim](src/merenda/nimkit/text/textlayout.nim),
startBackgroundTextLayout;
[textlayoutworkers.nim](src/merenda/nimkit/text/textlayoutworkers.nim),
requestTextLayout.

- [ ] Replace the worker request's string plus seq[TextAttributeRun] with
  immutable source, compact runs, and an immutable style table. The caller
  exports stringValue() and expands every stored style ID through
  attributeRuns(); the worker copies these into locals and rebuilds storage,
  indexes, and style interning.
- [ ] Define safe ownership for the complete payload. Ordinary ARC ref sharing
  across threads is not made safe merely by immutable bytes. Use the project's
  transfer/shared-owner facilities, or one deliberate worker-owned copy per
  character revision that can be reused across reflows.
- [ ] Reuse worker source state for width/style-only changes. Retain the existing
  one-pending-request/coalescing behavior and stale-generation checks.

## 5. Reduce edit-history storage with deltas or shared chunks

Evidence: [textviews.nim](src/merenda/nimkit/text/textviews.nim), TextUndoRecord,
xMarkedUndoStorage, and grouped undo;
[textstorage.nim](src/merenda/nimkit/text/textstorage.nim), replaceStorageText
and applySnapshot.

- [ ] Store removed/inserted text, affected style ranges, and selection state
  in undo records instead of entire before/after storages.
- [ ] Coalesce typing and composition edits, and support an undo byte budget.
- [ ] Evaluate persistent chunks or a piece table for large editable documents.
  Sharing snapshots makes copies of an unchanged revision cheap; it does not
  share unchanged portions between character revisions. Ordinary replacement
  still slices/concatenates a complete new string and rebuilds its indexes.
- [ ] Keep gap storage's compact mutable representation where useful; switching
  every TextView to gap storage alone does not solve history copies.

## 6. Compact Markdown table rendering

Evidence: [markdownviews.nim](src/merenda/nimkit/text/markdownviews.nim),
MarkdownTableRune, tableRunes, wrapTableCell, and renderTable.

- [ ] Represent cell text as UTF-8 plus style runs/IDs, attachments as sparse
  ranges, and wrapped lines as boundaries into cell text.
- [ ] Remove full TextAttributes, image references, and image sizes from each
  ordinary rune. Wrapping currently builds nested sequences of these records
  for cells, words, and lines.
- [ ] Build overflowing table storage independently or from a shared range.
  Constructing storage from builder.text/builder.runs before sliceTextStorage
  currently copies/indexes the entire rendered prefix just to extract a table.

These per-rune table records are rendering temporaries, not permanently retained
by MarkdownView. The primary gain is lower rendering/resize peak memory and
allocation traffic; embedded table storage is a separate retained cost.

## 7. Share Markdown children and budget preview caches

Evidence: [markdownviews.nim](src/merenda/nimkit/text/markdownviews.nim),
MarkdownBuilder, code-block rendering, xMarkdownRoot, and xMatterHighlights;
[markdownparsing.nim](src/merenda/nimkit/text/markdownparsing.nim),
highlightCodeBlocks;
[application_editor.nim](src/merenda/kosmo/application_editor.nim),
syncSelectedEditorContent and markdownViewForBuffer.

- [ ] Add immutable storage range views for embedded code/table text. Code
  blocks retain child storage and append the same bytes into the main document.
  Include a stable style table and range origin in the view; borrowing mutable
  storage style IDs is insufficient.
- [ ] Intern builder attributes while building instead of keeping full
  TextAttributeRun payloads until final storage construction.
- [ ] Key code-block highlights by document generation and block ID/range,
  with optional collision-checked content deduplication. The current table
  retains complete code strings in (source, language) keys alongside the AST
  and rendered storages. Return borrowed spans when their lifetime allows it.
- [ ] Lazily materialize embedded layouts, and consider releasing reconstructible
  AST/render state for inactive previews. Preserve heading folding and resize
  behavior that currently reuse the AST.
- [ ] Budget Kosmo Markdown previews by retained bytes as well as count. A
  three-preview limit already exists; three large ASTs, layouts, images, and
  storages can still be expensive, especially across panes.
- [ ] Gate preview synchronization by Moe buffer content version before calling
  bufferText(). It builds a complete string before markdown= can reject an
  unchanged value. Share immutable document data across panes where feasible.

## 8. Stream Kosmo terminal search

Evidence: [terminalsearch.nim](src/merenda/kosmo/terminalsearch.nim),
TerminalSearchGlyph, terminalSearchGlyphs, and terminalSearchMatches.

- [ ] Search line/cell iterators directly with a streaming matcher and only
  enough source-coordinate history for a match. Each query builds a sequence
  containing a rune and two terminal positions for every character in the
  entire screen and scrollback, including blank cells.
- [ ] Decode compact scrollback incrementally instead of keeping an expanded
  coordinate record for every rune. Retain only matched ranges, or offer a
  bounded/lazy match index for queries with very many matches.
- [ ] Preserve matching across soft wraps, hard newlines, wide-cell continuation
  markers, combining sequences, and case normalization. Invalidate results on
  scrollback eviction/reset so row coordinates remain meaningful.

This is separate from terminal rendering, which already stores only viewport
rows in MonoText; the search path is what expands the whole history.

## 9. Compact MonoText and avoid intermediate viewport grids

Evidence: [monotextviews.nim](src/merenda/nimkit/text/monotextviews.nim),
MonoTextCell, textToCells, and replaceGrid;
[application_editor.nim](src/merenda/kosmo/application_editor.nim), renderGrid;
[terminalviews.nim](src/merenda/nimkit/terminal/terminalviews.nim),
terminalRowsToMonoTextCells and synchronizeTerminalGrid.

- [x] Store each row as one UTF-8 buffer, cell byte/rune endpoints, and interned
  styles. A row with one style omits the per-cell style-ID array, including
  blank/default rows.
- [x] Preserve cells containing multiple runes and terminal continuation cells.
  The packed row keeps full cell text; the terminal adapter renders continuation
  cells as spaces.
- [x] Stream Moe and Terminex rows into MonoText without a full temporary
  `seq[MonoTextCell]`. Borrow source symbols and compare each cell before
  allocating a replacement row. Existing `replaceGrid` callers retain their
  cell-based entry point.
- [x] Reuse shifted terminal rows across changed-screen generations, then
  rebuild only rows whose rendered cells differ. Unchanged-generation scrolling
  still streams only newly exposed rows.

### Profile: MonoText viewport grids

The reproducible [benchmark](tests/benchmarks/monotextmemory.nim) uses a
250 × 320 ASCII grid with one changed cell per frame. Release/ARC builds on
macOS used `-d:nimAllocStats`; results are medians of three standalone runs
against parent `4cafb140` and this change. Heap figures are live bytes across
all malloc zones, while allocation figures count Nim allocator calls.

| Measure | Before | After |
| --- | ---: | ---: |
| Synthetic upstream symbols, live heap | 2,692,128 B | 2,692,128 B |
| Populated Celina editor buffer, live heap | 5,258,224 B | 5,258,224 B |
| Populated Terminex screen, live heap | 5,769,568 B | 5,769,568 B |
| MonoText viewport, live heap | 12,939,280 B | 895,680 B |
| Initial grid allocation calls | 160,252 | 1,002 |
| One-cell changed frame allocation calls | 80,000 | 5 |
| Unchanged frame allocation calls | 80,000 | 1 |

The synthetic source and view setup are measured before the viewport is filled;
they are excluded from the viewport figure. A populated Celina buffer, the
cell store used by Moe's render buffer, and a populated Terminex screen are
measured separately after the grid operations. Current RSS growth ranged from
about 13 to 20 MiB before and
0.15 to 0.93 MiB after; it depends on allocator page reuse and is diagnostic
only. The fixture isolates grid transfer; it does not include Moe's render pass,
terminal row extraction, terminal parsing, glyph creation, or a varied-color
screen. The Terminex figure includes a separate parse of the same ASCII grid.
Changed generations still compare the visible cells; this bounds
allocation traffic, though it does not remove the scan.

## 10. Reduce Kosmo Matter request and line allocations

Evidence: [moe.nim](src/merenda/kosmo/moe.nim), scheduleMatterHighlighting;
[matterworkers.nim](src/merenda/kosmo/matterworkers.nim), requestMatterHighlight,
highlightMatter, runeColumns, and addLineSegments.

- [ ] Reuse an immutable source per buffer content version, or send changed
  lines with lexical-state checkpoints. Each new request calls getTextString()
  and the worker then splits the full source into owned line strings. Iterate
  line ranges and materialize only the current tokenizer line if its API
  requires a string.
- [ ] Coalesce superseded requests before transferring their source payloads
  and bound queued source bytes. Cancellation already exists and prevents
  stale work from publishing, but an enqueued cancelled request still owns its
  payload until consumed. Keep buffer/version checks and worker-local grammar
  state.
- [ ] Convert sorted Matter span endpoints to rune columns with a cursor instead
  of allocating runeColumns per line. This is lower priority than the
  whole-document maps: parsing already has a 1,024-byte line limit and a deadline.

Kosmo's main editor uses Moe buffers; NimKit TextStorage improvements do not
automatically change this path. Keep any upstream buffer redesign separate.

## 11. Share Git Diff patch payloads across owners

Evidence: [gitdiff.nim](src/merenda/kosmo/gitdiff.nim), GitFileDiff,
GitDiffSection, GitDiffHighlightKey, patch completion, and mergeSectionIntoSnapshot.

- [ ] Store immutable patch payloads once per file/revision and reference them
  from snapshot metadata, materialized sections, and highlight requests. Loaded
  patch and syntaxPatch strings are copied back from sections into snapshot
  files, while display TextStorage and queued/cache keys can own more copies.
- [ ] Keep visible and full-context syntax patches distinct when their contents
  differ; deduplicate ownership of each instead of dropping syntax context.
- [ ] Account for actual retained payloads, style runs, and layouts in a document
  memory budget. Existing per-file/total patch limits, highlight queue/cache byte
  limits, and section/view-pool limits should remain; this is not an unbounded
  cache discovery.

## 12. Reuse snapshots in text helpers and native queries

Evidence: [textruneutils.nim](src/merenda/nimkit/text/textruneutils.nim),
utf8RunesForText; [textviews.nim](src/merenda/nimkit/text/textviews.nim),
applySmartInsert; [textlayout.nim](src/merenda/nimkit/text/textlayout.nim),
defaultGlyphProperties;
[textsnapshots.nim](src/merenda/nimkit/text/textsnapshots.nim), bytes and lineRange.

- [ ] Pass the storage's existing snapshot to word, smart-insertion, and pending
  layout queries instead of stringValue() followed by another UTF-8 copy and
  index build. Preserve the helper's malformed-input replacement semantics;
  direct source reuse needs equivalent semantics or a cached normalized view.
- [ ] Add byte-range operations across the native facade. Its snapshot bytes
  accessor returns a whole owned string, whereas the static path borrows it.
  Substrings and repeated native queries should not materialize the entire
  source just to inspect a short range. Keep native ownership/lifetime explicit.

## 13. Share layout resources and remove redundant glyph geometry

Evidence: [textviews.nim](src/merenda/nimkit/text/textviews.nim),
glyphLineArrangement, drawTextViewText, and drawTextViewTextInViewport;
[renderscenes.nim](src/merenda/nimkit/drawing/renderscenes.nim),
isolateGlyphArrangement;
[fonttypes.nim](deps/figdraw/src/figdraw/common/fonttypes.nim),
ArrangedGlyph and GlyphArrangement.

- [ ] Use immutable layout resources plus glyph-range views for line render
  nodes. Current line arrangements slice glyphs, display text, positions, and
  selection rectangles; render isolation copies the arrays and text again.
- [ ] Use viewport drawing for appropriate long TextViews. It already exists
  and Markdown uses it, but it still retains a complete document layout.
  True viewport-only layout is a separate project requiring height estimates,
  selection/navigation support, and offscreen layout invalidation.
- [ ] Preserve source/display aliasing when isolating layouts; two independent
  copyUtf8Runes() calls duplicate identical buffers when both fields share
  one source. Share more broadly only with a safe immutable thread owner.
- [ ] Remove compatibility positions/selectionRects arrays where consumers can
  read ArrangedGlyph.pos/.rect. They add roughly 24 bytes per glyph with the
  current float32 geometry. Consider checked 32-bit source ranges under the
  existing UTF-8 size limit, and lazy display-text materialization.

## Verification and measurement backlog

- [ ] Add allocation/retained-byte checks for large dynamically generated text,
  many short styled runs, many paragraphs, long scrollback, Markdown tables,
  rapid highlighting requests, and repeated width-only reflows. Pointer identity
  proves sharing of one field, not the absence of another retained copy.
- [ ] Measure source bytes, styles/runs, undo history, worker payloads, layouts,
  and render replicas independently, including peak overlap between generations.
- [ ] Measure allocation scaling through both backends, including partial-run
  fallback and static/native facade paths. Preserve the existing source-identity,
  width-changing case conversion, control-filtering, and empty-input regression
  tests added by the FigDraw follow-up.
- [ ] Extend native-facade coverage for UTF-8 lookup, iteration, slicing, equality,
  and source-span layout, including allocation behavior at the ABI boundary.

Keep rune-based public APIs and intentional compatibility conversions. Rich
per-cell/per-rune records need purpose-built compaction rather than mechanical
replacement with Utf8Runes.
