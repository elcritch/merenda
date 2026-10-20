## Row selection, activation, keyboard navigation, and type selection.

import std/[algorithm, strutils, times]
import sigils/core
import ../accessibility/accessibilityprotocols
import ../controls/controls
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../foundation/undomanagers
import ../view/views
import ../containers/scrollviews
import ./tablecore
import ./private/tablecoordination

const TableTypeSelectTimeout = 1.0

proc `selectedIndexes=`*(tableView: TableView, indexes: openArray[int])
proc applySelectedIndexes(
  tableView: TableView, indexes: openArray[int], anchor, lead: int
)

proc applySelectionForRowIdentifiers*(
    tableView: TableView,
    identifiers: openArray[string],
    anchorIdentifier, leadIdentifier: string,
) =
  if identifiers.len == 0:
    return
  var rows: seq[int]
  for identifier in identifiers:
    let row = tableView.tableRowIndexForIdentifier(identifier)
    if row >= 0:
      rows.add row
  tableView.applySelectedIndexes(
    rows,
    tableView.tableRowIndexForIdentifier(anchorIdentifier),
    tableView.tableRowIndexForIdentifier(leadIdentifier),
  )

proc indexesInRange(selectionRange: Slice[int]): seq[int] =
  if selectionRange.b < selectionRange.a:
    return @[]
  for index in selectionRange.a .. selectionRange.b:
    result.add index

proc syncSelectedIndex*(tableView: TableView) =
  tableView.xRowSelection.index =
    tableView.firstSelectedIndex(tableView.xRowSelection.indexes)

proc normalizeSelection*(tableView: TableView, indexes: openArray[int]): seq[int] =
  if tableView.xRowSelection.mode == tsmNone or tableView.len() == 0:
    return @[]
  for index in indexes:
    if tableView.rowSelectable(index):
      result.add index
  result.sort()
  var writeIndex = 0
  for index in result:
    if writeIndex == 0 or result[writeIndex - 1] != index:
      result[writeIndex] = index
      inc writeIndex
  result.setLen(writeIndex)
  if tableView.xRowSelection.mode == tsmSingle and result.len > 1:
    result.setLen(1)

proc normalizeSelectionAnchor(tableView: TableView, anchor: int): int =
  if tableView.rowSelectable(anchor): anchor else: tableView.xRowSelection.index

proc syncSelectionCursor*(tableView: TableView) =
  if tableView.xRowSelection.indexes.len == 0:
    tableView.xRowSelection.anchor = -1
    tableView.xRowSelection.lead = -1
    return
  if tableView.xRowSelection.mode == tsmSingle:
    tableView.xRowSelection.anchor = tableView.xRowSelection.index
    tableView.xRowSelection.lead = tableView.xRowSelection.index
    return
  if not tableView.rowSelectable(tableView.xRowSelection.anchor):
    tableView.xRowSelection.anchor = tableView.xRowSelection.index
  if not tableView.rowSelectable(tableView.xRowSelection.lead):
    tableView.xRowSelection.lead = tableView.xRowSelection.index

proc firstSelectableIndex*(tableView: TableView): int =
  for index in 0 ..< tableView.len():
    if tableView.rowSelectable(index):
      return index
  -1

proc lastSelectableIndex*(tableView: TableView): int =
  for countdown in 0 ..< tableView.len():
    let index = tableView.len() - countdown - 1
    if tableView.rowSelectable(index):
      return index
  -1

proc nextSelectableIndex(tableView: TableView, index, delta: int): int =
  if delta == 0 or tableView.len() == 0:
    return -1
  let step = if delta < 0: -1 else: 1
  var current = index
  while current >= 0 and current < tableView.len():
    if tableView.rowSelectable(current):
      return current
    current += step
  -1

