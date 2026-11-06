# TODO: Reduce text memory in NimKit and Kosmo

Source review and profiling: 2026-11-06, against Merenda `24896588` and the same
Atlas dependency tree. The first implementation batches are committed separately
on `utf8-memory-followups`; current allocation profiles and historical results
are distinguished below. Completed changes are summarized in [CHANGES.md](CHANGES.md).
NimKit stores UTF-8 in shared immutable snapshots with sparse indexes and
compact style IDs. Editing ranges remain rune-based; tokenizer and layout
endpoints can use byte ranges. Build further optimizations on these facilities.

Accept changes that reduce rich-text memory or keep it effectively unchanged
while making the UTF-8 API more consistent. Verify equivalent text workloads
before and after each change; investigate increases in retained heap or peak
memory rather than assuming fewer copies imply lower total memory. Use Markdown
views and attributed-text reflows to exercise the public text APIs.

## Current status

The UTF-8/storage foundation and all four checked layout-resource changes below
are implemented. Most remaining reductions in source, undo, worker, and preview
memory are still open. Checkbox counts are not an estimate of implementation
effort: this document already excluded much of the completed foundation.

| Area | Status from current source |
| --- | --- |
| Shared UTF-8 snapshots, sparse indexes, compact style IDs | Implemented; retain existing behavior |
| Shared glyph-range layouts and viewport drawing | Four listed tasks complete; full layout still retained |
| SynEdit incremental tokenization | Single-line fast path only; multiline/custom paths still open |
| SynEdit tokenizer source ownership | Scoped borrow implemented; an 8 MiB copy is absent in allocation stacks |
| Background layout requests | Compact interned payload implemented; source caching deferred pending a reliable memory benefit |
| Edit history | Still retains before/after storages; grouping exists, deltas/budget remain open |
| Markdown tables and embedded storage | UTF-8 cells/word ranges, table-only overflow storage, and compact builder styles implemented; shared child text remains open |
| Markdown child layout | Lazy creation implemented; releasing inactive state remains open |
| Terminal search | Compact row/exception mapping implemented on this branch; full search text and match list remain |
| Kosmo Matter | Current-line processing implemented; source reuse, queue-byte bounds, and rune-column cursor remain open |
| Git Diff | Patch ownership duplication remains; existing payload/cache limits are retained |

Implementation on branch `utf8-memory-followups` covers terminal search mappings,
compact background-layout payloads, and Markdown table temporaries. The detailed
checklist records validation below. The shared NimKit runner and all eight
terminal-search tests pass.

## Priorities

| Priority | Work | Main benefit |
| --- | --- | --- |
| 1 | Stream/bound Kosmo terminal search | Avoid a full search subject and unbounded match list |
| 2 | Measure compact layout payload reuse | Verify reflow allocation savings and revision-overlap memory |
| 2 | Share Markdown embedded text and intern builder styles | Reduce duplicate retained text and style payloads |
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

- [x] Inspect source ownership: the previous `SynEditHighlightBuffer.source`
  assignment copied an owning string under ARC.
- [x] Borrow the source for synchronous tokenization and byte-to-rune span
  conversion. The buffer is local to `internalTokenSpans` and cannot outlive the
  source parameter; returned spans own no source references. Dynamic temporary
  input and malformed UTF-8 coverage pass. ARC expansion and allocator stacks
  confirm removal of the 8 MiB copy; retained allocation size is unchanged.

## Preserve compact input across background layout

Evidence: [textlayout.nim](src/merenda/nimkit/text/textlayout.nim),
startBackgroundTextLayout;
[textlayoutworkers.nim](src/merenda/nimkit/text/textlayoutworkers.nim),
requestTextLayout.

- [x] Replace the worker request's string plus seq[TextAttributeRun] with
  a detached compact value payload. The implementation on this branch carries
  UTF-8 bytes, style-ID runs, and an interned style table via `TextLayoutSource`;
  worker storage is reconstructed without expanded runs or style re-interning.
- [x] Define safe ownership for the complete payload. Ordinary ARC ref sharing
  across threads is not made safe merely by immutable bytes. Use the project's
  transfer/shared-owner facilities. This branch transfers detached values via
  `ConstPtr`, releases the payload after processing, and retains worker-local
  storage.
