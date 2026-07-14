import std/[options, strutils, tables]

import sigils/core

import ../accessibility/accessibilityprotocols
import ../app/animations
import ../app/windows
import ../controls/controls
import ../drawing
import ../foundation/events
import ../foundation/notifications
import ../foundation/objectvalues
import ../foundation/selectors
import ../foundation/types
import ../themes
import ../view/views
import ./listbasics
import ./scrollviews
import ./tableviews

export controls, scrollviews, tableviews

type
  CascadingChildrenCache = object
    modelCount: int
    visibleIndices: seq[int]
    items: seq[CascadingItem]
    visibleIndexByIdentifier: Table[string, int]
    measuredContentWidth: float32
    measuredFontName: string
    measuredFontSize: float32
    measuredTextInsets: EdgeInsets
    measuredRowMinWidth: float32
    contentWidthMeasurementValid: bool

  CascadingItem* = object
    identifier*: string
    parentIdentifier*: string
    title*: string
    objectValue*: ObjectValue
    leaf*: bool
    hidden*: bool
    image*: ImageResource
    representedObject*: DynamicAgent

  CascadingSelection* = object
    column*: int
    row*: int
    identifier*: string
    title*: string
    objectValue*: ObjectValue
    leaf*: bool
    representedObject*: DynamicAgent

  CascadingTreeUpdateKind* = enum
    ctukInsert
    ctukRemove
    ctukMove
    ctukReload

  CascadingTreeUpdate* = object
    kind*: CascadingTreeUpdateKind
    parentIdentifier*: string
    indexes*: seq[int]
    fromIndex*: int
    toIndex*: int
    identifiers*: seq[string]

  CascadingView* = ref object of Control
    xItems: seq[CascadingItem]
    xDataSource: DynamicAgent
    xDelegate: DynamicAgent
    xScrollView: ScrollView
    xColumnContainer: View
    xColumns: seq[TableView]
    xSelectedPath: seq[string]
    xColumnWidth: float32
    xColumnSpacing: float32
    xMinColumnWidth: float32
    xShowsColumnHeaders: bool
    xSyncingColumnSelection: bool
    xBatchUpdateDepth: int
    xPendingTreeUpdates: seq[CascadingTreeUpdate]
    xActivatedIdentifier: string
    xLocalIndexByIdentifier: Table[string, int]
    xItemByIdentifier: Table[string, CascadingItem]
    xChildCountByParent: Table[string, int]
    xChildrenByParent: Table[string, CascadingChildrenCache]
    xTitleByIdentifier: Table[string, string]
    xNormalizedSearchTextByIdentifier: Table[string, string]

const
  CascadingDefaultColumnWidth = 160.0'f32
  CascadingDefaultMinColumnWidth = 72.0'f32
  CascadingDefaultColumnSpacing = 1.0'f32
  CascadingColumnEdgeInset = 1.0'f32
  CascadingChildArrowWidth = 10.0'f32
  CascadingChildArrowRightInset = 8.0'f32
  CascadingChildArrowTextGap = 6.0'f32

proc reloadData*(view: CascadingView)
proc selectItem*(view: CascadingView, column, row: int)
proc selectedItem*(view: CascadingView): CascadingSelection
proc scrollView*(view: CascadingView): ScrollView
proc tableViewForColumn*(view: CascadingView, column: int): TableView
proc columnForTableView(view: CascadingView, tableView: TableView): int
proc cascadingItemWithIdentifier*(
  view: CascadingView, identifier: string
): CascadingItem

proc childrenForParent*(
  view: CascadingView, parentIdentifier: string
): seq[CascadingItem]

proc itemHasChildren*(view: CascadingView, identifier: string): bool
proc indexOfChildIdentifier*(
  view: CascadingView, parentIdentifier, identifier: string
): int

proc applySelectedPath(view: CascadingView, path: openArray[string])
proc focusColumnRelative(view: CascadingView, delta: int): bool
proc scrollColumnToVisible(view: CascadingView, column: int)
proc syncCascadingStyle(view: CascadingView)
proc `columnWidth=`*(view: CascadingView, width: float32)
proc `minColumnWidth=`*(view: CascadingView, width: float32)
proc `columnSpacing=`*(view: CascadingView, spacing: float32)

protocol CascadingDataSource {.selectorScope: protocol.}:
  method cascadingNumberOfChildren*(
    view: CascadingView, parentIdentifier: string
  ): int {.optional.}

  method cascadingChildIdentifier*(
    view: CascadingView, parentIdentifier: string, index: int
  ): string {.optional.}

  method cascadingItem*(
    view: CascadingView, identifier: string
  ): CascadingItem {.optional.}

  method cascadingItemTitle*(
    view: CascadingView, identifier: string
  ): string {.optional.}

  method objectValueForCascadingItem*(
    view: CascadingView, identifier: string
  ): ObjectValue {.optional.}

  method isLeafCascadingItem*(
    view: CascadingView, identifier: string
  ): bool {.optional.}

  method indexOfCascadingChildIdentifier*(
    view: CascadingView, parentIdentifier: string, identifier: string
  ): int {.optional.}

protocol CascadingDelegate {.selectorScope: protocol.}:
  method shouldSelectCascadingItem*(
    view: CascadingView, column: int, row: int, identifier: string
  ): bool {.optional.}

  method didSelectCascadingItem*(
    view: CascadingView, column: int, row: int, identifier: string
  ) {.optional.}

  method didActivateCascadingItem*(
    view: CascadingView, column: int, row: int, identifier: string
  ) {.optional.}

  method rowHeightForCascadingColumn*(
    view: CascadingView, column: int
  ): float32 {.optional.}

protocol CascadingEvents:
  proc selectionIsChanging*(view: CascadingView, sender: DynamicAgent) {.signal.}
  proc selectionDidChange*(view: CascadingView, sender: DynamicAgent) {.signal.}
  proc itemWasActivated*(view: CascadingView, sender: DynamicAgent) {.signal.}
  proc cascadingItemsDidUpdate*(
    view: CascadingView, sender: DynamicAgent, updates: seq[CascadingTreeUpdate]
  ) {.signal.}

protocol CascadingSelectionProtocol:
  method selectionPath*(): seq[string]
  method setSelectionPath*(path: seq[string])
  method selectItemAt*(column, row: int)
  method currentSelection*(): CascadingSelection

protocol CascadingReloadProtocol:
  method reloadViewData*()
  method reloadViewColumn*(column: int)

protocol CascadingTransactionAnimProtocol:
  method animColumnWidthValue*(width: float32)
  method animMinColumnWidthValue*(width: float32)
  method animColumnSpacingValue*(spacing: float32)

protocol CascadingTransactionAnim of CascadingTransactionAnimProtocol:
  method animColumnWidthValue(view: CascadingView, width: float32) =
    view.columnWidth = width

  method animMinColumnWidthValue(view: CascadingView, width: float32) =
    view.minColumnWidth = width

  method animColumnSpacingValue(view: CascadingView, spacing: float32) =
    view.columnSpacing = spacing

proc cascadeItem*(
    identifier: string,
    title = "",
    parentIdentifier = "",
    leaf = false,
    objectValue = emptyObjectValue(),
    hidden = false,
    image: ImageResource = nil,
    representedObject: DynamicAgent = nil,
): CascadingItem =
  CascadingItem(
    identifier: identifier,
    parentIdentifier: parentIdentifier,
    title: title,
    objectValue: objectValue,
    leaf: leaf,
    hidden: hidden,
    image: image,
    representedObject: representedObject,
  )

