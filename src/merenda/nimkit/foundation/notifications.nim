import std/options

import sigils/core
import sigils/selectors

import ../themes/themecore

type
  NotificationKind* = enum
    nkApplicationWillFinishLaunching
    nkApplicationDidFinishLaunching
    nkApplicationDidBecomeActive
    nkApplicationDidResignActive
    nkApplicationWillHide
    nkApplicationDidHide
    nkApplicationWillUnhide
    nkApplicationDidUnhide
    nkApplicationWillTerminate
    nkApplicationAppearanceDidChange
    nkWindowDidBecomeKey
    nkWindowDidResignKey
    nkWindowDidBecomeMain
    nkWindowDidResignMain
    nkWindowWillClose
    nkWindowDidClose
    nkWindowAppearanceDidChange
    nkDocumentWillSave
    nkDocumentDidSave
    nkDocumentWillRevert
    nkDocumentDidRevert
    nkDocumentWillClose
    nkDocumentDidClose
    nkDocumentDidChangeDisplayName
    nkDocumentDidChangeEdited
    nkDocControllerDidCreateDocument
    nkDocControllerDidOpenDocument
    nkDocControllerDidReopenDocument
    nkDocControllerDidAddDocument
    nkDocControllerDidRemoveDocument
    nkDocControllerDidChangeRecentDocuments
    nkDefaultsDidChange
    nkUndoStateDidChange
    nkSelectionDidChange
    nkModelMutationDidChange

  DefaultsChangeKind* = enum
    dckSet
    dckRemove
    dckClear

  AppearanceTargetKind* = enum
    atkApplication
    atkWindow
    atkView

  SelectionChangeKind* = enum
    sckUnknown
    sckModel
    sckTable
    sckCascading
    sckComboBox
    sckMatrix
    sckDocumentTabs

  ModelMutationKind* = enum
    mmkUnknown
    mmkItemChanged
    mmkObjectValueChanged
    mmkValueChanged
    mmkItemsChanged
    mmkColumnsChanged
    mmkSortChanged
    mmkFilterChanged
    mmkTreeChanged
    mmkBatchChanged

  ApplicationNotificationPayload* = object
    active*: bool
    hidden*: bool
    terminating*: bool

  WindowNotificationPayload* = object
    keyWindow*: bool
    mainWindow*: bool
    visible*: bool
    closed*: bool

  DocumentNotificationPayload* = object
    fileUrl*: string
    fileType*: string
    displayName*: string
    edited*: bool
    closed*: bool

  DefaultsNotificationPayload* = object
    change*: DefaultsChangeKind
    key*: string
    hasValue*: bool
    value*: DynamicAgent

  AppearanceNotificationPayload* = object
    targetKind*: AppearanceTargetKind
    hasExplicitAppearance*: bool
    appearance*: Appearance

  UndoNotificationPayload* = object
    undoCount*: Natural
    redoCount*: Natural
    groupingDepth*: Natural
    disabledDepth*: Natural
    undoing*: bool
    redoing*: bool
    clean*: bool
    nextUndoActionName*: string
    nextRedoActionName*: string

  SelectionNotificationPayload* = object
    change*: SelectionChangeKind
    selectedIdentifiers*: seq[string]
    anchorIdentifier*: string
    leadIdentifier*: string
    selectedIndex*: int
    selectedIndexes*: seq[int]

  ModelNotificationPayload* = object
    mutation*: ModelMutationKind
    identifiers*: seq[string]
    keys*: seq[string]
    index*: int
    count*: Natural

  NotificationPayloadKind* = enum
    npNone
    npApplication
    npWindow
    npDocument
    npDefaults
    npAppearance
    npUndo
    npSelection
    npModel

  NotificationPayload* = object
    case kind*: NotificationPayloadKind
    of npNone:
      discard
    of npApplication:
      application*: ApplicationNotificationPayload
    of npWindow:
      window*: WindowNotificationPayload
    of npDocument:
      document*: DocumentNotificationPayload
    of npDefaults:
      defaults*: DefaultsNotificationPayload
    of npAppearance:
      appearance*: AppearanceNotificationPayload
    of npUndo:
      undo*: UndoNotificationPayload
    of npSelection:
      selection*: SelectionNotificationPayload
    of npModel:
      model*: ModelNotificationPayload

  Notification* = object
    sender*: DynamicAgent
    name*: string
    kind*: NotificationKind
    representedObject*: DynamicAgent
    payload*: NotificationPayload

  NotificationObserver* = proc(notification: Notification) {.closure.}

  NotificationObserverAgent = ref object of DynamicAgent
    observer: NotificationObserver

  NotificationRoute* = ref object of DynamicAgent
    xId: Natural
    xKind: Option[NotificationKind]
    xName: string
    xSender: DynamicAgent
    xRepresentedObject: DynamicAgent
    xActive: bool
    xObserverAgent: NotificationObserverAgent

  NotificationCenter* = ref object of DynamicAgent
    xRoutes: seq[NotificationRoute]
    xNextObserverId: Natural
    xPostingDepth: Natural
    xNeedsCompaction: bool

  NotificationObserverToken* = object
    id*: Natural
    center: NotificationCenter
    route: NotificationRoute

