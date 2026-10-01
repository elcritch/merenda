## Shared literal search for read-only Kosmo documents.

import std/unicode
import sigils/core
import ../nimkit as nimkit
import ./searchbar

type
  KosmoViewerMatch* = object
    source*: int
    range*: nimkit.TextRange

  KosmoViewerSearch* = ref object of nimkit.Agent
    bar*: KosmoSearchBar
    host: WeakRef[nimkit.View]
    sources: proc(): seq[string] {.closure.}
    reveal: proc(match: KosmoViewerMatch) {.closure.}
    clear: proc() {.closure.}
    matches: seq[KosmoViewerMatch]
    selected: int

proc plainSearchRanges*(text, query: string): seq[nimkit.TextRange] =
  ## Case-insensitive literal matches in rune coordinates, including Unicode.
  if query.len == 0:
    return
  let needle = query.toRunes()
  # KMP keeps searching long diff lines linear even for repetitive queries.
  var normalized = newSeq[Rune](needle.len)
  var prefix = newSeq[int](needle.len)
  for i, value in needle:
    normalized[i] = value.toLower()
    if i > 0:
      var j = prefix[i - 1]
      while j > 0 and normalized[i] != normalized[j]:
        j = prefix[j - 1]
      if normalized[i] == normalized[j]:
        inc j
      prefix[i] = j
  var matched = 0
  var index = 0
  for value in text.runes:
    let current = value.toLower()
    while matched > 0 and current != normalized[matched]:
      matched = prefix[matched - 1]
    if current == normalized[matched]:
      inc matched
    if matched == normalized.len:
      result.add nimkit.initTextRange(index - normalized.len + 1, normalized.len)
      matched = prefix[matched - 1]
    inc index

proc searchVisible*(search: KosmoViewerSearch): bool =
  not search.isNil and not search.bar.hidden

proc revealSelected(search: KosmoViewerSearch) =
  if search.selected in 0 ..< search.matches.len:
    search.reveal(search.matches[search.selected])
  else:
    search.clear()

proc refreshSearch*(search: KosmoViewerSearch, reset = false) =
  if not search.searchVisible():
    return
  var previous = KosmoViewerMatch(source: -1)
  if not reset and search.selected in 0 ..< search.matches.len:
    previous = search.matches[search.selected]
  search.matches.setLen(0)
  search.selected = -1
  let query = search.bar.query()
  if query.len > 0:
    for source, text in search.sources():
      for range in plainSearchRanges(text, query):
        let match = KosmoViewerMatch(source: source, range: range)
        if match == previous:
          search.selected = search.matches.len
        search.matches.add match
  if search.selected < 0 and search.matches.len > 0:
    search.selected = 0
  search.bar.hasMatches = search.matches.len > 0
  search.revealSelected()

proc findNext*(search: KosmoViewerSearch, backwards = false) =
  search.refreshSearch()
  if search.matches.len > 0:
    let delta = if backwards: -1 else: 1
    search.selected =
      (search.selected + delta + search.matches.len) mod search.matches.len
    search.revealSelected()

proc dismissSearch*(search: KosmoViewerSearch) =
  search.bar.hidden = true
  search.matches.setLen(0)
  search.selected = -1
  search.clear()
  if not search.host.isNil:
    let owner = search.host[].window()
    if owner of nimkit.Window:
      discard nimkit.Window(owner).makeFirstResponder(search.host[])

proc layoutSearch(search: KosmoViewerSearch) {.slot.} =
  if not search.host.isNil:
    search.bar.layoutInBounds(search.host[].bounds())

proc showSearch*(search: KosmoViewerSearch): bool {.discardable.} =
  if search.isNil or search.host.isNil:
    return
  let owner = search.host[].window()
  if not (owner of nimkit.Window):
    return
  search.bar.hidden = false
  search.layoutSearch()
  search.bar.layoutSubtreeIfNeeded()
  search.refreshSearch()
  search.bar.queryField().selectedRange =
    nimkit.initTextRange(0, search.bar.query().runeLen)
  nimkit.Window(owner).makeFirstResponder(search.bar.queryField())

proc handleSearchKey*(search: KosmoViewerSearch, event: nimkit.KeyEvent): bool =
  if event.key == nimkit.keyF and event.modifiers == nimkit.shortcutModifiers():
    return search.showSearch()
  if search.searchVisible() and event.key == nimkit.keyG:
    if event.modifiers == nimkit.shortcutModifiers():
      search.findNext()
      return true
    if event.modifiers == nimkit.shortcutModifiers() + {nimkit.kmShift}:
      search.findNext(backwards = true)
      return true

proc newKosmoViewerSearch*(
    host: nimkit.View,
    subject: string,
    sources: proc(): seq[string] {.closure.},
    reveal: proc(match: KosmoViewerMatch) {.closure.},
    clear: proc() {.closure.},
): KosmoViewerSearch =
  result = KosmoViewerSearch(
    host: host.unsafeWeakRef(),
    sources: sources,
    reveal: reveal,
    clear: clear,
    selected: -1,
  )
  let search = result.unsafeWeakRef()
  result.bar = newKosmoSearchBar(
    subject,
    proc(query: string) =
      if not search.isNil:
        search[].refreshSearch(reset = true)
    ,
    proc() =
      if not search.isNil:
        search[].findNext(backwards = true)
    ,
    proc() =
      if not search.isNil:
        search[].findNext()
    ,
    proc() =
      if not search.isNil:
        search[].dismissSearch()
    ,
  )
  host.addSubview(result.bar)
  host.connect(nimkit.geometryDidChange, result, layoutSearch)

func searchMatchCount*(search: KosmoViewerSearch): int =
  search.matches.len

proc revealTextMatch*(
    textView: nimkit.TextView,
    scroll: nimkit.ScrollView,
    range: nimkit.TextRange,
    origin = nimkit.initPoint(0, 0),
): bool {.discardable.} =
  ## Select the match and center its first row in the owning scroll view.
  textView.selectedRange = range
  let frame = textView.characterRect(range.location)
  if not textView.layoutManager().hasValidLayout() or frame.isEmpty:
    return
  scroll.contentOffset = nimkit.initPoint(
    max(origin.x + frame.minX - scroll.viewportSize().width * 0.5'f32, 0),
    max(
      origin.y + frame.minY -
        (scroll.viewportSize().height - frame.size.height) * 0.5'f32,
      0,
    ),
  )
  result = true
