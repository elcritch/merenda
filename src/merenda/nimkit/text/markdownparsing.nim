## Internal Sigils worker for moving complete nim-markdown ASTs between threads.

import std/[exitprocs, isolation, os]

import markdown as markdownParser
import sigils/[core, threads]
import threading/smartptrs

type
  MarkdownParseDialect* = enum
    mpdCommonMark
    mpdGitHub

  MarkdownParseResult* = object
    generation*: uint64
    root*: markdownParser.Document
    workerThreadId*: int
    errorMessage*: string

  MarkdownParseWorker* = ref object of AgentActor

var
  defaultMarkdownParsePool {.threadvar.}: SigilThreadPoolPtr
  defaultMarkdownParsePoolExitRegistered {.threadvar.}: bool

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

proc parseMarkdownRoot(
    source: string, config: markdownParser.MarkdownConfig
): markdownParser.Document =
  result = markdownParser.Document()
  discard markdownParser.markdown(source, config, result)

proc requestMarkdownParse*(
  worker: AgentProxy[MarkdownParseWorker],
  generation: uint64,
  source: string,
  dialect: MarkdownParseDialect,
  escape: bool,
  keepHtml: bool,
) {.signal.}

proc markdownParseFinished*(
  worker: MarkdownParseWorker, parseResult: SharedPtr[MarkdownParseResult]
) {.signal.}

proc requestMarkdownParse(
    worker: MarkdownParseWorker,
    generation: uint64,
    source: string,
    dialect: MarkdownParseDialect,
    escape: bool,
    keepHtml: bool,
) {.slot.} =
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
  except CatchableError as error:
    parseResult.errorMessage = error.msg
  # The parser created this entire graph on the worker and retains no aliases
  # after this signal. Transfer that one ownership unit back to the view thread.
  emit worker.markdownParseFinished(newSharedPtr(unsafeIsolate(move parseResult)))

proc stopDefaultMarkdownParsePool() {.noconv.} =
  if not defaultMarkdownParsePool.isNil:
    defaultMarkdownParsePool.stop(immediate = true)
    defaultMarkdownParsePool.join()
    defaultMarkdownParsePool = nil

proc resolvedDefaultMarkdownParsePool(): SigilThreadPoolPtr =
  startLocalThreadDefault()
  if defaultMarkdownParsePool.isNil:
    defaultMarkdownParsePool = newSigilThreadPool(workers = 1)
    defaultMarkdownParsePool.start()
  if not defaultMarkdownParsePoolExitRegistered:
    addExitProc(stopDefaultMarkdownParsePool)
    defaultMarkdownParsePoolExitRegistered = true
  defaultMarkdownParsePool

proc newMarkdownParseWorker*(): AgentProxy[MarkdownParseWorker] =
  var worker = MarkdownParseWorker()
  result = worker.moveToThread(resolvedDefaultMarkdownParsePool())
  connectThreaded(result, requestMarkdownParse, result, requestMarkdownParse)