func defaultCascadingTreeUpdate(
    kind: CascadingTreeUpdateKind,
    parentIdentifier = "",
    indexes: openArray[int] = [],
    identifiers: openArray[string] = [],
    fromIndex = -1,
    toIndex = -1,
): CascadingTreeUpdate =
  CascadingTreeUpdate(
    kind: kind,
    parentIdentifier: parentIdentifier,
    indexes: @indexes,
    fromIndex: fromIndex,
    toIndex: toIndex,
    identifiers: @identifiers,
  )

func initCascadingTreeInsertUpdate*(
    parentIdentifier: string,
    indexes: openArray[int],
    identifiers: openArray[string] = [],
): CascadingTreeUpdate =
  defaultCascadingTreeUpdate(ctukInsert, parentIdentifier, indexes, identifiers)

func initCascadingTreeRemoveUpdate*(
    parentIdentifier: string,
    indexes: openArray[int],
    identifiers: openArray[string] = [],
): CascadingTreeUpdate =
  defaultCascadingTreeUpdate(ctukRemove, parentIdentifier, indexes, identifiers)

func initCascadingTreeReloadUpdate*(
    parentIdentifier: string,
    indexes: openArray[int] = [],
    identifiers: openArray[string] = [],
): CascadingTreeUpdate =
  defaultCascadingTreeUpdate(ctukReload, parentIdentifier, indexes, identifiers)

func initCascadingTreeMoveUpdate*(
    parentIdentifier: string,
    fromIndex, toIndex: int,
    identifiers: openArray[string] = [],
): CascadingTreeUpdate =
  defaultCascadingTreeUpdate(
    ctukMove,
    parentIdentifier,
    identifiers = identifiers,
    fromIndex = fromIndex,
    toIndex = toIndex,
  )

proc dataSource*(view: CascadingView): DynamicAgent =
  view.xDataSource

proc `dataSource=`*(view: CascadingView, dataSource: DynamicAgent) =
  if view.xDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(CascadingDataSource)
  view.xDataSource = dataSource
  view.reloadData()

proc `dataSource=`*(view: CascadingView, dataSource: Responder) =
  view.dataSource = DynamicAgent(dataSource)

proc delegate*(view: CascadingView): DynamicAgent =
  view.xDelegate

proc `delegate=`*(view: CascadingView, delegate: DynamicAgent) =
  if view.xDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(CascadingDelegate)
  view.xDelegate = delegate
  view.reloadData()

proc `delegate=`*(view: CascadingView, delegate: Responder) =
  view.delegate = DynamicAgent(delegate)

proc cascadingItems*(view: CascadingView): seq[CascadingItem] =
  view.xItems

proc `cascadingItems=`*(view: CascadingView, items: openArray[CascadingItem]) =
  view.xItems = @items
  view.reloadData()

proc columnWidth*(view: CascadingView): float32 =
  view.xColumnWidth

proc `columnWidth=`*(view: CascadingView, width: float32) =
  let nextWidth = max(width, view.xMinColumnWidth)
  if view.xColumnWidth == nextWidth:
    return
  discard view.withProtocol(CascadingTransactionAnim)
  discard recordPropertyAnimation(
    DynamicAgent(view), animColumnWidthValue(), view.xColumnWidth, nextWidth
  )
  view.xColumnWidth = nextWidth
  view.invalidateIntrinsicContentSize()
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc minColumnWidth*(view: CascadingView): float32 =
  view.xMinColumnWidth

