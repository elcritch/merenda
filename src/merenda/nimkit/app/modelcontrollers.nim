import std/[algorithm, options]

import sigils/core
import sigils/selectors

import ../containers/cascadingviews
import ../containers/collectionviews
import ../containers/documenttabs
import ../containers/outlineviews
import ../containers/tableviews
import ../controls/comboboxes
import ../controls/controls
import ../controls/matrices
import ../controls/menus
import ../foundation/notifications
import ../foundation/objectvalues
import ../foundation/types
import ../responder/responders

export objectvalues

type
  ModelControllerError* = object of KeyError

  ModelSelectionMode* = enum
    mselNone
    mselSingle
    mselMultiple

  ModelSortDirection* = enum
    msdAscending
    msdDescending

  ModelField* = object
    key*: string
    value*: ObjectValue

  ModelItem* = object
    identifier*: string
    title*: string
    objectValue*: ObjectValue
    fields*: seq[ModelField]
    enabled*: bool
    hidden*: bool
    separator*: bool
    representedObject*: DynamicAgent

  ModelColumn* = object
    identifier*: string
    title*: string
    valueKey*: string
    width*: float32

  ModelSortDescriptor* = object
    key*: string
    direction*: ModelSortDirection

  ModelFilter* = proc(item: ModelItem): bool {.closure.}

  ModelTreeItem* = object
    item*: ModelItem
    parentIdentifier*: string
    leaf*: bool

  ObjectController* = ref object of Responder
    xItem: ModelItem

  SelectionController* = ref object of Responder
    xMode: ModelSelectionMode
    xSelectedIdentifiers: seq[string]
    xAnchorIdentifier: string
    xLeadIdentifier: string

  ArrayController* = ref object of Responder
    xItems: seq[ModelItem]
    xColumns: seq[ModelColumn]
    xSortDescriptors: seq[ModelSortDescriptor]
    xFilter: ModelFilter
    xSelection: SelectionController

  TreeController* = ref object of Responder
    xItems: seq[ModelTreeItem]
    xSelection: SelectionController

protocol ObjectControllerEvents:
  proc objectControllerDidChange*(
    controller: ObjectController, sender: DynamicAgent
  ) {.signal.}

protocol SelectionControllerEvents:
  proc selectionControllerDidChange*(
    controller: SelectionController, sender: DynamicAgent
  ) {.signal.}

protocol ArrayControllerEvents:
  proc arrayControllerDidChange*(
    controller: ArrayController, sender: DynamicAgent
  ) {.signal.}

protocol TreeControllerEvents:
  proc treeControllerDidChange*(
    controller: TreeController, sender: DynamicAgent
  ) {.signal.}

proc raiseModelControllerError(message: string) {.noinline, noreturn.} =
  raise newException(ModelControllerError, message)

proc installArrayControllerProtocols(controller: ArrayController)
proc installTreeControllerProtocols(controller: TreeController)

proc postSelectionNotification(controller: SelectionController) =
  doAssert not controller.isNil
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      nkSelectionDidChange,
      sender = DynamicAgent(controller),
      payload = initSelectionNotificationPayload(
        sckModel,
        selectedIdentifiers = controller.xSelectedIdentifiers,
        anchorIdentifier = controller.xAnchorIdentifier,
        leadIdentifier = controller.xLeadIdentifier,
        selectedIndex = if controller.xSelectedIdentifiers.len > 0: 0 else: -1,
      ),
    )
  )

proc notifySelectionControllerDidChange(controller: SelectionController) =
  doAssert not controller.isNil
  emit controller.selectionControllerDidChange(DynamicAgent(controller))
  controller.postSelectionNotification()

proc notifyObjectControllerDidChange(
    controller: ObjectController,
    mutation = mmkItemChanged,
    keys: openArray[string] = [],
) =
  doAssert not controller.isNil
  emit controller.objectControllerDidChange(DynamicAgent(controller))
  var identifiers: seq[string]
  if controller.xItem.identifier.len > 0:
    identifiers.add controller.xItem.identifier
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      nkModelMutationDidChange,
      sender = DynamicAgent(controller),
      representedObject = controller.xItem.representedObject,
      payload = initModelNotificationPayload(
        mutation, identifiers = identifiers, keys = keys, count = 1
      ),
    )
  )

proc notifyArrayControllerDidChange(
    controller: ArrayController,
    mutation = mmkItemsChanged,
    identifiers: openArray[string] = [],
    keys: openArray[string] = [],
    index = -1,
) =
  doAssert not controller.isNil
  emit controller.arrayControllerDidChange(DynamicAgent(controller))
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      nkModelMutationDidChange,
      sender = DynamicAgent(controller),
      payload = initModelNotificationPayload(
        mutation,
        identifiers = identifiers,
        keys = keys,
        index = index,
        count = controller.xItems.len.Natural,
      ),
    )
  )

