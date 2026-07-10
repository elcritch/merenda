## Model-backed repeated-content views.
##
## `CollectionView` owns selection, reuse, item lifecycle, incremental view
## updates, and drag/drop coordination for repeated content. Layout is delegated
## to a `CollectionViewLayout` agent so list, grid, wrapped, and custom layouts
## can evolve independently from item storage.

import std/[algorithm, math, options, strutils, tables]

import sigils/core
import sigils/selectors

import ../accessibility/accessibilityprotocols
import ../app/dragging
import ../app/pasteboards
import ../app/windows
import ../controls/controls
import ../containers/listbasics
import ../containers/scrollviews
import ../drawing
import ../foundation/events
import ../foundation/objectvalues
import ../foundation/selectors
import ../foundation/types
import ../foundation/undomanagers
import ../themes
import ../view/views

export controls, dragging, objectvalues, views

const CollectionPasteboardTypeItems* = "nimkit.collection.items"

type
  CollectionSelectionMode* = enum
    csmNone
    csmSingle
    csmMultiple
    csmExtended

  CollectionLayoutKind* = enum
    clkList
    clkGrid
    clkWrapped
    clkCustom

  CollectionSupplementaryKind* = enum
    cskHeader
    cskFooter
    cskBackground
    cskCustom

  CollectionUpdateKind* = enum
    cukInsert
    cukRemove
    cukMove
    cukReload

  CollectionUpdate* = object
    kind*: CollectionUpdateKind
    indexes*: seq[int]
    fromIndex*: int
    toIndex*: int
    identifiers*: seq[string]

  CollectionItemState* = object
    index*: int
    identifier*: string
    objectValue*: ObjectValue
    text*: string
    rect*: Rect
    states*: set[WidgetState]

  CollectionVisibleItemSummary* = object
    index*: int
    identifier*: string
    text*: string
    rect*: Rect
    states*: set[WidgetState]

  CollectionItemSlot = object
    index: int
    identifier: string
    reuseIdentifier: string
    view: View

  CollectionViewLayout* = ref object of DynamicAgent
    xKind: CollectionLayoutKind
    xItemSize: Size
    xMinimumInteritemSpacing: float32
    xMinimumLineSpacing: float32
    xEdgeInsets: EdgeInsets
    xColumnCount: Natural

  CollectionItemView* = ref object of View
    xCollectionView: CollectionView
    xReuseIdentifier: string
    xItemIdentifier: string
    xItemIndex: int
    xObjectValue: ObjectValue
    xText: string
    xItemStates: set[WidgetState]

  CollectionSupplementaryView* = ref object of View
    xCollectionView: CollectionView
    xKind: CollectionSupplementaryKind
    xReuseIdentifier: string
    xElementIdentifier: string

  CollectionContentView = ref object of View
    xCollectionView: CollectionView

  CollectionView* = ref object of Control
    xDataSource: DynamicAgent
    xDelegate: DynamicAgent
    xLayout: DynamicAgent
    xScrollView: ScrollView
    xContentView: CollectionContentView
    xReusableItemViews: Table[string, seq[View]]
    xReusableSupplementaryViews: Table[string, seq[View]]
    xItemSlots: seq[CollectionItemSlot]
    xSupplementaryViews: Table[string, View]
    xItemCount: int
    xDefaultReuseIdentifier: string
    xSelectedIdentifiers: seq[string]
    xSelectionMode: CollectionSelectionMode
    xSelectionAnchorIdentifier: string
    xSelectionLeadIdentifier: string
    xHighlightedIdentifier: string
    xPressedIdentifier: string
    xTrackingItem: bool
    xCollectionRole: StyleRole
    xItemRole: StyleRole
    xCollectionDraggingSession: DraggingSession
    xDropTarget: DraggingDropTarget

const
  csvNone* = CollectionSelectionMode.csmNone
  csvSingle* = CollectionSelectionMode.csmSingle
  csvMultiple* = CollectionSelectionMode.csmMultiple
  csvExtended* = CollectionSelectionMode.csmExtended

proc collectionView*(contentView: CollectionContentView): CollectionView
proc scrollView*(collectionView: CollectionView): ScrollView
proc contentView*(collectionView: CollectionView): CollectionContentView
proc len*(collectionView: CollectionView): int
proc collectionItemIdentifier*(collectionView: CollectionView, index: int): string
proc collectionItemIndexForIdentifier*(
  collectionView: CollectionView, identifier: string
): int

proc collectionItemObjectValue*(collectionView: CollectionView, index: int): ObjectValue
proc collectionItemText*(collectionView: CollectionView, index: int): string
proc collectionItemState*(
  collectionView: CollectionView, index: int
): CollectionItemState

proc collectionItemRect*(collectionView: CollectionView, index: int): Rect
proc collectionItemIndexAtPoint*(collectionView: CollectionView, point: Point): int
proc visibleItemIndexes*(collectionView: CollectionView): seq[int]
proc reloadData*(collectionView: CollectionView)
proc dequeueReusableItemView*(collectionView: CollectionView, identifier: string): View
proc selectedIdentifiers*(collectionView: CollectionView): seq[string]
proc `selectedIdentifiers=`*(
  collectionView: CollectionView, identifiers: openArray[string]
)

proc selectedIndexes*(collectionView: CollectionView): seq[int]
proc `selectedIndexes=`*(collectionView: CollectionView, indexes: openArray[int])
proc selectedIndex*(collectionView: CollectionView): int
proc `selectedIndex=`*(collectionView: CollectionView, index: int)
proc selectItemAtIndex*(collectionView: CollectionView, index: int)
proc selectItemAtIndex*(
  collectionView: CollectionView, index: int, modifiers: set[KeyModifier]
)

proc activateItemAtIndex*(
  collectionView: CollectionView, index: int, modifiers: set[KeyModifier] = {}
)

proc scrollItemToVisible*(collectionView: CollectionView, index: int)
proc dropTargetForDraggingLocation*(
  collectionView: CollectionView, location: Point
): DraggingDropTarget

proc currentDropTarget*(collectionView: CollectionView): DraggingDropTarget
proc validateDragging*(
  collectionView: CollectionView, info: DraggingInfo
): DragOperations

proc acceptDragging*(collectionView: CollectionView, info: DraggingInfo): bool
proc installDefaultCollectionLayoutProtocols(layout: CollectionViewLayout)
proc installDefaultCollectionItemProtocols(itemView: CollectionItemView)
proc installDefaultCollectionSupplementaryProtocols(view: CollectionSupplementaryView)
proc installDefaultCollectionContentProtocols(contentView: CollectionContentView)
proc newCollectionItemView*(
  reuseIdentifier = "item", frame: Rect = AutoRect
): CollectionItemView

proc dequeueReusableSupplementaryView*(
  collectionView: CollectionView,
  kind: CollectionSupplementaryKind,
  reuseIdentifier: string,
): View

proc supplementaryView*(
  collectionView: CollectionView,
  kind: CollectionSupplementaryKind,
  identifier: string,
  reuseIdentifier = "",
): View

protocol CollectionLayoutProtocol {.selectorScope: protocol.}:
  method collectionContentSize*(
    collectionView: CollectionView, itemCount: int
  ): Size {.optional.}

  method rectForCollectionItem*(
    collectionView: CollectionView, index: int
  ): Rect {.optional.}

  method layoutItemIndexAtPoint*(
    collectionView: CollectionView, point: Point
  ): int {.optional.}

  method visibleCollectionItemIndexes*(
    collectionView: CollectionView, visibleRect: Rect
  ): seq[int] {.optional.}

protocol CollectionReusableViewProtocol {.selectorScope: protocol.}:
  method prepareForReuse*(
    collectionView: CollectionView, reuseIdentifier: string
  ) {.optional.}

  method applyCollectionItemState*(state: CollectionItemState) {.optional.}

protocol CollectionViewDataSource {.selectorScope: protocol.}:
  method numberOfCollectionItems*(collectionView: CollectionView): int {.optional.}

  method identifierForCollectionItem*(
    collectionView: CollectionView, index: int
  ): string {.optional.}

  method indexForCollectionItemIdentifier*(
    collectionView: CollectionView, identifier: string
  ): int {.optional.}

  method objectValueForCollectionItem*(
    collectionView: CollectionView, index: int
  ): ObjectValue {.optional.}

  method textForCollectionItem*(
    collectionView: CollectionView, index: int
  ): string {.optional.}

protocol CollectionViewEvents:
  proc collectionSelectionIsChanging*(
    collectionView: CollectionView, sender: DynamicAgent
  ) {.signal.}

  proc collectionSelectionDidChange*(
    collectionView: CollectionView, sender: DynamicAgent
  ) {.signal.}

  proc collectionItemWasActivated*(
    collectionView: CollectionView, sender: DynamicAgent, index: int, identifier: string
  ) {.signal.}

  proc collectionItemsDidUpdate*(
    collectionView: CollectionView, sender: DynamicAgent, updates: seq[CollectionUpdate]
  ) {.signal.}

protocol CollectionViewDelegate {.selectorScope: protocol.}:
  method reuseIdentifierForCollectionItem*(
    collectionView: CollectionView, index: int
  ): string {.optional.}

  method viewForCollectionItem*(
    collectionView: CollectionView, index: int, reuseIdentifier: string
  ): View {.optional.}

  method configureCollectionItemView*(
    collectionView: CollectionView,
    index: int,
    identifier: string,
    objectValue: ObjectValue,
    view: View,
  ) {.optional.}

  method supplementaryViewForCollectionElement*(
    collectionView: CollectionView,
    kind: CollectionSupplementaryKind,
    identifier: string,
    reuseIdentifier: string,
  ): View {.optional.}

  method shouldSelectCollectionItem*(
    collectionView: CollectionView, index: int, identifier: string
  ): bool {.optional.}

  method didSelectCollectionItem*(
    collectionView: CollectionView, index: int, identifier: string
  ) {.optional.}

  method didActivateCollectionItem*(
    collectionView: CollectionView, index: int, identifier: string
  ) {.optional.}

  method draggingItemsForCollectionItems*(
    collectionView: CollectionView, identifiers: seq[string], pasteboardName: string
  ): seq[DraggingItem] {.optional.}

  method validateCollectionDropOperation*(
    collectionView: CollectionView,
    info: DraggingInfo,
    proposedOperation: DragOperations,
    target: DraggingDropTarget,
    position: DraggingDropPosition,
  ): DragOperations {.optional.}

  method acceptCollectionDropOperation*(
    collectionView: CollectionView,
    info: DraggingInfo,
    operation: DragOperations,
    target: DraggingDropTarget,
    position: DraggingDropPosition,
  ): bool {.optional.}

  method collectionDropTargetForLocation*(
    collectionView: CollectionView, location: Point, proposedTarget: DraggingDropTarget
  ): DraggingDropTarget {.optional.}

