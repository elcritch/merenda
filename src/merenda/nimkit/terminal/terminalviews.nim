## A reusable terminal-emulator view backed by Terminex.

import std/[math, strutils, times, unicode]

import sigils/core
import terminex/[ringbuffer, terminput, termscreen, termsessions]

import ../app/[animations, pasteboards]
import ../app/windows except performKeyEquivalent
import ../foundation/[events, selectors, types]
import ../responder/responders
from ../text/textviews import isInsertableText
import ../text/monotextviews
import ../view/views

const
  DefaultTerminalFontSize* = 14.0'f32
  DefaultTerminalPadding* = 4.0'f32

type
  TerminalPalette* = object
    colors*: array[16, Color]
    foreground*, background*: Color
    selection*, cursor*: Color

  TerminalSelection* = object
    anchor*, extent*: TerminexPosition

  TerminalView* = ref object of MonoTextView
    xSession: TerminexSession[TerminexCell, TerminexLine, RingBuffer[TerminexLine]]
    xPalette: TerminalPalette
    xSelection: TerminalSelection
    xHasSelection: bool
    xSelecting: bool
    xScrollPosition: float32
    xLastScrollbackCount: int
    xLastGeneration: uint64
    xRenderedStart, xRenderedRows, xRenderedColumns: int
    xCachedLineHeight, xCachedFontSize: float32
    xCachedFontName: string
    xLastTitle, xLastDirectory: string
    xLastBellCount: uint64
    xExitNotified: bool
    xAllowsClipboardWrites: bool
    xOptionAsMeta: bool
    xSuppressOptionTextInput: bool
    xLastInputError: string
    xBlinkElapsed: Duration
    xBlinkVisible: bool
    xHeartbeat: Animation
    xPollingWindow: BackRef[Window]

protocol TerminalViewEvents:
  proc terminalTitleDidChange*(view: TerminalView, title: string) {.signal.}
  proc terminalDirectoryDidChange*(view: TerminalView, directory: string) {.signal.}
  proc terminalBellDidRing*(view: TerminalView) {.signal.}
  proc terminalProcessDidExit*(view: TerminalView, exitCode: int) {.signal.}
  proc terminalHyperlinkWasActivated*(view: TerminalView, link: string) {.signal.}

func initTerminalPalette*(): TerminalPalette =
  TerminalPalette(
    colors: [
      color(0.10, 0.11, 0.13, 1.0),
      color(0.80, 0.22, 0.25, 1.0),
      color(0.31, 0.72, 0.36, 1.0),
      color(0.85, 0.69, 0.30, 1.0),
      color(0.30, 0.49, 0.85, 1.0),
      color(0.70, 0.36, 0.78, 1.0),
      color(0.27, 0.70, 0.73, 1.0),
      color(0.78, 0.79, 0.82, 1.0),
      color(0.35, 0.37, 0.41, 1.0),
      color(0.96, 0.39, 0.41, 1.0),
      color(0.49, 0.86, 0.49, 1.0),
      color(0.98, 0.82, 0.43, 1.0),
      color(0.46, 0.65, 0.96, 1.0),
      color(0.84, 0.51, 0.91, 1.0),
      color(0.45, 0.86, 0.88, 1.0),
      color(0.94, 0.94, 0.95, 1.0),
    ],
    foreground: color(0.86, 0.87, 0.89, 1.0),
    background: color(0.055, 0.06, 0.075, 1.0),
    selection: color(0.25, 0.43, 0.72, 0.72),
    cursor: color(0.88, 0.89, 0.91, 0.66),
  )

func colorByte(value: int): float32 =
  clamp(value, 0, 255).float32 / 255.0'f32

func indexedColor(palette: TerminalPalette, index: uint8): Color =
  let value = index.int
  if value < 16:
    return palette.colors[value]
  if value < 232:
    let
      cube = value - 16
      red = cube div 36
      green = (cube div 6) mod 6
      blue = cube mod 6
    func component(level: int): int =
      if level == 0:
        0
      else:
        55 + level * 40
    return color(
      component(red).colorByte(),
      component(green).colorByte(),
      component(blue).colorByte(),
      1.0,
    )
  let gray = 8 + (value - 232) * 10
  color(gray.colorByte(), gray.colorByte(), gray.colorByte(), 1.0)

func resolvedColor(
    palette: TerminalPalette, value: TerminexColor, fallback: Color
): Color =
  case value.kind
  of tckDefault:
    fallback
  of tckIndexed:
    palette.indexedColor(value.index)
  of tckRgb:
    color(
      value.red.int.colorByte(),
      value.green.int.colorByte(),
      value.blue.int.colorByte(),
      1.0,
    )

