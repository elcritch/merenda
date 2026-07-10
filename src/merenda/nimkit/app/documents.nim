import std/[options, os, strutils]

import sigils/core

import ../foundation/notifications
import ../foundation/selectors
import ../foundation/undomanagers
import ../responder/responders
import ./userdefaults
import ./application
import ./viewcontrollers
import ./windowcontrollers
import ./windows

type Document* = ref object of Responder
  xDocumentIdentifier: string
  xFileUrl: string
  xFileName: string
  xHasFileName: bool
  xFileType: string
  xDisplayName: string
  xHasDisplayName: bool
  xDocumentEdited: bool
  xClosed: bool
  xUndoManager: UndoManager
  xDelegate: DynamicAgent
  xWindowControllers: seq[WindowController]
  xUserDefaults: UserDefaults

protocol DocumentFileProtocol {.selectorScope: protocol.}:
  method canReadType*(fileType: string): bool {.optional.}
  method canWriteType*(fileType: string): bool {.optional.}
  method readContents*(fileUrl: string, fileType: string): bool {.optional.}
  method writeContents*(fileUrl: string, fileType: string): bool {.optional.}

protocol DocumentWindowProtocol {.selectorScope: protocol.}:
  method makeWindowControllers*(): seq[WindowController] {.optional.}

protocol DocumentDelegate:
  method documentWillSave*(document: Document) {.optional.}
  method documentDidSave*(document: Document) {.optional.}
  method documentWillRevert*(document: Document) {.optional.}
  method documentDidRevert*(document: Document) {.optional.}
  method documentShouldClose*(document: Document): bool {.optional.}
  method documentWillClose*(document: Document) {.optional.}
  method documentDidClose*(document: Document) {.optional.}
  method documentDidChangeName*(document: Document) {.optional.}
  method documentDidChangeEdited*(document: Document) {.optional.}

protocol DocumentEvents:
  proc willSaveDocument*(document: Document, fileUrl: string) {.signal.}
  proc didSaveDocument*(document: Document, fileUrl: string) {.signal.}
  proc willRevertDocument*(document: Document, fileUrl: string) {.signal.}
  proc didRevertDocument*(document: Document, fileUrl: string) {.signal.}
  proc willCloseDocument*(document: Document) {.signal.}
  proc didCloseDocument*(document: Document) {.signal.}
  proc didChangeDisplayName*(document: Document, displayName: string) {.signal.}
  proc didChangeDocumentEdited*(document: Document, edited: bool) {.signal.}
  proc didAddWindowController*(
    document: Document, controller: WindowController
  ) {.signal.}

  proc didRemoveWindowController*(
    document: Document, controller: WindowController
  ) {.signal.}

proc setDocumentEdited*(document: Document, edited: bool)
proc displayName*(document: Document): string
proc isDocumentEdited*(document: Document): bool
proc undoManagerFor*(document: Document): UndoManager
proc setUndoManager*(document: Document, undoManager: UndoManager)
proc userDefaults*(document: Document): UserDefaults
proc save*(document: Document): bool {.discardable.}
proc revert*(document: Document): bool {.discardable.}
proc close*(document: Document): bool {.discardable.}
proc syncWindowControllerTitles(document: Document)
proc setDocumentEditedFromUndoManager(document: Document, edited: bool)

var nextDocumentIdentifierValue = 0

proc nextDocumentIdentifier(): string =
  inc nextDocumentIdentifierValue
  "document:" & $nextDocumentIdentifierValue

proc filePathFromUrl(fileUrl: string): string =
  result = fileUrl
  let queryStart = result.find('?')
  if queryStart >= 0:
    result.setLen(queryStart)
  let fragmentStart = result.find('#')
  if fragmentStart >= 0:
    result.setLen(fragmentStart)
  if result.startsWith("file://"):
    result = result[7 .. ^1]

