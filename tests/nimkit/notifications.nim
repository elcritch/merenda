import std/[options, unittest]

import sigils/core

import merenda/nimkit

type NotificationSignalSpy = ref object of Agent
  notifications: seq[Notification]

type TestFileDocument = ref object of Document
  reads: int
  writes: int

proc rememberNotification(
    spy: NotificationSignalSpy, notification: Notification
) {.slot.} =
  spy.notifications.add notification

protocol TestFileDocumentProtocol of DocumentFileProtocol:
  method readContents(
      document: TestFileDocument, fileUrl: string, fileType: string
  ): bool =
    discard fileUrl
    discard fileType
    inc document.reads
    true

  method writeContents(
      document: TestFileDocument, fileUrl: string, fileType: string
  ): bool =
    discard fileUrl
    discard fileType
    inc document.writes
    true

proc notificationKinds(notifications: openArray[Notification]): seq[NotificationKind] =
  for notification in notifications:
    result.add notification.kind

proc lastNotification(
    notifications: openArray[Notification], kind: NotificationKind
): Option[Notification] =
  var index = notifications.high
  while index >= 0:
    if notifications[index].kind == kind:
      return some(notifications[index])
    dec index
  none(Notification)

proc requireNotification(
    notifications: openArray[Notification], kind: NotificationKind
): Notification =
  let found = notifications.lastNotification(kind)
  check found.isSome
  if found.isSome:
    found.get()
  else:
    initNotification(kind)