proc notifyTreeControllerDidChange(
    controller: TreeController, identifiers: openArray[string] = [], index = -1
) =
  if controller.isNil:
    return
  emit controller.treeControllerDidChange(DynamicAgent(controller))
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      nkModelMutationDidChange,
      sender = DynamicAgent(controller),
      payload = initModelNotificationPayload(
        mmkTreeChanged,
        identifiers = identifiers,
        index = index,
        count = controller.xItems.len.Natural,
      ),
    )
  )

func initModelField*(key: string, value: ObjectValue): ModelField =
  ModelField(key: key, value: value)

func initModelColumn*(
    identifier: string, title = "", valueKey = "", width = 120.0'f32
): ModelColumn =
  ModelColumn(identifier: identifier, title: title, valueKey: valueKey, width: width)

func initModelSortDescriptor*(
    key: string, direction = msdAscending
): ModelSortDescriptor =
  ModelSortDescriptor(key: key, direction: direction)

proc initModelItem*(
    identifier = "",
    title = "",
    objectValue = emptyObjectValue(),
    fields: openArray[ModelField] = [],
    enabled = true,
    hidden = false,
    separator = false,
    representedObject: DynamicAgent = nil,
): ModelItem =
  ModelItem(
    identifier: identifier,
    title: title,
    objectValue: objectValue,
    fields: @fields,
    enabled: enabled,
    hidden: hidden,
    separator: separator,
    representedObject: representedObject,
  )

proc initModelTreeItem*(
    item: ModelItem, parentIdentifier = "", leaf = false
): ModelTreeItem =
  ModelTreeItem(item: item, parentIdentifier: parentIdentifier, leaf: leaf)

proc findFieldIndex(item: ModelItem, key: string): int =
  for index, field in item.fields:
    if field.key == key:
      return index
  -1

proc hasValue*(item: ModelItem, key: string): bool =
  key.len == 0 or item.findFieldIndex(key) >= 0

proc getValue*(item: ModelItem, key: string): Option[ObjectValue] =
  if key.len == 0:
    return some(item.objectValue)
  let index = item.findFieldIndex(key)
  if index >= 0:
    some(item.fields[index].value)
  else:
    none(ObjectValue)

proc value*(item: ModelItem, key = ""): ObjectValue {.raises: [ModelControllerError].} =
  let found = item.getValue(key)
  if found.isSome:
    return found.get()
  raiseModelControllerError("unknown model value key: " & key)

proc `[]`*(item: ModelItem, key: string): ObjectValue =
  item.value(key)

proc setValue*(item: var ModelItem, key: string, value: ObjectValue) =
  if key.len == 0:
    item.objectValue = value
    return
  let index = item.findFieldIndex(key)
  if index >= 0:
    item.fields[index].value = value
  else:
    item.fields.add initModelField(key, value)

proc `[]=`*(item: var ModelItem, key: string, value: ObjectValue) =
  item.setValue(key, value)

proc displayTitle*(item: ModelItem, role = ovrLabel): string =
  if item.title.len > 0:
    item.title
  else:
    item.objectValue.formatObjectValue(initObjectFormatContext(role = role))

proc compareObjectValues(a, b: ObjectValue): int =
  case a.kind
  of ovInt:
    if b.kind == ovInt:
      return cmp(a.intValue, b.intValue)
  of ovFloat:
    if b.kind == ovFloat:
      return cmp(a.floatValue, b.floatValue)
    if b.kind == ovInt:
      return cmp(a.floatValue, b.intValue.float)
  of ovString:
    if b.kind == ovString:
      return cmp(a.text, b.text)
  of ovBool:
    if b.kind == ovBool:
      return cmp(a.boolValue, b.boolValue)
  else:
    discard
  cmp(a.formatObjectValue(), b.formatObjectValue())

proc compareItems(a, b: ModelItem, descriptors: openArray[ModelSortDescriptor]): int =
  for descriptor in descriptors:
    let
      left = a.getValue(descriptor.key).get(emptyObjectValue())
      right = b.getValue(descriptor.key).get(emptyObjectValue())
    result = compareObjectValues(left, right)
    if result != 0:
      if descriptor.direction == msdDescending:
        result = -result
      return

proc initSelectionControllerFields(controller: SelectionController, mode = mselSingle) =
  initResponder(controller)
  controller.xMode = mode

