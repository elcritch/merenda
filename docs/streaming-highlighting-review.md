# Streaming syntax highlighting review

Reviewed on 2026-09-26 against `3512701f`, on
`review/streaming-syntax-highlighting`. Findings come from the current source and
Atlas dependencies in `nim.cfg`; the suggested batch sizes are starting points
for measurement. This review does not change runtime behavior.

## Recommendation

Stream completed ranges of syntax spans. Matter already tokenizes sequentially
by line and carries the grammar state into the next line. Keep that state on the
worker, and publish batches of completed lines while tokenization continues.

Start with Moe, where the current payload already contains color segments.
For the Markdown viewer, first deliver the parsed document before highlighting
its code blocks, then apply code colors as they arrive. Publishing document
content progressively is another useful step: the existing rendering chunks
yield to the event loop but keep their output private until the final chunk.

## Where the current waits occur

| Path | Current behavior | Change needed |
| --- | --- | --- |
| Kosmo's Matter worker | [`highlightMatter`](../src/merenda/kosmo/matterworkers.nim#L407) calls `tokenizeMatterLine` for each line and accumulates all `ColorSegment` values. [`requestMatterHighlight`](../src/merenda/kosmo/matterworkers.nim#L561) emits once after the loop. | Publish completed row ranges during the loop. No Matter parser change is needed for this first step. |
| Moe result application | [`applyMatterHighlightResult`](../src/merenda/kosmo/moe.nim#L1799) replaces the complete segment array, installs complete Markdown line flags, and scans URI underlines through EOF. | Replace only the covered rows, apply line flags and URI work for those rows, and track progress separately from completion. |
| Markdown worker | [`requestMarkdownParse`](../src/merenda/nimkit/text/markdownparsing.nim#L143) parses the complete Markdown AST, highlights every code block, then transfers the AST and a span cache together. | Transfer structure first; deliver code highlighting separately. |
| Markdown presentation | [`continueMarkdownRendering`](../src/merenda/nimkit/text/markdownviews.nim#L2222) builds up to 16 top-level blocks or about 4 ms of work per continuation, but calls `applyMarkdownDocument` only at EOF. A single large block can exceed that budget. | Apply highlights to existing storage; optionally publish completed presentation blocks earlier. |

Moe already receives colored spans rather than a Matter AST. The transferred AST
in the viewer belongs to **nim-markdown** and describes headings, lists, links,
tables, images, and code blocks. Matter supplies the code highlighting alongside
that structure.

The generic [`SyntaxHighlighter`](../src/merenda/nimkit/text/syntaxhighlighting.nim)
contract returns a complete `seq[SyntaxTokenSpan]`. Both that contract and
[`matterSyntaxHighlighterBounded`](../src/merenda/nimkit/text/matterhighlighting.nim#L153)
currently collect results before returning. The bounded function can return a
partial result when stopped, but exposes no continuation state for resuming it.
Repeatedly calling it on independent text chunks would lose grammar context.

## Line boundaries and delivery batches

A completed Matter line is a suitable publication boundary. Its colors are
available immediately, and its returned state describes how to parse the next
line. Multiline strings, comments, embedded languages, and Markdown fences mean
that adjacent lines generally need to be tokenized in order.

Use a batch of up to **64 lines or about 8 ms of worker work**, whichever is
reached first, checking the time after each completed line. These are proposed
tuning values, not measured optimal settings. Limit payload bytes as well, and
coalesce the resulting UI edits into at most one application per frame. A small
first batch can cover the initial viewport promptly.

The batch deadline is soft: one grammar call can run longer. Kosmo currently
allows a 100 ms soft deadline per line and skips lines over 1024 bytes. The
viewer uses Matter without a time limit through `matterSyntaxHighlighter`.
Streaming should retain the existing oversized-line recovery rules, add bounded
viewer calls, and never carry an interrupted tokenizer stack into the next line.
Grammar compilation also happens before the first tokens; streaming alone does
not remove that startup cost.

For an initial load, parse from the start. To prioritize a viewport far into a
file accurately, first establish the state at its starting line. Later, cache
states on the worker and resume from an earlier valid checkpoint after an edit.
Stop reparsing only when both tokenizer state and unchanged source alignment
converge. Kosmo's extra fence and embedded-language states must participate too.
Moe's dependency already has progressive and converging highlight machinery in
`moepkg/highlight.nim` and `moepkg/buffer/highlight.nim`; its invariants are useful
references, although Kosmo deliberately runs its Matter adapter separately.

## Moe: a direct first implementation

Extend the result protocol to describe a replacement range:

| Field | Purpose |
| --- | --- |
| Buffer ID, content version, request ID | Reject results for closed buffers or superseded text. |
| First row and exclusive end row | Identify complete row coverage, including rows with no colored tokens. |
| Color segments and Markdown code-block flags | Apply the styles and fence backgrounds for the same range together. |
| Completion status and optional error | Distinguish a progress batch from the final result. |

Retain Moe's existing rune-column `ColorSegment` representation for this adapter.
The UI maps its color roles through the current theme. No source text or grammar
objects need to accompany each batch after the request's source snapshot.

The receiving side needs more than an extra `emit` inside the loop:

- `receiveMatterHighlight` currently marks a request complete whenever a result
  arrives. Only the final result may satisfy `matterHighlightingReady`.
- Apply a batch by replacing its covered rows, including clearing previous
  colors when its span list is empty. Preserve other rows as the existing
  fallback until their replacements arrive.
- Preserve the partial Matter projection around Moe's built-in rendering pass.
  `pendingMatterSyntaxFallbacks` and `restoreMatterSyntaxFallbacks` currently
  protect a previously completed projection. They must also protect the current
  version's accumulated batches, including the first load.
- Keep Markdown fence flags current only through the valid frontier. The
  current complete-cache handling must not mark an unfinished document as fully
  parsed. Underline scans must be limited to the newly covered rows.
- Avoid copying or rebuilding the entire segment sequence for every batch.
  Coalesce adjacent ranges and use row indexing or bounded splicing. Emitting
  the entire accumulated prefix on every update would make transport and
  application cost grow quadratically.

[`refreshMatterHighlighting`](../src/merenda/kosmo/application_editor.nim#L651)
already coalesces a refresh onto the next main-thread frame, providing a useful
place to drain multiple batches together. Also replace the worker's eager
`source.split('\n')` with a line cursor so first delivery does not require
allocating a second representation of the complete source.

## Markdown: separate structure from code colors

The first milestone can keep the existing Markdown parser:

1. Parse the AST once and collect independent code-block descriptors containing
   a generation, block identity, language, and source snapshot.
2. Transfer ownership of the AST to the view as soon as parsing finishes. The
   worker must retain no aliases into that transferred graph.
3. Build the formatted document with code blocks initially using their base
   style. Queue highlighting for individual blocks; batch lines within large
   blocks. Distinct code blocks can start from fresh grammar states.
4. Deliver block-relative, half-open rune spans and update the corresponding
   storage. Cache batches that arrive before their presentation exists.

Use a stable block identity within each document generation. The current cache
key `(source, language)` deduplicates identical code blocks, but a result must
reach every matching presentation. Record mappings for language labels, nested
list indentation, quote prefixes, and collapsed sections: source offsets do not
directly equal displayed document offsets.

Each code block currently has both a range in the main document storage and
separate storage for its horizontal scrolling view. Updating only the main
document would leave the embedded view with old colors. Preserve the mapping
and update both representations, or give both a shared presentation source.

Applying a color patch should not call `scheduleMarkdownRendering` to rebuild
the complete document. That would repeatedly replace storage, headings, and
embedded views while batches arrive. Preserve their identities and scroll
positions, and group attribute changes. `TextStorage.setAttributeRanges` already
supports a range with multiple overlays, although it currently scans the stored
style runs and its attribute notification invalidates layout. A display-only
path for foreground changes would reduce repeated layout work; simply changing
the color without updating cached layout/render styles would be insufficient.

This milestone removes the wait for all code highlighting, but **first display
still waits for Markdown parsing and presentation construction**. To shorten
that remaining wait, extend the render job to publish completed top-level
presentation blocks and append the rest, with continuations inside very large
blocks. Keep selection, scroll anchors, heading identities, and background
layout generations stable while content arrives. The current test explicitly
expects empty storage until all render chunks finish, so that contract needs an
intentional update.

Splitting raw Markdown into arbitrary groups of source lines and parsing each
group independently is unsafe. Setext headings and tables reinterpret earlier
lines, lists and fences cross boundaries, and reference definitions later in
the document can resolve links earlier in it. The parser currently gathers
block structure and references before parsing inline content. True AST streaming
would need retained parser state and a way to revise already published content.
Colored text spans alone cannot carry the viewer's rich document structure.

Another source of work to measure: `parseMarkdownRoot` calls
`markdownParser.markdown` and discards its returned HTML. The dependency still
renders that HTML after parsing. A parser entry point that returns only the AST
could avoid this extra traversal and allocation without changing Markdown
semantics.

## Scheduling and lifetime requirements

Sigils can queue result messages while the worker slot is still executing, so
initial streaming need not wait for a coroutine-style worker rewrite. It does
need limits on queued batches and bytes; sending a message for every fast line
can fill the mailbox before the UI consumes it.

For fairness, represent a resumable job with explicit source position, grammar
state, version, cancellation control, and pending spans. Process a bounded slice
and schedule a continuation through its owning actor. NimKit's shared pool has
two workers and also handles text layout, so large highlighting jobs should
eventually yield worker capacity as well as publishing progress.

Keep grammar and tokenizer references within the owning worker. Transfer each
span batch as an immutable ownership unit, and never mutate it after delivery.
Discard stale batches before adding them to the UI queue and check generation
again when applying them. Add cancellation to the Markdown path: it currently
finishes the active parse/highlight request before starting the latest source.
Support cancellation between lines even while the actor is busy, and retain
the existing view/worker shutdown guarantees.

## Suggested implementation order and verification

1. Stream Moe row batches and preserve partial projections. Keep full source
   requests initially; this improves time to first color without depending on
   an edit-delta protocol.
2. Deliver Markdown structure before highlighting; patch code-block storage as
   completed blocks or line batches arrive.
3. Publish Markdown presentation blocks progressively if the remaining
   parse/build delay warrants it. Add a parse-only dependency API if measuring
   the discarded HTML shows material cost.
4. Add worker state checkpoints and edit-range requests to reduce total work
   after edits, with viewport scheduling once valid checkpoints exist.

Verify that early lines become colored while the request is still incomplete,
and that final streamed output matches the existing output across multiline
comments/strings, embedded fences, UTF-8, CRLF, empty lines, oversized lines,
and timeout recovery. Exercise edits and closure while old batches are queued,
theme changes, duplicate/nested/collapsed code blocks, and preservation of
selection and horizontal scrolling. Use the shared Kosmo/NimKit runners and
observable conditions with monotonic deadlines.

Measure time to first visible text, first visible colors, total completion,
maximum UI application time, and peak queued bytes. Separate grammar startup,
AST parsing, code highlighting, presentation construction, and layout. The
existing Markdown load benchmark combines parsing, highlighting, and applying
the document in its `parseApplyMs`, so it cannot yet attribute the perceived
delay to one of those stages. No latency measurements were run for this review.