proc `minColumnWidth=`*(view: CascadingView, width: float32) =
  let nextWidth = max(width, 1.0'f32)
  if view.xMinColumnWidth == nextWidth:
    return
  discard view.withProtocol(CascadingTransactionAnim)
  discard recordPropertyAnimation(
    DynamicAgent(view), animMinColumnWidthValue(), view.xMinColumnWidth, nextWidth
  )
  view.xMinColumnWidth = nextWidth
  view.xColumnWidth = max(view.xColumnWidth, nextWidth)
  view.invalidateIntrinsicContentSize()
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc columnSpacing*(view: CascadingView): float32 =
  view.xColumnSpacing

proc `columnSpacing=`*(view: CascadingView, spacing: float32) =
  let nextSpacing = max(spacing, 0.0'f32)
  if view.xColumnSpacing == nextSpacing:
    return
  discard view.withProtocol(CascadingTransactionAnim)
  discard recordPropertyAnimation(
    DynamicAgent(view), animColumnSpacingValue(), view.xColumnSpacing, nextSpacing
  )
  view.xColumnSpacing = nextSpacing
  view.invalidateIntrinsicContentSize()
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc showsColumnHeaders*(view: CascadingView): bool =
  view.xShowsColumnHeaders

proc `showsColumnHeaders=`*(view: CascadingView, shows: bool) =
  if view.xShowsColumnHeaders == shows:
    return
  view.xShowsColumnHeaders = shows
  for column in view.xColumns:
    column.showsHeader = shows
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc columnCount*(view: CascadingView): int =
  view.xColumns.len

proc scrollView*(view: CascadingView): ScrollView =
  view.xScrollView

proc tableViewForColumn*(view: CascadingView, column: int): TableView =
  if column notin 0 ..< view.xColumns.len:
    nil
  else:
    view.xColumns[column]

protocol CascadingViewProtocol {.selectorScope: protocol.} from CascadingView:
  property cascadingSelectionPath -> seq[string]
  property cascadingColumnWidth -> float32
  property cascadingMinColumnWidth -> float32
  property cascadingColumnSpacing -> float32
  property cascadingShowsHeaders -> bool

  method cascadingSelectionPath(view: CascadingView): seq[string] =
    view.xSelectedPath

  method setCascadingSelectionPath(view: CascadingView, path: seq[string]) =
    view.applySelectedPath(path)

  method cascadingColumnWidth(view: CascadingView): float32 =
    view.xColumnWidth

  method setCascadingColumnWidth(view: CascadingView, width: float32) =
    view.columnWidth = width

  method cascadingMinColumnWidth(view: CascadingView): float32 =
    view.xMinColumnWidth

  method setCascadingMinColumnWidth(view: CascadingView, width: float32) =
    view.minColumnWidth = width

  method cascadingColumnSpacing(view: CascadingView): float32 =
    view.xColumnSpacing

  method setCascadingColumnSpacing(view: CascadingView, spacing: float32) =
    view.columnSpacing = spacing

  method cascadingShowsHeaders(view: CascadingView): bool =
    view.xShowsColumnHeaders

  method setCascadingShowsHeaders(view: CascadingView, shows: bool) =
    view.showsColumnHeaders = shows

  method cascadeScrollView*(view: CascadingView): ScrollView =
    view.xScrollView

  method cascadeColumnCount*(view: CascadingView): int =
    view.xColumns.len

  method cascadeTableForColumn*(view: CascadingView, column: int): TableView =
    if column notin 0 ..< view.xColumns.len:
      nil
    else:
      view.xColumns[column]

proc columnForTableView(view: CascadingView, tableView: TableView): int =
  for index, column in view.xColumns:
    if column == tableView:
      return index
  -1

proc clearCascadingModelCaches(view: CascadingView) =
  view.xLocalIndexByIdentifier = initTable[string, int]()
  view.xItemByIdentifier = initTable[string, CascadingItem]()
  view.xChildCountByParent = initTable[string, int]()
  view.xChildrenByParent = initTable[string, CascadingChildrenCache]()
  view.xTitleByIdentifier = initTable[string, string]()
  view.xNormalizedSearchTextByIdentifier = initTable[string, string]()
  for index, item in view.xItems:
    if item.identifier.len > 0 and item.identifier notin view.xLocalIndexByIdentifier:
      view.xLocalIndexByIdentifier[item.identifier] = index

proc localItemWithIdentifier(
    view: CascadingView, identifier: string
): tuple[found: bool, item: CascadingItem] =
  let index = view.xLocalIndexByIdentifier.getOrDefault(identifier, -1)
  if index in 0 ..< view.xItems.len:
    (true, view.xItems[index])
  else:
    (false, CascadingItem())

proc dataSourceObjectValueForIdentifier(
    view: CascadingView, identifier: string
): Option[ObjectValue] =
  let source = view.dataSource()
  if source.isNil:
    none(ObjectValue)
  else:
    source.trySendLocal(
      objectValueForCascadingItem(), (view: view, identifier: identifier)
    )

proc applyDataSourceItemMetadata(view: CascadingView, item: var CascadingItem) =
  if item.identifier.len == 0:
    return
  let objectValue = view.dataSourceObjectValueForIdentifier(item.identifier)
  if objectValue.isSome and item.objectValue.isNilOrEmpty():
    item.objectValue = objectValue.get()
  if item.title.len == 0 and not item.objectValue.isNilOrEmpty():
    item.title = Control(view).formatObjectValue(item.objectValue, ovrTableCell)

proc cacheCascadingItem(view: CascadingView, item: sink CascadingItem): CascadingItem =
  result = item
  let identifier = result.identifier
  if identifier.len == 0:
    return
  view.xItemByIdentifier[identifier] = result
  let title =
    if result.title.len > 0:
      result.title
    elif not result.objectValue.isNilOrEmpty():
      Control(view).formatObjectValue(result.objectValue, ovrTableCell)
    else:
      identifier
  view.xTitleByIdentifier[identifier] = title
  view.xNormalizedSearchTextByIdentifier[identifier] = title.strip().toLowerAscii()

proc rebuildLocalCascadingCaches(view: CascadingView) =
  if not view.dataSource().isNil:
    return
  var siblingCounts = initTable[string, int]()
  for item in view.xItems:
    let
      parentIdentifier = item.parentIdentifier
      modelIndex = siblingCounts.getOrDefault(parentIdentifier)
    siblingCounts[parentIdentifier] = modelIndex + 1
    if parentIdentifier notin view.xChildrenByParent:
      view.xChildrenByParent[parentIdentifier] =
        CascadingChildrenCache(visibleIndexByIdentifier: initTable[string, int]())
    view.xChildrenByParent[parentIdentifier].modelCount = modelIndex + 1
    var cachedItem = item
    view.applyDataSourceItemMetadata(cachedItem)
    cachedItem = view.cacheCascadingItem(cachedItem)
    if cachedItem.hidden:
      continue
    let visibleIndex = view.xChildrenByParent[parentIdentifier].visibleIndices.len
    view.xChildrenByParent[parentIdentifier].visibleIndices.add modelIndex
    view.xChildrenByParent[parentIdentifier].items.add cachedItem
    if cachedItem.identifier.len > 0 and
        cachedItem.identifier notin
        view.xChildrenByParent[parentIdentifier].visibleIndexByIdentifier:
      view.xChildrenByParent[parentIdentifier].visibleIndexByIdentifier[
        cachedItem.identifier
      ] = visibleIndex
  for parentIdentifier, cache in view.xChildrenByParent:
    view.xChildCountByParent[parentIdentifier] = cache.items.len

proc refreshCascadingModelCaches(view: CascadingView) =
  view.clearCascadingModelCaches()
  view.rebuildLocalCascadingCaches()

proc cascadingItemWithIdentifier*(
    view: CascadingView, identifier: string
): CascadingItem =
  if identifier.len == 0:
    return
  if identifier in view.xItemByIdentifier:
    return view.xItemByIdentifier[identifier]
  let source = view.dataSource()
  if not source.isNil:
    let item =
      source.trySendLocal(cascadingItem(), (view: view, identifier: identifier))
    if item.isSome:
      result = item.get()
      if result.identifier.len == 0:
        result.identifier = identifier
      view.applyDataSourceItemMetadata(result)
      if result.title.len == 0:
        let title = source.trySendLocal(
          cascadingItemTitle(), (view: view, identifier: identifier)
        )
        if title.isSome:
          result.title = title.get()
      if result.title.len == 0:
        result.title = result.identifier
      return view.cacheCascadingItem(result)
    let title =
      source.trySendLocal(cascadingItemTitle(), (view: view, identifier: identifier))
    if title.isSome:
      result = cascadeItem(identifier, title.get())
      view.applyDataSourceItemMetadata(result)
      return view.cacheCascadingItem(result)
  let local = view.localItemWithIdentifier(identifier)
  if local.found:
    result = local.item
    view.applyDataSourceItemMetadata(result)
  else:
    result = cascadeItem(identifier, identifier, leaf = true)
    view.applyDataSourceItemMetadata(result)
  result = view.cacheCascadingItem(result)

proc cascadingItemObjectValue*(view: CascadingView, identifier: string): ObjectValue =
  if identifier.len == 0:
    return nilObjectValue()
  let item = view.cascadingItemWithIdentifier(identifier)
  if not item.objectValue.isNilOrEmpty():
    item.objectValue
  elif item.title.len > 0:
    toObj(item.title)
  else:
    emptyObjectValue()

proc cascadingItemImage*(view: CascadingView, identifier: string): ImageResource =
  if identifier.len == 0:
    return nil
  view.cascadingItemWithIdentifier(identifier).image

proc cascadingItemRepresentedObject*(
    view: CascadingView, identifier: string
): DynamicAgent =
  if identifier.len == 0:
    return nil
  view.cascadingItemWithIdentifier(identifier).representedObject

proc parentIdentifierForColumn(view: CascadingView, column: int): string =
  if column <= 0:
    return ""
  if column - 1 in 0 ..< view.xSelectedPath.len:
    view.xSelectedPath[column - 1]
  else:
    ""

proc cachedChildCount(view: CascadingView, parentIdentifier: string): Option[int] =
  if parentIdentifier in view.xChildCountByParent:
    return some(view.xChildCountByParent[parentIdentifier])
  let source = view.dataSource()
  if source.isNil:
    return none(int)
  let count = source.trySendLocal(
    cascadingNumberOfChildren(), (view: view, parentIdentifier: parentIdentifier)
  )
  if count.isSome:
    let modelCount = max(count.get(), 0)
    view.xChildCountByParent[parentIdentifier] = modelCount
    return some(modelCount)

proc refreshChildrenForParent(view: CascadingView, parentIdentifier: string) =
  if parentIdentifier in view.xChildrenByParent:
    return
  var cache = CascadingChildrenCache(visibleIndexByIdentifier: initTable[string, int]())
  let
    source = view.dataSource()
    count = view.cachedChildCount(parentIdentifier)
  if not source.isNil and count.isSome:
    cache.modelCount = count.get()
    for modelIndex in 0 ..< cache.modelCount:
      let identifier = source.trySendLocal(
        cascadingChildIdentifier(),
        (view: view, parentIdentifier: parentIdentifier, index: modelIndex),
      )
      if identifier.isNone or identifier.get().len == 0:
        continue
      var item = view.cascadingItemWithIdentifier(identifier.get())
      if item.hidden:
        continue
      if item.parentIdentifier.len == 0 and parentIdentifier.len > 0:
        item.parentIdentifier = parentIdentifier
      let visibleIndex = cache.visibleIndices.len
      cache.visibleIndices.add modelIndex
      cache.items.add item
      if item.identifier notin cache.visibleIndexByIdentifier:
        cache.visibleIndexByIdentifier[item.identifier] = visibleIndex
  else:
    var modelIndex = 0
    for item in view.xItems:
      if item.parentIdentifier != parentIdentifier:
        continue
      inc cache.modelCount
      if not item.hidden:
        let visibleIndex = cache.visibleIndices.len
        cache.visibleIndices.add modelIndex
        cache.items.add item
        if item.identifier.len > 0 and
            item.identifier notin cache.visibleIndexByIdentifier:
          cache.visibleIndexByIdentifier[item.identifier] = visibleIndex
      inc modelIndex
    view.xChildCountByParent[parentIdentifier] = cache.items.len
  view.xChildrenByParent[parentIdentifier] = cache

proc childrenForParent*(
    view: CascadingView, parentIdentifier: string
): seq[CascadingItem] =
  view.refreshChildrenForParent(parentIdentifier)
  view.xChildrenByParent[parentIdentifier].items

proc itemHasChildren*(view: CascadingView, identifier: string): bool =
  if identifier.len == 0:
    return false
  let source = view.dataSource()
  if not source.isNil:
    let count = view.cachedChildCount(identifier)
    if count.isSome:
      return count.get() > 0
    let leaf =
      source.trySendLocal(isLeafCascadingItem(), (view: view, identifier: identifier))
    if leaf.isSome:
      return not leaf.get()
  view.refreshChildrenForParent(identifier)
  view.xChildrenByParent[identifier].items.len > 0

proc cascadingItemIsLeaf(view: CascadingView, item: CascadingItem): bool =
  if item.identifier.len == 0:
    return true
  let source = view.dataSource()
  if not source.isNil:
    let leaf = source.trySendLocal(
      isLeafCascadingItem(), (view: view, identifier: item.identifier)
    )
    if leaf.isSome:
      return leaf.get()
  if item.leaf:
    return true
  not view.itemHasChildren(item.identifier)

proc cascadingRowForIdentifier(
    view: CascadingView, parentIdentifier, identifier: string
): int =
  if identifier.len == 0:
    return -1
  view.refreshChildrenForParent(parentIdentifier)
  view.xChildrenByParent[parentIdentifier].visibleIndexByIdentifier.getOrDefault(
    identifier, -1
  )

proc indexOfChildIdentifier*(
    view: CascadingView, parentIdentifier, identifier: string
): int =
  view.cascadingRowForIdentifier(parentIdentifier, identifier)

proc itemForColumnRow(view: CascadingView, column, row: int): CascadingItem =
  if row < 0:
    return
  let parentIdentifier = view.parentIdentifierForColumn(column)
  view.refreshChildrenForParent(parentIdentifier)
  if row in 0 ..< view.xChildrenByParent[parentIdentifier].items.len:
    result = view.xChildrenByParent[parentIdentifier].items[row]

proc titleForItem(view: CascadingView, item: CascadingItem): string =
  if item.identifier in view.xTitleByIdentifier:
    return view.xTitleByIdentifier[item.identifier]
  let cachedItem = view.cacheCascadingItem(item)
  view.xTitleByIdentifier.getOrDefault(cachedItem.identifier, cachedItem.identifier)

proc normalizedSearchTextForItem(view: CascadingView, item: CascadingItem): string =
  if item.identifier notin view.xNormalizedSearchTextByIdentifier:
    discard view.cacheCascadingItem(item)
  view.xNormalizedSearchTextByIdentifier.getOrDefault(item.identifier)

proc syncCascadingColumnStyle(view: CascadingView, tableView: TableView) =
  let transparent = color(0.0, 0.0, 0.0, 0.0)
  let
    styleId = view.styleId()
    styleClasses = view.styleClasses()
  tableView.tableRole = srCascadingColumn
  tableView.rowItemRole = srCascadingRowItem
  tableView.styleId = styleId
  tableView.styleClasses = styleClasses
  let scrollView = tableView.scrollView()
  scrollView.scrollViewRole = srCascadingScrollView
  scrollView.scrollerRole = srCascadingScroller
  scrollView.styleId = styleId
  scrollView.styleClasses = styleClasses
  scrollView.background = transparent

proc syncCascadingStyle(view: CascadingView) =
  let transparent = color(0.0, 0.0, 0.0, 0.0)
  let
    styleId = view.styleId()
    styleClasses = view.styleClasses()
  view.xScrollView.scrollViewRole = srCascadingScrollView
  view.xScrollView.scrollerRole = srCascadingScroller
  view.xScrollView.styleId = styleId
  view.xScrollView.styleClasses = styleClasses
  view.xScrollView.drawsBackground = false
  view.xScrollView.background = transparent
  view.xColumnContainer.styleId = styleId
  view.xColumnContainer.styleClasses = styleClasses
  view.xColumnContainer.background = transparent
  for tableView in view.xColumns:
    view.syncCascadingColumnStyle(tableView)

proc selectionFor(
    view: CascadingView, column, row: int, item: CascadingItem
): CascadingSelection =
  CascadingSelection(
    column: column,
    row: row,
    identifier: item.identifier,
    title: view.titleForItem(item),
    objectValue:
      if item.objectValue.isNilOrEmpty():
        view.cascadingItemObjectValue(item.identifier)
      else:
        item.objectValue,
    leaf: view.cascadingItemIsLeaf(item),
    representedObject: item.representedObject,
  )

proc selectedPath*(view: CascadingView): seq[string] =
  view.xSelectedPath

proc postCascadingSelectionNotification(view: CascadingView) =
  var selectedIndexes: seq[int]
  var parent = ""
  for identifier in view.xSelectedPath:
    let row = view.indexOfChildIdentifier(parent, identifier)
    selectedIndexes.add row
    parent = identifier
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      nkSelectionDidChange,
      sender = DynamicAgent(view),
      representedObject = view.selectedItem().representedObject,
      payload = initSelectionNotificationPayload(
        sckCascading,
        selectedIdentifiers = view.xSelectedPath,
        anchorIdentifier =
          if view.xSelectedPath.len > 0:
            view.xSelectedPath[0]
          else:
            "",
        leadIdentifier =
          if view.xSelectedPath.len > 0:
            view.xSelectedPath[^1]
          else:
            "",
        selectedIndex =
          if selectedIndexes.len > 0:
            selectedIndexes[^1]
          else:
            -1,
        selectedIndexes = selectedIndexes,
      ),
    )
  )

