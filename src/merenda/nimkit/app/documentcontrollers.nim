import std/options

import sigils/core

import ../containers/documenttabs
import ../foundation/notifications
import ../foundation/objectvalues
import ../foundation/selectors
import ../responder/responders
import ./application
import ./documents except newDocument
import ./panels
import ./windowcontrollers
import ./windows

type
  DocumentCloseReviewAction* = enum
    dcraCancel
    dcraSave
    dcraDiscardChanges

  DocumentController* = ref object of Responder
    xApplication: Application
    xDocuments: seq[Document]
    xRecentDocumentUrls: seq[string]
    xMaximumRecentDocumentCount: Natural
    xOpenPanel: OpenPanel
    xSavePanel: SavePanel

const DefaultMaximumRecentDocumentCount* = 10

var sharedDocumentControllerInstance: DocumentController

protocol DocumentControllerFactory {.selectorScope: protocol.}:
  method defaultDocumentType*(): string {.optional.}
  method makeUntitledDocument*(fileType: string): Document {.optional.}
  method makeDocumentForFileUrl*(
    fileUrl: string, fileType: string
  ): Document {.optional.}

protocol DocumentControllerReview {.selectorScope: protocol.}:
  method reviewUnsavedDocument*(
    document: Document
  ): DocumentCloseReviewAction {.optional.}

protocol DocumentControllerEvents:
  proc didCreateDocument*(controller: DocumentController, document: Document) {.signal.}

  proc didOpenDocument*(controller: DocumentController, document: Document) {.signal.}

  proc didReopenDocument*(controller: DocumentController, document: Document) {.signal.}

  proc didAddDocument*(controller: DocumentController, document: Document) {.signal.}

  proc didRemoveDocument*(controller: DocumentController, document: Document) {.signal.}

  proc didChangeRecentDocuments*(controller: DocumentController) {.signal.}

proc initDocumentController*(controller: DocumentController, app: Application = nil)
proc newDocumentController*(app: Application = nil): DocumentController
proc sharedDocumentController*(): DocumentController
proc setSharedDocumentController*(controller: DocumentController)

proc currentDocument*(controller: DocumentController): Document
proc openPanel*(controller: DocumentController): OpenPanel
proc `openPanel=`*(controller: DocumentController, panel: OpenPanel)
proc savePanel*(controller: DocumentController): SavePanel
proc `savePanel=`*(controller: DocumentController, panel: SavePanel)
proc noteRecentDocumentUrl*(controller: DocumentController, fileUrl: string)
proc createDocumentImpl(
  controller: DocumentController, fileType: string, app: Application
): Document {.discardable.}

proc openDocumentImpl(
  controller: DocumentController, fileUrl, fileType: string, app: Application
): Document {.discardable.}

proc reopenDocumentImpl(
  controller: DocumentController, fileUrl: string, app: Application
): Document {.discardable.}

proc openDocumentWithPanel*(
  controller: DocumentController, panel: OpenPanel = nil, app: Application = nil
): Document {.discardable.}

proc saveDocumentWithPanel*(
  controller: DocumentController,
  document: Document,
  panel: SavePanel = nil,
  app: Application = nil,
): bool {.discardable.}

proc closeDocumentImpl(
  controller: DocumentController, document: Document, reviewUnsaved: bool
): bool {.discardable.}

proc effectiveApplication(
    controller: DocumentController, app: Application
): Application =
  if not app.isNil:
    return app
  if not controller.isNil:
    return controller.xApplication

proc postNotification(
    controller: DocumentController, kind: NotificationKind, document: Document = nil
) =
  if controller.isNil:
    return
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      kind,
      sender = DynamicAgent(controller),
      representedObject = DynamicAgent(document),
      payload =
        if document.isNil:
          initNotificationPayload()
        else:
          initDocumentNotificationPayload(
            fileUrl = document.fileUrl(),
            fileType = document.fileType(),
            displayName = document.displayName(),
            edited = document.isDocumentEdited(),
            closed = document.isClosed(),
          ),
    )
  )

