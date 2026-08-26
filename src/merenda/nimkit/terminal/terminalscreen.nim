## Terminal screen state independent of rendering and process transport.

import std/[sequtils, strutils, unicode]

import pkg/unicodedb/[properties, widths]

const
  DefaultTerminalColumns* = 80
  DefaultTerminalRows* = 24
  DefaultTerminalScrollback* = 10_000

type
  TerminalColorKind* = enum
    tckDefault
    tckIndexed
    tckRgb

  TerminalColor* = object
    case kind*: TerminalColorKind
    of tckDefault:
      discard
    of tckIndexed:
      index*: uint8
    of tckRgb:
      red*, green*, blue*: uint8

  TerminalAttribute* = enum
    taBold
    taFaint
    taItalic
    taUnderline
    taDoubleUnderline
    taBlink
    taInverse
    taHidden
    taStrikethrough
    taOverline

  TerminalStyle* = object
    foreground*, background*, underlineColor*: TerminalColor
    attributes*: set[TerminalAttribute]
    hyperlink*: string

  TerminalCell* = object
    text*: string
    style*: TerminalStyle
    continuation*: bool

  TerminalLine* = seq[TerminalCell]

  TerminalPosition* = object
    row*, column*: int

  TerminalCursorShape* = enum
    tcsBlock
    tcsUnderline
    tcsBar

  TerminalMouseTracking* = enum
    tmtNone
    tmtX10
    tmtButton
    tmtAny

  TerminalMouseEncoding* = enum
    tmeX10
    tmeUtf8
    tmeSgr
    tmeUrxvt

  TerminalModes* = object
    insert*: bool
    origin*: bool
    autoWrap*: bool
    applicationCursorKeys*: bool
    applicationKeypad*: bool
    bracketedPaste*: bool
    focusReporting*: bool
    mouseTracking*: TerminalMouseTracking
    mouseEncoding*: TerminalMouseEncoding

  TerminalCursor* = object
    position*: TerminalPosition
    visible*: bool
    blinking*: bool
    shape*: TerminalCursorShape

  TerminalSavedState = object
    cursor: TerminalCursor
    style: TerminalStyle
    modes: TerminalModes
    wrapPending: bool

  TerminalScreen* = object
    columns*, rows*: int
    cells: seq[TerminalCell]
    scrollback: seq[TerminalLine]
    maxScrollback*: int
    cursor*: TerminalCursor
    style*: TerminalStyle
    modes*: TerminalModes
    scrollTop*, scrollBottom*: int
    title*, iconName*, currentDirectory*: string
    pendingReplies: seq[string]
    clipboardText*: string
    clipboardRequestPending*: bool
    alternateScreen*: bool
    generation*: uint64
    tabStops: seq[bool]
    saved: TerminalSavedState
    primaryCells: seq[TerminalCell]
    primaryCursor: TerminalCursor
    primarySaved: TerminalSavedState
    wrapPending: bool
    lastPrintedText: string

const ZeroWidthCategories = ctgMn + ctgMe + ctgCf

func defaultTerminalColor*(): TerminalColor =
  TerminalColor(kind: tckDefault)

func indexedTerminalColor*(index: uint8): TerminalColor =
  TerminalColor(kind: tckIndexed, index: index)

func rgbTerminalColor*(red, green, blue: uint8): TerminalColor =
  TerminalColor(kind: tckRgb, red: red, green: green, blue: blue)

func `==`*(left, right: TerminalColor): bool =
  if left.kind != right.kind:
    return false
  case left.kind
  of tckDefault:
    true
  of tckIndexed:
    left.index == right.index
  of tckRgb:
    left.red == right.red and left.green == right.green and left.blue == right.blue

func initTerminalStyle*(): TerminalStyle =
  TerminalStyle(
    foreground: defaultTerminalColor(),
    background: defaultTerminalColor(),
    underlineColor: defaultTerminalColor(),
  )

func initTerminalCell*(text = "", style = initTerminalStyle()): TerminalCell =
  TerminalCell(text: text, style: style)

func initTerminalPosition*(row, column: int): TerminalPosition =
  TerminalPosition(row: row, column: column)

func initTerminalModes*(): TerminalModes =
  TerminalModes(autoWrap: true, mouseEncoding: tmeX10)

func initTerminalCursor*(): TerminalCursor =
  TerminalCursor(visible: true, blinking: true, shape: tcsBlock)

func cellIndex(screen: TerminalScreen, row, column: int): int =
  row * screen.columns + column

func contains*(screen: TerminalScreen, position: TerminalPosition): bool =
  position.row in 0 ..< screen.rows and position.column in 0 ..< screen.columns

