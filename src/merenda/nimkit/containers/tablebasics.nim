## Table values, sizing records, and helpers independent of live table widgets.
## Import tableviews for TableView, TableColumn, protocols, and widget behavior.

import std/[options, tables]

from sigils/selectors import DynamicAgent

import ../foundation/objectvalues
import ../foundation/types
import ../themes/themecore

const
  TablePasteboardTypeRows* = "nimkit.table.rows"
  TablePasteboardTypeRowIdentifiers* = "nimkit.table.row-identifiers"
  TablePasteboardTypeColumns* = "nimkit.table.columns"

type
  TableModelError* = object of KeyError

  TableSelectionMode* = enum
    lsmNone
    lsmSingle
    lsmMultiple
    lsmExtended

  TableViewOption* = enum
    tvoAlternatingRowBackgrounds
    tvoRowSeparators
    tvoColumnSelection
    tvoRowReordering
    tvoPointerRowHighlights
    tvoPointerColumnHighlights
    tvoFocusedRowHighlight
    tvoFocusedColumnHighlight

  TableRowSelection* = object
    mode*: TableSelectionMode
    index*: int ## Cached first selected row, or -1 when empty.
    indexes*: seq[int]
    anchor*: int ## Fixed end of a Shift selection range, or -1 when empty.
    lead*: int ## Moving end of a Shift selection range, or -1 when empty.

  TableColumnResizePolicy* = enum
    tcrFixed
    tcrResizable

  TableColumnSizingPolicy* = enum
    tcspFixed
    tcspFlexible
    tcspContentSized

  TableViewColumnSizing* = enum
    tvcsNatural
    tvcsFill

  TableViewWidthSizingMode* = enum
    tvwsmColumns
    tvwsmContent
    tvwsmPreferredWidth

  TableSortDirection* = enum
    tsdNone
    tsdAscending
    tsdDescending

  TableRowUpdateKind* = enum
    trukInsert
    trukRemove
    trukMove
    trukReload

  TableViewStateScope* = enum
    tvssAutomatic
    tvssApplication
    tvssDocument
    tvssWorkspace

  TableHeaderHitPart* = enum
    thpNone
    thpRowHeader
    thpRowHeaderResizeHandle
    thpRowHeaderRowResizeHandle
    thpColumn
    thpResizeHandle

  TableVisibleRowSummary* = object
    index*: int
    text*: string
    rect*: Rect
    states*: set[WidgetState]

  TableRowUpdate* = object
    kind*: TableRowUpdateKind
    indexes*: seq[int]
    fromIndex*: int
    toIndex*: int
    identifiers*: seq[string]

  TableCellValue* = object
    columnIdentifier*: string
    value*: ObjectValue

  TableRowValue* = object
    identifier*: string
    objectValue*: ObjectValue
    cells*: seq[TableCellValue]
    enabled*: bool
    hidden*: bool
    representedObject*: DynamicAgent

  TableModelColumn* = object
    identifier*: string
    title*: string
    valueKey*: string
    width*: float32
    hidden*: bool

  TableModelSortDescriptor* = object
    columnIdentifier*: string
    direction*: TableSortDirection

  TableModelFilter* = proc(row: TableRowValue): bool {.closure.}

  TableRowIdentifierResolver* = proc(identifier: string): string {.closure.}

  TableHeaderDragIndicator* = object
    index*: int
    rect*: Rect
    visible*: bool

  TableHeaderChrome* = object
    headerFill*: Fill
    headerBorderColor*: Color
    cellFill*: Fill
    hoveredCellFill*: Fill
    pressedCellFill*: Fill
    cellBorderColor*: Color
    textColor*: Color
    sortIndicatorColor*: Color
    insertionIndicatorFill*: Fill
    borderWidth*: float32
    sortIndicatorWidth*: float32
    insertionWidth*: float32
    insertionCapWidth*: float32
    insertionCapHeight*: float32
    cornerRadius*: float32

  TableColumnAutosaveRecord* = object
    identifier*: string
    width*: float32
    hidden*: bool
    sortDirection*: TableSortDirection

  TableViewState* = object
    columns*: seq[TableColumnAutosaveRecord]
    selectedRows*: seq[int]
    selectedRowIdentifiers*: seq[string]
    selectedColumns*: seq[string]
    expandedItems*: seq[string]

  TableWidthSizing* = object
    mode*: TableViewWidthSizingMode
    columnSizing*: TableViewColumnSizing
    preferredContentWidth*: float32

  TableRowSizing* = object
    height*: float32
    hasExplicitHeight*: bool
    visibleRows*: int
    overrides*: Table[int, float32]

  TableHeaderSettings* = object
    visible*: bool
    height*: float32
    hasExplicitHeight*: bool

  TableRowHeaderSettings* = object
    visible*: bool
    width*: float32
    title*: string

  TableTypeSelection* = object
    buffer*: string
    lastInputTime*: float

  TableWidthMeasurement* = object
    width*: float32
    fontName*: string
    fontSize*: float32
    valid*: bool

  TableColWidth* = object
    resolved*: float32
    preferred*: float32
    min*: float32
    max*: float32
    # A manually resized flexible column opts out of automatic fill resizing.
    userResized*: bool

  TableColWidthMeasurement* = object
    width*: float32
    contentFontName*: string
    contentFontSize*: float32
    contentHorizontalInsets*: float32
    headerFontName*: string
    headerFontSize*: float32
    valid*: bool

  TableRowHeightMeasurement* = object
    heights*: seq[float32]
    offsets*: seq[float32]
    defaultHeight*: float32
    valid*: bool
    computing*: bool

  TableRowDragStart* = object
    row*: int
    point*: Point

  TableRowUpdateBatch* = object
    depth*: int
    pending*: seq[TableRowUpdate]