func normalizedMetric(value, fallback: float32): float32 =
  if value.isNaN:
    fallback
  else:
    max(value, 0.0'f32)

func normalizedItemSize(size: Size): Size =
  initSize(
    size.width.normalizedMetric(96.0'f32), size.height.normalizedMetric(64.0'f32)
  )

func normalizedSpacing(value: float32): float32 =
  max(value, 0.0'f32)

func normalizedInsets(insets: EdgeInsets): EdgeInsets =
  insets(
    max(insets.top, 0.0'f32),
    max(insets.left, 0.0'f32),
    max(insets.bottom, 0.0'f32),
    max(insets.right, 0.0'f32),
  )

func rowCount(itemCount, columns: int): int =
  if itemCount <= 0:
    0
  else:
    (itemCount + max(columns, 1) - 1) div max(columns, 1)

func defaultCollectionUpdate(
    kind: CollectionUpdateKind,
    indexes: openArray[int] = [],
    identifiers: openArray[string] = [],
    fromIndex = -1,
    toIndex = -1,
): CollectionUpdate =
  CollectionUpdate(
    kind: kind,
    indexes: @indexes,
    fromIndex: fromIndex,
    toIndex: toIndex,
    identifiers: @identifiers,
  )

func initCollectionInsertUpdate*(
    indexes: openArray[int], identifiers: openArray[string] = []
): CollectionUpdate =
  defaultCollectionUpdate(cukInsert, indexes, identifiers)

func initCollectionRemoveUpdate*(
    indexes: openArray[int], identifiers: openArray[string] = []
): CollectionUpdate =
  defaultCollectionUpdate(cukRemove, indexes, identifiers)

func initCollectionReloadUpdate*(
    indexes: openArray[int], identifiers: openArray[string] = []
): CollectionUpdate =
  defaultCollectionUpdate(cukReload, indexes, identifiers)

func initCollectionMoveUpdate*(
    fromIndex, toIndex: int, identifiers: openArray[string] = []
): CollectionUpdate =
  defaultCollectionUpdate(
    cukMove, identifiers = identifiers, fromIndex = fromIndex, toIndex = toIndex
  )

proc collectionView*(contentView: CollectionContentView): CollectionView =
  contentView.xCollectionView

proc scrollView*(collectionView: CollectionView): ScrollView =
  collectionView.xScrollView

proc contentView*(collectionView: CollectionView): CollectionContentView =
  collectionView.xContentView

proc initCollectionViewLayoutFields*(
    layout: CollectionViewLayout,
    kind = clkWrapped,
    itemSize = initSize(96.0, 64.0),
    minimumInteritemSpacing = 8.0'f32,
    minimumLineSpacing = 8.0'f32,
    edgeInsets = insets(8.0),
    columnCount: Natural = 0,
) =
  layout.xKind = kind
  layout.xItemSize = itemSize.normalizedItemSize()
  layout.xMinimumInteritemSpacing = minimumInteritemSpacing.normalizedSpacing()
  layout.xMinimumLineSpacing = minimumLineSpacing.normalizedSpacing()
  layout.xEdgeInsets = edgeInsets.normalizedInsets()
  layout.xColumnCount = columnCount

proc newCollectionViewLayout*(
    kind = clkWrapped,
    itemSize = initSize(96.0, 64.0),
    minimumInteritemSpacing = 8.0'f32,
    minimumLineSpacing = 8.0'f32,
    edgeInsets = insets(8.0),
    columnCount: Natural = 0,
): CollectionViewLayout =
  result = CollectionViewLayout()
  result.initCollectionViewLayoutFields(
    kind, itemSize, minimumInteritemSpacing, minimumLineSpacing, edgeInsets, columnCount
  )
  result.installDefaultCollectionLayoutProtocols()

proc kind*(layout: CollectionViewLayout): CollectionLayoutKind =
  layout.xKind

proc `kind=`*(layout: CollectionViewLayout, kind: CollectionLayoutKind) =
  layout.xKind = kind

proc itemSize*(layout: CollectionViewLayout): Size =
  layout.xItemSize

proc `itemSize=`*(layout: CollectionViewLayout, itemSize: Size) =
  layout.xItemSize = itemSize.normalizedItemSize()

proc minimumInteritemSpacing*(layout: CollectionViewLayout): float32 =
  layout.xMinimumInteritemSpacing

proc `minimumInteritemSpacing=`*(layout: CollectionViewLayout, value: float32) =
  layout.xMinimumInteritemSpacing = value.normalizedSpacing()

proc minimumLineSpacing*(layout: CollectionViewLayout): float32 =
  layout.xMinimumLineSpacing

proc `minimumLineSpacing=`*(layout: CollectionViewLayout, value: float32) =
  layout.xMinimumLineSpacing = value.normalizedSpacing()

proc edgeInsets*(layout: CollectionViewLayout): EdgeInsets =
  layout.xEdgeInsets

proc `edgeInsets=`*(layout: CollectionViewLayout, edgeInsets: EdgeInsets) =
  layout.xEdgeInsets = edgeInsets.normalizedInsets()

proc columnCount*(layout: CollectionViewLayout): Natural =
  layout.xColumnCount

proc `columnCount=`*(layout: CollectionViewLayout, count: Natural) =
  layout.xColumnCount = count

func layoutAvailableWidth(
    layout: CollectionViewLayout, viewportWidth: float32
): float32 =
  let fallback =
    layout.edgeInsets().horizontal + layout.itemSize().width +
    layout.minimumInteritemSpacing()
  max(viewportWidth, fallback)

func layoutColumnCount(
    layout: CollectionViewLayout, itemCount: int, width: float32
): int =
  if itemCount <= 0:
    return 0
  let
    itemSize = layout.itemSize()
    insets = layout.edgeInsets()
    spacing = layout.minimumInteritemSpacing()
    availableWidth = max(width - insets.horizontal, itemSize.width)
  case layout.kind()
  of clkList:
    1
  of clkGrid:
    max(layout.columnCount().int, 1)
  of clkWrapped, clkCustom:
    if layout.columnCount() > 0:
      max(layout.columnCount().int, 1)
    else:
      max(int(floor((availableWidth + spacing) / (itemSize.width + spacing))), 1)

func layoutContentSize(
    layout: CollectionViewLayout, itemCount: int, viewportWidth: float32
): Size =
  let
    insets = layout.edgeInsets()
    itemSize = layout.itemSize()
    width = layout.layoutAvailableWidth(viewportWidth)
    columns = layout.layoutColumnCount(itemCount, width)
    rows = itemCount.rowCount(columns)
    lineSpacing =
      if rows <= 1:
        0.0'f32
      else:
        layout.minimumLineSpacing() * float32(rows - 1)
    interitemSpacing =
      if columns <= 1:
        0.0'f32
      else:
        layout.minimumInteritemSpacing() * float32(columns - 1)
    naturalWidth =
      case layout.kind()
      of clkList, clkWrapped, clkCustom:
        width
      of clkGrid:
        insets.horizontal + itemSize.width * float32(columns) + interitemSpacing
  initSize(
    naturalWidth, insets.vertical + itemSize.height * float32(rows) + lineSpacing
  )

func layoutItemRect(
    layout: CollectionViewLayout, itemCount, index: int, viewportWidth: float32
): Rect =
  if index < 0 or index >= itemCount:
    return rect(0.0, 0.0, 0.0, 0.0)
  let
    insets = layout.edgeInsets()
    itemSize = layout.itemSize()
    width = layout.layoutAvailableWidth(viewportWidth)
    columns = max(layout.layoutColumnCount(itemCount, width), 1)
    row = index div columns
    column = index mod columns
    itemWidth =
      if layout.kind() == clkList:
        max(width - insets.horizontal, 0.0'f32)
      else:
        itemSize.width
    x = insets.left + float32(column) * (itemWidth + layout.minimumInteritemSpacing())
    y = insets.top + float32(row) * (itemSize.height + layout.minimumLineSpacing())
  rect(x, y, itemWidth, itemSize.height)

proc collectionViewportSize(collectionView: CollectionView): Size =
  let scrollView = collectionView.scrollView()
  if scrollView.isNil:
    collectionView.bounds().size
  else:
    scrollView.viewportSize()

proc collectionContentOffset(collectionView: CollectionView): Point =
  let scrollView = collectionView.scrollView()
  if scrollView.isNil:
    initPoint(0.0, 0.0)
  else:
    scrollView.contentOffset()

proc collectionVisibleContentRect(collectionView: CollectionView): Rect =
  rect(
    collectionView.collectionContentOffset(), collectionView.collectionViewportSize()
  )

proc resolvedLayout(collectionView: CollectionView): DynamicAgent =
  if collectionView.xLayout.isNil:
    collectionView.xLayout = DynamicAgent(newCollectionViewLayout())
  collectionView.xLayout

proc defaultLayout(collectionView: CollectionView): CollectionViewLayout =
  let layout = collectionView.resolvedLayout()
  if layout of CollectionViewLayout:
    CollectionViewLayout(layout)
  else:
    nil

proc resolvedContentSize(collectionView: CollectionView): Size =
  let
    layout = collectionView.resolvedLayout()
    count = collectionView.len()
  if not layout.isNil:
    let custom = layout.trySendLocal(
      collectionContentSize(), (collectionView: collectionView, itemCount: count)
    )
    if custom.isSome:
      return custom.get()
  let default = collectionView.defaultLayout()
  if default.isNil:
    initSize(0.0, 0.0)
  else:
    default.layoutContentSize(count, collectionView.collectionViewportSize().width)

proc resolvedContentItemRect(collectionView: CollectionView, index: int): Rect =
  if index < 0 or index >= collectionView.len():
    return rect(0.0, 0.0, 0.0, 0.0)
  let layout = collectionView.resolvedLayout()
  if not layout.isNil:
    let custom = layout.trySendLocal(
      rectForCollectionItem(), (collectionView: collectionView, index: index)
    )
    if custom.isSome:
      return custom.get()
  let default = collectionView.defaultLayout()
  if default.isNil:
    rect(0.0, 0.0, 0.0, 0.0)
  else:
    default.layoutItemRect(
      collectionView.len(), index, collectionView.collectionViewportSize().width
    )

proc resolvedIndexAtContentPoint(collectionView: CollectionView, point: Point): int =
  let layout = collectionView.resolvedLayout()
  if not layout.isNil:
    let custom = layout.trySendLocal(
      layoutItemIndexAtPoint(), (collectionView: collectionView, point: point)
    )
    if custom.isSome:
      return custom.get()
  for index in 0 ..< collectionView.len():
    if collectionView.resolvedContentItemRect(index).contains(point):
      return index
  -1

proc resolvedVisibleIndexes(collectionView: CollectionView): seq[int] =
  let
    layout = collectionView.resolvedLayout()
    visibleRect = collectionView.collectionVisibleContentRect()
  if not layout.isNil:
    let custom = layout.trySendLocal(
      visibleCollectionItemIndexes(),
      (collectionView: collectionView, visibleRect: visibleRect),
    )
    if custom.isSome:
      for index in custom.get():
        if index in 0 ..< collectionView.len() and index notin result:
          result.add index
      result.sort()
      return
  for index in 0 ..< collectionView.len():
    if not collectionView
    .resolvedContentItemRect(index)
    .intersection(visibleRect).isEmpty:
      result.add index

protocol DefaultCollectionLayout of CollectionLayoutProtocol:
  method collectionContentSize(
      layout: CollectionViewLayout, collectionView: CollectionView, itemCount: int
  ): Size =
    layout.layoutContentSize(itemCount, collectionView.collectionViewportSize().width)

  method rectForCollectionItem(
      layout: CollectionViewLayout, collectionView: CollectionView, index: int
  ): Rect =
    layout.layoutItemRect(
      collectionView.len(), index, collectionView.collectionViewportSize().width
    )

  method layoutItemIndexAtPoint(
      layout: CollectionViewLayout, collectionView: CollectionView, point: Point
  ): int =
    for index in 0 ..< collectionView.len():
      if layout
      .layoutItemRect(
        collectionView.len(), index, collectionView.collectionViewportSize().width
      )
      .contains(point):
        return index
    -1

  method visibleCollectionItemIndexes(
      layout: CollectionViewLayout, collectionView: CollectionView, visibleRect: Rect
  ): seq[int] =
    for index in 0 ..< collectionView.len():
      let rect = layout.layoutItemRect(
        collectionView.len(), index, collectionView.collectionViewportSize().width
      )
      if not rect.intersection(visibleRect).isEmpty:
        result.add index

proc installDefaultCollectionLayoutProtocols(layout: CollectionViewLayout) =
  discard layout.withProtocol(DefaultCollectionLayout)

proc collectionLayout*(collectionView: CollectionView): DynamicAgent =
  collectionView.resolvedLayout()

proc `collectionLayout=`*(collectionView: CollectionView, layout: DynamicAgent) =
  if collectionView.xLayout == layout:
    return
  if not layout.isNil:
    discard layout.adopt(CollectionLayoutProtocol)
  collectionView.xLayout = layout
  collectionView.reloadData()

proc `collectionLayout=`*(
    collectionView: CollectionView, layout: CollectionViewLayout
) =
  collectionView.collectionLayout = DynamicAgent(layout)

proc dataSource*(collectionView: CollectionView): DynamicAgent =
  collectionView.xDataSource

proc `dataSource=`*(collectionView: CollectionView, dataSource: DynamicAgent) =
  if collectionView.xDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(CollectionViewDataSource)
  collectionView.xDataSource = dataSource
  collectionView.reloadData()

proc `dataSource=`*(collectionView: CollectionView, dataSource: Responder) =
  collectionView.dataSource = DynamicAgent(dataSource)

proc delegate*(collectionView: CollectionView): DynamicAgent =
  collectionView.xDelegate

proc `delegate=`*(collectionView: CollectionView, delegate: DynamicAgent) =
  if collectionView.xDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(CollectionViewDelegate)
  collectionView.xDelegate = delegate
  collectionView.reloadData()

proc `delegate=`*(collectionView: CollectionView, delegate: Responder) =
  collectionView.delegate = DynamicAgent(delegate)

proc len*(collectionView: CollectionView): int =
  let source = collectionView.dataSource()
  if not source.isNil:
    let count = source.trySendLocal(numberOfCollectionItems(), collectionView)
    if count.isSome:
      return max(count.get(), 0)
  max(collectionView.xItemCount, 0)

proc collectionItemCount*(collectionView: CollectionView): int =
  collectionView.len()

proc `itemCount=`*(collectionView: CollectionView, count: int) =
  let nextCount = max(count, 0)
  if collectionView.xItemCount == nextCount:
    return
  collectionView.xItemCount = nextCount
  collectionView.reloadData()

proc defaultReuseIdentifier*(collectionView: CollectionView): string =
  collectionView.xDefaultReuseIdentifier

proc `defaultReuseIdentifier=`*(collectionView: CollectionView, identifier: string) =
  if collectionView.xDefaultReuseIdentifier == identifier:
    return
  collectionView.xDefaultReuseIdentifier = identifier

proc collectionRole*(collectionView: CollectionView): StyleRole =
  collectionView.xCollectionRole

proc `collectionRole=`*(collectionView: CollectionView, role: StyleRole) =
  if collectionView.xCollectionRole == role:
    return
  collectionView.xCollectionRole = role
  collectionView.setNeedsDisplay(true)

proc collectionItemRole*(collectionView: CollectionView): StyleRole =
  collectionView.xItemRole

proc `collectionItemRole=`*(collectionView: CollectionView, role: StyleRole) =
  if collectionView.xItemRole == role:
    return
  collectionView.xItemRole = role
  collectionView.setNeedsDisplay(true)

proc collectionItemIdentifier*(collectionView: CollectionView, index: int): string =
  if index notin 0 ..< collectionView.len():
    return ""
  let source = collectionView.dataSource()
  if not source.isNil:
    let identifier = source.trySendLocal(
      identifierForCollectionItem(), (collectionView: collectionView, index: index)
    )
    if identifier.isSome and identifier.get().len > 0:
      return identifier.get()
  $index

proc collectionItemIndexForIdentifier*(
    collectionView: CollectionView, identifier: string
): int =
  if identifier.len == 0:
    return -1
  let source = collectionView.dataSource()
  if not source.isNil:
    let index = source.trySendLocal(
      indexForCollectionItemIdentifier(),
      (collectionView: collectionView, identifier: identifier),
    )
    if index.isSome and index.get() in 0 ..< collectionView.len():
      return index.get()
  for index in 0 ..< collectionView.len():
    if collectionView.collectionItemIdentifier(index) == identifier:
      return index
  -1

proc collectionItemObjectValue*(
    collectionView: CollectionView, index: int
): ObjectValue =
  if index notin 0 ..< collectionView.len():
    return nilObjectValue()
  let source = collectionView.dataSource()
  if not source.isNil:
    let value = source.trySendLocal(
      objectValueForCollectionItem(), (collectionView: collectionView, index: index)
    )
    if value.isSome:
      return value.get()
    let text = source.trySendLocal(
      textForCollectionItem(), (collectionView: collectionView, index: index)
    )
    if text.isSome:
      return toObj(text.get())
  emptyObjectValue()

proc collectionItemText*(collectionView: CollectionView, index: int): string =
  if index notin 0 ..< collectionView.len():
    return ""
  let source = collectionView.dataSource()
  if not source.isNil:
    let text = source.trySendLocal(
      textForCollectionItem(), (collectionView: collectionView, index: index)
    )
    if text.isSome:
      return text.get()
  Control(collectionView).formatObjectValue(
    collectionView.collectionItemObjectValue(index), ovrLabel
  )

proc collectionItemEnabled(collectionView: CollectionView, index: int): bool =
  collectionView.collectionItemObjectValue(index).kind != ovValidationFailure

proc collectionItemSelectable(collectionView: CollectionView, index: int): bool =
  if index notin 0 ..< collectionView.len():
    return false
  if not collectionView.collectionItemEnabled(index):
    return false
  let
    identifier = collectionView.collectionItemIdentifier(index)
    delegate = collectionView.delegate()
  if not delegate.isNil:
    let selectable = delegate.trySendLocal(
      shouldSelectCollectionItem(),
      (collectionView: collectionView, index: index, identifier: identifier),
    )
    if selectable.isSome:
      return selectable.get()
  true

proc selectionContains(collectionView: CollectionView, identifier: string): bool =
  identifier.len > 0 and identifier in collectionView.xSelectedIdentifiers

proc collectionItemState*(
    collectionView: CollectionView, index: int
): CollectionItemState =
  if index notin 0 ..< collectionView.len():
    return CollectionItemState(index: -1, objectValue: nilObjectValue())
  let
    identifier = collectionView.collectionItemIdentifier(index)
    value = collectionView.collectionItemObjectValue(index)
  var states: set[WidgetState] = {}
  if not collectionView.collectionItemEnabled(index):
    states.incl ssDisabled
  if collectionView.selectionContains(identifier):
    states.incl ssSelected
  if identifier.len > 0 and identifier == collectionView.xHighlightedIdentifier:
    states.incl ssHovered
  if identifier.len > 0 and identifier == collectionView.xPressedIdentifier:
    states.incl ssPressed
  if ssFocused in collectionView.widgetStateSet():
    states.incl ssFocused
  CollectionItemState(
    index: index,
    identifier: identifier,
    objectValue: value,
    text: collectionView.collectionItemText(index),
    rect: collectionView.resolvedContentItemRect(index),
    states: states,
  )

proc initCollectionItemViewFields*(
    itemView: CollectionItemView, reuseIdentifier = "item", frame: Rect = AutoRect
) =
  initViewFields(itemView, frame)
  itemView.xReuseIdentifier = reuseIdentifier
  itemView.xItemIndex = -1
  itemView.xObjectValue = emptyObjectValue()
  itemView.background = color(0.0, 0.0, 0.0, 0.0)
  itemView.autoresizingMaskConstraints = false
  itemView.clipsToBounds = true
  itemView.installDefaultCollectionItemProtocols()

proc newCollectionItemView*(reuseIdentifier: string, frame: Rect): CollectionItemView =
  result = CollectionItemView()
  result.initCollectionItemViewFields(reuseIdentifier, frame)

proc reuseIdentifier*(itemView: CollectionItemView): string =
  itemView.xReuseIdentifier

proc collectionView*(itemView: CollectionItemView): CollectionView =
  itemView.xCollectionView

proc itemIdentifier*(itemView: CollectionItemView): string =
  itemView.xItemIdentifier

proc itemIndex*(itemView: CollectionItemView): int =
  itemView.xItemIndex

proc objectValue*(itemView: CollectionItemView): ObjectValue =
  itemView.xObjectValue

proc text*(itemView: CollectionItemView): string =
  itemView.xText

proc itemStates*(itemView: CollectionItemView): set[WidgetState] =
  itemView.xItemStates

proc initCollectionSupplementaryViewFields*(
    view: CollectionSupplementaryView,
    kind = cskCustom,
    reuseIdentifier = "",
    elementIdentifier = "",
    frame: Rect = AutoRect,
) =
  initViewFields(view, frame)
  view.xKind = kind
  view.xReuseIdentifier = reuseIdentifier
  view.xElementIdentifier = elementIdentifier
  view.background = color(0.0, 0.0, 0.0, 0.0)
  view.autoresizingMaskConstraints = false
  view.installDefaultCollectionSupplementaryProtocols()

proc newCollectionSupplementaryView*(
    kind = cskCustom,
    reuseIdentifier = "",
    elementIdentifier = "",
    frame: Rect = AutoRect,
): CollectionSupplementaryView =
  result = CollectionSupplementaryView()
  result.initCollectionSupplementaryViewFields(
    kind, reuseIdentifier, elementIdentifier, frame
  )

proc kind*(view: CollectionSupplementaryView): CollectionSupplementaryKind =
  view.xKind

proc reuseIdentifier*(view: CollectionSupplementaryView): string =
  view.xReuseIdentifier

proc elementIdentifier*(view: CollectionSupplementaryView): string =
  view.xElementIdentifier

proc collectionView*(view: CollectionSupplementaryView): CollectionView =
  view.xCollectionView

proc initCollectionBaseChild(view: View, clipsToBounds: bool) =
  initViewFields(view, rect(0.0, 0.0, 0.0, 0.0))
  view.background = color(0.0, 0.0, 0.0, 0.0)
  view.autoresizingMaskConstraints = false
  view.clipsToBounds = clipsToBounds
  view.setAcceptsFirstResponder(false)

proc initCollectionContentView(collectionView: CollectionView): CollectionContentView =
  result = CollectionContentView()
  initCollectionBaseChild(result, false)
  result.xCollectionView = collectionView
  result.installDefaultCollectionContentProtocols()

proc initCollectionScrollView(collectionView: CollectionView): ScrollView =
  result = ScrollView()
  initScrollViewFields(result)
  result.background = color(0.0, 0.0, 0.0, 0.0)
  result.drawsBackground = false
  result.clipsToBounds = true
  result.hasHorizontalScroller = true
  result.hasVerticalScroller = true
  result.autohidesScrollers = true
  result.scrollerThickness = 12.0'f32
  result.lineScroll = collectionView.defaultLayout().itemSize().height
  result.setAcceptsFirstResponder(false)
  result.autoresizingMaskConstraints = false

proc applyCollectionItemAccessibility(
    collectionView: CollectionView, state: CollectionItemState, view: View
) =
  if view.isNil:
    return
  if not view.xHasAccessibilityRole:
    view.accessibilityRole = arListItem
  if view.xAccessibilityLabel.len == 0:
    view.accessibilityLabel = state.text
  view.accessibilityIdentifier = state.identifier
  view.xAccessibilityTraits.incl atSelectable
  if collectionView.xSelectionMode == csmNone:
    view.xAccessibilityTraits.excl atSelectable

proc applyCollectionViewStates(view: View, states: set[WidgetState]) =
  if view.isNil:
    return
  for state in [ssDisabled, ssSelected, ssHovered, ssPressed, ssFocused]:
    view.setWidgetState(state, state in states)

proc applyCollectionItemStateToView(
    collectionView: CollectionView, state: CollectionItemState, view: View
) =
  if view.isNil:
    return
  view.applyCollectionViewStates(state.states)
  applyCollectionItemAccessibility(collectionView, state, view)
  if view of CollectionItemView:
    let itemView = CollectionItemView(view)
    itemView.xCollectionView = collectionView
    itemView.xItemIndex = state.index
    itemView.xItemIdentifier = state.identifier
    itemView.xObjectValue = state.objectValue
    itemView.xText = state.text
    itemView.xItemStates = state.states
  discard view.sendLocalIfHandled(applyCollectionItemState(), state)

proc defaultReuseIdentifierForItem(collectionView: CollectionView, index: int): string =
  let delegate = collectionView.delegate()
  if not delegate.isNil:
    let identifier = delegate.trySendLocal(
      reuseIdentifierForCollectionItem(), (collectionView: collectionView, index: index)
    )
    if identifier.isSome and identifier.get().len > 0:
      return identifier.get()
  if collectionView.xDefaultReuseIdentifier.len > 0:
    collectionView.xDefaultReuseIdentifier
  else:
    "item"

proc dequeueReusableItemView*(
    collectionView: CollectionView, identifier: string
): View =
  if identifier.len == 0:
    return nil
  if identifier notin collectionView.xReusableItemViews:
    return nil
  var views = collectionView.xReusableItemViews[identifier]
  if views.len == 0:
    return nil
  result = views[^1]
  views.setLen(views.len - 1)
  collectionView.xReusableItemViews[identifier] = views
  if not result.isNil:
    discard result.sendLocalIfHandled(
      prepareForReuse(), (collectionView: collectionView, reuseIdentifier: identifier)
    )
    result.hidden = false

proc enqueueReusableItemView(
    collectionView: CollectionView, identifier: string, view: View
) =
  if view.isNil or identifier.len == 0:
    return
  view.hidden = true
  view.applyCollectionViewStates({})
  if view.superview() != nil:
    view.removeFromSuperview()
  collectionView.xReusableItemViews.mgetOrPut(identifier, @[]).add view

proc recycleItemSlot(collectionView: CollectionView, slot: CollectionItemSlot) =
  if slot.view.isNil:
    return
  if slot.reuseIdentifier.len > 0:
    collectionView.enqueueReusableItemView(slot.reuseIdentifier, slot.view)
  else:
    slot.view.hidden = true
    if slot.view.superview() != nil:
      slot.view.removeFromSuperview()

proc clearCollectionItemSlots(collectionView: CollectionView) =
  for slot in collectionView.xItemSlots:
    collectionView.recycleItemSlot(slot)
  collectionView.xItemSlots.setLen(0)

func supplementaryReuseKey(
    kind: CollectionSupplementaryKind, reuseIdentifier: string
): string =
  $kind & "\t" & reuseIdentifier

func supplementaryElementKey(
    kind: CollectionSupplementaryKind, identifier: string
): string =
  $kind & "\t" & identifier

func resolvedSupplementaryReuseIdentifier(
    kind: CollectionSupplementaryKind, reuseIdentifier: string
): string =
  if reuseIdentifier.len > 0:
    reuseIdentifier
  else:
    $kind

proc dequeueReusableSupplementaryView*(
    collectionView: CollectionView,
    kind: CollectionSupplementaryKind,
    reuseIdentifier: string,
): View =
  let
    resolvedReuseIdentifier =
      resolvedSupplementaryReuseIdentifier(kind, reuseIdentifier)
    key = supplementaryReuseKey(kind, resolvedReuseIdentifier)
  if key notin collectionView.xReusableSupplementaryViews:
    return nil
  var views = collectionView.xReusableSupplementaryViews[key]
  if views.len == 0:
    return nil
  result = views[^1]
  views.setLen(views.len - 1)
  collectionView.xReusableSupplementaryViews[key] = views
  if not result.isNil:
    discard result.sendLocalIfHandled(
      prepareForReuse(),
      (collectionView: collectionView, reuseIdentifier: resolvedReuseIdentifier),
    )
    result.hidden = false

proc enqueueReusableSupplementaryView(
    collectionView: CollectionView,
    kind: CollectionSupplementaryKind,
    reuseIdentifier: string,
    view: View,
) =
  if view.isNil or reuseIdentifier.len == 0:
    return
  view.hidden = true
  view.applyCollectionViewStates({})
  if view.superview() != nil:
    view.removeFromSuperview()

  collectionView.xReusableSupplementaryViews.mgetOrPut(
    supplementaryReuseKey(kind, reuseIdentifier), @[]
  ).add view

proc recycleSupplementaryView(collectionView: CollectionView, view: View) =
  if view.isNil:
    return
  if view of CollectionSupplementaryView:
    let supplementary = CollectionSupplementaryView(view)
    if supplementary.xReuseIdentifier.len > 0:
      collectionView.enqueueReusableSupplementaryView(
        supplementary.xKind, supplementary.xReuseIdentifier, view
      )
      return
  view.hidden = true
  if view.superview() != nil:
    view.removeFromSuperview()

proc clearCollectionSupplementaryViews(collectionView: CollectionView) =
  for view in collectionView.xSupplementaryViews.values:
    collectionView.recycleSupplementaryView(view)
  collectionView.xSupplementaryViews.clear()

proc applyCollectionSupplementaryMetadata(
    collectionView: CollectionView,
    kind: CollectionSupplementaryKind,
    identifier, reuseIdentifier: string,
    view: View,
) =
  if view.isNil:
    return
  view.identifier = identifier
  view.accessibilityIdentifier = identifier
  if not view.xHasAccessibilityRole:
    view.accessibilityRole = arGroup
  if view of CollectionSupplementaryView:
    let supplementary = CollectionSupplementaryView(view)
    supplementary.xCollectionView = collectionView
    supplementary.xKind = kind
    supplementary.xReuseIdentifier = reuseIdentifier
    supplementary.xElementIdentifier = identifier

proc supplementaryView*(
    collectionView: CollectionView,
    kind: CollectionSupplementaryKind,
    identifier: string,
    reuseIdentifier = "",
): View =
  let key = supplementaryElementKey(kind, identifier)
  if key in collectionView.xSupplementaryViews:
    return collectionView.xSupplementaryViews[key]

  let
    resolvedReuseIdentifier =
      resolvedSupplementaryReuseIdentifier(kind, reuseIdentifier)
    delegate = collectionView.delegate()
  if not delegate.isNil:
    let provided = delegate.trySendLocal(
      supplementaryViewForCollectionElement(),
      (
        collectionView: collectionView,
        kind: kind,
        identifier: identifier,
        reuseIdentifier: resolvedReuseIdentifier,
      ),
    )
    if provided.isSome:
      result = provided.get(nil)
  if result.isNil:
    result =
      collectionView.dequeueReusableSupplementaryView(kind, resolvedReuseIdentifier)
  if result.isNil:
    result =
      View(newCollectionSupplementaryView(kind, resolvedReuseIdentifier, identifier))
  collectionView.applyCollectionSupplementaryMetadata(
    kind, identifier, resolvedReuseIdentifier, result
  )
  result.hidden = false
  if result.superview() != collectionView.xContentView:
    collectionView.xContentView.addSubview(result)
  collectionView.xSupplementaryViews[key] = result

proc slotIndexForItem(collectionView: CollectionView, index: int): int =
  for slotIndex, slot in collectionView.xItemSlots:
    if slot.index == index:
      return slotIndex
  -1

proc makeCollectionItemView(
    collectionView: CollectionView, index: int
): CollectionItemSlot =
  let
    reuseIdentifier = collectionView.defaultReuseIdentifierForItem(index)
    identifier = collectionView.collectionItemIdentifier(index)
    delegate = collectionView.delegate()
  var view: View
  if not delegate.isNil:
    let provided = delegate.trySendLocal(
      viewForCollectionItem(),
      (collectionView: collectionView, index: index, reuseIdentifier: reuseIdentifier),
    )
    if provided.isSome:
      view = provided.get(nil)
  if view.isNil:
    view = collectionView.dequeueReusableItemView(reuseIdentifier)
  if view.isNil:
    view = View(newCollectionItemView(reuseIdentifier))
  if view.superview() != collectionView.xContentView:
    collectionView.xContentView.addSubview(view)
  CollectionItemSlot(
    index: index, identifier: identifier, reuseIdentifier: reuseIdentifier, view: view
  )

proc configureCollectionItemSlot(
    collectionView: CollectionView, slot: CollectionItemSlot
) =
  if slot.view.isNil:
    return
  let state = collectionView.collectionItemState(slot.index)
  slot.view.frame = state.rect
  collectionView.applyCollectionItemStateToView(state, slot.view)
  let delegate = collectionView.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      configureCollectionItemView(),
      (
        collectionView: collectionView,
        index: slot.index,
        identifier: slot.identifier,
        objectValue: state.objectValue,
        view: slot.view,
      ),
    )

proc syncVisibleItemViews(contentView: CollectionContentView) =
  let collectionView = contentView.collectionView()
  let visible = collectionView.visibleItemIndexes()
  var visibleLookup = initTable[int, bool]()
  for index in visible:
    visibleLookup[index] = true

  var slotIndex = 0
  while slotIndex < collectionView.xItemSlots.len:
    let slot = collectionView.xItemSlots[slotIndex]
    if slot.index notin visibleLookup:
      collectionView.recycleItemSlot(slot)
      collectionView.xItemSlots.delete(slotIndex)
    else:
      inc slotIndex

  for index in visible:
    var slotPos = collectionView.slotIndexForItem(index)
    if slotPos < 0:
      let slot = collectionView.makeCollectionItemView(index)
      collectionView.xItemSlots.add slot
      slotPos = collectionView.xItemSlots.high
    collectionView.configureCollectionItemSlot(collectionView.xItemSlots[slotPos])

proc tileCollectionContent(collectionView: CollectionView) =
  let
    offset = collectionView.collectionContentOffset()
    scrollFrame = rect(
      0.0'f32,
      0.0'f32,
      max(collectionView.bounds().size.width, 0.0'f32),
      max(collectionView.bounds().size.height, 0.0'f32),
    )
  collectionView.xScrollView.frame = scrollFrame
  let size = collectionView.resolvedContentSize()
  collectionView.xContentView.frame = rect(0.0'f32, 0.0'f32, size.width, size.height)
  collectionView.xScrollView.tile()
  collectionView.xScrollView.contentOffset = offset
  collectionView.xContentView.syncVisibleItemViews()

proc invalidateCollectionItems(collectionView: CollectionView) =
  collectionView.xContentView.syncVisibleItemViews()
  collectionView.xContentView.setNeedsDisplay(true)
  collectionView.xScrollView.setNeedsDisplay(true)
  collectionView.xScrollView.verticalScroller().setNeedsDisplay(true)
  collectionView.xScrollView.horizontalScroller().setNeedsDisplay(true)
  collectionView.setNeedsDisplay(true)

proc reloadData*(collectionView: CollectionView) =
  let selected = collectionView.xSelectedIdentifiers
  collectionView.clearCollectionItemSlots()
  collectionView.clearCollectionSupplementaryViews()
  collectionView.tileCollectionContent()
  collectionView.selectedIdentifiers = selected
  collectionView.invalidateIntrinsicContentSize()
  collectionView.invalidateCollectionItems()

proc applyCollectionUpdates*(
    collectionView: CollectionView, updates: openArray[CollectionUpdate]
) =
  let selected = collectionView.xSelectedIdentifiers
  for update in updates:
    case update.kind
    of cukReload, cukRemove, cukMove, cukInsert:
      collectionView.clearCollectionItemSlots()
      collectionView.clearCollectionSupplementaryViews()
  collectionView.tileCollectionContent()
  collectionView.selectedIdentifiers = selected
  emit collectionView.collectionItemsDidUpdate(DynamicAgent(collectionView), @updates)

proc insertItemsAtIndexes*(
    collectionView: CollectionView,
    indexes: openArray[int],
    identifiers: openArray[string] = [],
) =
  collectionView.applyCollectionUpdates(
    [initCollectionInsertUpdate(indexes, identifiers)]
  )

proc removeItemsAtIndexes*(
    collectionView: CollectionView,
    indexes: openArray[int],
    identifiers: openArray[string] = [],
) =
  collectionView.applyCollectionUpdates(
    [initCollectionRemoveUpdate(indexes, identifiers)]
  )

proc reloadItemsAtIndexes*(
    collectionView: CollectionView,
    indexes: openArray[int],
    identifiers: openArray[string] = [],
) =
  collectionView.applyCollectionUpdates(
    [initCollectionReloadUpdate(indexes, identifiers)]
  )

proc moveItem*(collectionView: CollectionView, fromIndex, toIndex: int) =
  collectionView.applyCollectionUpdates([initCollectionMoveUpdate(fromIndex, toIndex)])

proc visibleItemIndexes*(collectionView: CollectionView): seq[int] =
  collectionView.resolvedVisibleIndexes()

proc visibleItemSummaries*(
    collectionView: CollectionView
): seq[CollectionVisibleItemSummary] =
  for index in collectionView.visibleItemIndexes():
    let state = collectionView.collectionItemState(index)
    result.add CollectionVisibleItemSummary(
      index: index,
      identifier: state.identifier,
      text: state.text,
      rect: collectionView.collectionItemRect(index),
      states: state.states,
    )

proc itemViewAtIndex*(collectionView: CollectionView, index: int): View =
  let slotIndex = collectionView.slotIndexForItem(index)
  if slotIndex < 0:
    nil
  else:
    collectionView.xItemSlots[slotIndex].view

proc visibleItemViews*(collectionView: CollectionView): seq[View] =
  for slot in collectionView.xItemSlots:
    if not slot.view.isNil:
      result.add slot.view

proc collectionItemRect*(collectionView: CollectionView, index: int): Rect =
  collectionView.tileCollectionContent()
  let contentView = collectionView.contentView()
  let contentRect = collectionView.resolvedContentItemRect(index)
  if contentRect.isEmpty:
    return rect(0.0, 0.0, 0.0, 0.0)
  contentView.rectToView(contentRect, collectionView).intersection(
    collectionView.bounds()
  )

proc collectionItemIndexAtPoint*(collectionView: CollectionView, point: Point): int =
  collectionView.tileCollectionContent()
  let contentView = collectionView.contentView()
  collectionView.resolvedIndexAtContentPoint(
    contentView.pointFromView(point, collectionView)
  )

proc scrollItemToVisible*(collectionView: CollectionView, index: int) =
  if index notin 0 ..< collectionView.len():
    return
  collectionView.tileCollectionContent()
  let scrollView = collectionView.scrollView()
  discard scrollView.scrollRectToVisible(collectionView.resolvedContentItemRect(index))
  collectionView.xContentView.syncVisibleItemViews()

proc normalizeSelectedIdentifiers(
    collectionView: CollectionView, identifiers: openArray[string]
): seq[string] =
  if collectionView.xSelectionMode == csmNone:
    return
  for identifier in identifiers:
    let index = collectionView.collectionItemIndexForIdentifier(identifier)
    if index >= 0 and collectionView.collectionItemSelectable(index) and
        identifier notin result:
      result.add identifier
  result.sort(
    proc(left, right: string): int =
      cmp(
        collectionView.collectionItemIndexForIdentifier(left),
        collectionView.collectionItemIndexForIdentifier(right),
      )
  )
  if collectionView.xSelectionMode == csmSingle and result.len > 1:
    result.setLen(1)

proc normalizeSelectionAnchor(
    collectionView: CollectionView, identifier: string
): string =
  if collectionView.collectionItemIndexForIdentifier(identifier) >= 0:
    identifier
  else:
    collectionView.xSelectionAnchorIdentifier

proc firstSelectedIdentifier(identifiers: openArray[string]): string =
  if identifiers.len == 0:
    ""
  else:
    identifiers[0]

proc applySelectedIdentifiers(
    collectionView: CollectionView,
    identifiers: openArray[string],
    anchorIdentifier, leadIdentifier: string,
) =
  let nextIdentifiers = collectionView.normalizeSelectedIdentifiers(identifiers)
  let
    nextSelected = nextIdentifiers.firstSelectedIdentifier()
    nextAnchor =
      if nextIdentifiers.len == 0:
        ""
      else:
        collectionView.normalizeSelectionAnchor(anchorIdentifier)
    nextLead =
      if nextIdentifiers.len == 0:
        ""
      else:
        collectionView.normalizeSelectionAnchor(leadIdentifier)
    selectionChanged = collectionView.xSelectedIdentifiers != nextIdentifiers
  if not selectionChanged:
    collectionView.xSelectionAnchorIdentifier = nextAnchor
    collectionView.xSelectionLeadIdentifier = nextLead
    let leadIndex = collectionView.collectionItemIndexForIdentifier(nextLead)
    if leadIndex >= 0:
      collectionView.scrollItemToVisible(leadIndex)
    return

  let beforeIdentifiers = collectionView.xSelectedIdentifiers
  collectionView.findUndoManager().registerSelectionChange(
    proc(values: seq[string]) =
      collectionView.selectedIdentifiers = values,
    beforeIdentifiers,
    "Change Selection",
  )
  emit collectionView.collectionSelectionIsChanging(DynamicAgent(collectionView))
  collectionView.xSelectedIdentifiers = nextIdentifiers
  collectionView.xSelectionAnchorIdentifier = nextAnchor
  collectionView.xSelectionLeadIdentifier = nextLead
  let leadIndex = collectionView.collectionItemIndexForIdentifier(nextLead)
  if leadIndex >= 0:
    collectionView.scrollItemToVisible(leadIndex)
  collectionView.invalidateCollectionItems()
  emit collectionView.collectionSelectionDidChange(DynamicAgent(collectionView))
  collectionView.postAccessibilityNotification(anSelectionChanged)
  let selectedIndex = collectionView.collectionItemIndexForIdentifier(nextSelected)
  if selectedIndex >= 0:
    let delegate = collectionView.delegate()
    if not delegate.isNil:
      discard delegate.sendLocalIfHandled(
        didSelectCollectionItem(),
        (collectionView: collectionView, index: selectedIndex, identifier: nextSelected),
      )

proc selectedIdentifiers*(collectionView: CollectionView): seq[string] =
  collectionView.xSelectedIdentifiers

proc `selectedIdentifiers=`*(
    collectionView: CollectionView, identifiers: openArray[string]
) =
  let next = collectionView.normalizeSelectedIdentifiers(identifiers)
  collectionView.applySelectedIdentifiers(
    next, next.firstSelectedIdentifier(), next.firstSelectedIdentifier()
  )

proc selectedIdentifier*(collectionView: CollectionView): string =
  collectionView.xSelectedIdentifiers.firstSelectedIdentifier()

proc selectedIndexes*(collectionView: CollectionView): seq[int] =
  for identifier in collectionView.xSelectedIdentifiers:
    let index = collectionView.collectionItemIndexForIdentifier(identifier)
    if index >= 0:
      result.add index
  result.sort()

proc `selectedIndexes=`*(collectionView: CollectionView, indexes: openArray[int]) =
  var identifiers: seq[string]
  for index in indexes:
    let identifier = collectionView.collectionItemIdentifier(index)
    if identifier.len > 0:
      identifiers.add identifier
  collectionView.selectedIdentifiers = identifiers

proc selectedIndex*(collectionView: CollectionView): int =
  collectionView.collectionItemIndexForIdentifier(collectionView.selectedIdentifier())

proc `selectedIndex=`*(collectionView: CollectionView, index: int) =
  if index < 0:
    collectionView.selectedIdentifiers = []
  else:
    collectionView.selectItemAtIndex(index)

proc selectionMode*(collectionView: CollectionView): CollectionSelectionMode =
  collectionView.xSelectionMode

proc `selectionMode=`*(collectionView: CollectionView, mode: CollectionSelectionMode) =
  if collectionView.xSelectionMode == mode:
    return
  collectionView.xSelectionMode = mode
  if mode == csmNone:
    collectionView.xSelectedIdentifiers.setLen(0)
    collectionView.xSelectionAnchorIdentifier = ""
    collectionView.xSelectionLeadIdentifier = ""
  elif mode == csmSingle and collectionView.xSelectedIdentifiers.len > 1:
    collectionView.xSelectedIdentifiers.setLen(1)
    collectionView.xSelectionAnchorIdentifier = collectionView.xSelectedIdentifiers[0]
    collectionView.xSelectionLeadIdentifier = collectionView.xSelectedIdentifiers[0]
  collectionView.reloadData()

proc selectItemAtIndex*(collectionView: CollectionView, index: int) =
  if collectionView.xSelectionMode == csmNone:
    return
  let boundedIndex = if index in 0 ..< collectionView.len(): index else: -1
  if boundedIndex < 0:
    collectionView.selectedIdentifiers = []
    return
  if not collectionView.collectionItemSelectable(boundedIndex):
    return
  let identifier = collectionView.collectionItemIdentifier(boundedIndex)
  collectionView.applySelectedIdentifiers([identifier], identifier, identifier)

proc identifiersInRange(
    collectionView: CollectionView, anchorIdentifier, leadIdentifier: string
): seq[string] =
  let
    anchor = collectionView.collectionItemIndexForIdentifier(anchorIdentifier)
    lead = collectionView.collectionItemIndexForIdentifier(leadIdentifier)
  if anchor < 0 or lead < 0:
    return
  for index in min(anchor, lead) .. max(anchor, lead):
    let identifier = collectionView.collectionItemIdentifier(index)
    if identifier.len > 0:
      result.add identifier

proc extendSelectionToIndex(collectionView: CollectionView, index: int) =
  if collectionView.xSelectionMode != csmExtended:
    collectionView.selectItemAtIndex(index)
    return
  if index notin 0 ..< collectionView.len() or
      not collectionView.collectionItemSelectable(index):
    return
  let
    identifier = collectionView.collectionItemIdentifier(index)
    anchor =
      if collectionView.xSelectionAnchorIdentifier.len > 0:
        collectionView.xSelectionAnchorIdentifier
      else:
        collectionView.selectedIdentifier()
  collectionView.applySelectedIdentifiers(
    collectionView.identifiersInRange(anchor, identifier), anchor, identifier
  )

proc toggleSelectionAtIndex(collectionView: CollectionView, index: int) =
  if collectionView.xSelectionMode notin {csmMultiple, csmExtended}:
    collectionView.selectItemAtIndex(index)
    return
  if index notin 0 ..< collectionView.len() or
      not collectionView.collectionItemSelectable(index):
    return
  let identifier = collectionView.collectionItemIdentifier(index)
  var next = collectionView.xSelectedIdentifiers
  if identifier in next:
    var filtered: seq[string]
    for selected in next:
      if selected != identifier:
        filtered.add selected
    next = filtered
  elif identifier.len > 0:
    next.add identifier
  collectionView.applySelectedIdentifiers(next, identifier, identifier)

proc usesDiscontiguousSelection(modifiers: set[KeyModifier]): bool =
  kmCommand in modifiers or kmControl in modifiers

proc selectItemAtIndex*(
    collectionView: CollectionView, index: int, modifiers: set[KeyModifier]
) =
  if collectionView.xSelectionMode == csmNone:
    return
  if kmShift in modifiers and collectionView.xSelectionMode == csmExtended:
    collectionView.extendSelectionToIndex(index)
  elif modifiers.usesDiscontiguousSelection() and
      collectionView.xSelectionMode in {csmMultiple, csmExtended}:
    collectionView.toggleSelectionAtIndex(index)
  else:
    collectionView.selectItemAtIndex(index)

proc activateItemAtIndex*(
    collectionView: CollectionView, index: int, modifiers: set[KeyModifier] = {}
) =
  if index notin 0 ..< collectionView.len():
    return
  if not collectionView.collectionItemEnabled(index):
    return
  if collectionView.xSelectionMode != csmNone:
    collectionView.selectItemAtIndex(index, modifiers)
  let identifier = collectionView.collectionItemIdentifier(index)
  let delegate = collectionView.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didActivateCollectionItem(),
      (collectionView: collectionView, index: index, identifier: identifier),
    )
  emit collectionView.collectionItemWasActivated(
    DynamicAgent(collectionView), index, identifier
  )
  discard collectionView.sendAction()

proc highlightedIndex*(collectionView: CollectionView): int =
  collectionView.collectionItemIndexForIdentifier(collectionView.xHighlightedIdentifier)

proc highlightedIdentifier*(collectionView: CollectionView): string =
  collectionView.xHighlightedIdentifier

proc `highlightedIndex=`*(collectionView: CollectionView, index: int) =
  let identifier =
    if index in 0 ..< collectionView.len() and
        collectionView.collectionItemEnabled(index):
      collectionView.collectionItemIdentifier(index)
    else:
      ""
  if collectionView.xHighlightedIdentifier == identifier:
    return
  collectionView.xHighlightedIdentifier = identifier
  collectionView.invalidateCollectionItems()

proc `highlightedIdentifier=`*(collectionView: CollectionView, identifier: string) =
  if collectionView.xHighlightedIdentifier == identifier:
    return
  collectionView.xHighlightedIdentifier = identifier
  collectionView.invalidateCollectionItems()

proc selectionLeadIndex(collectionView: CollectionView): int =
  let lead = collectionView.collectionItemIndexForIdentifier(
    collectionView.xSelectionLeadIdentifier
  )
  if lead >= 0:
    lead
  else:
    collectionView.selectedIndex()

proc firstSelectableIndex(collectionView: CollectionView): int =
  for index in 0 ..< collectionView.len():
    if collectionView.collectionItemSelectable(index):
      return index
  -1

proc lastSelectableIndex(collectionView: CollectionView): int =
  for offset in 0 ..< collectionView.len():
    let index = collectionView.len() - offset - 1
    if collectionView.collectionItemSelectable(index):
      return index
  -1

proc nextSelectableIndex(collectionView: CollectionView, index, delta: int): int =
  if delta == 0:
    return -1
  let step = if delta < 0: -1 else: 1
  var current = index
  while current >= 0 and current < collectionView.len():
    if collectionView.collectionItemSelectable(current):
      return current
    current += step
  -1

proc itemsPerRow(collectionView: CollectionView): int =
  let layout = collectionView.defaultLayout()
  if layout.isNil:
    return 1
  layout.layoutColumnCount(
    collectionView.len(), collectionView.collectionViewportSize().width
  )

proc moveSelectionTo(
    collectionView: CollectionView, index: int, extend = false, delta = 1
) =
  if collectionView.len() == 0 or collectionView.xSelectionMode == csmNone:
    return
  let boundedTarget = max(0, min(index, collectionView.len() - 1))
  var boundedIndex = collectionView.nextSelectableIndex(boundedTarget, delta)
  if boundedIndex < 0 and delta > 0:
    boundedIndex = collectionView.nextSelectableIndex(boundedTarget, -1)
  elif boundedIndex < 0 and delta < 0:
    boundedIndex = collectionView.nextSelectableIndex(boundedTarget, 1)
  if boundedIndex < 0:
    return
  if extend and collectionView.xSelectionMode == csmExtended:
    collectionView.extendSelectionToIndex(boundedIndex)
  else:
    collectionView.selectItemAtIndex(boundedIndex)

proc moveSelection(collectionView: CollectionView, delta: int, extend = false) =
  let start =
    if collectionView.selectionLeadIndex() >= 0:
      collectionView.selectionLeadIndex()
    elif delta > 0:
      -1
    else:
      collectionView.len()
  collectionView.moveSelectionTo(start + delta, extend, delta)

proc defaultCollectionViewMouseDown(
    collectionView: CollectionView, event: MouseEvent
): bool =
  if not collectionView.isEnabled() or event.button != mbPrimary:
    return false
  let owner = collectionView.window()
  if owner of Window:
    discard Window(owner).makeFirstResponder(collectionView)
  collectionView.xTrackingItem = true
  let index = collectionView.collectionItemIndexAtPoint(event.location)
  collectionView.highlightedIndex = index
  collectionView.xPressedIdentifier = collectionView.xHighlightedIdentifier
  collectionView.invalidateCollectionItems()
  true

proc defaultCollectionViewMouseDragged(
    collectionView: CollectionView, event: MouseEvent
): bool =
  if collectionView.isEnabled() and collectionView.xTrackingItem:
    let index = collectionView.collectionItemIndexAtPoint(event.location)
    collectionView.highlightedIndex = index
    collectionView.xPressedIdentifier = collectionView.xHighlightedIdentifier
    collectionView.invalidateCollectionItems()
    return true
  false

proc defaultCollectionViewMouseUp(
    collectionView: CollectionView, event: MouseEvent
): bool =
  if not collectionView.isEnabled() or event.button != mbPrimary:
    return false
  let index =
    if collectionView.xTrackingItem:
      collectionView.collectionItemIndexAtPoint(event.location)
    else:
      -1
  collectionView.xTrackingItem = false
  collectionView.xPressedIdentifier = ""
  if index >= 0:
    collectionView.activateItemAtIndex(index, event.modifiers)
  collectionView.invalidateCollectionItems()
  true

proc defaultCollectionViewKeyDown(
    collectionView: CollectionView, event: KeyEvent
): bool =
  if not collectionView.isEnabled():
    return false
  result = true
  let
    extendSelection = kmShift in event.modifiers
    rowDelta = max(collectionView.itemsPerRow(), 1)
  case event.key
  of keyArrowRight:
    collectionView.moveSelection(1, extendSelection)
  of keyArrowLeft:
    collectionView.moveSelection(-1, extendSelection)
  of keyArrowDown:
    collectionView.moveSelection(rowDelta, extendSelection)
  of keyArrowUp:
    collectionView.moveSelection(-rowDelta, extendSelection)
  of keyHome:
    collectionView.moveSelectionTo(
      collectionView.firstSelectableIndex(), extendSelection
    )
  of keyEnd:
    collectionView.moveSelectionTo(
      collectionView.lastSelectableIndex(), extendSelection, -1
    )
  of keyEnter, keySpace:
    let index = collectionView.selectionLeadIndex()
    if index >= 0:
      collectionView.activateItemAtIndex(index)
  else:
    result = event.text.len > 0

proc selectedDragIdentifiers(collectionView: CollectionView): seq[string] =
  if collectionView.xSelectedIdentifiers.len > 0:
    collectionView.xSelectedIdentifiers
  elif collectionView.xHighlightedIdentifier.len > 0:
    @[collectionView.xHighlightedIdentifier]
  else:
    @[]

proc defaultDraggingItemsForIdentifiers(
    collectionView: CollectionView, identifiers: openArray[string]
): seq[DraggingItem] =
  if identifiers.len == 0:
    return
  result.add initDraggingItem(
    CollectionPasteboardTypeItems, initPasteboardStringItem(identifiers.join("\n"))
  )

proc beginDraggingItems*(
    collectionView: CollectionView,
    identifiers: openArray[string],
    operations: DragOperations = {dgoMove},
    pasteboardName: string = DragPasteboardName,
): DraggingSession =
  let delegate = collectionView.delegate()
  var items: seq[DraggingItem]
  if not delegate.isNil:
    let provided = delegate.trySendLocal(
      draggingItemsForCollectionItems(),
      (
        collectionView: collectionView,
        identifiers: @identifiers,
        pasteboardName: pasteboardName,
      ),
    )
    if provided.isSome:
      items = provided.get()
  if items.len == 0:
    items = collectionView.defaultDraggingItemsForIdentifiers(identifiers)
  if items.len == 0:
    return nil
  result = beginDraggingSession(
    DynamicAgent(collectionView), items, operations, pasteboardName
  )
  collectionView.xCollectionDraggingSession = result

proc beginDraggingSelection*(
    collectionView: CollectionView,
    operations: DragOperations = {dgoMove},
    pasteboardName: string = DragPasteboardName,
): DraggingSession =
  collectionView.beginDraggingItems(
    collectionView.selectedDragIdentifiers(), operations, pasteboardName
  )

proc draggingSession*(collectionView: CollectionView): DraggingSession =
  collectionView.xCollectionDraggingSession

proc draggingInfo*(collectionView: CollectionView): DraggingInfo =
  if collectionView.xCollectionDraggingSession.isNil:
    DraggingInfo()
  else:
    collectionView.xCollectionDraggingSession.draggingInfo()

func collectionDropPositionForItem(location: Point, rect: Rect): DraggingDropPosition =
  let edge = rect.size.height * 0.25'f32
  if location.y <= rect.minY + edge:
    ddpBefore
  elif location.y >= rect.maxY - edge:
    ddpAfter
  else:
    ddpOn

proc defaultDropTargetForLocation(
    collectionView: CollectionView, location: Point
): DraggingDropTarget =
  let index = collectionView.collectionItemIndexAtPoint(location)
  if index >= 0:
    let
      identifier = collectionView.collectionItemIdentifier(index)
      rect = collectionView.collectionItemRect(index)
    var target = initItemDropTarget(identifier, row = index, rect = rect)
    target.position = collectionDropPositionForItem(location, rect)
    return target
  initDraggingDropTarget()

proc dropTargetForDraggingLocation*(
    collectionView: CollectionView, location: Point
): DraggingDropTarget =
  let proposed = collectionView.defaultDropTargetForLocation(location)
  let delegate = collectionView.delegate()
  if not delegate.isNil:
    let resolved = delegate.trySendLocal(
      collectionDropTargetForLocation(),
      (collectionView: collectionView, location: location, proposedTarget: proposed),
    )
    if resolved.isSome:
      return resolved.get()
  proposed

proc updateCollectionDropTarget(
    collectionView: CollectionView, target: DraggingDropTarget
) =
  if collectionView.xDropTarget == target:
    return
  collectionView.xDropTarget = target
  collectionView.setNeedsDisplay(true)

proc currentDropTarget*(collectionView: CollectionView): DraggingDropTarget =
  if not collectionView.xCollectionDraggingSession.isNil and
      collectionView.xCollectionDraggingSession.state() == dssActive:
    return collectionView.xCollectionDraggingSession.dropTarget()
  collectionView.xDropTarget

proc acceptsDraggingInfo(collectionView: CollectionView, info: DraggingInfo): bool =
  if info.pasteboard.isNil:
    return false
  let types = collectionView.registeredDraggedTypes()
  types.len > 0 and info.pasteboard.availableTypeFromArray(types).len > 0

proc validateDragging*(
    collectionView: CollectionView, info: DraggingInfo
): DragOperations =
  let proposed =
    if collectionView.acceptsDraggingInfo(info):
      info.selectedOperations
    else:
      NoDragOperations
  let delegate = collectionView.delegate()
  if not delegate.isNil:
    let operation = delegate.trySendLocal(
      validateCollectionDropOperation(),
      (
        collectionView: collectionView,
        info: info,
        proposedOperation: proposed,
        target: info.dropTarget,
        position: info.dropTarget.position,
      ),
    )
    if operation.isSome:
      return operation.get()
  proposed

proc acceptDragging*(collectionView: CollectionView, info: DraggingInfo): bool =
  let operation = collectionView.validateDragging(info)
  if operation == NoDragOperations:
    return false
  let delegate = collectionView.delegate()
  if not delegate.isNil:
    let accepted = delegate.trySendLocal(
      acceptCollectionDropOperation(),
      (
        collectionView: collectionView,
        info: info,
        operation: operation,
        target: info.dropTarget,
        position: info.dropTarget.position,
      ),
    )
    if accepted.isSome:
      return accepted.get()
  true

proc autoscrollDraggingInfo(collectionView: CollectionView, info: DraggingInfo): bool =
  if collectionView.scrollView().isNil:
    return false
  let bounds = collectionView.bounds()
  if bounds.isEmpty:
    return false
  let edge = 24.0'f32
  var delta = initPoint(0.0, 0.0)
  if info.location.x < bounds.minX + edge:
    delta.x = -collectionView.scrollView().lineScroll(laHorizontal)
  elif info.location.x > bounds.maxX - edge:
    delta.x = collectionView.scrollView().lineScroll(laHorizontal)
  if info.location.y < bounds.minY + edge:
    delta.y = -collectionView.scrollView().lineScroll(laVertical)
  elif info.location.y > bounds.maxY - edge:
    delta.y = collectionView.scrollView().lineScroll(laVertical)
  if delta.x == 0.0'f32 and delta.y == 0.0'f32:
    return false
  collectionView.scrollView().scrollBy(delta)
  collectionView.invalidateCollectionItems()
  true

protocol DefaultCollectionItemViewLifecycle of CollectionReusableViewProtocol:
  method prepareForReuse(
      itemView: CollectionItemView,
      collectionView: CollectionView,
      reuseIdentifier: string,
  ) =
    discard collectionView
    itemView.xReuseIdentifier = reuseIdentifier
    itemView.xCollectionView = nil
    itemView.xItemIdentifier = ""
    itemView.xItemIndex = -1
    itemView.xObjectValue = emptyObjectValue()
    itemView.xText = ""
    itemView.xItemStates = {}
    itemView.validationMessage = ""
    itemView.applyCollectionViewStates({})

  method applyCollectionItemState(
      itemView: CollectionItemView, state: CollectionItemState
  ) =
    itemView.xItemIndex = state.index
    itemView.xItemIdentifier = state.identifier
    itemView.xObjectValue = state.objectValue
    itemView.xText = state.text
    itemView.xItemStates = state.states
    itemView.identifier = state.identifier

protocol DefaultCollectionItemViewDrawing of ViewDrawingProtocol:
  method draw(itemView: CollectionItemView, context: DrawContext) =
    if context.isNil or itemView.bounds().isEmpty:
      return
    let owner = itemView.collectionView()
    let role =
      if owner.isNil:
        srRowItem
      else:
        owner.collectionItemRole()
    context.drawRowItem(
      itemView.bounds(),
      initRowState(itemView.xItemIndex, itemView.xText, itemView.xItemStates),
      role,
      id = itemView.styleId(),
      classes = itemView.styleClasses(),
    )

protocol DefaultCollectionItemViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(itemView: CollectionItemView): AccessibilityRole =
    arListItem

  method accessibilityLabel(itemView: CollectionItemView): string =
    if itemView.xText.len > 0: itemView.xText else: itemView.xAccessibilityLabel

  method accessibilityValue(itemView: CollectionItemView): string =
    itemView.xItemIdentifier

  method accessibilityTraits(itemView: CollectionItemView): AccessibilityTraits =
    result = itemView.xAccessibilityTraits + {atSelectable}
    if ssDisabled in itemView.xItemStates:
      result.incl atDisabled
    if ssFocused in itemView.xItemStates:
      result.incl atFocused
    if ssSelected in itemView.xItemStates:
      result.incl atSelected

  method isAccessibilityElement(itemView: CollectionItemView): bool =
    itemView.xItemIndex >= 0

proc installDefaultCollectionItemProtocols(itemView: CollectionItemView) =
  discard itemView.withProtocol(DefaultCollectionItemViewLifecycle)
  discard itemView.withProtocol(DefaultCollectionItemViewDrawing)
  discard itemView.withProtocol(DefaultCollectionItemViewAccessibility)

protocol DefaultCollectionSupplementaryViewLifecycle of CollectionReusableViewProtocol:
  method prepareForReuse(
      view: CollectionSupplementaryView,
      collectionView: CollectionView,
      reuseIdentifier: string,
  ) =
    discard collectionView
    view.xCollectionView = nil
    view.xKind = cskCustom
    view.xReuseIdentifier = reuseIdentifier
    view.xElementIdentifier = ""
    view.identifier = ""
    view.accessibilityIdentifier = ""
    view.validationMessage = ""
    view.applyCollectionViewStates({})

protocol DefaultCollectionSupplementaryViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(view: CollectionSupplementaryView): AccessibilityRole =
    arGroup

  method accessibilityLabel(view: CollectionSupplementaryView): string =
    if view.xAccessibilityLabel.len > 0:
      view.xAccessibilityLabel
    else:
      view.xElementIdentifier

  method accessibilityValue(view: CollectionSupplementaryView): string =
    view.xReuseIdentifier

  method isAccessibilityElement(view: CollectionSupplementaryView): bool =
    view.xAccessibilityLabel.len > 0

proc installDefaultCollectionSupplementaryProtocols(view: CollectionSupplementaryView) =
  discard view.withProtocol(DefaultCollectionSupplementaryViewLifecycle)
  discard view.withProtocol(DefaultCollectionSupplementaryViewAccessibility)

protocol DefaultCollectionContentViewDrawing of ViewDrawingProtocol:
  method draw(contentView: CollectionContentView, context: DrawContext) =
    discard context
    contentView.syncVisibleItemViews()

protocol DefaultCollectionContentViewHitTesting of ViewProtocol:
  method pointInside(contentView: CollectionContentView, point: Point): bool =
    contentView.bounds().contains(point)

proc installDefaultCollectionContentProtocols(contentView: CollectionContentView) =
  discard contentView.withProtocol(DefaultCollectionContentViewDrawing)
  discard contentView.withProtocol(DefaultCollectionContentViewHitTesting)

protocol DefaultCollectionViewLayoutBehavior of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(collectionView: CollectionView): IntrinsicSize =
    initIntrinsicSize(collectionView.resolvedContentSize())

  method layoutSubviews(collectionView: CollectionView) =
    collectionView.tileCollectionContent()

protocol DefaultCollectionViewEvents of ResponderEventProtocol:
  method mouseDown(collectionView: CollectionView, event: MouseEvent): bool =
    collectionView.defaultCollectionViewMouseDown(event)

  method mouseDragged(collectionView: CollectionView, event: MouseEvent): bool =
    let session = collectionView.draggingSession()
    if not session.isNil and session.state() == dssActive:
      let target = collectionView.dropTargetForDraggingLocation(event.location)
      collectionView.updateCollectionDropTarget(target)
      discard updateDraggingSession(
        session, event.location, DynamicAgent(collectionView), target
      )
      discard autoscrollDraggingSession(
        session, event.location, DynamicAgent(collectionView), target
      )
      return true
    collectionView.defaultCollectionViewMouseDragged(event)

  method mouseUp(collectionView: CollectionView, event: MouseEvent): bool =
    collectionView.defaultCollectionViewMouseUp(event)

  method mouseMoved(collectionView: CollectionView, event: MouseEvent): bool =
    if collectionView.isEnabled():
      collectionView.highlightedIndex =
        collectionView.collectionItemIndexAtPoint(event.location)
      return true
    false

  method keyDown(collectionView: CollectionView, event: KeyEvent): bool =
    collectionView.defaultCollectionViewKeyDown(event)

protocol DefaultCollectionViewDraggingSource of DraggingSourceProtocol:
  method draggingSourceOperationMask(
      collectionView: CollectionView, info: DraggingInfo
  ): DragOperations =
    discard collectionView
    info.allowedOperations

  method draggingSessionEnded(collectionView: CollectionView, info: DraggingInfo) =
    if collectionView.xCollectionDraggingSession == info.session:
      collectionView.xCollectionDraggingSession = nil
      collectionView.updateCollectionDropTarget(initDraggingDropTarget())

protocol DefaultCollectionViewDraggingDestination of DraggingDestinationProtocol:
  method draggingEntered(
      collectionView: CollectionView, info: DraggingInfo
  ): DragOperations =
    collectionView.updateCollectionDropTarget(info.dropTarget)
    collectionView.validateDragging(info)

  method draggingUpdated(
      collectionView: CollectionView, info: DraggingInfo
  ): DragOperations =
    collectionView.updateCollectionDropTarget(info.dropTarget)
    collectionView.validateDragging(info)

  method draggingExited(collectionView: CollectionView, info: DraggingInfo) =
    discard info
    collectionView.updateCollectionDropTarget(initDraggingDropTarget())

  method prepareForDragOperation(
      collectionView: CollectionView, info: DraggingInfo
  ): bool =
    collectionView.validateDragging(info) != NoDragOperations

  method performDragOperation(
      collectionView: CollectionView, info: DraggingInfo
  ): bool =
    collectionView.acceptDragging(info)

  method concludeDragOperation(collectionView: CollectionView, info: DraggingInfo) =
    discard info
    collectionView.updateCollectionDropTarget(initDraggingDropTarget())

  method autoscrollDraggingSession(
      collectionView: CollectionView, info: DraggingInfo
  ): bool =
    collectionView.autoscrollDraggingInfo(info)

protocol DefaultCollectionViewDrawing of ViewDrawingProtocol:
  method draw(collectionView: CollectionView, context: DrawContext) =
    if context.isNil or collectionView.bounds().isEmpty:
      return
    collectionView.tileCollectionContent()
    let style = context.appearance.resolveTableViewStyle(
      controlStyle(
        collectionView.collectionRole(),
        collectionView.widgetStateSet(),
        id = collectionView.styleId(),
        classes = collectionView.styleClasses(),
      )
    )
    discard context.addRenderRectangle(
      context.renderRectFor(collectionView.bounds()),
      style.box.fill,
      style.box.borderColor,
      style.box.borderWidth,
      style.box.cornerRadius,
      style.box.shadows,
      clips = true,
    )

protocol DefaultCollectionViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(collectionView: CollectionView): AccessibilityRole =
    arList

  method accessibilityValue(collectionView: CollectionView): string =
    $collectionView.len()

  method accessibilityTraits(collectionView: CollectionView): AccessibilityTraits =
    result = collectionView.xAccessibilityTraits
    if collectionView.selectionMode() != csmNone:
      result.incl atSelectable
    if ssDisabled in collectionView.xWidgetStates:
      result.incl atDisabled
    if collectionView.focused():
      result.incl atFocused

  method isAccessibilityElement(collectionView: CollectionView): bool =
    true

proc initCollectionViewFields*(collectionView: CollectionView, frame: Rect = AutoRect) =
  initControlFields(collectionView, frame)
  collectionView.xCollectionRole = srTableView
  collectionView.xItemRole = srRowItem
  collectionView.xItemCount = 0
  collectionView.xDefaultReuseIdentifier = "item"
  collectionView.xSelectionMode = csmSingle
  collectionView.xReusableItemViews = initTable[string, seq[View]]()
  collectionView.xReusableSupplementaryViews = initTable[string, seq[View]]()
  collectionView.xSupplementaryViews = initTable[string, View]()
  collectionView.xLayout = DynamicAgent(newCollectionViewLayout())
  discard collectionView.xLayout.adopt(CollectionLayoutProtocol)
  collectionView.xDropTarget = initDraggingDropTarget()
  collectionView.xScrollView = initCollectionScrollView(collectionView)
  collectionView.xContentView = initCollectionContentView(collectionView)
  collectionView.xScrollView.documentView = collectionView.xContentView
  collectionView.setAcceptsFirstResponder(true)
  collectionView.clipsToBounds = true
  collectionView.addSubview(collectionView.xScrollView)
  discard collectionView.withProtocol(DefaultCollectionViewLayoutBehavior)
  discard collectionView.withProtocol(DefaultCollectionViewEvents)
  discard collectionView.withProtocol(DefaultCollectionViewDraggingSource)
  discard collectionView.withProtocol(DefaultCollectionViewDraggingDestination)
  discard collectionView.withProtocol(DefaultCollectionViewDrawing)
  discard collectionView.withProtocol(DefaultCollectionViewAccessibility)
  collectionView.applyInitialFrame(frame)

proc newCollectionView*(frame: Rect = AutoRect): CollectionView =
  result = CollectionView()
  result.initCollectionViewFields(frame)