proc applySelectedIndexes(
    tableView: TableView, indexes: openArray[int], anchor: int, lead: int
) =
  let nextIndexes = tableView.normalizeSelection(indexes)
  let
    nextSelected = tableView.firstSelectedIndex(nextIndexes)
    nextAnchor =
      if nextIndexes.len == 0:
        -1
      elif tableView.rowSelectable(anchor):
        anchor
      else:
        nextSelected
    nextLead =
      if nextIndexes.len == 0:
        -1
      elif tableView.rowSelectable(lead):
        lead
      else:
        nextSelected
    selectionChanged = tableView.xRowSelection.indexes != nextIndexes
  if not selectionChanged:
    tableView.xRowSelection.anchor = nextAnchor
    tableView.xRowSelection.lead = nextLead
    if nextIndexes.len == 0:
      tableView.clearFocusedColumn()
    if nextLead >= 0:
      tableView.scrollItemToVisible(nextLead)
    return
  let beforeIndexes = tableView.xRowSelection.indexes
  tableView.findUndoManager().registerSelectionChange(
    proc(indexes: seq[int]) =
      tableView.selectedIndexes = indexes,
    beforeIndexes,
    "Change Selection",
  )
  emit tableView.selectionIsChanging(DynamicAgent(tableView))
  tableView.xRowSelection.indexes = nextIndexes
  tableView.syncSelectedIndex()
  tableView.xRowSelection.anchor = nextAnchor
  tableView.xRowSelection.lead = nextLead
  if nextIndexes.len == 0:
    tableView.clearFocusedColumn()
  if nextLead >= 0:
    tableView.scrollItemToVisible(nextLead)
  tableView.invalidateTableRows()
  emit tableView.selectionDidChange(DynamicAgent(tableView))
  tableView.postAccessibilityNotification(anSelectionChanged)
  if nextSelected >= 0:
    let delegate = tableView.delegate()
    if not delegate.isNil:
      discard delegate.sendLocalIfHandled(
        didSelectTableRow(), (tableView: tableView, row: nextSelected)
      )

proc selectItemAtIndex*(tableView: TableView, index: int) =
  if tableView.xRowSelection.mode == tsmNone:
    return
  let boundedIndex = if index < 0 or index >= tableView.len(): -1 else: index
  if boundedIndex >= 0 and not tableView.rowSelectable(boundedIndex):
    return
  if tableView.xRowSelection.index == boundedIndex and
      tableView.xRowSelection.indexes.len <= 1:
    if boundedIndex >= 0:
      tableView.scrollItemToVisible(boundedIndex)
    return
  if boundedIndex < 0:
    tableView.selectedIndexes = @[]
  else:
    tableView.applySelectedIndexes([boundedIndex], boundedIndex, boundedIndex)

proc rangeSelectionIndexes(anchor, lead: int): seq[int] =
  if anchor < 0 or lead < 0:
    return @[]
  let
    firstIndex = min(anchor, lead)
    lastIndex = max(anchor, lead)
  for index in firstIndex .. lastIndex:
    result.add index

proc extendSelectionToIndex(tableView: TableView, index: int) =
  if tableView.xRowSelection.mode != tsmExtended:
    tableView.selectItemAtIndex(index)
    return
  let boundedIndex = if tableView.validTableIndex(index): index else: -1
  if boundedIndex < 0 or not tableView.rowSelectable(boundedIndex):
    return
  let anchor = tableView.normalizeSelectionAnchor(tableView.xRowSelection.anchor)
  tableView.applySelectedIndexes(
    rangeSelectionIndexes(anchor, boundedIndex), anchor, boundedIndex
  )

proc toggleSelectionAtIndex(tableView: TableView, index: int) =
  if tableView.xRowSelection.mode notin {tsmMultiple, tsmExtended}:
    tableView.selectItemAtIndex(index)
    return
  if not tableView.rowSelectable(index):
    return
  var nextIndexes: seq[int]
  if tableView.selectionContains(index):
    for selectedIndex in tableView.xRowSelection.indexes:
      if selectedIndex != index:
        nextIndexes.add selectedIndex
  else:
    nextIndexes = tableView.xRowSelection.indexes
    nextIndexes.add index
  tableView.applySelectedIndexes(nextIndexes, index, index)