proc notifyCascadingSelectionDidChange(view: CascadingView) =
  emit view.selectionDidChange(DynamicAgent(view))
  view.postAccessibilityNotification(anSelectionChanged)
  view.postCascadingSelectionNotification()

proc `selectedPath=`*(view: CascadingView, path: openArray[string]) =
  view.applySelectedPath(path)

proc selectedItem*(view: CascadingView): CascadingSelection =
  if view.xSelectedPath.len == 0:
    return CascadingSelection(column: -1, row: -1)
  let
    column = view.xSelectedPath.high
    identifier = view.xSelectedPath[^1]
    parent = view.parentIdentifierForColumn(column)
    row = view.cascadingRowForIdentifier(parent, identifier)
    item = view.cascadingItemWithIdentifier(identifier)
  view.selectionFor(column, row, item)

proc activatedIdentifier*(view: CascadingView): string =
  view.xActivatedIdentifier

proc desiredColumnCount(view: CascadingView): int =
  if view.xSelectedPath.len == 0:
    return 1
  let selected = view.xSelectedPath[^1]
  if view.itemHasChildren(selected):
    view.xSelectedPath.len + 1
  else:
    view.xSelectedPath.len

proc cascadingRowItemStyle(
    view: CascadingView, appearance: Appearance, states: set[WidgetState] = {}
): RowItemStyle =
  appearance.resolveRowItemStyle(
    controlStyle(
      srCascadingRowItem, states, id = view.styleId(), classes = view.styleClasses()
    )
  )

func hasMatchingContentWidthMetrics(
    cache: CascadingChildrenCache, style: RowItemStyle
): bool =
  cache.contentWidthMeasurementValid and cache.measuredFontName == style.text.fontName and
    cache.measuredFontSize == style.text.fontSize and
    cache.measuredTextInsets == style.text.insets and
    cache.measuredRowMinWidth == style.minSize.width