proc defaultFileName(fileUrl: string): string =
  let path = filePathFromUrl(fileUrl)
  if path.len == 0:
    return ""
  path.extractFilename()

proc inferredFileType(fileUrl: string): string =
  let ext = splitFile(filePathFromUrl(fileUrl)).ext
  if ext.len > 0 and ext[0] == '.':
    return ext[1 .. ^1]
  ext

proc resolvedFileType(document: Document, fileUrl, fileType: string): string =
  if fileType.len > 0:
    return fileType
  if document.xFileType.len > 0:
    return document.xFileType
  inferredFileType(fileUrl)

proc sendDocumentDelegate(document: Document, selector: Selector[Document, EmptyArgs]) =
  if not document.xDelegate.isNil:
    discard document.xDelegate.sendLocalIfHandled(selector, document)

proc postNotification(document: Document, kind: NotificationKind, fileUrl = "") =
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      kind,
      sender = DynamicAgent(document),
      payload = initDocumentNotificationPayload(
        fileUrl = if fileUrl.len > 0: fileUrl else: document.xFileUrl,
        fileType = document.xFileType,
        displayName = document.displayName(),
        edited = document.xDocumentEdited,
        closed = document.xClosed,
      ),
    )
  )

proc notifyDisplayNameChanged(document: Document) =
  document.sendDocumentDelegate(documentDidChangeName())
  emit document.didChangeDisplayName(document.displayName())
  document.postNotification(nkDocumentDidChangeDisplayName)
  document.syncWindowControllerTitles()

proc notifyDocumentEditedChanged(document: Document) =
  document.sendDocumentDelegate(documentDidChangeEdited())
  emit document.didChangeDocumentEdited(document.isDocumentEdited())
  document.postNotification(nkDocumentDidChangeEdited)

proc documentShouldCloseNow(document: Document): bool =
  if not document.xDelegate.isNil:
    let allowed = document.xDelegate.trySendLocal(documentShouldClose(), document)
    if allowed.isSome:
      return allowed.get()
  document.trySendLocal(documentShouldClose(), document).get(true)

protocol DocumentUndoManagerProvider of UndoManagerProvider:
  method undoManager(document: Document): Option[UndoManager] =
    some(document.undoManagerFor())

protocol DocumentDefaultsProvider of UserDefaultsProvider:
  method defaultsStore(document: Document): DynamicAgent =
    DynamicAgent(document.userDefaults())

  method defaultsScopeId(document: Document): string =
    if document.xFileUrl.len > 0:
      return "document:file:" & document.xFileUrl
    if document.xHasDisplayName:
      return "document:name:" & document.xDisplayName
    let name =
      if document.xHasFileName:
        document.xFileName
      else:
        defaultFileName(document.xFileUrl)
    if name.len > 0:
      "document:name:" & name
    else:
      "document:untitled"

protocol DocumentMenuCommands of MenuCommandProtocol:
  method saveDocument(document: Document, args: ActionArgs) =
    discard document.save()

  method saveDocumentAs(document: Document, args: ActionArgs) =
    discard document.save()

  method revertDocumentToSaved(document: Document, args: ActionArgs) =
    discard document.revert()

  method performClose(document: Document, args: ActionArgs) =
    discard document.close()

protocol DefaultDocumentWindows of DocumentWindowProtocol:
  method makeWindowControllers(document: Document): seq[WindowController] =
    @[newWindowController()]

proc initDocument*(document: Document, fileUrl = "", fileType = "", fileName = "") =
  initResponder(document)
  document.xDocumentIdentifier = nextDocumentIdentifier()
  document.xFileUrl = fileUrl
  document.xFileType =
    if fileType.len > 0:
      fileType
    else:
      inferredFileType(fileUrl)
  if fileName.len > 0:
    document.xFileName = fileName
    document.xHasFileName = true
  discard document.withProtocol(DocumentUndoManagerProvider)
  discard document.withProtocol(DocumentDefaultsProvider)
  discard document.withProtocol(DocumentMenuCommands)
  discard document.withProtocol(DefaultDocumentWindows)

