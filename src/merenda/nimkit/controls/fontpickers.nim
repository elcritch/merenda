import std/[algorithm, locks, os, strutils, tables]

import sigils/core

import ./comboboxes
import ../foundation/selectors

export comboboxes

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw

type
  FontCatalogFace* = object
    style*: string
    language*: string
    path*: string
    identifier*: string

  FontCatalogEntry* = object
    family*: string
    path*: string
    identifier*: string
    searchText*: string
    faces*: seq[FontCatalogFace]
    searchKey: string
    faceRank: int

  FontCatalogDataSource* = ref object of Responder
    entries: seq[FontCatalogEntry]
    visibleEntryIndexes: seq[int]
    identifierToVisibleIndex: Table[string, int]
    optionCache: Table[int, ComboBoxOption]
    normalizedFilter: string
    intrinsicWidth: float32

const
  DefaultSystemFontIdentifier* = "system-font:default"
  DefaultFontLanguage* = "Default"
  DefaultFontPickerContentWidth* = 260.0'f32

  FontLanguageSuffixes = [
    ("Thai Looped", "Thai Looped"),
    ("Simplified Chinese", "Simplified Chinese"),
    ("Traditional Chinese", "Traditional Chinese"),
    ("Devanagari", "Devanagari"),
    ("Malayalam", "Malayalam"),
    ("Vietnamese", "Vietnamese"),
    ("Armenian", "Armenian"),
    ("Cyrillic", "Cyrillic"),
    ("Ethiopic", "Ethiopic"),
    ("Georgian", "Georgian"),
    ("Gujarati", "Gujarati"),
    ("Gurmukhi", "Gurmukhi"),
    ("Japanese", "Japanese"),
    ("Kannada", "Kannada"),
    ("Korean", "Korean"),
    ("Bengali", "Bengali"),
    ("Bangla", "Bengali"),
    ("Arabic", "Arabic"),
    ("Hebrew", "Hebrew"),
    ("Sinhala", "Sinhala"),
    ("Tamil", "Tamil"),
    ("Telugu", "Telugu"),
    ("Tibetan", "Tibetan"),
    ("Myanmar", "Myanmar"),
    ("Khmer", "Khmer"),
    ("Lao", "Lao"),
    ("Thai", "Thai"),
    ("Urdu", "Urdu"),
    ("Greek", "Greek"),
    ("Oriya", "Oriya"),
    ("JP", "Japanese"),
    ("KR", "Korean"),
    ("SC", "Simplified Chinese"),
    ("GB", "Simplified Chinese"),
    ("TC", "Traditional Chinese"),
    ("HK", "Traditional Chinese"),
    ("TW", "Traditional Chinese"),
  ]

var
  cachedSystemFontCatalog: seq[FontCatalogEntry]
  systemFontCatalogCached: bool
  systemFontCatalogLock: Lock

initLock(systemFontCatalogLock)

func normalizedFontText(text: string): string =
  result = newStringOfCap(text.len)
  for ch in text.toLowerAscii():
    if ch in {'a' .. 'z', '0' .. '9'} or ch.ord >= 128:
      result.add ch

func humanizedFontStem(stem: string): string =
  result = newStringOfCap(stem.len + 8)
  for index, ch in stem:
    if ch in {'-', '_'}:
      if result.len > 0 and result[^1] != ' ':
        result.add ' '
      continue

    let
      previous =
        if index > 0:
          stem[index - 1]
        else:
          '\0'
      following =
        if index + 1 < stem.len:
          stem[index + 1]
        else:
          '\0'
      startsWord =
        ch in {'A' .. 'Z'} and index > 0 and previous notin {' ', '-', '_'} and (
          previous in {'a' .. 'z'} or
          (previous in {'A' .. 'Z'} and following in {'a' .. 'z'})
        )
    if startsWord and result.len > 0 and result[^1] != ' ':
      result.add ' '
    result.add ch
  result = result.strip()