proc measuredContentWidthForParent(
    view: CascadingView, parentIdentifier: string, style: RowItemStyle
): float32 =
  view.refreshChildrenForParent(parentIdentifier)
  var cache = view.xChildrenByParent[parentIdentifier]
  if cache.hasMatchingContentWidthMetrics(style):
    return cache.measuredContentWidth

  let trailingInset = max(
    style.text.insets.right,
    CascadingChildArrowRightInset + CascadingChildArrowWidth + CascadingChildArrowTextGap,
  )
  result = style.minSize.width
  for item in cache.items:
    let textWidth = textNaturalSize(view.titleForItem(item), style.text).width
    result = max(
      result,
      textWidth + style.text.insets.left + trailingInset +
        CascadingColumnEdgeInset * 2.0'f32,
    )

  cache.measuredContentWidth = result
  cache.measuredFontName = style.text.fontName
  cache.measuredFontSize = style.text.fontSize
  cache.measuredTextInsets = style.text.insets
  cache.measuredRowMinWidth = style.minSize.width
  cache.contentWidthMeasurementValid = true
  view.xChildrenByParent[parentIdentifier] = cache

proc widthForColumn(view: CascadingView, column: int, style: RowItemStyle): float32 =
  max(
    max(view.xColumnWidth, view.xMinColumnWidth),
    view.measuredContentWidthForParent(view.parentIdentifierForColumn(column), style),
  )

proc columnsContentWidth(view: CascadingView): float32 =
  if view.xColumns.len == 0:
    return max(view.xColumnWidth, view.xMinColumnWidth)
  let
    count = view.xColumns.len
    spacing = view.xColumnSpacing * max(count - 1, 0).float32
    style = view.cascadingRowItemStyle(view.effectiveAppearance())
  result = spacing
  for column in 0 ..< count:
    result += view.widthForColumn(column, style)

proc syncCascadingLayout(view: CascadingView) =
  view.syncCascadingStyle()
  let bounds = view.bounds()
  let
    contentWidth = view.columnsContentWidth()
    documentWidth = max(contentWidth, bounds.size.width)
    oldOffset = view.xScrollView.contentOffset()
  view.xScrollView.frame = bounds
  view.xColumnContainer.frame =
    rect(0.0'f32, 0.0'f32, documentWidth, bounds.size.height)
  view.xScrollView.tile()
  let
    viewport = view.xScrollView.viewportSize()
    documentHeight = viewport.height
    style = view.cascadingRowItemStyle(view.effectiveAppearance())
  view.xColumnContainer.frame =
    rect(0.0'f32, 0.0'f32, max(contentWidth, viewport.width), documentHeight)
  if view.xColumns.len == 0:
    view.xScrollView.tile()
    view.xScrollView.contentOffset = oldOffset
    return
  var x = 0.0'f32
  for index, tableView in view.xColumns:
    let columnWidth = view.widthForColumn(index, style)
    tableView.frame = rect(x, 0.0'f32, columnWidth, documentHeight)
    let column = tableView.columnAt(0)
    if not column.isNil:
      column.width = max(columnWidth - CascadingColumnEdgeInset * 2.0'f32, 0.0'f32)
    x += columnWidth
    if index < view.xColumns.high:
      x += view.xColumnSpacing
  view.xScrollView.tile()
  view.xScrollView.contentOffset = oldOffset

proc scrollColumnToVisible(view: CascadingView, column: int) =
  if column notin 0 ..< view.xColumns.len:
    return
  let tableView = view.xColumns[column]
  if tableView.frame().isEmpty:
    return
  discard view.xScrollView.scrollRectToVisible(tableView.frame())

proc updateColumnSelections(view: CascadingView) =
  view.xSyncingColumnSelection = true
  try:
    for columnIndex, tableView in view.xColumns:
      tableView.reloadData()
      if columnIndex in 0 ..< view.xSelectedPath.len:
        let row = view.cascadingRowForIdentifier(
          view.parentIdentifierForColumn(columnIndex), view.xSelectedPath[columnIndex]
        )
        tableView.selectedIndex = row
      else:
        tableView.selectedIndex = -1
  finally:
    view.xSyncingColumnSelection = false

proc initCascadingTableView(view: CascadingView): TableView =
  result = newTableView()
  view.syncCascadingColumnStyle(result)
  result.showsHeader = view.xShowsColumnHeaders
  result.usesAlternatingRowBackgrounds = false
  result.selectionMode = tsmSingle
  result.dataSource = DynamicAgent(view)
  result.delegate = DynamicAgent(view)
  let column = newTableColumn("item", width = view.xColumnWidth)
  column.resizePolicy = tcrFixed
  result.addColumn(column)
  `hasHorizontalScroller=`(result.scrollView(), false)
  result.autoresizingMaskConstraints = false
  result.setAcceptsFirstResponder(true)

proc focusedColumnTable(view: CascadingView): TableView =
  let owner = view.window()
  if not (owner of Window):
    return nil
  let responder = Window(owner).firstResponder()
  if responder of TableView:
    let tableView = TableView(responder)
    if view.columnForTableView(tableView) >= 0:
      return tableView
  nil

proc focusColumn(view: CascadingView, column: int): bool =
  if column notin 0 ..< view.xColumns.len:
    return false
  let tableView = view.xColumns[column]
  let owner = tableView.window()
  result =
    if owner of Window:
      Window(owner).makeFirstResponder(tableView)
    else:
      false
  view.scrollColumnToVisible(column)

proc clearSelectionFromColumn(view: CascadingView, column: int) =
  if column < 0 or view.xSelectedPath.len <= column:
    return
  var nextPath = view.xSelectedPath
  nextPath.setLen(column)
  view.applySelectedPath(nextPath)

proc focusColumnRelative(view: CascadingView, delta: int): bool =
  if delta == 0:
    return false
  let tableView = view.focusedColumnTable()
  if tableView.isNil:
    return false
  let column = view.columnForTableView(tableView)
  let nextColumn = column + delta
  if nextColumn notin 0 ..< view.xColumns.len:
    return false
  if delta > 0:
    let nextTableView = view.tableViewForColumn(nextColumn)
    if nextTableView.selectedIndex() < 0 and nextTableView.rowCount() > 0:
      view.selectItem(nextColumn, 0)
  elif delta < 0:
    view.clearSelectionFromColumn(column)
  view.focusColumn(nextColumn)

proc syncCascadingColumns(view: CascadingView) =
  let needed = view.desiredColumnCount()
  while view.xColumns.len > needed:
    let tableView = view.xColumns[^1]
    view.xColumns.setLen(view.xColumns.len - 1)
    tableView.removeFromSuperview()
  while view.xColumns.len < needed:
    let tableView = view.initCascadingTableView()
    view.xColumns.add tableView
    view.xColumnContainer.addSubview(tableView)
  view.syncCascadingStyle()
  view.syncCascadingLayout()
  view.updateColumnSelections()

proc pruneSelectedPath(view: CascadingView) =
  var parent = ""
  var nextPath: seq[string]
  for identifier in view.xSelectedPath:
    let row = view.cascadingRowForIdentifier(parent, identifier)
    if row < 0:
      break
    nextPath.add identifier
    if not view.itemHasChildren(identifier):
      break
    parent = identifier
  view.xSelectedPath = nextPath

proc normalizedSelectedPath(view: CascadingView, path: openArray[string]): seq[string] =
  let oldPath = view.xSelectedPath
  view.xSelectedPath = @path
  view.pruneSelectedPath()
  result = view.xSelectedPath
  view.xSelectedPath = oldPath

proc preserveSelectedPathAfterDataChange(view: CascadingView): bool =
  let
    oldPath = view.xSelectedPath
    nextPath = view.normalizedSelectedPath(oldPath)
  if oldPath == nextPath:
    view.xSelectedPath = nextPath
    return false
  emit view.selectionIsChanging(DynamicAgent(view))
  view.xSelectedPath = nextPath
  true

proc applySelectedPath(view: CascadingView, path: openArray[string]) =
  let nextPath = view.normalizedSelectedPath(path)
  if view.xSelectedPath == nextPath:
    view.updateColumnSelections()
    return
  emit view.selectionIsChanging(DynamicAgent(view))
  view.xSelectedPath = nextPath
  view.invalidateIntrinsicContentSize()
  view.syncCascadingColumns()
  view.scrollColumnToVisible(min(view.xSelectedPath.len, view.xColumns.high))
  view.notifyCascadingSelectionDidChange()

proc reloadData*(view: CascadingView) =
  view.refreshCascadingModelCaches()
  let selectionChanged = view.preserveSelectedPathAfterDataChange()
  view.syncCascadingColumns()
  view.scrollColumnToVisible(min(view.xSelectedPath.len, view.xColumns.high))
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)
  if selectionChanged:
    view.notifyCascadingSelectionDidChange()

