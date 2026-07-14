import std/[algorithm, locks, os, strutils, tables]

import sigils/core
from figdraw/common/typefaceinfos import TypefaceInfo, parseTypefaceInfo

import ./comboboxes
import ../foundation/selectors

export comboboxes

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw

type
  FontCatalogMetadataMode* = enum
    fcmmDeferred
    fcmmEager

  FontCatalogFace* = object
    style*: string
    language*: string
    path*: string
    identifier*: string
    weightClass*: uint16
    widthClass*: uint16
    bold*: bool
    italic*: bool
    oblique*: bool
    regular*: bool
    monospace*: bool
    variable*: bool
    metadataLoaded*: bool

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

  FontLayoutScriptLanguages = [
    ("arab", "Arabic"),
    ("armn", "Armenian"),
    ("beng", "Bengali"),
    ("cyrl", "Cyrillic"),
    ("deva", "Devanagari"),
    ("ethi", "Ethiopic"),
    ("geor", "Georgian"),
    ("grek", "Greek"),
    ("gujr", "Gujarati"),
    ("guru", "Gurmukhi"),
    ("hang", "Korean"),
    ("hani", "Chinese"),
    ("hebr", "Hebrew"),
    ("kana", "Japanese"),
    ("knda", "Kannada"),
    ("khmr", "Khmer"),
    ("lao", "Lao"),
    ("mlym", "Malayalam"),
    ("mymr", "Myanmar"),
    ("orya", "Oriya"),
    ("sinh", "Sinhala"),
    ("taml", "Tamil"),
    ("telu", "Telugu"),
    ("thai", "Thai"),
    ("tibt", "Tibetan"),
  ]

  FontLayoutTagLanguages = [
    ("jan", "Japanese"),
    ("kor", "Korean"),
    ("urd", "Urdu"),
    ("zhs", "Simplified Chinese"),
    ("zht", "Traditional Chinese"),
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

func fontLanguageForTag(tag: string, mappings: openArray[(string, string)]): string =
  let normalized = tag.strip().toLowerAscii()
  for (candidate, language) in mappings:
    if normalized == candidate:
      return language

proc addUniqueFontLanguage(languages: var seq[string], language: string) =
  if language.len > 0 and language notin languages:
    languages.add language

proc fontLanguage(info: TypefaceInfo, family: string): string =
  let namedLanguage = family.splitFontFamilyAndLanguage().language
  if namedLanguage != DefaultFontLanguage:
    return namedLanguage

  var languages: seq[string]
  for tag in info.layoutLanguages:
    languages.addUniqueFontLanguage(tag.fontLanguageForTag(FontLayoutTagLanguages))
  if languages.len == 1:
    return languages[0]

  languages.setLen(0)
  for tag in info.layoutScripts:
    languages.addUniqueFontLanguage(tag.fontLanguageForTag(FontLayoutScriptLanguages))
  if languages.len == 1:
    languages[0]
  else:
    DefaultFontLanguage

func normalizedFontStyle(style: string): string =
  let normalized = style.strip().toLowerAscii()
  if normalized.len == 0 or normalized in ["normal", "roman"]:
    "Regular"
  else:
    style.strip()

func inferredFontWeight(style: string): uint16 =
  case style.normalizedFontText()
  of "thin": 100
  of "extralight", "ultralight": 200
  of "light": 300
  of "medium": 500
  of "semibold", "demibold", "semi", "demi": 600
  of "bold", "bolditalic", "boldoblique": 700
  of "extrabold", "ultrabold": 800
  of "heavy", "black": 900
  else: 400

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

func preferredFontStyleRank(face: FontCatalogFace): int =
  if face.regular or
      face.weightClass in 350'u16 .. 450'u16 and not face.italic and not face.oblique:
    0
  elif face.italic or face.oblique:
    1
  else:
    face.style.preferredFontStyleRank()

func fontStyleSortRank(face: FontCatalogFace): int =
  if face.regular and not face.italic and not face.oblique:
    0
  elif face.weightClass in 350'u16 .. 450'u16 and (face.italic or face.oblique):
    1
  elif face.weightClass in 450'u16 ..< 550'u16:
    3
  elif face.weightClass in 550'u16 ..< 650'u16:
    4
  elif face.bold or face.weightClass in 650'u16 ..< 800'u16:
    if face.italic or face.oblique: 6 else: 5
  elif face.weightClass >= 800'u16:
    7
  elif face.weightClass in 250'u16 ..< 350'u16:
    8
  elif face.weightClass > 0 and face.weightClass < 250'u16:
    9
  else:
    face.style.fontStyleSortRank()

func initFontCatalogFace*(
    style, language, path: string, identifier = ""
): FontCatalogFace =
  let
    normalizedStyle = style.normalizedFontStyle()
    styleKey = normalizedStyle.normalizedFontText()
  FontCatalogFace(
    style: normalizedStyle,
    language: if language.len > 0: language else: DefaultFontLanguage,
    path: path,
    identifier:
      if identifier.len > 0:
        identifier
      else:
        "system-font-face:" & path,
    weightClass: normalizedStyle.inferredFontWeight(),
    widthClass: 5,
    bold: styleKey.contains("bold") or styleKey in ["heavy", "black"],
    italic: styleKey.contains("italic"),
    oblique: styleKey.contains("oblique"),
    regular: styleKey in ["regular", "normal", "roman", "book"],
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
      result.faces[0].preferredFontStyleRank()
    else:
      high(int)

type ParsedFontFace = object
  rawFamily: string
  candidateFamily: string
  searchText: string
  face: FontCatalogFace

func preferredFaceRank(face: ParsedFontFace): int =
  (if face.face.language == DefaultFontLanguage: 0 else: 100) +
    face.face.preferredFontStyleRank()

proc fontInfoForPath(path: string): tuple[info: TypefaceInfo, available: bool] =
  result.info = parseTypefaceInfo(path, "")
  if not fileExists(path):
    return
  try:
    result.info = parseTypefaceInfo(path, readFile(path))
    result.available = result.info.localizedNames.len > 0 or result.info.weightClass > 0
  except IOError:
    discard

proc addUniqueFontSearchText(values: var seq[string], value: string) =
  let trimmed = value.strip()
  if trimmed.len > 0 and trimmed notin values:
    values.add trimmed

proc fontMetadataSearchText(info: TypefaceInfo): string =
  var values: seq[string]
  for value in [info.family, info.subfamily, info.fullName, info.postScriptName]:
    values.addUniqueFontSearchText(value)
  for name in info.localizedNames:
    if name.nameId in {1'u16, 2'u16, 4'u16, 6'u16, 16'u16, 17'u16, 21'u16, 22'u16}:
      values.addUniqueFontSearchText(name.text)
  for tag in info.layoutScripts:
    values.addUniqueFontSearchText(tag)
  for tag in info.layoutLanguages:
    values.addUniqueFontSearchText(tag)
  for axis in info.variationAxes:
    values.addUniqueFontSearchText(axis.name)
    values.addUniqueFontSearchText(axis.tag)
  values.join(" ")

proc parsedFontFace(path: string): ParsedFontFace =
  let
    fallbackName = path.splitFontFamilyAndStyle()
    metadata = path.fontInfoForPath()
    rawFamily =
      if metadata.available and metadata.info.family.len > 0:
        metadata.info.family
      else:
        fallbackName.family
    style =
      if metadata.available and metadata.info.subfamily.len > 0:
        metadata.info.subfamily.normalizedFontStyle()
      else:
        fallbackName.style
    language =
      if metadata.available:
        metadata.info.fontLanguage(rawFamily)
      else:
        rawFamily.splitFontFamilyAndLanguage().language
    family = rawFamily.splitFontFamilyAndLanguage()
  result.rawFamily = rawFamily
  result.candidateFamily = family.baseFamily
  result.face = initFontCatalogFace(style, language, path)
  result.face.metadataLoaded = true
  result.searchText = path.splitFile().name.humanizedFontStem()
  if metadata.available:
    let info = metadata.info
    result.face.weightClass = info.weightClass
    result.face.widthClass = info.widthClass
    result.face.bold = info.bold
    result.face.italic = info.italic
    result.face.oblique = info.oblique
    result.face.regular = info.regular
    result.face.monospace = info.monospace
    result.face.variable = info.variationAxes.len > 0
    result.searchText.add " " & info.fontMetadataSearchText()

proc loadFontCatalogFaceMetadata*(face: var FontCatalogFace) =
  if face.metadataLoaded:
    return
  let metadata = face.path.fontInfoForPath()
  face.metadataLoaded = true
  if not metadata.available:
    return

  let info = metadata.info
  if info.subfamily.len > 0:
    face.style = info.subfamily.normalizedFontStyle()
  face.language = info.fontLanguage(info.family)
  face.weightClass = info.weightClass
  face.widthClass = info.widthClass
  face.bold = info.bold
  face.italic = info.italic
  face.oblique = info.oblique
  face.regular = info.regular
  face.monospace = info.monospace
  face.variable = info.variationAxes.len > 0

func copyFontCatalogEntry(entry: FontCatalogEntry): FontCatalogEntry =
  result = entry
  result.faces = newSeqOfCap[FontCatalogFace](entry.faces.len)
  for face in entry.faces:
    result.faces.add face

proc buildFontCatalog*(
    paths: openArray[string], metadataMode = fcmmEager
): seq[FontCatalogEntry] =
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
      parsedFace =
        if metadataMode == fcmmEager:
          path.parsedFontFace()
        else:
          let
            name = path.splitFontFamilyAndStyle()
            family = name.family.splitFontFamilyAndLanguage()
          ParsedFontFace(
            rawFamily: name.family,
            candidateFamily: family.baseFamily,
            searchText: path.splitFile().name.humanizedFontStem(),
            face: initFontCatalogFace(name.style, family.language, path),
          )
      rawFamilyKey = parsedFace.rawFamily.normalizedFontText()
      candidateKey = parsedFace.candidateFamily.normalizedFontText()
    if rawFamilyKey.len > 0:
      parsedFaces.add parsedFace
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
        path: parsedFace.face.path,
        identifier: "system-font:" & familyKey,
        searchText: family,
        faceRank: high(int),
      )

    let entryIndex = familyIndexes[familyKey]
    result[entryIndex].searchText.add " " & parsedFace.searchText
    result[entryIndex].searchKey = result[entryIndex].searchText.normalizedFontText()
    result[entryIndex].faces.add parsedFace.face
    let faceRank = parsedFace.preferredFaceRank()
    if faceRank < result[entryIndex].faceRank:
      result[entryIndex].path = parsedFace.face.path
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
          result = cmp(left.fontStyleSortRank(), right.fontStyleSortRank())
        if result == 0:
          result = cmp(left.style.toLowerAscii(), right.style.toLowerAscii())
        if result == 0:
          result = cmp(left.path, right.path)
    )

proc systemFontCatalog*(): seq[FontCatalogEntry] =
  withLock systemFontCatalogLock:
    if not systemFontCatalogCached:
      cachedSystemFontCatalog = buildFontCatalog(systemFontFiles(), fcmmDeferred)
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
