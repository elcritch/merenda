## Search UI and scrollback matching for Kosmo terminal tabs.

import std/[strutils, unicode]

import sigils/core

import ../nimkit as nimkit except performKeyEquivalent
from ../nimkit/foundation/selectors import performKeyEquivalent
import ../nimkit/text/searchmatching
import ./terminalinput

export terminalinput

type
  TerminalSearchGlyph = object
    value: Rune
    first, last: nimkit.TerminexPosition

  KosmoTerminalView* = ref object of nimkit.TerminalView
    search: nimkit.TextSearchController
    searchGlyphs: seq[TerminalSearchGlyph]
    xInputPolicy: KosmoTerminalInputPolicy
    xShortcutState: TerminalShortcutState
    xPaneCommandHandler: proc(command: KosmoPaneCommand): bool {.closure.}
    xShortcutWindow: nimkit.BackRef[nimkit.Window]

proc terminalShortcutFocusLost(view: KosmoTerminalView) {.slot.} =
  view.xShortcutState.reset()

proc observeShortcutWindow*(view: KosmoTerminalView, window: nimkit.Window) =
  ## Reset incomplete shortcuts when the owning window loses keyboard focus.
  if view.xShortcutWindow.target == window:
    return
  if not view.xShortcutWindow.isNil:
    view.xShortcutWindow.target.disconnect(
      nimkit.didResignKeyWindow, view, terminalShortcutFocusLost
    )
  view.xShortcutWindow.target = window
  if not window.isNil:
    window.connect(nimkit.didResignKeyWindow, view, terminalShortcutFocusLost)

proc terminalInputPolicy*(view: KosmoTerminalView): KosmoTerminalInputPolicy =
  view.xInputPolicy

proc `terminalInputPolicy=`*(
    view: KosmoTerminalView, policy: KosmoTerminalInputPolicy
) =
  ## Apply shortcut routing and discard an unfinished prefix.
  view.xInputPolicy = policy
  view.xShortcutState.reset()

proc `paneCommandHandler=`*(
    view: KosmoTerminalView, handler: proc(command: KosmoPaneCommand): bool {.closure.}
) =
  ## Attach the owning dock's scoped pane command handler.
  view.xPaneCommandHandler = handler
  view.xShortcutState.reset()

proc interceptTerminalKey(view: KosmoTerminalView, event: nimkit.KeyEvent): bool =
  let owner = view.window()
  let route = view.xShortcutState.routeTerminalKey(
    event, view.xInputPolicy, panesEnabled = not view.xPaneCommandHandler.isNil
  )
  case route.kind
  of tkrPass:
    discard
  of tkrConsume:
    result = true
  of tkrPane:
    discard view.xPaneCommandHandler(route.command)
    result = true
  of tkrCopy, tkrPaste:
    let selector =
      if route.kind == tkrCopy:
        nimkit.copy()
      else:
        nimkit.paste()
    discard view.sendLocalIfHandled(selector, nimkit.ActionArgs(sender: view))
    result = true
  of tkrRaw:
    for key in route.keys:
      let bytes = nimkit.terminalKeyInput(
        key, view.session().screenInfo().modes, view.optionAsMeta
      )
      if bytes.len > 0:
        discard view.sendTerminalKeyInput(key)
    result =
      nimkit.terminalKeyInput(
        event, view.session().screenInfo().modes, view.optionAsMeta
      ).len > 0
  if result and event.modifiers - {nimkit.kmShift} == {}:
    let textKey =
      event.key in nimkit.keyA .. nimkit.keyZ or
      event.key in {nimkit.keyEqual, nimkit.keyMinus, nimkit.keyComma, nimkit.keyDot}
    if owner of nimkit.Window and
        (event.text.len > 0 or (route.kind == tkrPane and textKey)):
      nimkit.Window(owner).suppressShortcutText(event.text)

proc dismissSearch*(view: KosmoTerminalView)
proc findPrevious*(view: KosmoTerminalView)
proc findNext*(view: KosmoTerminalView)

func lineEndsAtRightMargin(line: nimkit.TerminexLine): bool =
  line.len > 0 and (line[^1].text.len > 0 or line[^1].continuation)