proc reloadColumn*(view: CascadingView, column: int) =
  if column < 0:
    return
  if column < view.xSelectedPath.len:
    view.xSelectedPath.setLen(column)
  view.reloadData()

proc columnForParentIdentifier(view: CascadingView, parentIdentifier: string): int =
  if parentIdentifier.len == 0:
    return 0
  for index, identifier in view.xSelectedPath:
    if identifier == parentIdentifier:
      return index + 1
  -1

proc tableRowUpdate(update: CascadingTreeUpdate): TableRowUpdate =
  case update.kind
  of ctukInsert:
    initTableRowInsertUpdate(update.indexes, update.identifiers)
  of ctukRemove:
    initTableRowRemoveUpdate(update.indexes, update.identifiers)
  of ctukMove:
    initTableRowMoveUpdate(update.fromIndex, update.toIndex, update.identifiers)
  of ctukReload:
    initTableRowReloadUpdate(update.indexes, update.identifiers)

proc postCascadingModelNotification(
    view: CascadingView, updates: openArray[CascadingTreeUpdate]
) =
  if updates.len == 0:
    return
  var identifiers: seq[string]
  var firstIndex = -1
  for update in updates:
    if firstIndex < 0 and update.indexes.len > 0:
      firstIndex = update.indexes[0]
    for identifier in update.identifiers:
      if identifier notin identifiers:
        identifiers.add identifier
  let representedObject =
    if identifiers.len > 0:
      view.cascadingItemRepresentedObject(identifiers[0])
    else:
      nil
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      nkModelMutationDidChange,
      sender = DynamicAgent(view),
      representedObject = representedObject,
      payload = initModelNotificationPayload(
        if updates.len == 1: mmkTreeChanged else: mmkBatchChanged,
        identifiers = identifiers,
        index = firstIndex,
        count = view.childrenForParent(updates[0].parentIdentifier).len.Natural,
      ),
    )
  )

proc restoreFocusedColumn(view: CascadingView, column: int) =
  if column < 0:
    return
  if column in 0 ..< view.xColumns.len:
    discard view.focusColumn(column)

proc flushCascadingTreeUpdates(
    view: CascadingView, updates: openArray[CascadingTreeUpdate]
) =
  if updates.len == 0:
    return
  view.refreshCascadingModelCaches()
  let
    focusedColumn = view.columnForTableView(view.focusedColumnTable())
    selectionChanged = view.preserveSelectedPathAfterDataChange()
  view.syncCascadingColumns()
  for update in updates:
    let column = view.columnForParentIdentifier(update.parentIdentifier)
    if column in 0 ..< view.xColumns.len:
      view.xColumns[column].applyTableRowUpdates([update.tableRowUpdate()])
  view.scrollColumnToVisible(min(view.xSelectedPath.len, view.xColumns.high))
  view.restoreFocusedColumn(focusedColumn)
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)
  emit view.cascadingItemsDidUpdate(DynamicAgent(view), @updates)
  view.postAccessibilityNotification(anValueChanged)
  view.postCascadingModelNotification(updates)
  if selectionChanged:
    view.notifyCascadingSelectionDidChange()

proc beginCascadingUpdates*(view: CascadingView) =
  inc view.xBatchUpdateDepth

proc endCascadingUpdates*(view: CascadingView) =
  if view.xBatchUpdateDepth <= 0:
    return
  dec view.xBatchUpdateDepth
  if view.xBatchUpdateDepth == 0 and view.xPendingTreeUpdates.len > 0:
    let updates = view.xPendingTreeUpdates
    view.xPendingTreeUpdates.setLen(0)
    view.flushCascadingTreeUpdates(updates)

proc applyCascadingTreeUpdates*(
    view: CascadingView, updates: openArray[CascadingTreeUpdate]
) =
  if updates.len == 0:
    return
  if view.xBatchUpdateDepth > 0:
    for update in updates:
      view.xPendingTreeUpdates.add update
    return
  view.flushCascadingTreeUpdates(updates)

proc reloadChildrenForParent*(view: CascadingView, parentIdentifier: string) =
  view.refreshCascadingModelCaches()
  let children = view.childrenForParent(parentIdentifier)
  var
    indexes: seq[int]
    identifiers: seq[string]
  for index, item in children:
    indexes.add index
    identifiers.add item.identifier
  view.applyCascadingTreeUpdates(
    [initCascadingTreeReloadUpdate(parentIdentifier, indexes, identifiers)]
  )

proc insertChildrenForParent*(
    view: CascadingView,
    parentIdentifier: string,
    indexes: openArray[int],
    identifiers: openArray[string] = [],
) =
  view.applyCascadingTreeUpdates(
    [initCascadingTreeInsertUpdate(parentIdentifier, indexes, identifiers)]
  )

proc removeChildrenForParent*(
    view: CascadingView,
    parentIdentifier: string,
    indexes: openArray[int],
    identifiers: openArray[string] = [],
) =
  view.applyCascadingTreeUpdates(
    [initCascadingTreeRemoveUpdate(parentIdentifier, indexes, identifiers)]
  )

proc moveChildForParent*(
    view: CascadingView,
    parentIdentifier: string,
    fromIndex, toIndex: int,
    identifiers: openArray[string] = [],
) =
  view.applyCascadingTreeUpdates(
    [initCascadingTreeMoveUpdate(parentIdentifier, fromIndex, toIndex, identifiers)]
  )

proc localStorageIndexForChildIndex(
    view: CascadingView, parentIdentifier: string, childIndex: int
): int =
  let target = max(childIndex, 0)
  var
    sibling = 0
    lastSiblingIndex = -1
  for index, item in view.xItems:
    if item.parentIdentifier == parentIdentifier:
      if sibling == target:
        return index
      lastSiblingIndex = index
      inc sibling
  if lastSiblingIndex >= 0:
    lastSiblingIndex + 1
  else:
    view.xItems.len

proc localDescendantIdentifiers(view: CascadingView, identifier: string): seq[string] =
  if identifier.len == 0:
    return
  for item in view.xItems:
    if item.parentIdentifier == identifier:
      result.add item.identifier
      for child in view.localDescendantIdentifiers(item.identifier):
        result.add child

proc deleteLocalIdentifiers(view: CascadingView, identifiers: openArray[string]) =
  if identifiers.len == 0:
    return
  var index = view.xItems.high
  while index >= 0:
    if view.xItems[index].identifier in identifiers:
      view.xItems.delete(index)
    dec index

