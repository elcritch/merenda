import std/[math, unicode]

import figdraw/common/fonttypes
import figdraw/common/fontutils
import figdraw/common/typefaces
import pkg/pixie/fonts
import pkg/vmath

import ../accessibility/accessibilityprotocols
import ../app/windows
import ../drawing
import ../foundation/events
import ../foundation/selectors
import ../foundation/types as nimkitTypes
import ../themes
import ../view/views

export views

const
  DefaultMonoFontName* = "HackNerdFont-Regular.ttf"
  DefaultMonoTabWidth* = 2
  DefaultMonoPadding* = 6.0'f32

type
  MonoTextCell* = object
    text*: string
    foregroundColor*: nimkitTypes.Color
    backgroundColor*: nimkitTypes.Color
    hasForegroundColor*: bool
    hasBackgroundColor*: bool

  MonoTextMetrics* = object
    cellWidth*: float32
    lineHeight*: float32

  MonoTextCursorStyle* = enum
    mtcBlock
    mtcVertical
    mtcUnderline

  MonoTextRawEventKind* = enum
    mtreMouseDown
    mtreMouseDragged
    mtreMouseUp
    mtreScrollWheel
    mtreKeyDown
    mtreFlagsChanged

  MonoTextRawEventKinds* = set[MonoTextRawEventKind]

  MonoTextRawEvent* = object
    row*: int
    column*: int
    input*: string
    case kind*: MonoTextRawEventKind
    of mtreMouseDown, mtreMouseDragged, mtreMouseUp:
      mouseEvent*: MouseEvent
    of mtreScrollWheel:
      scrollEvent*: ScrollEvent
    of mtreKeyDown, mtreFlagsChanged:
      keyEvent*: KeyEvent

  MonoTextRawEventHandler* = proc(event: MonoTextRawEvent): bool {.closure.}

  MonoTextRawEventPolicy* = object
    forwardedEvents*: MonoTextRawEventKinds
    capturedEvents*: MonoTextRawEventKinds

  MonoTextLine = object
    cells: seq[MonoTextCell]

  MonoTextView* = ref object of View
    xLines: seq[MonoTextLine]
    xMaxColumns: int
    xEditable: bool
    xForwardedRawEvents: MonoTextRawEventKinds
    xCapturedRawEvents: MonoTextRawEventKinds
    xRawEventHandler: MonoTextRawEventHandler
    xSuppressNextTextInput: bool
    xCursorRow: int
    xCursorColumn: int
    xCursorVisible: bool
    xCursorStyle: MonoTextCursorStyle
    xTabWidth: int
    xPadding: float32
    xFontName: string
    xFontSize: float32
    xTextColor: nimkitTypes.Color
    xCursorColor: nimkitTypes.Color
    xTypefaceId: TypefaceId
    xFontReady: bool
    xCachedFontName: string

const AllMonoTextRawEvents* = {
  mtreMouseDown, mtreMouseDragged, mtreMouseUp, mtreScrollWheel, mtreKeyDown,
  mtreFlagsChanged,
}

var monoTypefaceId {.threadvar.}: TypefaceId
var monoTypefaceKey {.threadvar.}: string
var monoTypefaceReady {.threadvar.}: bool

func initMonoTextRawEventPolicy*(
    forwardedEvents: MonoTextRawEventKinds = AllMonoTextRawEvents,
    capturedEvents: MonoTextRawEventKinds = {},
): MonoTextRawEventPolicy =
  MonoTextRawEventPolicy(
    forwardedEvents: forwardedEvents + capturedEvents, capturedEvents: capturedEvents
  )

func initMonoTextCell*(
    text = " ",
    foregroundColor = initColor(0.0, 0.0, 0.0, 1.0),
    backgroundColor = initColor(0.0, 0.0, 0.0, 0.0),
    hasForegroundColor = false,
    hasBackgroundColor = false,
): MonoTextCell =
  MonoTextCell(
    text: if text.len == 0: " " else: text,
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    hasForegroundColor: hasForegroundColor,
    hasBackgroundColor: hasBackgroundColor,
  )

func initMonoTextCell*(
    rune: Rune,
    foregroundColor = initColor(0.0, 0.0, 0.0, 1.0),
    backgroundColor = initColor(0.0, 0.0, 0.0, 0.0),
    hasForegroundColor = false,
    hasBackgroundColor = false,
): MonoTextCell =
  initMonoTextCell(
    $rune, foregroundColor, backgroundColor, hasForegroundColor, hasBackgroundColor
  )

func styledMonoTextCell*(
    text: string,
    foregroundColor: nimkitTypes.Color,
    backgroundColor = initColor(0.0, 0.0, 0.0, 0.0),
    hasBackgroundColor = false,
): MonoTextCell =
  initMonoTextCell(
    text,
    foregroundColor = foregroundColor,
    backgroundColor = backgroundColor,
    hasForegroundColor = true,
    hasBackgroundColor = hasBackgroundColor,
  )

func foreground(cell: MonoTextCell, fallback: nimkitTypes.Color): nimkitTypes.Color =
  if cell.hasForegroundColor: cell.foregroundColor else: fallback

func sameRunStyle(
    left, right: MonoTextCell, defaultTextColor: nimkitTypes.Color
): bool =
  left.foreground(defaultTextColor) == right.foreground(defaultTextColor) and
    left.hasBackgroundColor == right.hasBackgroundColor and
    (not left.hasBackgroundColor or left.backgroundColor == right.backgroundColor)

proc firstRune(cell: MonoTextCell): Rune =
  for rune in cell.text.runes:
    return rune
  Rune(' ')

proc splitMonoLines(value: string): seq[string] =
  var start = 0
  for index, ch in value:
    if ch == '\n':
      var stop = index
      if stop > start and value[stop - 1] == '\r':
        dec stop
      result.add value[start ..< stop]
      start = index + 1
  if start <= value.len:
    var tail = value[start ..< value.len]
    if tail.len > 0 and tail[^1] == '\r':
      tail.setLen(tail.len - 1)
    result.add tail
  if result.len == 0:
    result.add ""

proc textToCells(text: string): seq[MonoTextCell] =
  for rune in text.runes:
    result.add initMonoTextCell(rune)

proc lineToString(line: MonoTextLine): string =
  for cell in line.cells:
    result.add cell.text