proc defaultType(controller: DocumentController, fileType: string): string =
  if fileType.len > 0:
    return fileType
  if controller.isNil:
    return ""
  controller.trySendLocal(defaultDocumentType(), ()).get("")

proc includeDocument(controller: DocumentController, document: Document) =
  if controller.isNil or document.isNil or document in controller.xDocuments:
    return
  controller.xDocuments.add document
  let forwardedNext = document.nextResponder()
  if forwardedNext != Responder(controller):
    if controller.nextResponder().isNil:
      if not forwardedNext.isNil:
        controller.setNextResponder(forwardedNext)
      elif not controller.xApplication.isNil:
        controller.setNextResponder(controller.xApplication)
    document.setNextResponder(controller)
  emit controller.didAddDocument(document)
  controller.postNotification(nkDocControllerDidAddDocument, document)

proc removeDocumentAt(controller: DocumentController, index: int): Document =
  result = controller.xDocuments[index]
  controller.xDocuments.delete(index)
  if not result.isNil and result.nextResponder() == Responder(controller):
    let next = controller.nextResponder()
    if next.isNil:
      result.clearNextResponder()
    else:
      result.setNextResponder(next)
  emit controller.didRemoveDocument(result)
  controller.postNotification(nkDocControllerDidRemoveDocument, result)

proc trimRecentDocuments(controller: DocumentController) =
  if controller.isNil:
    return
  if controller.xMaximumRecentDocumentCount == 0:
    if controller.xRecentDocumentUrls.len > 0:
      controller.xRecentDocumentUrls.setLen(0)
      emit controller.didChangeRecentDocuments()
      controller.postNotification(nkDocControllerDidChangeRecentDocuments)
    return
  if controller.xRecentDocumentUrls.len > controller.xMaximumRecentDocumentCount:
    controller.xRecentDocumentUrls.setLen(controller.xMaximumRecentDocumentCount)
    emit controller.didChangeRecentDocuments()
    controller.postNotification(nkDocControllerDidChangeRecentDocuments)

proc reviewDocumentForClose(controller: DocumentController, document: Document): bool =
  if controller.isNil or document.isNil or not document.isDocumentEdited():
    return true
  let action =
    controller.trySendLocal(reviewUnsavedDocument(), document).get(dcraCancel)
  case action
  of dcraCancel:
    false
  of dcraSave:
    document.save()
  of dcraDiscardChanges:
    document.documentEdited = false
    true

proc activeDocumentForValidation(controller: DocumentController): Document =
  controller.currentDocument()

protocol DefaultDocumentControllerCreation of DocumentControllerFactory:
  method defaultDocumentType(controller: DocumentController): string =
    ""

  method makeUntitledDocument(
      controller: DocumentController, fileType: string
  ): Document =
    documents.newDocument(fileType = fileType)

  method makeDocumentForFileUrl(
      controller: DocumentController, fileUrl: string, fileType: string
  ): Document =
    documents.newDocument(fileUrl = fileUrl, fileType = fileType)

protocol DefaultDocumentControllerReview of DocumentControllerReview:
  method reviewUnsavedDocument(
      controller: DocumentController, document: Document
  ): DocumentCloseReviewAction =
    dcraCancel

proc documentIndexOfIdentifier(
    controller: DocumentController, identifier: string
): int =
  if controller.isNil or identifier.len == 0:
    return -1
  for index, document in controller.xDocuments:
    if not document.isNil and document.documentIdentifier() == identifier:
      return index
  -1

proc documentTabModelForDocument(document: Document): DocumentTabModel =
  if document.isNil:
    return initDocumentTabModel()
  initDocumentTabModel(
    identifier = document.documentIdentifier(),
    title = document.displayName(),
    objectValue = toObj(DynamicAgent(document)),
    modified = document.isDocumentEdited(),
    closeable = true,
    tooltip = document.fileUrl(),
    representedObject = DynamicAgent(document),
  )

