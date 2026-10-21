## Shared table types, model storage, data queries, and geometry calculations.
## Import tableviews for widget construction and coordinated behavior.

import std/[algorithm, math, options, strutils, tables]

import sigils/core

import ../accessibility/accessibilityprotocols
import ../drawing
import ../foundation/events
import ../app/dragging
import ../app/pasteboards
import ../app/windows
import ../controls/controls
import ../containers/listbasics
import ./tablebasics
import ./tablecoordination
import ../containers/scrollviews
import ../foundation/objectvalues
import ../foundation/private/itemcollections
import ../foundation/selectors
import ../themes
import ../foundation/types
from ../view/viewgeometry import setFrameFromLayout
import ../view/views

export tablebasics

const
  TableColumnWidthEpsilon = 0.001'f32
  MaxTableContentLayoutPasses = 4

const
  TableHeaderTrackingTag* = 0x74001
  TableRowHeaderTrackingTag* = 0x74002
  TableHeaderResizeCursorName* = "resizeLeftRight"
  TableRowHeaderResizeCursorName* = "resize-up-down"

type
  TableRowView* = ref object of View
    xTableView*: TableView
    xRow*: RowState

  TableContentView* = ref object of View
    xTableView*: TableView
    xRowViews*: seq[TableRowView]

  TableModel* = ref object of DynamicAgent
    xRows: ItemCollection[TableRowValue]
    xColumns: seq[TableModelColumn]
    xSortDescriptors: seq[TableModelSortDescriptor]
    xFilter: TableModelFilter

  TableHeaderHit* = object
    column*: TableColumn
    columnIndex*: int
    row*: int
    part*: TableHeaderHitPart
    rect*: Rect

  TableEditingState* = object
    row*: int = -1
    column*: TableColumn
    active*: bool
    validationError*: string
    validation*: ObjectValidationError
    objectValue*: ObjectValue

  TableHeaderTracking* = object
    part*: TableHeaderHitPart
    column*: TableColumn
    columnIndex*: int = -1
    row*: int = -1
    startPoint*: Point
    startSize*: Size
    draggingColumn*: bool
    insertionIndex*: int = -1
    insertionRect*: Rect

  TableDraggingState* = object
    session*: DraggingSession
    dropTarget*: DraggingDropTarget = initDraggingDropTarget()
    rowStart*: TableRowDragStart

  TableEditingSurface* = object
    hostView*: View
    cell*: Cell
    isRowView*: bool

  TableEditCompletion* = object
    row*: int = -1
    column*: TableColumn
    committed*: bool

  TableEditorState* = object
    state*: TableEditingState
    surface*: TableEditingSurface
    cancelling*: bool
    completion*: TableEditCompletion

  TableView* = ref object of Control
    xColumns*: seq[TableColumn]
    xRowSelection*: TableRowSelection
    xOptions*: set[TableViewOption] = {
      tvoPointerRowHighlights, tvoPointerColumnHighlights, tvoFocusedRowHighlight,
      tvoFocusedColumnHighlight,
    }
    xHighlightedIndex*: int = -1
    xScrollView*: ScrollView
    xContentView*: TableContentView
    xRowSizing*: TableRowSizing
    xWidthSizing*: TableWidthSizing
    xWidthMeasurement*: TableWidthMeasurement
    xRowHeightMeasurement*: TableRowHeightMeasurement
    xTrackingItem*: bool
    xPressedIndex*: int = -1
    xTypeSelection*: TableTypeSelection
    xTableRole*: StyleRole = srTableView
    xItemRole*: StyleRole = srRowItem
    xRowCount*: int
    xTableDataSource*: DynamicAgent
    xTableDelegate*: DynamicAgent
    xCellSlots*: seq[TableCellSlot]
    xReusableCellViews: Table[string, seq[View]]
    xHeaderSettings*: TableHeaderSettings
    xHoveredColumn*: TableColumn
    xPressedColumn*: TableColumn
    xClickedRow*: int = -1
    xClickedColumn*: TableColumn
    xFocusedColumn*: TableColumn
    xHighlightedColumn*: TableColumn
    xSelectedColumns*: seq[TableColumn]
    xRowHeaderSettings*: TableRowHeaderSettings
    xCellEditing*: TableEditorState
    xAutosaveName*: string
    xStateStorage*: DynamicAgent
    xStateScope*: TableViewStateScope
    xWorkspaceIdentifier*: string
    xHasRestoredState*: bool
    xObservedStateWindow*: Window
    xColumnAutosaveAliases*: Table[string, string]
    xRowIdentifierAliases: Table[string, string]
    xRowIdentifierResolver: TableRowIdentifierResolver
    xRowUpdates*: TableRowUpdateBatch
    xDragging*: TableDraggingState
    xHeaderTracking*: TableHeaderTracking

  TableCellSlot* = object
    row*: int
    column*: TableColumn
    view*: View

  TableContentLayout* = object
    scrollFrame*: Rect
    documentSize*: Size

  TableColumn* = ref object
    xTableView*: TableView
    xIdentifier*: string
    xTitle*: string
    xWidth*: TableColWidth
    xAlignment*: TextAlignment
    xResizePolicy*: TableColumnResizePolicy
    xSizingPolicy*: TableColumnSizingPolicy
    xWidthMeasurement*: TableColWidthMeasurement
    xHidden*: bool
    xSortDirection*: TableSortDirection
    xReuseIdentifier*: string
    xStyleId*: string
    xStyleClasses*: seq[string]
    xUserInfo*: DynamicAgent

protocol TableViewDataSource {.selectorScope: protocol.}:
  ## Supplies row counts, cell values, and stable row identities.
  method numberOfRows*(tableView: TableView): int {.optional.}
    ## Returns the number of available rows.

  method textForCell*(
    tableView: TableView, row: int, column: TableColumn
  ): string {.optional.} ## Returns display text for the requested cell.

  method textForRowHeader*(tableView: TableView, row: int): string {.optional.}
    ## Returns display text for a row header.

  method normalizedSearchTextForRow*(
    tableView: TableView, row: int
  ): string {.optional.} ## Returns normalized row text for keyboard type selection.

  method objectValueForCell*(
    tableView: TableView, row: int, column: TableColumn
  ): ObjectValue {.optional.} ## Returns the typed value for the requested cell.

  method setObjectValueForCell*(
    tableView: TableView, row: int, column: TableColumn, value: ObjectValue
  ): bool {.optional.} ## Stores a typed cell value and reports whether it was accepted.

  method identifierForRow*(tableView: TableView, row: int): string {.optional.}
    ## Returns a stable identity for the row.

  method rowForIdentifier*(tableView: TableView, identifier: string): int {.optional.}
    ## Resolves a stable row identity, or returns -1 when absent.

  method tableIntrinsicContentWidth*(tableView: TableView): float32 {.optional.}
    ## Returns the preferred content width supplied by the data source.

protocol TableViewEvents:
  ## Publishes selection, activation, editing, and row-update notifications.
  proc selectionIsChanging*(tableView: TableView, sender: DynamicAgent) {.signal.}
    ## Notifies observers before the selection changes.

  proc selectionDidChange*(tableView: TableView, sender: DynamicAgent) {.signal.}
    ## Notifies observers after the selection changes.

  proc rowWasActivated*(tableView: TableView, sender: DynamicAgent) {.signal.}
    ## Notifies observers when the clicked row is activated.

  proc cellEditDidCommit*(
    tableView: TableView,
    sender: DynamicAgent,
    row: int,
    column: TableColumn,
    value: string,
  ) {.signal.} ## Notifies observers of a committed cell text value.

  proc cellObjectValueDidCommit*(
    tableView: TableView,
    sender: DynamicAgent,
    row: int,
    column: TableColumn,
    value: ObjectValue,
  ) {.signal.} ## Notifies observers of a committed typed cell value.

  proc tableRowsDidUpdate*(
    tableView: TableView, sender: DynamicAgent, updates: seq[TableRowUpdate]
  ) {.signal.} ## Notifies observers of applied row changes.