protocol NotificationCenterEvents:
  proc notificationReceived*(
    center: NotificationCenter, notification: Notification
  ) {.signal.}

  proc notificationPosted*(
    center: NotificationCenter, notification: Notification
  ) {.signal.}

protocol NotificationRouteEvents:
  proc notificationMatched*(
    route: NotificationRoute, notification: Notification
  ) {.signal.}

var sharedNotificationCenterInstance {.threadvar.}: NotificationCenter

func notificationName*(kind: NotificationKind): string =
  case kind
  of nkApplicationWillFinishLaunching:
    "nimkit.application.willFinishLaunching"
  of nkApplicationDidFinishLaunching:
    "nimkit.application.didFinishLaunching"
  of nkApplicationDidBecomeActive:
    "nimkit.application.didBecomeActive"
  of nkApplicationDidResignActive:
    "nimkit.application.didResignActive"
  of nkApplicationWillHide:
    "nimkit.application.willHide"
  of nkApplicationDidHide:
    "nimkit.application.didHide"
  of nkApplicationWillUnhide:
    "nimkit.application.willUnhide"
  of nkApplicationDidUnhide:
    "nimkit.application.didUnhide"
  of nkApplicationWillTerminate:
    "nimkit.application.willTerminate"
  of nkApplicationAppearanceDidChange:
    "nimkit.application.appearanceDidChange"
  of nkWindowDidBecomeKey:
    "nimkit.window.didBecomeKey"
  of nkWindowDidResignKey:
    "nimkit.window.didResignKey"
  of nkWindowDidBecomeMain:
    "nimkit.window.didBecomeMain"
  of nkWindowDidResignMain:
    "nimkit.window.didResignMain"
  of nkWindowWillClose:
    "nimkit.window.willClose"
  of nkWindowDidClose:
    "nimkit.window.didClose"
  of nkWindowAppearanceDidChange:
    "nimkit.window.appearanceDidChange"
  of nkDocumentWillSave:
    "nimkit.document.willSave"
  of nkDocumentDidSave:
    "nimkit.document.didSave"
  of nkDocumentWillRevert:
    "nimkit.document.willRevert"
  of nkDocumentDidRevert:
    "nimkit.document.didRevert"
  of nkDocumentWillClose:
    "nimkit.document.willClose"
  of nkDocumentDidClose:
    "nimkit.document.didClose"
  of nkDocumentDidChangeDisplayName:
    "nimkit.document.didChangeDisplayName"
  of nkDocumentDidChangeEdited:
    "nimkit.document.didChangeEdited"
  of nkDocControllerDidCreateDocument:
    "nimkit.docController.didCreateDocument"
  of nkDocControllerDidOpenDocument:
    "nimkit.docController.didOpenDocument"
  of nkDocControllerDidReopenDocument:
    "nimkit.docController.didReopenDocument"
  of nkDocControllerDidAddDocument:
    "nimkit.docController.didAddDocument"
  of nkDocControllerDidRemoveDocument:
    "nimkit.docController.didRemoveDocument"
  of nkDocControllerDidChangeRecentDocuments:
    "nimkit.docController.didChangeRecentDocuments"
  of nkDefaultsDidChange:
    "nimkit.defaults.didChange"
  of nkUndoStateDidChange:
    "nimkit.undo.stateDidChange"
  of nkSelectionDidChange:
    "nimkit.selection.didChange"
  of nkModelMutationDidChange:
    "nimkit.model.mutationDidChange"

