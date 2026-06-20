import std/unittest

import sigils/core

import merenda/nimkit

type
  FileDocument = ref object of Document
  FileDocumentController = ref object of DocumentController
  DocumentDelegateSpy = ref object of Responder

var
  fileEvents: seq[string]
  delegateEvents: seq[string]
  reviewActions: seq[DocumentCloseReviewAction]
  allowDocumentClose: bool

protocol FileDocumentProtocol of DocumentFileProtocol:
  method canReadType(document: FileDocument, fileType: string): bool =
    fileType in ["txt", "md"]

  method canWriteType(document: FileDocument, fileType: string): bool =
    fileType in ["txt", "md"]

  method readContents(document: FileDocument, fileUrl: string, fileType: string): bool =
    fileEvents.add "read:" & fileUrl & ":" & fileType
    true

  method writeContents(
      document: FileDocument, fileUrl: string, fileType: string
  ): bool =
    fileEvents.add "write:" & fileUrl & ":" & fileType
    true

protocol DocumentDelegateSpyProtocol of DocumentDelegate:
  method documentWillSave(delegate: DocumentDelegateSpy, document: Document) =
    delegateEvents.add "willSave"

  method documentDidSave(delegate: DocumentDelegateSpy, document: Document) =
    delegateEvents.add "didSave"

  method documentWillRevert(delegate: DocumentDelegateSpy, document: Document) =
    delegateEvents.add "willRevert"

  method documentDidRevert(delegate: DocumentDelegateSpy, document: Document) =
    delegateEvents.add "didRevert"

  method documentShouldClose(delegate: DocumentDelegateSpy, document: Document): bool =
    delegateEvents.add "shouldClose"
    allowDocumentClose

  method documentWillClose(delegate: DocumentDelegateSpy, document: Document) =
    delegateEvents.add "willClose"

  method documentDidClose(delegate: DocumentDelegateSpy, document: Document) =
    delegateEvents.add "didClose"

  method documentDidChangeName(delegate: DocumentDelegateSpy, document: Document) =
    delegateEvents.add "name"

  method documentDidChangeEdited(delegate: DocumentDelegateSpy, document: Document) =
    delegateEvents.add "edited"

protocol FileDocumentControllerCreation of DocumentControllerFactory:
  method defaultDocumentType(controller: FileDocumentController): string =
    "txt"

  method makeUntitledDocument(
      controller: FileDocumentController, fileType: string
  ): Document =
    result = FileDocument()
    FileDocument(result).initDocument(fileType = fileType)
    discard FileDocument(result).withProtocol(FileDocumentProtocol)

  method makeDocumentForFileUrl(
      controller: FileDocumentController, fileUrl: string, fileType: string
  ): Document =
    result = FileDocument()
    FileDocument(result).initDocument(fileUrl = fileUrl, fileType = fileType)
    discard FileDocument(result).withProtocol(FileDocumentProtocol)

protocol FileDocumentControllerReview of DocumentControllerReview:
  method reviewUnsavedDocument(
      controller: FileDocumentController, document: Document
  ): DocumentCloseReviewAction =
    result = reviewActions[0]
    reviewActions.delete(0)