func positionLess(left, right: TerminexPosition): bool =
  left.row < right.row or (left.row == right.row and left.column < right.column)

func orderedSelection(
    selection: TerminalSelection
): tuple[first, last: TerminexPosition] =
  if selection.extent.positionLess(selection.anchor):
    (selection.extent, selection.anchor)
  else:
    (selection.anchor, selection.extent)

func contains(selection: TerminalSelection, row, column: int): bool =
  let
    bounds = selection.orderedSelection()
    position = initTerminalPosition(row, column)
  not position.positionLess(bounds.first) and position.positionLess(bounds.last)

func terminalCellToMonoTextCell*(
    cell: TerminexCell, palette: TerminalPalette, selected = false, blinkVisible = true
): MonoTextCell =
  var
    foreground = palette.resolvedColor(cell.style.foreground, palette.foreground)
    background = palette.resolvedColor(cell.style.background, palette.background)
    traits: set[MonoTextTrait]
    decorations: set[MonoTextDecoration]
  if taInverse in cell.style.attributes:
    swap foreground, background
  if taBold in cell.style.attributes:
    traits.incl mttBold
  if taFaint in cell.style.attributes:
    traits.incl mttFaint
  if taItalic in cell.style.attributes:
    traits.incl mttItalic
  if taHidden in cell.style.attributes or
      (taBlink in cell.style.attributes and not blinkVisible):
    traits.incl mttHidden
  if taUnderline in cell.style.attributes:
    decorations.incl mtdUnderline
  if taDoubleUnderline in cell.style.attributes:
    decorations.incl mtdDoubleUnderline
  if taStrikethrough in cell.style.attributes:
    decorations.incl mtdStrikethrough
  if taOverline in cell.style.attributes:
    decorations.incl mtdOverline
  let decorationColor = palette.resolvedColor(cell.style.underlineColor, foreground)
  initMonoTextCell(
    if cell.continuation or cell.text.len == 0: " " else: cell.text,
    foreground,
    if selected: palette.selection else: background,
    hasForegroundColor = true,
    hasBackgroundColor = true,
    traits = traits,
    decorations = decorations,
    decorationColor = decorationColor,
    hasDecorationColor = cell.style.underlineColor.kind != tckDefault,
  )

static:
  doAssert ord(keyF15) - ord(keyA) == ord(tkF15) - ord(tkA)
  doAssert ord(keyBackspace) - ord(keyLeftBracket) ==
    ord(tkBackspace) - ord(tkLeftBracket)
  doAssert ord(keyDivide) - ord(keySlash) == ord(tkDivide) - ord(tkSlash)

func toTerminexKey(key: Key): TerminexKey =
  case key
  of keyA .. keyF15:
    TerminexKey(ord(tkA) + ord(key) - ord(keyA))
  of keyLeftBracket .. keyBackspace:
    TerminexKey(ord(tkLeftBracket) + ord(key) - ord(keyLeftBracket))
  of keySlash .. keyDivide:
    TerminexKey(ord(tkSlash) + ord(key) - ord(keySlash))
  else:
    tkUnknown

func toTerminexModifiers(modifiers: set[KeyModifier]): set[TerminexModifier] =
  if kmShift in modifiers:
    result.incl tmShift
  if kmControl in modifiers:
    result.incl tmControl
  if kmOption in modifiers:
    result.incl tmAlt
  if kmCommand in modifiers:
    result.incl tmSuper

func toTerminexKeyEvent(event: KeyEvent): TerminexKeyEvent =
  TerminexKeyEvent(
    key: event.key.toTerminexKey(),
    text: event.text,
    modifiers: event.modifiers.toTerminexModifiers(),
  )

func isPrintableTerminalKey(key: Key): bool =
  key in keyA .. keyEqual or key in keyLeftBracket .. keySpace or
    key in keySlash .. keyBackslash or key in keyNumpad0 .. keyDivide

func terminalKeyInput*(
    event: KeyEvent, modes: TerminexModes, optionAsMeta = true
): string =
  ## Translate a NimKit key event into xterm-compatible input bytes.
  terminput.terminalKeyInput(event.toTerminexKeyEvent(), modes, optionAsMeta)

func terminalShortcutModifiers*(): set[KeyModifier] =
  ## Modifiers for terminal-local clipboard and scrollback shortcuts.
  ##
  ## Ctrl is terminal input on Linux and Windows, so use Ctrl-Shift there.
  when defined(macosx) or defined(macos):
    {kmCommand}
  else:
    {kmControl, kmShift}