proc addSearchGlyph(
    glyphs: var seq[TerminalSearchGlyph], value: Rune, row, firstColumn, lastColumn: int
) =
  glyphs.add TerminalSearchGlyph(
    value: value,
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
          var lastColumn = column + 1
          while lastColumn < line.len and line[lastColumn].continuation:
            inc lastColumn
          for value in cell.text.runes:
            result.addSearchGlyph(value, row, column, lastColumn)
    if not line.lineEndsAtRightMargin():
      result.addSearchGlyph(Rune('\n'), row, line.len, line.len)

proc searchText(glyphs: seq[TerminalSearchGlyph]): string =
  result = newStringOfCap(glyphs.len)
  for glyph in glyphs:
    result.add glyph.value

proc terminalSelection(
    glyphs: seq[TerminalSearchGlyph], range: nimkit.TextRange
): nimkit.TerminalSelection =
  let first = int(range.location)
  let anchor =
    if first < glyphs.len:
      glyphs[first].first
    elif glyphs.len > 0:
      glyphs[^1].last
    else:
      nimkit.initTerminalPosition(0, 0)
  let extent =
    if range.length > 0:
      glyphs[range.maxIndex - 1].last
    else:
      anchor
  nimkit.TerminalSelection(anchor: anchor, extent: extent)

proc terminalSearchMatches*(
    session: nimkit.TerminalViewSession, query: string, regularExpression = false
): seq[nimkit.TerminalSelection] =
  ## Search screen and scrollback with Reni, retaining terminal cell positions.
  ## Invalid expressions raise TextSearchError; empty queries have no matches.
  if not session.isNil and query.len > 0:
    let glyphs = session.terminalSearchGlyphs()
    let pattern = initTextSearchPattern(query, regularExpression, caseSensitive = false)
    for range in pattern.searchRanges(glyphs.searchText()):
      result.add glyphs.terminalSelection(range)

proc findPrevious*(view: KosmoTerminalView) =
  ## Select and reveal the previous terminal match, wrapping at the beginning.
  if not view.isNil:
    view.search.findNext(backwards = true)

proc findNext*(view: KosmoTerminalView) =
  ## Select and reveal the next terminal match, wrapping at the end.
  if not view.isNil:
    view.search.findNext()

proc dismissSearch*(view: KosmoTerminalView) =
  ## Hide terminal search, clear its selection, and return focus to the terminal.
  if not view.isNil:
    view.search.dismissSearch()

proc showSearch*(view: KosmoTerminalView): bool {.discardable.} =
  ## Show the terminal search widget and focus its query field.
  if view.isNil or view.search.isNil:
    return
  if not view.search.searchVisible():
    view.search.bar.query = ""
  view.search.showSearch()

protocol KosmoTerminalKeyEquivalents of nimkit.ResponderCommandDispatchProtocol:
  method interceptKeyEquivalent(view: KosmoTerminalView, event: nimkit.KeyEvent): bool =
    view.interceptTerminalKey(event)

  method performKeyEquivalent(view: KosmoTerminalView, event: nimkit.KeyEvent): bool =
    if event.key == nimkit.keyF and event.modifiers == nimkit.terminalShortcutModifiers():
      return view.showSearch()
    if not view.search.bar.hidden() and event.key == nimkit.keyG:
      if event.modifiers == nimkit.shortcutModifiers():
        view.findPrevious()
        return true
      if event.modifiers == nimkit.shortcutModifiers() + {nimkit.kmShift}:
        view.findNext()
        return true
    let owner = view.window()
    if owner of nimkit.Window:
      let binding = nimkit.Window(owner).keyBindings().match([event])
      let terminalInputShortcut =
        event.key in {nimkit.keyA, nimkit.keyC, nimkit.keyX, nimkit.keyV} and (
          event.modifiers == nimkit.terminalShortcutModifiers() or
          event.modifiers == {nimkit.kmControl}
        )
      # Clipboard shortcuts and bare Ctrl input belong to the focused terminal.
      # Other Kosmo commands still route through the window's bindings.
      if not terminalInputShortcut and binding.kind == nimkit.kbmCommand and
          binding.selector.name.startsWith("kosmo."):
        return false
    nimkit.performTerminalKeyEquivalent(nimkit.TerminalView(view), event)

protocol KosmoTerminalViewLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(view: KosmoTerminalView) =
    view.resizeToFit()
    view.search.bar.layoutInBounds(view.bounds())

proc newKosmoTerminalView*(
    session: nimkit.TerminalViewSession = nil,
    frame: nimkit.Rect = nimkit.AutoRect,
    palette = nimkit.initTerminalPalette(),
): KosmoTerminalView =
  ## Create a terminal view with Kosmo's in-buffer search widget.
  result = KosmoTerminalView()
  result.initTerminalViewFields(session, frame, palette)
  let
    terminalOwner = result.unsafeWeakRef()
    rawHandler = result.rawEventHandler()
    focusHandler = result.localMethod(nimkit.didResignFirstResponder())
  result.rawEventHandler = proc(event: nimkit.MonoTextRawEvent): bool =
    if not terminalOwner.isNil:
      if event.kind == nimkit.mtreKeyDown and
          terminalOwner[].interceptTerminalKey(event.keyEvent):
        return true
      result = rawHandler(event)
  discard result.replaceMethod(
    nimkit.didResignFirstResponder(),
    proc(self: nimkit.DynamicAgent, invocation: var nimkit.Invocation) =
      KosmoTerminalView(self).xShortcutState.reset()
      if not focusHandler.isNil:
        focusHandler(self, invocation)
    ,
  )
  discard result.withProtocol(KosmoTerminalKeyEquivalents)
  discard result.withProtocol(KosmoTerminalViewLayout)

  let terminal = result.unsafeWeakRef()
  result.search = nimkit.newTextSearchController(
    result,
    "terminal output",
    nimkit.TextSearchAdapter(
      sources: proc(): seq[string] =
        if not terminal.isNil:
          terminal[].searchGlyphs = terminal[].session().terminalSearchGlyphs()
          result = @[terminal[].searchGlyphs.searchText()]
      ,
      reveal: proc(match: nimkit.TextSearchLocation) =
        if not terminal.isNil:
          terminal[].selectTerminalRange(
            terminal[].searchGlyphs.terminalSelection(match.range), centered = true
          )
      ,
      clear: proc() =
        if not terminal.isNil:
          terminal[].clearSelection()
          terminal[].searchGlyphs = @[]
      ,
    ),
    backwardsSearch = true,
  )

func searchField*(view: KosmoTerminalView): nimkit.TextField =
  if not view.isNil:
    result = view.search.bar.queryField()

proc searchVisible*(view: KosmoTerminalView): bool =
  not view.isNil and view.search.searchVisible()

func searchMatchCount*(view: KosmoTerminalView): int =
  if not view.isNil:
    result = view.search.searchMatchCount()

func selectedSearchMatch*(view: KosmoTerminalView): int =
  if view.isNil:
    -1
  else:
    view.search.selectedSearchMatch()
