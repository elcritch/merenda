## Matter's TextMate grammars adapted to NimKit's frontend-neutral syntax spans.
##
## Grammar archives are embedded at compile time so installed applications do
## not need to locate Matter's package data at runtime. Each thread lazily
## compiles and caches only the grammars it uses.

import std/[monotimes, options, strutils, tables, times]

import matter

import ./mattergrammarassets
import ./syntaxhighlighting
import ./textbytecursors
import ./texttypes

const NimkitMatterMaximumLineBytes* {.intdefine.} = 1024
  ## Maximum line size passed to Matter's TextMate tokenizer.
  ## Longer lines stay plain to bound parsing work on generated or minified input.

static:
  doAssert NimkitMatterMaximumLineBytes > 0,
    "NimkitMatterMaximumLineBytes must be positive"

type
  MatterHighlightCancellation* = proc(): bool {.closure.}
    ## Return true when the caller wants the current highlighting pass to stop.

  MatterHighlightResult* = object
    spans*: seq[SyntaxTokenSpan]
    completed*: bool

var
  matterGrammarCache {.threadvar.}: Table[string, Grammar]
  matterGrammarCacheInitialized {.threadvar.}: bool

func normalizedMatterLanguage(language: string): string =
  let name = language.strip().toLowerAscii()
  case name
  of "c++", "cc", "cxx", "hpp", "hxx": "cpp"
  of "c#", "cs": "csharp"
  of "docker": "dockerfile"
  of "golang": "go"
  of "hs": "haskell"
  of "htm": "html"
  of "js": "javascript"
  of "luau": "lua"
  of "md": "markdown"
  of "nims", "nimble": "nim"
  of "py": "python"
  of "rs": "rust"
  of "sh", "bash": "shell"
  of "hcl", "tf": "terraform"
  of "tex": "latex"
  of "ts": "typescript"
  of "yml": "yaml"
  else: name

func primaryMatterGrammar(modeName: string): Option[GrammarContribution] =
  result = findMoeGrammar(modeName)
  if result.isSome:
    return
  for contribution in knownGrammars:
    if contribution.isPrimary and contribution.languageId == modeName:
      return some(contribution)

iterator relatedMatterGrammars(primary: GrammarContribution): GrammarContribution =
  yield primary
  for contribution in knownGrammars:
    if contribution.packageKey == primary.packageKey and
        contribution.scopeName != primary.scopeName:
      yield contribution

proc grammarForLanguage(language: string): Grammar =
  let modeName = language.normalizedMatterLanguage()
  if modeName.len == 0:
    return
  if not matterGrammarCacheInitialized:
    matterGrammarCache = initTable[string, Grammar]()
    matterGrammarCacheInitialized = true
  if matterGrammarCache.hasKey(modeName):
    return matterGrammarCache[modeName]

  let primary = primaryMatterGrammar(modeName)
  if primary.isNone:
    matterGrammarCache[modeName] = nil
    return

  let registry = newRegistry()
  for contribution in relatedMatterGrammars(primary.get()):
    registry.addGrammar(
      parseRawGrammar(
        contribution.bundledMatterGrammarContents(), contribution.archiveMember
      )
    )
  result = registry.loadGrammar(primary.get.scopeName)
  matterGrammarCache[modeName] = result

func scopeMatches(scope, prefix: string): bool =
  scope == prefix or
    (scope.len > prefix.len and scope.startsWith(prefix) and scope[prefix.len] == '.')

func hasScope(scopes: openArray[string], prefixes: openArray[string]): bool =
  for scope in scopes:
    for prefix in prefixes:
      if scope.scopeMatches(prefix):
        return true