func toTerminexMouseButton(button: MouseButton): TerminexMouseButton =
  case button
  of mbPrimary: tmbPrimary
  of mbOther: tmbMiddle
  of mbSecondary: tmbSecondary

func encodeMouseInput(
    session: TerminexSession[TerminexCell, TerminexLine, RingBuffer[TerminexLine]],
    row, column: int,
    button: TerminexMouseButton,
    release, motion: bool,
    modifiers: set[KeyModifier],
): string =
  let info = session.screenInfo()
  terminput.encodeTerminalMouseInput(
    info.modes,
    info.columns,
    info.rows,
    row,
    column,
    button,
    modifiers.toTerminexModifiers(),
    release,
    motion,
  )

func session*(
    view: TerminalView
): TerminexSession[TerminexCell, TerminexLine, RingBuffer[TerminexLine]] =
  view.xSession

proc syncTerminalScreen(view: TerminalView)
proc startTerminalPolling(view: TerminalView)
proc stopTerminalPolling(view: TerminalView)

proc `session=`*(
    view: TerminalView,
    session: TerminexSession[TerminexCell, TerminexLine, RingBuffer[TerminexLine]],
) =
  let next =
    if session.isNil:
      newTerminalSession()
    else:
      session
  if view.xSession == next:
    return
  view.stopTerminalPolling()
  view.xSession = next
  view.xLastGeneration = high(uint64)
  view.xLastScrollbackCount = next.screenInfo().scrollbackCount
  view.xExitNotified = false
  view.xScrollPosition = 0.0'f32
  view.xHasSelection = false
  view.syncTerminalScreen()
  view.startTerminalPolling()

func palette*(view: TerminalView): TerminalPalette =
  view.xPalette

proc `palette=`*(view: TerminalView, palette: TerminalPalette) =
  if view.xPalette == palette:
    return
  view.xPalette = palette
  view.textColor = palette.foreground
  view.cursorColor = palette.cursor
  view.backgroundColor = palette.background
  view.xLastGeneration = high(uint64)
  view.syncTerminalScreen()

func allowsClipboardWrites*(view: TerminalView): bool =
  view.xAllowsClipboardWrites

proc `allowsClipboardWrites=`*(view: TerminalView, value: bool) =
  view.xAllowsClipboardWrites = value

func optionAsMeta*(view: TerminalView): bool =
  ## Whether Option/Alt prefixes terminal input with Escape (Meta).
  view.xOptionAsMeta

proc `optionAsMeta=`*(view: TerminalView, value: bool) =
  ## Configure Option/Alt to behave as the terminal Meta modifier.
  view.xOptionAsMeta = value
  if not value:
    view.xSuppressOptionTextInput = false

func lastInputError*(view: TerminalView): string =
  view.xLastInputError

func scrollPosition*(view: TerminalView): float32 =
  view.xScrollPosition

func hasSelection*(view: TerminalView): bool =
  view.xHasSelection

func selection*(view: TerminalView): TerminalSelection =
  view.xSelection

proc clearSelection*(view: TerminalView) =
  if not view.xHasSelection:
    return
  view.xHasSelection = false
  view.xSelecting = false
  view.xLastGeneration = high(uint64)
  view.syncTerminalScreen()

proc clearScrollback*(view: TerminalView) =
  ## Remove saved history and return the viewport to the live screen.
  if view.isNil or view.xSession.isNil:
    return
  view.xSession.clearScrollback()
  view.xScrollPosition = 0.0'f32
  view.xLastScrollbackCount = 0
  view.xHasSelection = false
  view.xSelecting = false
  view.xLastGeneration = high(uint64)
  view.syncTerminalScreen()

proc sendInput*(view: TerminalView, input: string): bool {.discardable.} =
  if view.isNil or view.xSession.isNil or input.len == 0:
    return false
  try:
    view.xSession.write(input)
    view.xLastInputError.setLen(0)
    view.xScrollPosition = 0.0'f32
    view.clearSelection()
    true
  except TerminexSessionError as error:
    view.xLastInputError = error.msg
    false

proc pasteText*(view: TerminalView, text: string): bool {.discardable.} =
  if text.len == 0:
    return false
  let input = terminput.terminalPasteInput(text, view.xSession.screenInfo().modes)
  view.sendInput(input)

func endsAtRightMargin(line: TerminexLine): bool =
  line.len > 0 and (line[^1].text.len > 0 or line[^1].continuation)