proc newDocument*(fileUrl = "", fileType = "", fileName = ""): Document =
  result = Document()
  result.initDocument(fileUrl, fileType, fileName)

proc delegate*(document: Document): DynamicAgent =
  document.xDelegate

proc `delegate=`*(document: Document, delegate: DynamicAgent) =
  document.xDelegate = delegate

proc `delegate=`*(document: Document, delegate: Responder) =
  document.delegate = DynamicAgent(delegate)

proc fileUrl*(document: Document): string =
  document.xFileUrl

proc documentIdentifier*(document: Document): string =
  if document.xFileUrl.len > 0:
    "file:" & document.xFileUrl
  else:
    document.xDocumentIdentifier

proc setFileUrl*(document: Document, fileUrl: string) =
  if document.xFileUrl == fileUrl:
    return
  let oldDisplayName = document.displayName()
  document.xFileUrl = fileUrl
  if document.xFileType.len == 0:
    document.xFileType = inferredFileType(fileUrl)
  if oldDisplayName != document.displayName():
    document.notifyDisplayNameChanged()

proc `fileUrl=`*(document: Document, fileUrl: string) =
  document.setFileUrl(fileUrl)

proc fileName*(document: Document): string =
  if document.xHasFileName:
    return document.xFileName
  defaultFileName(document.xFileUrl)

proc setFileName*(document: Document, fileName: string) =
  if (document.xHasFileName and document.xFileName == fileName):
    return
  let oldDisplayName = document.displayName()
  document.xFileName = fileName
  document.xHasFileName = true
  if oldDisplayName != document.displayName():
    document.notifyDisplayNameChanged()

proc `fileName=`*(document: Document, fileName: string) =
  document.setFileName(fileName)

proc clearFileName*(document: Document) =
  if not document.xHasFileName:
    return
  let oldDisplayName = document.displayName()
  document.xFileName = ""
  document.xHasFileName = false
  if oldDisplayName != document.displayName():
    document.notifyDisplayNameChanged()

proc fileType*(document: Document): string =
  document.xFileType

proc setFileType*(document: Document, fileType: string) =
  document.xFileType = fileType

proc `fileType=`*(document: Document, fileType: string) =
  document.setFileType(fileType)

proc displayName*(document: Document): string =
  if document.xHasDisplayName:
    return document.xDisplayName
  let name = document.fileName()
  if name.len > 0:
    return name
  "Untitled"

proc setDisplayName*(document: Document, displayName: string) =
  if (document.xHasDisplayName and document.xDisplayName == displayName):
    return
  document.xDisplayName = displayName
  document.xHasDisplayName = true
  document.notifyDisplayNameChanged()

proc `displayName=`*(document: Document, displayName: string) =
  document.setDisplayName(displayName)

proc clearDisplayName*(document: Document) =
  if not document.xHasDisplayName:
    return
  let oldDisplayName = document.displayName()
  document.xDisplayName = ""
  document.xHasDisplayName = false
  if oldDisplayName != document.displayName():
    document.notifyDisplayNameChanged()

proc isDocumentEdited*(document: Document): bool =
  document.xDocumentEdited

proc documentEdited*(document: Document): bool =
  document.isDocumentEdited()

proc setDocumentEdited*(document: Document, edited: bool) =
  if edited:
    if not document.xUndoManager.isNil and document.xUndoManager.isAtCleanState():
      document.xUndoManager.clearCleanState()
  elif not document.xUndoManager.isNil:
    document.xUndoManager.markCleanState()
  if document.xDocumentEdited == edited:
    return
  document.xDocumentEdited = edited
  document.notifyDocumentEditedChanged()

proc setDocumentEditedFromUndoManager(document: Document, edited: bool) =
  if document.xDocumentEdited == edited:
    return
  document.xDocumentEdited = edited
  document.notifyDocumentEditedChanged()