proc newSelectionController*(mode = mselSingle): SelectionController =
  result = SelectionController()
  result.initSelectionControllerFields(mode)

proc mode*(controller: SelectionController): ModelSelectionMode =
  if controller.isNil: mselNone else: controller.xMode

proc `mode=`*(controller: SelectionController, mode: ModelSelectionMode) =
  if controller.isNil or controller.xMode == mode:
    return
  controller.xMode = mode
  if mode in {mselNone, mselSingle} and controller.xSelectedIdentifiers.len > 1:
    controller.xSelectedIdentifiers.setLen(if mode == mselNone: 0 else: 1)
  controller.notifySelectionControllerDidChange()

proc selectedIdentifiers*(controller: SelectionController): seq[string] =
  if controller.isNil:
    @[]
  else:
    controller.xSelectedIdentifiers

proc selectedIdentifier*(controller: SelectionController): string =
  if controller.isNil or controller.xSelectedIdentifiers.len == 0:
    ""
  else:
    controller.xSelectedIdentifiers[0]

proc anchorIdentifier*(controller: SelectionController): string =
  if controller.isNil: "" else: controller.xAnchorIdentifier

proc leadIdentifier*(controller: SelectionController): string =
  if controller.isNil: "" else: controller.xLeadIdentifier

proc isSelected*(controller: SelectionController, identifier: string): bool =
  not controller.isNil and identifier in controller.xSelectedIdentifiers

proc setSelectedIdentifiers*(
    controller: SelectionController, identifiers: openArray[string]
) =
  if controller.isNil:
    return
  var next: seq[string]
  case controller.xMode
  of mselNone:
    discard
  of mselSingle:
    for identifier in identifiers:
      if identifier.len > 0:
        next.add identifier
        break
  of mselMultiple:
    for identifier in identifiers:
      if identifier.len > 0 and identifier notin next:
        next.add identifier
  if controller.xSelectedIdentifiers == next:
    return
  controller.xSelectedIdentifiers = next
  controller.xAnchorIdentifier =
    if next.len > 0:
      next[0]
    else:
      ""
  controller.xLeadIdentifier =
    if next.len > 0:
      next[^1]
    else:
      ""
  controller.notifySelectionControllerDidChange()

proc clearSelection*(controller: SelectionController) =
  controller.setSelectedIdentifiers([])

proc selectIdentifier*(controller: SelectionController, identifier: string) =
  if controller.isNil:
    return
  case controller.xMode
  of mselNone:
    controller.clearSelection()
  of mselSingle:
    controller.setSelectedIdentifiers([identifier])
  of mselMultiple:
    var next = controller.xSelectedIdentifiers
    if identifier.len > 0 and identifier notin next:
      next.add identifier
    controller.setSelectedIdentifiers(next)

proc deselectIdentifier*(controller: SelectionController, identifier: string) =
  if controller.isNil or identifier.len == 0:
    return
  var next: seq[string]
  for selected in controller.xSelectedIdentifiers:
    if selected != identifier:
      next.add selected
  controller.setSelectedIdentifiers(next)

proc toggleIdentifier*(controller: SelectionController, identifier: string) =
  if controller.isSelected(identifier):
    controller.deselectIdentifier(identifier)
  else:
    controller.selectIdentifier(identifier)

proc initObjectControllerFields(controller: ObjectController, item: ModelItem) =
  initResponder(controller)
  controller.xItem = item

proc newObjectController*(item = initModelItem()): ObjectController =
  result = ObjectController()
  result.initObjectControllerFields(item)

proc item*(controller: ObjectController): ModelItem =
  if controller.isNil:
    initModelItem()
  else:
    controller.xItem

proc `item=`*(controller: ObjectController, item: ModelItem) =
  if controller.isNil:
    return
  controller.xItem = item
  controller.notifyObjectControllerDidChange(mmkItemChanged)

proc objectValue*(controller: ObjectController): ObjectValue =
  if controller.isNil:
    nilObjectValue()
  else:
    controller.xItem.objectValue

proc `objectValue=`*(controller: ObjectController, value: ObjectValue) =
  if controller.isNil:
    return
  controller.xItem.objectValue = value
  controller.notifyObjectControllerDidChange(mmkObjectValueChanged)

proc value*(controller: ObjectController, key: string): ObjectValue =
  if controller.isNil:
    raiseModelControllerError("nil object controller")
  controller.xItem.value(key)

proc setValue*(controller: ObjectController, key: string, value: ObjectValue) =
  if controller.isNil:
    return
  controller.xItem.setValue(key, value)
  controller.notifyObjectControllerDidChange(mmkValueChanged, keys = [key])