func syntaxTokenClass(scopes: openArray[string]): SyntaxTokenClass =
  if scopes.hasScope(["comment"]):
    stcComment
  elif scopes.hasScope(["string", "regexp"]):
    stcString
  elif scopes.hasScope(["constant.numeric"]):
    stcNumber
  elif scopes.hasScope(["meta.preprocessor", "keyword.control.directive"]):
    stcPreprocessor
  elif scopes.hasScope(["keyword.operator"]):
    stcOperator
  elif scopes.hasScope(["keyword", "storage", "constant.language"]):
    stcKeyword
  elif scopes.hasScope(["punctuation"]):
    stcPunctuation
  elif scopes.hasScope(["entity", "support", "variable"]):
    stcIdentifier
  else:
    stcOther

proc addSpan(
    spans: var seq[SyntaxTokenSpan],
    source: string,
    cursor: var TextByteCursor,
    startByte, stopByte: int,
    tokenClass: SyntaxTokenClass,
) =
  if tokenClass == stcOther:
    return
  let
    start = max(0, min(startByte, source.len))
    stop = max(start, min(stopByte, source.len))
    startRune = source.runeIndexAtByte(cursor, start)
    stopRune = source.runeIndexAtByte(cursor, stop)
  if stopRune <= startRune:
    return
  if spans.len > 0 and spans[^1].tokenClass == tokenClass and
      spans[^1].range.maxIndex == startRune:
    spans[^1].range.length =
      (int(spans[^1].range.length) + stopRune - startRune).Natural
  else:
    spans.add SyntaxTokenSpan(
      range: initTextRange(startRune, stopRune - startRune), tokenClass: tokenClass
    )

proc matterSyntaxHighlighterBounded*(
    source, language: string,
    timeLimitMs = 0,
    cancelled: MatterHighlightCancellation = nil,
): MatterHighlightResult =
  ## Classify `source` with Matter's bundled TextMate grammar for `language`.
  ## Unknown language names return no spans. Returned ranges use rune offsets.
  ##
  ## ``timeLimitMs`` covers the complete source, not just one grammar line.
  ## ``cancelled`` is checked between lines and before/after the recursive
  ## grammar call so callers can stop stale worker requests promptly.
  ## ``result.completed`` is false when cancellation, the deadline, or Matter's own
  ## early-stop result prevents reaching the end of `source`.
  result.completed = true
  let startedAt = getMonoTime()
  if source.len == 0:
    return
  let grammar = grammarForLanguage(language)
  if grammar.isNil:
    return

  var cursor: TextByteCursor
  proc shouldStop(): bool =
    (not cancelled.isNil and cancelled()) or (
      timeLimitMs > 0 and
      getMonoTime() - startedAt >= initDuration(milliseconds = timeLimitMs)
    )

  var
    lineStart = 0
    ruleStack: StateStack
  while lineStart < source.len:
    if shouldStop():
      result.completed = false
      return
    var lineStop = source.find('\n', lineStart)
    if lineStop < 0:
      lineStop = source.len
    var contentStop = lineStop
    if contentStop > lineStart and source[contentStop - 1] == '\r':
      dec contentStop

    if contentStop - lineStart > NimkitMatterMaximumLineBytes:
      # Keep very large lines plain to bound the tokenizer's work.
      ruleStack = nil
      lineStart = lineStop + 1
      continue

    if shouldStop():
      result.completed = false
      return
    let remainingMilliseconds =
      if timeLimitMs > 0:
        max(1, timeLimitMs - int((getMonoTime() - startedAt).inMilliseconds))
      else:
        0
    let tokenized = grammar.tokenizeLine(
      source[lineStart ..< contentStop], ruleStack, remainingMilliseconds
    )
    if tokenized.stoppedEarly or shouldStop():
      result.completed = false
      return
    for token in tokenized.tokens:
      result.spans.addSpan(
        source,
        cursor,
        lineStart + token.startIndex,
        lineStart + token.endIndex,
        token.scopes.syntaxTokenClass(),
      )
    ruleStack = tokenized.ruleStack
    lineStart = lineStop + 1

proc matterSyntaxHighlighter*(source, language: string): seq[SyntaxTokenSpan] =
  ## Classify a source with no explicit deadline or cancellation callback.
  matterSyntaxHighlighterBounded(source, language).spans