proc selectionText*(view: TerminalView): string =
  if not view.xHasSelection:
    return
  let
    bounds = view.xSelection.orderedSelection()
    totalLineCount = view.xSession.screenInfo().totalLineCount
  var
    selectedLineCount = 0
    previousLineEndedAtRightMargin = false
  for row in bounds.first.row .. bounds.last.row:
    if row < 0 or row >= totalLineCount:
      continue
    let
      line = view.xSession.lineAtAbsolute(row)
      firstColumn = if row == bounds.first.row: bounds.first.column else: 0
      lastColumn = if row == bounds.last.row: bounds.last.column else: line.len
    var text = ""
    for column in clamp(firstColumn, 0, line.len) ..< clamp(lastColumn, 0, line.len):
      if not line[column].continuation:
        if line[column].text.len > 0:
          text.add line[column].text
        else:
          text.add ' '
    text = text.strip(leading = false, trailing = true, chars = {' '})
    if selectedLineCount > 0 and not previousLineEndedAtRightMargin:
      result.add '\n'
    result.add text
    inc selectedLineCount
    previousLineEndedAtRightMargin = line.endsAtRightMargin()

proc viewportOffset(view: TerminalView): int =
  int(ceil(view.xScrollPosition.float64))

proc viewportStart(view: TerminalView): int =
  let info = view.xSession.screenInfo()
  max(info.totalLineCount - info.rows - view.viewportOffset(), 0)

proc terminalRowsToMonoTextCells(
    view: TerminalView,
    session: TerminexSession[TerminexCell, TerminexLine, RingBuffer[TerminexLine]],
    columns, firstRow, rowCount: int,
): seq[MonoTextCell] =
  result = newSeq[MonoTextCell](max(rowCount, 0) * columns)
  for row in 0 ..< max(rowCount, 0):
    let
      absoluteRow = firstRow + row
      line = session.lineAtAbsolute(absoluteRow)
    for column in 0 ..< columns:
      result[row * columns + column] = terminalCellToMonoTextCell(
        if column < line.len:
          line[column]
        else:
          initTerminalCell(),
        view.xPalette,
        selected = view.xHasSelection and view.xSelection.contains(absoluteRow, column),
        blinkVisible = view.xBlinkVisible,
      )

proc renderedGridDimensionsMatch(view: TerminalView, rows, columns: int): bool =
  if view.xRenderedRows != rows or view.xRenderedColumns != columns or
      view.lineCount() != rows:
    return false
  for row in 0 ..< rows:
    if view.columnCount(row) != columns:
      return false
  true

proc synchronizeTerminalGrid(
    view: TerminalView,
    session: TerminexSession[TerminexCell, TerminexLine, RingBuffer[TerminexLine]],
    info: TerminexScreenInfo,
    start: int,
) =
  let
    rows = info.rows
    columns = info.columns
    rowOffset = start - view.xRenderedStart
    canReuseRows =
      view.xLastGeneration == info.generation and
      view.renderedGridDimensionsMatch(rows, columns)
  if canReuseRows and rowOffset != 0 and abs(rowOffset) < rows:
    let
      replacementCount = abs(rowOffset)
      firstReplacementRow =
        if rowOffset > 0:
          start + rows - replacementCount
        else:
          start
      replacementCells = view.terminalRowsToMonoTextCells(
        session, columns, firstReplacementRow, replacementCount
      )
    view.scrollGridRows(rowOffset, replacementCells)
  elif not canReuseRows or rowOffset != 0:
    view.replaceGrid(
      rows, columns, view.terminalRowsToMonoTextCells(session, columns, start, rows)
    )
  view.xRenderedStart = start
  view.xRenderedRows = rows
  view.xRenderedColumns = columns

proc terminalLineHeight(view: TerminalView): float32 =
  let
    fontName = view.fontName()
    fontSize = view.fontSize()
  if view.xCachedLineHeight <= 0.0'f32 or view.xCachedFontName != fontName or
      view.xCachedFontSize != fontSize:
    view.xCachedLineHeight = view.monoTextMetrics().lineHeight
    view.xCachedFontName = fontName
    view.xCachedFontSize = fontSize
  view.xCachedLineHeight