proc sourceIndexOfIdentifier(controller: ArrayController, identifier: string): int =
  if controller.isNil:
    return -1
  for index, item in controller.xItems:
    if item.identifier == identifier:
      return index
  -1

proc sortedVisibleIndexes(controller: ArrayController): seq[int] =
  if controller.isNil:
    return
  for index, item in controller.xItems:
    if item.hidden:
      continue
    if not controller.xFilter.isNil and not controller.xFilter(item):
      continue
    result.add index
  if controller.xSortDescriptors.len > 0:
    result.sort(
      proc(a, b: int): int =
        compareItems(
          controller.xItems[a], controller.xItems[b], controller.xSortDescriptors
        )
    )

proc arrangedSourceIndex(controller: ArrayController, index: int): int =
  let indexes = controller.sortedVisibleIndexes()
  if index in 0 ..< indexes.len:
    indexes[index]
  else:
    -1

proc initArrayControllerFields(
    controller: ArrayController,
    items: openArray[ModelItem] = [],
    columns: openArray[ModelColumn] = [],
) =
  initResponder(controller)
  controller.xItems = @items
  controller.xColumns = @columns
  controller.xSelection = newSelectionController(mselSingle)
  controller.installArrayControllerProtocols()

proc newArrayController*(
    items: openArray[ModelItem] = [], columns: openArray[ModelColumn] = []
): ArrayController =
  result = ArrayController()
  result.initArrayControllerFields(items, columns)

proc len*(controller: ArrayController): int =
  controller.sortedVisibleIndexes().len

proc sourceLen*(controller: ArrayController): int =
  if controller.isNil: 0 else: controller.xItems.len

proc selectionController*(controller: ArrayController): SelectionController =
  if controller.isNil: nil else: controller.xSelection

proc columns*(controller: ArrayController): seq[ModelColumn] =
  if controller.isNil:
    @[]
  else:
    controller.xColumns

proc `columns=`*(controller: ArrayController, columns: openArray[ModelColumn]) =
  if controller.isNil:
    return
  controller.xColumns = @columns
  controller.notifyArrayControllerDidChange(mmkColumnsChanged)

proc sortDescriptors*(controller: ArrayController): seq[ModelSortDescriptor] =
  if controller.isNil:
    @[]
  else:
    controller.xSortDescriptors

proc `sortDescriptors=`*(
    controller: ArrayController, descriptors: openArray[ModelSortDescriptor]
) =
  if controller.isNil:
    return
  controller.xSortDescriptors = @descriptors
  controller.notifyArrayControllerDidChange(mmkSortChanged)

proc filter*(controller: ArrayController): ModelFilter =
  if controller.isNil: nil else: controller.xFilter

proc `filter=`*(controller: ArrayController, filter: ModelFilter) =
  if controller.isNil:
    return
  controller.xFilter = filter
  controller.notifyArrayControllerDidChange(mmkFilterChanged)

proc itemAt*(controller: ArrayController, index: int): ModelItem =
  let sourceIndex = controller.arrangedSourceIndex(index)
  if sourceIndex >= 0:
    controller.xItems[sourceIndex]
  else:
    initModelItem()

proc itemWithIdentifier*(
    controller: ArrayController, identifier: string
): ModelItem {.raises: [ModelControllerError].} =
  let index = controller.sourceIndexOfIdentifier(identifier)
  if index >= 0:
    return controller.xItems[index]
  raiseModelControllerError("unknown model item identifier: " & identifier)

proc getItemWithIdentifier*(
    controller: ArrayController, identifier: string
): Option[ModelItem] =
  let index = controller.sourceIndexOfIdentifier(identifier)
  if index >= 0:
    some(controller.xItems[index])
  else:
    none(ModelItem)

proc indexOfIdentifier*(controller: ArrayController, identifier: string): int =
  let indexes = controller.sortedVisibleIndexes()
  for arrangedIndex, sourceIndex in indexes:
    if controller.xItems[sourceIndex].identifier == identifier:
      return arrangedIndex
  -1

proc addItem*(controller: ArrayController, item: ModelItem) =
  if controller.isNil:
    return
  if item.identifier.len > 0 and controller.sourceIndexOfIdentifier(item.identifier) >= 0:
    raiseModelControllerError("duplicate model item identifier: " & item.identifier)
  controller.xItems.add item
  var identifiers: seq[string]
  if item.identifier.len > 0:
    identifiers.add item.identifier
  controller.notifyArrayControllerDidChange(
    mmkItemsChanged, identifiers = identifiers, index = controller.xItems.high
  )