const
  tsmNone* = TableSelectionMode.lsmNone
  tsmSingle* = TableSelectionMode.lsmSingle
  tsmMultiple* = TableSelectionMode.lsmMultiple
  tsmExtended* = TableSelectionMode.lsmExtended

proc `[]=`*(
    options: var set[TableViewOption], option: TableViewOption, enabled: bool
) {.inline.} =
  ## Enables or disables one table option without changing the others.
  if enabled:
    options.incl(option)
  else:
    options.excl(option)

func initTableRowSelection*(mode = tsmSingle): TableRowSelection =
  ## Initializes an empty selection with no anchor or lead row.
  TableRowSelection(mode: mode, index: -1, anchor: -1, lead: -1)

proc clear*(selection: var TableRowSelection) =
  ## Clears the selected rows and cursor while preserving the selection mode.
  selection.indexes.setLen(0)
  selection.index = -1
  selection.anchor = -1
  selection.lead = -1

proc raiseTableModelError*(message: string) {.noinline, noreturn.} =
  raise newException(TableModelError, message)

func tableCell*(columnIdentifier: string, value: ObjectValue): TableCellValue =
  TableCellValue(columnIdentifier: columnIdentifier, value: value)

proc tableRow*(
    identifier = "",
    objectValue = emptyObjectValue(),
    cells: openArray[TableCellValue] = [],
    enabled = true,
    hidden = false,
    representedObject: DynamicAgent = nil,
): TableRowValue =
  TableRowValue(
    identifier: identifier,
    objectValue: objectValue,
    cells: @cells,
    enabled: enabled,
    hidden: hidden,
    representedObject: representedObject,
  )

func initTableModelColumn*(
    identifier: string, title = "", valueKey = "", width = 120.0'f32, hidden = false
): TableModelColumn =
  TableModelColumn(
    identifier: identifier,
    title: title,
    valueKey: valueKey,
    width: width,
    hidden: hidden,
  )

func initTableModelSortDescriptor*(
    columnIdentifier: string, direction = tsdAscending
): TableModelSortDescriptor =
  TableModelSortDescriptor(columnIdentifier: columnIdentifier, direction: direction)

