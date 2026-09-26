## Parse Markdown structure first, then stream bounded code-color batches.

import std/[lists, locks, os, strutils, tables]

import markdown as markdownParser
import sigils/[core, threads]
import ../foundation/backgroundworkers
import ./[matterhighlighting, syntaxhighlighting, texttypes]

type
  MarkdownParseDialect* = enum
    mpdCommonMark
    mpdGitHub

  MarkdownCodeSource* = tuple[source, language: string]

  MarkdownParseResult* = object
    generation*: uint64
    root*: markdownParser.Document
    workerThreadId*: int
    errorMessage*: string
    codes*: seq[MarkdownCodeSource]

  MarkdownHighlightBatch* = object
    generation*: uint64
    codeIndex*: int
    range*: TextRange
    spans*: seq[SyntaxTokenSpan]
    finished*: bool

  MarkdownParseWorker* = ref object of AgentActor
    generation: uint64
    codes: seq[MarkdownCodeSource]
    codeIndex: int
    codeStarted: bool
    highlightJob: MatterHighlightJob
    grammars: MatterGrammarCache

proc collectCodeBlocks(
    token: markdownParser.Token,
    codes: var seq[MarkdownCodeSource],
    seen: var Table[MarkdownCodeSource, bool],
) =
  if token of markdownParser.CodeBlock:
    let code = markdownParser.CodeBlock(token)
    let key = (source: code.doc.strip(chars = {'\n'}), language: code.info)
    if not seen.hasKey(key):
      seen[key] = true
      codes.add key
  for child in token.children:
    child.collectCodeBlocks(codes, seen)

func isCommonMarkConfig(config: markdownParser.MarkdownConfig): bool =
  let
    blocks = config.blockParsers
    inlines = config.inlineParsers
  blocks.len == 12 and blocks[0] of markdownParser.ReferenceParser and
    blocks[1] of markdownParser.ThematicBreakParser and
    blocks[2] of markdownParser.BlockquoteParser and blocks[3] of markdownParser.UlParser and
    blocks[4] of markdownParser.OlParser and
    blocks[5] of markdownParser.IndentedCodeParser and
    blocks[6] of markdownParser.FencedCodeParser and
    blocks[7] of markdownParser.HtmlBlockParser and
    blocks[8] of markdownParser.AtxHeadingParser and
    blocks[9] of markdownParser.SetextHeadingParser and
    blocks[10] of markdownParser.BlanklineParser and
    blocks[11] of markdownParser.ParagraphParser and inlines.len == 11 and
    inlines[0] of markdownParser.DelimiterParser and
    inlines[1] of markdownParser.ImageParser and
    inlines[2] of markdownParser.AutoLinkParser and
    inlines[3] of markdownParser.LinkParser and
    inlines[4] of markdownParser.HtmlEntityParser and
    inlines[5] of markdownParser.InlineHtmlParser and
    inlines[6] of markdownParser.EscapeParser and
    inlines[7] of markdownParser.CodeSpanParser and
    inlines[8] of markdownParser.HardBreakParser and
    inlines[9] of markdownParser.SoftBreakParser and
    inlines[10] of markdownParser.TextParser

func isGfmConfig(config: markdownParser.MarkdownConfig): bool =
  let
    blocks = config.blockParsers
    inlines = config.inlineParsers
  blocks.len == 13 and blocks[0] of markdownParser.ReferenceParser and
    blocks[1] of markdownParser.ThematicBreakParser and
    blocks[2] of markdownParser.BlockquoteParser and blocks[3] of markdownParser.UlParser and
    blocks[4] of markdownParser.OlParser and
    blocks[5] of markdownParser.IndentedCodeParser and
    blocks[6] of markdownParser.FencedCodeParser and
    blocks[7] of markdownParser.HtmlBlockParser and
    blocks[8] of markdownParser.HtmlTableParser and
    blocks[9] of markdownParser.AtxHeadingParser and
    blocks[10] of markdownParser.SetextHeadingParser and
    blocks[11] of markdownParser.BlanklineParser and
    blocks[12] of markdownParser.ParagraphParser and inlines.len == 12 and
    inlines[0] of markdownParser.DelimiterParser and
    inlines[1] of markdownParser.ImageParser and
    inlines[2] of markdownParser.AutoLinkParser and
    inlines[3] of markdownParser.LinkParser and
    inlines[4] of markdownParser.HtmlEntityParser and
    inlines[5] of markdownParser.InlineHtmlParser and
    inlines[6] of markdownParser.EscapeParser and
    inlines[7] of markdownParser.StrikethroughParser and
    inlines[8] of markdownParser.CodeSpanParser and
    inlines[9] of markdownParser.HardBreakParser and
    inlines[10] of markdownParser.SoftBreakParser and
    inlines[11] of markdownParser.TextParser

func builtInMarkdownDialect*(
    config: markdownParser.MarkdownConfig, dialect: var MarkdownParseDialect
): bool =
  if config.isGfmConfig():
    dialect = mpdGitHub
    true
  elif config.isCommonMarkConfig():
    dialect = mpdCommonMark
    true
  else:
    false

