import std/[strutils, unittest]

import sigils/core

import merenda/nimkit

type
  WorkspaceProviderSpy = ref object of DynamicAgent
    operationRequests: seq[WorkspaceOperationRequest]
    locationRequests: seq[WorkspaceLocationRequest]
    textRequests: seq[SelectedTextServiceRequest]
    fileRequests: seq[SelectedFilesServiceRequest]
    pasteboardRequests: seq[PasteboardServiceRequest]
    promiseRequests: seq[PromisedFileRequest]
    handoffRequests: seq[FileHandoffRequest]
    recentRequests: seq[RecentDocumentRequest]

  WorkspaceDropDestination = ref object of DynamicAgent
    concluded: int

const TestWorkspaceFeatures = {
  wfOpenUrls, wfOpenFiles, wfRevealFiles, wfLaunchApplications, wfActivateApplications,
  wfSelectedTextServices, wfSelectedFileServices, wfPasteboardServices, wfPromisedFiles,
  wfRecentDocuments, wfFileHandoff,
}

protocol WorkspaceProviderSpyProtocol of WorkspaceProviderProtocol:
  method workspaceFeatures(
      provider: WorkspaceProviderSpy, workspace: Workspace
  ): WorkspaceFeatures =
    TestWorkspaceFeatures

  method workspacePerformOperation(
      provider: WorkspaceProviderSpy, request: WorkspaceOperationRequest
  ): WorkspaceOperationResponse =
    provider.operationRequests.add request
    WorkspaceOperationResponse(handled: true, succeeded: request.target.len > 0)

  method workspaceFindLocation(
      provider: WorkspaceProviderSpy, request: WorkspaceLocationRequest
  ): WorkspaceLocationResponse =
    provider.locationRequests.add request
    if request.location == wslDocuments:
      return WorkspaceLocationResponse(
        handled: true, found: true, path: "/provider/Documents"
      )

  method workspacePerformSelectedTextService(
      provider: WorkspaceProviderSpy, request: SelectedTextServiceRequest
  ): SelectedTextServiceResponse =
    provider.textRequests.add request
    SelectedTextServiceResponse(
      handled: true,
      accepted: true,
      replacementRange: request.range,
      replacement: newTextStorage(request.stringValue.toUpperAscii()),
    )

  method workspacePerformSelectedFilesService(
      provider: WorkspaceProviderSpy, request: SelectedFilesServiceRequest
  ): SelectedFilesServiceResponse =
    provider.fileRequests.add request
    SelectedFilesServiceResponse(
      handled: true, accepted: true, fileUrls: request.fileUrls
    )

  method workspacePerformPasteboardService(
      provider: WorkspaceProviderSpy, request: PasteboardServiceRequest
  ): PasteboardServiceResponse =
    provider.pasteboardRequests.add request
    PasteboardServiceResponse(
      handled: true, accepted: true, providedTypes: request.requestedTypes
    )

  method workspaceCompletePromisedFile(
      provider: WorkspaceProviderSpy, request: PromisedFileRequest
  ): PromisedFileResponse =
    provider.promiseRequests.add request
    PromisedFileResponse(
      handled: true,
      succeeded: true,
      fileUrl: request.destinationUrl & "/" & request.fileName,
    )

  method workspaceHandoffFiles(
      provider: WorkspaceProviderSpy, request: FileHandoffRequest
  ): FileHandoffResponse =
    provider.handoffRequests.add request
    FileHandoffResponse(handled: true, accepted: true, fileUrls: request.fileUrls)

  method workspaceUpdateRecentDocument(
      provider: WorkspaceProviderSpy, request: RecentDocumentRequest
  ): RecentDocumentResponse =
    provider.recentRequests.add request
    RecentDocumentResponse(handled: true, succeeded: true)

protocol WorkspaceDropDestinationProtocol of DraggingDestinationProtocol:
  method prepareForDragOperation(
      destination: WorkspaceDropDestination, info: DraggingInfo
  ): bool =
    true

  method performDragOperation(
      destination: WorkspaceDropDestination, info: DraggingInfo
  ): bool =
    true

  method concludeDragOperation(
      destination: WorkspaceDropDestination, info: DraggingInfo
  ) =
    inc destination.concluded

proc newWorkspaceProviderSpy(): WorkspaceProviderSpy =
  result = WorkspaceProviderSpy()
  discard result.withProtocol(WorkspaceProviderSpyProtocol)

proc newWorkspaceDropDestination(): WorkspaceDropDestination =
  result = WorkspaceDropDestination()
  discard result.withProtocol(WorkspaceDropDestinationProtocol)