protocol TableViewDelegate {.selectorScope: protocol.}:
  ## Customizes cell presentation, interaction, editing, and drops.
  method viewForCell*(
    tableView: TableView, row: int, column: TableColumn
  ): View {.optional.}
    ## Provides a hosted view for a cell instead of standard cell drawing.

  method tableRowHeight*(tableView: TableView, row: int): float32 {.optional.}
    ## Returns the preferred height for a row.

  method isRowEnabled*(tableView: TableView, row: int): bool {.optional.}
    ## Reports whether a row permits interaction.

  method shouldSelectTableRow*(tableView: TableView, row: int): bool {.optional.}
    ## Reports whether a row may be selected.

  method didSelectTableRow*(tableView: TableView, row: int) {.optional.}
    ## Handles selection of a row.

  method shouldTrackCell*(
    tableView: TableView, row: int, column: TableColumn, target: View
  ): bool {.optional.} ## Reports whether a hosted cell view may track pointer input.

  method hitPolicyForCell*(
    tableView: TableView, row: int, column: TableColumn, target: View, event: MouseEvent
  ): CellHitPolicy {.optional.} ## Chooses how cell input is shared with row selection.

  method didActivateRow*(tableView: TableView, row: int) {.optional.}
    ## Handles activation of a row.

  method sortDescriptorsDidChange*(
    tableView: TableView, column: TableColumn, direction: TableSortDirection
  ) {.optional.} ## Applies the requested column sort direction.

  method shouldEditCell*(
    tableView: TableView, row: int, column: TableColumn
  ): bool {.optional.} ## Reports whether editing is allowed for a cell.

  method didBeginEditingCell*(
    tableView: TableView, row: int, column: TableColumn
  ) {.optional.} ## Handles the start of cell editing.

  method fieldEditorFrameForCell*(
    tableView: TableView, row: int, column: TableColumn, proposedFrame: Rect
  ): Rect {.optional.} ## Adjusts the proposed editor frame for a cell.

  method validationErrorForCell*(
    tableView: TableView, row: int, column: TableColumn, value: string
  ): string {.optional.}
    ## Returns an error message for cell text, or an empty string if valid.

  method parseObjectValueForCell*(
    tableView: TableView, row: int, column: TableColumn, value: string
  ): ObjectParseResult {.optional.} ## Parses editor text into a typed cell value.

  method validationErrorForObjectValue*(
    tableView: TableView, row: int, column: TableColumn, value: ObjectValue
  ): ObjectValidationError {.optional.} ## Validates a typed cell value before writeback.

  method didCommitEditingCell*(
    tableView: TableView, row: int, column: TableColumn, value: string
  ) {.optional.} ## Handles committed cell text.

  method didCommitEditingObjectValue*(
    tableView: TableView, row: int, column: TableColumn, value: ObjectValue
  ) {.optional.} ## Handles a committed typed cell value.

  method didCancelEditingCell*(
    tableView: TableView, row: int, column: TableColumn
  ) {.optional.} ## Handles cancellation of cell editing.

  method validateDragOperation*(
    tableView: TableView, info: DraggingInfo
  ): DragOperations {.optional.} ## Returns the allowed operations for an incoming drag.

  method acceptDragOperation*(
    tableView: TableView, info: DraggingInfo
  ): bool {.optional.} ## Accepts an incoming drag and reports success.

  method validateDropOperation*(
    tableView: TableView,
    info: DraggingInfo,
    proposedOperation: DragOperations,
    target: DraggingDropTarget,
    position: DraggingDropPosition,
  ): DragOperations {.optional.}
    ## Returns allowed operations for the proposed drop target and position.

  method acceptDropOperation*(
    tableView: TableView,
    info: DraggingInfo,
    operation: DragOperations,
    target: DraggingDropTarget,
    position: DraggingDropPosition,
  ): bool {.optional.} ## Performs a validated drop at the proposed target and position.

  method tableDropTargetForLocation*(
    tableView: TableView, location: Point, proposedTarget: DraggingDropTarget
  ): DraggingDropTarget {.optional.}
    ## Adjusts the proposed drop target for a pointer location.

  method shouldReorderRows*(
    tableView: TableView, rows: seq[int], target: DraggingDropTarget
  ): bool {.optional.} ## Reports whether the rows may move to the proposed target.

  method performRowReorder*(
    tableView: TableView, rows: seq[int], target: DraggingDropTarget
  ): bool {.optional.} ## Moves the rows to the proposed target and reports success.

  method drawRow*(
    tableView: TableView, context: DrawContext, rect: Rect, row: RowState
  ) {.optional.} ## Draws a row using its current visual state.

protocol TableViewEditingProtocol:
  ## Controls the lifecycle of an editable table cell.
  method shouldBeginEditingCell*(row: int, column: TableColumn): bool
    ## Checks that the cell is valid and editing is permitted.

  method beginEditingCell*(row: int, column: TableColumn): bool
    ## Selects a cell and starts editing when permitted.

  method commitEditingCell*(value: string = ""): bool
    ## Attempts to commit the active cell edit and reports success.

  method cancelEditingCell*(): bool ## Cancels the active cell edit and reports success.

protocol TableViewColumnProtocol:
  ## Coordinates column geometry, sorting, and header interaction.
  method columnAtPoint*(point: Point): TableColumn
    ## Returns the visible column at a horizontal content position.

  method headerHitTest*(point: Point): TableHeaderHit
    ## Identifies a header or resize handle at the pointer location.

  method resizeColumn*(column: TableColumn, width: float32)
    ## Applies a user resize and refreshes dependent layout.

  method moveColumn*(fromIndex, toIndex: int) ## Moves a column within the table order.
  method requestSort*(column: TableColumn, direction: TableSortDirection)
    ## Updates column sorting and preserves selection by row identity.

  method headerMouseDown*(event: MouseEvent): bool
    ## Starts header tracking for resizing, sorting, or reordering.

  method headerMouseDragged*(event: MouseEvent): bool
    ## Updates the active header resize or reorder gesture.

  method headerMouseUp*(event: MouseEvent): bool ## Completes the active header gesture.
  method headerMouseMoved*(event: MouseEvent): bool
    ## Updates pointer feedback over headers and resize handles.

protocol TableViewSelectionProtocol:
  ## Controls cell and column selection and its persistence.
  method shouldSelectCell*(row: int, column: TableColumn): bool
    ## Reports whether the requested cell can be selected.

  method selectCell*(row: int, column: TableColumn)
    ## Selects a cell and updates row, column, and keyboard focus state.

  method setSelectedColumns*(columns: seq[TableColumn])
    ## Applies column selection when enabled and notifies observers.

  method selectionPersistenceString*(): string
    ## Encodes selected rows using stable identities or row indexes.

  method restoreSelectionPersistenceString*(value: string)
    ## Restores row selection from encoded identities or indexes.

protocol TableViewDraggingProtocol:
  ## Starts table drags and validates or accepts incoming drops.
  method beginDraggingRows*(
    rows: seq[int], operations: DragOperations, pasteboardName: string
  ): DraggingSession
    ## Starts a drag carrying row indexes and available stable identities.

  method beginDraggingColumns*(
    columns: seq[TableColumn], operations: DragOperations, pasteboardName: string
  ): DraggingSession ## Starts a drag carrying the selected column identifiers.

  method validateDragging*(info: DraggingInfo): DragOperations
    ## Combines delegate drop validation with row-reorder constraints.

  method acceptDragging*(info: DraggingInfo): bool
    ## Performs a permitted row reorder or delegates an incoming drop.

  method reorderTableRows*(rows: seq[int], target: DraggingDropTarget): bool
    ## Moves the requested rows to a validated drop target.

protocol TableViewPersistenceProtocol:
  ## Captures and restores column configuration by identifier.
  method columnAutosaveRecords*(): seq[TableColumnAutosaveRecord]
    ## Captures column order, widths, visibility, and sort directions.

  method restoreColumnAutosaveRecords*(records: seq[TableColumnAutosaveRecord])
    ## Restores known columns by identity and retains unlisted columns.

protocol TableViewStateProtocol:
  ## Captures and restores column configuration and selection.
  method captureState*(): TableViewState
    ## Captures column configuration and selected row and column identities.

  method restoreState*(state: TableViewState)
    ## Restores column configuration and selection from a snapshot.

protocol TableViewStateStorageProtocol:
  ## Stores named table snapshots independently of the view.
  method saveTableViewState*(name: string, state: TableViewState) {.optional.}
    ## Stores a table snapshot under its autosave name.

  method loadTableViewState*(name: string): TableViewState {.optional.}
    ## Loads a named snapshot, returning empty state when absent.

  method hasTableViewState*(name: string): bool {.optional.}
    ## Reports whether a named snapshot exists.

proc len*(model: TableModel): int
proc rows*(model: TableModel): seq[TableRowValue]
proc columns*(model: TableModel): seq[TableModelColumn]
proc moveRow*(model: TableModel, identifier: string, toIndex: int): bool
proc tableStyle*(tableView: TableView): TableViewStyle
proc tableView*(contentView: TableContentView): TableView
proc tableView*(column: TableColumn): TableView
proc contentView*(tableView: TableView): TableContentView
proc identifier*(column: TableColumn): string
proc width*(column: TableColumn): float32
proc minWidth*(column: TableColumn): float32
proc styleId*(column: TableColumn): string
proc styleClasses*(column: TableColumn): seq[string]
proc columnAt*(tableView: TableView, index: int): TableColumn
proc tableCellText*(tableView: TableView, row: int, column: TableColumn): string
proc selectionLeadIndex*(tableView: TableView): int
proc resolvedRowHeight(tableView: TableView, row: int): float32
proc rowHeight*(tableView: TableView): float32
proc rowHeightForRow*(tableView: TableView, row: int): float32
proc rowEnabled*(tableView: TableView, row: int): bool
proc highlightedIndex*(tableView: TableView): int
proc selectedRanges*(tableView: TableView): seq[Slice[int]]
proc visibleRows*(tableView: TableView): int
proc usesAlternatingRowBackgrounds*(tableView: TableView): bool
proc selectedIndex*(tableView: TableView): int
proc len*(tableView: TableView): int
proc firstVisibleIndex*(tableView: TableView): int
proc tableDropPosition*(info: DraggingInfo): DraggingDropPosition
proc tableContentItemRect*(contentView: TableContentView, itemIndex: int): Rect
proc tableContentItemIndexAtPoint*(contentView: TableContentView, point: Point): int
proc visibleContentRows*(contentView: TableContentView): tuple[first, last: int]

proc tableModelColumnKey*(model: TableModel, column: TableColumn): string =
  model.xColumns.itemColumnKey(column.xIdentifier)