proc `documentEdited=`*(document: Document, edited: bool) =
  document.setDocumentEdited(edited)

proc isClosed*(document: Document): bool =
  document.xClosed

proc undoManagerFor*(document: Document): UndoManager =
  if document.xUndoManager.isNil:
    document.setUndoManager(newUndoManager())
  document.xUndoManager

proc userDefaults*(document: Document): UserDefaults =
  if document.xUserDefaults.isNil:
    document.xUserDefaults = newUserDefaults()
  document.xUserDefaults

proc undoManagerStateDidChange(document: Document, manager: UndoManager) {.slot.} =
  if document.xUndoManager != manager:
    return
  document.setDocumentEditedFromUndoManager(not manager.isAtCleanState())

proc setUndoManager*(document: Document, undoManager: UndoManager) =
  if document.xUndoManager == undoManager:
    return
  if not document.xUndoManager.isNil:
    document.xUndoManager.disconnect(
      stateDidChange, document, undoManagerStateDidChange
    )
  document.xUndoManager = undoManager
  if not undoManager.isNil:
    undoManager.connect(stateDidChange, document, undoManagerStateDidChange)
    if document.xDocumentEdited:
      undoManager.clearCleanState()
    else:
      undoManager.markCleanState()

proc `undoManager=`*(document: Document, undoManager: UndoManager) =
  document.setUndoManager(undoManager)

proc windowControllers*(document: Document): lent seq[WindowController] =
  document.xWindowControllers

proc windowControllerCount*(document: Document): int =
  document.xWindowControllers.len

proc syncWindowControllerTitles(document: Document) =
  let name = document.displayName()
  for controller in document.xWindowControllers:
    controller.documentDisplayName = name

proc addWindowController*(document: Document, controller: WindowController) =
  if controller.isNil or controller in document.xWindowControllers:
    return
  document.xWindowControllers.add controller
  controller.documentDisplayName = document.displayName()
  let viewController = controller.viewController()
  if not viewController.isNil and viewController.representedObject().isNil:
    viewController.representedObject = DynamicAgent(document)
  let forwardedNext = controller.nextResponder()
  if forwardedNext != Responder(document):
    if document.nextResponder().isNil and not forwardedNext.isNil:
      document.setNextResponder(forwardedNext)
    controller.setNextResponder(document)
  emit document.didAddWindowController(controller)

proc removeWindowController*(
    document: Document, controller: WindowController
): bool {.discardable.} =
  if controller.isNil:
    return false
  let idx = document.xWindowControllers.find(controller)
  if idx < 0:
    return false
  document.xWindowControllers.delete(idx)
  if controller.nextResponder() == Responder(document):
    let next = document.nextResponder()
    if next.isNil:
      controller.clearNextResponder()
    else:
      controller.setNextResponder(next)
  emit document.didRemoveWindowController(controller)
  true

proc canReadFileType*(document: Document, fileType: string): bool =
  document.trySendLocal(canReadType(), fileType).get(true)

proc canWriteFileType*(document: Document, fileType: string): bool =
  document.trySendLocal(canWriteType(), fileType).get(true)

proc readFromFileUrl*(
    document: Document, fileUrl: string, fileType = ""
): bool {.discardable.} =
  if fileUrl.len == 0:
    return false
  let resolvedType = document.resolvedFileType(fileUrl, fileType)
  if not document.canReadFileType(resolvedType):
    return false
  let oldDisplayName = document.displayName()
  let read =
    document.trySendLocal(readContents(), (fileUrl: fileUrl, fileType: resolvedType))
  if read.isNone or not read.get():
    return false
  document.xFileUrl = fileUrl
  document.xFileType = resolvedType
  document.setDocumentEdited(false)
  if oldDisplayName != document.displayName():
    document.notifyDisplayNameChanged()
  true