proc insertItem*(controller: ArrayController, item: ModelItem, index: int) =
  if controller.isNil:
    return
  if item.identifier.len > 0 and controller.sourceIndexOfIdentifier(item.identifier) >= 0:
    raiseModelControllerError("duplicate model item identifier: " & item.identifier)
  let insertIndex = max(0, min(index, controller.xItems.len))
  controller.xItems.insert(item, insertIndex)
  var identifiers: seq[string]
  if item.identifier.len > 0:
    identifiers.add item.identifier
  controller.notifyArrayControllerDidChange(
    mmkItemsChanged, identifiers = identifiers, index = insertIndex
  )

proc removeItem*(
    controller: ArrayController, identifier: string
): bool {.discardable.} =
  let index = controller.sourceIndexOfIdentifier(identifier)
  if index < 0:
    return false
  controller.xItems.delete(index)
  controller.xSelection.deselectIdentifier(identifier)
  controller.notifyArrayControllerDidChange(
    mmkItemsChanged, identifiers = [identifier], index = index
  )
  true

proc moveItem*(controller: ArrayController, identifier: string, toIndex: int): bool =
  let index = controller.sourceIndexOfIdentifier(identifier)
  if index < 0:
    return false
  let item = controller.xItems[index]
  controller.xItems.delete(index)
  let insertIndex = max(0, min(toIndex, controller.xItems.len))
  controller.xItems.insert(item, insertIndex)
  controller.notifyArrayControllerDidChange(
    mmkItemsChanged, identifiers = [identifier], index = insertIndex
  )
  true

proc valueForItem*(
    controller: ArrayController, identifier, key: string
): ObjectValue {.raises: [ModelControllerError].} =
  controller.itemWithIdentifier(identifier).value(key)

proc setValue*(
    controller: ArrayController, identifier, key: string, value: ObjectValue
) =
  let index = controller.sourceIndexOfIdentifier(identifier)
  if index < 0:
    raiseModelControllerError("unknown model item identifier: " & identifier)
  controller.xItems[index].setValue(key, value)
  controller.notifyArrayControllerDidChange(
    mmkValueChanged, identifiers = [identifier], keys = [key], index = index
  )

proc tableColumnIdentifier(column: ModelColumn): string =
  if column.identifier.len > 0: column.identifier else: column.valueKey

proc tableColumnTitle(column: ModelColumn): string =
  if column.title.len > 0:
    column.title
  elif column.identifier.len > 0:
    column.identifier
  else:
    column.valueKey

proc columnKey(controller: ArrayController, column: TableColumn): string =
  if column.isNil:
    return ""
  let identifier = column.identifier()
  if not controller.isNil:
    for modelColumn in controller.xColumns:
      if modelColumn.tableColumnIdentifier() == identifier:
        if modelColumn.valueKey.len > 0:
          return modelColumn.valueKey
        return modelColumn.tableColumnIdentifier()
  identifier

proc objectValueForArrayCell(
    controller: ArrayController, row: int, column: TableColumn
): ObjectValue =
  let item = controller.itemAt(row)
  item.getValue(controller.columnKey(column)).get(item.objectValue)

proc parseArrayCellValue(
    controller: ArrayController,
    tableView: TableView,
    row: int,
    column: TableColumn,
    value: string,
): ObjectParseResult =
  let current = controller.objectValueForArrayCell(row, column)
  let expectedKind = if current.kind in {ovNil, ovEmpty}: ovString else: current.kind
  let context =
    Control(tableView).objectParseContext.expecting(expectedKind).withRole(ovrTableCell)
  Control(tableView).objectValueFormatter.parseObjectValue(value, context)

protocol ArrayControllerTableDataSource of TableViewDataSource:
  method numberOfRows(controller: ArrayController, tableView: TableView): int =
    controller.len()

  method objectValueForCell(
      controller: ArrayController, tableView: TableView, row: int, column: TableColumn
  ): ObjectValue =
    controller.objectValueForArrayCell(row, column)

  method setObjectValueForCell(
      controller: ArrayController,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: ObjectValue,
  ): bool =
    discard tableView
    let item = controller.itemAt(row)
    if item.identifier.len == 0:
      return false
    controller.setValue(item.identifier, controller.columnKey(column), value)
    true

  method textForCell(
      controller: ArrayController, tableView: TableView, row: int, column: TableColumn
  ): string =
    let value = controller.objectValueForArrayCell(row, column)
    Control(tableView).formatObjectValue(value, ovrTableCell)

  method identifierForRow(
      controller: ArrayController, tableView: TableView, row: int
  ): string =
    controller.itemAt(row).identifier

  method rowForIdentifier(
      controller: ArrayController, tableView: TableView, identifier: string
  ): int =
    controller.indexOfIdentifier(identifier)

