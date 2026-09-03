## Matter's TextMate grammars adapted to NimKit's frontend-neutral syntax spans.
##
## Grammar archives are embedded at compile time so installed applications do
## not need to locate Matter's package data at runtime. Each thread lazily
## compiles and caches only the grammars it uses.

import std/[compilesettings, options, os, strutils, tables, unicode]

import matter

import ./syntaxhighlighting
import ./texttypes

type EmbeddedGrammarArchive = tuple[path, contents: string]

const ZipLocalHeader = "PK\x03\x04"

proc findMatterPackageRoot(): string {.compileTime.} =
  for searchPath in querySettingSeq(MultipleValueSetting.searchPaths):
    let
      sourceDir = searchPath
      packageRoot = sourceDir.parentDir
    if fileExists(sourceDir / "matter.nim") and
        dirExists(packageRoot / "data" / "grammars"):
      return packageRoot
  raise newException(ValueError, "could not locate Matter's grammar archives")

const MatterPackageRoot = findMatterPackageRoot()

template embedGrammarArchive(package: untyped): untyped =
  (
    path: package.dataArchivePath,
    contents: staticRead(MatterPackageRoot / package.dataArchivePath),
  )

const EmbeddedGrammarArchives = [
  embedGrammarArchive(vscodeCppPackage),
  embedGrammarArchive(vscodeCsharpPackage),
  embedGrammarArchive(vscodeDiffPackage),
  embedGrammarArchive(vscodeDockerPackage),
  embedGrammarArchive(vscodeGitBasePackage),
  embedGrammarArchive(vscodeGoPackage),
  embedGrammarArchive(vscodeHtmlPackage),
  embedGrammarArchive(vscodeJavaPackage),
  embedGrammarArchive(vscodeJavascriptPackage),
  embedGrammarArchive(vscodeLatexPackage),
  embedGrammarArchive(vscodeLogPackage),
  embedGrammarArchive(vscodeLuaPackage),
  embedGrammarArchive(vscodeMarkdownPackage),
  embedGrammarArchive(vscodeRustPackage),
  embedGrammarArchive(vscodeShellscriptPackage),
  embedGrammarArchive(vscodeTypescriptPackage),
  embedGrammarArchive(vscodeXmlPackage),
  embedGrammarArchive(vscodeYamlPackage),
  embedGrammarArchive(vscodeJsonPackage),
  embedGrammarArchive(vscodePythonPackage),
  embedGrammarArchive(nimVscodePackage),
  embedGrammarArchive(fishPackage),
  embedGrammarArchive(haskellPackage),
  embedGrammarArchive(hyprlangPackage),
  embedGrammarArchive(tomlPackage),
  embedGrammarArchive(lispPackage),
  embedGrammarArchive(astroPackage),
  embedGrammarArchive(tclPackage),
]

var
  matterGrammarCache {.threadvar.}: Table[string, Grammar]
  matterGrammarCacheInitialized {.threadvar.}: bool

func littleEndian16(contents: string, offset: int): int =
  ord(contents[offset]) or (ord(contents[offset + 1]) shl 8)

func littleEndian32(contents: string, offset: int): int =
  ord(contents[offset]) or (ord(contents[offset + 1]) shl 8) or
    (ord(contents[offset + 2]) shl 16) or (ord(contents[offset + 3]) shl 24)

func archiveContents(path: string): string =
  for archive in EmbeddedGrammarArchives:
    if archive.path == path:
      return archive.contents

proc readStoredZipMember(contents, member: string): string =
  var offset = 0
  while offset + 30 <= contents.len and
      contents[offset ..< offset + ZipLocalHeader.len] == ZipLocalHeader:
    let
      flags = contents.littleEndian16(offset + 6)
      compression = contents.littleEndian16(offset + 8)
      compressedSize = contents.littleEndian32(offset + 18)
      nameSize = contents.littleEndian16(offset + 26)
      extraSize = contents.littleEndian16(offset + 28)
      nameStart = offset + 30
      dataStart = nameStart + nameSize + extraSize
      dataStop = dataStart + compressedSize
    if flags != 0 or compression != 0 or dataStop > contents.len:
      raise newException(MatterError, "invalid bundled Matter grammar archive")
    if contents[nameStart ..< nameStart + nameSize] == member:
      return contents[dataStart ..< dataStop]
    offset = dataStop
  raise newException(MatterError, "missing bundled Matter grammar: " & member)

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
  of "tex": "latex"
  of "ts": "typescript"
  of "yml": "yaml"
  else: name

proc grammarForLanguage(language: string): Grammar =
  let modeName = language.normalizedMatterLanguage()
  if modeName.len == 0:
    return
  if not matterGrammarCacheInitialized:
    matterGrammarCache = initTable[string, Grammar]()
    matterGrammarCacheInitialized = true
  if matterGrammarCache.hasKey(modeName):
    return matterGrammarCache[modeName]

  let primary = findMoeGrammar(modeName)
  if primary.isNone:
    matterGrammarCache[modeName] = nil
    return

  let registry = newRegistry()
  for contribution in importedGrammars(modeName):
    let archive = archiveContents(contribution.dataArchivePath)
    if archive.len == 0:
      raise newException(
        MatterError, "missing bundled Matter archive: " & contribution.dataArchivePath
      )
    registry.addGrammar(
      parseRawGrammar(
        archive.readStoredZipMember(contribution.archiveMember),
        contribution.archiveMember,
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