proc writeToFileUrl*(
    document: Document, fileUrl: string, fileType = ""
): bool {.discardable.} =
  if fileUrl.len == 0:
    return false
  let resolvedType = document.resolvedFileType(fileUrl, fileType)
  if not document.canWriteFileType(resolvedType):
    return false
  let oldDisplayName = document.displayName()
  let written =
    document.trySendLocal(writeContents(), (fileUrl: fileUrl, fileType: resolvedType))
  if written.isNone or not written.get():
    return false
  document.xFileUrl = fileUrl
  document.xFileType = resolvedType
  document.setDocumentEdited(false)
  if oldDisplayName != document.displayName():
    document.notifyDisplayNameChanged()
  true

proc save*(document: Document): bool {.discardable.} =
  if document.xFileUrl.len == 0:
    return false
  document.sendDocumentDelegate(documentWillSave())
  emit document.willSaveDocument(document.xFileUrl)
  document.postNotification(nkDocumentWillSave)
  result = document.writeToFileUrl(document.xFileUrl, document.xFileType)
  if result:
    document.sendDocumentDelegate(documentDidSave())
    emit document.didSaveDocument(document.xFileUrl)
    document.postNotification(nkDocumentDidSave)

proc saveAs*(document: Document, fileUrl: string, fileType = ""): bool {.discardable.} =
  if fileUrl.len == 0:
    return false
  document.sendDocumentDelegate(documentWillSave())
  emit document.willSaveDocument(fileUrl)
  document.postNotification(nkDocumentWillSave, fileUrl)
  result = document.writeToFileUrl(fileUrl, fileType)
  if result:
    document.sendDocumentDelegate(documentDidSave())
    emit document.didSaveDocument(fileUrl)
    document.postNotification(nkDocumentDidSave)

proc revert*(document: Document): bool {.discardable.} =
  if document.xFileUrl.len == 0:
    return false
  let fileUrl = document.xFileUrl
  document.sendDocumentDelegate(documentWillRevert())
  emit document.willRevertDocument(fileUrl)
  document.postNotification(nkDocumentWillRevert)
  result = document.readFromFileUrl(fileUrl, document.xFileType)
  if result:
    document.sendDocumentDelegate(documentDidRevert())
    emit document.didRevertDocument(fileUrl)
    document.postNotification(nkDocumentDidRevert)

proc ensureWindowControllers(document: Document) =
  if document.xWindowControllers.len > 0:
    return
  let controllers = document.trySendLocal(makeWindowControllers(), ()).get(@[])
  for controller in controllers:
    document.addWindowController(controller)

proc removeClosedWindowControllers(document: Document) =
  var index = document.xWindowControllers.high
  while index >= 0:
    let
      controller = document.xWindowControllers[index]
      window =
        if controller.isNil:
          nil
        else:
          controller.windowOrNil()
    if not window.isNil and window.isClosed:
      discard document.removeWindowController(controller)
    dec index

proc showWindows*(
    document: Document, app: Application = nil
): seq[Window] {.discardable.} =
  document.removeClosedWindowControllers()
  document.ensureWindowControllers()
  if not app.isNil:
    document.setNextResponder(app)
  for controller in document.xWindowControllers:
    if not app.isNil:
      let window = controller.showWindow(app)
      controller.setNextResponder(document)
      if not window.isNil:
        result.add window
    else:
      controller.setNextResponder(document)
      let window = controller.showWindow()
      if not window.isNil:
        result.add window

proc close*(document: Document): bool {.discardable.} =
  if document.xClosed:
    return true
  if not document.documentShouldCloseNow():
    return false
  document.sendDocumentDelegate(documentWillClose())
  emit document.willCloseDocument()
  document.postNotification(nkDocumentWillClose)
  for controller in document.xWindowControllers:
    if not controller.close():
      return false
  document.xClosed = true
  document.sendDocumentDelegate(documentDidClose())
  emit document.didCloseDocument()
  document.postNotification(nkDocumentDidClose)
  true