proc usesDiscontiguousSelection(modifiers: set[KeyModifier]): bool =
  kmCommand in modifiers or kmControl in modifiers

proc selectItemAtIndex*(tableView: TableView, index: int, modifiers: set[KeyModifier]) =
  if tableView.xRowSelection.mode == tsmNone:
    return
  if kmShift in modifiers and tableView.xRowSelection.mode == tsmExtended:
    tableView.extendSelectionToIndex(index)
  elif modifiers.usesDiscontiguousSelection() and
      tableView.xRowSelection.mode in {tsmMultiple, tsmExtended}:
    tableView.toggleSelectionAtIndex(index)
  else:
    tableView.selectItemAtIndex(index)

proc sendTableActivation*(tableView: TableView, index: int) =
  if not tableView.rowEnabled(index):
    return
  tableView.tableRowDidActivate(index)
  emit tableView.rowWasActivated(DynamicAgent(tableView))
  discard tableView.sendAction()

proc activateItemAtIndex(
    tableView: TableView, index: int, modifiers: set[KeyModifier]
) =
  if not tableView.rowEnabled(index):
    return
  if tableView.selectionMode() != tsmNone:
    if not tableView.rowSelectable(index):
      return
    tableView.selectItemAtIndex(index, modifiers)
  tableView.sendTableActivation(index)

proc typeSelectStartIndex(tableView: TableView): int =
  if tableView.selectionLeadIndex() >= 0:
    tableView.selectionLeadIndex() + 1
  elif tableView.selectedIndex() >= 0:
    tableView.selectedIndex() + 1
  else:
    tableView.firstVisibleIndex()

proc rowTextMatchesPrefix(
    tableView: TableView, index: int, normalizedPrefix: string
): bool =
  let source = tableView.dataSource()
  if not source.isNil:
    let searchText = source.trySendLocal(
      normalizedSearchTextForRow(), (tableView: tableView, row: index)
    )
    if searchText.isSome:
      return searchText.get().startsWith(normalizedPrefix)
  tableView.rowTextForSummary(index).toLowerAscii().startsWith(normalizedPrefix)

proc firstRowMatchingText(tableView: TableView, text: string): int =
  if text.len == 0 or tableView.len() == 0:
    return -1
  let
    normalized = text.toLowerAscii()
    start = max(tableView.typeSelectStartIndex(), 0)
  for offset in 0 ..< tableView.len():
    let index = (start + offset) mod tableView.len()
    if tableView.rowSelectable(index) and
        tableView.rowTextMatchesPrefix(index, normalized):
      return index
  -1

proc selectItemMatchingText(tableView: TableView, text: string): bool =
  if tableView.selectionMode() == tsmNone:
    return false
  let index = tableView.firstRowMatchingText(text)
  if index < 0:
    return false
  tableView.selectItemAtIndex(index)
  true

proc isTypeSelectEvent(event: KeyEvent): bool =
  event.text.len > 0 and event.text notin [" ", "\n", "\r", "\t"] and
    event.modifiers * {kmControl, kmOption, kmCommand} == {}

proc handleTypeSelect*(tableView: TableView, event: KeyEvent): bool =
  if not event.isTypeSelectEvent():
    return false
  let now = epochTime()
  if now - tableView.xTypeSelection.lastInputTime > TableTypeSelectTimeout:
    tableView.xTypeSelection.buffer = ""
  tableView.xTypeSelection.lastInputTime = now
  tableView.xTypeSelection.buffer.add event.text
  if tableView.selectItemMatchingText(tableView.xTypeSelection.buffer):
    return true
  if event.text != tableView.xTypeSelection.buffer:
    tableView.xTypeSelection.buffer = event.text
    return tableView.selectItemMatchingText(tableView.xTypeSelection.buffer)
  false

