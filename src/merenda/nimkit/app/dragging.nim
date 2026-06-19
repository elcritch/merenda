import std/options

import sigils/selectors

import ../drawing/images
import ../foundation/types
import ./pasteboards

type
  DragOperation* = enum
    dgoCopy
    dgoLink
    dgoGeneric
    dgoPrivate
    dgoMove
    dgoDelete

  DragOperations* = set[DragOperation]

  DraggingSessionState* = enum
    dssReady
    dssActive
    dssEnded
    dssCancelled

  DraggingDropTargetKind* = enum
    ddtNone
    ddtRow
    ddtColumn
    ddtCell
    ddtItem

  DraggingDropTarget* = object
    kind*: DraggingDropTargetKind
    row*: int
    column*: string
    itemIdentifier*: string
    rect*: Rect

  DraggingItem* = object
    pasteboardType*: string
    pasteboardItem*: PasteboardItem
    frame*: Rect
    image*: ImageResource
    promisedFileName*: string

  DraggingSession* = ref object
    xSource: DynamicAgent
    xDestination: DynamicAgent
    xPasteboard: Pasteboard
    xItems: seq[DraggingItem]
    xAllowedOperations: DragOperations
    xSelectedOperations: DragOperations
    xState: DraggingSessionState
    xSequenceNumber: Natural
    xDropTarget: DraggingDropTarget

  DraggingInfo* = object
    session*: DraggingSession
    pasteboard*: Pasteboard
    source*: DynamicAgent
    destination*: DynamicAgent
    location*: Point
    allowedOperations*: DragOperations
    selectedOperations*: DragOperations
    sequenceNumber*: Natural
    dropTarget*: DraggingDropTarget

const
  NoDragOperations*: DragOperations = {}
  EveryDragOperation*: DragOperations = {
    dgoCopy,
    dgoLink,
    dgoGeneric,
    dgoPrivate,
    dgoMove,
    dgoDelete,
  }

protocol DraggingSourceProtocol:
  method draggingSessionWillBegin*(info: DraggingInfo) {.optional.}
  method draggingSessionMoved*(info: DraggingInfo) {.optional.}
  method draggingSessionEnded*(info: DraggingInfo) {.optional.}
  method draggingSourceOperationMask*(info: DraggingInfo): DragOperations {.optional.}
  method ignoreModifierKeysForDraggingSession*(
    session: DraggingSession
  ): bool {.optional.}

protocol DraggingDestinationProtocol:
  method draggingEntered*(info: DraggingInfo): DragOperations {.optional.}
  method draggingUpdated*(info: DraggingInfo): DragOperations {.optional.}
  method draggingExited*(info: DraggingInfo) {.optional.}
  method prepareForDragOperation*(info: DraggingInfo): bool {.optional.}
  method performDragOperation*(info: DraggingInfo): bool {.optional.}
  method concludeDragOperation*(info: DraggingInfo) {.optional.}
  method wantsPeriodicDraggingUpdates*(info: DraggingInfo): bool {.optional.}
  method autoscrollDraggingSession*(info: DraggingInfo): bool {.optional.}

proc initDraggingDropTarget*(
    kind = ddtNone,
    row = -1,
    column = "",
    itemIdentifier = "",
    rect = AutoRect,
): DraggingDropTarget =
  DraggingDropTarget(
    kind: kind,
    row: row,
    column: column,
    itemIdentifier: itemIdentifier,
    rect: rect,
  )

proc initRowDropTarget*(row: int, rect = AutoRect): DraggingDropTarget =
  initDraggingDropTarget(ddtRow, row = row, rect = rect)

proc initColumnDropTarget*(
    column: string, rect = AutoRect
): DraggingDropTarget =
  initDraggingDropTarget(ddtColumn, column = column, rect = rect)

proc initCellDropTarget*(
    row: int, column: string, rect = AutoRect
): DraggingDropTarget =
  initDraggingDropTarget(ddtCell, row = row, column = column, rect = rect)

proc initItemDropTarget*(
    itemIdentifier: string, row = -1, rect = AutoRect
): DraggingDropTarget =
  initDraggingDropTarget(ddtItem, row = row, itemIdentifier = itemIdentifier, rect = rect)