proc insertCascadingItems*(
    view: CascadingView,
    parentIdentifier: string,
    index: int,
    items: openArray[CascadingItem],
) =
  if items.len == 0:
    return
  var
    indexes: seq[int]
    identifiers: seq[string]
    row = max(index, 0)
  for item in items:
    var next = item
    next.parentIdentifier = parentIdentifier
    let storageIndex = view.localStorageIndexForChildIndex(parentIdentifier, row)
    view.xItems.insert(next, storageIndex)
    indexes.add row
    identifiers.add next.identifier
    inc row
  view.insertChildrenForParent(parentIdentifier, indexes, identifiers)

proc removeCascadingItem*(
    view: CascadingView, identifier: string
): bool {.discardable.} =
  if identifier.len == 0:
    return false
  let found = view.localItemWithIdentifier(identifier)
  if not found.found:
    return false
  let
    parentIdentifier = found.item.parentIdentifier
    row = view.indexOfChildIdentifier(parentIdentifier, identifier)
  var identifiers = @[identifier]
  for child in view.localDescendantIdentifiers(identifier):
    identifiers.add child
  view.deleteLocalIdentifiers(identifiers)
  view.removeChildrenForParent(parentIdentifier, [row], [identifier])
  true

proc moveCascadingItem*(
    view: CascadingView, identifier, parentIdentifier: string, index: int
): bool {.discardable.} =
  if identifier.len == 0:
    return false
  let sourceIndex = view.localItemWithIdentifier(identifier)
  if not sourceIndex.found:
    return false
  let
    oldParent = sourceIndex.item.parentIdentifier
    oldRow = view.indexOfChildIdentifier(oldParent, identifier)
  var storageIndex = -1
  for index, item in view.xItems:
    if item.identifier == identifier:
      storageIndex = index
      break
  if storageIndex < 0:
    return false
  var item = view.xItems[storageIndex]
  view.xItems.delete(storageIndex)
  item.parentIdentifier = parentIdentifier
  let targetStorageIndex = view.localStorageIndexForChildIndex(parentIdentifier, index)
  view.xItems.insert(item, targetStorageIndex)
  view.refreshCascadingModelCaches()
  let newRow = view.indexOfChildIdentifier(parentIdentifier, identifier)
  if oldParent == parentIdentifier:
    view.moveChildForParent(parentIdentifier, oldRow, newRow, [identifier])
  else:
    view.applyCascadingTreeUpdates(
      [
        initCascadingTreeRemoveUpdate(oldParent, [oldRow], [identifier]),
        initCascadingTreeInsertUpdate(parentIdentifier, [newRow], [identifier]),
      ]
    )
  true

proc selectItem*(view: CascadingView, column, row: int) =
  if column < 0:
    return
  let item = view.itemForColumnRow(column, row)
  if item.identifier.len == 0:
    return
  let delegate = view.delegate()
  if not delegate.isNil:
    let allowed = delegate.trySendLocal(
      shouldSelectCascadingItem(),
      (view: view, column: column, row: row, identifier: item.identifier),
    )
    if allowed.isSome and not allowed.get():
      view.updateColumnSelections()
      return

  var nextPath = view.xSelectedPath
  if nextPath.len > column:
    nextPath.setLen(column)
  while nextPath.len < column:
    nextPath.add ""
  if nextPath.len == column:
    nextPath.add item.identifier
  else:
    nextPath[column] = item.identifier
  nextPath = view.normalizedSelectedPath(nextPath)

  if view.xSelectedPath == nextPath:
    view.updateColumnSelections()
    return

  emit view.selectionIsChanging(DynamicAgent(view))
  view.xSelectedPath = nextPath
  view.invalidateIntrinsicContentSize()
  view.syncCascadingColumns()
  view.scrollColumnToVisible(min(column + 1, view.xColumns.high))
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didSelectCascadingItem(),
      (view: view, column: column, row: row, identifier: item.identifier),
    )
  view.notifyCascadingSelectionDidChange()

proc activateCascadingItem(view: CascadingView, column, row: int) =
  if column < 0 or row < 0:
    return
  let item = view.itemForColumnRow(column, row)
  if item.identifier.len == 0:
    return
  view.selectItem(column, row)
  view.xActivatedIdentifier = item.identifier
  let delegate = view.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didActivateCascadingItem(),
      (view: view, column: column, row: row, identifier: item.identifier),
    )
  emit view.itemWasActivated(DynamicAgent(view))
  discard view.sendAction()

proc cascadingChildArrowRect(rowBounds: Rect): Rect =
  let width = min(CascadingChildArrowWidth, rowBounds.size.width)
  rect(
    rowBounds.maxX - CascadingChildArrowRightInset - width,
    rowBounds.origin.y,
    width,
    rowBounds.size.height,
  )

proc drawCascadingChildArrow(context: DrawContext, rect: Rect, color: Color) =
  if context.isNil or rect.isEmpty:
    return
  let
    centerX = rect.origin.x + rect.size.width * 0.5'f32
    centerY = rect.origin.y + rect.size.height * 0.5'f32
  for index in 0 .. 2:
    let height = 7.0'f32 - index.float32 * 2.0'f32
    discard context.addRenderRectangle(
      context.renderRectFor(
        rect(
          centerX - 1.0'f32 + index.float32, centerY - height * 0.5'f32, 1.0'f32, height
        )
      ),
      fill(color),
    )

proc drawCascadingRowText(
    tableView: TableView,
    context: DrawContext,
    rowBounds: Rect,
    text: string,
    style: RowItemStyle,
    reservesArrowSpace: bool,
) =
  if text.len == 0:
    return
  var textRect = style.rowItemTextRect(rowBounds)
  if reservesArrowSpace:
    let maxTextX = max(
      textRect.origin.x,
      rowBounds.maxX - CascadingChildArrowRightInset - CascadingChildArrowWidth -
        CascadingChildArrowTextGap,
    )
    textRect.w = min(textRect.w, maxTextX - textRect.x)
  if textRect.isEmpty:
    return
  let textRoot = context.addRenderRectangle(
    context.renderRectFor(textRect), fill(color(0.0, 0.0, 0.0, 0.0)), clips = true
  )
  let column = tableView.columnAt(0)
  discard context.addText(
    DefaultDrawLevel,
    textRoot,
    textRect,
    clippedText(text, textRect.size.width, style.text),
    style.text,
    if column.isNil:
      taLeft
    else:
      column.alignment(),
  )

protocol CascadingTableDataSource of TableViewDataSource:
  method numberOfRows(view: CascadingView, tableView: TableView): int =
    let column = view.columnForTableView(tableView)
    if column < 0:
      return 0
    view.childrenForParent(view.parentIdentifierForColumn(column)).len

  method textForCell(
      view: CascadingView, tableView: TableView, row: int, column: TableColumn
  ): string =
    discard column
    let columnIndex = view.columnForTableView(tableView)
    if columnIndex < 0:
      return ""
    view.titleForItem(view.itemForColumnRow(columnIndex, row))

  method normalizedSearchTextForRow(
      view: CascadingView, tableView: TableView, row: int
  ): string =
    let columnIndex = view.columnForTableView(tableView)
    if columnIndex < 0:
      return ""
    view.normalizedSearchTextForItem(view.itemForColumnRow(columnIndex, row))

  method objectValueForCell(
      view: CascadingView, tableView: TableView, row: int, column: TableColumn
  ): ObjectValue =
    discard column
    let columnIndex = view.columnForTableView(tableView)
    if columnIndex < 0:
      return nilObjectValue()
    let item = view.itemForColumnRow(columnIndex, row)
    if item.identifier.len == 0:
      return nilObjectValue()
    view.cascadingItemObjectValue(item.identifier)

  method identifierForRow(view: CascadingView, tableView: TableView, row: int): string =
    let columnIndex = view.columnForTableView(tableView)
    if columnIndex < 0:
      return ""
    view.itemForColumnRow(columnIndex, row).identifier

  method rowForIdentifier(
      view: CascadingView, tableView: TableView, identifier: string
  ): int =
    let columnIndex = view.columnForTableView(tableView)
    if columnIndex < 0:
      return -1
    view.cascadingRowForIdentifier(
      view.parentIdentifierForColumn(columnIndex), identifier
    )

