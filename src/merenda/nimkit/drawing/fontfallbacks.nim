import std/[hashes, os, strutils, tables]

import figdraw
import figdraw/extras/systemfonts

import ../foundation/types

type
  FontFallbackGroups* = seq[seq[string]]
    ## Ordered font-name groups. Names within one group are alternatives.

  AutomaticFallbackState = object
    typefaceIds: seq[TypefaceId]
    attemptedPaths: seq[string]
    nextGroup: int

var
  languageFallbackTable {.threadvar.}: Table[string, Table[string, FontFallbackGroups]]
  languageFallbackTableInitialized {.threadvar.}: bool
  automaticFallbackStates {.threadvar.}: Table[string, AutomaticFallbackState]

proc normalizeFallbackKey(value: string): string =
  value.strip().toLowerAscii().replace('_', '-')

proc addDefaultFallbackGroup(language, category: string, fontNames: openArray[string]) =
  let
    languageKey = language.normalizeFallbackKey()
    categoryKey = category.normalizeFallbackKey()
  var
    categories = languageFallbackTable.getOrDefault(languageKey)
    groups = categories.getOrDefault(categoryKey)
  groups.add @fontNames
  categories[categoryKey] = groups
  languageFallbackTable[languageKey] = categories

proc initLanguageFallbackTable() =
  if languageFallbackTableInitialized:
    return
  languageFallbackTableInitialized = true
  languageFallbackTable = initTable[string, Table[string, FontFallbackGroups]]()

  when defined(macosx):
    addDefaultFallbackGroup("", "hani", ["PingFang SC", "Hiragino Sans GB"])
    addDefaultFallbackGroup("", "hani", ["Arial Unicode MS", "Arial Unicode"])
    addDefaultFallbackGroup("ja", "hani", ["Hiragino Sans", "Yu Gothic"])
    addDefaultFallbackGroup("ko", "hani", ["Apple SD Gothic Neo"])
    addDefaultFallbackGroup("zh-hant", "hani", ["PingFang TC"])
    addDefaultFallbackGroup("zh-tw", "hani", ["PingFang TC"])
    addDefaultFallbackGroup("zh-hk", "hani", ["PingFang TC"])
    addDefaultFallbackGroup("", "hira", ["Hiragino Sans", "Yu Gothic"])
    addDefaultFallbackGroup("", "kana", ["Hiragino Sans", "Yu Gothic"])
    addDefaultFallbackGroup("", "hang", ["Apple SD Gothic Neo"])
    addDefaultFallbackGroup("", "arab", ["SF Arabic", "Geeza Pro"])
    addDefaultFallbackGroup("", "hebr", ["Arial Hebrew", "New Peninim MT"])
    addDefaultFallbackGroup("", "deva", ["Kohinoor Devanagari", "Devanagari Sangam MN"])
    addDefaultFallbackGroup("", "emoji", ["Noto Emoji"])
    addDefaultFallbackGroup("", "emoji", ["Apple Symbols"])
    addDefaultFallbackGroup("", "symbols", [DefaultMonospaceFontName])
    addDefaultFallbackGroup(
      "", "symbols", ["Apple Symbols", "Noto Sans Symbols 2", "Noto Sans Symbols"]
    )
    addDefaultFallbackGroup("", "*", ["Arial Unicode MS", "Arial Unicode"])
  elif defined(windows):
    addDefaultFallbackGroup("", "hani", ["Microsoft YaHei UI", "Microsoft YaHei"])
    addDefaultFallbackGroup("ja", "hani", ["Yu Gothic UI", "Yu Gothic"])
    addDefaultFallbackGroup("ko", "hani", ["Malgun Gothic"])
    addDefaultFallbackGroup(
      "zh-hant", "hani", ["Microsoft JhengHei UI", "Microsoft JhengHei"]
    )
    addDefaultFallbackGroup(
      "zh-tw", "hani", ["Microsoft JhengHei UI", "Microsoft JhengHei"]
    )
    addDefaultFallbackGroup(
      "zh-hk", "hani", ["Microsoft JhengHei UI", "Microsoft JhengHei"]
    )
    addDefaultFallbackGroup("", "hira", ["Yu Gothic UI", "Yu Gothic"])
    addDefaultFallbackGroup("", "kana", ["Yu Gothic UI", "Yu Gothic"])
    addDefaultFallbackGroup("", "hang", ["Malgun Gothic"])
    addDefaultFallbackGroup("", "emoji", ["Segoe UI Emoji", "Segoe UI Symbol"])
    addDefaultFallbackGroup("", "symbols", [DefaultMonospaceFontName])
    addDefaultFallbackGroup("", "symbols", ["Segoe UI Symbol", "Segoe UI Emoji"])
    addDefaultFallbackGroup("", "*", ["Segoe UI", "Arial Unicode MS"])
  else:
    addDefaultFallbackGroup("", "hani", ["Noto Sans CJK SC", "Noto Sans SC"])
    addDefaultFallbackGroup("ja", "hani", ["Noto Sans CJK JP", "Noto Sans JP"])
    addDefaultFallbackGroup("ko", "hani", ["Noto Sans CJK KR", "Noto Sans KR"])
    addDefaultFallbackGroup("zh-hant", "hani", ["Noto Sans CJK TC", "Noto Sans TC"])
    addDefaultFallbackGroup("zh-tw", "hani", ["Noto Sans CJK TC", "Noto Sans TC"])
    addDefaultFallbackGroup("zh-hk", "hani", ["Noto Sans CJK TC", "Noto Sans TC"])
    addDefaultFallbackGroup("", "hira", ["Noto Sans CJK JP", "Noto Sans JP"])
    addDefaultFallbackGroup("", "kana", ["Noto Sans CJK JP", "Noto Sans JP"])
    addDefaultFallbackGroup("", "hang", ["Noto Sans CJK KR", "Noto Sans KR"])
    addDefaultFallbackGroup("", "arab", ["Noto Sans Arabic", "DejaVu Sans"])
    addDefaultFallbackGroup("", "hebr", ["Noto Sans Hebrew", "DejaVu Sans"])
    addDefaultFallbackGroup("", "deva", ["Noto Sans Devanagari"])
    addDefaultFallbackGroup("", "emoji", ["Noto Emoji", "Noto Sans Symbols 2"])
    addDefaultFallbackGroup("", "symbols", [DefaultMonospaceFontName])
    addDefaultFallbackGroup(
      "", "symbols", ["Noto Sans Symbols 2", "Noto Sans Symbols", "DejaVu Sans"]
    )
    addDefaultFallbackGroup("", "*", ["Noto Sans", "DejaVu Sans"])