proc syncTerminalScreen(view: TerminalView) =
  if view.isNil or view.xSession.isNil:
    return
  let
    info = view.xSession.screenInfo()
    nextScrollbackCount = info.scrollbackCount
  if view.xScrollPosition > 0.0'f32 and nextScrollbackCount > view.xLastScrollbackCount:
    view.xScrollPosition = min(
      view.xScrollPosition + (nextScrollbackCount - view.xLastScrollbackCount).float32,
      nextScrollbackCount.float32,
    )
  view.xLastScrollbackCount = nextScrollbackCount
  view.xScrollPosition =
    clamp(view.xScrollPosition, 0.0'f32, nextScrollbackCount.float32)

  let
    start = max(info.totalLineCount - info.rows - view.viewportOffset(), 0)
    offset = view.viewportOffset().float32
    cursor = info.cursor
  view.synchronizeTerminalGrid(view.xSession, info, start)
  view.gridOffset =
    initPoint(0.0'f32, -(offset - view.xScrollPosition) * view.terminalLineHeight())
  if view.cursorRow() != cursor.position.row or
      view.cursorColumn() != cursor.position.column:
    view.setCursorPosition(cursor.position.row, cursor.position.column)
  view.cursorVisible =
    view.xScrollPosition == 0.0'f32 and cursor.visible and
    (not cursor.blinking or view.xBlinkVisible)
  view.cursorStyle =
    case cursor.shape
    of tcsBlock: mtcBlock
    of tcsBar: mtcVertical
    of tcsUnderline: mtcUnderline
  view.xLastGeneration = info.generation

proc synchronizeMetadata(view: TerminalView) =
  let info = view.xSession.screenInfo()
  if info.title != view.xLastTitle:
    view.xLastTitle = info.title
    emit view.terminalTitleDidChange(info.title)
  if info.currentDirectory != view.xLastDirectory:
    view.xLastDirectory = info.currentDirectory
    emit view.terminalDirectoryDidChange(info.currentDirectory)
  if info.bellCount != view.xLastBellCount:
    view.xLastBellCount = info.bellCount
    emit view.terminalBellDidRing()
  if view.xAllowsClipboardWrites and info.clipboardRequestPending:
    let text = view.xSession.takeClipboardRequest()
    discard generalPasteboard().setPlainText(text)

proc poll*(view: TerminalView): TerminexPollResult =
  ## Drain available PTY output and synchronize the rendered grid.
  if view.isNil or view.xSession.isNil:
    return
  result = view.xSession.poll()
  let generation = view.xSession.screenInfo().generation
  if result.bytesRead > 0 or result.screenChanged or view.xLastGeneration != generation:
    view.syncTerminalScreen()
  view.synchronizeMetadata()
  if result.processExited and not view.xExitNotified:
    view.xExitNotified = true
    emit view.terminalProcessDidExit(view.xSession.exitCode())
    view.stopTerminalPolling()

proc resizeToFit*(view: TerminalView) =
  if view.isNil or view.xSession.isNil:
    return
  let
    metrics = view.monoTextMetrics()
    bounds = view.bounds()
    availableWidth = max(bounds.w - view.padding() * 2.0'f32, metrics.cellWidth)
    availableHeight = max(bounds.h - view.padding() * 2.0'f32, metrics.lineHeight)
    columns = max(int(floor(availableWidth / metrics.cellWidth)), 1)
    rows = max(int(floor(availableHeight / metrics.lineHeight)), 1)
    info = view.xSession.screenInfo()
  if columns != info.columns or rows != info.rows:
    view.xSession.resize(columns, rows)
    view.xLastGeneration = high(uint64)
    view.syncTerminalScreen()

proc start*(view: TerminalView, options = initTerminalSpawnOptions()) =
  view.xSession.start(options)
  view.xExitNotified = false
  view.xLastInputError.setLen(0)
  view.startTerminalPolling()

proc close*(view: TerminalView) =
  if view.isNil:
    return
  view.stopTerminalPolling()
  if not view.xSession.isNil:
    view.xSession.close()

proc absolutePosition(view: TerminalView, row, column: int): TerminexPosition =
  let info = view.xSession.screenInfo()
  initTerminalPosition(
    clamp(view.viewportStart() + row, 0, info.totalLineCount - 1),
    clamp(column, 0, info.columns),
  )

func isWordCell(cell: TerminexCell): bool =
  if cell.text.len == 0:
    return false
  for rune in cell.text.runes:
    return rune.isAlpha() or rune.int in ord('0') .. ord('9') or rune == Rune('_')

proc selectWord(view: TerminalView, position: TerminexPosition) =
  let line = view.xSession.lineAtAbsolute(position.row)
  if line.len == 0:
    return
  var
    first = clamp(position.column, 0, line.high)
    last = first + 1
  let word = line[first].isWordCell()
  while first > 0 and line[first - 1].isWordCell() == word:
    dec first
  while last < line.len and line[last].isWordCell() == word:
    inc last
  view.xSelection = TerminalSelection(
    anchor: initTerminalPosition(position.row, first),
    extent: initTerminalPosition(position.row, last),
  )
  view.xHasSelection = true

proc selectLine(view: TerminalView, position: TerminexPosition) =
  let line = view.xSession.lineAtAbsolute(position.row)
  view.xSelection = TerminalSelection(
    anchor: initTerminalPosition(position.row, 0),
    extent: initTerminalPosition(position.row, line.len),
  )
  view.xHasSelection = true

proc handleLocalMouse(view: TerminalView, event: MonoTextRawEvent): bool =
  let mouse = event.mouseEvent
  case event.kind
  of mtreMouseDown:
    if mouse.button != mbPrimary:
      return false
    let owner = view.window()
    if owner of Window:
      discard Window(owner).makeFirstResponder(view, focusVisible = false)
    let position = view.absolutePosition(event.row, event.column)
    if kmCommand in mouse.modifiers:
      let line = view.xSession.lineAtAbsolute(position.row)
      if position.column in 0 ..< line.len and
          line[position.column].style.hyperlink.len > 0:
        emit view.terminalHyperlinkWasActivated(line[position.column].style.hyperlink)
        return true
    if mouse.clickCount >= 3:
      view.selectLine(position)
      view.xSelecting = false
    elif mouse.clickCount == 2:
      view.selectWord(position)
      view.xSelecting = false
    else:
      view.xSelection = TerminalSelection(
        anchor: position,
        extent: initTerminalPosition(position.row, position.column + 1),
      )
      view.xHasSelection = false
      view.xSelecting = true
    view.xLastGeneration = high(uint64)
    view.syncTerminalScreen()
    true
  of mtreMouseDragged:
    if mouse.button != mbPrimary or not view.xSelecting:
      return false
    let position = view.absolutePosition(event.row, event.column)
    view.xSelection.extent = initTerminalPosition(position.row, position.column + 1)
    view.xHasSelection = true
    view.xLastGeneration = high(uint64)
    view.syncTerminalScreen()
    true
  of mtreMouseUp:
    if mouse.button != mbPrimary:
      return false
    view.xSelecting = false
    true
  else:
    false

proc mouseTrackingAccepts(modes: TerminexModes, kind: MonoTextRawEventKind): bool =
  case kind
  of mtreMouseDown:
    terminput.mouseTrackingAccepts(modes, tmekPress)
  of mtreMouseDragged:
    terminput.mouseTrackingAccepts(modes, tmekMotion)
  of mtreMouseUp:
    terminput.mouseTrackingAccepts(modes, tmekRelease)
  else:
    false

proc handleTrackedMouse(view: TerminalView, event: MonoTextRawEvent): bool =
  if kmShift in event.mouseEvent.modifiers or
      not view.xSession.screenInfo().modes.mouseTrackingAccepts(event.kind):
    return false
  let input = view.xSession.encodeMouseInput(
    event.row,
    event.column,
    event.mouseEvent.button.toTerminexMouseButton(),
    release = event.kind == mtreMouseUp,
    motion = event.kind == mtreMouseDragged,
    modifiers = event.mouseEvent.modifiers,
  )
  view.sendInput(input)

proc scrollLocally(view: TerminalView, event: ScrollEvent): bool =
  if event.deltaY == 0.0'f32:
    return false
  let maxScroll = view.xSession.screenInfo().scrollbackCount.float32
  view.xScrollPosition = clamp(view.xScrollPosition + event.deltaY, 0.0'f32, maxScroll)
  view.syncTerminalScreen()
  true

func shouldScrollLocally(
    view: TerminalView, event: ScrollEvent, screenInfo: TerminexScreenInfo
): bool =
  ## Keep terminal history reachable after a TUI enables mouse reporting.
  ## Applications still receive wheel input when no local history exists.
  kmShift in event.modifiers or screenInfo.scrollbackCount > 0 or
    view.xScrollPosition > 0.0'f32

proc handleTerminalShortcut(view: TerminalView, event: KeyEvent): bool =
  if event.modifiers != terminalShortcutModifiers():
    return false
  case event.key
  of keyK:
    view.clearScrollback()
    true
  of keyA:
    view.sendLocalIfHandled(selectAll(), ActionArgs(sender: DynamicAgent(view)))
  of keyC:
    view.sendLocalIfHandled(copy(), ActionArgs(sender: DynamicAgent(view)))
  of keyX:
    view.sendLocalIfHandled(cut(), ActionArgs(sender: DynamicAgent(view)))
  of keyV:
    view.sendLocalIfHandled(paste(), ActionArgs(sender: DynamicAgent(view)))
  else:
    false

proc handleTerminalKeyDown(view: TerminalView, event: KeyEvent): bool =
  view.xSuppressOptionTextInput = false
  if view.handleTerminalShortcut(event):
    return true
  if event.key == keyL and event.modifiers == {kmControl}:
    view.clearScrollback()
    discard view.sendInput("\x0c")
    return true
  let input =
    terminalKeyInput(event, view.xSession.screenInfo().modes, view.xOptionAsMeta)
  if input.len == 0:
    return false
  if view.xOptionAsMeta and kmOption in event.modifiers and
      event.key.isPrintableTerminalKey():
    view.xSuppressOptionTextInput = true
  view.sendInput(input)

proc handleTerminalRawEvent(view: TerminalView, event: MonoTextRawEvent): bool =
  case event.kind
  of mtreMouseDown, mtreMouseDragged, mtreMouseUp:
    if view.handleTrackedMouse(event):
      return true
    view.handleLocalMouse(event)
  of mtreScrollWheel:
    if event.scrollEvent.deltaY == 0.0'f32:
      return false
    let screenInfo = view.xSession.screenInfo()
    if view.shouldScrollLocally(event.scrollEvent, screenInfo):
      return view.scrollLocally(event.scrollEvent)
    if screenInfo.modes.mouseTracking != tmtNone:
      let button = if event.scrollEvent.deltaY > 0.0'f32: tmbWheelUp else: tmbWheelDown
      return view.sendInput(
        view.xSession.encodeMouseInput(
          event.row,
          event.column,
          button,
          release = false,
          motion = false,
          modifiers = event.scrollEvent.modifiers,
        )
      )
    if screenInfo.alternateScreen and screenInfo.modes.alternateScroll and
        screenInfo.modes.mouseTracking == tmtNone:
      let key = if event.scrollEvent.deltaY > 0.0'f32: keyArrowUp else: keyArrowDown
      return view.sendInput(
        terminalKeyInput(
          KeyEvent(key: key, keyCode: key.ord), screenInfo.modes, view.xOptionAsMeta
        )
      )
    view.scrollLocally(event.scrollEvent)
  of mtreKeyDown:
    view.handleTerminalKeyDown(event.keyEvent)
  of mtreFlagsChanged:
    true

proc terminalTicked(view: TerminalView, delta: Duration) {.slot.} =
  if view.isNil:
    return
  discard view.poll()
  view.xBlinkElapsed = view.xBlinkElapsed + delta
  if view.xBlinkElapsed >= initDuration(milliseconds = 500):
    view.xBlinkElapsed = initDuration()
    view.xBlinkVisible = not view.xBlinkVisible
    view.xLastGeneration = high(uint64)
    view.syncTerminalScreen()

proc stopTerminalPolling(view: TerminalView) =
  if view.isNil or view.xPollingWindow.isNil:
    return
  let owner = view.xPollingWindow[]
  if not owner.isNil:
    owner.animationScheduler().disconnect(schedulerTicked, view, terminalTicked)
    if not view.xHeartbeat.isNil:
      discard owner.stopAnimation(view.xHeartbeat)
  view.xPollingWindow.clear()
  view.xHeartbeat = nil

proc startTerminalPolling(view: TerminalView) =
  if view.isNil or view.xSession.isNil or not view.xSession.running() or
      not view.xPollingWindow.isNil:
    return
  let responder = view.window()
  if not (responder of Window):
    return
  let owner = Window(responder)
  view.xPollingWindow[] = owner
  owner.animationScheduler().connect(schedulerTicked, view, terminalTicked)
  view.xHeartbeat = newAnimation(duration = initDuration(seconds = 1))
  view.xHeartbeat.loopCount = -1
  discard owner.startAnimation(view.xHeartbeat)

protocol TerminalViewKeyEquivalents of ResponderCommandDispatchProtocol:
  method performKeyEquivalent(view: TerminalView, event: KeyEvent): bool =
    view.handleTerminalKeyDown(event)

protocol TerminalViewInput of TextInputProtocol:
  method insertText(view: TerminalView, text: string) =
    if view.xSuppressOptionTextInput:
      view.xSuppressOptionTextInput = false
      return
    if text.isInsertableText():
      discard view.sendInput(text)

protocol TerminalViewEditingCommands of TextEditingCommandProtocol:
  method insertNewline(view: TerminalView, args: ActionArgs) =
    discard args
    discard view.sendInput("\r")

  method insertTab(view: TerminalView, args: ActionArgs) =
    discard args
    discard view.sendInput("\t")

  method insertBacktab(view: TerminalView, args: ActionArgs) =
    discard args
    discard view.sendInput("\x1b[Z")

  method deleteBackward(view: TerminalView, args: ActionArgs) =
    discard args
    discard view.sendInput("\x7f")

  method deleteForward(view: TerminalView, args: ActionArgs) =
    discard args
    discard view.sendInput("\x1b[3~")

  method copy(view: TerminalView, args: ActionArgs) =
    discard args
    let text = view.selectionText()
    if text.len > 0:
      discard generalPasteboard().setPlainText(text)

  method cut(view: TerminalView, args: ActionArgs) =
    discard args
    let text = view.selectionText()
    if text.len > 0:
      discard generalPasteboard().setPlainText(text)

  method paste(view: TerminalView, args: ActionArgs) =
    discard args
    discard view.pasteText(generalPasteboard().plainText())

  method selectAll(view: TerminalView, args: ActionArgs) =
    discard args
    let info = view.xSession.screenInfo()
    view.xSelection = TerminalSelection(
      anchor: initTerminalPosition(0, 0),
      extent: initTerminalPosition(info.totalLineCount - 1, info.columns),
    )
    view.xHasSelection = true
    view.xLastGeneration = high(uint64)
    view.syncTerminalScreen()

protocol TerminalViewFocus of ResponderProtocol:
  method didBecomeFirstResponder(view: TerminalView) =
    discard view.sendInput(
      terminput.terminalFocusInput(true, view.xSession.screenInfo().modes)
    )

  method didResignFirstResponder(view: TerminalView) =
    discard view.sendInput(
      terminput.terminalFocusInput(false, view.xSession.screenInfo().modes)
    )

protocol TerminalViewLayout of ViewLayoutProtocol:
  method layoutSubviews(view: TerminalView) =
    view.resizeToFit()

protocol TerminalViewLifecycle of ViewLifecycleProtocol:
  proc terminalViewWillMoveToWindow(
      view: TerminalView, window: Responder
  ) {.slotFor: viewWillMoveToWindow.} =
    discard window
    view.stopTerminalPolling()

  proc terminalViewDidMoveToWindow(
      view: TerminalView
  ) {.slotFor: viewDidMoveToWindow.} =
    view.startTerminalPolling()

proc initTerminalViewFields*(
    view: TerminalView,
    session: TerminexSession[TerminexCell, TerminexLine, RingBuffer[TerminexLine]] = nil,
    frame: Rect = AutoRect,
    palette = initTerminalPalette(),
) =
  initMonoTextViewFields(view, frame = frame)
  view.xSession =
    if session.isNil:
      newTerminalSession()
    else:
      session
  view.xPalette = palette
  view.xOptionAsMeta = true
  view.xLastGeneration = high(uint64)
  view.xLastScrollbackCount = view.xSession.screenInfo().scrollbackCount
  view.xBlinkVisible = true
  view.clipsToBounds = true
  view.focusRingType = frtNone
  view.padding = DefaultTerminalPadding
  view.fontName = DefaultMonoFontName
  view.fontSize = DefaultTerminalFontSize
  view.textColor = palette.foreground
  view.cursorColor = palette.cursor
  view.backgroundColor = palette.background
  view.rawEventPolicy = initMonoTextRawEventPolicy(
    forwardedEvents = AllMonoTextRawEvents,
    capturedEvents = AllMonoTextRawEvents - {mtreKeyDown},
  )
  let terminalView = view
  view.rawEventHandler = proc(event: MonoTextRawEvent): bool =
    terminalView.handleTerminalRawEvent(event)
  discard view.withProtocol(TerminalViewKeyEquivalents)
  discard view.withProtocol(TerminalViewInput)
  discard view.withProtocol(TerminalViewEditingCommands)
  discard view.withProtocol(TerminalViewFocus)
  discard view.withProtocol(TerminalViewLayout)
  view.observeProtocol(view, TerminalViewLifecycle)
  view.syncTerminalScreen()
  view.applyInitialFrame(frame)

proc newTerminalView*(
    session: TerminexSession[TerminexCell, TerminexLine, RingBuffer[TerminexLine]] = nil,
    frame: Rect = AutoRect,
    palette = initTerminalPalette(),
): TerminalView =
  result = TerminalView()
  result.initTerminalViewFields(session, frame, palette)

proc newTerminalView*(
    options: TerminexSpawnOptions,
    frame: Rect = AutoRect,
    palette = initTerminalPalette(),
): TerminalView =
  result = newTerminalView(frame = frame, palette = palette)
  result.start(options)
