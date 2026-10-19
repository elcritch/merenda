## Cell focus, validation, field-editor hosting, and editing lifecycle for tables.
## Shared storage, geometry, and cache helpers live in tablecore.

import std/options

import sigils/core

import ../accessibility/accessibilityprotocols
import ../app/windows
import ../controls/controls
import ../foundation/events
import ../foundation/objectvalues
import ../foundation/selectors
import ../foundation/types
import ../themes
import ../text/fieldeditors
import ../text/textviews
from ../view/viewgeometry import setFrameFromLayout
import ../view/views
import ./tablecore
import ./tablepresentation

proc editingState*(tableView: TableView): TableEditingState =
  tableView.xCellEditing.state

proc editingValidationError*(tableView: TableView): string =
  tableView.xCellEditing.state.validationError

proc editingValidation*(tableView: TableView): ObjectValidationError =
  tableView.xCellEditing.state.validation

proc tableCellHitPolicy*(
    tableView: TableView, row: int, column: TableColumn, target: View, event: MouseEvent
): CellHitPolicy =
  if column.isNil or row notin 0 ..< tableView.rowCount():
    return chpDefault
  let delegate = tableView.delegate()
  if delegate.isNil:
    return chpDefault
  let explicitPolicy = delegate.trySendLocal(
    hitPolicyForCell(),
    (tableView: tableView, row: row, column: column, target: target, event: event),
  )
  if explicitPolicy.isSome and explicitPolicy.get() != chpDefault:
    return explicitPolicy.get()
  let shouldTrack = delegate.trySendLocal(
    shouldTrackCell(), (tableView: tableView, row: row, column: column, target: target)
  )
  if shouldTrack.isSome:
    if shouldTrack.get(): chpTrackCell else: chpSelectRow
  else:
    chpDefault

proc clearEditingSurface*(tableView: TableView) =
  tableView.xCellEditing.surface = default(TableEditingSurface)

proc selectableCellColumns(tableView: TableView, row: int): seq[TableColumn] =
  if row notin 0 ..< tableView.len():
    return @[]
  for column in tableView.visibleColumns():
    if tableView.shouldSelectCell(row, column):
      result.add column

proc visibleCellColumnPosition(
    tableView: TableView,
    row: int,
    column: TableColumn,
    columns: openArray[TableColumn],
    direction: int,
): int =
  if column.isNil:
    return (if direction >= 0: -1 else: columns.len)
  for index, current in columns:
    if current == column:
      return index
  if column.tableView() != tableView:
    return (if direction >= 0: -1 else: columns.len)

  var before = 0
  for current in tableView.xColumns:
    if current == column:
      break
    if not current.hidden() and tableView.shouldSelectCell(row, current):
      inc before
  if direction >= 0:
    before - 1
  else:
    before

proc setFocusedCellColumn*(
    tableView: TableView, row: int, column: TableColumn, notifySelection = true
): bool =
  if row notin 0 ..< tableView.len() or column.isNil or column.hidden() or
      not tableView.shouldSelectCell(row, column):
    return false
  let
    previousColumn = tableView.xFocusedColumn
    previousSelectedColumns = tableView.xSelectedColumns
  tableView.xFocusedColumn = column
  if tvoColumnSelection in tableView.xOptions:
    tableView.xSelectedColumns = @[column]
  if previousColumn != tableView.xFocusedColumn or
      previousSelectedColumns != tableView.xSelectedColumns:
    if not tableView.window().isNil:
      tableView.scrollCellToVisible(row, column)
    tableView.needsDisplay = true
    if notifySelection and previousSelectedColumns != tableView.xSelectedColumns:
      emit tableView.selectionDidChange(DynamicAgent(tableView))
      tableView.postAccessibilityNotification(anSelectionChanged)
  true

proc moveFocusedCell*(tableView: TableView, delta: int): bool =
  if delta == 0 or tableView.selectionMode() == tsmNone:
    return false
  let row = tableView.selectionLeadIndex()
  if row < 0:
    return false
  let columns = tableView.selectableCellColumns(row)
  if columns.len < 2:
    return false
  let
    step = if delta < 0: -1 else: 1
    position =
      tableView.visibleCellColumnPosition(row, tableView.xFocusedColumn, columns, step)
    nextIndex = max(0, min(position + step, columns.len - 1))
  tableView.setFocusedCellColumn(row, columns[nextIndex])