proc fallbackGroupsForKey(language, category: string): FontFallbackGroups =
  if language notin languageFallbackTable:
    return
  let categories = languageFallbackTable[language]
  if category in categories:
    result.add categories[category]
  if category != "*" and "*" in categories:
    result.add categories["*"]

proc fontFallbackGroups*(language, category: string): FontFallbackGroups =
  ## Returns configured groups for a BCP 47 language and script category.
  ## Categories are lowercase ISO 15924 script tags plus `symbols` and `emoji`.
  initLanguageFallbackTable()
  let
    languageKey = language.normalizeFallbackKey()
    categoryKey = category.normalizeFallbackKey()
  var matchingLanguage = ""
  for configuredLanguage in languageFallbackTable.keys:
    if configuredLanguage.len > matchingLanguage.len and (
      languageKey == configuredLanguage or
      languageKey.startsWith(configuredLanguage & "-")
    ):
      matchingLanguage = configuredLanguage

  if matchingLanguage.len > 0:
    result.add fallbackGroupsForKey(matchingLanguage, categoryKey)
  result.add fallbackGroupsForKey("", categoryKey)

proc setFontFallbackGroups*(
    language, category: string, groups: openArray[seq[string]]
) =
  ## Replaces the runtime fallback groups for a language and script category.
  initLanguageFallbackTable()
  let
    languageKey = language.normalizeFallbackKey()
    categoryKey = category.normalizeFallbackKey()
  var categories = languageFallbackTable.getOrDefault(languageKey)
  categories[categoryKey] = @groups
  languageFallbackTable[languageKey] = categories
  automaticFallbackStates.clear()