proc recomputeMaxColumns(view: MonoTextView) =
  view.xMaxColumns = 0
  for line in view.xLines:
    view.xMaxColumns = max(view.xMaxColumns, line.cells.len)

proc invalidateTextGeometry(view: MonoTextView) =
  if view.isNil:
    return
  view.recomputeMaxColumns()
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc ensureLine(view: MonoTextView, row: int) =
  if view.isNil or row < 0:
    return
  while view.xLines.len <= row:
    view.xLines.add MonoTextLine()

proc ensureColumn(view: MonoTextView, row, column: int) =
  if view.isNil or row < 0 or column < 0:
    return
  view.ensureLine(row)
  while view.xLines[row].cells.len <= column:
    view.xLines[row].cells.add initMonoTextCell()

func clampIndex(value, low, high: int): int =
  min(max(value, low), high)

proc clampCursor(view: MonoTextView) =
  if view.xLines.len == 0:
    view.xLines.add MonoTextLine()
  view.xCursorRow = view.xCursorRow.clampIndex(0, view.xLines.high)
  view.xCursorColumn =
    view.xCursorColumn.clampIndex(0, view.xLines[view.xCursorRow].cells.len)

proc textLength(view: MonoTextView): int =
  if view.isNil:
    return 0
  for row, line in view.xLines:
    result += line.lineToString().runeLen
    if row + 1 < view.xLines.len:
      inc result

proc textIndexForRowColumn(view: MonoTextView, row, column: int): int =
  if view.isNil or view.xLines.len == 0:
    return 0
  let targetRow = row.clampIndex(0, view.xLines.high)
  for currentRow in 0 ..< targetRow:
    result += view.xLines[currentRow].lineToString().runeLen
    if currentRow + 1 < view.xLines.len:
      inc result
  let targetColumn = column.clampIndex(0, view.xLines[targetRow].cells.len)
  for currentColumn in 0 ..< targetColumn:
    result += view.xLines[targetRow].cells[currentColumn].text.runeLen

proc rowColumnForTextIndex(view: MonoTextView, index: int): tuple[row, column: int] =
  if view.isNil or view.xLines.len == 0:
    return (row: 0, column: 0)
  var remaining = index.clampIndex(0, view.textLength())
  for row, line in view.xLines:
    let lineLength = line.lineToString().runeLen
    if remaining <= lineLength:
      var consumed = 0
      for column, cell in line.cells:
        let cellLength = max(cell.text.runeLen, 1)
        if remaining < consumed + cellLength:
          return (row: row, column: column)
        consumed += cellLength
      return (row: row, column: line.cells.len)
    remaining -= lineLength
    if row + 1 < view.xLines.len:
      if remaining == 0:
        return (row: row, column: line.cells.len)
      dec remaining
  (row: view.xLines.high, column: view.xLines[^1].cells.len)

proc cursorTextIndex(view: MonoTextView): int =
  if view.isNil:
    return 0
  view.textIndexForRowColumn(view.xCursorRow, view.xCursorColumn)

proc postCursorSelectionChanged(view: MonoTextView, before: int) =
  if not view.isNil and view.cursorTextIndex() != before:
    view.postAccessibilityNotification(anSelectionChanged)

proc monoFont(view: MonoTextView): FigFont =
  if view.isNil:
    if not monoTypefaceReady or monoTypefaceKey != DefaultMonoFontName:
      monoTypefaceId =
        loadTypeface(DefaultMonoFontName, [defaultFontName(), "Ubuntu.ttf"])
      monoTypefaceKey = DefaultMonoFontName
      monoTypefaceReady = true
    return monoTypefaceId.fontWithSize(defaultFontSize())
  if not view.xFontReady or view.xCachedFontName != view.xFontName:
    if not monoTypefaceReady or monoTypefaceKey != view.xFontName:
      monoTypefaceId = loadTypeface(view.xFontName, [defaultFontName(), "Ubuntu.ttf"])
      monoTypefaceKey = view.xFontName
      monoTypefaceReady = true
    view.xTypefaceId = monoTypefaceId
    view.xCachedFontName = view.xFontName
    view.xFontReady = true
  view.xTypefaceId.fontWithSize(view.xFontSize)