func isFontStyleSuffix(word: string): bool =
  let bracket = word.find('[')
  let normalized = (if bracket >= 0: word[0 ..< bracket] else: word).toLowerAscii()
  normalized in [
    "regular", "roman", "italic", "oblique", "bold", "semibold", "demibold",
    "extrabold", "ultrabold", "medium", "light", "extralight", "ultralight", "thin",
    "black", "heavy", "book", "text", "normal", "variable", "var", "semi", "demi",
    "extra", "ultra",
  ]

func splitFontFamilyAndStyle(path: string): tuple[family, style: string] =
  var words = path.splitFile().name.humanizedFontStem().splitWhitespace()
  var styleWords: seq[string]
  while words.len > 1 and words[^1].isFontStyleSuffix():
    let
      word = words[^1]
      bracket = word.find('[')
      cleanWord =
        if bracket >= 0:
          word[0 ..< bracket]
        else:
          word
    if cleanWord.toLowerAscii() notin ["variable", "var"]:
      styleWords.insert(cleanWord, 0)
    words.setLen(words.len - 1)
  result.family = words.join(" ")
  result.style = styleWords.join(" ")
  if result.style.len == 0 or result.style.toLowerAscii() in ["roman", "normal"]:
    result.style = "Regular"

func splitFontFamilyAndLanguage(family: string): tuple[baseFamily, language: string] =
  let normalizedFamily = family.toLowerAscii()
  for (suffix, language) in FontLanguageSuffixes:
    let normalizedSuffix = suffix.toLowerAscii()
    if normalizedFamily == normalizedSuffix:
      return (family, language)
    let marker = " " & normalizedSuffix
    if normalizedFamily.endsWith(marker):
      return (family[0 ..< family.len - marker.len].strip(), language)

  let paddedFamily = " " & normalizedFamily & " "
  for (suffix, language) in FontLanguageSuffixes:
    if paddedFamily.contains(" " & suffix.toLowerAscii() & " "):
      return (family, language)
  (family, DefaultFontLanguage)

func preferredFontStyleRank(style: string): int =
  let normalized = style.normalizedFontText()
  if normalized in ["regular", "roman", "book"]:
    return 0
  if normalized == "text":
    return 1
  2

func fontStyleSortRank(style: string): int =
  case style.normalizedFontText()
  of "regular", "roman", "normal": 0
  of "italic", "oblique": 1
  of "book", "text": 2
  of "medium": 3
  of "semibold", "demibold", "semi", "demi": 4
  of "bold": 5
  of "bolditalic", "boldoblique": 6
  of "extrabold", "ultrabold", "heavy", "black": 7
  of "light": 8
  of "extralight", "ultralight", "thin": 9
  else: 10

func initFontCatalogFace*(
    style, language, path: string, identifier = ""
): FontCatalogFace =
  FontCatalogFace(
    style: if style.len > 0: style else: "Regular",
    language: if language.len > 0: language else: DefaultFontLanguage,
    path: path,
    identifier:
      if identifier.len > 0:
        identifier
      else:
        "system-font-face:" & path,
  )

func initFontCatalogEntry*(
    family, path: string,
    identifier = "",
    searchText = "",
    faces: openArray[FontCatalogFace] = [],
): FontCatalogEntry =
  result.family = family
  result.path = path
  result.identifier =
    if identifier.len > 0:
      identifier
    else:
      "system-font:" & family.normalizedFontText()
  result.searchText =
    if searchText.len > 0:
      searchText
    else:
      family & " " & path.extractFilename()
  result.searchKey = result.searchText.normalizedFontText()
  result.faces = @faces
  if result.faces.len == 0 and path.len > 0:
    let
      name = path.splitFontFamilyAndStyle()
      language = name.family.splitFontFamilyAndLanguage().language
    result.faces.add initFontCatalogFace(name.style, language, path)
  result.faceRank =
    if result.faces.len > 0:
      result.faces[0].style.preferredFontStyleRank()
    else:
      high(int)

type ParsedFontFace = object
  path: string
  rawFamily: string
  candidateFamily: string
  language: string
  style: string
  searchText: string

