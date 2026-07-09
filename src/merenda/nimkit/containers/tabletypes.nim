import std/[algorithm, math, options, strutils, tables, times]

from figdraw/fignodes import FigIdx
import sigils/core

import ../accessibility/accessibilityprotocols
import ../drawing
import ../foundation/events
import ../app/dragging
import ../app/pasteboards
import ../app/userdefaults
import ../app/windows
import ../controls/controls
import ../containers/listbasics
import ../containers/scrollviews
import ../foundation/objectvalues
import ../foundation/selectors
import ../themes
import ../text/fieldeditors
import ../text/textviews
import ../foundation/types
import ../foundation/undomanagers
import ../view/views

const
  TablePasteboardTypeRows* = "nimkit.table.rows"
  TablePasteboardTypeRowIdentifiers* = "nimkit.table.row-identifiers"
  TablePasteboardTypeColumns* = "nimkit.table.columns"

type
  TableModelError* = object of KeyError

  TableView* = ref object of Control

  TableModel* = ref object of DynamicAgent

  TableRowView = ref object of View

  TableContentView = ref object of View

  TableViewStateStore* = ref object of DynamicAgent

  TableColumn* = ref object


type
  TableSelectionMode* = enum
    lsmNone
    lsmSingle
    lsmMultiple
    lsmExtended

  TableColumnResizePolicy* = enum
    tcrFixed
    tcrResizable

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

type
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

  TableHeaderHit* = object
    column*: TableColumn
    columnIndex*: int
    row*: int
    part*: TableHeaderHitPart
    rect*: Rect

  TableEditingState* = object
    row*: int
    column*: TableColumn
    active*: bool
    validationError*: string
    validation*: ObjectValidationError
    objectValue*: ObjectValue

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

const
  tsmNone* = TableSelectionMode.lsmNone
  tsmSingle* = TableSelectionMode.lsmSingle
  tsmMultiple* = TableSelectionMode.lsmMultiple
  tsmExtended* = TableSelectionMode.lsmExtended