protocol DocumentControllerDocumentTabsDataSource of DocumentTabsDataSource:
  method documentTabCount(controller: DocumentController, tabs: DocumentTabs): int =
    discard tabs
    if controller.isNil: 0 else: controller.xDocuments.len

  method documentTabModelAtIndex(
      controller: DocumentController, tabs: DocumentTabs, index: int
  ): DocumentTabModel =
    discard tabs
    if not controller.isNil and index in 0 ..< controller.xDocuments.len:
      controller.xDocuments[index].documentTabModelForDocument()
    else:
      initDocumentTabModel()

  method indexOfDocumentTabModelIdentifier(
      controller: DocumentController, tabs: DocumentTabs, identifier: string
  ): int =
    controller.documentIndexOfIdentifier(identifier)

protocol DocumentControllerDocumentTabsDelegate of DocumentTabsDelegate:
  method didSelectDocumentTab(
      controller: DocumentController, tabs: DocumentTabs, item: DocumentTabItem
  ) =
    discard tabs
    let represented = item.representedObject()
    if represented of Document:
      discard Document(represented).showWindows(controller.effectiveApplication(nil))

  method shouldCloseDocumentTab(
      controller: DocumentController,
      tabs: DocumentTabs,
      item: DocumentTabItem,
      index: int,
  ): bool =
    discard index
    let represented = item.representedObject()
    if represented of Document:
      let document = Document(represented)
      if not controller.isNil and document in controller.xDocuments:
        if controller.closeDocumentImpl(document, reviewUnsaved = true):
          tabs.reloadData()
        return false
    true

protocol DocumentControllerMenuCommands of MenuCommandProtocol:
  method newDocument(controller: DocumentController, args: ActionArgs) =
    discard controller.createDocumentImpl("", nil)

  method openDocument(controller: DocumentController, args: ActionArgs) =
    if not controller.xOpenPanel.isNil:
      discard controller.openDocumentWithPanel(controller.xOpenPanel, nil)
    else:
      discard controller.reopenDocumentImpl("", nil)

  method saveDocument(controller: DocumentController, args: ActionArgs) =
    let document = controller.currentDocument()
    if not document.isNil:
      if document.fileUrl.len > 0:
        discard document.save()
        if document.fileUrl.len > 0:
          controller.noteRecentDocumentUrl(document.fileUrl)
      else:
        discard controller.saveDocumentWithPanel(document, controller.xSavePanel, nil)

  method saveDocumentAs(controller: DocumentController, args: ActionArgs) =
    let document = controller.currentDocument()
    if not document.isNil:
      if not controller.xSavePanel.isNil:
        discard controller.saveDocumentWithPanel(document, controller.xSavePanel, nil)
      else:
        discard document.save()
        if document.fileUrl.len > 0:
          controller.noteRecentDocumentUrl(document.fileUrl)

  method revertDocumentToSaved(controller: DocumentController, args: ActionArgs) =
    let document = controller.currentDocument()
    if not document.isNil:
      discard document.revert()

  method performClose(controller: DocumentController, args: ActionArgs) =
    discard controller.closeDocumentImpl(controller.currentDocument(), true)

protocol DocumentControllerMenuValidation of UserInterfaceValidations:
  method validateUserInterfaceItem(
      controller: DocumentController, args: ValidationArgs
  ): bool =
    let document = controller.activeDocumentForValidation()
    if args.action.name == "newDocument":
      return true
    if args.action.name == "openDocument":
      return
        not controller.isNil and (
          controller.xRecentDocumentUrls.len > 0 or (
            not controller.xOpenPanel.isNil and controller.xOpenPanel.validateSelection()
          )
        )
    if args.action.name == "saveDocument":
      return
        not document.isNil and (
          document.fileUrl.len > 0 or (
            not controller.xSavePanel.isNil and controller.xSavePanel.validateSelection()
          )
        )
    if args.action.name == "saveDocumentAs":
      return
        not document.isNil and (
          document.fileUrl.len > 0 or (
            not controller.xSavePanel.isNil and controller.xSavePanel.validateSelection()
          )
        )
    if args.action.name == "revertDocumentToSaved":
      return
        not document.isNil and document.fileUrl.len > 0 and document.isDocumentEdited()
    if args.action.name == "performClose":
      return not document.isNil
    else:
      args.action.name.len > 0 and controller.respondsTo(args.action.name)