protocol CascadingTableDelegate of TableViewDelegate:
  method drawRow(
      view: CascadingView,
      tableView: TableView,
      context: DrawContext,
      rect: Rect,
      row: RowState,
  ) =
    let emptyRow = initRowState(row.index, "", states = row.states)
    tableView.drawTableRowItem(context, rect, emptyRow)
    if row.index < 0:
      return
    let
      column = view.columnForTableView(tableView)
      rowBounds = rect(0.0, 0.0, rect.size.width, rect.size.height)
      style = view.cascadingRowItemStyle(context.appearance, row.states)
    if column < 0:
      return
    let
      item = view.itemForColumnRow(column, row.index)
      hasChildren = view.itemHasChildren(item.identifier)
    tableView.drawCascadingRowText(
      context, rowBounds, view.titleForItem(item), style, hasChildren
    )
    if hasChildren:
      context.drawCascadingChildArrow(
        rowBounds.cascadingChildArrowRect(), style.text.color
      )

  method tableRowHeight(view: CascadingView, tableView: TableView, row: int): float32 =
    discard row
    let column = view.columnForTableView(tableView)
    let delegate = view.delegate()
    if column >= 0 and not delegate.isNil:
      let height = delegate.trySendLocal(
        rowHeightForCascadingColumn(), (view: view, column: column)
      )
      if height.isSome:
        return height.get()
    tableView.rowHeight()

  method shouldSelectTableRow(
      view: CascadingView, tableView: TableView, row: int
  ): bool =
    let column = view.columnForTableView(tableView)
    if column < 0:
      return false
    let item = view.itemForColumnRow(column, row)
    if item.identifier.len == 0:
      return false
    let delegate = view.delegate()
    if delegate.isNil:
      return true
    let allowed = delegate.trySendLocal(
      shouldSelectCascadingItem(),
      (view: view, column: column, row: row, identifier: item.identifier),
    )
    if allowed.isSome:
      allowed.get()
    else:
      true

  method didSelectTableRow(view: CascadingView, tableView: TableView, row: int) =
    if view.xSyncingColumnSelection:
      return
    view.selectItem(view.columnForTableView(tableView), row)

  method didActivateRow(view: CascadingView, tableView: TableView, row: int) =
    let column = view.columnForTableView(tableView)
    view.activateCascadingItem(column, row)

  method shouldEditCell(
      view: CascadingView, tableView: TableView, row: int, column: TableColumn
  ): bool =
    discard view
    discard tableView
    discard row
    discard column
    false

protocol CascadingViewKeyEvents of ResponderEventProtocol:
  method keyDown(view: CascadingView, event: KeyEvent): bool =
    if event.modifiers != {}:
      return false
    case event.key
    of keyArrowLeft:
      view.focusColumnRelative(-1)
    of keyArrowRight:
      view.focusColumnRelative(1)
    else:
      false

protocol CascadingViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: CascadingView): IntrinsicSize =
    let
      width = view.columnsContentWidth()
      height = max(view.tableViewForColumn(0).rowHeight() * 5.0'f32, 96.0'f32)
    initIntrinsicSize(initSize(width, height))

  method layoutSubviews(view: CascadingView) =
    view.syncCascadingLayout()

protocol CascadingSelectionBehavior of CascadingSelectionProtocol:
  method selectionPath(view: CascadingView): seq[string] =
    view.xSelectedPath

  method setSelectionPath(view: CascadingView, path: seq[string]) =
    view.applySelectedPath(path)

  method selectItemAt(view: CascadingView, column, row: int) =
    view.selectItem(column, row)

  method currentSelection(view: CascadingView): CascadingSelection =
    selectedItem(view)

protocol CascadingReloadBehavior of CascadingReloadProtocol:
  method reloadViewData(view: CascadingView) =
    reloadData(view)

  method reloadViewColumn(view: CascadingView, column: int) =
    reloadColumn(view, column)

proc cascadingModelDidChange*(view: CascadingView, sender: DynamicAgent) {.slot.} =
  discard sender
  view.reloadData()

protocol CascadingDrawing of ViewDrawingProtocol:
  method draw(view: CascadingView, context: DrawContext) =
    if context.isNil or view.bounds().isEmpty:
      return
    view.syncCascadingStyle()
    let style = context.appearance.resolveTableViewStyle(
      controlStyle(
        srCascadingView,
        view.widgetStateSet(),
        id = view.styleId(),
        classes = view.styleClasses(),
      )
    )
    discard context.addRenderRectangle(
      context.renderRectFor(view.bounds()),
      style.box.fill,
      style.box.borderColor,
      style.box.borderWidth,
      style.box.cornerRadius,
      style.box.shadows,
      clips = true,
    )
    if view.isFocusVisible():
      context.addFocusRing(context.renderRectFor(view.bounds()), style.box)

protocol CascadingAccessibility of AccessibilityProtocol:
  method accessibilityRole(view: CascadingView): AccessibilityRole =
    arGroup

  method accessibilityLabel(view: CascadingView): string =
    if view.xAccessibilityLabel.len > 0: view.xAccessibilityLabel else: "CascadingView"

  method accessibilityValue(view: CascadingView): string =
    view.selectedPath().join("/")

  method accessibilityTraits(view: CascadingView): AccessibilityTraits =
    result = view.xAccessibilityTraits + {atSelectable}
    if ssDisabled in view.xWidgetStates:
      result.incl atDisabled
    if view.focused():
      result.incl atFocused

  method isAccessibilityElement(view: CascadingView): bool =
    true

proc initCascadingMillerColumn*(view: CascadingView, frame: Rect = AutoRect) =
  initControlFields(view, frame)
  view.background = color(0.0, 0.0, 0.0, 0.0)
  view.clipsToBounds = true
  view.xColumnWidth = CascadingDefaultColumnWidth
  view.xMinColumnWidth = CascadingDefaultMinColumnWidth
  view.xColumnSpacing = CascadingDefaultColumnSpacing
  view.xShowsColumnHeaders = false
  view.xColumnContainer = newView()
  view.xColumnContainer.autoresizingMaskConstraints = false
  view.xScrollView = newScrollView(documentView = view.xColumnContainer)
  view.xScrollView.drawsBackground = false
  view.xScrollView.hasHorizontalScroller = true
  view.xScrollView.hasVerticalScroller = false
  view.xScrollView.horizontalLineScroll = view.xColumnWidth
  view.xScrollView.autoresizingMaskConstraints = false
  view.addSubview(view.xScrollView)
  view.setAcceptsFirstResponder(false)
  discard view.withProto()
  discard view.withProtocol(CascadingTableDataSource)
  discard view.withProtocol(CascadingTableDelegate)
  discard view.withProtocol(CascadingViewLayout)
  discard view.withProtocol(CascadingSelectionBehavior)
  discard view.withProtocol(CascadingReloadBehavior)
  discard view.withProtocol(CascadingViewKeyEvents)
  discard view.withProtocol(CascadingDrawing)
  discard view.withProtocol(CascadingAccessibility)
  view.syncCascadingColumns()
  view.applyInitialFrame(frame)

proc initCascadingMillerColumn*(frame: Rect = AutoRect): CascadingView =
  result = CascadingView()
  result.initCascadingMillerColumn(frame)

proc newCascadingView*(frame: Rect = AutoRect): CascadingView =
  result = initCascadingMillerColumn(frame)
