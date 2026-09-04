## Search UI and scrollback matching for Kosmo terminal tabs.

import std/unicode

import sigils/core

import ../nimkit as nimkit except performKeyEquivalent
from ../nimkit/foundation/selectors import performKeyEquivalent
import ./searchbar

type
  TerminalSearchGlyph = object
    value: Rune
    first, last: nimkit.TerminexPosition

  KosmoTerminalView* = ref object of nimkit.TerminalView
    searchBar: KosmoSearchBar
    xSearchMatches: seq[nimkit.TerminalSelection]
    xSelectedSearchMatch: int

proc dismissSearch*(view: KosmoTerminalView)
proc findPrevious*(view: KosmoTerminalView)
proc findNext*(view: KosmoTerminalView)

func lineEndsAtRightMargin(line: nimkit.TerminexLine): bool =
  line.len > 0 and (line[^1].text.len > 0 or line[^1].continuation)

proc addSearchGlyph(
    glyphs: var seq[TerminalSearchGlyph], value: Rune, row, firstColumn, lastColumn: int
) =
  glyphs.add TerminalSearchGlyph(
    value: value.toLower(),
    first: nimkit.initTerminalPosition(row, firstColumn),
    last: nimkit.initTerminalPosition(row, lastColumn),
  )

proc terminalSearchGlyphs(
    session: nimkit.TerminalViewSession
): seq[TerminalSearchGlyph] =
  let info = session.screenInfo()
  for row in 0 ..< info.totalLineCount:
    let line = session.lineAtAbsolute(row)
    for column, cell in line:
      if not cell.continuation:
        if cell.text.len == 0:
          result.addSearchGlyph(Rune(' '), row, column, column + 1)
        else:
          for value in cell.text.runes:
            result.addSearchGlyph(value, row, column, column + 1)
    if not line.lineEndsAtRightMargin():
      result.addSearchGlyph(Rune('\n'), row, line.len, line.len)

proc terminalSearchMatches*(
    session: nimkit.TerminalViewSession, query: string
): seq[nimkit.TerminalSelection] =
  ## Find case-insensitive text occurrences in the visible screen and scrollback.
  if session.isNil or query.len == 0:
    return
  let
    glyphs = session.terminalSearchGlyphs()
    needle = block:
      var normalized: seq[Rune]
      for value in query.runes:
        normalized.add value.toLower()
      normalized
  if needle.len == 0 or needle.len > glyphs.len:
    return
  for first in 0 .. glyphs.len - needle.len:
    var matches = true
    for offset, value in needle:
      if glyphs[first + offset].value != value:
        matches = false
        break
    if matches:
      result.add nimkit.TerminalSelection(
        anchor: glyphs[first].first, extent: glyphs[first + needle.high].last
      )

proc syncSearchControls(view: KosmoTerminalView) =
  view.searchBar.hasMatches = view.xSearchMatches.len > 0

proc selectSearchMatch(view: KosmoTerminalView, index: int) =
  if index notin 0 ..< view.xSearchMatches.len:
    view.xSelectedSearchMatch = -1
    view.clearSelection()
    return
  view.xSelectedSearchMatch = index
  view.selectTerminalRange(view.xSearchMatches[index])

proc refreshSearchMatches(view: KosmoTerminalView) =
  view.xSearchMatches = terminalSearchMatches(view.session(), view.searchBar.query())
  view.selectSearchMatch(
    if view.xSearchMatches.len > 0: view.xSearchMatches.high else: -1
  )
  view.syncSearchControls()

proc moveSearchMatch(view: KosmoTerminalView, delta: int) =
  if view.isNil or delta == 0:
    return
  if view.xSearchMatches.len == 0:
    view.refreshSearchMatches()
  if view.xSearchMatches.len == 0:
    return
  let next =
    if view.xSelectedSearchMatch notin 0 ..< view.xSearchMatches.len:
      if delta < 0: view.xSearchMatches.high else: 0
    else:
      (view.xSelectedSearchMatch + delta + view.xSearchMatches.len) mod
        view.xSearchMatches.len
  view.selectSearchMatch(next)