proc compareTableRows(
    a, b: TableRowValue, descriptors: openArray[TableModelSortDescriptor]
): int =
  for descriptor in descriptors:
    if descriptor.direction != tsdNone:
      let
        left = a.getValue(descriptor.columnIdentifier).get(emptyObjectValue())
        right = b.getValue(descriptor.columnIdentifier).get(emptyObjectValue())
      result = compareObjectValues(left, right)
      if result != 0:
        if descriptor.direction == tsdDescending:
          result = -result
        return

proc arrangeSorted(model: TableModel) =
  model.xRows.arrange(
    model.xFilter,
    proc(left, right: int): int =
      compareTableRows(model.xRows[left], model.xRows[right], model.xSortDescriptors),
  )

proc refreshArrangement(model: TableModel) =
  arrangeWithDescriptors(
    model.xRows, model.xFilter, model.xSortDescriptors, model.arrangeSorted()
  )

iterator arrangedItems(model: TableModel): lent TableRowValue =
  model.refreshArrangement()
  for sourceIndex in model.xRows.arrangedIndexes:
    yield model.xRows[sourceIndex]

proc arrangedSourceIndex(model: TableModel, index: int): int =
  model.refreshArrangement()
  model.xRows.arrangedSourceIndex(index)

proc initTableModelStorage*(
    model: TableModel,
    rows: openArray[TableRowValue] = [],
    columns: openArray[TableModelColumn] = [],
) =
  model.xRows = initItemCollection(rows)
  model.xColumns = @columns

proc len*(model: TableModel): int =
  model.refreshArrangement()
  model.xRows.arrangedIndexes.len

proc revision*(model: TableModel): Natural =
  model.xRows.revision

proc sourceLen*(model: TableModel): int =
  model.xRows.len

proc rows*(model: TableModel): seq[TableRowValue] =
  model.xRows.items

proc `rows=`*(model: TableModel, rows: openArray[TableRowValue]) =
  model.xRows.replaceItems(rows)

proc arrangedRows*(model: TableModel): seq[TableRowValue] =
  result = newSeqOfCap[TableRowValue](model.len)
  for row in model.arrangedItems:
    result.add row

proc columns*(model: TableModel): seq[TableModelColumn] =
  model.xColumns

proc `columns=`*(model: TableModel, columns: openArray[TableModelColumn]) =
  model.xColumns = @columns
  model.xRows.invalidate(arrangementChanged = false)

proc sortDescriptors*(model: TableModel): seq[TableModelSortDescriptor] =
  model.xSortDescriptors

proc `sortDescriptors=`*(
    model: TableModel, descriptors: openArray[TableModelSortDescriptor]
) =
  model.xSortDescriptors = @descriptors
  model.xRows.invalidate()

proc filter*(model: TableModel): TableModelFilter =
  model.xFilter

proc `filter=`*(model: TableModel, filter: TableModelFilter) =
  model.xFilter = filter
  model.xRows.invalidate()

proc getRowAt*(model: TableModel, index: int): Option[TableRowValue] =
  let sourceIndex = model.arrangedSourceIndex(index)
  if sourceIndex >= 0:
    some(model.xRows[sourceIndex])
  else:
    none(TableRowValue)

proc rowAt*(model: TableModel, index: int): TableRowValue =
  let found = model.getRowAt(index)
  if found.isSome:
    return found.get()
  tableRow()

proc getRowWithIdentifier*(
    model: TableModel, identifier: string
): Option[TableRowValue] =
  model.xRows.getItemWithIdentifier(identifier)

proc rowWithIdentifier*(
    model: TableModel, identifier: string
): TableRowValue {.raises: [TableModelError].} =
  let found = model.getRowWithIdentifier(identifier)
  if found.isSome:
    return found.get()
  raiseTableModelError("unknown table row identifier: " & identifier)

proc indexOfIdentifier*(model: TableModel, identifier: string): int =
  if identifier.len == 0:
    return -1
  model.refreshArrangement()
  model.xRows.arrangedIndexOfIdentifier(identifier)

proc addRow*(model: TableModel, row: TableRowValue) =
  if row.identifier.len > 0 and model.xRows.sourceIndexOfIdentifier(row.identifier) >= 0:
    raiseTableModelError("duplicate table row identifier: " & row.identifier)
  model.xRows.add row

proc insertRow*(model: TableModel, row: TableRowValue, index: int) =
  if row.identifier.len > 0 and model.xRows.sourceIndexOfIdentifier(row.identifier) >= 0:
    raiseTableModelError("duplicate table row identifier: " & row.identifier)
  discard model.xRows.insert(row, index)

proc removeRow*(model: TableModel, identifier: string): bool {.discardable.} =
  let index = model.xRows.sourceIndexOfIdentifier(identifier)
  if index < 0:
    return false
  model.xRows.delete(index)
  true

proc moveRow*(model: TableModel, identifier: string, toIndex: int): bool =
  let index = model.xRows.sourceIndexOfIdentifier(identifier)
  if index < 0:
    return false
  discard model.xRows.moveItem(index, toIndex)
  true

proc valueForRow*(
    model: TableModel, identifier, columnIdentifier: string
): ObjectValue {.raises: [TableModelError].} =
  model.rowWithIdentifier(identifier).value(columnIdentifier)

proc setValue*(
    model: TableModel, identifier, columnIdentifier: string, value: ObjectValue
) =
  let index = model.xRows.sourceIndexOfIdentifier(identifier)
  if index < 0:
    raiseTableModelError("unknown table row identifier: " & identifier)
  model.xRows[index, columnIdentifier] = value

proc objectValueForTableModelCell*(
    model: TableModel, row: int, column: TableColumn
): ObjectValue =
  let rowValue = model.rowAt(row)
  rowValue.getValue(model.tableModelColumnKey(column)).get(rowValue.objectValue)

proc setObjectValueForTableModelCell*(
    model: TableModel, row: int, column: TableColumn, value: ObjectValue
): bool =
  let sourceIndex = model.arrangedSourceIndex(row)
  if sourceIndex < 0:
    return false
  model.xRows[sourceIndex, model.tableModelColumnKey(column)] = value
  true

proc parseTableModelCellValue*(
    model: TableModel,
    tableView: TableView,
    row: int,
    column: TableColumn,
    value: string,
): ObjectParseResult =
  let current = model.objectValueForTableModelCell(row, column)
  let expectedKind = if current.kind in {ovNil, ovEmpty}: ovString else: current.kind
  let context =
    Control(tableView).objectParseContext.expecting(expectedKind).withRole(ovrTableCell)
  Control(tableView).objectValueFormatter.parseObjectValue(value, context)

proc tableStyleContext*(tableView: TableView): StyleContext =
  controlStyle(
    tableView.xTableRole,
    tableView.widgetStateSet(),
    id = tableView.styleId,
    classes = tableView.styleClasses,
  )

proc tableStyle*(tableView: TableView): TableViewStyle =
  tableView.effectiveAppearance().resolveTableViewStyle(tableView.tableStyleContext())

proc defaultTableStyle*(): TableViewStyle =
  initAppearance().resolveTableViewStyle(controlStyle(srTableView))

proc invalidateTableWidthMeasurement*(tableView: TableView) =
  tableView.xWidthMeasurement.valid = false
  tableView.invalidateIntrinsicContentSize()

proc invalidateColumnWidthMeasurements*(tableView: TableView) =
  if tableView.isNil:
    return
  var needsLayout = false
  for column in tableView.xColumns:
    if column.xSizingPolicy == tcspContentSized:
      column.xWidthMeasurement.valid = false
      needsLayout = true
  if needsLayout:
    tableView.setNeedsLayout()

proc widthSizingMode*(tableView: TableView): TableViewWidthSizingMode =
  tableView.xWidthSizing.mode

proc columnSizing*(tableView: TableView): TableViewColumnSizing =
  tableView.xWidthSizing.columnSizing

proc preferredContentWidth*(tableView: TableView): float32 =
  tableView.xWidthSizing.preferredContentWidth

proc tableRole*(tableView: TableView): StyleRole =
  tableView.xTableRole

proc rowItemRole*(tableView: TableView): StyleRole =
  tableView.xItemRole