protocol ArrayControllerTableDelegate of TableViewDelegate:
  method didSelectTableRow(
      controller: ArrayController, tableView: TableView, row: int
  ) =
    let identifier = controller.itemAt(row).identifier
    controller.xSelection.setSelectedIdentifiers([identifier])

  method parseObjectValueForCell(
      controller: ArrayController,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ): ObjectParseResult =
    controller.parseArrayCellValue(tableView, row, column, value)

  method sortDescriptorsDidChange(
      controller: ArrayController,
      tableView: TableView,
      column: TableColumn,
      direction: TableSortDirection,
  ) =
    if direction == tsdNone:
      controller.sortDescriptors = []
    else:
      let modelDirection =
        if direction == tsdDescending: msdDescending else: msdAscending
      controller.sortDescriptors =
        [initModelSortDescriptor(controller.columnKey(column), modelDirection)]
    tableView.setNeedsLayout()
    tableView.setNeedsDisplay(true)

protocol ArrayControllerComboDataSource of ComboBoxDataSource:
  method itemCount(controller: ArrayController, comboBox: ComboBox): int =
    controller.len()

  method typedObjectValueAtIndex(
      controller: ArrayController, comboBox: ComboBox, index: int
  ): ObjectValue =
    controller.itemAt(index).objectValue

  method objectValueAtIndex(
      controller: ArrayController, comboBox: ComboBox, index: int
  ): string =
    controller.itemAt(index).displayTitle(ovrComboBox)

protocol ArrayControllerCollectionDataSource of CollectionViewDataSource:
  method numberOfCollectionItems(
      controller: ArrayController, collectionView: CollectionView
  ): int =
    controller.len()

  method identifierForCollectionItem(
      controller: ArrayController, collectionView: CollectionView, index: int
  ): string =
    controller.itemAt(index).identifier

  method indexForCollectionItemIdentifier(
      controller: ArrayController, collectionView: CollectionView, identifier: string
  ): int =
    controller.indexOfIdentifier(identifier)

  method objectValueForCollectionItem(
      controller: ArrayController, collectionView: CollectionView, index: int
  ): ObjectValue =
    controller.itemAt(index).objectValue

  method textForCollectionItem(
      controller: ArrayController, collectionView: CollectionView, index: int
  ): string =
    controller.itemAt(index).displayTitle(ovrLabel)

protocol ArrayControllerCollectionDelegate of CollectionViewDelegate:
  method didSelectCollectionItem(
      controller: ArrayController,
      collectionView: CollectionView,
      index: int,
      identifier: string,
  ) =
    discard index
    discard identifier
    controller.xSelection.setSelectedIdentifiers(collectionView.selectedIdentifiers())

proc installArrayControllerProtocols(controller: ArrayController) =
  discard controller.withProtocol(ArrayControllerTableDataSource)
  discard controller.withProtocol(ArrayControllerTableDelegate)
  discard controller.withProtocol(ArrayControllerComboDataSource)
  discard controller.withProtocol(ArrayControllerCollectionDataSource)
  discard controller.withProtocol(ArrayControllerCollectionDelegate)

proc bindTableView*(tableView: TableView, controller: ArrayController) =
  if tableView.isNil:
    return
  if not controller.isNil:
    for column in controller.xColumns:
      let identifier = column.tableColumnIdentifier()
      if identifier.len == 0 or tableView.containsColumn(identifier):
        continue
      let tableColumn =
        if column.width > 0.0'f32:
          newTableColumn(identifier, column.tableColumnTitle(), width = column.width)
        else:
          newTableColumn(identifier, column.tableColumnTitle())
      tableView.addColumn(tableColumn)
  tableView.dataSource = controller
  tableView.delegate = controller
  tableviews.reloadData(tableView)

proc bindComboBox*(comboBox: ComboBox, controller: ArrayController) =
  if comboBox.isNil:
    return
  comboBox.dataSource = controller
  comboboxes.reloadData(comboBox)

proc bindCollectionView*(collectionView: CollectionView, controller: ArrayController) =
  if collectionView.isNil:
    return
  collectionView.dataSource = DynamicAgent(controller)
  collectionView.delegate = DynamicAgent(controller)
  if not controller.isNil:
    collectionView.selectionMode =
      case controller.xSelection.mode()
      of mselNone: csmNone
      of mselSingle: csmSingle
      of mselMultiple: csmMultiple
    collectionView.selectedIdentifiers = controller.xSelection.selectedIdentifiers()
  collectionviews.reloadData(collectionView)