proc initDocumentController*(controller: DocumentController, app: Application = nil) =
  if controller.isNil:
    return
  initResponder(controller)
  controller.xApplication = app
  controller.xMaximumRecentDocumentCount = DefaultMaximumRecentDocumentCount
  if not app.isNil:
    controller.setNextResponder(app)
  discard controller.withProtocol(DefaultDocumentControllerCreation)
  discard controller.withProtocol(DefaultDocumentControllerReview)
  discard controller.withProtocol(DocumentControllerDocumentTabsDataSource)
  discard controller.withProtocol(DocumentControllerDocumentTabsDelegate)
  discard controller.withProtocol(DocumentControllerMenuCommands)
  discard controller.withProtocol(DocumentControllerMenuValidation)

proc newDocumentController*(app: Application = nil): DocumentController =
  result = DocumentController()
  result.initDocumentController(app)

proc sharedDocumentController*(): DocumentController =
  if sharedDocumentControllerInstance.isNil:
    sharedDocumentControllerInstance = newDocumentController(sharedApplication())
  sharedDocumentControllerInstance

proc setSharedDocumentController*(controller: DocumentController) =
  sharedDocumentControllerInstance = controller

proc application*(controller: DocumentController): Application =
  if controller.isNil: nil else: controller.xApplication

proc `application=`*(controller: DocumentController, app: Application) =
  if controller.isNil:
    return
  controller.xApplication = app
  if not app.isNil and controller.nextResponder().isNil:
    controller.setNextResponder(app)

proc documents*(controller: DocumentController): lent seq[Document] =
  controller.xDocuments

proc documentCount*(controller: DocumentController): int =
  if controller.isNil: 0 else: controller.xDocuments.len

proc contains*(controller: DocumentController, document: Document): bool =
  not controller.isNil and document in controller.xDocuments

proc bindDocumentTabs*(tabs: DocumentTabs, controller: DocumentController) =
  if tabs.isNil:
    return
  tabs.dataSource = controller
  tabs.delegate = controller
  let current = controller.currentDocument()
  if not current.isNil:
    tabs.selectedDocumentTabIdentifier = current.documentIdentifier()
  documenttabs.reloadData(tabs)

proc addDocument*(controller: DocumentController, document: Document) =
  controller.includeDocument(document)
  if not document.isNil and document.fileUrl.len > 0:
    controller.noteRecentDocumentUrl(document.fileUrl)

proc removeDocument*(
    controller: DocumentController, document: Document
): bool {.discardable.} =
  if controller.isNil or document.isNil:
    return false
  let index = controller.xDocuments.find(document)
  if index < 0:
    return false
  discard controller.removeDocumentAt(index)
  true

proc documentForFileUrl*(controller: DocumentController, fileUrl: string): Document =
  if controller.isNil or fileUrl.len == 0:
    return nil
  for document in controller.xDocuments:
    if not document.isNil and document.fileUrl == fileUrl:
      return document

proc documentForWindow*(controller: DocumentController, window: Window): Document =
  if controller.isNil or window.isNil:
    return nil
  for document in controller.xDocuments:
    if not document.isNil:
      for windowController in document.windowControllers():
        if not windowController.isNil and windowController.windowOrNil() == window:
          return document

proc currentDocument*(controller: DocumentController): Document =
  if controller.isNil:
    return nil
  let app = controller.xApplication
  if not app.isNil:
    result = controller.documentForWindow(app.keyWindow())
    if result.isNil:
      result = controller.documentForWindow(app.mainWindow())
    if not result.isNil:
      return
  if controller.xDocuments.len > 0:
    result = controller.xDocuments[^1]

proc openPanel*(controller: DocumentController): OpenPanel =
  if controller.isNil:
    return nil
  if controller.xOpenPanel.isNil:
    controller.xOpenPanel = newOpenPanel()
  controller.xOpenPanel