func initNotificationPayload*(): NotificationPayload =
  NotificationPayload(kind: npNone)

func initApplicationNotificationPayload*(
    active = false, hidden = false, terminating = false
): NotificationPayload =
  NotificationPayload(
    kind: npApplication,
    application: ApplicationNotificationPayload(
      active: active, hidden: hidden, terminating: terminating
    ),
  )

func initWindowNotificationPayload*(
    keyWindow = false, mainWindow = false, visible = false, closed = false
): NotificationPayload =
  NotificationPayload(
    kind: npWindow,
    window: WindowNotificationPayload(
      keyWindow: keyWindow, mainWindow: mainWindow, visible: visible, closed: closed
    ),
  )

func initDocumentNotificationPayload*(
    fileUrl = "", fileType = "", displayName = "", edited = false, closed = false
): NotificationPayload =
  NotificationPayload(
    kind: npDocument,
    document: DocumentNotificationPayload(
      fileUrl: fileUrl,
      fileType: fileType,
      displayName: displayName,
      edited: edited,
      closed: closed,
    ),
  )

func initDefaultsNotificationPayload*(
    change: DefaultsChangeKind, key = "", value: DynamicAgent = nil
): NotificationPayload =
  NotificationPayload(
    kind: npDefaults,
    defaults: DefaultsNotificationPayload(
      change: change, key: key, hasValue: not value.isNil, value: value
    ),
  )

func initAppearanceNotificationPayload*(
    targetKind: AppearanceTargetKind,
    appearance: Appearance,
    hasExplicitAppearance = false,
): NotificationPayload =
  NotificationPayload(
    kind: npAppearance,
    appearance: AppearanceNotificationPayload(
      targetKind: targetKind,
      hasExplicitAppearance: hasExplicitAppearance,
      appearance: appearance,
    ),
  )

func initUndoNotificationPayload*(
    undoCount: Natural = 0,
    redoCount: Natural = 0,
    groupingDepth: Natural = 0,
    disabledDepth: Natural = 0,
    undoing = false,
    redoing = false,
    clean = false,
    nextUndoActionName = "",
    nextRedoActionName = "",
): NotificationPayload =
  NotificationPayload(
    kind: npUndo,
    undo: UndoNotificationPayload(
      undoCount: undoCount,
      redoCount: redoCount,
      groupingDepth: groupingDepth,
      disabledDepth: disabledDepth,
      undoing: undoing,
      redoing: redoing,
      clean: clean,
      nextUndoActionName: nextUndoActionName,
      nextRedoActionName: nextRedoActionName,
    ),
  )

func initSelectionNotificationPayload*(
    change = sckUnknown,
    selectedIdentifiers: openArray[string] = [],
    anchorIdentifier = "",
    leadIdentifier = "",
    selectedIndex = -1,
    selectedIndexes: openArray[int] = [],
): NotificationPayload =
  NotificationPayload(
    kind: npSelection,
    selection: SelectionNotificationPayload(
      change: change,
      selectedIdentifiers: @selectedIdentifiers,
      anchorIdentifier: anchorIdentifier,
      leadIdentifier: leadIdentifier,
      selectedIndex: selectedIndex,
      selectedIndexes: @selectedIndexes,
    ),
  )