template normalizedColumnMetric*(value, fallback: float32): float32 =
  block:
    let metric = value
    if math.isNaN(metric):
      fallback
    else:
      max(metric, 0.0'f32)

proc normalizedMaxWidth*(value, minWidth: float32): float32 =
  max(value.normalizedColumnMetric(defaultTableStyle().columnMaxWidth), minWidth)

proc normalizedWidth*(value: float32, width: TableColWidth): float32 =
  min(
    max(value.normalizedColumnMetric(defaultTableStyle().columnWidth), width.min),
    width.max,
  )

proc tableView*(contentView: TableContentView): TableView =
  contentView.xTableView

proc tableView*(column: TableColumn): TableView =
  column.xTableView

proc scrollView*(tableView: TableView): ScrollView =
  tableView.xScrollView

proc contentView*(tableView: TableView): TableContentView =
  tableView.xContentView

proc initTableBaseChild*(view: View, clipsToBounds: bool) =
  initViewFields(view, rect(0.0, 0.0, 0.0, 0.0))
  view.background = color(0.0, 0.0, 0.0, 0.0)
  view.autoresizingMaskConstraints = false
  view.clipsToBounds = clipsToBounds
  view.acceptsFirstResponder = false

proc rowTextForSummary*(tableView: TableView, row: int): string =
  let column = tableView.columnAt(0)
  tableView.tableCellText(row, column)

proc identifier*(column: TableColumn): string =
  column.xIdentifier

proc title*(column: TableColumn): string =
  column.xTitle

proc width*(column: TableColumn): float32 =
  column.xWidth.resolved

proc minWidth*(column: TableColumn): float32 =
  column.xWidth.min

proc maxWidth*(column: TableColumn): float32 =
  column.xWidth.max

proc alignment*(column: TableColumn): TextAlignment =
  column.xAlignment

proc resizePolicy*(column: TableColumn): TableColumnResizePolicy =
  column.xResizePolicy

proc sizingPolicy*(column: TableColumn): TableColumnSizingPolicy =
  column.xSizingPolicy

proc hidden*(column: TableColumn): bool =
  column.xHidden

proc sortDirection*(column: TableColumn): TableSortDirection =
  column.xSortDirection

proc reuseIdentifier*(column: TableColumn): string =
  if column.xReuseIdentifier.len > 0:
    column.xReuseIdentifier
  else:
    column.identifier()

proc styleId*(column: TableColumn): string =
  column.xStyleId

proc styleClasses*(column: TableColumn): seq[string] =
  column.xStyleClasses

proc userInfo*(column: TableColumn): DynamicAgent =
  column.xUserInfo

proc dataSource*(tableView: TableView): DynamicAgent =
  tableView.xTableDataSource

proc delegate*(tableView: TableView): DynamicAgent =
  tableView.xTableDelegate

proc resolvedRowCount(tableView: TableView): int =
  let source = tableView.dataSource()
  if not source.isNil:
    let count = source.trySendLocal(numberOfRows(), tableView)
    if count.isSome:
      return max(count.get(), 0)
  max(tableView.xRowCount, 0)

proc rowCount*(tableView: TableView): int =
  tableView.resolvedRowCount()

proc columnCount*(tableView: TableView): int =
  tableView.xColumns.len

proc columnAt*(tableView: TableView, index: int): TableColumn =
  if index notin 0 ..< tableView.xColumns.len:
    nil
  else:
    tableView.xColumns[index]

proc columnIndex*(tableView: TableView, identifier: string): int =
  for index, column in tableView.xColumns:
    if column.identifier == identifier:
      return index
  -1

proc columnWithIdentifier*(tableView: TableView, identifier: string): TableColumn =
  let index = tableView.columnIndex(identifier)
  if index < 0:
    nil
  else:
    tableView.xColumns[index]

proc containsColumn*(tableView: TableView, identifier: string): bool =
  tableView.columnIndex(identifier) >= 0

iterator columns*(tableView: TableView): TableColumn =
  for column in tableView.xColumns:
    yield column

iterator visibleColumns*(tableView: TableView): TableColumn =
  for column in tableView.xColumns:
    if not column.hidden():
      yield column

proc columnRect*(tableView: TableView, bounds: Rect, column: TableColumn): Rect =
  if column.isNil:
    return rect(0.0, 0.0, 0.0, 0.0)
  var x = bounds.origin.x
  for current in tableView.xColumns:
    if not current.hidden():
      if current == column:
        let width = min(current.width(), max(bounds.maxX - x, 0.0'f32))
        return rect(x, bounds.origin.y, width, bounds.size.height)
      x += current.width()
  rect(bounds.origin.x, bounds.origin.y, 0.0, 0.0)

proc visibleColumnWidth*(tableView: TableView): float32 =
  for column in tableView.visibleColumns():
    result += column.width()

proc tableHeaderHeight*(tableView: TableView): float32 =
  if not tableView.xHeaderSettings.visible:
    return
  result = tableView.xHeaderSettings.height
  let appearance = tableView.effectiveAppearance()
  if not tableView.xHeaderSettings.hasExplicitHeight:
    result = max(
      appearance.resolveLength(tableView.tableStyleContext(), StyleHeaderHeight, result),
      0.0'f32,
    )

proc showsRowHeader*(tableView: TableView): bool =
  tableView.xRowHeaderSettings.visible

proc visibleRowHeaderWidth*(tableView: TableView): float32 =
  if tableView.showsRowHeader(): tableView.xRowHeaderSettings.width else: 0.0'f32

proc rowHeaderWidth*(tableView: TableView): float32 =
  tableView.xRowHeaderSettings.width

proc rowHeaderTitle*(tableView: TableView): string =
  tableView.xRowHeaderSettings.title

proc defaultTableHeaderChrome*(): TableHeaderChrome =
  TableHeaderChrome(
    headerFill:
      linear(color(0.97, 0.98, 0.99, 0.78), color(0.78, 0.81, 0.86, 0.78), fgaY),
    headerBorderColor: color(0.52, 0.56, 0.62, 0.92),
    cellFill: linear(color(1.0, 1.0, 1.0, 0.64), color(0.82, 0.84, 0.88, 0.64), fgaY),
    hoveredCellFill:
      linear(color(1.0, 1.0, 1.0, 0.72), color(0.74, 0.78, 0.84, 0.72), fgaY),
    pressedCellFill:
      linear(color(0.72, 0.75, 0.80, 0.78), color(0.58, 0.62, 0.68, 0.78), fgaY),
    cellBorderColor: color(0.54, 0.58, 0.64, 0.76),
    textColor: color(0.12, 0.14, 0.18, 1.0),
    sortIndicatorColor: color(0.10, 0.13, 0.18, 0.95),
    insertionIndicatorFill: fill(color(0.16, 0.36, 0.84, 0.95)),
    borderWidth: 1.0'f32,
    sortIndicatorWidth: 24.0'f32,
    insertionWidth: 3.0'f32,
    insertionCapWidth: 9.0'f32,
    insertionCapHeight: 3.0'f32,
    cornerRadius: 5.0'f32,
  )

proc showsHeader*(tableView: TableView): bool =
  tableView.xHeaderSettings.visible

proc tableRowHeaderRect*(tableView: TableView): Rect =
  if not tableView.showsRowHeader():
    return rect(0.0, 0.0, 0.0, 0.0)
  let headerHeight = tableView.tableHeaderHeight()
  rect(
    1.0'f32,
    1.0'f32 + headerHeight,
    tableView.visibleRowHeaderWidth(),
    max(tableView.bounds().h - 2.0'f32 - headerHeight, 0.0'f32),
  )

proc validCell*(tableView: TableView, row: int, column: TableColumn): bool =
  row in 0 ..< tableView.rowCount() and not column.isNil and
    column.tableView() == tableView

proc tableCellText*(tableView: TableView, row: int, column: TableColumn): string =
  if not tableView.validCell(row, column):
    return ""
  let source = tableView.dataSource()
  if source.isNil:
    return ""
  let value = source.trySendLocal(
    objectValueForCell(), (tableView: tableView, row: row, column: column)
  )
  if value.isSome:
    return Control(tableView).formatObjectValue(value.get(), ovrTableCell)
  let text =
    source.trySendLocal(textForCell(), (tableView: tableView, row: row, column: column))
  if text.isSome:
    text.get()
  else:
    ""

proc rowHeaderText*(tableView: TableView, row: int): string =
  if row notin 0 ..< tableView.rowCount():
    return ""
  let source = tableView.dataSource()
  if not source.isNil:
    let text = source.trySendLocal(textForRowHeader(), (tableView: tableView, row: row))
    if text.isSome:
      return text.get()
  $row

proc tableRowIdentifier*(tableView: TableView, row: int): string =
  if row notin 0 ..< tableView.len():
    return ""
  let source = tableView.dataSource()
  if source.isNil:
    return ""
  let identifier =
    source.trySendLocal(identifierForRow(), (tableView: tableView, row: row))
  if identifier.isSome:
    identifier.get()
  else:
    ""

proc directTableRowIndexForIdentifier(tableView: TableView, identifier: string): int =
  if identifier.len == 0:
    return -1
  let source = tableView.dataSource()
  if source.isNil:
    return -1
  let direct = source.trySendLocal(
    rowForIdentifier(), (tableView: tableView, identifier: identifier)
  )
  if direct.isSome and direct.get() in 0 ..< tableView.len():
    return direct.get()
  for row in 0 ..< tableView.len():
    if tableView.tableRowIdentifier(row) == identifier:
      return row
  -1

proc resolveTableRowIdentifier(tableView: TableView, identifier: string): string =
  if identifier.len == 0:
    return ""
  if tableView.directTableRowIndexForIdentifier(identifier) >= 0:
    return identifier
  if identifier in tableView.xRowIdentifierAliases:
    let aliased = tableView.xRowIdentifierAliases[identifier]
    if tableView.directTableRowIndexForIdentifier(aliased) >= 0:
      return aliased
  if not tableView.xRowIdentifierResolver.isNil:
    let resolved = tableView.xRowIdentifierResolver(identifier)
    if tableView.directTableRowIndexForIdentifier(resolved) >= 0:
      return resolved
  ""

proc tableRowIndexForIdentifier*(tableView: TableView, identifier: string): int =
  let resolved = tableView.resolveTableRowIdentifier(identifier)
  if resolved.len == 0:
    -1
  else:
    tableView.directTableRowIndexForIdentifier(resolved)

proc getTableRowIdentifier*(tableView: TableView, row: int): Option[string] =
  let identifier = tableView.tableRowIdentifier(row)
  if identifier.len > 0:
    some(identifier)
  else:
    none(string)

proc requireTableRowIdentifier*(tableView: TableView, row: int): string =
  let identifier = tableView.tableRowIdentifier(row)
  if identifier.len > 0:
    return identifier
  raiseTableModelError("missing table row identifier at row: " & $row)

proc getTableRowIndexForIdentifier*(
    tableView: TableView, identifier: string
): Option[int] =
  let row = tableView.tableRowIndexForIdentifier(identifier)
  if row >= 0:
    some(row)
  else:
    none(int)

proc requireTableRowIndexForIdentifier*(tableView: TableView, identifier: string): int =
  let row = tableView.tableRowIndexForIdentifier(identifier)
  if row >= 0:
    return row
  raiseTableModelError("unknown table row identifier: " & identifier)

proc setRowIdentifierAlias*(
    tableView: TableView, oldIdentifier, newIdentifier: string
) =
  if oldIdentifier.len == 0:
    return
  if newIdentifier.len == 0:
    tableView.xRowIdentifierAliases.del(oldIdentifier)
  else:
    tableView.xRowIdentifierAliases[oldIdentifier] = newIdentifier

proc clearRowIdentifierAliases*(tableView: TableView) =
  tableView.xRowIdentifierAliases.clear()

proc rowIdentifierResolver*(tableView: TableView): TableRowIdentifierResolver =
  tableView.xRowIdentifierResolver

proc `rowIdentifierResolver=`*(
    tableView: TableView, resolver: TableRowIdentifierResolver
) =
  tableView.xRowIdentifierResolver = resolver

proc rowIdentifiersForRows*(tableView: TableView, rows: openArray[int]): seq[string] =
  for row in rows:
    let identifier = tableView.tableRowIdentifier(row)
    if identifier.len == 0:
      return @[]
    result.add identifier

proc tableCellView*(tableView: TableView, row: int, column: TableColumn): View =
  if not tableView.validCell(row, column):
    return nil
  let delegate = tableView.delegate()
  if delegate.isNil:
    return nil
  var cellView: View
  discard delegate.performLocal(
    viewForCell(), (tableView: tableView, row: row, column: column), cellView
  )
  cellView

proc applyCellAccessibility*(
    tableView: TableView, row: int, column: TableColumn, cell: View
) =
  if cell.isNil:
    return
  if not cell.xHasAccessibilityRole:
    cell.accessibilityRole = arCell
  if cell.xAccessibilityLabel.len == 0:
    cell.accessibilityLabel = tableView.tableCellText(row, column)
  cell.xAccessibilityTraits.incl atSelectable

proc dequeueReusableCellView*(tableView: TableView, identifier: string): View =
  if identifier.len == 0:
    return nil
  if identifier notin tableView.xReusableCellViews:
    return nil
  var views = tableView.xReusableCellViews[identifier]
  if views.len == 0:
    return nil
  result = views[^1]
  views.setLen(views.len - 1)
  tableView.xReusableCellViews[identifier] = views
  if not result.isNil:
    result.hidden = false

proc enqueueReusableCellView(tableView: TableView, identifier: string, view: View) =
  if view.isNil or identifier.len == 0:
    return
  view.hidden = true
  if view.superview() != nil:
    view.removeFromSuperview()
  tableView.xReusableCellViews.mgetOrPut(identifier, @[]).add view

proc recycleCellSlot*(tableView: TableView, slot: TableCellSlot) =
  if slot.view.isNil:
    return
  let identifier =
    if slot.column.isNil:
      ""
    else:
      slot.column.reuseIdentifier()
  if identifier.len > 0:
    tableView.enqueueReusableCellView(identifier, slot.view)
  else:
    slot.view.hidden = true
    if slot.view.superview() != nil:
      slot.view.removeFromSuperview()

proc tableRowEnabled(tableView: TableView, row: int): bool =
  if row notin 0 ..< tableView.rowCount():
    return false
  let delegate = tableView.delegate()
  if delegate.isNil:
    return true
  let enabled = delegate.trySendLocal(isRowEnabled(), (tableView: tableView, row: row))
  if enabled.isSome:
    enabled.get()
  else:
    true

proc tableRowSelectable(tableView: TableView, row: int): bool =
  if not tableView.tableRowEnabled(row):
    return false
  let delegate = tableView.delegate()
  if delegate.isNil:
    return true
  let selectable =
    delegate.trySendLocal(shouldSelectTableRow(), (tableView: tableView, row: row))
  if selectable.isSome:
    selectable.get()
  else:
    true

proc viewportSize*(tableView: TableView): Size =
  tableView.xScrollView.viewportSize()

proc invalidateTableRows*(tableView: TableView) =
  tableView.setNeedsLayout()
  tableView.xScrollView.needsDisplay = true
  let scroller = tableView.xScrollView.verticalScroller()
  if not scroller.isNil:
    scroller.needsDisplay = true
  tableView.xContentView.needsDisplay = true
  for rowView in tableView.xContentView.xRowViews:
    rowView.needsDisplay = true
  tableView.needsDisplay = true

proc uncachedRowHeightForRow(tableView: TableView, index: int): float32 =
  if index notin 0 ..< tableView.len():
    return 0.0'f32
  tableView.resolvedRowHeight(index).normalizedRowHeight()

proc usesFixedRowHeights*(tableView: TableView): bool =
  if tableView.xRowSizing.overrides.len > 0:
    return false
  let delegate = tableView.delegate()
  delegate.isNil or not delegate.respondsTo(tableRowHeight())

proc refreshRowHeightCache(tableView: TableView) =
  let defaultHeight = tableView.rowHeight()
  if tableView.xRowHeightMeasurement.matches(defaultHeight):
    return
  tableView.xRowHeightMeasurement.valid = false
  if tableView.xRowHeightMeasurement.computing:
    return
  tableView.xRowHeightMeasurement.computing = true
  try:
    var
      heights: seq[float32]
      offsets: seq[float32]
      offset = 0.0'f32
    for index in 0 ..< tableView.len():
      offsets.add offset
      let height = tableView.uncachedRowHeightForRow(index)
      heights.add height
      offset += height
    tableView.xRowHeightMeasurement.heights = heights
    tableView.xRowHeightMeasurement.offsets = offsets
    tableView.xRowHeightMeasurement.defaultHeight = defaultHeight
    tableView.xRowHeightMeasurement.valid = true
  finally:
    tableView.xRowHeightMeasurement.computing = false

proc invalidateRowHeightCache*(tableView: TableView) =
  tableView.xRowHeightMeasurement.valid = false

proc rowOffset*(tableView: TableView, index: int): float32 =
  if index <= 0:
    return 0.0'f32
  let rowCount = tableView.len()
  if tableView.usesFixedRowHeights():
    return min(index, rowCount).float32 * tableView.rowHeight()
  tableView.refreshRowHeightCache()
  if index >= tableView.xRowHeightMeasurement.heights.len:
    if tableView.xRowHeightMeasurement.heights.len > 0:
      result =
        tableView.xRowHeightMeasurement.offsets[^1] +
        tableView.xRowHeightMeasurement.heights[^1]
  elif index < tableView.xRowHeightMeasurement.offsets.len:
    result = tableView.xRowHeightMeasurement.offsets[index]

proc rowIndexAtContentY(tableView: TableView, y: float32): int =
  let rowCount = tableView.len()
  if rowCount <= 0:
    return -1
  let targetY = max(y, 0.0'f32)
  if tableView.usesFixedRowHeights():
    return min(int(floor(targetY / tableView.rowHeight())), rowCount - 1)

  tableView.refreshRowHeightCache()
  var
    lower = 0
    upper = tableView.xRowHeightMeasurement.heights.len
  while lower < upper:
    let middle = lower + (upper - lower) div 2
    if targetY <
        tableView.xRowHeightMeasurement.offsets[middle] +
        tableView.xRowHeightMeasurement.heights[middle]:
      upper = middle
    else:
      lower = middle + 1
  min(lower, rowCount - 1)

proc contentHeight(tableView: TableView): float32 =
  if tableView.usesFixedRowHeights():
    tableView.len().float32 * tableView.rowHeight()
  else:
    tableView.rowOffset(tableView.len())

proc visibleRowsFrom(tableView: TableView, firstIndex: int, height: float32): int =
  let rowCount = tableView.len()
  if rowCount <= 0 or firstIndex notin 0 ..< rowCount or height <= 0.0'f32:
    return 0
  if tableView.usesFixedRowHeights():
    return
      min(max(int(floor(height / tableView.rowHeight())), 1), rowCount - firstIndex)
  var
    count = 0
    consumed = 0.0'f32
    index = firstIndex
  while index < tableView.len():
    let next = consumed + tableView.rowHeightForRow(index)
    if count > 0 and next > height:
      break
    consumed = next
    inc count
    inc index
  max(count, 1)

proc listContentOffset*(tableView: TableView): Point =
  tableView.xScrollView.contentOffset()

proc setTableContentOffset*(tableView: TableView, offset: Point, invalidate: bool) =
  let scrollView = tableView.xScrollView
  let oldOffset = scrollView.contentOffset()
  scrollView.contentOffset = offset
  let nextOffset = scrollView.contentOffset()
  if oldOffset != nextOffset and invalidate:
    tableView.invalidateTableRows()

proc measuredColumnContentWidth(tableView: TableView, column: TableColumn): float32 =
  let
    appearance = tableView.effectiveAppearance()
    rowStyle = appearance.resolveRowItemStyle(
      controlStyle(
        tableView.xItemRole,
        tableView.widgetStateSet(),
        id = tableView.styleId(),
        classes = tableView.styleClasses(),
      )
    )
    contentStyle = rowStyle.text
    headerStyle = appearance.resolveTextStyle(
      controlStyle(srTableHeaderCell), color(0.0, 0.0, 0.0), insets(0.0)
    )
    contentInsets = contentStyle.insets.horizontal
  if column.xWidthMeasurement.matches(contentStyle, headerStyle):
    return column.xWidthMeasurement.width

  let indicatorWidth =
    if column.sortDirection() == tsdNone:
      0.0'f32
    else:
      defaultTableHeaderChrome().sortIndicatorWidth
  result =
    textNaturalSize(column.title(), headerStyle).width + 16.0'f32 + indicatorWidth
  for row in 0 ..< tableView.len():
    result = max(
      result,
      textNaturalSize(tableView.tableCellText(row, column), contentStyle).width +
        contentInsets,
    )
  result = result.normalizedWidth(column.xWidth)
  column.xWidthMeasurement = TableColWidthMeasurement(
    width: result,
    contentFontName: contentStyle.fontName,
    contentFontSize: contentStyle.fontSize,
    contentHorizontalInsets: contentInsets,
    headerFontName: headerStyle.fontName,
    headerFontSize: headerStyle.fontSize,
    valid: true,
  )

proc setResolvedColumnWidth(column: TableColumn, width: float32): bool =
  let resolved = width.normalizedWidth(column.xWidth)
  if abs(column.xWidth.resolved - resolved) <= TableColumnWidthEpsilon:
    return
  column.xWidth.resolved = resolved
  true

proc hasUserResizedFlexibleColumn(tableView: TableView): bool =
  for column in tableView.visibleColumns():
    if column.sizingPolicy() == tcspFlexible and column.xWidth.userResized:
      return true

proc distributeFlexibleColumnWidths(
    tableView: TableView, availableWidth: float32
): bool =
  var
    flexible: seq[TableColumn]
    occupiedWidth = 0.0'f32
  for column in tableView.visibleColumns():
    if column.sizingPolicy() == tcspFlexible:
      flexible.add column
    else:
      occupiedWidth += column.width()
  if flexible.len == 0 or tableView.hasUserResizedFlexibleColumn():
    return

  var flexibleWidth = 0.0'f32
  for column in flexible:
    flexibleWidth += column.width()
  var
    remaining = max(availableWidth - occupiedWidth, 0.0'f32) - flexibleWidth
    adjustable = flexible
  while abs(remaining) > TableColumnWidthEpsilon and adjustable.len > 0:
    let adjustment = remaining / adjustable.len.float32
    var
      applied = 0.0'f32
      nextAdjustable: seq[TableColumn]
    for column in adjustable:
      let
        oldWidth = column.width()
        nextWidth = (oldWidth + adjustment).normalizedWidth(column.xWidth)
      if column.setResolvedColumnWidth(nextWidth):
        result = true
      applied += nextWidth - oldWidth
      let canAdjust =
        if remaining > 0.0'f32:
          nextWidth < column.xWidth.max - TableColumnWidthEpsilon
        else:
          nextWidth > column.xWidth.min + TableColumnWidthEpsilon
      if canAdjust:
        nextAdjustable.add column
    if abs(applied) <= TableColumnWidthEpsilon:
      break
    remaining -= applied
    adjustable = nextAdjustable

proc resolveNaturalColumnWidths(tableView: TableView): bool =
  let hasUserResizedFlexibleColumn =
    tableView.xWidthSizing.columnSizing == tvcsFill and
    tableView.hasUserResizedFlexibleColumn()
  for column in tableView.visibleColumns():
    let width =
      case column.sizingPolicy()
      of tcspFixed:
        column.xWidth.preferred
      of tcspFlexible:
        if hasUserResizedFlexibleColumn and not column.xWidth.userResized:
          column.xWidth.resolved
        else:
          column.xWidth.preferred
      of tcspContentSized:
        tableView.measuredColumnContentWidth(column)
    if column.setResolvedColumnWidth(width):
      result = true

proc noteResolvedColumnWidthsChanged(tableView: TableView) =
  tableView.xContentView.needsDisplay = true
  tableView.xScrollView.needsDisplay = true
  tableView.needsDisplay = true

proc resolveColumnSizing(tableView: TableView, availableWidth: float32): bool =
  result = tableView.resolveNaturalColumnWidths()
  if tableView.xWidthSizing.columnSizing == tvcsFill and
      tableView.distributeFlexibleColumnWidths(availableWidth):
    result = true
  if result:
    tableView.noteResolvedColumnWidthsChanged()

proc resolvedTableContentLayout*(tableView: TableView): TableContentLayout =
  let rowHeaderWidth = tableView.visibleRowHeaderWidth()
  result.scrollFrame = rect(
    1.0'f32 + rowHeaderWidth,
    1.0'f32,
    max(tableView.bounds().size.width - 2.0'f32 - rowHeaderWidth, 0.0'f32),
    max(tableView.bounds().size.height - 2.0'f32, 0.0'f32),
  )
  let contentHeight = tableView.contentHeight()
  if tableView.resolveNaturalColumnWidths():
    tableView.noteResolvedColumnWidthsChanged()
  var availableWidth = tableView.xScrollView.viewportSizeForDocumentSize(
    result.scrollFrame.size, initSize(tableView.visibleColumnWidth(), contentHeight)
  ).width
  for _ in 0 ..< MaxTableContentLayoutPasses:
    discard tableView.resolveColumnSizing(availableWidth)
    let
      documentWidth = max(tableView.visibleColumnWidth(), availableWidth)
      viewportSize = tableView.xScrollView.viewportSizeForDocumentSize(
        result.scrollFrame.size, initSize(documentWidth, contentHeight)
      )
    result.documentSize = initSize(documentWidth, contentHeight)
    if abs(viewportSize.width - availableWidth) <= TableColumnWidthEpsilon:
      break
    availableWidth = viewportSize.width

proc layoutTableContentIfNeeded*(tableView: TableView) =
  if tableView.needsLayout() or tableView.needsUpdateConstraints():
    tableView.layoutSubtreeIfNeeded()

proc scrollContentRectToVisible(tableView: TableView, rect: Rect) =
  let oldFirst = tableView.firstVisibleIndex()
  if rect.isEmpty:
    return
  discard tableView.xScrollView.scrollRectToVisible(rect)
  if tableView.firstVisibleIndex() != oldFirst:
    tableView.invalidateTableRows()

proc scrollItemToVisible*(tableView: TableView, itemIndex: int) =
  if itemIndex < 0 or itemIndex >= tableView.len():
    return
  var rect = tableView.xContentView.tableContentItemRect(itemIndex)
  let offset = tableView.listContentOffset()
  rect.x = offset.x
  rect.w = tableView.viewportSize().width
  tableView.scrollContentRectToVisible(rect)

proc scrollCellToVisible*(tableView: TableView, row: int, column: TableColumn) =
  if row < 0 or row >= tableView.len() or column.isNil:
    return
  let
    width = max(tableView.visibleColumnWidth(), tableView.viewportSize().width)
    rowRect =
      rect(0.0'f32, tableView.rowOffset(row), width, tableView.rowHeightForRow(row))
    columnRect = tableView.columnRect(rowRect, column)
  tableView.scrollContentRectToVisible(columnRect)

proc selectionContains*(tableView: TableView, index: int): bool =
  for selectedIndex in tableView.xRowSelection.indexes:
    if selectedIndex == index:
      return true
  false

proc tableRowState(tableView: TableView, index: int): RowState =
  if index notin 0 ..< tableView.len():
    initRowState(-1, "", states = {})
  else:
    var rowStates: set[WidgetState] = {}
    if not tableView.rowEnabled(index):
      rowStates.incl(ssDisabled)
    if tableView.selectionContains(index):
      rowStates.incl(ssSelected)
    if index == tableView.highlightedIndex():
      rowStates.incl(ssHovered)
    if tableView.usesAlternatingRowBackgrounds() and index mod 2 == 1:
      rowStates.incl(ssAlternating)
    if index == tableView.xPressedIndex:
      rowStates.incl(ssPressed)
    if ssFocused in tableView.widgetStateSet():
      rowStates.incl(ssFocused)
    initRowState(index, tableView.rowTextForSummary(index), states = rowStates)

proc drawingTableRowState*(tableView: TableView, row: RowState): RowState =
  result = row
  if tvoFocusedRowHighlight notin tableView.xOptions and
      row.index == tableView.selectionLeadIndex():
    result.states.excl(ssSelected)

proc firstSelectedIndex*(tableView: TableView, indexes: openArray[int]): int =
  if indexes.len == 0:
    -1
  else:
    indexes[0]

proc validTableIndex*(tableView: TableView, index: int): bool =
  index >= 0 and index < tableView.len()

proc selectionLeadIndex*(tableView: TableView): int =
  if tableView.validTableIndex(tableView.xRowSelection.lead):
    tableView.xRowSelection.lead
  else:
    tableView.selectedIndex()

proc clearFocusedColumn*(tableView: TableView) =
  if tableView.xFocusedColumn.isNil:
    return
  tableView.xFocusedColumn = nil
  tableView.needsDisplay = true

proc resolvedRowHeight(tableView: TableView, row: int): float32 =
  if row notin 0 ..< tableView.rowCount():
    return tableView.rowHeight()
  if row in tableView.xRowSizing.overrides:
    return tableView.xRowSizing.overrides[row]
  let delegate = tableView.delegate()
  if not delegate.isNil:
    let height =
      delegate.trySendLocal(tableRowHeight(), (tableView: tableView, row: row))
    if height.isSome:
      return height.get()
  tableView.rowHeight()

proc tableRowDidActivate*(tableView: TableView, row: int) =
  let delegate = tableView.delegate()
  if delegate.isNil:
    return
  discard
    delegate.sendLocalIfHandled(didActivateRow(), (tableView: tableView, row: row))

proc clickedRow*(tableView: TableView): int =
  tableView.xClickedRow

proc clickedColumn*(tableView: TableView): TableColumn =
  tableView.xClickedColumn

proc clickedColumnIndex*(tableView: TableView): int =
  if tableView.xClickedColumn.isNil:
    -1
  else:
    tableView.columnIndex(tableView.xClickedColumn.identifier())

proc focusedColumn*(tableView: TableView): TableColumn =
  tableView.xFocusedColumn

proc focusedColumnIndex*(tableView: TableView): int =
  if tableView.xFocusedColumn.isNil:
    -1
  else:
    tableView.columnIndex(tableView.xFocusedColumn.identifier())

proc rowHeight*(tableView: TableView): float32 =
  result = tableView.xRowSizing.height
  let appearance = tableView.effectiveAppearance()
  if not tableView.xRowSizing.hasExplicitHeight:
    result =
      appearance.resolveLength(tableView.tableStyleContext(), StyleRowHeight, result)
  result = result.normalizedRowHeight()

proc rowHeightForRow*(tableView: TableView, row: int): float32 =
  if row notin 0 ..< tableView.len():
    return 0.0'f32
  if tableView.usesFixedRowHeights():
    return tableView.rowHeight()
  tableView.uncachedRowHeightForRow(row)

proc rowEnabled*(tableView: TableView, row: int): bool =
  tableView.tableRowEnabled(row)

proc rowSelectable*(tableView: TableView, row: int): bool =
  tableView.tableRowSelectable(row)

proc highlightedIndex*(tableView: TableView): int =
  tableView.xHighlightedIndex

proc selectedIndexes*(tableView: TableView): seq[int] =
  tableView.xRowSelection.indexes

proc selectedRange*(tableView: TableView): Slice[int] =
  let ranges = tableView.selectedRanges()
  if ranges.len == 0:
    0 .. -1
  else:
    ranges[0]

proc selectedRanges*(tableView: TableView): seq[Slice[int]] =
  if tableView.xRowSelection.indexes.len == 0:
    return @[]
  var
    firstIndex = tableView.xRowSelection.indexes[0]
    previousIndex = firstIndex
  for offset in 1 ..< tableView.xRowSelection.indexes.len:
    let index = tableView.xRowSelection.indexes[offset]
    if index == previousIndex + 1:
      previousIndex = index
    else:
      result.add firstIndex .. previousIndex
      firstIndex = index
      previousIndex = index
  result.add firstIndex .. previousIndex

proc selectionMode*(tableView: TableView): TableSelectionMode =
  tableView.xRowSelection.mode

proc visibleRows*(tableView: TableView): int =
  tableView.xRowSizing.visibleRows

proc usesAlternatingRowBackgrounds*(tableView: TableView): bool =
  tvoAlternatingRowBackgrounds in tableView.xOptions

proc showsRowSeparators*(tableView: TableView): bool =
  tvoRowSeparators in tableView.xOptions

proc allowsRowReordering*(tableView: TableView): bool =
  tvoRowReordering in tableView.xOptions

proc selectedIndex*(tableView: TableView): int =
  tableView.xRowSelection.index

proc rowItemRect*(tableView: TableView, itemIndex: int): Rect =
  tableView.layoutTableContentIfNeeded()
  let contentView = tableView.contentView()
  let contentRect = contentView.tableContentItemRect(itemIndex)
  if contentRect.isEmpty:
    return rect(0.0, 0.0, 0.0, 0.0)
  let visibleRect =
    contentView.rectToView(contentRect, tableView).intersection(tableView.bounds())
  if visibleRect.size.height < tableView.rowHeightForRow(itemIndex) or
      visibleRect.isEmpty:
    rect(0.0, 0.0, 0.0, 0.0)
  else:
    visibleRect

proc rowItemIndexAtPoint*(tableView: TableView, point: Point): int =
  tableView.layoutTableContentIfNeeded()
  if tableView.showsRowHeader() and tableView.tableRowHeaderRect().contains(point):
    let contentView = tableView.contentView()
    let index =
      tableView.rowIndexAtContentY(contentView.pointFromView(point, tableView).y)
    if index in 0 ..< tableView.len():
      return index
    return -1
  let contentView = tableView.contentView()
  contentView.tableContentItemIndexAtPoint(contentView.pointFromView(point, tableView))

proc len*(tableView: TableView): int =
  tableView.rowCount()

proc visibleItemCount*(tableView: TableView): int =
  if tableView.len() <= 0:
    return 0
  let
    contentHeight = tableView.viewportSize().height
    visibleFromBounds =
      tableView.visibleRowsFrom(tableView.firstVisibleIndex(), contentHeight)
    preferredRows =
      if visibleFromBounds > 0:
        visibleFromBounds
      else:
        tableView.visibleRows()
  visibleRowItemCount(tableView.len(), preferredRows)

proc firstVisibleIndex*(tableView: TableView): int =
  tableView.rowIndexAtContentY(tableView.listContentOffset().y)

proc visibleRowSummaries*(tableView: TableView): seq[TableVisibleRowSummary] =
  tableView.layoutTableContentIfNeeded()
  let
    contentView = tableView.contentView()
    rows = contentView.visibleContentRows()
  for index in rows.first ..< rows.last:
    let row = tableView.tableRowState(index)
    let contentRect = contentView.tableContentItemRect(index)
    let rect =
      contentView.rectToView(contentRect, tableView).intersection(tableView.bounds())
    if not rect.isEmpty:
      result.add TableVisibleRowSummary(
        index: row.index,
        text: row.text,
        rect: rect,
        states: row.states * {ssDisabled, ssFocused, ssSelected, ssHovered},
      )

iterator visibleRowViews*(
    tableView: TableView
): tuple[index: int, view: View, rect: Rect] =
  tableView.layoutTableContentIfNeeded()
  let contentView = tableView.contentView()
  for rowView in contentView.xRowViews:
    yield (rowView.xRow.index, View(rowView), rowView.frame())

proc scrollRows*(tableView: TableView, delta: int) =
  if delta == 0:
    return
  let oldFirst = tableView.firstVisibleIndex()
  let nextFirst = max(oldFirst + delta, 0)
  let offset = tableView.listContentOffset()
  tableView.setTableContentOffset(
    initPoint(offset.x, tableView.rowOffset(nextFirst)), false
  )
  if tableView.firstVisibleIndex() != oldFirst:
    tableView.invalidateTableRows()

proc allowsColumnSelection*(tableView: TableView): bool =
  tvoColumnSelection in tableView.xOptions

proc tracksPointerRowHighlights*(tableView: TableView): bool =
  tvoPointerRowHighlights in tableView.xOptions

proc tracksPointerColumnHighlights*(tableView: TableView): bool =
  tvoPointerColumnHighlights in tableView.xOptions

proc showsFocusedRowHighlight*(tableView: TableView): bool =
  tvoFocusedRowHighlight in tableView.xOptions

proc showsFocusedColumnHighlight*(tableView: TableView): bool =
  tvoFocusedColumnHighlight in tableView.xOptions

proc selectedColumns*(tableView: TableView): seq[TableColumn] =
  tableView.xSelectedColumns

proc draggingSession*(tableView: TableView): DraggingSession =
  tableView.xDragging.session

proc beginDraggingRows*(
    tableView: TableView,
    rows: openArray[int],
    operations: DragOperations = {dgoMove},
    pasteboardName: string = DragPasteboardName,
): DraggingSession =
  let resolved = tableView.trySendLocal(
    beginDraggingRows(),
    (rows: @rows, operations: operations, pasteboardName: pasteboardName),
  )
  if resolved.isSome:
    resolved.get()
  else:
    nil

proc beginDraggingColumns*(
    tableView: TableView,
    columns: openArray[TableColumn],
    operations: DragOperations = {dgoMove},
    pasteboardName: string = DragPasteboardName,
): DraggingSession =
  let resolved = tableView.trySendLocal(
    beginDraggingColumns(),
    (columns: @columns, operations: operations, pasteboardName: pasteboardName),
  )
  if resolved.isSome:
    resolved.get()
  else:
    nil

proc draggingInfo*(tableView: TableView): DraggingInfo =
  if tableView.xDragging.session.isNil:
    DraggingInfo()
  else:
    tableView.xDragging.session.draggingInfo()

proc withDropTarget*(
    info: DraggingInfo, row = -1, column: TableColumn = nil, position = ddpOn
): DraggingInfo =
  if row >= 0 and not column.isNil:
    info.withDropTarget(initCellDropTarget(row, column.identifier()))
  elif row >= 0:
    info.withDropTarget(initRowDropTarget(row, position = position))
  elif not column.isNil:
    info.withDropTarget(initColumnDropTarget(column.identifier(), position = position))
  else:
    info.withDropTarget(initDraggingDropTarget())

func tableDropPositionForAxis(
    value, minValue, maxValue: float32
): DraggingDropPosition =
  let edge = (maxValue - minValue) * 0.25'f32
  if value <= minValue + edge:
    ddpBefore
  elif value >= maxValue - edge:
    ddpAfter
  else:
    ddpOn

func tableDropPositionForRow*(location: Point, rect: Rect): DraggingDropPosition =
  tableDropPositionForAxis(location.y, rect.minY, rect.maxY)

func tableInsertionPositionForRow*(location: Point, rect: Rect): DraggingDropPosition =
  if location.y < rect.origin.y + rect.size.height * 0.5'f32: ddpBefore else: ddpAfter

func tableDropPositionForColumn*(location: Point, rect: Rect): DraggingDropPosition =
  tableDropPositionForAxis(location.x, rect.minX, rect.maxX)

proc draggingTableRows*(tableView: TableView): bool =
  let session = tableView.draggingSession()
  not session.isNil and session.state() == dssActive and
    session.pasteboard().stringForType(TablePasteboardTypeRows).len > 0

proc activeDropTarget*(tableView: TableView): DraggingDropTarget =
  if not tableView.xDragging.session.isNil and
      tableView.xDragging.session.state() == dssActive:
    return tableView.xDragging.session.dropTarget()
  tableView.xDragging.dropTarget

proc currentDropTarget*(tableView: TableView): DraggingDropTarget =
  tableView.activeDropTarget()

proc joinRowIndexes*(rows: openArray[int]): string =
  for index, row in rows:
    if index > 0:
      result.add ","
    result.add $row

proc joinIdentifiers*(identifiers: openArray[string]): string =
  for index, identifier in identifiers:
    if index > 0:
      result.add ","
    result.add identifier

proc parseRowIndexes(value: string): seq[int] =
  for part in value.split(","):
    let text = part.strip()
    if text.len > 0:
      try:
        result.add parseInt(text)
      except ValueError:
        discard

proc parseIdentifiers*(value: string): seq[string] =
  for part in value.split(","):
    let identifier = part.strip()
    if identifier.len > 0:
      result.add identifier

proc tableDraggingRows*(info: DraggingInfo): seq[int] =
  if info.pasteboard.isNil:
    return @[]
  parseRowIndexes(info.pasteboard.stringForType(TablePasteboardTypeRows))

proc tableDraggingRowIdentifiers*(info: DraggingInfo): seq[string] =
  if info.pasteboard.isNil:
    return @[]
  parseIdentifiers(info.pasteboard.stringForType(TablePasteboardTypeRowIdentifiers))

proc tableDraggingColumns*(info: DraggingInfo): seq[string] =
  if info.pasteboard.isNil:
    return @[]
  parseIdentifiers(info.pasteboard.stringForType(TablePasteboardTypeColumns))

proc tableDropRow*(info: DraggingInfo): int =
  info.dropTarget.row

proc tableDropColumn*(info: DraggingInfo): string =
  info.dropTarget.column

proc tableDropPosition*(info: DraggingInfo): DraggingDropPosition =
  info.dropTarget.position

proc normalizedReorderRows*(tableView: TableView, rows: openArray[int]): seq[int] =
  for row in rows:
    if row in 0 ..< tableView.len() and row notin result:
      result.add row
  result.sort()

func adjustedReorderInsertionIndex*(rows: openArray[int], insertionIndex: int): int =
  result = max(insertionIndex, 0)
  for row in rows:
    if row < insertionIndex:
      dec result
  result = max(result, 0)

func rowsAreContiguous(rows: openArray[int]): bool =
  if rows.len <= 1:
    return true
  for index in 1 ..< rows.len:
    if rows[index] != rows[index - 1] + 1:
      return false
  true

func reorderWouldChange(rows: openArray[int], adjustedInsertionIndex: int): bool =
  rows.len > 0 and not (rows.rowsAreContiguous() and adjustedInsertionIndex == rows[0])

proc insertionIndexForDropTarget*(
    tableView: TableView, target: DraggingDropTarget
): int =
  if target.kind != ddtRow:
    return -1
  let row = max(0, min(target.row, tableView.len()))
  case target.position
  of ddpAfter:
    min(row + 1, tableView.len())
  of ddpOn, ddpBefore:
    row

proc canReorderRows*(
    tableView: TableView, rows: openArray[int], target: DraggingDropTarget
): bool =
  if not tableView.allowsRowReordering():
    return false
  let normalizedRows = tableView.normalizedReorderRows(rows)
  if normalizedRows.len == 0:
    return false
  let insertionIndex = tableView.insertionIndexForDropTarget(target)
  if insertionIndex < 0:
    return false
  let adjustedIndex = adjustedReorderInsertionIndex(normalizedRows, insertionIndex)
  if not normalizedRows.reorderWouldChange(adjustedIndex):
    return false

  let delegate = tableView.delegate()
  if not delegate.isNil:
    let allowed = delegate.trySendLocal(
      shouldReorderRows(), (tableView: tableView, rows: normalizedRows, target: target)
    )
    if allowed.isSome:
      return allowed.get()
  true

proc canReorderTableModelRows*(model: TableModel): bool =
  model.xSortDescriptors.len == 0 and model.xFilter.isNil and
    model.len() == model.sourceLen()

proc isInternalTableRowDrag(tableView: TableView, info: DraggingInfo): bool =
  info.source == DynamicAgent(tableView) and info.tableDraggingRows().len > 0

proc isTableRowReorderDrag*(tableView: TableView, info: DraggingInfo): bool =
  tableView.isInternalTableRowDrag(info) and tableView.allowsRowReordering() and
    info.dropTarget.kind == ddtRow

proc canAcceptTableRowReorder*(tableView: TableView, info: DraggingInfo): bool =
  tableView.isTableRowReorderDrag(info) and dgoMove in info.allowedOperations and
    tableView.canReorderRows(info.tableDraggingRows(), info.dropTarget)

proc findCellSlot*(
    slots: openArray[TableCellSlot], row: int, column: TableColumn
): int =
  for index, slot in slots:
    if slot.row == row and slot.column == column:
      return index
  -1

proc clearTableCellSlots*(tableView: TableView) =
  for slot in tableView.xCellSlots:
    tableView.recycleCellSlot(slot)
  tableView.xCellSlots.setLen(0)

proc recycleVisibleCellViews*(tableView: TableView) =
  tableView.clearTableCellSlots()

proc hasHostedCell*(tableView: TableView, row: int, column: TableColumn): bool =
  tableView.xCellSlots.findCellSlot(row, column) >= 0

proc tableContentItemRect*(contentView: TableContentView, itemIndex: int): Rect =
  let tableView = contentView.tableView()
  if itemIndex notin 0 ..< tableView.len():
    return rect(0.0, 0.0, 0.0, 0.0)
  rect(
    0.0'f32,
    tableView.rowOffset(itemIndex),
    max(contentView.bounds().size.width, 0.0'f32),
    tableView.rowHeightForRow(itemIndex),
  )

proc tableContentItemIndexAtPoint*(contentView: TableContentView, point: Point): int =
  let tableView = contentView.tableView()
  if not contentView.bounds().contains(point):
    return -1
  let index = tableView.rowIndexAtContentY(point.y)
  if index < 0 or index >= tableView.len():
    return -1
  index

proc visibleContentRows*(contentView: TableContentView): tuple[first, last: int] =
  let tableView = contentView.tableView()
  if tableView.len() <= 0:
    return (0, 0)
  let visible = contentView.visibleRect()
  if visible.isEmpty:
    return (0, 0)
  result.first = max(tableView.rowIndexAtContentY(visible.minY), 0)
  result.last = result.first
  while result.last < tableView.len() and tableView.rowOffset(result.last) < visible.maxY:
    inc result.last
  if result.last < result.first:
    result.last = result.first

proc configureRowView*(rowView: TableRowView, itemIndex: int) =
  let tableView = rowView.xTableView
  let nextRow = tableView.tableRowState(itemIndex)
  if rowView.xRow != nextRow:
    rowView.xRow = nextRow
    rowView.needsDisplay = true
  rowView.setFrameFromLayout(tableView.xContentView.tableContentItemRect(itemIndex))

proc `rowCount=`*(tableView: TableView, count: int) =
  let nextCount = max(count, 0)
  if tableView.xRowCount == nextCount:
    return
  tableView.xRowCount = nextCount
  tableView.requestTableReload()

proc `dataSource=`*(tableView: TableView, dataSource: DynamicAgent) =
  if tableView.xTableDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(TableViewDataSource)
  tableView.clearTableCellSlots()
  tableView.xTableDataSource = dataSource
  tableView.requestTableReload()

proc `dataSource=`*(tableView: TableView, dataSource: Responder) =
  tableView.dataSource = DynamicAgent(dataSource)

proc `delegate=`*(tableView: TableView, delegate: DynamicAgent) =
  if tableView.xTableDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(TableViewDelegate)
  tableView.clearTableCellSlots()
  tableView.xTableDelegate = delegate
  tableView.requestTableReload()

proc `delegate=`*(tableView: TableView, delegate: Responder) =
  tableView.delegate = DynamicAgent(delegate)