suite "NimKit workspace and services":
  test "providerless workspaces expose portable locations and explicit features":
    let workspace = newWorkspace()

    check workspace.supports(wfSystemLocations)
    check not workspace.supports(wfOpenUrls)
    check not workspace.openUrl("https://example.com").supported

    let home = workspace.findLocation(wslHome)
    check home.supported
    check home.handled
    check home.found
    check home.path.len > 0

  test "workspace providers handle operations and override locations":
    let
      provider = newWorkspaceProviderSpy()
      workspace = newWorkspace(DynamicAgent(provider))

    check workspace.supports(wfOpenUrls)
    check workspace.openUrl("https://example.com").succeeded
    check workspace.openFile("/tmp/example.txt").succeeded
    check workspace.revealFile("/tmp/example.txt").succeeded
    discard workspace.launchApplication("com.example.Editor")
    discard workspace.activateApplication("com.example.Editor")

    check provider.operationRequests.len == 5
    check provider.operationRequests[0].kind == wokOpenUrl
    check provider.operationRequests[3].applicationIdentifier == "com.example.Editor"

    let documents = workspace.findLocation(wslDocuments)
    check documents.path == "/provider/Documents"
    check provider.locationRequests.len == 1

  test "selected text files and pasteboards use typed service records":
    let
      provider = newWorkspaceProviderSpy()
      workspace = newWorkspace(DynamicAgent(provider))
      pasteboard = pasteboardWithUniqueName()
      textView = newTextView("service", frame = rect(0, 0, 120, 30))

    textView.selectedRange = initTextRange(0, 7)
    let textResponse = textView.performSelectedTextService(workspace, "uppercase")
    check textResponse.supported
    check textResponse.accepted
    check textView.stringValue == "SERVICE"
    check provider.textRequests.len == 1
    check provider.textRequests[0].serviceIdentifier == "uppercase"

    let files = workspace.performSelectedFilesService(
      SelectedFilesServiceRequest(
        serviceIdentifier: "inspect",
        fileUrls: @["/tmp/one.txt", "/tmp/two.txt"],
        pasteboard: pasteboard,
      )
    )
    check files.accepted
    check files.fileUrls.len == 2
    check provider.fileRequests[0].workspace == workspace

    let pasteboardResponse = workspace.performPasteboardService(
      PasteboardServiceRequest(
        serviceIdentifier: "convert",
        pasteboard: pasteboard,
        requestedTypes: @[PasteboardTypeString],
      )
    )
    check pasteboardResponse.providedTypes == @[PasteboardTypeString]
    check provider.pasteboardRequests[0].pasteboard == pasteboard

  test "document recent changes are mirrored through the application workspace":
    let
      provider = newWorkspaceProviderSpy()
      workspace = newWorkspace(DynamicAgent(provider))
      app = newApplication()
      controller = newDocumentController(app)

    app.workspace = workspace
    controller.noteRecentDocumentUrl("/tmp/recent.txt")
    check controller.removeRecentDocumentUrl("/tmp/recent.txt")
    controller.noteRecentDocumentUrl("/tmp/other.txt")
    controller.clearRecentDocuments()

    check provider.recentRequests.len == 4
    check provider.recentRequests[0].action == rdaNote
    check provider.recentRequests[1].action == rdaRemove
    check provider.recentRequests[3].action == rdaClear

  test "promised files and dropped files hand off through workspace records":
    let
      provider = newWorkspaceProviderSpy()
      workspace = newWorkspace(DynamicAgent(provider))
      destination = newWorkspaceDropDestination()
      promisedSession = beginDraggingSession(
        nil,
        [initPromisedFileDraggingItem("report.txt")],
        {dgoCopy},
        pasteboardWithUniqueName().pasteboardName(),
      )

    check promisedSession.performDraggingOperation(
      DynamicAgent(destination), workspace = workspace, destinationUrl = "/tmp/export"
    )
    check provider.promiseRequests.len == 1
    check provider.promiseRequests[0].fileName == "report.txt"
    check provider.promiseRequests[0].destinationUrl == "/tmp/export"

    let fileSession = beginDraggingSession(
      nil,
      [initDraggingItem(PasteboardTypeFile, initPasteboardFileItem("/tmp/input.txt"))],
      {dgoCopy},
      pasteboardWithUniqueName().pasteboardName(),
    )
    check fileSession.performDraggingOperation(
      DynamicAgent(destination), workspace = workspace
    )
    check provider.handoffRequests.len == 1
    check provider.handoffRequests[0].fileUrls == @["/tmp/input.txt"]
    check provider.handoffRequests[0].destination == DynamicAgent(destination)
    check destination.concluded == 2
