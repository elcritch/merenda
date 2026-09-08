## Matter's TextMate grammars adapted to NimKit's frontend-neutral syntax spans.
##
## Grammar archives are embedded at compile time so installed applications do
## not need to locate Matter's package data at runtime. Each thread lazily
## compiles and caches only the grammars it uses.

import std/[options, strutils, tables, unicode]

import matter

import ./mattergrammarassets
import ./syntaxhighlighting
import ./texttypes

const MatterMaximumTokenizedLineBytes = 96
  ## Keep recursive TextMate regex matching within Nim's worker-thread stack.

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

proc byteRuneMap(source: string): seq[int] =
  result = newSeq[int](source.len + 1)
  var
    byteIndex = 0
    runeIndex = 0
  while byteIndex < source.len:
    let nextByte = min(byteIndex + max(runeLenAt(source, byteIndex), 1), source.len)
    for index in byteIndex ..< nextByte:
      result[index] = runeIndex
    byteIndex = nextByte
    inc runeIndex
  result[source.len] = runeIndex

proc addSpan(
    spans: var seq[SyntaxTokenSpan],
    byteToRune: openArray[int],
    startByte, stopByte: int,
    tokenClass: SyntaxTokenClass,
) =
  if tokenClass == stcOther:
    return
  let
    start = max(0, min(startByte, byteToRune.high))
    stop = max(start, min(stopByte, byteToRune.high))
    startRune = byteToRune[start]
    stopRune = byteToRune[stop]
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

proc matterSyntaxHighlighter*(source, language: string): seq[SyntaxTokenSpan] =
  ## Classify `source` with Matter's bundled TextMate grammar for `language`.
  ## Unknown language names return no spans. Returned ranges use rune offsets.
  if source.len == 0:
    return
  let grammar = grammarForLanguage(language)
  if grammar.isNil:
    return

  let byteToRune = source.byteRuneMap()
  var
    lineStart = 0
    ruleStack: StateStack
  while lineStart < source.len:
    var lineStop = source.find('\n', lineStart)
    if lineStop < 0:
      lineStop = source.len
    var contentStop = lineStop
    if contentStop > lineStart and source[contentStop - 1] == '\r':
      dec contentStop

    if contentStop - lineStart > MatterMaximumTokenizedLineBytes:
      # Reni's continuation matcher can consume several native frames per byte.
      # A plain long line is preferable to losing the background worker.
      ruleStack = nil
      lineStart = lineStop + 1
      continue

    let tokenized = grammar.tokenizeLine(source[lineStart ..< contentStop], ruleStack)
    for token in tokenized.tokens:
      result.addSpan(
        byteToRune,
        lineStart + token.startIndex,
        lineStart + token.endIndex,
        token.scopes.syntaxTokenClass(),
      )
    ruleStack = tokenized.ruleStack
    lineStart = lineStop + 1