func cellAt*(screen: TerminalScreen, row, column: int): lent TerminalCell =
  screen.cells[screen.cellIndex(row, column)]

func lineAt*(screen: TerminalScreen, row: int): TerminalLine =
  result = newSeq[TerminalCell](screen.columns)
  for column in 0 ..< screen.columns:
    result[column] = screen.cellAt(row, column)

func scrollbackLines*(screen: TerminalScreen): seq[TerminalLine] =
  screen.scrollback

func scrollbackCount*(screen: TerminalScreen): int =
  screen.scrollback.len

func pendingReplies*(screen: TerminalScreen): seq[string] =
  screen.pendingReplies

proc takePendingReplies*(screen: var TerminalScreen): seq[string] =
  result = move(screen.pendingReplies)
  screen.pendingReplies = @[]

proc markChanged(screen: var TerminalScreen) =
  inc screen.generation

proc resetTabStops(screen: var TerminalScreen) =
  screen.tabStops = newSeq[bool](screen.columns)
  for column in 0 ..< screen.columns:
    screen.tabStops[column] = column > 0 and column mod 8 == 0

proc initTerminalScreen*(
    columns = DefaultTerminalColumns,
    rows = DefaultTerminalRows,
    maxScrollback = DefaultTerminalScrollback,
): TerminalScreen =
  result.columns = max(columns, 1)
  result.rows = max(rows, 1)
  result.cells = newSeqWith(result.columns * result.rows, initTerminalCell())
  result.maxScrollback = max(maxScrollback, 0)
  result.cursor = initTerminalCursor()
  result.style = initTerminalStyle()
  result.modes = initTerminalModes()
  result.scrollBottom = result.rows - 1
  result.resetTabStops()

proc setCell(screen: var TerminalScreen, row, column: int, cell: TerminalCell) =
  if screen.contains(initTerminalPosition(row, column)):
    screen.cells[screen.cellIndex(row, column)] = cell

proc clearWideCell(screen: var TerminalScreen, row, column: int) =
  if not screen.contains(initTerminalPosition(row, column)):
    return
  let cell = screen.cellAt(row, column)
  if cell.continuation and column > 0:
    screen.setCell(row, column - 1, initTerminalCell())
    screen.setCell(row, column, initTerminalCell())
  elif column + 1 < screen.columns and screen.cellAt(row, column + 1).continuation:
    screen.setCell(row, column, initTerminalCell())
    screen.setCell(row, column + 1, initTerminalCell())

proc clearRange(screen: var TerminalScreen, row, firstColumn, lastColumn: int) =
  if row notin 0 ..< screen.rows:
    return
  let
    first = clamp(firstColumn, 0, screen.columns - 1)
    last = clamp(lastColumn, 0, screen.columns - 1)
  if first > last:
    return
  screen.clearWideCell(row, first)
  screen.clearWideCell(row, last)
  for column in first .. last:
    screen.setCell(row, column, initTerminalCell(style = screen.style))

proc clearLine(screen: var TerminalScreen, row: int) =
  screen.clearRange(row, 0, screen.columns - 1)

proc appendScrollback(screen: var TerminalScreen, line: sink TerminalLine) =
  if screen.alternateScreen or screen.maxScrollback == 0:
    return
  screen.scrollback.add line
  if screen.scrollback.len > screen.maxScrollback:
    screen.scrollback.delete(0 .. screen.scrollback.len - screen.maxScrollback - 1)

proc replaceLine(screen: var TerminalScreen, row: int, line: TerminalLine) =
  for column in 0 ..< screen.columns:
    screen.setCell(
      row,
      column,
      if column < line.len:
        line[column]
      else:
        initTerminalCell(),
    )

proc scrollUp*(screen: var TerminalScreen, count = 1) =
  let amount = min(max(count, 0), screen.scrollBottom - screen.scrollTop + 1)
  for _ in 0 ..< amount:
    if screen.scrollTop == 0 and screen.scrollBottom == screen.rows - 1:
      screen.appendScrollback(screen.lineAt(screen.scrollTop))
    for row in screen.scrollTop ..< screen.scrollBottom:
      screen.replaceLine(row, screen.lineAt(row + 1))
    screen.clearLine(screen.scrollBottom)
  if amount > 0:
    screen.markChanged()

proc scrollDown*(screen: var TerminalScreen, count = 1) =
  let amount = min(max(count, 0), screen.scrollBottom - screen.scrollTop + 1)
  for _ in 0 ..< amount:
    for row in countdown(screen.scrollBottom, screen.scrollTop + 1):
      screen.replaceLine(row, screen.lineAt(row - 1))
    screen.clearLine(screen.scrollTop)
  if amount > 0:
    screen.markChanged()

