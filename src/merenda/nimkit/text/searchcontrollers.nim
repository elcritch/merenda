## Reusable Reni search controller with adapters for document text and selections.

import std/[options, unicode]
import sigils/core
import ../app/windows
import ../containers/scrollviews
import ../controls/searchbars
import ../foundation/[events, types]
import ../responder/keybindings
import ./[textfields, textlayout, textviews]
import ../view/[viewgeometry, views]
import ./searchmatching

export searchbars, searchmatching

type
  TextSearchLocation* = object ## A match in an adapter's current text snapshot.
    source*: int ## Index in the adapter's current text sources.
    range*: TextRange ## Match range in Unicode runes, including zero-width matches.

  TextSearchAdapter* = object ## Text source and optional editing callbacks.
    sources*: proc(): seq[string] {.closure.}
    reveal*: proc(match: TextSearchLocation) {.closure.}
    clear*: proc() {.closure.}
    replace*: proc(
      pattern: TextSearchPattern,
      replacement: TextSearchReplacement,
      selected: Option[TextSearchLocation],
      all: bool,
    ): int {.closure.} ## Optional; returns the number of replacements made.

  TextSearchController* = ref object of Agent ## Retained search state and controls.
    bar*: SearchBar
    host: WeakRef[View]
    adapter: TextSearchAdapter
    caseSensitive: bool
    matches: seq[TextSearchLocation]
    selected: int

proc plainSearchRanges*(text, query: string): seq[TextRange] =
  ## Case-insensitive literal Reni matches in rune coordinates.
  if query.len == 0:
    return
  initTextSearchPattern(query, caseSensitive = false).searchRanges(text)

proc searchVisible*(search: TextSearchController): bool =
  not search.isNil and not search.bar.hidden

proc revealSelected(search: TextSearchController) =
  if search.selected in 0 ..< search.matches.len:
    if not search.adapter.reveal.isNil:
      search.adapter.reveal(search.matches[search.selected])
  else:
    if not search.adapter.clear.isNil:
      search.adapter.clear()

proc refreshSearch*(search: TextSearchController, reset = false) =
  ## Rescan the adapter's current text snapshots and keep the selected match.
  ## Use reset when sources change order or when starting a different query.
  if not search.searchVisible():
    return
  var previous = TextSearchLocation(source: -1)
  if not reset and search.selected in 0 ..< search.matches.len:
    previous = search.matches[search.selected]
  search.matches.setLen(0)
  search.selected = -1
  search.bar.errorMessage = ""
  let query = search.bar.query()
  if query.len > 0:
    try:
      let pattern =
        initTextSearchPattern(query, search.bar.regularExpression, search.caseSensitive)
      for source, text in search.adapter.sources():
        for range in pattern.searchRanges(text):
          let match = TextSearchLocation(source: source, range: range)
          if match == previous:
            search.selected = search.matches.len
          search.matches.add match
    except CatchableError as error:
      search.matches.setLen(0)
      search.selected = -1
      search.bar.errorMessage = "Search error: " & error.msg
  if search.selected < 0 and search.matches.len > 0:
    search.selected = if search.bar.backwardsSearch: search.matches.high else: 0
  search.bar.hasMatches = search.matches.len > 0
  search.revealSelected()

proc findNext*(search: TextSearchController, backwards = false) =
  ## Refresh and select the next match, wrapping in either direction.
  search.refreshSearch()
  if search.matches.len > 0:
    let delta = if backwards: -1 else: 1
    search.selected =
      (search.selected + delta + search.matches.len) mod search.matches.len
    search.revealSelected()

proc dismissSearch*(search: TextSearchController) =
  search.bar.hidden = true
  search.matches.setLen(0)
  search.selected = -1
  if not search.adapter.clear.isNil:
    search.adapter.clear()
  if not search.host.isNil:
    let owner = search.host[].window()
    if owner of Window:
      discard Window(owner).makeFirstResponder(search.host[])

proc layoutSearch(search: TextSearchController) {.slot.} =
  if not search.host.isNil:
    search.bar.layoutInBounds(search.host[].bounds())

proc showSearch*(
    search: TextSearchController, replacing = false
): bool {.discardable.} =
  if search.isNil or search.host.isNil:
    return
  let owner = search.host[].window()
  if not (owner of Window):
    return
  search.bar.hidden = false
  search.bar.replacementVisible = replacing
  search.layoutSearch()
  search.bar.layoutSubtreeIfNeeded()
  search.refreshSearch()
  search.bar.queryField().selectedRange = initTextRange(0, search.bar.query().runeLen)
  Window(owner).makeFirstResponder(search.bar.queryField())