proc findPrevious*(view: KosmoTerminalView) =
  ## Select and reveal the previous terminal match, wrapping at the beginning.
  view.moveSearchMatch(-1)

proc findNext*(view: KosmoTerminalView) =
  ## Select and reveal the next terminal match, wrapping at the end.
  view.moveSearchMatch(1)

proc dismissSearch*(view: KosmoTerminalView) =
  ## Hide terminal search, clear its selection, and return focus to the terminal.
  if view.isNil or view.searchBar.isNil:
    return
  view.searchBar.hidden = true
  view.xSearchMatches.setLen(0)
  view.xSelectedSearchMatch = -1
  view.clearSelection()
  let owner = view.window()
  if owner of nimkit.Window:
    discard nimkit.Window(owner).makeFirstResponder(view)

proc showSearch*(view: KosmoTerminalView): bool {.discardable.} =
  ## Show the terminal search widget and focus its query field.
  if view.isNil or view.searchBar.isNil:
    return
  let owner = view.window()
  if not (owner of nimkit.Window):
    return
  if view.searchBar.hidden():
    view.searchBar.query = ""
    view.refreshSearchMatches()
    view.searchBar.hidden = false
    view.setNeedsLayout()
    view.layoutSubtreeIfNeeded()
  else:
    view.searchBar.queryField().selectedRange =
      nimkit.initTextRange(0, view.searchBar.query().runeLen)
  result = nimkit.Window(owner).makeFirstResponder(view.searchBar.queryField())

protocol KosmoTerminalKeyEquivalents of nimkit.ResponderCommandDispatchProtocol:
  method performKeyEquivalent(view: KosmoTerminalView, event: nimkit.KeyEvent): bool =
    if event.key == nimkit.keyF and event.modifiers == nimkit.terminalShortcutModifiers():
      return view.showSearch()
    nimkit.performTerminalKeyEquivalent(nimkit.TerminalView(view), event)

protocol KosmoTerminalViewLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(view: KosmoTerminalView) =
    view.resizeToFit()
    view.searchBar.layoutInBounds(view.bounds())

proc newKosmoTerminalView*(
    session: nimkit.TerminalViewSession = nil,
    frame: nimkit.Rect = nimkit.AutoRect,
    palette = nimkit.initTerminalPalette(),
): KosmoTerminalView =
  ## Create a terminal view with Kosmo's in-buffer search widget.
  result = KosmoTerminalView(xSelectedSearchMatch: -1)
  result.initTerminalViewFields(session, frame, palette)
  discard result.withProtocol(KosmoTerminalKeyEquivalents)
  discard result.withProtocol(KosmoTerminalViewLayout)

  let
    terminal = result.unsafeWeakRef()
    onQueryChanged: KosmoSearchQueryAction = proc(query: string) =
      discard query
      if not terminal.isNil:
        terminal[].refreshSearchMatches()
    onPrevious: KosmoSearchAction = proc() =
      if not terminal.isNil:
        terminal[].findPrevious()
    onNext: KosmoSearchAction = proc() =
      if not terminal.isNil:
        terminal[].findNext()
    onClose: KosmoSearchAction = proc() =
      if not terminal.isNil:
        terminal[].dismissSearch()
  result.searchBar =
    newKosmoSearchBar("terminal output", onQueryChanged, onPrevious, onNext, onClose)
  result.addSubview(result.searchBar)
  result.syncSearchControls()
  result.searchBar.applyKosmoSearchAppearance(result.effectiveAppearance())

func searchField*(view: KosmoTerminalView): nimkit.TextField =
  if not view.isNil and not view.searchBar.isNil:
    result = view.searchBar.queryField()

proc searchVisible*(view: KosmoTerminalView): bool =
  not view.isNil and not view.searchBar.isNil and not view.searchBar.hidden()

func searchMatchCount*(view: KosmoTerminalView): int =
  if not view.isNil:
    result = view.xSearchMatches.len

func selectedSearchMatch*(view: KosmoTerminalView): int =
  if view.isNil: -1 else: view.xSelectedSearchMatch