proc initTreeControllerFields(
    controller: TreeController, items: openArray[ModelTreeItem] = []
) =
  initResponder(controller)
  controller.xItems = @items
  controller.xSelection = newSelectionController(mselSingle)
  controller.installTreeControllerProtocols()

proc newTreeController*(items: openArray[ModelTreeItem] = []): TreeController =
  result = TreeController()
  result.initTreeControllerFields(items)

proc selectionController*(controller: TreeController): SelectionController =
  if controller.isNil: nil else: controller.xSelection

proc sourceLen*(controller: TreeController): int =
  if controller.isNil: 0 else: controller.xItems.len

proc treeIndexOfIdentifier(controller: TreeController, identifier: string): int =
  if controller.isNil:
    return -1
  for index, item in controller.xItems:
    if item.item.identifier == identifier:
      return index
  -1

proc treeItemWithIdentifier*(
    controller: TreeController, identifier: string
): ModelTreeItem {.raises: [ModelControllerError].} =
  let index = controller.treeIndexOfIdentifier(identifier)
  if index >= 0:
    return controller.xItems[index]
  raiseModelControllerError("unknown tree item identifier: " & identifier)

proc getTreeItemWithIdentifier*(
    controller: TreeController, identifier: string
): Option[ModelTreeItem] =
  let index = controller.treeIndexOfIdentifier(identifier)
  if index >= 0:
    some(controller.xItems[index])
  else:
    none(ModelTreeItem)

proc childIdentifiers*(controller: TreeController, parentIdentifier = ""): seq[string] =
  if controller.isNil:
    return
  for item in controller.xItems:
    if item.parentIdentifier == parentIdentifier and not item.item.hidden:
      result.add item.item.identifier

proc childCount*(controller: TreeController, parentIdentifier = ""): int =
  controller.childIdentifiers(parentIdentifier).len

proc childIdentifierAt*(
    controller: TreeController, parentIdentifier: string, index: int
): string =
  let children = controller.childIdentifiers(parentIdentifier)
  if index in 0 ..< children.len:
    children[index]
  else:
    ""

proc addItem*(controller: TreeController, item: ModelTreeItem) =
  if controller.isNil:
    return
  if item.item.identifier.len > 0 and
      controller.treeIndexOfIdentifier(item.item.identifier) >= 0:
    raiseModelControllerError("duplicate tree item identifier: " & item.item.identifier)
  controller.xItems.add item
  var identifiers: seq[string]
  if item.item.identifier.len > 0:
    identifiers.add item.item.identifier
  controller.notifyTreeControllerDidChange(
    identifiers = identifiers, index = controller.xItems.high
  )

proc removeItem*(controller: TreeController, identifier: string): bool {.discardable.} =
  let index = controller.treeIndexOfIdentifier(identifier)
  if index < 0:
    return false
  let childIds = controller.childIdentifiers(identifier)
  for childId in childIds:
    discard controller.removeItem(childId)
  let currentIndex = controller.treeIndexOfIdentifier(identifier)
  if currentIndex >= 0:
    controller.xItems.delete(currentIndex)
  controller.xSelection.deselectIdentifier(identifier)
  controller.notifyTreeControllerDidChange(
    identifiers = [identifier], index = currentIndex
  )
  true

proc moveItem*(
    controller: TreeController, identifier, parentIdentifier: string, index: int
): bool =
  let sourceIndex = controller.treeIndexOfIdentifier(identifier)
  if sourceIndex < 0:
    return false
  controller.xItems[sourceIndex].parentIdentifier = parentIdentifier
  let item = controller.xItems[sourceIndex]
  controller.xItems.delete(sourceIndex)
  var insertIndex = controller.xItems.len
  var siblingCount = 0
  for currentIndex, candidate in controller.xItems:
    if candidate.parentIdentifier == parentIdentifier:
      if siblingCount == index:
        insertIndex = currentIndex
        break
      inc siblingCount
  let targetIndex = max(0, min(insertIndex, controller.xItems.len))
  controller.xItems.insert(item, targetIndex)
  controller.notifyTreeControllerDidChange(
    identifiers = [identifier], index = targetIndex
  )
  true

proc hasChildren*(controller: TreeController, identifier: string): bool =
  controller.childCount(identifier) > 0

proc isLeaf*(controller: TreeController, identifier: string): bool =
  let item = controller.getTreeItemWithIdentifier(identifier)
  if item.isNone:
    return true
  item.get().leaf and not controller.hasChildren(identifier)