func initModelNotificationPayload*(
    mutation = mmkUnknown,
    identifiers: openArray[string] = [],
    keys: openArray[string] = [],
    index = -1,
    count: Natural = 0,
): NotificationPayload =
  NotificationPayload(
    kind: npModel,
    model: ModelNotificationPayload(
      mutation: mutation,
      identifiers: @identifiers,
      keys: @keys,
      index: index,
      count: count,
    ),
  )

func initNotification*(
    kind: NotificationKind,
    sender: DynamicAgent = nil,
    representedObject: DynamicAgent = nil,
    payload = initNotificationPayload(),
    name = "",
): Notification =
  Notification(
    sender: sender,
    name:
      if name.len > 0:
        name
      else:
        notificationName(kind),
    kind: kind,
    representedObject: representedObject,
    payload: payload,
  )

proc deliverObservedNotification(
    agent: NotificationObserverAgent, notification: Notification
) {.slot.} =
  if not agent.observer.isNil:
    agent.observer(notification)

proc disconnectRoute(route: NotificationRoute) =
  var index = route.subcriptions.high
  while index >= 0:
    let entry = route.subcriptions[index]
    route.delSubscription(entry.signal, entry.subscription)
    dec index
  route.xObserverAgent = nil

proc compactInactive(center: NotificationCenter) =
  if center.xPostingDepth > 0:
    return
  var index = center.xRoutes.high
  while index >= 0:
    let route = center.xRoutes[index]
    if route.isNil or not route.xActive:
      route.disconnectRoute()
      center.xRoutes.delete(index)
    dec index
  center.xNeedsCompaction = false

proc matches(route: NotificationRoute, notification: Notification): bool =
  if not route.xActive:
    return false
  if route.xKind.isSome and route.xKind.get() != notification.kind:
    return false
  if route.xName.len > 0 and route.xName != notification.name:
    return false
  if not route.xSender.isNil and route.xSender != notification.sender:
    return false
  if not route.xRepresentedObject.isNil and
      route.xRepresentedObject != notification.representedObject:
    return false
  true

proc forwardNotification(center: NotificationCenter, notification: Notification) =
  var delivered = notification
  if delivered.name.len == 0:
    delivered.name = notificationName(delivered.kind)
  emit center.notificationPosted(delivered)
  inc center.xPostingDepth
  let limit = center.xRoutes.len
  try:
    var index = 0
    while index < limit:
      if index < center.xRoutes.len:
        let route = center.xRoutes[index]
        if route.matches(delivered):
          emit route.notificationMatched(delivered)
      inc index
  finally:
    dec center.xPostingDepth
    if center.xPostingDepth == 0 and center.xNeedsCompaction:
      center.compactInactive()

proc receiveNotification*(
    center: NotificationCenter, notification: Notification
) {.slot.} =
  center.forwardNotification(notification)

proc newNotificationCenter*(): NotificationCenter =
  result = NotificationCenter()
  result.connect(notificationReceived, result, receiveNotification)

proc sharedNotificationCenter*(): NotificationCenter =
  if sharedNotificationCenterInstance.isNil:
    sharedNotificationCenterInstance = newNotificationCenter()
  sharedNotificationCenterInstance

proc addRoute*(
    center: NotificationCenter,
    kind = none(NotificationKind),
    name = "",
    sender: DynamicAgent = nil,
    representedObject: DynamicAgent = nil,
): NotificationObserverToken =
  inc center.xNextObserverId
  let route = NotificationRoute(
    xId: center.xNextObserverId,
    xKind: kind,
    xName: name,
    xSender: sender,
    xRepresentedObject: representedObject,
    xActive: true,
  )
  center.xRoutes.add route
  NotificationObserverToken(id: route.xId, center: center, route: route)

proc addObserver*(
    center: NotificationCenter,
    observer: NotificationObserver,
    kind = none(NotificationKind),
    name = "",
    sender: DynamicAgent = nil,
    representedObject: DynamicAgent = nil,
): NotificationObserverToken =
  if observer.isNil:
    return
  result = center.addRoute(kind, name, sender, representedObject)
  if result.route.isNil:
    return
  result.route.xObserverAgent = NotificationObserverAgent(observer: observer)
  result.route.connect(
    notificationMatched, result.route.xObserverAgent, deliverObservedNotification
  )