proc `openPanel=`*(controller: DocumentController, panel: OpenPanel) =
  if not controller.isNil:
    controller.xOpenPanel = panel

proc savePanel*(controller: DocumentController): SavePanel =
  if controller.isNil:
    return nil
  if controller.xSavePanel.isNil:
    controller.xSavePanel = newSavePanel()
  controller.xSavePanel

proc `savePanel=`*(controller: DocumentController, panel: SavePanel) =
  if not controller.isNil:
    controller.xSavePanel = panel

proc recentDocumentUrls*(controller: DocumentController): lent seq[string] =
  controller.xRecentDocumentUrls

proc recentDocumentCount*(controller: DocumentController): int =
  if controller.isNil: 0 else: controller.xRecentDocumentUrls.len

proc maximumRecentDocumentCount*(controller: DocumentController): Natural =
  if controller.isNil: 0 else: controller.xMaximumRecentDocumentCount

proc setMaximumRecentDocumentCount*(controller: DocumentController, count: Natural) =
  if controller.isNil:
    return
  controller.xMaximumRecentDocumentCount = count
  controller.trimRecentDocuments()

proc `maximumRecentDocumentCount=`*(controller: DocumentController, count: Natural) =
  controller.setMaximumRecentDocumentCount(count)

proc noteRecentDocumentUrl*(controller: DocumentController, fileUrl: string) =
  if controller.isNil or fileUrl.len == 0 or controller.xMaximumRecentDocumentCount == 0:
    return
  let existing = controller.xRecentDocumentUrls.find(fileUrl)
  if existing >= 0:
    controller.xRecentDocumentUrls.delete(existing)
  controller.xRecentDocumentUrls.insert(fileUrl, 0)
  controller.trimRecentDocuments()
  emit controller.didChangeRecentDocuments()
  controller.postNotification(nkDocControllerDidChangeRecentDocuments)

proc removeRecentDocumentUrl*(
    controller: DocumentController, fileUrl: string
): bool {.discardable.} =
  if controller.isNil or fileUrl.len == 0:
    return false
  let existing = controller.xRecentDocumentUrls.find(fileUrl)
  if existing < 0:
    return false
  controller.xRecentDocumentUrls.delete(existing)
  emit controller.didChangeRecentDocuments()
  controller.postNotification(nkDocControllerDidChangeRecentDocuments)
  true

proc clearRecentDocuments*(controller: DocumentController) =
  if controller.isNil or controller.xRecentDocumentUrls.len == 0:
    return
  controller.xRecentDocumentUrls.setLen(0)
  emit controller.didChangeRecentDocuments()
  controller.postNotification(nkDocControllerDidChangeRecentDocuments)

proc createDocumentImpl(
    controller: DocumentController, fileType: string, app: Application
): Document {.discardable.} =
  if controller.isNil:
    return nil
  let resolvedType = controller.defaultType(fileType)
  result = controller.trySendLocal(makeUntitledDocument(), resolvedType).get(nil)
  if result.isNil:
    return nil
  if resolvedType.len > 0 and result.fileType.len == 0:
    result.fileType = resolvedType
  controller.addDocument(result)
  discard result.showWindows(controller.effectiveApplication(app))
  result.setNextResponder(controller)
  emit controller.didCreateDocument(result)
  controller.postNotification(nkDocControllerDidCreateDocument, result)

proc openDocumentImpl(
    controller: DocumentController, fileUrl: string, fileType: string, app: Application
): Document {.discardable.} =
  if controller.isNil or fileUrl.len == 0:
    return nil
  result = controller.documentForFileUrl(fileUrl)
  if not result.isNil:
    discard result.showWindows(controller.effectiveApplication(app))
    result.setNextResponder(controller)
    controller.noteRecentDocumentUrl(fileUrl)
    emit controller.didReopenDocument(result)
    controller.postNotification(nkDocControllerDidReopenDocument, result)
    return
  let resolvedType = controller.defaultType(fileType)
  let document = controller
    .trySendLocal(makeDocumentForFileUrl(), (fileUrl: fileUrl, fileType: resolvedType))
    .get(nil)
  if document.isNil or not document.readFromFileUrl(fileUrl, resolvedType):
    return nil
  controller.addDocument(document)
  discard document.showWindows(controller.effectiveApplication(app))
  document.setNextResponder(controller)
  result = document
  emit controller.didOpenDocument(result)
  controller.postNotification(nkDocControllerDidOpenDocument, result)

