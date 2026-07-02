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

  NotificationCenter* = ref object of DynamicAgent
    xObservers: seq[NotificationObserverEntry]
    xNextObserverId: Natural
    xPostingDepth: Natural
    xNeedsCompaction: bool

  NotificationObserverToken* = object
    id*: Natural
    center: NotificationCenter

  NotificationObserverEntry = object
    token: NotificationObserverToken
    kind: Option[NotificationKind]
    name: string
    sender: DynamicAgent
    representedObject: DynamicAgent
    active: bool
    observer: NotificationObserver

protocol NotificationCenterEvents:
  proc notificationPosted*(
    center: NotificationCenter, notification: Notification
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

proc newNotificationCenter*(): NotificationCenter =
  NotificationCenter()

proc sharedNotificationCenter*(): NotificationCenter =
  if sharedNotificationCenterInstance.isNil:
    sharedNotificationCenterInstance = newNotificationCenter()
  sharedNotificationCenterInstance

proc compactInactive(center: NotificationCenter) =
  if center.isNil or center.xPostingDepth > 0:
    return
  var index = center.xObservers.high
  while index >= 0:
    if not center.xObservers[index].active:
      center.xObservers.delete(index)
    dec index
  center.xNeedsCompaction = false

proc matches(entry: NotificationObserverEntry, notification: Notification): bool =
  if entry.kind.isSome and entry.kind.get() != notification.kind:
    return false
  if entry.name.len > 0 and entry.name != notification.name:
    return false
  if not entry.sender.isNil and entry.sender != notification.sender:
    return false
  if not entry.representedObject.isNil and
      entry.representedObject != notification.representedObject:
    return false
  true

proc addObserver*(
    center: NotificationCenter,
    observer: NotificationObserver,
    kind = none(NotificationKind),
    name = "",
    sender: DynamicAgent = nil,
    representedObject: DynamicAgent = nil,
): NotificationObserverToken =
  if center.isNil or observer.isNil:
    return
  inc center.xNextObserverId
  result = NotificationObserverToken(id: center.xNextObserverId, center: center)
  center.xObservers.add NotificationObserverEntry(
    token: result,
    kind: kind,
    name: name,
    sender: sender,
    representedObject: representedObject,
    active: true,
    observer: observer,
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

proc removeObserver*(
    center: NotificationCenter, token: NotificationObserverToken
): bool {.discardable.} =
  if center.isNil or token.center != center or token.id == 0:
    return false
  for index, entry in center.xObservers:
    if entry.active and entry.token.id == token.id:
      center.xObservers[index].active = false
      center.xObservers[index].observer = nil
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
  if center.isNil or token.center != center or token.id == 0:
    return false
  for entry in center.xObservers:
    if entry.active and entry.token.id == token.id:
      return true

proc isRegistered*(token: NotificationObserverToken): bool =
  not token.center.isNil and token.center.isRegistered(token)

proc observerCount*(center: NotificationCenter): Natural =
  if center.isNil:
    return 0
  for entry in center.xObservers:
    if entry.active:
      inc result

proc post*(center: NotificationCenter, notification: Notification) =
  if center.isNil:
    return
  var delivered = notification
  if delivered.name.len == 0:
    delivered.name = notificationName(delivered.kind)
  emit center.notificationPosted(delivered)
  inc center.xPostingDepth
  let limit = center.xObservers.len
  try:
    var index = 0
    while index < limit:
      if index < center.xObservers.len:
        let entry = center.xObservers[index]
        if entry.active and not entry.observer.isNil and entry.matches(delivered):
          entry.observer(delivered)
      inc index
  finally:
    dec center.xPostingDepth
    if center.xPostingDepth == 0 and center.xNeedsCompaction:
      center.compactInactive()

proc postNotification*(
    kind: NotificationKind,
    sender: DynamicAgent = nil,
    representedObject: DynamicAgent = nil,
    payload = initNotificationPayload(),
    name = "",
) =
  sharedNotificationCenter().post(
    initNotification(kind, sender, representedObject, payload, name)
  )