- [ ] Reuse worker source state for width-only reflows only after demonstrating
  a reliable memory benefit. A token-based cache was profiled and removed from
  the selected implementation: live heap was close to baseline, but RSS peaks
  were variable and did not establish an improvement. The selected version
  transfers compact data and constructs worker-local storage for every request.
  Preserve one-pending-request coalescing and stale-generation checks.
- [x] Measure the selected compact payload across repeated width reflows and a
  style revision; keep raw samples in
  [text-reflow-memory-2026-11-06.json](tests/benchmarks/results/text-reflow-memory-2026-11-06.json).
  Live heap remained close to baseline. UTF-8 indexes are rebuilt in worker-local
  storage, not transferred from the UI. This is not shared snapshot identity
  across threads, and source caching remains deferred.
- [x] Avoid populating a gap storage's cached text snapshot when preparing a
  worker payload. `storageString()` preserves custom overrides and avoids
  retaining another full UI-side UTF-8 buffer. An 8 MiB gap-source control
  benchmark confirms the extra cache costs about 8.36 MiB of retained heap.

## Reduce edit-history storage with deltas or shared chunks

Evidence: [textviews.nim](src/merenda/nimkit/text/textviews.nim), TextUndoRecord,
xMarkedUndoStorage, and grouped undo;
[textstorage.nim](src/merenda/nimkit/text/textstorage.nim), replaceStorageText
and applySnapshot.

- [ ] Store removed/inserted text, affected style ranges, and selection state
  in undo records instead of entire before/after storages.
- [ ] Coalesce typing and composition edits, and support an undo byte budget.
  Explicit `beginUndoGrouping`/`endUndoGrouping` and marked-text grouping already
  exist; they still record complete `storageBefore`/`storageAfter` values.
- [ ] Evaluate persistent chunks or a piece table for large editable documents.
  Sharing snapshots makes copies of an unchanged revision cheap; it does not
  share unchanged portions between character revisions. Ordinary replacement
  still slices/concatenates a complete new string and rebuilds its indexes.
- [ ] Keep gap storage's compact mutable representation where useful; switching
  every TextView to gap storage alone does not solve history copies.

## Compact Markdown table rendering

Evidence: [markdownviews.nim](src/merenda/nimkit/text/markdownviews.nim),
MarkdownTableCell, wrapTableCell, and renderTable.

- [x] Represent cell text as UTF-8 plus style runs, attachments as sparse
  ranges, and wrapped words as boundaries into cell text. Full attributes remain
  once per style run, so builder-wide style interning remains a separate task
  below.
- [x] Remove full TextAttributes, image references, and image sizes from each
  ordinary rune. This branch removes `MarkdownTableRune` and stores word ranges
  in wrapped lines.
- [x] Build overflowing table storage independently. This branch slices only
  table bytes and clips relevant runs before constructing storage, avoiding
  full-prefix storage/index construction.

These per-rune table records are rendering temporaries, not permanently retained
by MarkdownView. The primary gain is lower rendering/resize peak memory and
allocation traffic; embedded table storage is a separate retained cost.

## Share Markdown children and budget preview caches

Evidence: [markdownviews.nim](src/merenda/nimkit/text/markdownviews.nim),
MarkdownBuilder, code-block rendering, xMarkdownRoot, and xMatterHighlights;
[markdownparsing.nim](src/merenda/nimkit/text/markdownparsing.nim),
continueMarkdownHighlight;
[application_editor.nim](src/merenda/kosmo/application_editor.nim),
syncSelectedEditorContent and markdownViewForBuffer.

- [ ] Add immutable storage range views for embedded code/table text. Code
  blocks retain child storage and append the same bytes into the main document.
  Include a stable style table and range origin in the view; borrowing mutable
  storage style IDs is insufficient.
- [x] Intern builder attributes while building instead of keeping full
  TextAttributeRun payloads until final storage construction. `TextRunBuilder`
  transfers compact runs and a stable palette into storage; builder merges
  remap styles once, and range-only lookups do not copy attributes. The separate
  builder batch passes the shared NimKit runner and allocation verification.
