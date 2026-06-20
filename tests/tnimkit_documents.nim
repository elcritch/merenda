import std/unittest

import sigils/core

import merenda/nimkit

type
  FileDocument = ref object of Document
  DocumentDelegateSpy = ref object of Responder

var
  fileEvents: seq[string]
  delegateEvents: seq[string]
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