proc monoTextMetrics*(view: MonoTextView): MonoTextMetrics =
  let
    font = view.monoFont()
    (_, px) = font.convertFont()
    lineHeight =
      if px.lineHeight >= 0.0'f32:
        px.lineHeight
      else:
        px.defaultLineHeight()
    advance = px.typeface.getAdvance(Rune('M')) * px.scale
  MonoTextMetrics(
    cellWidth: max(advance, 1.0'f32), lineHeight: max(lineHeight, font.size)
  )

proc monoTextStyleContext(view: MonoTextView): StyleContext =
  if view.isNil:
    return controlStyle(srMonoTextView)
  controlStyle(
    srMonoTextView,
    view.widgetStateSet(),
    id = view.styleId,
    classes = view.styleClasses,
  )

proc monoTextStyle(view: MonoTextView): MonoTextStyle =
  if view.isNil:
    return initAppearance().resolveMonoTextStyle(controlStyle(srMonoTextView))
  view.effectiveAppearance().resolveMonoTextStyle(view.monoTextStyleContext())

proc monoTextInsets(view: MonoTextView, style: MonoTextStyle): EdgeInsets =
  if not view.isNil and view.xPadding >= 0.0'f32:
    return insets(view.xPadding)
  style.text.insets

proc resolvedTextColor(view: MonoTextView, style: MonoTextStyle): nimkitTypes.Color =
  if not view.isNil and view.xTextColor.a > 0.0'f32:
    view.xTextColor
  else:
    style.text.color

proc resolvedCursorColor(view: MonoTextView, style: MonoTextStyle): nimkitTypes.Color =
  if not view.isNil and view.xCursorColor.a > 0.0'f32:
    view.xCursorColor
  else:
    style.cursorColor

proc rowColumnAtPoint*(
    view: MonoTextView, point: nimkitTypes.Point
): tuple[row, column: int] =
  let
    metrics = view.monoTextMetrics()
    style = view.monoTextStyle()
    textInsets = view.monoTextInsets(style)
  result.row = int(floor(max(point.y - textInsets.top, 0.0'f32) / metrics.lineHeight))
  result.column =
    int(floor(max(point.x - textInsets.left, 0.0'f32) / metrics.cellWidth))
  if view.xLines.len > 0:
    result.row = result.row.clampIndex(0, view.xLines.high)
    result.column = result.column.clampIndex(0, view.xLines[result.row].cells.len)
  else:
    result.row = 0
    result.column = 0

proc stringValue*(view: MonoTextView): string =
  if view.isNil:
    return ""
  for index, line in view.xLines:
    if index > 0:
      result.add '\n'
    result.add line.lineToString()

proc `stringValue=`*(view: MonoTextView, value: string) =
  if view.isNil:
    return
  if view.stringValue() == value:
    return
  let previousCursor = view.cursorTextIndex()
  view.xLines.setLen(0)
  for lineText in value.splitMonoLines():
    view.xLines.add MonoTextLine(cells: lineText.textToCells())
  if view.xLines.len == 0:
    view.xLines.add MonoTextLine()
  view.xCursorRow = 0
  view.xCursorColumn = 0
  view.clampCursor()
  view.invalidateTextGeometry()
  view.postAccessibilityNotification(anValueChanged)
  view.postCursorSelectionChanged(previousCursor)

proc lines*(view: MonoTextView): seq[string] =
  if view.isNil:
    return
  for line in view.xLines:
    result.add line.lineToString()

proc setLines*(view: MonoTextView, lines: openArray[string]) =
  if view.isNil:
    return
  let previousValue = view.stringValue()
  let previousCursor = view.cursorTextIndex()
  view.xLines.setLen(0)
  for line in lines:
    view.xLines.add MonoTextLine(cells: line.textToCells())
  if view.xLines.len == 0:
    view.xLines.add MonoTextLine()
  view.clampCursor()
  view.invalidateTextGeometry()
  if view.stringValue() != previousValue:
    view.postAccessibilityNotification(anValueChanged)
  view.postCursorSelectionChanged(previousCursor)

proc lineCount*(view: MonoTextView): int =
  if view.isNil: 0 else: view.xLines.len

proc maxColumnCount*(view: MonoTextView): int =
  if view.isNil: 0 else: view.xMaxColumns

proc columnCount*(view: MonoTextView, row: int): int =
  if view.isNil or row < 0 or row >= view.xLines.len:
    0
  else:
    view.xLines[row].cells.len

proc cellAt*(view: MonoTextView, row, column: int): MonoTextCell =
  if view.isNil or row < 0 or row >= view.xLines.len or column < 0 or
      column >= view.xLines[row].cells.len:
    initMonoTextCell()
  else:
    view.xLines[row].cells[column]

proc setCell*(view: MonoTextView, row, column: int, cell: MonoTextCell) =
  if view.isNil or row < 0 or column < 0:
    return
  let previousCursor = view.cursorTextIndex()
  view.ensureColumn(row, column)
  if view.xLines[row].cells[column] == cell:
    return
  view.xLines[row].cells[column] = cell
  view.clampCursor()
  view.invalidateTextGeometry()
  view.postAccessibilityNotification(anValueChanged)
  view.postCursorSelectionChanged(previousCursor)

proc setGridSize*(view: MonoTextView, rows, columns: int) =
  if view.isNil:
    return
  let previousValue = view.stringValue()
  let previousCursor = view.cursorTextIndex()
  let
    nextRows = max(rows, 0)
    nextColumns = max(columns, 0)
  view.xLines.setLen(nextRows)
  for row in 0 ..< nextRows:
    view.xLines[row].cells.setLen(nextColumns)
    for col in 0 ..< nextColumns:
      if view.xLines[row].cells[col].text.len == 0:
        view.xLines[row].cells[col] = initMonoTextCell()
  if view.xLines.len == 0:
    view.xLines.add MonoTextLine()
  view.clampCursor()
  view.invalidateTextGeometry()
  if view.stringValue() != previousValue:
    view.postAccessibilityNotification(anValueChanged)
  view.postCursorSelectionChanged(previousCursor)

proc replaceCells*(
    view: MonoTextView, row, column: int, cells: openArray[MonoTextCell]
) =
  if view.isNil or row < 0 or column < 0 or cells.len == 0:
    return
  let previousCursor = view.cursorTextIndex()
  view.ensureColumn(row, column + cells.len - 1)
  var changed = false
  for index, cell in cells:
    let target = column + index
    if view.xLines[row].cells[target] != cell:
      view.xLines[row].cells[target] = cell
      changed = true
  if not changed:
    return
  view.clampCursor()
  view.invalidateTextGeometry()
  view.postAccessibilityNotification(anValueChanged)
  view.postCursorSelectionChanged(previousCursor)

proc setLine*(view: MonoTextView, row: int, text: string) =
  if view.isNil or row < 0:
    return
  let previousCursor = view.cursorTextIndex()
  view.ensureLine(row)
  if view.xLines[row].lineToString() == text:
    return
  view.xLines[row].cells = text.textToCells()
  view.clampCursor()
  view.invalidateTextGeometry()
  view.postAccessibilityNotification(anValueChanged)
  view.postCursorSelectionChanged(previousCursor)

proc scrollCells*(view: MonoTextView, top, bottom, left, right, rows, columns: int) =
  if view.isNil or rows == 0 and columns == 0:
    return
  let
    topRow = max(top, 0)
    bottomRow = min(max(bottom, topRow), view.xLines.len)
    leftCol = max(left, 0)
    rightCol = max(right, leftCol)
    oldLines = view.xLines
  var changed = false
  for row in topRow ..< bottomRow:
    view.ensureColumn(row, max(rightCol - 1, 0))
    for column in leftCol ..< rightCol:
      let
        srcRow = row + rows
        srcColumn = column + columns
      let nextCell =
        if srcRow >= topRow and srcRow < bottomRow and srcRow >= 0 and
            srcRow < oldLines.len and srcColumn >= leftCol and srcColumn < rightCol and
            srcColumn < oldLines[srcRow].cells.len:
          oldLines[srcRow].cells[srcColumn]
        else:
          initMonoTextCell()
      if view.xLines[row].cells[column] != nextCell:
        view.xLines[row].cells[column] = nextCell
        changed = true
  if changed:
    view.invalidateTextGeometry()
    view.postAccessibilityNotification(anValueChanged)

proc editable*(view: MonoTextView): bool =
  (not view.isNil) and view.xEditable

proc `editable=`*(view: MonoTextView, editable: bool) =
  if view.isNil or view.xEditable == editable:
    return
  view.xEditable = editable
  view.setAcceptsFirstResponder(editable or view.xForwardedRawEvents != {})

proc forwardsRawEvents*(view: MonoTextView): bool =
  (not view.isNil) and view.xForwardedRawEvents != {}

proc `forwardsRawEvents=`*(view: MonoTextView, value: bool) =
  if view.isNil:
    return
  if value:
    if view.xForwardedRawEvents == AllMonoTextRawEvents:
      return
    view.xForwardedRawEvents = AllMonoTextRawEvents
  else:
    if view.xForwardedRawEvents == {} and view.xCapturedRawEvents == {}:
      return
    view.xForwardedRawEvents = {}
    view.xCapturedRawEvents = {}
  view.setAcceptsFirstResponder(view.xEditable or view.xForwardedRawEvents != {})

proc rawEventPolicy*(view: MonoTextView): MonoTextRawEventPolicy =
  if view.isNil:
    initMonoTextRawEventPolicy(forwardedEvents = {}, capturedEvents = {})
  else:
    MonoTextRawEventPolicy(
      forwardedEvents: view.xForwardedRawEvents, capturedEvents: view.xCapturedRawEvents
    )

proc `rawEventPolicy=`*(view: MonoTextView, policy: MonoTextRawEventPolicy) =
  if view.isNil:
    return
  view.xForwardedRawEvents = policy.forwardedEvents + policy.capturedEvents
  view.xCapturedRawEvents = policy.capturedEvents
  view.setAcceptsFirstResponder(view.xEditable or view.xForwardedRawEvents != {})

proc forwardedRawEvents*(view: MonoTextView): MonoTextRawEventKinds =
  if view.isNil:
    {}
  else:
    view.xForwardedRawEvents

proc `forwardedRawEvents=`*(view: MonoTextView, events: MonoTextRawEventKinds) =
  if view.isNil:
    return
  view.xForwardedRawEvents = events
  view.xCapturedRawEvents = view.xCapturedRawEvents * events
  view.setAcceptsFirstResponder(view.xEditable or view.xForwardedRawEvents != {})

proc capturedRawEvents*(view: MonoTextView): MonoTextRawEventKinds =
  if view.isNil:
    {}
  else:
    view.xCapturedRawEvents

proc `capturedRawEvents=`*(view: MonoTextView, events: MonoTextRawEventKinds) =
  if view.isNil:
    return
  view.xCapturedRawEvents = events
  view.xForwardedRawEvents = view.xForwardedRawEvents + events
  view.setAcceptsFirstResponder(view.xEditable or view.xForwardedRawEvents != {})

proc rawEventHandler*(view: MonoTextView): MonoTextRawEventHandler =
  if view.isNil: nil else: view.xRawEventHandler

proc `rawEventHandler=`*(view: MonoTextView, handler: MonoTextRawEventHandler) =
  if view.isNil:
    return
  view.xRawEventHandler = handler
  if not handler.isNil and view.xForwardedRawEvents == {}:
    view.forwardedRawEvents = AllMonoTextRawEvents

proc cursorRow*(view: MonoTextView): int =
  if view.isNil: 0 else: view.xCursorRow

proc cursorColumn*(view: MonoTextView): int =
  if view.isNil: 0 else: view.xCursorColumn

proc setCursorPosition*(view: MonoTextView, row, column: int) =
  if view.isNil:
    return
  let previousCursor = view.cursorTextIndex()
  view.xCursorRow = row
  view.xCursorColumn = column
  view.clampCursor()
  view.setNeedsDisplay(true)
  view.postCursorSelectionChanged(previousCursor)

proc cursorVisible*(view: MonoTextView): bool =
  (not view.isNil) and view.xCursorVisible

proc `cursorVisible=`*(view: MonoTextView, value: bool) =
  if view.isNil or view.xCursorVisible == value:
    return
  view.xCursorVisible = value
  view.setNeedsDisplay(true)

proc cursorStyle*(view: MonoTextView): MonoTextCursorStyle =
  if view.isNil: mtcBlock else: view.xCursorStyle

proc `cursorStyle=`*(view: MonoTextView, style: MonoTextCursorStyle) =
  if view.isNil or view.xCursorStyle == style:
    return
  view.xCursorStyle = style
  view.setNeedsDisplay(true)

proc tabWidth*(view: MonoTextView): int =
  if view.isNil: DefaultMonoTabWidth else: view.xTabWidth

proc `tabWidth=`*(view: MonoTextView, width: int) =
  if view.isNil:
    return
  view.xTabWidth = max(width, 1)

proc textColor*(view: MonoTextView): nimkitTypes.Color =
  if view.isNil:
    initColor(0.08, 0.09, 0.11, 1.0)
  elif view.xTextColor.a > 0.0'f32:
    view.xTextColor
  else:
    view.monoTextStyle().text.color

proc `textColor=`*(view: MonoTextView, color: nimkitTypes.Color) =
  if view.isNil or view.xTextColor == color:
    return
  view.xTextColor = color
  view.setNeedsDisplay(true)

proc cursorColor*(view: MonoTextView): nimkitTypes.Color =
  if view.isNil:
    initColor(0.08, 0.45, 0.95, 0.72)
  elif view.xCursorColor.a > 0.0'f32:
    view.xCursorColor
  else:
    view.monoTextStyle().cursorColor

proc `cursorColor=`*(view: MonoTextView, color: nimkitTypes.Color) =
  if view.isNil or view.xCursorColor == color:
    return
  view.xCursorColor = color
  view.setNeedsDisplay(true)

proc fontName*(view: MonoTextView): string =
  if view.isNil: DefaultMonoFontName else: view.xFontName

proc `fontName=`*(view: MonoTextView, name: string) =
  if view.isNil or name.len == 0 or view.xFontName == name:
    return
  view.xFontName = name
  view.invalidateTextGeometry()

proc fontSize*(view: MonoTextView): float32 =
  if view.isNil:
    defaultFontSize()
  else:
    view.xFontSize

proc `fontSize=`*(view: MonoTextView, size: float32) =
  let normalized = max(size, 1.0'f32)
  if view.isNil or view.xFontSize == normalized:
    return
  view.xFontSize = normalized
  view.invalidateTextGeometry()

proc padding*(view: MonoTextView): float32 =
  if view.isNil:
    DefaultMonoPadding
  elif view.xPadding >= 0.0'f32:
    view.xPadding
  else:
    view.monoTextInsets(view.monoTextStyle()).left

proc `padding=`*(view: MonoTextView, padding: float32) =
  let normalized = if padding < 0.0'f32: -1.0'f32 else: padding
  if view.isNil or view.xPadding == normalized:
    return
  view.xPadding = normalized
  view.invalidateTextGeometry()

func withAltModifier(input: string): string =
  if input.len == 0:
    return ""
  if input.len >= 2 and input[0] == '<' and input[^1] == '>':
    return "<A-" & input[1 .. ^2] & ">"
  "<A-" & input & ">"

func ctrlKeyInput(key: Key): string =
  case key
  of keyA: "<C-a>"
  of keyB: "<C-b>"
  of keyC: "<C-c>"
  of keyD: "<C-d>"
  of keyE: "<C-e>"
  of keyF: "<C-f>"
  of keyG: "<C-g>"
  of keyH: "<C-h>"
  of keyI: "<C-i>"
  of keyJ: "<C-j>"
  of keyK: "<C-k>"
  of keyL: "<C-l>"
  of keyM: "<C-m>"
  of keyN: "<C-n>"
  of keyO: "<C-o>"
  of keyP: "<C-p>"
  of keyQ: "<C-q>"
  of keyR: "<C-r>"
  of keyS: "<C-s>"
  of keyT: "<C-t>"
  of keyU: "<C-u>"
  of keyV: "<C-v>"
  of keyW: "<C-w>"
  of keyX: "<C-x>"
  of keyY: "<C-y>"
  of keyZ: "<C-z>"
  else: ""

func specialKeyInput(key: Key): string =
  case key
  of keyEnter: "<CR>"
  of keyBackspace: "<BS>"
  of keyTab: "<Tab>"
  of keyEscape: "<Esc>"
  of keyArrowUp: "<Up>"
  of keyArrowDown: "<Down>"
  of keyArrowLeft: "<Left>"
  of keyArrowRight: "<Right>"
  of keyDelete: "<Del>"
  of keyHome: "<Home>"
  of keyEnd: "<End>"
  of keyPageUp: "<PageUp>"
  of keyPageDown: "<PageDown>"
  else: ""

proc monoKeyInput*(event: KeyEvent): string =
  let
    ctrlDown = kmControl in event.modifiers
    altDown = kmOption in event.modifiers
  if ctrlDown:
    let input = ctrlKeyInput(event.key)
    if input.len > 0:
      return
        if altDown:
          input.withAltModifier()
        else:
          input
  result = specialKeyInput(event.key)
  if result.len == 0 and event.text.len > 0:
    result = event.text
  if altDown and result.len > 0:
    result = result.withAltModifier()

func mouseButtonName(button: MouseButton): string =
  case button
  of mbPrimary: "Left"
  of mbSecondary: "Right"
  of mbOther: "Middle"

func mouseInput(
    kind: MonoTextRawEventKind, event: MouseEvent, row, column: int
): string =
  let button = event.button.mouseButtonName()
  case kind
  of mtreMouseDown:
    let prefix =
      if event.clickCount >= 2 and event.clickCount <= 4:
        $event.clickCount & "-"
      else:
        ""
    "<" & prefix & button & "Mouse><" & $column & "," & $row & ">"
  of mtreMouseDragged:
    "<" & button & "Drag><" & $column & "," & $row & ">"
  of mtreMouseUp:
    "<" & button & "Release><" & $column & "," & $row & ">"
  else:
    ""

func scrollInput(event: ScrollEvent, row, column: int): string =
  let direction =
    if abs(event.deltaY) >= abs(event.deltaX):
      if event.deltaY > 0.0'f32: "Up" else: "Down"
    else:
      if event.deltaX > 0.0'f32: "Left" else: "Right"
  "<ScrollWheel" & direction & "><" & $column & "," & $row & ">"

proc makeRawEvent(
    view: MonoTextView, kind: MonoTextRawEventKind, event: MouseEvent
): MonoTextRawEvent =
  let pos = view.rowColumnAtPoint(event.location)
  case kind
  of mtreMouseDown:
    MonoTextRawEvent(
      kind: mtreMouseDown,
      row: pos.row,
      column: pos.column,
      input: mouseInput(kind, event, pos.row, pos.column),
      mouseEvent: event,
    )
  of mtreMouseDragged:
    MonoTextRawEvent(
      kind: mtreMouseDragged,
      row: pos.row,
      column: pos.column,
      input: mouseInput(kind, event, pos.row, pos.column),
      mouseEvent: event,
    )
  of mtreMouseUp:
    MonoTextRawEvent(
      kind: mtreMouseUp,
      row: pos.row,
      column: pos.column,
      input: mouseInput(kind, event, pos.row, pos.column),
      mouseEvent: event,
    )
  else:
    MonoTextRawEvent(
      kind: mtreMouseDown,
      row: pos.row,
      column: pos.column,
      input: mouseInput(mtreMouseDown, event, pos.row, pos.column),
      mouseEvent: event,
    )

proc makeRawEvent(view: MonoTextView, event: ScrollEvent): MonoTextRawEvent =
  let pos = view.rowColumnAtPoint(event.location)
  MonoTextRawEvent(
    kind: mtreScrollWheel,
    row: pos.row,
    column: pos.column,
    input: scrollInput(event, pos.row, pos.column),
    scrollEvent: event,
  )

proc makeRawEvent(
    view: MonoTextView, kind: MonoTextRawEventKind, event: KeyEvent
): MonoTextRawEvent =
  case kind
  of mtreKeyDown:
    MonoTextRawEvent(
      kind: mtreKeyDown,
      row: view.xCursorRow,
      column: view.xCursorColumn,
      input: event.monoKeyInput(),
      keyEvent: event,
    )
  of mtreFlagsChanged:
    MonoTextRawEvent(
      kind: mtreFlagsChanged,
      row: view.xCursorRow,
      column: view.xCursorColumn,
      input: event.monoKeyInput(),
      keyEvent: event,
    )
  else:
    MonoTextRawEvent(
      kind: mtreKeyDown,
      row: view.xCursorRow,
      column: view.xCursorColumn,
      input: event.monoKeyInput(),
      keyEvent: event,
    )

proc forwardRawEvent(view: MonoTextView, event: MonoTextRawEvent): bool =
  if event.kind notin view.xForwardedRawEvents:
    return false
  if not view.xRawEventHandler.isNil and view.xRawEventHandler(event):
    return true
  event.kind in view.xCapturedRawEvents

func isControlInput(rune: Rune): bool =
  let code = rune.int
  code < 32 or (code >= 127 and code <= 159)

proc insertRune(view: MonoTextView, rune: Rune): bool =
  if rune == Rune('\n'):
    let
      row = view.xCursorRow
      column = view.xCursorColumn
      tail = view.xLines[row].cells[column .. ^1]
    view.xLines[row].cells.setLen(column)
    view.xLines.insert(MonoTextLine(cells: tail), row + 1)
    view.xCursorRow = row + 1
    view.xCursorColumn = 0
    return true

  if rune == Rune('\t'):
    let spaces = view.xTabWidth - (view.xCursorColumn mod view.xTabWidth)
    for _ in 0 ..< max(spaces, 1):
      result = view.insertRune(Rune(' ')) or result
    return

  if rune.isControlInput():
    return false

  let row = view.xCursorRow
  view.xLines[row].cells.insert(initMonoTextCell(rune), view.xCursorColumn)
  inc view.xCursorColumn
  true

proc insertTextAtCursor(view: MonoTextView, text: string) =
  let previousCursor = view.cursorTextIndex()
  var changed = false
  for rune in text.runes:
    changed = view.insertRune(rune) or changed
  if changed:
    view.invalidateTextGeometry()
    view.postAccessibilityNotification(anValueChanged)
    view.postCursorSelectionChanged(previousCursor)

proc deleteBackward(view: MonoTextView): bool =
  let previousCursor = view.cursorTextIndex()
  if view.xCursorColumn > 0:
    view.xLines[view.xCursorRow].cells.delete(view.xCursorColumn - 1)
    dec view.xCursorColumn
    result = true
  elif view.xCursorRow > 0:
    let
      row = view.xCursorRow
      previousLen = view.xLines[row - 1].cells.len
      current = view.xLines[row].cells
    view.xLines[row - 1].cells.add current
    view.xLines.delete(row)
    view.xCursorRow = row - 1
    view.xCursorColumn = previousLen
    result = true
  if result:
    view.invalidateTextGeometry()
    view.postAccessibilityNotification(anValueChanged)
    view.postCursorSelectionChanged(previousCursor)

proc deleteForward(view: MonoTextView): bool =
  let previousCursor = view.cursorTextIndex()
  let row = view.xCursorRow
  if view.xCursorColumn < view.xLines[row].cells.len:
    view.xLines[row].cells.delete(view.xCursorColumn)
    result = true
  elif row + 1 < view.xLines.len:
    let next = view.xLines[row + 1].cells
    view.xLines[row].cells.add next
    view.xLines.delete(row + 1)
    result = true
  if result:
    view.invalidateTextGeometry()
    view.postAccessibilityNotification(anValueChanged)
    view.postCursorSelectionChanged(previousCursor)

proc moveCursorHorizontal(view: MonoTextView, delta: int) =
  let previousCursor = view.cursorTextIndex()
  if delta < 0:
    if view.xCursorColumn > 0:
      dec view.xCursorColumn
    elif view.xCursorRow > 0:
      dec view.xCursorRow
      view.xCursorColumn = view.xLines[view.xCursorRow].cells.len
  elif delta > 0:
    if view.xCursorColumn < view.xLines[view.xCursorRow].cells.len:
      inc view.xCursorColumn
    elif view.xCursorRow + 1 < view.xLines.len:
      inc view.xCursorRow
      view.xCursorColumn = 0
  view.setNeedsDisplay(true)
  view.postCursorSelectionChanged(previousCursor)

proc moveCursorVertical(view: MonoTextView, delta: int) =
  let previousCursor = view.cursorTextIndex()
  view.xCursorRow = (view.xCursorRow + delta).clampIndex(0, view.xLines.high)
  view.xCursorColumn =
    view.xCursorColumn.clampIndex(0, view.xLines[view.xCursorRow].cells.len)
  view.setNeedsDisplay(true)
  view.postCursorSelectionChanged(previousCursor)

proc handleEditorKey(view: MonoTextView, event: KeyEvent): bool =
  case event.key
  of keyArrowLeft:
    view.moveCursorHorizontal(-1)
    true
  of keyArrowRight:
    view.moveCursorHorizontal(1)
    true
  of keyArrowUp:
    view.moveCursorVertical(-1)
    true
  of keyArrowDown:
    view.moveCursorVertical(1)
    true
  of keyHome:
    let previousCursor = view.cursorTextIndex()
    view.xCursorColumn = 0
    view.setNeedsDisplay(true)
    view.postCursorSelectionChanged(previousCursor)
    true
  of keyEnd:
    let previousCursor = view.cursorTextIndex()
    view.xCursorColumn = view.xLines[view.xCursorRow].cells.len
    view.setNeedsDisplay(true)
    view.postCursorSelectionChanged(previousCursor)
    true
  of keyBackspace:
    discard view.deleteBackward()
    true
  of keyDelete:
    discard view.deleteForward()
    true
  of keyEnter:
    view.insertTextAtCursor("\n")
    true
  of keyTab:
    view.insertTextAtCursor("\t")
    true
  else:
    if event.modifiers - {kmShift} == {} and event.text.len > 0:
      view.insertTextAtCursor(event.text)
      true
    else:
      false

proc cellRect(
    view: MonoTextView,
    row, column: int,
    metrics: MonoTextMetrics,
    textInsets: EdgeInsets,
): nimkitTypes.Rect =
  initRect(
    textInsets.left + column.float32 * metrics.cellWidth,
    textInsets.top + row.float32 * metrics.lineHeight,
    metrics.cellWidth,
    metrics.lineHeight,
  )

proc cursorRect(
    view: MonoTextView, metrics: MonoTextMetrics, textInsets: EdgeInsets
): nimkitTypes.Rect =
  result = view.cellRect(view.xCursorRow, view.xCursorColumn, metrics, textInsets)
  case view.xCursorStyle
  of mtcBlock:
    discard
  of mtcVertical:
    result.size.width = max(1.0'f32, metrics.cellWidth * 0.12'f32)
  of mtcUnderline:
    let height = max(1.0'f32, metrics.lineHeight * 0.12'f32)
    result.origin.y += metrics.lineHeight - height
    result.size.height = height

proc drawRun(
    view: MonoTextView,
    context: DrawContext,
    font: FigFont,
    row, startColumn, endColumn: int,
    metrics: MonoTextMetrics,
    textInsets: EdgeInsets,
    defaultTextColor: nimkitTypes.Color,
) =
  if endColumn <= startColumn:
    return
  let
    line = view.xLines[row]
    firstCell = line.cells[startColumn]
    foregroundColor = firstCell.foreground(defaultTextColor)
    runRect = initRect(
      textInsets.left + startColumn.float32 * metrics.cellWidth,
      textInsets.top + row.float32 * metrics.lineHeight,
      (endColumn - startColumn).float32 * metrics.cellWidth,
      metrics.lineHeight,
    )

  if firstCell.hasBackgroundColor:
    discard context.addRectangle(runRect, fill(firstCell.backgroundColor.rgba))

  var glyphs: seq[(Rune, Vec2)]
  glyphs.setLen(endColumn - startColumn)
  var x = 0.0'f32
  for column in startColumn ..< endColumn:
    glyphs[column - startColumn] = (line.cells[column].firstRune(), vec2(x, 0.0'f32))
    x += metrics.cellWidth

  let layout = placeGlyphs(fs(font, fill(foregroundColor.rgba)), glyphs, GlyphTopLeft)
  discard context.addText(runRect, layout)

proc drawMonoTextSurface(
    view: MonoTextView, context: DrawContext, style: MonoTextStyle
) =
  if view.isNil or context.bounds().isEmpty:
    return
  let
    states = view.widgetStateSet()
    frame = context.renderRectFor(context.bounds())
    chrome = chromeContext(style.chrome, crPopupList, cpFace, style.box.fill, states)
    surfaceRoot = context.addRenderRectangle(
      frame,
      context.appearance.chromeFill(chrome),
      style.box.borderColor,
      style.box.borderWidth,
      style.box.cornerRadius,
      style.box.shadows,
      maskContent = true,
      cornerRadii = style.box.cornerRadii,
    )
  context.drawChromeExtras(
    chrome,
    initChromeExtras(
      surfaceRoot,
      frame,
      cornerRadius = style.box.cornerRadius,
      cornerRadii = style.box.cornerRadii,
    ),
  )
  if view.isFocusVisible():
    context.addFocusRing(frame, style.box)

proc drawMonoText(view: MonoTextView, context: DrawContext) =
  if view.isNil or view.xLines.len == 0:
    return
  let
    style = context.appearance.resolveMonoTextStyle(view.monoTextStyleContext())
    textInsets = view.monoTextInsets(style)
    textColor = view.resolvedTextColor(style)
    cursorColor = view.resolvedCursorColor(style)
    metrics = view.monoTextMetrics()
    font = view.monoFont()
    visible = context.visibleRect()
    rowStart = max(
      int(floor(max(visible.origin.y - textInsets.top, 0.0'f32) / metrics.lineHeight)),
      0,
    )
    rowStop = min(
      int(ceil(max(visible.maxY - textInsets.top, 0.0'f32) / metrics.lineHeight)),
      view.xLines.len,
    )
    colStart = max(
      int(floor(max(visible.origin.x - textInsets.left, 0.0'f32) / metrics.cellWidth)),
      0,
    )
    colStop = max(
      int(ceil(max(visible.maxX - textInsets.left, 0.0'f32) / metrics.cellWidth)),
      colStart,
    )

  view.drawMonoTextSurface(context, style)

  for row in rowStart ..< rowStop:
    let line = view.xLines[row]
    var column = min(colStart, line.cells.len)
    let lastColumn = min(max(colStop, column), line.cells.len)
    while column < lastColumn:
      let startColumn = column
      inc column
      while column < lastColumn and
          line.cells[startColumn].sameRunStyle(line.cells[column], textColor):
        inc column
      view.drawRun(
        context, font, row, startColumn, column, metrics, textInsets, textColor
      )

  if view.xCursorVisible and view.isFocused():
    discard
      context.addRectangle(view.cursorRect(metrics, textInsets), fill(cursorColor.rgba))

proc monoTextIntrinsicSize(view: MonoTextView): IntrinsicSize =
  let
    style = view.monoTextStyle()
    textInsets = view.monoTextInsets(style)
    metrics = view.monoTextMetrics()
    contentSize = initSize(
      max(view.xMaxColumns, 1).float32 * metrics.cellWidth,
      max(view.xLines.len, 1).float32 * metrics.lineHeight,
    )
  initIntrinsicSize(
    max(style.minSize.width, textInsets.horizontal + contentSize.width),
    max(style.minSize.height, textInsets.vertical + contentSize.height),
  )

protocol DefaultMonoTextViewDrawing of ViewDrawingProtocol:
  method draw(view: MonoTextView, context: DrawContext) =
    view.drawMonoText(context)

protocol DefaultMonoTextViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: MonoTextView): IntrinsicSize =
    view.monoTextIntrinsicSize()

protocol DefaultMonoTextViewEvents of ResponderEventProtocol:
  method mouseDown(view: MonoTextView, event: MouseEvent): bool =
    if view.forwardRawEvent(view.makeRawEvent(mtreMouseDown, event)):
      return true
    if event.button == mbPrimary and view.xEditable:
      let owner = view.window()
      if owner of Window:
        discard Window(owner).makeFirstResponder(view)
      let pos = view.rowColumnAtPoint(event.location)
      view.setCursorPosition(pos.row, pos.column)
      return true
    false

  method mouseDragged(view: MonoTextView, event: MouseEvent): bool =
    view.forwardRawEvent(view.makeRawEvent(mtreMouseDragged, event))

  method mouseUp(view: MonoTextView, event: MouseEvent): bool =
    view.forwardRawEvent(view.makeRawEvent(mtreMouseUp, event))

  method scrollWheel(view: MonoTextView, event: ScrollEvent): bool =
    view.forwardRawEvent(view.makeRawEvent(event))

  method keyDown(view: MonoTextView, event: KeyEvent): bool =
    view.xSuppressNextTextInput = false
    if view.forwardRawEvent(view.makeRawEvent(mtreKeyDown, event)):
      view.xSuppressNextTextInput = true
      return true
    result = view.xEditable and view.handleEditorKey(event)
    if result and event.text.len > 0:
      view.xSuppressNextTextInput = true

  method flagsChanged(view: MonoTextView, event: KeyEvent): bool =
    view.forwardRawEvent(view.makeRawEvent(mtreFlagsChanged, event))

protocol DefaultMonoTextViewInput of TextInputProtocol:
  method insertText(view: MonoTextView, text: string) =
    if view.xSuppressNextTextInput or mtreKeyDown in view.xCapturedRawEvents:
      view.xSuppressNextTextInput = false
      return
    if view.xEditable and text.len > 0:
      view.insertTextAtCursor(text)

protocol DefaultMonoTextViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(view: MonoTextView): AccessibilityRole =
    if view.xEditable: arTextArea else: arStaticText

  method accessibilityValue(view: MonoTextView): string =
    view.stringValue()

  method accessibilityTraits(view: MonoTextView): AccessibilityTraits =
    result = view.xAccessibilityTraits
    if view.isFocused():
      result.incl atFocused
    if view.xEditable:
      result.incl atEditable
      result.incl atSelectable

  method isAccessibilityElement(view: MonoTextView): bool =
    true

  method accessibilityTextLength(view: MonoTextView): int =
    view.textLength()

  method accessibilitySelectedTextRange(view: MonoTextView): AccessibilityTextRange =
    let index = view.cursorTextIndex()
    initAccessibilityTextRange(index, 0)

  method setAccessibilitySelectedTextRange(
      view: MonoTextView, range: AccessibilityTextRange
  ): bool =
    if view.isNil or not view.xEditable:
      return false
    let position = view.rowColumnForTextIndex(int(range.location) + int(range.length))
    view.setCursorPosition(position.row, position.column)
    true

  method accessibilityInsertionPoint(view: MonoTextView): int =
    view.cursorTextIndex()

  method setAccessibilityInsertionPoint(view: MonoTextView, index: int): bool =
    if view.isNil or not view.xEditable:
      return false
    let position = view.rowColumnForTextIndex(index)
    view.setCursorPosition(position.row, position.column)
    true

  method accessibilityBoundsForTextRange(
      view: MonoTextView, range: AccessibilityTextRange
  ): seq[nimkitTypes.Rect] =
    if view.isNil:
      return
    let stop = min(range.maxIndex, view.textLength())
    for index in int(range.location) ..< stop:
      let rect = view.accessibilityBoundsForCharacter(index)
      if not rect.isEmpty:
        result.add rect

  method accessibilityBoundsForCharacter(
      view: MonoTextView, index: int
  ): nimkitTypes.Rect =
    if view.isNil or index < 0 or index >= view.textLength():
      return initRect(0, 0, 0, 0)
    let
      position = view.rowColumnForTextIndex(index)
      metrics = view.monoTextMetrics()
      style = view.monoTextStyle()
      textInsets = view.monoTextInsets(style)
    view.rectToWindow(view.cellRect(position.row, position.column, metrics, textInsets))

  method accessibilityCharacterIndexAtPoint(
      view: MonoTextView, point: nimkitTypes.Point
  ): int =
    if view.isNil:
      return -1
    let position = view.rowColumnAtPoint(view.pointFromWindow(point))
    view.textIndexForRowColumn(position.row, position.column)

  method accessibilityLineRange(view: MonoTextView, line: int): AccessibilityTextRange =
    if view.isNil or line < 0 or line >= view.xLines.len:
      return initAccessibilityTextRange(0, 0)
    initAccessibilityTextRange(
      view.textIndexForRowColumn(line, 0), view.xLines[line].lineToString().runeLen
    )

  method accessibilityLineForCharacter(view: MonoTextView, index: int): int =
    if view.isNil:
      return -1
    view.rowColumnForTextIndex(index).row

  method accessibilityBoundsForLine(view: MonoTextView, line: int): nimkitTypes.Rect =
    if view.isNil or line < 0 or line >= view.xLines.len:
      return initRect(0, 0, 0, 0)
    let
      metrics = view.monoTextMetrics()
      style = view.monoTextStyle()
      textInsets = view.monoTextInsets(style)
      width = max(view.xLines[line].cells.len, 1).float32 * metrics.cellWidth
    view.rectToWindow(
      initRect(
        textInsets.left,
        textInsets.top + line.float32 * metrics.lineHeight,
        width,
        metrics.lineHeight,
      )
    )

proc initMonoTextViewFields*(
    view: MonoTextView, value = "", frame: nimkitTypes.Rect = AutoRect, editable = false
) =
  initViewFields(view, frame)
  view.xEditable = editable
  view.xCursorVisible = true
  view.xCursorStyle = mtcBlock
  view.xTabWidth = DefaultMonoTabWidth
  view.xPadding = -1.0'f32
  view.xFontName = DefaultMonoFontName
  view.xFontSize = defaultFontSize()
  view.xTextColor = initColor(0.0, 0.0, 0.0, 0.0)
  view.xCursorColor = initColor(0.0, 0.0, 0.0, 0.0)
  view.backgroundColor = initColor(0.0, 0.0, 0.0, 0.0)
  discard view.withProtocol(DefaultMonoTextViewDrawing)
  discard view.withProtocol(DefaultMonoTextViewLayout)
  discard view.withProtocol(DefaultMonoTextViewEvents)
  discard view.withProtocol(DefaultMonoTextViewInput)
  discard view.withProtocol(DefaultMonoTextViewAccessibility)
  view.setAcceptsFirstResponder(editable)
  view.stringValue = value
  view.applyInitialFrame(frame)

proc newMonoTextView*(
    value = "", frame: nimkitTypes.Rect = AutoRect, editable = false
): MonoTextView =
  result = MonoTextView()
  initMonoTextViewFields(result, value, frame, editable)

proc newMonoTextEditor*(value = "", frame: nimkitTypes.Rect = AutoRect): MonoTextView =
  newMonoTextView(value, frame, editable = true)

proc newMonoTextViewer*(value = "", frame: nimkitTypes.Rect = AutoRect): MonoTextView =
  newMonoTextView(value, frame, editable = false)