proc moveSelectionTo*(tableView: TableView, index: int, extend = false, direction = 1) =
  if tableView.len() == 0 or tableView.selectionMode() == tsmNone:
    return
  let targetIndex = max(0, min(index, tableView.len() - 1))
  var boundedIndex = tableView.nextSelectableIndex(targetIndex, direction)
  if boundedIndex < 0 and direction > 0:
    boundedIndex = tableView.nextSelectableIndex(targetIndex, -1)
  elif boundedIndex < 0 and direction < 0:
    boundedIndex = tableView.nextSelectableIndex(targetIndex, 1)
  if boundedIndex < 0:
    return
  if extend and tableView.xRowSelection.mode == tsmExtended:
    tableView.extendSelectionToIndex(boundedIndex)
  else:
    tableView.selectItemAtIndex(boundedIndex)

proc moveSelection*(tableView: TableView, delta: int, extend = false) =
  let start =
    if tableView.selectionLeadIndex() >= 0:
      tableView.selectionLeadIndex()
    elif delta > 0:
      tableView.firstVisibleIndex() - 1
    elif delta < 0:
      tableView.firstVisibleIndex() + tableView.visibleItemCount()
    else:
      tableView.firstVisibleIndex()
  tableView.moveSelectionTo(start + delta, extend, delta)

proc pageSelection*(tableView: TableView, deltaPages: int, extend = false) =
  let delta = deltaPages * max(tableView.visibleItemCount(), 1)
  if delta == 0:
    return
  let start =
    if tableView.selectionLeadIndex() >= 0:
      tableView.selectionLeadIndex()
    elif delta > 0:
      tableView.firstVisibleIndex() - 1
    else:
      tableView.firstVisibleIndex() + tableView.visibleItemCount()
  let target = start + delta
  tableView.moveSelectionTo(target, extend, delta)
  let scrollView = tableView.xScrollView
  if target >= tableView.len():
    let
      currentOffset = scrollView.contentOffset()
      maximumOffset = scrollView.maximumContentOffset()
    tableView.setTableContentOffset(initPoint(currentOffset.x, maximumOffset.y), true)
  elif target < 0:
    let currentOffset = scrollView.contentOffset()
    tableView.setTableContentOffset(initPoint(currentOffset.x, 0.0'f32), true)

proc `selectedIndexes=`*(tableView: TableView, indexes: openArray[int]) =
  let nextIndexes = tableView.normalizeSelection(indexes)
  tableView.applySelectedIndexes(
    nextIndexes,
    tableView.firstSelectedIndex(nextIndexes),
    tableView.firstSelectedIndex(nextIndexes),
  )

proc `selectedRange=`*(tableView: TableView, selectionRange: Slice[int]) =
  let indexes = selectionRange.indexesInRange()
  tableView.selectedIndexes = indexes

proc `selectionMode=`*(tableView: TableView, mode: TableSelectionMode) =
  if tableView.xRowSelection.mode == mode:
    return
  tableView.xRowSelection.mode = mode
  if mode == tsmNone:
    tableView.xRowSelection.clear()
    tableView.clearFocusedColumn()
  elif mode == tsmSingle and tableView.xRowSelection.indexes.len > 1:
    tableView.xRowSelection.indexes.setLen(1)
    tableView.xRowSelection.index = tableView.xRowSelection.indexes[0]
    tableView.xRowSelection.anchor = tableView.xRowSelection.index
    tableView.xRowSelection.lead = tableView.xRowSelection.index
  tableView.requestTableReload()

proc `selectedIndex=`*(tableView: TableView, index: int) =
  if index < 0:
    tableView.selectedIndexes = @[]
  else:
    tableView.selectItemAtIndex(index)

proc activateItemAtIndex*(tableView: TableView, index: int) =
  tableView.activateItemAtIndex(index, {})