proc lineFeed*(screen: var TerminalScreen) =
  screen.wrapPending = false
  if screen.cursor.position.row == screen.scrollBottom:
    screen.scrollUp()
  elif screen.cursor.position.row < screen.rows - 1:
    inc screen.cursor.position.row
    screen.markChanged()

proc reverseIndex*(screen: var TerminalScreen) =
  screen.wrapPending = false
  if screen.cursor.position.row == screen.scrollTop:
    screen.scrollDown()
  elif screen.cursor.position.row > 0:
    dec screen.cursor.position.row
    screen.markChanged()

proc carriageReturn*(screen: var TerminalScreen) =
  screen.cursor.position.column = 0
  screen.wrapPending = false
  screen.markChanged()

proc nextLine*(screen: var TerminalScreen) =
  screen.lineFeed()
  screen.carriageReturn()

proc backspace*(screen: var TerminalScreen) =
  screen.wrapPending = false
  if screen.cursor.position.column > 0:
    dec screen.cursor.position.column
    screen.markChanged()

proc horizontalTab*(screen: var TerminalScreen) =
  screen.wrapPending = false
  for column in screen.cursor.position.column + 1 ..< screen.columns:
    if screen.tabStops[column]:
      screen.cursor.position.column = column
      screen.markChanged()
      return
  screen.cursor.position.column = screen.columns - 1
  screen.markChanged()

proc setTabStop*(screen: var TerminalScreen) =
  screen.tabStops[screen.cursor.position.column] = true

proc clearTabStop*(screen: var TerminalScreen, all = false) =
  if all:
    for tabStop in screen.tabStops.mitems:
      tabStop = false
  else:
    screen.tabStops[screen.cursor.position.column] = false

proc terminalRuneWidth*(rune: Rune): int =
  let value = rune.int
  if value < 0x20 or value in 0x7f .. 0x9f:
    return 0
  if rune.unicodeCategory in ZeroWidthCategories:
    return 0
  case rune.unicodeWidth
  of uwdtWide, uwdtFull: 2
  else: 1

proc insertCells*(screen: var TerminalScreen, count = 1) =
  let
    column = screen.cursor.position.column
    amount = min(max(count, 0), screen.columns - column)
  if amount == 0:
    return
  screen.clearWideCell(screen.cursor.position.row, column)
  screen.clearWideCell(screen.cursor.position.row, screen.columns - amount)
  for target in countdown(screen.columns - 1, column + amount):
    screen.setCell(
      screen.cursor.position.row,
      target,
      screen.cellAt(screen.cursor.position.row, target - amount),
    )
  screen.clearRange(screen.cursor.position.row, column, column + amount - 1)
  screen.markChanged()

proc deleteCells*(screen: var TerminalScreen, count = 1) =
  let
    column = screen.cursor.position.column
    amount = min(max(count, 0), screen.columns - column)
  if amount == 0:
    return
  screen.clearWideCell(screen.cursor.position.row, column)
  screen.clearWideCell(screen.cursor.position.row, column + amount - 1)
  for target in column ..< screen.columns - amount:
    screen.setCell(
      screen.cursor.position.row,
      target,
      screen.cellAt(screen.cursor.position.row, target + amount),
    )
  screen.clearRange(
    screen.cursor.position.row, screen.columns - amount, screen.columns - 1
  )
  screen.markChanged()

proc eraseCells*(screen: var TerminalScreen, count = 1) =
  let last = min(screen.cursor.position.column + max(count, 1) - 1, screen.columns - 1)
  screen.clearRange(screen.cursor.position.row, screen.cursor.position.column, last)
  screen.markChanged()

proc insertLines*(screen: var TerminalScreen, count = 1) =
  let row = screen.cursor.position.row
  if row notin screen.scrollTop .. screen.scrollBottom:
    return
  let amount = min(max(count, 1), screen.scrollBottom - row + 1)
  for target in countdown(screen.scrollBottom, row + amount):
    screen.replaceLine(target, screen.lineAt(target - amount))
  for target in row ..< row + amount:
    screen.clearLine(target)
  screen.markChanged()

proc deleteLines*(screen: var TerminalScreen, count = 1) =
  let row = screen.cursor.position.row
  if row notin screen.scrollTop .. screen.scrollBottom:
    return
  let amount = min(max(count, 1), screen.scrollBottom - row + 1)
  for target in row .. screen.scrollBottom - amount:
    screen.replaceLine(target, screen.lineAt(target + amount))
  for target in screen.scrollBottom - amount + 1 .. screen.scrollBottom:
    screen.clearLine(target)
  screen.markChanged()