protocol TreeControllerOutlineDataSource of OutlineViewDataSource:
  method numberOfChildren(
      controller: TreeController, outlineView: OutlineView, parentIdentifier: string
  ): int =
    controller.childCount(parentIdentifier)

  method childIdentifier(
      controller: TreeController,
      outlineView: OutlineView,
      parentIdentifier: string,
      index: int,
  ): string =
    controller.childIdentifierAt(parentIdentifier, index)

  method outlineItem(
      controller: TreeController, outlineView: OutlineView, identifier: string
  ): OutlineItem =
    let treeItem = controller.getTreeItemWithIdentifier(identifier)
    if treeItem.isNone:
      return OutlineItem()
    let item = treeItem.get()
    OutlineItem(
      identifier: item.item.identifier,
      parentIdentifier: item.parentIdentifier,
      title: item.item.displayTitle(ovrTableCell),
      expandable: not controller.isLeaf(item.item.identifier),
    )

protocol TreeControllerCascadingDataSource of CascadingDataSource:
  method cascadingNumberOfChildren(
      controller: TreeController, view: CascadingView, parentIdentifier: string
  ): int =
    controller.childCount(parentIdentifier)

  method cascadingChildIdentifier(
      controller: TreeController,
      view: CascadingView,
      parentIdentifier: string,
      index: int,
  ): string =
    controller.childIdentifierAt(parentIdentifier, index)

  method cascadingItem(
      controller: TreeController, view: CascadingView, identifier: string
  ): CascadingItem =
    let treeItem = controller.getTreeItemWithIdentifier(identifier)
    if treeItem.isNone:
      return CascadingItem()
    let item = treeItem.get()
    CascadingItem(
      identifier: item.item.identifier,
      parentIdentifier: item.parentIdentifier,
      title: item.item.displayTitle(ovrComboBox),
      leaf: controller.isLeaf(item.item.identifier),
    )

  method cascadingItemTitle(
      controller: TreeController, view: CascadingView, identifier: string
  ): string =
    controller.treeItemWithIdentifier(identifier).item.displayTitle(ovrComboBox)

  method isLeafCascadingItem(
      controller: TreeController, view: CascadingView, identifier: string
  ): bool =
    controller.isLeaf(identifier)

proc installTreeControllerProtocols(controller: TreeController) =
  discard controller.withProtocol(TreeControllerOutlineDataSource)
  discard controller.withProtocol(TreeControllerCascadingDataSource)

proc bindOutlineView*(outlineView: OutlineView, controller: TreeController) =
  if outlineView.isNil:
    return
  outlineView.outlineDataSource = controller
  tableviews.reloadData(TableView(outlineView))

proc bindCascadingView*(view: CascadingView, controller: TreeController) =
  if view.isNil:
    return
  view.dataSource = controller
  cascadingviews.reloadData(view)

proc syncMenu*(menu: Menu, controller: ArrayController) =
  if menu.isNil:
    return
  var existing: seq[MenuItem]
  for index in 0 ..< menu.len():
    existing.add menu[index.Natural]
  for index in countdown(existing.len - 1, 0):
    discard menu.removeItem(existing[index])
  if controller.isNil:
    return
  for index in 0 ..< controller.len():
    let item = controller.itemAt(index)
    if item.separator:
      discard menu.addSeparator()
    else:
      let menuItem = menu.addItem(newMenuItem(item.objectValue))
      menuItem.title = item.displayTitle(ovrMenu)
      menuItem.enabled = item.enabled
      menuItem.representedObject = item.representedObject

proc syncDocumentTabs*(tabs: DocumentTabs, controller: ArrayController) =
  if tabs.isNil:
    return
  tabs.removeAllDocumentTabs()
  if controller.isNil:
    return
  for index in 0 ..< controller.len():
    let item = controller.itemAt(index)
    if item.separator:
      continue
    let tab = newDocumentTabItem(
      item.displayTitle(ovrLabel), identifier = item.identifier, closeable = true
    )
    tab.enabled = item.enabled
    tab.userInfo = item.representedObject
    discard tabs.addDocumentTabItem(tab)

proc syncMatrix*(matrix: Matrix, controller: ArrayController, columns = 1) =
  if matrix.isNil:
    return
  let count =
    if controller.isNil:
      0
    else:
      controller.len()
  let columnCount = max(columns, 1)
  let rowCount =
    if count == 0:
      0
    else:
      (count + columnCount - 1) div columnCount
  matrix.renewRowsColumns(rowCount, columnCount)
  for index in 0 ..< matrix.len():
    let cell = matrix.cellAtIndex(index)
    if index < count:
      let item = controller.itemAt(index)
      cell.setTitle(item.displayTitle(ovrLabel))
      cell.setEnabled(item.enabled and not item.separator)
    else:
      cell.setTitle("")
      cell.setEnabled(false)
