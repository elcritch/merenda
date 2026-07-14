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
  FontCatalogEntry* = object
    family*: string
    path*: string
    identifier*: string
    searchText*: string
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
  DefaultFontPickerContentWidth* = 260.0'f32

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
  word.toLowerAscii() in [
    "regular", "roman", "italic", "oblique", "bold", "semibold", "demibold",
    "extrabold", "ultrabold", "medium", "light", "extralight", "ultralight", "thin",
    "black", "heavy", "book", "variable", "var", "semi", "demi", "extra", "ultra",
  ]

func fontFamilyTitle(path: string): string =
  var words = path.splitFile().name.humanizedFontStem().splitWhitespace()
  while words.len > 1 and words[^1].isFontStyleSuffix():
    words.setLen(words.len - 1)
  words.join(" ")

func fontFaceRank(path, family: string): int =
  let face = path.splitFile().name.humanizedFontStem()
  if face.normalizedFontText() == family.normalizedFontText():
    return 0
  let normalizedFace = face.toLowerAscii()
  if "regular" in normalizedFace or "roman" in normalizedFace or "book" in normalizedFace:
    return 1
  2

func initFontCatalogEntry*(
    family, path: string, identifier = "", searchText = ""
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
  result.faceRank = path.fontFaceRank(family)

proc buildFontCatalog*(paths: openArray[string]): seq[FontCatalogEntry] =
  var
    sortedPaths = @paths
    familyIndexes = initTable[string, int]()
  sortedPaths.sort(
    proc(left, right: string): int =
      result = cmp(left.toLowerAscii(), right.toLowerAscii())
      if result == 0:
        result = cmp(left, right)
  )

  for path in sortedPaths:
    let
      family = path.fontFamilyTitle()
      familyKey = family.normalizedFontText()
    if familyKey.len == 0:
      continue
    let faceSearchText = path.splitFile().name.humanizedFontStem()
    if familyKey notin familyIndexes:
      familyIndexes[familyKey] = result.len
      result.add initFontCatalogEntry(
        family,
        path,
        identifier = "system-font:" & familyKey,
        searchText = family & " " & faceSearchText,
      )
      continue

    let entryIndex = familyIndexes[familyKey]
    result[entryIndex].searchText.add " " & faceSearchText
    result[entryIndex].searchKey = result[entryIndex].searchText.normalizedFontText()
    let faceRank = path.fontFaceRank(family)
    if faceRank < result[entryIndex].faceRank:
      result[entryIndex].path = path
      result[entryIndex].faceRank = faceRank

  result.sort(
    proc(left, right: FontCatalogEntry): int =
      result = cmp(left.family.toLowerAscii(), right.family.toLowerAscii())
      if result == 0:
        result = cmp(left.family, right.family)
  )

proc systemFontCatalog*(): seq[FontCatalogEntry] =
  withLock systemFontCatalogLock:
    if not systemFontCatalogCached:
      cachedSystemFontCatalog = buildFontCatalog(systemFontFiles())
      systemFontCatalogCached = true
    result = newSeqOfCap[FontCatalogEntry](cachedSystemFontCatalog.len)
    for entry in cachedSystemFontCatalog:
      result.add entry

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