proc reopenDocumentImpl(
    controller: DocumentController, fileUrl: string, app: Application
): Document {.discardable.} =
  if controller.isNil:
    return nil
  let resolvedUrl =
    if fileUrl.len > 0:
      fileUrl
    elif controller.xRecentDocumentUrls.len > 0:
      controller.xRecentDocumentUrls[0]
    else:
      ""
  if resolvedUrl.len == 0:
    return nil
  result = controller.openDocumentImpl(resolvedUrl, "", app)

proc openDocumentWithPanel*(
    controller: DocumentController, panel: OpenPanel, app: Application
): Document {.discardable.} =
  if controller.isNil:
    return nil
  let resolvedPanel =
    if panel.isNil:
      controller.openPanel()
    else:
      panel
  if resolvedPanel.isNil or not resolvedPanel.validateSelection():
    return nil

  for fileUrl in resolvedPanel.selectedUrls():
    let document = controller.openDocumentImpl(fileUrl, fileUrl.fileTypeForUrl(), app)
    if result.isNil:
      result = document

proc saveDocumentWithPanel*(
    controller: DocumentController,
    document: Document,
    panel: SavePanel,
    app: Application,
): bool {.discardable.} =
  discard app
  if controller.isNil:
    return false
  let target =
    if document.isNil:
      controller.currentDocument()
    else:
      document
  if target.isNil:
    return false

  let resolvedPanel =
    if panel.isNil:
      controller.savePanel()
    else:
      panel
  if resolvedPanel.isNil or not resolvedPanel.validateSelection():
    return false

  let fileUrl = resolvedPanel.selectedUrl()
  result = target.saveAs(fileUrl, resolvedPanel.selectedFileType())
  if result:
    controller.noteRecentDocumentUrl(fileUrl)

proc newDocument*(
    controller: DocumentController, fileType = "", app: Application = nil
): Document {.discardable.} =
  controller.createDocumentImpl(fileType, app)

proc openDocument*(
    controller: DocumentController,
    fileUrl: string,
    fileType = "",
    app: Application = nil,
): Document {.discardable.} =
  controller.openDocumentImpl(fileUrl, fileType, app)

proc reopenDocument*(
    controller: DocumentController, fileUrl = "", app: Application = nil
): Document {.discardable.} =
  controller.reopenDocumentImpl(fileUrl, app)

proc reviewUnsavedDocuments*(controller: DocumentController): bool =
  if controller.isNil:
    return true
  let snapshot = controller.xDocuments
  for document in snapshot:
    if not controller.reviewDocumentForClose(document):
      return false
  true

proc closeDocumentImpl(
    controller: DocumentController, document: Document, reviewUnsaved: bool
): bool {.discardable.} =
  if controller.isNil or document.isNil:
    return true
  if reviewUnsaved and not controller.reviewDocumentForClose(document):
    return false
  result = document.close()
  if result:
    discard controller.removeDocument(document)

proc closeDocument*(
    controller: DocumentController, document: Document, reviewUnsaved = true
): bool {.discardable.} =
  controller.closeDocumentImpl(document, reviewUnsaved)

proc closeAllDocuments*(
    controller: DocumentController, reviewUnsaved = true
): bool {.discardable.} =
  if controller.isNil:
    return true
  if reviewUnsaved and not controller.reviewUnsavedDocuments():
    return false
  let snapshot = controller.xDocuments
  for document in snapshot:
    if not document.isNil:
      if not document.close():
        return false
      discard controller.removeDocument(document)
  true