var
  markdownParserLock: Lock
  markdownParserDepth {.threadvar.}: int
initLock(markdownParserLock)

proc parseMarkdownRoot*(
    source: string, config: markdownParser.MarkdownConfig
): markdownParser.Document =
  # nim-markdown's global skipParsing ref is not safe for concurrent ARC
  # reference-count updates. Serialize parser entry, not highlighting/layout.
  # Nested parses from a custom parser on this same thread remain supported.
  if markdownParserDepth == 0:
    acquire(markdownParserLock)
  inc markdownParserDepth
  defer:
    dec markdownParserDepth
    if markdownParserDepth == 0:
      release(markdownParserLock)
  result = markdownParser.Document()
  discard markdownParser.markdown(source, config, result)

proc requestMarkdownParse*(
  worker: AgentProxy[MarkdownParseWorker],
  generation: uint64,
  source: string,
  dialect: MarkdownParseDialect,
  escape: bool,
  keepHtml: bool,
  highlightMatter: bool,
) {.signal.}

proc markdownParseFinished*(
  worker: MarkdownParseWorker, parseResult: sink MarkdownParseResult
) {.signal.}

proc continueMarkdownHighlight*(
  worker: AgentProxy[MarkdownParseWorker], generation: uint64
) {.signal.}

proc cancelMarkdownHighlight*(
  worker: AgentProxy[MarkdownParseWorker], generation: uint64
) {.signal.}

proc markdownHighlightReady*(
  worker: MarkdownParseWorker, batch: sink MarkdownHighlightBatch
) {.signal.}

proc cancelMarkdownHighlight(worker: MarkdownParseWorker, generation: uint64) {.slot.} =
  if worker.generation == generation:
    worker.codes.setLen(0)
    worker.highlightJob = default(MatterHighlightJob)
    worker.codeStarted = false

proc continueMarkdownHighlight(
    worker: MarkdownParseWorker, generation: uint64
) {.slot.} =
  if generation != worker.generation or worker.codeIndex >= worker.codes.len:
    return
  var batch =
    MarkdownHighlightBatch(generation: generation, codeIndex: worker.codeIndex)
  var codeFinished = false
  try:
    if not worker.codeStarted:
      worker.highlightJob = worker.grammars.initMatterHighlightJob(
        move worker.codes[worker.codeIndex].source,
        worker.codes[worker.codeIndex].language,
      )
      worker.codes[worker.codeIndex] = default(MarkdownCodeSource)
      worker.codeStarted = true
    var parsed = worker.highlightJob.nextMatterHighlightBatch()
    batch.range = parsed.range
    batch.spans = move parsed.spans
    codeFinished = parsed.completed
  except CatchableError:
    # Keep the parsed document even if a code grammar fails.
    codeFinished = true
  if codeFinished:
    worker.codes[worker.codeIndex] = default(MarkdownCodeSource)
    inc worker.codeIndex
    worker.codeStarted = false
    worker.highlightJob = default(MatterHighlightJob)
  batch.finished = worker.codeIndex >= worker.codes.len
  if batch.finished:
    worker.codes.setLen(0)
  emit worker.markdownHighlightReady(move batch)

proc requestMarkdownParse(
    worker: MarkdownParseWorker,
    generation: uint64,
    source: string,
    dialect: MarkdownParseDialect,
    escape: bool,
    keepHtml: bool,
    highlightMatter: bool,
) {.slot.} =
  worker.cancelMarkdownHighlight(worker.generation)
  worker.generation = generation
  worker.codeIndex = 0
  var parseResult =
    MarkdownParseResult(generation: generation, workerThreadId: getThreadId())
  try:
    let config =
      case dialect
      of mpdCommonMark:
        markdownParser.initCommonmarkConfig(escape = escape, keepHtml = keepHtml)
      of mpdGitHub:
        markdownParser.initGfmConfig(escape = escape, keepHtml = keepHtml)
    parseResult.root = source.parseMarkdownRoot(config)
    if highlightMatter:
      var seen: Table[MarkdownCodeSource, bool]
      parseResult.root.collectCodeBlocks(parseResult.codes, seen)
      # Retain only value descriptors; the AST is transferred without aliases.
      worker.codes = parseResult.codes
  except CatchableError as error:
    parseResult.errorMessage = error.msg
  # The parser created this entire graph on the worker and retains no aliases
  # after this signal. Transfer that one ownership unit back to the view thread.
  emit worker.markdownParseFinished(move parseResult)

proc newMarkdownParseWorker*(): AgentProxy[MarkdownParseWorker] =
  var worker = MarkdownParseWorker()
  result = worker.moveToThread(nimkitWorkerPool())
  connectThreaded(result, requestMarkdownParse, result, requestMarkdownParse)
  connectThreaded(result, continueMarkdownHighlight, result, continueMarkdownHighlight)
  connectThreaded(result, cancelMarkdownHighlight, result, cancelMarkdownHighlight)

var markdownWorkerLifetime {.used.}: NimkitBackgroundWorkerLifetime