proc initDraggingItem*(
    pasteboardType: string,
    pasteboardItem: PasteboardItem,
    frame = AutoRect,
    image: ImageResource = nil,
): DraggingItem =
  DraggingItem(
    pasteboardType: pasteboardType,
    pasteboardItem: pasteboardItem.copyPasteboardItem(),
    frame: frame,
    image:
      if image.isNil:
        nil
      else:
        image.copyImageResource(),
  )

proc initPromisedFileDraggingItem*(
    fileName: string,
    pasteboardItem = PasteboardItem(kind: pikNone),
    frame = AutoRect,
    image: ImageResource = nil,
): DraggingItem =
  result = initDraggingItem(PasteboardTypePromisedFile, pasteboardItem, frame, image)
  result.promisedFileName = fileName

proc copyDraggingItem*(item: DraggingItem): DraggingItem =
  result = initDraggingItem(
    item.pasteboardType, item.pasteboardItem, item.frame, item.image
  )
  result.promisedFileName = item.promisedFileName

proc newDraggingSession*(
    source: DynamicAgent,
    pasteboard: Pasteboard = nil,
    allowedOperations = EveryDragOperation,
): DraggingSession =
  DraggingSession(
    xSource: source,
    xPasteboard:
      if pasteboard.isNil:
        dragPasteboard()
      else:
        pasteboard,
    xAllowedOperations: allowedOperations,
    xSelectedOperations: allowedOperations,
    xState: dssReady,
    xDropTarget: initDraggingDropTarget(),
  )

proc source*(session: DraggingSession): DynamicAgent =
  if session.isNil: nil else: session.xSource

proc destination*(session: DraggingSession): DynamicAgent =
  if session.isNil: nil else: session.xDestination

proc pasteboard*(session: DraggingSession): Pasteboard =
  if session.isNil: nil else: session.xPasteboard

proc state*(session: DraggingSession): DraggingSessionState =
  if session.isNil: dssCancelled else: session.xState

proc allowedOperations*(session: DraggingSession): DragOperations =
  if session.isNil: NoDragOperations else: session.xAllowedOperations

proc selectedOperations*(session: DraggingSession): DragOperations =
  if session.isNil: NoDragOperations else: session.xSelectedOperations

proc dropTarget*(session: DraggingSession): DraggingDropTarget =
  if session.isNil:
    initDraggingDropTarget()
  else:
    session.xDropTarget

proc setDropTarget*(session: DraggingSession, target: DraggingDropTarget) =
  if not session.isNil:
    session.xDropTarget = target

proc items*(session: DraggingSession): seq[DraggingItem] =
  if session.isNil:
    return @[]
  for item in session.xItems:
    result.add item.copyDraggingItem()

proc draggingInfo*(
    session: DraggingSession,
    location = AutoPoint,
    destination: DynamicAgent = nil,
): DraggingInfo =
  if session.isNil:
    return DraggingInfo()
  DraggingInfo(
    session: session,
    pasteboard: session.xPasteboard,
    source: session.xSource,
    destination:
      if destination.isNil:
        session.xDestination
      else:
        destination,
    location: location,
    allowedOperations: session.xAllowedOperations,
    selectedOperations: session.xSelectedOperations,
    sequenceNumber: session.xSequenceNumber,
    dropTarget: session.xDropTarget,
  )

proc withDropTarget*(
    info: DraggingInfo, target: DraggingDropTarget
): DraggingInfo =
  result = info
  result.dropTarget = target
  if not result.session.isNil:
    result.session.setDropTarget(target)

proc addDraggingItem*(session: DraggingSession, item: DraggingItem) =
  if session.isNil:
    return
  session.xItems.add item.copyDraggingItem()

proc writeItemsToPasteboard(session: DraggingSession) =
  if session.isNil or session.xPasteboard.isNil:
    return
  var declaredTypes: seq[string]
  for item in session.xItems:
    if item.pasteboardType.len > 0 and item.pasteboardType notin declaredTypes:
      declaredTypes.add item.pasteboardType
  session.xPasteboard.declareTypes(declaredTypes, session.xSource)
  for item in session.xItems:
    if item.pasteboardType.len > 0 and item.pasteboardItem.kind != pikNone:
      discard session.xPasteboard.setItem(item.pasteboardType, item.pasteboardItem)

proc sourceOperationMask(session: DraggingSession, location: Point): DragOperations =
  if session.isNil:
    return NoDragOperations
  result = session.xAllowedOperations
  if not session.xSource.isNil:
    let requested = session.xSource.trySendLocal(
      draggingSourceOperationMask(), session.draggingInfo(location)
    )
    if requested.isSome:
      result = requested.get() * session.xAllowedOperations