- [ ] Key code-block highlights by document generation and block ID/range,
  with optional collision-checked content deduplication. Highlight results now
  arrive in generation-checked batches indexed into `xMatterHighlights`, but
  `xMatterCodeIndices` still retains complete `(source, language)` keys alongside
  the AST, presentations, and rendered storages. Return borrowed spans when
  their lifetime allows it.
- [x] Lazily create embedded code/table views and their secondary layouts near
  the buffered viewport. Fitting code blocks reuse parent geometry without
  creating an embedded view. See `layoutMarkdownCodeBlocks`,
  `layoutMarkdownCodeBlock`, and `layoutMarkdownTables`, plus the existing tests
  "fitting code blocks do not allocate embedded text views" and "offscreen code
  and table scroll views are created near the viewport" in
  [markdownviews.nim](tests/nimkit/markdownviews.nim).
- [ ] Release reconstructible AST/render state for inactive previews where
  useful. Offscreen child views are currently hidden, not evicted; child storage
  is prepared during rendering and the AST remains retained. Preserve heading
  folding and resize behavior that currently reuse this state.
- [ ] Budget Kosmo Markdown previews by retained bytes as well as count. A
  three-preview limit already exists; three large ASTs, layouts, images, and
  storages can still be expensive, especially across panes.
- [ ] Gate preview synchronization by Moe buffer content version before calling
  bufferText(). It builds a complete string before markdown= can reject an
  unchanged value. Share immutable document data across panes where feasible.

## Stream Kosmo terminal search

Evidence: [terminalsearch.nim](src/merenda/kosmo/terminalsearch.nim),
TerminalSearchSnapshot, terminalSearchSnapshot, and terminalSearchMatches.

- [x] Replace per-character glyph-coordinate records with compact mappings.
  This branch retains UTF-8 search text, one record per row, and sparse exceptions
  for wide/combining cells. The eight terminal-search tests pass, including
  combining cells, regex boundaries, and refreshed output.
- [ ] Search line/cell iterators directly with a streaming matcher and only
  enough source-coordinate history for a match. The current regex/literal
  adapter still requires a complete search subject, including blank cells.
- [ ] Decode compact scrollback incrementally instead of keeping an expanded
  coordinate record for every rune. Retain only matched ranges, or offer a
  bounded/lazy match index for queries with very many matches.
- [x] Preserve matching across soft wraps, hard newlines, wide-cell continuation
  markers, combining sequences, and case normalization. Invalidate results on
  scrollback eviction/reset so row coordinates remain meaningful. Navigation
  refreshes the search snapshot before revealing a match; matching still uses
  the existing normalization/search implementation.

This is separate from terminal rendering, which already stores only viewport
rows in MonoText. Compact mapping removes dense coordinates but the search
subject still spans the whole history.

## Reduce Kosmo Matter request and line allocations

Evidence: [moe.nim](src/merenda/kosmo/moe.nim), scheduleMatterHighlighting;
[matterworkers.nim](src/merenda/kosmo/matterworkers.nim), requestMatterHighlight,
continueMatterHighlight, runeColumns, and addLineSegments.

- [x] Iterate line ranges and materialize only the current tokenizer line.
  `MatterHighlightJob` keeps `source` and `lineStart`; `continueMatterHighlight`
  searches for the next newline and slices one line per iteration, with bounded
  batches and cancellation checks. It no longer splits the full document into
  a retained sequence of line strings.
- [ ] Reuse an immutable source per buffer content version, or send changed
  lines with lexical-state checkpoints. `scheduleMatterHighlighting` still
  calls `getTextString()` for each new request and transfers a full source;
  current-line iteration does not eliminate this payload.
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

## Reuse snapshots in text helpers

Evidence: [textruneutils.nim](src/merenda/nimkit/text/textruneutils.nim),
utf8RunesForText; [textviews.nim](src/merenda/nimkit/text/textviews.nim),
applySmartInsert; [textlayout.nim](src/merenda/nimkit/text/textlayout.nim),
defaultGlyphProperties;
[textsnapshots.nim](src/merenda/nimkit/text/textsnapshots.nim), bytes and lineRange.

