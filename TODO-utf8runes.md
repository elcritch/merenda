# TODO: Reduce text memory in NimKit and Kosmo

Source review: 2026-09-23. Baseline: Sol's implementation plus the follow-up
commits Merenda `66e5cb15` and FigDraw `e742041`, which landed during this review.
This is a source-based backlog; no builds, tests, or allocation measurements
were run for this review. Completed migration tasks and historical test claims
have been removed.

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
| 1 | Gate undo copies and batch highlighting updates | Remove repeated document/run-table copies during edits |
| 1 | Remove dense maps and SynEdit's per-byte token cells | Lower highlighting peak memory |
| 1 | Stream Kosmo terminal search | Avoid expanding all scrollback into coordinate records |
| 2 | Preserve snapshots across layout worker requests | Avoid source copies and expanded attribute runs |
| 2 | Compact Markdown tables and share embedded text | Reduce render peaks and duplicate retained text |
| 2 | Compact MonoText and update grids by changed rows | Reduce retained cell size and frame allocations |
| 2 | Reduce Kosmo Matter and Git Diff source duplication | Bound worker and document working sets |
| 3 | Use edit deltas/chunks and share layout geometry | Larger structural reductions for long documents |

Priorities are estimates from the code paths, not measured rankings. Distinguish
retained memory, transient peak memory, and allocation traffic when evaluating
each change.

## 1. Avoid snapshots when undo will not use them

Evidence: [textstorage.nim](src/merenda/nimkit/text/textstorage.nim),
replace, setAttributes, stringValue=, registerSnapshotUndo, and copyStorageTextTo;
[gaptextbuffers.nim](src/merenda/nimkit/text/gaptextbuffers.nim), copyGapTextBuffer;
[textviews.nim](src/merenda/nimkit/text/textviews.nim), replaceRange and recordUndo.

- [ ] Create storage undo snapshots only after checking the undo manager.
  Mutation paths copy before registerSnapshotUndo checks it. Ordinary storage
  now shares source bytes, but still copies runs/styles; gap storage copies
  both byte arrays and discards the copied storage's snapshot cache.
- [ ] Transfer the prepared undo snapshot into the undo closure instead of
  copying it again in registerSnapshotUndo.
- [ ] Apply the same rule to TextView's independent undo stack. replaceRange
  captures storage and a complete beforeValue before edit approval, even when
  recording is disabled; recordUndo checks allowsUndo later. Preserve delegate
  ordering and actual value-change notification semantics using a small edit
  comparison or a character revision where possible.
- [ ] Avoid full-text equality strings in recordUndo and replaceAllText.
  Grouped undo still creates intermediate copies for each replacement.

Verify allocations with undo disabled, enabled, grouped, and during marked-text
composition. Cover ordinary and gap storage separately.

## 2. Apply highlighting as one compact run-table update

Evidence: [syneditviews.nim](src/merenda/nimkit/text/syneditviews.nim),
applyCachedHighlighting and applySyntaxHighlightingForEdit;
[textstorage.nim](src/merenda/nimkit/text/textstorage.nim), setAttributes,
styleId, and normalizeRuns.

- [ ] Add an internal bulk attribute-range update that interns styles once,
  merges sorted ranges once, and normalizes once. SynEdit resets the affected
  range and calls setAttributes for every intersecting token. beginEditing
  batches notifications, but does not defer snapshot creation or normalization.
- [ ] Compact an existing style table by remapping old IDs to new IDs; avoid
  comparing full TextAttributes against every compacted style for every run.
  Current normalization is O(runs × distinct styles), with fresh sequences.
- [ ] Preserve complete/partial coverage, overlapping-range semantics, delegate
  hooks, and style-ID lifetime rules. styledSpans IDs currently refer to a
  mutable storage table only until its next edit.
- [ ] Follow up with incremental tokenization. The current edit path computes
  a full new token cache and a shifted old cache before finding the changed
  highlight range. Restricting attribute updates alone does not bound that peak.

## 3. Remove dense highlighting maps and per-byte token storage

Evidence: [matterhighlighting.nim](src/merenda/nimkit/text/matterhighlighting.nim),
byteRuneMap; [syneditviews.nim](src/merenda/nimkit/text/syneditviews.nim),
byteRuneMap, SynEditHighlightBuffer, and tokenSpans;
[markdownviews.nim](src/merenda/nimkit/text/markdownviews.nim),
renderBlockquote and addHighlightedCode.

- [ ] Replace whole-source byte-to-rune seq[int] maps with shared sparse lookup
  or a monotonic cursor over sorted token endpoints. Each existing map costs
  approximately eight bytes per source byte on a 64-bit build.
- [ ] Emit token ranges directly from SynEdit's tokenizer instead of storing
  a character and token class for every byte, then reconstructing ranges.
  Its buffer omits CR bytes: preserve or explicitly correct that source mapping
  when changing the representation.
- [ ] Replace Markdown's per-rune highlighted-code byte-offset array with
  endpoint conversion. Replace blockquote's per-rune source/destination map
  with segments at inserted-prefix and presentation-range boundaries.
- [ ] Keep public rune-based SyntaxTokenSpan APIs if needed. Validate emoji,
  multibyte boundaries, CRLF, malformed UTF-8, and nested blockquotes.

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

- [ ] Use row UTF-8 buffers plus cell offsets/lengths and interned style IDs.
  Current cells each contain an owned string, three colors, flags, traits, and
  decorations. Compress blank/default runs where it helps.
- [ ] Preserve strings containing multiple runes and terminal continuation
  cells. Replacing every cell with one Rune would break the existing contract.
- [ ] Feed changed rows/ranges into MonoText from Moe/Terminex, avoiding a full
  temporary seq[MonoTextCell] followed by another copy into xLines.
  replaceGrid skips an identical grid, but copies every cell when any differ.
- [ ] Extend existing terminal row reuse: it already reuses rows when scrolling
  an unchanged generation. Target changed-screen generations and Kosmo's full
  grid conversion, rather than reimplementing that optimization.

Measure per-frame allocation traffic separately from viewport retention and
upstream terminal/editor buffer storage.

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