proc attachCombiningRune(screen: var TerminalScreen, text: string): bool =
  var
    row = screen.cursor.position.row
    column = screen.cursor.position.column - 1
  if screen.wrapPending:
    column = screen.columns - 1
  if column < 0 and row > 0:
    dec row
    column = screen.columns - 1
  if row < 0 or column < 0:
    return false
  if screen.cellAt(row, column).continuation and column > 0:
    dec column
  let index = screen.cellIndex(row, column)
  if screen.cells[index].text.len == 0:
    return false
  screen.cells[index].text.add text
  screen.markChanged()
  true

proc writeText*(screen: var TerminalScreen, text: string) =
  let runes = text.toRunes()
  if runes.len == 0:
    return
  let width = terminalRuneWidth(runes[0])
  if width == 0:
    discard screen.attachCombiningRune(text)
    return
  if screen.wrapPending and screen.modes.autoWrap:
    screen.cursor.position.column = 0
    screen.lineFeed()
  screen.wrapPending = false
  if width == 2 and screen.cursor.position.column == screen.columns - 1:
    if screen.modes.autoWrap:
      screen.cursor.position.column = 0
      screen.lineFeed()
    else:
      return
  if screen.modes.insert:
    screen.insertCells(width)
  let
    row = screen.cursor.position.row
    column = screen.cursor.position.column
  screen.clearWideCell(row, column)
  screen.setCell(row, column, initTerminalCell(text, screen.style))
  if width == 2 and column + 1 < screen.columns:
    screen.clearWideCell(row, column + 1)
    screen.setCell(
      row, column + 1, TerminalCell(style: screen.style, continuation: true)
    )
  screen.lastPrintedText = text
  if column + width >= screen.columns:
    screen.cursor.position.column = screen.columns - 1
    screen.wrapPending = screen.modes.autoWrap
  else:
    screen.cursor.position.column = column + width
  screen.markChanged()

proc repeatLastText*(screen: var TerminalScreen, count = 1) =
  if screen.lastPrintedText.len > 0:
    for _ in 0 ..< max(count, 1):
      screen.writeText(screen.lastPrintedText)

proc moveCursor*(screen: var TerminalScreen, row, column: int) =
  let rowMin = if screen.modes.origin: screen.scrollTop else: 0
  let rowMax =
    if screen.modes.origin:
      screen.scrollBottom
    else:
      screen.rows - 1
  screen.cursor.position = initTerminalPosition(
    clamp(row + rowMin, rowMin, rowMax), clamp(column, 0, screen.columns - 1)
  )
  screen.wrapPending = false
  screen.markChanged()

proc moveCursorRelative*(screen: var TerminalScreen, rows, columns: int) =
  let
    rowMin = if screen.modes.origin: screen.scrollTop else: 0
    rowMax =
      if screen.modes.origin:
        screen.scrollBottom
      else:
        screen.rows - 1
  screen.cursor.position.row = clamp(screen.cursor.position.row + rows, rowMin, rowMax)
  screen.cursor.position.column =
    clamp(screen.cursor.position.column + columns, 0, screen.columns - 1)
  screen.wrapPending = false
  screen.markChanged()

proc eraseInLine*(screen: var TerminalScreen, mode: int) =
  case mode
  of 0:
    screen.clearRange(
      screen.cursor.position.row, screen.cursor.position.column, screen.columns - 1
    )
  of 1:
    screen.clearRange(screen.cursor.position.row, 0, screen.cursor.position.column)
  of 2:
    screen.clearLine(screen.cursor.position.row)
  else:
    return
  screen.markChanged()

proc eraseInDisplay*(screen: var TerminalScreen, mode: int) =
  case mode
  of 0:
    screen.eraseInLine(0)
    for row in screen.cursor.position.row + 1 ..< screen.rows:
      screen.clearLine(row)
  of 1:
    for row in 0 ..< screen.cursor.position.row:
      screen.clearLine(row)
    screen.eraseInLine(1)
  of 2:
    for row in 0 ..< screen.rows:
      screen.clearLine(row)
  of 3:
    screen.scrollback.setLen(0)
  else:
    return
  screen.markChanged()

proc setScrollRegion*(screen: var TerminalScreen, top, bottom: int) =
  if top >= 0 and top < bottom and bottom < screen.rows:
    screen.scrollTop = top
    screen.scrollBottom = bottom
  else:
    screen.scrollTop = 0
    screen.scrollBottom = screen.rows - 1
  screen.moveCursor(0, 0)