proc handleSearchKey*(search: TextSearchController, event: KeyEvent): bool =
  if event.key == keyF and event.modifiers == shortcutModifiers():
    return search.showSearch()
  if event.key == keyF and event.modifiers == shortcutModifiers() + {kmOption} and
      not search.adapter.replace.isNil:
    return search.showSearch(replacing = true)
  if search.searchVisible() and event.key == keyG:
    if event.modifiers == shortcutModifiers():
      search.findNext(backwards = search.bar.backwardsSearch)
      return true
    if event.modifiers == shortcutModifiers() + {kmShift}:
      search.findNext(backwards = not search.bar.backwardsSearch)
      return true

proc replaceMatch*(search: TextSearchController, all = false): int =
  ## Validate Reni capture templates before calling the adapter's editing hook.
  ## Adapters own undo, read-only checks, and checking for stale source content.
  if search.isNil or search.adapter.replace.isNil or search.bar.query().len == 0:
    return
  search.refreshSearch()
  if search.matches.len == 0:
    return
  try:
    let pattern = initTextSearchPattern(
      search.bar.query(), search.bar.regularExpression, search.caseSensitive
    )
    let replacement =
      pattern.initTextSearchReplacement(search.bar.replacementField().text())
    let selected =
      if search.selected in 0 ..< search.matches.len:
        some(search.matches[search.selected])
      else:
        none(TextSearchLocation)
    result = search.adapter.replace(pattern, replacement, selected, all)
    search.refreshSearch(reset = true)
  except CatchableError as error:
    search.bar.errorMessage = "Replacement error: " & error.msg

proc newTextSearchController*(
    host: View,
    subject: string,
    adapter: TextSearchAdapter,
    caseSensitive = false,
    backwardsSearch = false,
): TextSearchController =
  ## Attach floating search controls to a host. Supply a text snapshot callback;
  ## optional reveal, clear, and replacement hooks adapt other data sources.
  ## Keep source ordering stable until a reset; capture hosts with weak references
  ## when the host owns the controller to avoid a reference cycle.
  ## Retain the controller while its controls are attached; close it before
  ## releasing it if the host view remains alive.
  if host.isNil or adapter.sources.isNil:
    raise newException(ValueError, "Search requires a host and a text source callback")
  result = TextSearchController(
    host: host.unsafeWeakRef(),
    adapter: adapter,
    caseSensitive: caseSensitive,
    selected: -1,
  )
  let search = result.unsafeWeakRef()
  result.bar = newSearchBar(
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
  result.bar.enableExpressions()
  result.bar.backwardsSearch = backwardsSearch
  if not adapter.replace.isNil:
    result.bar.enableReplacement(
      proc() =
        if not search.isNil:
          discard search[].replaceMatch()
      ,
      proc() =
        if not search.isNil:
          discard search[].replaceMatch(all = true)
      ,
    )
  host.addSubview(result.bar)
  host.connect(geometryDidChange, result, layoutSearch)

func searchMatchCount*(search: TextSearchController): int =
  search.matches.len

func selectedSearchMatch*(search: TextSearchController): int =
  search.selected

proc close*(search: TextSearchController) =
  ## Detach controls and release adapter callbacks without changing focus.
  if search.isNil:
    return
  if not search.adapter.clear.isNil:
    search.adapter.clear()
  if not search.host.isNil:
    search.host[].disconnect(geometryDidChange, search, layoutSearch)
  search.bar.close()
  search.adapter = TextSearchAdapter()
  search.host = default(WeakRef[View])
  search.matches.setLen(0)
  search.selected = -1

proc errorMessage*(search: TextSearchController): string =
  search.bar.errorMessage()

proc revealTextMatch*(
    textView: TextView, scroll: ScrollView, range: TextRange, origin = initPoint(0, 0)
): bool {.discardable.} =
  ## Select the match and center its first row in the owning scroll view.
  textView.selectedRange = range
  let frame = textView.characterRect(range.location)
  if not textView.layoutManager().hasValidLayout() or frame.isEmpty:
    return
  scroll.contentOffset = initPoint(
    max(origin.x + frame.minX - scroll.viewportSize().width * 0.5'f32, 0),
    max(
      origin.y + frame.minY -
        (scroll.viewportSize().height - frame.size.height) * 0.5'f32,
      0,
    ),
  )
  result = true

proc textViewSearchAdapter*(
    textView: TextView, scroll: ScrollView = nil
): TextSearchAdapter =
  ## Adapt a TextView for find, with optional centered scrolling. Replacement is
  ## supplied by an editing adapter so it can preserve its own undo contract.
  if textView.isNil:
    raise newException(ValueError, "Text search requires a text view")
  let view = textView.unsafeWeakRef()
  let scroller = scroll.unsafeWeakRef()
  TextSearchAdapter(
    sources: proc(): seq[string] =
      if not view.isNil:
        result = @[view[].stringValue()]
    ,
    reveal: proc(match: TextSearchLocation) =
      if not view.isNil:
        if scroller.isNil:
          view[].selectedRange = match.range
        else:
          discard revealTextMatch(view[], scroller[], match.range)
    ,
    clear: proc() =
      if not view.isNil:
        view[].selectedRange = initTextRange(0, 0)
    ,
  )