- [ ] Pass the storage's existing snapshot to word, smart-insertion, and pending
  layout queries instead of stringValue() followed by another UTF-8 copy and
  index build. Preserve the helper's malformed-input replacement semantics;
  direct source reuse needs equivalent semantics or a cached normalized view.

## Share layout resources and remove redundant glyph geometry

Evidence: [textviews.nim](src/merenda/nimkit/text/textviews.nim),
glyphLineArrangement, drawTextViewText, and drawTextViewTextInViewport;
[renderscenes.nim](src/merenda/nimkit/drawing/renderscenes.nim),
isolateGlyphArrangement;
[fonttypes.nim](deps/figdraw/src/figdraw/common/fonttypes.nim),
ArrangedGlyph and GlyphArrangement.

- [x] Use immutable layout resources plus glyph-range views for line render
  nodes. Each view holds an atomic owner and local style spans; render isolation
  retains the owner instead of copying glyphs and text again.
- [x] Use viewport drawing for TextViews with more than 256 visual lines. It
  still retains a complete document layout.
- [x] Preserve source/display aliasing while freezing and isolating layouts.
  A named ref identity check avoids copying the same UTF-8 buffer twice.
- [x] Drop positions/selectionRects from frozen layouts when ArrangedGlyph
  already has pos/rect, saving roughly 24 retained bytes per glyph. FigDraw's
  directly returned layouts keep their compatibility arrays.

Follow-up: true viewport-only layout needs height estimates, selection and
navigation support, and offscreen invalidation. Consider checked 32-bit source
ranges under the UTF-8 size limit and lazy display-text materialization.

Memory profile (macOS arm64, ARC release, 192,000 glyphs in 1,200 lines, both
UI line nodes and isolated replicas retained):

| Layout path | Heap after setup | Retained heap | RSS after setup | Retained RSS |
| --- | ---: | ---: | ---: | ---: |
| Copied line arrays | 25.4 MiB | 75.8 MiB | 31.1 MiB | 81.3 MiB |
| Shared range views | 25.4 MiB | 20.3 MiB | 31.1 MiB | 50.4 MiB |

The standalone benchmark is [layoutmemory.nim](tests/benchmarks/layoutmemory.nim).
Separate process runs were stable across three repetitions. RSS includes
allocator pages retained after the shared layout replaces the initial layout;
live heap better reflects retained layout data. This profiles synthetic layout
retention, not font shaping or full application memory.

README Markdown load profile (macOS arm64, ARC release, four samples, median):

| Version | Parse and apply | Layout | First render |
| --- | ---: | ---: | ---: |
| `origin/main` | 74.8 ms | 130.5 ms | 3.6 ms |
| Shared layout before borrow fix | 75.1 ms | 4,863.8 ms | 3.1 ms |
| Shared layout with borrowed accessor | 76.0 ms | 128.0 ms | 3.3 ms |

The standalone benchmark is [benchmark_markdown_load.nim](tests/benchmark_markdown_load.nim).
It loads this repository's README (14,237 runes; 393 visual lines) and separates
construction, parse/apply, layout, and first render. A stack sample traced the
regression to deep copies of the full `GlyphArrangement` while computing line
fragments: an `if` expression in `xLayout` materialized a value on every access.
Returning `lent GlyphArrangement` directly from each branch makes the generated
code borrow the arrangement and restores layout time to the main-branch range.

## Verification and measurement backlog

- [ ] Add allocation/retained-byte checks for large dynamically generated text,
  many short styled runs, many paragraphs, long scrollback, Markdown tables,
  rapid highlighting requests, and repeated width-only reflows. Pointer identity
  proves sharing of one field, not the absence of another retained copy.
- [ ] Measure source bytes, styles/runs, undo history, worker payloads, layouts,
  and render replicas independently, including peak overlap between generations.
- [ ] Measure allocation scaling through both backends, including partial-run
  fallback on the supported Pixie/Harfbuzzy paths. Preserve the existing
  source-identity, width-changing case conversion, control-filtering, and
  empty-input regression tests added by the FigDraw follow-up.