func preferredFaceRank(face: ParsedFontFace): int =
  (if face.language == DefaultFontLanguage: 0 else: 100) +
    face.style.preferredFontStyleRank()

func copyFontCatalogEntry(entry: FontCatalogEntry): FontCatalogEntry =
  result = entry
  result.faces = newSeqOfCap[FontCatalogFace](entry.faces.len)
  for face in entry.faces:
    result.faces.add face

proc buildFontCatalog*(paths: openArray[string]): seq[FontCatalogEntry] =
  var
    sortedPaths = @paths
    parsedFaces: seq[ParsedFontFace]
    rawFamilies = initTable[string, bool]()
    candidateCounts = initCountTable[string]()
    familyIndexes = initTable[string, int]()
  sortedPaths.sort(
    proc(left, right: string): int =
      result = cmp(left.toLowerAscii(), right.toLowerAscii())
      if result == 0:
        result = cmp(left, right)
  )

  for path in sortedPaths:
    let
      name = path.splitFontFamilyAndStyle()
      language = name.family.splitFontFamilyAndLanguage()
      rawFamilyKey = name.family.normalizedFontText()
      candidateKey = language.baseFamily.normalizedFontText()
    if rawFamilyKey.len > 0:
      parsedFaces.add ParsedFontFace(
        path: path,
        rawFamily: name.family,
        candidateFamily: language.baseFamily,
        language: language.language,
        style: name.style,
        searchText: path.splitFile().name.humanizedFontStem(),
      )
      rawFamilies[rawFamilyKey] = true
      candidateCounts.inc(candidateKey)

  for parsedFace in parsedFaces:
    let
      rawFamilyKey = parsedFace.rawFamily.normalizedFontText()
      candidateKey = parsedFace.candidateFamily.normalizedFontText()
      useCandidate =
        candidateKey != rawFamilyKey and
        (candidateKey in rawFamilies or candidateCounts.getOrDefault(candidateKey) > 1)
      family = if useCandidate: parsedFace.candidateFamily else: parsedFace.rawFamily
      familyKey = family.normalizedFontText()
    if familyKey notin familyIndexes:
      familyIndexes[familyKey] = result.len
      result.add FontCatalogEntry(
        family: family,
        path: parsedFace.path,
        identifier: "system-font:" & familyKey,
        searchText: family,
        faceRank: high(int),
      )

    let entryIndex = familyIndexes[familyKey]
    result[entryIndex].searchText.add " " & parsedFace.searchText
    result[entryIndex].searchKey = result[entryIndex].searchText.normalizedFontText()
    result[entryIndex].faces.add initFontCatalogFace(
      parsedFace.style, parsedFace.language, parsedFace.path
    )
    let faceRank = parsedFace.preferredFaceRank()
    if faceRank < result[entryIndex].faceRank:
      result[entryIndex].path = parsedFace.path
      result[entryIndex].faceRank = faceRank

  result.sort(
    proc(left, right: FontCatalogEntry): int =
      result = cmp(left.family.toLowerAscii(), right.family.toLowerAscii())
      if result == 0:
        result = cmp(left.family, right.family)
  )
  for entry in result.mitems:
    entry.faces.sort(
      proc(left, right: FontCatalogFace): int =
        let
          leftLanguageRank = if left.language == DefaultFontLanguage: 0 else: 1
          rightLanguageRank = if right.language == DefaultFontLanguage: 0 else: 1
        result = cmp(leftLanguageRank, rightLanguageRank)
        if result == 0:
          result = cmp(left.language.toLowerAscii(), right.language.toLowerAscii())
        if result == 0:
          result = cmp(left.style.fontStyleSortRank(), right.style.fontStyleSortRank())
        if result == 0:
          result = cmp(left.style.toLowerAscii(), right.style.toLowerAscii())
        if result == 0:
          result = cmp(left.path, right.path)
    )