proc beginEditingFocusedCell*(tableView: TableView): bool =
  if tableView.xFocusedColumn.isNil:
    return false
  let row = tableView.selectionLeadIndex()
  if row < 0:
    return false
  let column = tableView.xFocusedColumn
  if tableView.shouldBeginEditingCell(row, column):
    return tableView.beginEditingCell(row, column)
  false

func isTableTypeToEditEvent(event: KeyEvent): bool =
  event.modifiers - {kmShift} == {} and event.text.isInsertableText()

proc beginEditingFocusedCellWithText*(tableView: TableView, event: KeyEvent): bool =
  if not event.isTableTypeToEditEvent():
    return false
  if not tableView.beginEditingFocusedCell():
    return false
  let owner = tableView.window()
  if owner of Window:
    discard Window(owner).dispatchKeyDown(event)
  else:
    let editor = Control(tableView).currentEditor()
    if not editor.isNil:
      discard editor.keyDown(event)
  true

proc prepareEditingSurface(tableView: TableView): bool =
  if not tableView.xCellEditing.state.active:
    return false
  tableView.clearEditingSurface()

  tableView.scrollItemToVisible(tableView.xCellEditing.state.row)
  tableView.layoutSubtreeIfNeeded()

  let cellView = tableView.visibleCellView(
    tableView.xCellEditing.state.row, tableView.xCellEditing.state.column
  )
  if not cellView.isNil:
    tableView.xCellEditing.surface.hostView = cellView
    if cellView of Control:
      tableView.xCellEditing.surface.cell = Control(cellView).cell()
    return true

  let row = tableView.visibleRowView(tableView.xCellEditing.state.row)
  if row.view.isNil:
    return false
  tableView.xCellEditing.surface.hostView = row.view
  tableView.xCellEditing.surface.isRowView = true
  true

proc fieldEditorFrameForEditing(tableView: TableView): Rect =
  if tableView.xCellEditing.surface.hostView.isNil:
    return rect(0.0, 0.0, 0.0, 0.0)
  if tableView.xCellEditing.surface.isRowView:
    let row = tableView.visibleRowView(tableView.xCellEditing.state.row)
    let rowBounds = rect(0.0, 0.0, row.rect.size.width, row.rect.size.height)
    let cellFrame = tableView.columnRect(rowBounds, tableView.xCellEditing.state.column)
    let delegate = tableView.delegate()
    if not delegate.isNil:
      let frame = delegate.trySendLocal(
        fieldEditorFrameForCell(),
        (
          tableView: tableView,
          row: tableView.xCellEditing.state.row,
          column: tableView.xCellEditing.state.column,
          proposedFrame: cellFrame,
        ),
      )
      if frame.isSome:
        return frame.get()
    let style = tableView.effectiveAppearance().resolveRowItemStyle(
        controlStyle(
          tableView.xItemRole,
          tableView.widgetStateSet(),
          id = tableView.styleId(),
          classes = tableView.styleClasses(),
        )
      )
    return style.rowItemTextRect(cellFrame)
  tableView.xCellEditing.surface.hostView.bounds()

proc fieldEditorTextStyleForEditing(tableView: TableView): TextStyle =
  let style = tableView.effectiveAppearance().resolveRowItemStyle(
      controlStyle(
        tableView.xItemRole,
        tableView.widgetStateSet(),
        id = tableView.styleId(),
        classes = tableView.styleClasses(),
      )
    )
  style.text

proc removeFieldEditorFromSurface(tableView: TableView, editor: FieldEditor) =
  if editor.isNil:
    return
  TextView(editor).clearTextStyleOverride()
  if tableView.xCellEditing.surface.hostView of Control:
    Control(tableView.xCellEditing.surface.hostView).setCurrentEditor(nil)
  if not tableView.xCellEditing.surface.cell.isNil:
    tableView.xCellEditing.surface.cell.endEditing(
      editor, tableView.xCellEditing.surface.hostView
    )
  elif editor.superview() == tableView.xCellEditing.surface.hostView:
    editor.removeFromSuperview()