func defaultTableRowUpdate(
    kind: TableRowUpdateKind,
    indexes: openArray[int] = [],
    identifiers: openArray[string] = [],
    fromIndex = -1,
    toIndex = -1,
): TableRowUpdate =
  TableRowUpdate(
    kind: kind,
    indexes: @indexes,
    fromIndex: fromIndex,
    toIndex: toIndex,
    identifiers: @identifiers,
  )

func initTableRowInsertUpdate*(
    indexes: openArray[int], identifiers: openArray[string] = []
): TableRowUpdate =
  defaultTableRowUpdate(trukInsert, indexes, identifiers)

func initTableRowRemoveUpdate*(
    indexes: openArray[int], identifiers: openArray[string] = []
): TableRowUpdate =
  defaultTableRowUpdate(trukRemove, indexes, identifiers)

func initTableRowReloadUpdate*(
    indexes: openArray[int], identifiers: openArray[string] = []
): TableRowUpdate =
  defaultTableRowUpdate(trukReload, indexes, identifiers)

func initTableRowMoveUpdate*(
    fromIndex, toIndex: int, identifiers: openArray[string] = []
): TableRowUpdate =
  defaultTableRowUpdate(
    trukMove, identifiers = identifiers, fromIndex = fromIndex, toIndex = toIndex
  )

func findCellIndex(row: TableRowValue, columnIdentifier: string): int =
  for index, cell in row.cells:
    if cell.columnIdentifier == columnIdentifier:
      return index
  -1

func hasValue*(row: TableRowValue, columnIdentifier: string): bool =
  columnIdentifier.len == 0 or row.findCellIndex(columnIdentifier) >= 0

func getValue*(row: TableRowValue, columnIdentifier = ""): Option[ObjectValue] =
  if columnIdentifier.len == 0:
    return some(row.objectValue)
  let index = row.findCellIndex(columnIdentifier)
  if index >= 0:
    some(row.cells[index].value)
  else:
    none(ObjectValue)

proc value*(
    row: TableRowValue, columnIdentifier = ""
): ObjectValue {.raises: [TableModelError].} =
  let found = row.getValue(columnIdentifier)
  if found.isSome:
    return found.get()
  raiseTableModelError("unknown table cell column identifier: " & columnIdentifier)

proc `[]`*(row: TableRowValue, columnIdentifier: string): ObjectValue =
  row.value(columnIdentifier)

proc setValue*(row: var TableRowValue, columnIdentifier: string, value: ObjectValue) =
  if columnIdentifier.len == 0:
    row.objectValue = value
    return
  let index = row.findCellIndex(columnIdentifier)
  if index >= 0:
    row.cells[index].value = value
  else:
    row.cells.add tableCell(columnIdentifier, value)

proc `[]=`*(row: var TableRowValue, columnIdentifier: string, value: ObjectValue) =
  row.setValue(columnIdentifier, value)

proc initTableViewState*(
    columns: openArray[TableColumnAutosaveRecord] = [],
    selectedRows: openArray[int] = [],
    selectedColumns: openArray[string] = [],
    expandedItems: openArray[string] = [],
    selectedRowIdentifiers: openArray[string] = [],
): TableViewState =
  TableViewState(
    columns: @columns,
    selectedRows: @selectedRows,
    selectedRowIdentifiers: @selectedRowIdentifiers,
    selectedColumns: @selectedColumns,
    expandedItems: @expandedItems,
  )

func matches*(measurement: TableWidthMeasurement, style: TextStyle): bool {.inline.} =
  measurement.valid and measurement.fontName == style.fontName and
    measurement.fontSize == style.fontSize

func matches*(
    measurement: TableColWidthMeasurement, contentStyle, headerStyle: TextStyle
): bool {.inline.} =
  measurement.valid and measurement.contentFontName == contentStyle.fontName and
    measurement.contentFontSize == contentStyle.fontSize and
    measurement.contentHorizontalInsets == contentStyle.insets.horizontal and
    measurement.headerFontName == headerStyle.fontName and
    measurement.headerFontSize == headerStyle.fontSize

func matches*(
    measurement: TableRowHeightMeasurement, defaultHeight: float32
): bool {.inline.} =
  measurement.valid and measurement.defaultHeight == defaultHeight