proc systemFontCatalog*(): seq[FontCatalogEntry] =
  withLock systemFontCatalogLock:
    if not systemFontCatalogCached:
      cachedSystemFontCatalog = buildFontCatalog(systemFontFiles())
      systemFontCatalogCached = true
    result = newSeqOfCap[FontCatalogEntry](cachedSystemFontCatalog.len)
    for entry in cachedSystemFontCatalog:
      result.add entry.copyFontCatalogEntry()

proc rebuildVisibleEntries(source: FontCatalogDataSource, filterText = "") =
  source.normalizedFilter = filterText.normalizedFontText()
  source.visibleEntryIndexes.setLen(0)
  source.identifierToVisibleIndex = initTable[string, int]()

  if source.normalizedFilter.len == 0 or
      "Default system font".normalizedFontText().contains(source.normalizedFilter):
    source.identifierToVisibleIndex[DefaultSystemFontIdentifier] =
      source.visibleEntryIndexes.len
    source.visibleEntryIndexes.add -1

  for entryIndex, entry in source.entries:
    if source.normalizedFilter.len == 0 or
        entry.searchKey.contains(source.normalizedFilter):
      source.identifierToVisibleIndex[entry.identifier] = source.visibleEntryIndexes.len
      source.visibleEntryIndexes.add entryIndex

proc optionForEntry(source: FontCatalogDataSource, entryIndex: int): ComboBoxOption =
  if entryIndex in source.optionCache:
    return source.optionCache[entryIndex]

  result =
    if entryIndex < 0:
      initComboBoxOption(
        identifier = DefaultSystemFontIdentifier,
        displayText = "Default",
        objectValue = toObj(""),
        searchText = "Default system font",
      )
    else:
      let entry = source.entries[entryIndex]
      initComboBoxOption(
        identifier = entry.identifier,
        displayText = entry.family,
        objectValue = toObj(entry.path),
        searchText = entry.searchText,
      )
  source.optionCache[entryIndex] = result

proc cachedOptionCount*(source: FontCatalogDataSource): int =
  source.optionCache.len

protocol FontCatalogComboBoxDataSource of ComboBoxDataSource:
  method itemCount(source: FontCatalogDataSource, comboBox: ComboBox): int =
    source.visibleEntryIndexes.len

  method comboBoxOptionAtIndex(
      source: FontCatalogDataSource, comboBox: ComboBox, index: int
  ): ComboBoxOption =
    if index in 0 ..< source.visibleEntryIndexes.len:
      source.optionForEntry(source.visibleEntryIndexes[index])
    else:
      ComboBoxOption()

  method indexOfComboBoxOptionIdentifier(
      source: FontCatalogDataSource, comboBox: ComboBox, identifier: string
  ): int =
    source.identifierToVisibleIndex.getOrDefault(identifier, -1)

  method setComboBoxOptionFilterText(
      source: FontCatalogDataSource, comboBox: ComboBox, text: string
  ) =
    let normalizedFilter = text.normalizedFontText()
    if normalizedFilter != source.normalizedFilter:
      source.rebuildVisibleEntries(text)

  method comboBoxIntrinsicContentWidth(
      source: FontCatalogDataSource, comboBox: ComboBox
  ): float32 =
    source.intrinsicWidth

proc newFontCatalogDataSource*(
    entries: openArray[FontCatalogEntry], intrinsicWidth = DefaultFontPickerContentWidth
): FontCatalogDataSource =
  result = FontCatalogDataSource(
    entries: @entries,
    optionCache: initTable[int, ComboBoxOption](),
    intrinsicWidth: max(intrinsicWidth, 0.0'f32),
  )
  for entry in result.entries.mitems:
    if entry.identifier.len == 0:
      entry.identifier = "system-font:" & entry.family.normalizedFontText()
    if entry.searchText.len == 0:
      entry.searchText = entry.family & " " & entry.path.extractFilename()
    entry.searchKey = entry.searchText.normalizedFontText()
  initResponder(result)
  discard result.withProtocol(FontCatalogComboBoxDataSource)
  result.rebuildVisibleEntries()

proc newSystemFontCatalogDataSource*(): FontCatalogDataSource =
  newFontCatalogDataSource(systemFontCatalog())