proc observe*(
    center: NotificationCenter, observer: NotificationObserver
): NotificationObserverToken =
  center.addObserver(observer)

proc observe*(
    center: NotificationCenter,
    kind: NotificationKind,
    observer: NotificationObserver,
    sender: DynamicAgent = nil,
    representedObject: DynamicAgent = nil,
): NotificationObserverToken =
  center.addObserver(
    observer, some(kind), sender = sender, representedObject = representedObject
  )

proc observeName*(
    center: NotificationCenter,
    name: string,
    observer: NotificationObserver,
    sender: DynamicAgent = nil,
    representedObject: DynamicAgent = nil,
): NotificationObserverToken =
  center.addObserver(
    observer,
    kind = none(NotificationKind),
    name = name,
    sender = sender,
    representedObject = representedObject,
  )

proc route*(token: NotificationObserverToken): NotificationRoute =
  token.route

template connectNotification*(
    center: NotificationCenter,
    target: Agent,
    slot: untyped,
    filterSender: DynamicAgent = nil,
    filterRepresentedObject: DynamicAgent = nil,
): NotificationObserverToken =
  block:
    let token = center.addRoute(
      sender = filterSender, representedObject = filterRepresentedObject
    )
    if not token.route.isNil:
      token.route.connect(notificationMatched, target, slot)
    token

template connectNotification*(
    center: NotificationCenter,
    kind: NotificationKind,
    target: Agent,
    slot: untyped,
    filterSender: DynamicAgent = nil,
    filterRepresentedObject: DynamicAgent = nil,
): NotificationObserverToken =
  block:
    let token = center.addRoute(
      some(kind), sender = filterSender, representedObject = filterRepresentedObject
    )
    if not token.route.isNil:
      token.route.connect(notificationMatched, target, slot)
    token

template connectNotificationName*(
    center: NotificationCenter,
    name: string,
    target: Agent,
    slot: untyped,
    filterSender: DynamicAgent = nil,
    filterRepresentedObject: DynamicAgent = nil,
): NotificationObserverToken =
  block:
    let token = center.addRoute(
      name = name, sender = filterSender, representedObject = filterRepresentedObject
    )
    if not token.route.isNil:
      token.route.connect(notificationMatched, target, slot)
    token

proc removeObserver*(
    center: NotificationCenter, token: NotificationObserverToken
): bool {.discardable.} =
  if token.center != center or token.id == 0:
    return false
  for route in center.xRoutes:
    if not route.isNil and route.xActive and route.xId == token.id and
        route == token.route:
      route.xActive = false
      result = true
      break
  if result:
    if center.xPostingDepth == 0:
      center.compactInactive()
    else:
      center.xNeedsCompaction = true

proc unregister*(token: NotificationObserverToken): bool {.discardable.} =
  if token.center.isNil:
    return false
  token.center.removeObserver(token)

proc isRegistered*(center: NotificationCenter, token: NotificationObserverToken): bool =
  if token.center != center or token.id == 0:
    return false
  for route in center.xRoutes:
    if not route.isNil and route.xActive and route.xId == token.id and
        route == token.route:
      return true

proc isRegistered*(token: NotificationObserverToken): bool =
  not token.center.isNil and token.center.isRegistered(token)

proc observerCount*(center: NotificationCenter): Natural =
  for route in center.xRoutes:
    if not route.isNil and route.xActive:
      inc result

proc post*(center: NotificationCenter, notification: Notification) =
  emit center.notificationReceived(notification)

proc postNotification*(
    kind: NotificationKind,
    sender: DynamicAgent = nil,
    representedObject: DynamicAgent = nil,
    payload = initNotificationPayload(),
    name = "",
) =
  emit sharedNotificationCenter().notificationReceived(
    initNotification(kind, sender, representedObject, payload, name)
  )