Existing behavioral coverage includes UTF-8 lookup/ranges, compact style updates,
source identity, and shared layout ownership in `tests/nimkit/textstorage.nim`,
`tests/nimkit/textlayout.nim`, and FigDraw's `tests/tfontutils.nim`. These tests do
not replace the allocation and retained-byte measurements above.

Keep rune-based public APIs and intentional compatibility conversions. Rich
per-cell/per-rune records need purpose-built compaction rather than mechanical
replacement with Utf8Runes.

## Allocation verification for the current feature sets

The following measurements use matched before/after binaries, the same Atlas
dependencies, and classic `nim c -d:release --mm:arc` on macOS arm64. Component
validation uses the repository's `nim ic` shared runners. Allocation profiles use
`MallocStackLogging`, `leaks --fullStackHistory --outputGraph`, and
`malloc_history -highWaterMark -callTree`; they identify live allocation stacks,
unlike process RSS alone.

| Workload and captured checkpoint | Logged live allocations, before → after | Logged peak, before → after | Cumulative allocation bytes, before → after |
| --- | ---: | ---: | ---: |
| 2,000-row Markdown table, attributed storage constructed | 1.5 MB → 1.5 MB | 88.2 MB → 28.9 MB | 583.9 MB → 276.3 MB |
| 500-row Markdown table view, first render | 228.3 MB → 228.3 MB | 293.5 MB → 284.3 MB | 43.49 GB → 43.4 GB |
| SynEdit, tokenize 8 MiB of spaces | 8.2 MB → 8.2 MB | 16.2 MB → 8.2 MB | 17.6 MB → 9.6 MB |
| 2,000-row table, compact table cells → compact builder styles | 1.59M → 1.59M | 28.9 MB → 13.7 MB | 276.3 MB → 227.7 MB |

These are Apple tool-reported heap/VM units, preserved as reported, not converted
to MiB. Each allocation-stack profile is one traced process; logging changes
allocation timing and excludes some startup blocks without recorded stacks. The
paired storage call trees both contain 757 live blocks / 1.59M, plus the same
816 unstacked blocks / 183K. Capturing after the first render does not include
the later resize phase in that graph's peak.

The old `tableRunes` allocation stack accounts for 7,994 blocks / 67.4M at the
storage-construction peak. After its removal, expanded builder attribute-run
arrays were the next large stacks. The separate builder-interning batch removes
those arrays and further lowers the peak to 13.7 MB; allocation event count
increases slightly while cumulative allocated bytes decrease. Its retained
checkpoint has 756 blocks / 1.59M versus 757 / 1.59M before. The old SynEdit stack contains an 8.00M `nimAsgnStrV2` allocation under
`internalTokenSpans`; that allocation is absent after the scoped borrow.

Full Markdown view profiles retain the same 10 HarfBuzz fallback-font blob
allocations / 78.5M before and after. They are a substantial existing rich-text
cost, not a saving from the UTF-8 changes.

Raw process and allocation summaries, build/source hashes, commands, checkpoint
details, and limitations:

- [Markdown allocation stacks](tests/benchmarks/results/markdown-allocations-2026-11-06.json).
- [SynEdit allocation stacks](tests/benchmarks/results/synedit-allocations-2026-11-06.json).
- [Compact builder allocation stacks](tests/benchmarks/results/markdown-builder-allocations-2026-11-06.json).
- [Markdown fresh-process samples](tests/benchmarks/results/markdown-memory-2026-11-06.json):
  nine storage and nine prose/code control runs per version, three table-view
  runs per version. RSS peaks vary; they are not a count of retained text objects.
- [Attributed-text reflows](tests/benchmarks/results/text-reflow-memory-2026-11-06.json).
- [Gap-source cache control](tests/benchmarks/results/text-gap-source-memory-2026-11-06.json):
  an explicit precache mode reproduces the previous path in the same binary;
  this is not a separate baseline checkout.

Reproduce checkpoint captures using the tracked probes and driver described in
[ALLOCATION-PROFILING.md](tests/benchmarks/ALLOCATION-PROFILING.md).

The measured first batches reduce temporary allocation and keep retained rich
text allocations unchanged at these checkpoints. Keep this as an acceptance
criterion for subsequent work, rather than extrapolating it to unmeasured APIs.

## Historical measurements from completed changes

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