proc beginDraggingSession*(
    source: DynamicAgent,
    items: openArray[DraggingItem],
    allowedOperations = EveryDragOperation,
    pasteboardName = DragPasteboardName,
): DraggingSession =
  result = newDraggingSession(
    source, pasteboardWithName(pasteboardName), allowedOperations
  )
  for item in items:
    result.addDraggingItem(item)
  result.writeItemsToPasteboard()
  result.xSelectedOperations = result.sourceOperationMask(AutoPoint)
  result.xState = dssActive
  if not source.isNil:
    discard source.sendLocalIfHandled(
      draggingSessionWillBegin(), result.draggingInfo()
    )

proc updateDraggingSession*(
    session: DraggingSession,
    location: Point,
    destination: DynamicAgent = nil,
    dropTarget = initDraggingDropTarget(),
): DragOperations =
  if session.isNil or session.xState != dssActive:
    return NoDragOperations

  inc session.xSequenceNumber
  session.xDropTarget = dropTarget
  let oldDestination = session.xDestination
  if oldDestination != destination:
    if not oldDestination.isNil:
      discard oldDestination.sendLocalIfHandled(
        draggingExited(), session.draggingInfo(location, oldDestination)
      )
    session.xDestination = destination
    if not destination.isNil:
      let entered = destination.trySendLocal(
        draggingEntered(), session.draggingInfo(location, destination)
      )
      if entered.isSome:
        session.xSelectedOperations = entered.get() * session.sourceOperationMask(location)
  elif not destination.isNil:
    let updated = destination.trySendLocal(
      draggingUpdated(), session.draggingInfo(location, destination)
    )
    if updated.isSome:
      session.xSelectedOperations = updated.get() * session.sourceOperationMask(location)
  else:
    session.xSelectedOperations = session.sourceOperationMask(location)

  if not session.xSource.isNil:
    discard session.xSource.sendLocalIfHandled(
      draggingSessionMoved(), session.draggingInfo(location)
    )
  session.xSelectedOperations

proc performDraggingOperation*(
    session: DraggingSession,
    destination: DynamicAgent = nil,
    location = AutoPoint,
    dropTarget = initDraggingDropTarget(),
): bool =
  if session.isNil or session.xState != dssActive:
    return false
  session.xDropTarget = dropTarget
  let resolvedDestination =
    if destination.isNil:
      session.xDestination
    else:
      destination
  if resolvedDestination.isNil:
    return false

  let info = session.draggingInfo(location, resolvedDestination)
  let prepared = resolvedDestination.trySendLocal(prepareForDragOperation(), info)
  if prepared.isSome and not prepared.get():
    return false

  let performed = resolvedDestination.trySendLocal(performDragOperation(), info)
  result =
    if performed.isSome:
      performed.get()
    else:
      session.xSelectedOperations != NoDragOperations

  if result:
    discard resolvedDestination.sendLocalIfHandled(concludeDragOperation(), info)

proc autoscrollDraggingSession*(
    session: DraggingSession,
    location: Point,
    destination: DynamicAgent = nil,
    dropTarget = initDraggingDropTarget(),
): bool =
  if session.isNil or session.xState != dssActive:
    return false
  session.xDropTarget = dropTarget
  let resolvedDestination =
    if destination.isNil:
      session.xDestination
    else:
      destination
  if resolvedDestination.isNil:
    return false
  let handled = resolvedDestination.trySendLocal(
    autoscrollDraggingSession(),
    session.draggingInfo(location, resolvedDestination),
  )
  handled.isSome and handled.get()

proc endDraggingSession*(
    session: DraggingSession,
    operation: DragOperations = NoDragOperations,
) =
  if session.isNil or session.xState notin {dssReady, dssActive}:
    return
  session.xSelectedOperations = operation
  session.xState = dssEnded
  if not session.xSource.isNil:
    discard session.xSource.sendLocalIfHandled(
      draggingSessionEnded(), session.draggingInfo()
    )

proc cancelDraggingSession*(session: DraggingSession) =
  if session.isNil or session.xState notin {dssReady, dssActive}:
    return
  session.xSelectedOperations = NoDragOperations
  session.xState = dssCancelled
  if not session.xSource.isNil:
    discard session.xSource.sendLocalIfHandled(
      draggingSessionEnded(), session.draggingInfo()
    )
