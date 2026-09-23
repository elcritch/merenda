# TODO: Reduce text memory in NimKit and Kosmo

Source review: 2026-09-23. This file tracks remaining work. Completed changes
are summarized in [CHANGES.md](CHANGES.md); their measured results are below.
NimKit stores UTF-8 in shared immutable snapshots with sparse indexes and
compact style IDs. Editing ranges remain rune-based; tokenizer and layout
endpoints can use byte ranges. Build further optimizations on these facilities.

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

## Public text API question

- [ ] Decide later whether a byte-native highlighter callback would simplify
  external tokenizer adapters enough to justify a second callback surface.
  Keep rune-based editing ranges and `SyntaxTokenSpan`; a byte-to-rune
  conversion must reject endpoints inside a multibyte rune. Grapheme-based
  caret movement is separate future work.

## Extend SynEdit incremental tokenization

Evidence: [syneditviews.nim](src/merenda/nimkit/text/syneditviews.nim),
applySyntaxHighlightingForEdit and the built-in tokenizer cache.

- [ ] Extend incremental tokenization across multiline lexical state and custom
  highlighters. Safe single-line built-in edits already retokenize locally;
  these remaining paths still use a full new token cache. Keep complete/partial
  coverage, overlapping-range semantics, and delegate hooks.

## Check SynEdit tokenizer source ownership

Evidence: [syneditviews.nim](src/merenda/nimkit/text/syneditviews.nim),
SynEditHighlightBuffer and tokenSpans.

- [ ] Check whether `SynEditHighlightBuffer.source` still copies the input
  string. The 8 MiB tokenizer sample retains about 8 MiB after conversion;
  borrow the source through tokenizer parameters if this is the remaining copy,
  and remeasure without introducing an unsafe pointer lifetime.

## Preserve compact input across background layout

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

## Reduce edit-history storage with deltas or shared chunks

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

## Compact Markdown table rendering

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

## Share Markdown children and budget preview caches

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

## Stream Kosmo terminal search

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

## Reduce Kosmo Matter request and line allocations

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

## Share Git Diff patch payloads across owners

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

## Reuse snapshots in text helpers and native queries

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

## Share layout resources and remove redundant glyph geometry

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

## Measurements from completed changes

The text-editing profiles compared Merenda `dd933623` with `172eedf1` in three
standalone release/ARC runs per build on macOS, using the same static FigDraw
dependency tree. Values are median current RSS growth after each operation;
they include allocator retention and are not allocation counts.

| Workload | Before | After |
| --- | ---: | ---: |
| 8 MiB gap edit, undo disabled | 20,816 KiB | 4,384 KiB |
| 8 MiB gap edit, undo enabled | 20,864 KiB | 12,640 KiB |
| Tokenize 8 MiB of spaces with SynEdit | 81,968 KiB | 8,208 KiB |
| Apply 2,048 token styles over 1 MiB | 1,440 KiB | 1,312 KiB |

The bulk style update took about 0.336 s before and 0.006 s after, despite its
small RSS change. Over 8 MiB of UTF-8 (`4,194,304` `é` runes), iterating a
snapshot added 0 KiB current RSS; materializing `toRunes()` added 16,432 KiB.

The [MonoText benchmark](tests/benchmarks/monotextmemory.nim) uses a 250 × 320
ASCII grid with one changed cell per frame. It compares parent `4cafb140` with
the compact row implementation after removing its uniform-style special case
and owned-grid adapters. Values are medians of three standalone macOS
release/ARC runs. Heap figures are live bytes across all malloc zones;
allocation figures count Nim allocator calls.

| Measure | Before | After |
| --- | ---: | ---: |
| Synthetic upstream symbols, live heap | 2,692,128 B | 2,692,128 B |
| Populated Celina editor buffer, live heap | 5,258,224 B | 5,258,224 B |
| Populated Terminex screen, live heap | 5,769,568 B | 5,769,568 B |
| MonoText viewport, live heap | 12,939,280 B | 1,277,632 B |
| Initial grid allocation calls | 160,252 | 1,252 |
| One-cell changed frame allocation calls | 80,000 | 6 |
| Unchanged frame allocation calls | 80,000 | 1 |

The upstream buffers were measured separately from the viewport. This fixture
isolates grid transfer; it excludes Moe's render pass, terminal row extraction,
glyph creation, and varied-color screens. Changed generations still compare
visible cells. RSS varies with allocator page reuse, so the heap and allocation
figures are more useful for this comparison.