proc installFieldEditorOnSurface*(tableView: TableView, editor: FieldEditor) =
  if editor.isNil:
    return
  if tableView.xCellEditing.surface.hostView.isNil and
      not tableView.prepareEditingSurface():
    return
  let frame = tableView.fieldEditorFrameForEditing()
  if not tableView.xCellEditing.surface.cell.isNil:
    tableView.xCellEditing.surface.cell.selectWithFrame(
      frame,
      tableView.xCellEditing.surface.hostView,
      editor,
      0,
      editor.textStorage().len,
    )
    if tableView.xCellEditing.surface.hostView of Control:
      Control(tableView.xCellEditing.surface.hostView).setCurrentEditor(editor)
  else:
    let textView = TextView(editor)
    textView.setTextStyleOverride(tableView.fieldEditorTextStyleForEditing())
    textView.alignment = tableView.xCellEditing.state.column.alignment()
    editor.setFrameFromLayout(frame)
    editor.bounds = rect(0.0, 0.0, frame.size.width, frame.size.height)
    if not tableView.xCellEditing.surface.hostView.isNil and
        editor.superview() != tableView.xCellEditing.surface.hostView:
      tableView.xCellEditing.surface.hostView.addSubview(editor)
    editor.selectedRange = initTextRange(0, editor.textStorage().len)

proc setEditingValidation(tableView: TableView, error: ObjectValidationError) =
  if not tableView.xCellEditing.state.active:
    return
  let hadError = tableView.xCellEditing.state.validation.failed()
  tableView.xCellEditing.state.validation = error
  tableView.xCellEditing.state.validationError =
    if error.failed():
      error.displayMessage()
    else:
      ""
  if error.failed():
    Control(tableView).setValidationError(error)
  else:
    Control(tableView).clearValidationError()
  if hadError or error.failed():
    tableView.needsDisplay = true

proc parseEditingObjectValue(tableView: TableView, value: string): ObjectParseResult =
  if not tableView.xCellEditing.state.active:
    return initObjectParseResult(toObj(value))
  let delegate = tableView.delegate()
  if not delegate.isNil:
    let parsed = delegate.trySendLocal(
      parseObjectValueForCell(),
      (
        tableView: tableView,
        row: tableView.xCellEditing.state.row,
        column: tableView.xCellEditing.state.column,
        value: value,
      ),
    )
    if parsed.isSome:
      return parsed.get()
  Control(tableView).parseEditedObjectValue(value, ovrTableCell)

proc validateEditingValue(tableView: TableView, value: string): bool =
  if not tableView.xCellEditing.state.active:
    return true
  tableView.setEditingValidation(initObjectValidationError())
  let parsed = tableView.parseEditingObjectValue(value)
  if parsed.failed():
    tableView.setEditingValidation(parsed.error)
    return false
  let delegate = tableView.delegate()
  if delegate.isNil:
    tableView.xCellEditing.state.objectValue = parsed.value
    return true
  let validation = delegate.trySendLocal(
    validationErrorForCell(),
    (
      tableView: tableView,
      row: tableView.xCellEditing.state.row,
      column: tableView.xCellEditing.state.column,
      value: value,
    ),
  )
  if validation.isSome and validation.get().len > 0:
    tableView.setEditingValidation(
      initObjectValidationError(
        oveCustom,
        message = validation.get(),
        input = value,
        expectedKind = parsed.value.kind,
        actualKind = parsed.value.kind,
      )
    )
    return false
  let objectValidation = delegate.trySendLocal(
    validationErrorForObjectValue(),
    (
      tableView: tableView,
      row: tableView.xCellEditing.state.row,
      column: tableView.xCellEditing.state.column,
      value: parsed.value,
    ),
  )
  if objectValidation.isSome and objectValidation.get().failed():
    tableView.setEditingValidation(objectValidation.get())
    return false
  tableView.xCellEditing.state.objectValue = parsed.value
  true

proc finishCommitEditingCell(tableView: TableView, value: string): bool =
  if not tableView.xCellEditing.state.active:
    return false
  if not tableView.validateEditingValue(value):
    return false
  let editing = tableView.xCellEditing.state
  let objectValue = editing.objectValue
  if not tableView.writeTableCellObjectValue(editing.row, editing.column, objectValue):
    tableView.setEditingValidation(
      initObjectValidationError(
        oveRejected,
        message = "Cell value was rejected by the data source",
        input = value,
        expectedKind = objectValue.kind,
        actualKind = objectValue.kind,
      )
    )
    return false
  tableView.xCellEditing.completion =
    TableEditCompletion(row: editing.row, column: editing.column, committed: true)
  tableView.xCellEditing.state = TableEditingState()
  tableView.clearEditingSurface()
  let delegate = tableView.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didCommitEditingCell(),
      (tableView: tableView, row: editing.row, column: editing.column, value: value),
    )
    discard delegate.sendLocalIfHandled(
      didCommitEditingObjectValue(),
      (
        tableView: tableView,
        row: editing.row,
        column: editing.column,
        value: objectValue,
      ),
    )
  emit tableView.cellEditDidCommit(
    DynamicAgent(tableView), editing.row, editing.column, value
  )
  emit tableView.cellObjectValueDidCommit(
    DynamicAgent(tableView), editing.row, editing.column, objectValue
  )
  Control(tableView).clearValidationError()
  tableView.clearTableCellSlots()
  tableView.needsDisplay = true
  true