proc addFontFallbackGroup*(
    language, category: string, fontNames: openArray[string], prepend = false
) =
  ## Adds one ordered group of alternative font names at runtime.
  initLanguageFallbackTable()
  let
    languageKey = language.normalizeFallbackKey()
    categoryKey = category.normalizeFallbackKey()
  var
    categories = languageFallbackTable.getOrDefault(languageKey)
    groups = categories.getOrDefault(categoryKey)
  if prepend:
    groups.insert(@fontNames, 0)
  else:
    groups.add @fontNames
  categories[categoryKey] = groups
  languageFallbackTable[languageKey] = categories
  automaticFallbackStates.clear()

proc automaticFallbackCategory(
    request: FontFallbackRequest, codepoint: uint32
): string =
  if codepoint in 0x1F000'u32 .. 0x1FAFF'u32 or codepoint in 0x2600'u32 .. 0x27BF'u32:
    return "emoji"
  if codepoint in 0xE000'u32 .. 0xF8FF'u32 or codepoint in 0xF0000'u32 .. 0xFFFFD'u32 or
      codepoint in 0x100000'u32 .. 0x10FFFD'u32:
    return "symbols"

  result = request.script.normalizeFallbackKey()
  if result in ["zinh", "zsye", "zsym", "zyyy", "zzzz"]:
    result = "symbols"

proc automaticFallbackCategories(request: FontFallbackRequest): seq[string] =
  for codepoint in request.codepoints:
    let category = request.automaticFallbackCategory(codepoint)
    if category notin result:
      result.add category
  if result.len == 0:
    result.add request.script.normalizeFallbackKey()

proc automaticFallbackCacheKey(request: FontFallbackRequest): string =
  result =
    $Hash(request.primaryTypefaceId) & "\0" & request.language & "\0" & request.script
  for category in request.automaticFallbackCategories():
    result.add '\0'
    result.add category

proc findFallbackFontPath(fontNames: openArray[string]): string =
  for fontName in fontNames:
    let dataPath = figDataDir() / fontName
    if fileExists(dataPath):
      return dataPath
    if fileExists(fontName):
      return fontName
  findSystemFontFile(fontNames)

proc resolveAutomaticFontFallback(request: FontFallbackRequest): seq[TypefaceId] =
  if automaticFallbackStates.len == 0:
    automaticFallbackStates = initTable[string, AutomaticFallbackState]()

  let
    cacheKey = request.automaticFallbackCacheKey()
    categories = request.automaticFallbackCategories()
  var state = automaticFallbackStates.getOrDefault(cacheKey)
  var groups: FontFallbackGroups
  for category in categories:
    for group in fontFallbackGroups(request.language, category):
      if group notin groups:
        groups.add group

  for typefaceId in state.typefaceIds:
    if typefaceId notin request.existingTypefaceIds:
      return @[typefaceId]

  while state.nextGroup < groups.len:
    let group = groups[state.nextGroup]
    inc state.nextGroup
    let path = findFallbackFontPath(group)
    if path.len == 0 or path in state.attemptedPaths:
      continue
    state.attemptedPaths.add path

    try:
      let typefaceId = loadTypeface(path)
      if typefaceId != request.primaryTypefaceId and typefaceId notin state.typefaceIds:
        state.typefaceIds.add typefaceId
      automaticFallbackStates[cacheKey] = state
      if typefaceId notin request.existingTypefaceIds:
        return @[typefaceId]
    except CatchableError:
      discard

  automaticFallbackStates[cacheKey] = state

proc installAutomaticFontFallbackResolver*() =
  ## Installs Merenda's script-aware resolver when an app has not supplied one.
  if fontFallbackResolver() == nil:
    setFontFallbackResolver(resolveAutomaticFontFallback)