suite "nimkit documents":
  test "document metadata synchronizes window controller display names":
    let
      app = newApplication()
      document = newDocument("file:///tmp/Spec.nim")
      controller =
        newWindowController(newWindow("Raw", frame = initRect(0, 0, 240, 160)))

    document.setNextResponder(app)
    check document.fileUrl == "file:///tmp/Spec.nim"
    check document.fileName == "Spec.nim"
    check document.fileType == "nim"
    check document.displayName == "Spec.nim"

    document.addWindowController(controller)
    check document.windowControllerCount == 1
    check controller.documentDisplayName == "Spec.nim"
    check controller.nextResponder() == Responder(document)

    document.displayName = "Custom Title"
    check document.displayName == "Custom Title"
    check controller.documentDisplayName == "Custom Title"

    document.clearDisplayName()
    check document.displayName == "Spec.nim"
    check controller.documentDisplayName == "Spec.nim"

    document.fileUrl = "file:///tmp/Renamed.nim"
    check document.fileName == "Renamed.nim"
    check document.displayName == "Renamed.nim"
    check controller.documentDisplayName == "Renamed.nim"

    check document.removeWindowController(controller)
    check controller.nextResponder() == Responder(app)

  test "document creates and shows window controllers through the responder chain":
    let
      app = newApplication()
      document = newDocument()

    let windows = document.showWindows(app)

    check windows.len == 1
    check document.windowControllerCount == 1
    let controller = document.windowControllers()[0]
    check windows[0].nextResponder() == Responder(controller)
    check controller.nextResponder() == Responder(document)
    check document.nextResponder() == Responder(app)
    check app.keyWindow == windows[0]

  test "document file hooks drive read save save-as revert and undo lookup":
    let
      document = FileDocument()
      manager = newResponder()
      delegate = DocumentDelegateSpy()

    fileEvents = @[]
    delegateEvents = @[]
    document.initDocument()
    discard document.withProtocol(FileDocumentProtocol)
    discard delegate.withProtocol(DocumentDelegateSpyProtocol)
    document.delegate = delegate
    document.undoManager = manager

    check document.findUndoManager() == DynamicAgent(manager)
    check document.readFromFileUrl("file:///tmp/Read.txt", "txt")
    check document.fileUrl == "file:///tmp/Read.txt"
    check document.fileName == "Read.txt"
    check document.fileType == "txt"
    check fileEvents == @["read:file:///tmp/Read.txt:txt"]

    document.documentEdited = true
    check document.isDocumentEdited
    check document.save()
    check not document.isDocumentEdited
    check fileEvents[^1] == "write:file:///tmp/Read.txt:txt"
    check "willSave" in delegateEvents
    check delegateEvents[^1] == "didSave"

    document.documentEdited = true
    check document.saveAs("file:///tmp/Saved.md", "md")
    check document.fileUrl == "file:///tmp/Saved.md"
    check document.fileName == "Saved.md"
    check document.fileType == "md"
    check not document.isDocumentEdited
    check fileEvents[^1] == "write:file:///tmp/Saved.md:md"

    document.documentEdited = true
    check document.revert()
    check not document.isDocumentEdited
    check fileEvents[^1] == "read:file:///tmp/Saved.md:md"
    check "willRevert" in delegateEvents
    check delegateEvents[^1] == "didRevert"

    check not document.writeToFileUrl("file:///tmp/Bad.bin", "bin")
    check document.tryToPerform(saveDocument(), DynamicAgent(document))
    check fileEvents[^1] == "write:file:///tmp/Saved.md:md"

  test "document close lifecycle delegates and closes owned windows":
    let
      document = newDocument()
      delegate = DocumentDelegateSpy()
      firstWindow = newWindow("One", frame = initRect(0, 0, 240, 160))
      secondWindow = newWindow("Two", frame = initRect(20, 20, 240, 160))

    delegateEvents = @[]
    allowDocumentClose = false
    discard delegate.withProtocol(DocumentDelegateSpyProtocol)
    document.delegate = delegate
    document.addWindowController(newWindowController(firstWindow))
    document.addWindowController(newWindowController(secondWindow))

    check not document.close()
    check not document.isClosed
    check not firstWindow.isClosed
    check delegateEvents == @["shouldClose"]

    allowDocumentClose = true
    check document.close()
    check document.isClosed
    check firstWindow.isClosed
    check secondWindow.isClosed
    check delegateEvents == @["shouldClose", "shouldClose", "willClose", "didClose"]

  test "document controller creates opens reopens and finds documents":
    let
      app = newApplication()
      controller = FileDocumentController()

    fileEvents = @[]
    controller.initDocumentController(app)
    discard controller.withProtocol(FileDocumentControllerCreation)
    check controller.application == app
    check controller.nextResponder() == Responder(app)

    let created = controller.newDocument(app = app)
    check created of FileDocument
    check created.fileType == "txt"
    check controller.documentCount == 1
    check controller.contains(created)
    check created.nextResponder() == Responder(controller)
    check app.keyWindow == created.windowControllers()[0].windowOrNil()
    check controller.currentDocument() == created

    let opened = controller.openDocument("file:///tmp/Open.txt", app = app)
    check opened of FileDocument
    check opened.fileUrl == "file:///tmp/Open.txt"
    check opened.fileName == "Open.txt"
    check fileEvents == @["read:file:///tmp/Open.txt:txt"]
    check controller.documentCount == 2
    check controller.documentForFileUrl("file:///tmp/Open.txt") == opened
    check controller.documentForWindow(app.keyWindow) == opened
    check controller.currentDocument() == opened
    check controller.recentDocumentUrls() == @["file:///tmp/Open.txt"]

    let reopened = controller.openDocument("file:///tmp/Open.txt", app = app)
    check reopened == opened
    check fileEvents == @["read:file:///tmp/Open.txt:txt"]
    check controller.reopenDocument(app = app) == opened

    controller.noteRecentDocumentUrl("file:///tmp/Second.txt")
    controller.maximumRecentDocumentCount = 1
    check controller.recentDocumentUrls() == @["file:///tmp/Second.txt"]
    check controller.removeRecentDocumentUrl("file:///tmp/Second.txt")
    check controller.recentDocumentCount == 0

  test "document controller reviews unsaved documents before close all":
    let
      app = newApplication()
      controller = FileDocumentController()

    fileEvents = @[]
    reviewActions = @[]
    controller.initDocumentController(app)
    discard controller.withProtocol(FileDocumentControllerCreation)
    discard controller.withProtocol(FileDocumentControllerReview)

    let
      saved = controller.openDocument("file:///tmp/Saved.txt", app = app)
      discardOnly = controller.newDocument(app = app)
      cancel = controller.newDocument(app = app)

    saved.documentEdited = true
    discardOnly.documentEdited = true
    cancel.documentEdited = true
    reviewActions = @[dcraSave, dcraDiscardChanges, dcraCancel]

    check not controller.closeAllDocuments()
    check controller.documentCount == 3
    check not saved.isDocumentEdited
    check not discardOnly.isDocumentEdited
    check cancel.isDocumentEdited
    check fileEvents[^1] == "write:file:///tmp/Saved.txt:txt"

    reviewActions = @[dcraDiscardChanges]
    check controller.closeAllDocuments()
    check controller.documentCount == 0
    check saved.isClosed
    check discardOnly.isClosed
    check cancel.isClosed

  test "document controller menu commands validate against the current document":
    let
      app = newApplication()
      controller = FileDocumentController()
      saveItem = newMenuItem("Save", actionSelector("saveDocument"))
      revertItem = newMenuItem("Revert", actionSelector("revertDocumentToSaved"))
      closeItem = newMenuItem("Close", actionSelector("performClose"))
      openItem = newMenuItem("Open", actionSelector("openDocument"))
      newItem = newMenuItem("New", actionSelector("newDocument"))

    fileEvents = @[]
    reviewActions = @[]
    controller.initDocumentController(app)
    discard controller.withProtocol(FileDocumentControllerCreation)
    discard controller.withProtocol(FileDocumentControllerReview)

    check newItem.validate(Responder(controller))
    check not saveItem.validate(Responder(controller))
    check not openItem.validate(Responder(controller))

    let document = controller.openDocument("file:///tmp/Menu.txt", app = app)
    document.documentEdited = true
    check saveItem.validate(Responder(controller))
    check revertItem.validate(Responder(controller))
    check closeItem.validate(Responder(controller))
    check openItem.validate(Responder(controller))

    check saveItem.perform(Responder(controller))
    check fileEvents[^1] == "write:file:///tmp/Menu.txt:txt"
    check not revertItem.validate(Responder(controller))

    check newItem.perform(Responder(controller))
    check controller.documentCount == 2

    let current = controller.currentDocument()
    current.documentEdited = true
    reviewActions = @[dcraDiscardChanges]
    check closeItem.perform(Responder(controller))
    check current.isClosed
    check controller.documentCount == 1
