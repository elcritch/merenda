## Search UI and scrollback matching for Kosmo terminal tabs.

import std/[strutils, unicode]

import sigils/core

import ../nimkit as nimkit except performKeyEquivalent
from ../nimkit/foundation/selectors import performKeyEquivalent
import ../nimkit/text/searchmatching
import ./terminalinput
import ./scrolling

export terminalinput

type
  TerminalSearchException = object
    first, last: int # Half-open rune offsets within the row.
    column, endColumn: int

  TerminalSearchRow = object
    first, last: int # Half-open rune offsets in the search text.
    row, columns: int
    hasNewline: bool
    exceptions: seq[TerminalSearchException]

  TerminalSearchSnapshot = object
    text: string
    rows: seq[TerminalSearchRow]

  KosmoTerminalView* = ref object of nimkit.TerminalView
    search: nimkit.TextSearchController
    searchSnapshot: TerminalSearchSnapshot
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

proc terminalSearchSnapshot(
    session: nimkit.TerminalViewSession
): TerminalSearchSnapshot =
  let info = session.screenInfo()
  var offset = 0
  for row in 0 ..< info.totalLineCount:
    let line = session.lineAtAbsolute(row)
    var mapping = TerminalSearchRow(first: offset, row: row, columns: line.len)
    var expectedColumn = 0
    for column, cell in line:
      if not cell.continuation:
        var lastColumn = column + 1
        while lastColumn < line.len and line[lastColumn].continuation:
          inc lastColumn
        let count = if cell.text.len == 0: 1 else: cell.text.runeLen
        if count != 1 or lastColumn != column + 1 or column != expectedColumn:
          mapping.exceptions.add TerminalSearchException(
            first: offset - mapping.first,
            last: offset - mapping.first + count,
            column: column,
            endColumn: lastColumn,
          )
        if cell.text.len == 0:
          result.text.add ' '
        else:
          result.text.add cell.text
        offset += count
        expectedColumn = lastColumn
    if not line.lineEndsAtRightMargin():
      result.text.add '\n'
      mapping.hasNewline = true
      inc offset
    mapping.last = offset
    if mapping.last > mapping.first:
      result.rows.add move(mapping)

proc terminalPosition(
    snapshot: TerminalSearchSnapshot, index: int, endPosition: bool
): nimkit.TerminexPosition =
  if snapshot.rows.len == 0:
    return nimkit.initTerminalPosition(0, 0)
  let target = min(index, snapshot.rows[^1].last - 1)
  var low = 0
  var high = snapshot.rows.len
  while low < high:
    let middle = (low + high) div 2
    if snapshot.rows[middle].last <= target:
      low = middle + 1
    else:
      high = middle
  let row = snapshot.rows[low]
  let local = target - row.first
  if row.hasNewline and target == row.last - 1:
    return nimkit.initTerminalPosition(row.row, row.columns)
  var column = local
  for exception in row.exceptions:
    if local < exception.first:
      break
    if local < exception.last:
      return nimkit.initTerminalPosition(
        row.row,
        if endPosition or index > target: exception.endColumn else: exception.column,
      )
    column = exception.endColumn + local - exception.last
  if endPosition or index > target:
    inc column
  nimkit.initTerminalPosition(row.row, column)

proc terminalSelection(
    snapshot: TerminalSearchSnapshot, range: nimkit.TextRange
): nimkit.TerminalSelection =
  let anchor = snapshot.terminalPosition(int(range.location), false)
  let extent =
    if range.length > 0:
      snapshot.terminalPosition(range.maxIndex - 1, true)
    else:
      anchor
  nimkit.TerminalSelection(anchor: anchor, extent: extent)

proc terminalSearchMatches*(
    session: nimkit.TerminalViewSession, query: string, regularExpression = false
): seq[nimkit.TerminalSelection] =
  ## Search screen and scrollback with Reni, retaining terminal cell positions.
  ## Invalid expressions raise TextSearchError; empty queries have no matches.
  if not session.isNil and query.len > 0:
    let snapshot = session.terminalSearchSnapshot()
    let pattern = initTextSearchPattern(query, regularExpression, caseSensitive = false)
    for range in pattern.searchRanges(snapshot.text):
      result.add snapshot.terminalSelection(range)

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
      if event.kind == nimkit.mtreScrollWheel and
          nimkit.kmControl in event.scrollEvent.modifiers:
        var accelerated = event
        accelerated.scrollEvent.deltaY *= KosmoControlScrollMultiplier
        return rawHandler(accelerated)
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
          terminal[].searchSnapshot = terminal[].session().terminalSearchSnapshot()
          result = @[terminal[].searchSnapshot.text]
      ,
      reveal: proc(match: nimkit.TextSearchLocation) =
        if not terminal.isNil:
          terminal[].selectTerminalRange(
            terminal[].searchSnapshot.terminalSelection(match.range),
            centered = true,
            searchHighlight = true,
          )
      ,
      clear: proc() =
        if not terminal.isNil:
          terminal[].clearSelection()
          terminal[].searchSnapshot = TerminalSearchSnapshot()
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