proc finishCancelEditingCell(tableView: TableView): bool =
  if not tableView.xCellEditing.state.active:
    return false
  let editing = tableView.xCellEditing.state
  tableView.xCellEditing.completion =
    TableEditCompletion(row: editing.row, column: editing.column)
  tableView.xCellEditing.state = TableEditingState()
  Control(tableView).clearValidationError()
  tableView.clearEditingSurface()
  let delegate = tableView.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didCancelEditingCell(),
      (tableView: tableView, row: editing.row, column: editing.column),
    )
  tableView.needsDisplay = true
  true

proc editableColumns(tableView: TableView): seq[TableColumn] =
  for column in tableView.visibleColumns():
    result.add column

proc editableCellInRowAfter(
    tableView: TableView, row: int, column: TableColumn, direction: int
): TableEditingState =
  result = TableEditingState()
  if row notin 0 ..< tableView.rowCount():
    return
  let columns = tableView.editableColumns()
  if columns.len == 0:
    return
  var columnIndex = -1
  for index, current in columns:
    if current == column:
      columnIndex = index
      break
  if columnIndex < 0:
    columnIndex = (if direction >= 0: -1 else: columns.len)
  var nextColumnIndex = columnIndex
  while true:
    nextColumnIndex += (if direction >= 0: 1 else: -1)
    if nextColumnIndex < 0 or nextColumnIndex >= columns.len:
      return
    let nextColumn = columns[nextColumnIndex]
    if tableView.shouldBeginEditingCell(row, nextColumn):
      return TableEditingState(row: row, column: nextColumn, active: true)

proc moveEditingFromEndedCell(tableView: TableView, movement: TextEditMovement): bool =
  if not tableView.xCellEditing.completion.committed:
    return false
  var next = TableEditingState()
  case movement
  of temTab:
    next = tableView.editableCellInRowAfter(
      tableView.xCellEditing.completion.row, tableView.xCellEditing.completion.column, 1
    )
  of temBacktab:
    next = tableView.editableCellInRowAfter(
      tableView.xCellEditing.completion.row, tableView.xCellEditing.completion.column,
      -1,
    )
  of temReturn, temNone:
    discard
  if next.row < 0 or next.column.isNil:
    return false
  tableView.beginEditingCell(next.row, next.column)

protocol DefaultTableViewEditingBehavior of TableViewEditingProtocol:
  method shouldBeginEditingCell(
      tableView: TableView, row: int, column: TableColumn
  ): bool =
    if not tableView.validCell(row, column):
      return false
    let delegate = tableView.delegate()
    if not delegate.isNil:
      let allowed = delegate.trySendLocal(
        shouldEditCell(), (tableView: tableView, row: row, column: column)
      )
      if allowed.isSome:
        return allowed.get()
    true

  method beginEditingCell(tableView: TableView, row: int, column: TableColumn): bool =
    if not tableView.shouldBeginEditingCell(row, column):
      return false
    if tableView.xCellEditing.state.active:
      if tableView.xCellEditing.state.row == row and
          tableView.xCellEditing.state.column == column:
        let owner = tableView.window()
        if owner of Window:
          return Window(owner).makeFirstResponder(tableView)
        return true
      let editor = Control(tableView).activeEditor()
      if not editor.isNil and editor.client() == tableView:
        if not editor.commitEditing():
          return false
      elif not tableView.finishCommitEditingCell(""):
        return false
    tableView.xCellEditing.state =
      TableEditingState(row: row, column: column, active: true)
    tableView.selectCell(row, column)
    discard tableView.prepareEditingSurface()
    let delegate = tableView.delegate()
    if not delegate.isNil:
      discard delegate.sendLocalIfHandled(
        didBeginEditingCell(), (tableView: tableView, row: row, column: column)
      )
    let owner = tableView.window()
    if owner of Window:
      return Window(owner).makeFirstResponder(tableView)
    true

  method commitEditingCell(tableView: TableView, value: string): bool =
    if not tableView.xCellEditing.state.active:
      return false
    let editor = Control(tableView).activeEditor()
    if not editor.isNil and editor.client() == tableView:
      if value.len > 0:
        TextView(editor).stringValue = value
      return editor.commitEditing()
    tableView.finishCommitEditingCell(value)

  method cancelEditingCell(tableView: TableView): bool =
    if not tableView.xCellEditing.state.active:
      return false
    let editor = Control(tableView).activeEditor()
    if not editor.isNil and editor.client() == tableView:
      tableView.xCellEditing.cancelling = true
      result = editor.cancelEditing()
      tableView.xCellEditing.cancelling = false
      if result:
        let owner = tableView.window()
        if owner of Window and Window(owner).firstResponder() == editor:
          discard Window(owner).makeFirstResponder(nil)
      return
    tableView.finishCancelEditingCell()