proc saveCursor*(screen: var TerminalScreen) =
  screen.saved = TerminalSavedState(
    cursor: screen.cursor,
    style: screen.style,
    modes: screen.modes,
    wrapPending: screen.wrapPending,
  )

proc restoreCursor*(screen: var TerminalScreen) =
  screen.cursor = screen.saved.cursor
  screen.style = screen.saved.style
  screen.modes = screen.saved.modes
  screen.wrapPending = screen.saved.wrapPending
  screen.cursor.position.row = clamp(screen.cursor.position.row, 0, screen.rows - 1)
  screen.cursor.position.column =
    clamp(screen.cursor.position.column, 0, screen.columns - 1)
  screen.markChanged()

proc useAlternateScreen*(screen: var TerminalScreen, enabled, saveRestore: bool) =
  if enabled == screen.alternateScreen:
    return
  if enabled:
    if saveRestore:
      screen.saveCursor()
    screen.primaryCells = move(screen.cells)
    screen.primaryCursor = screen.cursor
    screen.primarySaved = screen.saved
    screen.cells = newSeqWith(screen.columns * screen.rows, initTerminalCell())
    screen.cursor.position = initTerminalPosition(0, 0)
    screen.wrapPending = false
    screen.alternateScreen = true
  else:
    screen.cells = move(screen.primaryCells)
    screen.primaryCells = @[]
    screen.alternateScreen = false
    if saveRestore:
      screen.cursor = screen.primaryCursor
      screen.saved = screen.primarySaved
    screen.wrapPending = false
  screen.scrollTop = 0
  screen.scrollBottom = screen.rows - 1
  screen.markChanged()

proc queueReply*(screen: var TerminalScreen, reply: sink string) =
  screen.pendingReplies.add reply

proc reset*(screen: var TerminalScreen) =
  let
    columns = screen.columns
    rows = screen.rows
    maxScrollback = screen.maxScrollback
    generation = screen.generation
  screen = initTerminalScreen(columns, rows, maxScrollback)
  screen.generation = generation + 1

proc resizeLine(line: TerminalLine, columns: int): TerminalLine =
  result = newSeqWith(columns, initTerminalCell())
  for column in 0 ..< min(columns, line.len):
    result[column] = line[column]
  if columns > 0 and columns < line.len and line[columns].continuation:
    result[columns - 1] = initTerminalCell()

proc resizeCells(
    cells: seq[TerminalCell], oldColumns, oldRows, columns, rows: int
): seq[TerminalCell] =
  result = newSeqWith(columns * rows, initTerminalCell())
  for row in 0 ..< min(oldRows, rows):
    var oldLine = newSeq[TerminalCell](oldColumns)
    for column in 0 ..< oldColumns:
      oldLine[column] = cells[row * oldColumns + column]
    let line = oldLine.resizeLine(columns)
    for column in 0 ..< columns:
      result[row * columns + column] = line[column]

proc resize*(screen: var TerminalScreen, columns, rows: int) =
  let
    nextColumns = max(columns, 1)
    nextRows = max(rows, 1)
  if nextColumns == screen.columns and nextRows == screen.rows:
    return
  screen.cells =
    resizeCells(screen.cells, screen.columns, screen.rows, nextColumns, nextRows)
  if screen.primaryCells.len > 0:
    screen.primaryCells = resizeCells(
      screen.primaryCells, screen.columns, screen.rows, nextColumns, nextRows
    )
  screen.columns = nextColumns
  screen.rows = nextRows
  screen.cursor.position.row = clamp(screen.cursor.position.row, 0, nextRows - 1)
  screen.cursor.position.column =
    clamp(screen.cursor.position.column, 0, nextColumns - 1)
  screen.scrollTop = 0
  screen.scrollBottom = nextRows - 1
  screen.resetTabStops()
  screen.wrapPending = false
  screen.markChanged()

func lineText(line: TerminalLine): string =
  for cell in line:
    if not cell.continuation:
      if cell.text.len > 0:
        result.add cell.text
      else:
        result.add ' '
  result = result.strip(leading = false, trailing = true, chars = {' '})

func plainText*(screen: TerminalScreen, includeScrollback = true): string =
  var lines: seq[string]
  if includeScrollback and not screen.alternateScreen:
    for line in screen.scrollback:
      lines.add line.lineText()
  var lastContentRow = -1
  for row in 0 ..< screen.rows:
    let text = screen.lineAt(row).lineText()
    lines.add text
    if text.len > 0:
      lastContentRow = lines.high
  if lastContentRow < 0:
    if screen.scrollback.len == 0 or not includeScrollback:
      return ""
    lastContentRow = screen.scrollback.high
  lines.setLen(lastContentRow + 1)
  lines.join("\n")