suite "nimkit notifications":
  test "notification center filters signals and unregisters deterministically":
    let
      center = newNotificationCenter()
      sender = newUserDefaults()
      signalSpy = NotificationSignalSpy()

    var
      allKinds: seq[NotificationKind]
      defaultsKinds: seq[NotificationKind]
      undoNames: seq[string]
      senderMatches = 0

    center.connect(notificationPosted, signalSpy, rememberNotification)

    proc recordAll(notification: Notification) =
      allKinds.add notification.kind

    proc recordDefaults(notification: Notification) =
      defaultsKinds.add notification.kind

    proc recordUndoName(notification: Notification) =
      undoNames.add notification.name

    proc recordSender(notification: Notification) =
      discard notification
      inc senderMatches

    let allToken = center.observe(recordAll)
    let defaultsToken = center.observe(nkDefaultsDidChange, recordDefaults)
    let undoNameToken =
      center.observeName(notificationName(nkUndoStateDidChange), recordUndoName)
    let senderToken = center.addObserver(recordSender, sender = DynamicAgent(sender))

    center.post(
      initNotification(
        nkDefaultsDidChange,
        sender = DynamicAgent(sender),
        payload = initDefaultsNotificationPayload(dckSet, "theme", DynamicAgent(sender)),
      )
    )
    center.post(initNotification(nkUndoStateDidChange))

    check signalSpy.notifications.notificationKinds() ==
      @[nkDefaultsDidChange, nkUndoStateDidChange]
    check allKinds == @[nkDefaultsDidChange, nkUndoStateDidChange]
    check defaultsKinds == @[nkDefaultsDidChange]
    check undoNames == @[notificationName(nkUndoStateDidChange)]
    check senderMatches == 1
    check center.observerCount() == 4

    check defaultsToken.unregister()
    check not defaultsToken.isRegistered()

    center.post(initNotification(nkDefaultsDidChange, sender = DynamicAgent(sender)))
    check allKinds == @[nkDefaultsDidChange, nkUndoStateDidChange, nkDefaultsDidChange]
    check defaultsKinds == @[nkDefaultsDidChange]
    check senderMatches == 2

    var selfRemovingCount = 0
    var selfRemovingToken: NotificationObserverToken

    proc recordAndRemove(notification: Notification) =
      discard notification
      inc selfRemovingCount
      check selfRemovingToken.unregister()

    selfRemovingToken = center.observe(nkDefaultsDidChange, recordAndRemove)

    center.post(initNotification(nkDefaultsDidChange))
    center.post(initNotification(nkDefaultsDidChange))
    check selfRemovingCount == 1
    check not selfRemovingToken.isRegistered()

    check allToken.unregister()
    check undoNameToken.unregister()
    check senderToken.unregister()

  test "lifecycle defaults undo selection and model events post typed payloads":
    let center = sharedNotificationCenter()
    var notifications: seq[Notification]

    proc record(notification: Notification) =
      notifications.add notification

    let token = center.observe(record)

    let app = newApplication()
    app.activate()
    app.deactivate()

    var appearance = initAppearance()
    appearance[srButton, StyleCornerRadius] = 5.0'f32
    app.setAppearance(appearance)

    let window = newWindow("Notifications", frame = initRect(0, 0, 320, 180))
    app.addWindow(window)
    window.setAppearance(appearance)
    window.close()

    let defaults = newUserDefaults()
    defaults.setObjectForKey("theme", DynamicAgent(app))

    let manager = newUndoManager()
    manager.registerUndo(
      proc() =
        discard,
      "Change",
    )

    let selection = newSelectionController(mselMultiple)
    selection.setSelectedIdentifiers(["one", "two"])

    let array = newArrayController(
      [
        initModelItem(
          "one",
          objectValue = toObjectValue("One"),
          fields = [initModelField("name", toObjectValue("One"))],
        )
      ]
    )
    array.setValue("one", "name", toObjectValue("Uno"))

    check token.unregister()

    let becameActive = notifications.requireNotification(nkApplicationDidBecomeActive)
    check becameActive.sender == DynamicAgent(app)
    check becameActive.payload.kind == npApplication
    check becameActive.payload.application.active

    let appAppearance =
      notifications.requireNotification(nkApplicationAppearanceDidChange)
    check appAppearance.payload.kind == npAppearance
    check appAppearance.payload.appearance.targetKind == atkApplication
    check appAppearance.payload.appearance.hasExplicitAppearance

    let keyWindow = notifications.requireNotification(nkWindowDidBecomeKey)
    check keyWindow.sender == DynamicAgent(window)
    check keyWindow.payload.kind == npWindow
    check keyWindow.payload.window.keyWindow

    let windowClosed = notifications.requireNotification(nkWindowDidClose)
    check windowClosed.payload.window.closed

    let defaultsChanged = notifications.requireNotification(nkDefaultsDidChange)
    check defaultsChanged.sender == DynamicAgent(defaults)
    check defaultsChanged.payload.kind == npDefaults
    check defaultsChanged.payload.defaults.change == dckSet
    check defaultsChanged.payload.defaults.key == "theme"
    check defaultsChanged.payload.defaults.value == DynamicAgent(app)

    let undoChanged = notifications.requireNotification(nkUndoStateDidChange)
    check undoChanged.sender == DynamicAgent(manager)
    check undoChanged.payload.kind == npUndo
    check undoChanged.payload.undo.undoCount == 1
    check undoChanged.payload.undo.nextUndoActionName == "Change"

    let selectionChanged = notifications.requireNotification(nkSelectionDidChange)
    check selectionChanged.sender == DynamicAgent(selection)
    check selectionChanged.payload.kind == npSelection
    check selectionChanged.payload.selection.change == sckModel
    check selectionChanged.payload.selection.selectedIdentifiers == @["one", "two"]
    check selectionChanged.payload.selection.leadIdentifier == "two"

    let modelChanged = notifications.requireNotification(nkModelMutationDidChange)
    check modelChanged.sender == DynamicAgent(array)
    check modelChanged.payload.kind == npModel
    check modelChanged.payload.model.mutation == mmkValueChanged
    check modelChanged.payload.model.identifiers == @["one"]
    check modelChanged.payload.model.keys == @["name"]

  test "document lifecycle notifications carry file payloads":
    let center = sharedNotificationCenter()
    var notifications: seq[Notification]

    proc record(notification: Notification) =
      notifications.add notification

    let token = center.observe(record)

    let document = TestFileDocument()
    document.initDocument(fileUrl = "file:///tmp/notes.txt", fileType = "txt")
    discard document.withProtocol(TestFileDocumentProtocol)

    check document.save()
    check document.revert()
    document.displayName = "Notes"
    document.documentEdited = true
    check document.close()

    check token.unregister()

    check document.writes == 1
    check document.reads == 1

    let didSave = notifications.requireNotification(nkDocumentDidSave)
    check didSave.sender == DynamicAgent(document)
    check didSave.payload.kind == npDocument
    check didSave.payload.document.fileUrl == "file:///tmp/notes.txt"
    check didSave.payload.document.fileType == "txt"

    let didRevert = notifications.requireNotification(nkDocumentDidRevert)
    check didRevert.payload.document.fileUrl == "file:///tmp/notes.txt"

    let didRename = notifications.requireNotification(nkDocumentDidChangeDisplayName)
    check didRename.payload.document.displayName == "Notes"

    let didEdit = notifications.requireNotification(nkDocumentDidChangeEdited)
    check didEdit.payload.document.edited

    let didClose = notifications.requireNotification(nkDocumentDidClose)
    check didClose.payload.document.closed