protocol DefaultTableViewFieldEditorClient of FieldEditorClient:
  method fieldEditorForClient(
      tableView: TableView, defaultEditor: FieldEditor
  ): FieldEditor =
    if not tableView.xCellEditing.state.active:
      return defaultEditor
    if tableView.xCellEditing.surface.hostView.isNil:
      discard tableView.prepareEditingSurface()
    if not tableView.xCellEditing.surface.cell.isNil:
      let editor = tableView.xCellEditing.surface.cell.fieldEditorForView(
        tableView.xCellEditing.surface.hostView
      )
      if not editor.isNil:
        return editor
    defaultEditor

  method usesFieldEditor(tableView: TableView, editor: FieldEditor): bool =
    tableView.xCellEditing.state.active

  method stringForFieldEditor(tableView: TableView, editor: FieldEditor): string =
    if not tableView.xCellEditing.state.active:
      ""
    else:
      tableView.tableCellText(
        tableView.xCellEditing.state.row, tableView.xCellEditing.state.column
      )

  method setStringFromFieldEditor(
      tableView: TableView, editor: FieldEditor, value: string
  ) =
    discard

  method didBeginEditing(tableView: TableView, editor: FieldEditor) =
    Control(tableView).setCurrentEditor(editor)
    tableView.installFieldEditorOnSurface(editor)
    tableView.focused = true
    tableView.focusVisible = editor.isFocusVisible()
    tableView.needsDisplay = true

  method didChangeFocusInEditor(tableView: TableView, editor: FieldEditor) =
    if Control(tableView).activeEditor() != editor:
      return
    tableView.focused = editor.isFocused()
    tableView.focusVisible = editor.isFocusVisible()

  method didChangeTextInEditor(tableView: TableView, editor: FieldEditor) =
    if not tableView.xCellEditing.state.active:
      return
    if tableView.xCellEditing.state.validation.failed():
      tableView.setEditingValidation(initObjectValidationError())

  method shouldBeginEditing(tableView: TableView, editor: FieldEditor): bool =
    tableView.xCellEditing.state.active

  method shouldEndEditing(tableView: TableView, editor: FieldEditor): bool =
    if tableView.xCellEditing.cancelling:
      return true
    tableView.validateEditingValue(TextView(editor).stringValue())

  method validationErrorForEditor(
      tableView: TableView, editor: FieldEditor
  ): ObjectValidationError =
    tableView.editingValidation()

  method didEndEditing(tableView: TableView, editor: FieldEditor) =
    tableView.removeFieldEditorFromSurface(editor)
    Control(tableView).setCurrentEditor(nil)
    tableView.focused = false
    tableView.focusVisible = false
    tableView.needsDisplay = true

  method didEndEditingReason(
      tableView: TableView, editor: FieldEditor, reason: TextEditReason
  ) =
    case reason
    of terCancel:
      discard tableView.finishCancelEditingCell()
    of terCommit, terFocusChange, terProgrammatic:
      discard tableView.finishCommitEditingCell(TextView(editor).stringValue())

  method didEndEditingMovement(
      tableView: TableView, editor: FieldEditor, movement: TextEditMovement
  ) =
    if not tableView.moveEditingFromEndedCell(movement):
      let owner = tableView.window()
      if owner of Window and Window(owner).firstResponder() == editor:
        case movement
        of temTab:
          if not Window(owner).selectKeyViewFollowingView(tableView):
            discard Window(owner).makeFirstResponder(tableView)
        of temBacktab:
          if not Window(owner).selectKeyViewPrecedingView(tableView):
            discard Window(owner).makeFirstResponder(tableView)
        of temReturn, temNone:
          discard Window(owner).makeFirstResponder(tableView)

proc installTableCellEditingProtocols*(tableView: TableView) =
  discard tableView.withProtocol(DefaultTableViewEditingBehavior)
  discard tableView.withProtocol(DefaultTableViewFieldEditorClient)
