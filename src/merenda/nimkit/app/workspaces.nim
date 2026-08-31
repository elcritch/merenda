import std/[options, os]

import sigils/selectors

import ../foundation/urls
import ../text/textstorage
import ../text/texttypes
import ./pasteboards

type
  WorkspaceFeature* = enum
    wfOpenUrls
    wfOpenFiles
    wfRevealFiles
    wfLaunchApplications
    wfActivateApplications
    wfSystemLocations
    wfSelectedTextServices
    wfSelectedFileServices
    wfPasteboardServices
    wfPromisedFiles
    wfRecentDocuments
    wfFileHandoff

  WorkspaceFeatures* = set[WorkspaceFeature]

  WorkspaceOperationKind* = enum
    wokOpenUrl
    wokOpenFile
    wokRevealFile
    wokLaunchApplication
    wokActivateApplication

  WorkspaceSystemLocation* = enum
    wslHome
    wslDesktop
    wslDocuments
    wslDownloads
    wslApplications
    wslApplicationData
    wslCaches
    wslConfiguration
    wslTemporary

  RecentDocumentAction* = enum
    rdaNote
    rdaRemove
    rdaClear

  Workspace* = ref object
    xProvider: DynamicAgent
    xDeclaredFeatures: WorkspaceFeatures

  WorkspaceOperationRequest* = object
    workspace*: Workspace
    kind*: WorkspaceOperationKind
    target*: string
    applicationIdentifier*: string

  WorkspaceOperationResponse* = object
    supported*: bool
    handled*: bool
    succeeded*: bool
    message*: string

  WorkspaceLocationRequest* = object
    workspace*: Workspace
    location*: WorkspaceSystemLocation

  WorkspaceLocationResponse* = object
    supported*: bool
    handled*: bool
    found*: bool
    path*: string
    message*: string

  SelectedTextServiceRequest* = object
    workspace*: Workspace
    serviceIdentifier*: string
    range*: TextRange
    selectedRanges*: seq[TextRange]
    stringValue*: string
    attributedString*: TextStorage
    pasteboard*: Pasteboard

  SelectedTextServiceResponse* = object
    supported*: bool
    handled*: bool
    accepted*: bool
    replacementRange*: TextRange
    replacement*: TextStorage
    message*: string

  SelectedFilesServiceRequest* = object
    workspace*: Workspace
    serviceIdentifier*: string
    fileUrls*: seq[string]
    pasteboard*: Pasteboard

  SelectedFilesServiceResponse* = object
    supported*: bool
    handled*: bool
    accepted*: bool
    fileUrls*: seq[string]
    message*: string

  PasteboardServiceRequest* = object
    workspace*: Workspace
    serviceIdentifier*: string
    pasteboard*: Pasteboard
    requestedTypes*: seq[string]

  PasteboardServiceResponse* = object
    supported*: bool
    handled*: bool
    accepted*: bool
    providedTypes*: seq[string]
    message*: string

  PromisedFileRequest* = object
    workspace*: Workspace
    fileName*: string
    destinationUrl*: string
    pasteboard*: Pasteboard
    pasteboardType*: string
    item*: PasteboardItem

  PromisedFileResponse* = object
    supported*: bool
    handled*: bool
    succeeded*: bool
    fileUrl*: string
    message*: string

  FileHandoffRequest* = object
    workspace*: Workspace
    fileUrls*: seq[string]
    pasteboard*: Pasteboard
    destination*: DynamicAgent
    destinationUrl*: string

  FileHandoffResponse* = object
    supported*: bool
    handled*: bool
    accepted*: bool
    fileUrls*: seq[string]
    message*: string

  RecentDocumentRequest* = object
    workspace*: Workspace
    action*: RecentDocumentAction
    fileUrl*: string

  RecentDocumentResponse* = object
    supported*: bool
    handled*: bool
    succeeded*: bool
    message*: string

protocol WorkspaceProviderProtocol:
  method workspaceFeatures*(workspace: Workspace): WorkspaceFeatures {.optional.}
  method workspacePerformOperation*(
    request: WorkspaceOperationRequest
  ): WorkspaceOperationResponse {.optional.}

  method workspaceFindLocation*(
    request: WorkspaceLocationRequest
  ): WorkspaceLocationResponse {.optional.}

  method workspacePerformSelectedTextService*(
    request: SelectedTextServiceRequest
  ): SelectedTextServiceResponse {.optional.}

  method workspacePerformSelectedFilesService*(
    request: SelectedFilesServiceRequest
  ): SelectedFilesServiceResponse {.optional.}

  method workspacePerformPasteboardService*(
    request: PasteboardServiceRequest
  ): PasteboardServiceResponse {.optional.}

  method workspaceCompletePromisedFile*(
    request: PromisedFileRequest
  ): PromisedFileResponse {.optional.}

  method workspaceHandoffFiles*(
    request: FileHandoffRequest
  ): FileHandoffResponse {.optional.}

  method workspaceUpdateRecentDocument*(
    request: RecentDocumentRequest
  ): RecentDocumentResponse {.optional.}

const PortableWorkspaceFeatures* = {wfSystemLocations}

proc newWorkspace*(
    provider: DynamicAgent = nil, declaredFeatures: WorkspaceFeatures = {}
): Workspace =
  Workspace(xProvider: provider, xDeclaredFeatures: declaredFeatures)

proc provider*(workspace: Workspace): DynamicAgent =
  if workspace.isNil:
    return nil
  workspace.xProvider

proc setProvider*(
    workspace: Workspace,
    provider: DynamicAgent,
    declaredFeatures: WorkspaceFeatures = {},
) =
  if workspace.isNil:
    return
  workspace.xProvider = provider
  workspace.xDeclaredFeatures = declaredFeatures

proc declaredFeatures*(workspace: Workspace): WorkspaceFeatures =
  if workspace.isNil:
    return PortableWorkspaceFeatures
  workspace.xDeclaredFeatures + PortableWorkspaceFeatures

proc features*(workspace: Workspace): WorkspaceFeatures =
  result = workspace.declaredFeatures()
  if workspace.isNil or workspace.xProvider.isNil:
    return
  result =
    result + workspace.xProvider.trySendLocal(workspaceFeatures(), workspace).get({})

proc supports*(workspace: Workspace, feature: WorkspaceFeature): bool =
  feature in workspace.features()

proc featureForOperation(kind: WorkspaceOperationKind): WorkspaceFeature =
  case kind
  of wokOpenUrl: wfOpenUrls
  of wokOpenFile: wfOpenFiles
  of wokRevealFile: wfRevealFiles
  of wokLaunchApplication: wfLaunchApplications
  of wokActivateApplication: wfActivateApplications

proc perform*(
    workspace: Workspace, request: WorkspaceOperationRequest
): WorkspaceOperationResponse =
  var routedRequest = request
  routedRequest.workspace = workspace
  let feature = featureForOperation(routedRequest.kind)
  if not workspace.supports(feature):
    return
  result.supported = true
  if workspace.isNil or workspace.xProvider.isNil:
    return
  let response =
    workspace.xProvider.trySendLocal(workspacePerformOperation(), routedRequest)
  if response.isSome:
    result = response.get()
    result.supported = true

proc performOperation(
    workspace: Workspace,
    kind: WorkspaceOperationKind,
    target: string,
    applicationIdentifier = "",
): WorkspaceOperationResponse =
  workspace.perform(
    WorkspaceOperationRequest(
      workspace: workspace,
      kind: kind,
      target: target,
      applicationIdentifier: applicationIdentifier,
    )
  )

proc openUrl*(workspace: Workspace, url: string): WorkspaceOperationResponse =
  workspace.performOperation(wokOpenUrl, url)

proc openUrl*(workspace: Workspace, url: Url): WorkspaceOperationResponse =
  ## Ask the platform workspace to open a parsed Foundation URL.
  workspace.openUrl(url.absoluteString())

proc openFile*(
    workspace: Workspace, fileUrl: string, applicationIdentifier = ""
): WorkspaceOperationResponse =
  workspace.performOperation(wokOpenFile, fileUrl, applicationIdentifier)

proc openFile*(
    workspace: Workspace, fileUrl: Url, applicationIdentifier = ""
): WorkspaceOperationResponse =
  ## Ask the platform workspace to open a parsed Foundation file URL.
  workspace.openFile(fileUrl.absoluteString(), applicationIdentifier)

proc revealFile*(workspace: Workspace, fileUrl: string): WorkspaceOperationResponse =
  workspace.performOperation(wokRevealFile, fileUrl)

proc revealFile*(workspace: Workspace, fileUrl: Url): WorkspaceOperationResponse =
  ## Ask the platform workspace to reveal a parsed Foundation file URL.
  workspace.revealFile(fileUrl.absoluteString())

proc launchApplication*(
    workspace: Workspace, applicationIdentifier: string
): WorkspaceOperationResponse =
  workspace.performOperation(wokLaunchApplication, "", applicationIdentifier)

proc activateApplication*(
    workspace: Workspace, applicationIdentifier: string
): WorkspaceOperationResponse =
  workspace.performOperation(wokActivateApplication, "", applicationIdentifier)

proc portableLocation(location: WorkspaceSystemLocation): string =
  case location
  of wslHome:
    getHomeDir()
  of wslDesktop:
    getHomeDir() / "Desktop"
  of wslDocuments:
    getHomeDir() / "Documents"
  of wslDownloads:
    getHomeDir() / "Downloads"
  of wslApplications:
    when defined(macosx): "/Applications" else: ""
  of wslApplicationData:
    getDataDir()
  of wslCaches:
    getCacheDir()
  of wslConfiguration:
    getConfigDir()
  of wslTemporary:
    getTempDir()

proc findLocation*(
    workspace: Workspace, location: WorkspaceSystemLocation
): WorkspaceLocationResponse =
  if not workspace.supports(wfSystemLocations):
    return
  result.supported = true
  if not workspace.isNil and not workspace.xProvider.isNil:
    let response = workspace.xProvider.trySendLocal(
      workspaceFindLocation(),
      WorkspaceLocationRequest(workspace: workspace, location: location),
    )
    if response.isSome:
      result = response.get()
      result.supported = true
      if result.handled:
        return
  result.handled = true
  result.path = portableLocation(location)
  result.found = result.path.len > 0

proc performSelectedTextService*(
    workspace: Workspace, request: SelectedTextServiceRequest
): SelectedTextServiceResponse =
  if not workspace.supports(wfSelectedTextServices):
    return
  result.supported = true
  if workspace.isNil or workspace.xProvider.isNil:
    return
  var routedRequest = request
  routedRequest.workspace = workspace
  let response = workspace.xProvider.trySendLocal(
    workspacePerformSelectedTextService(), routedRequest
  )
  if response.isSome:
    result = response.get()
    result.supported = true

proc performSelectedFilesService*(
    workspace: Workspace, request: SelectedFilesServiceRequest
): SelectedFilesServiceResponse =
  if not workspace.supports(wfSelectedFileServices):
    return
  result.supported = true
  if workspace.isNil or workspace.xProvider.isNil:
    return
  var routedRequest = request
  routedRequest.workspace = workspace
  let response = workspace.xProvider.trySendLocal(
    workspacePerformSelectedFilesService(), routedRequest
  )
  if response.isSome:
    result = response.get()
    result.supported = true

proc performPasteboardService*(
    workspace: Workspace, request: PasteboardServiceRequest
): PasteboardServiceResponse =
  if not workspace.supports(wfPasteboardServices):
    return
  result.supported = true
  if workspace.isNil or workspace.xProvider.isNil:
    return
  var routedRequest = request
  routedRequest.workspace = workspace
  let response =
    workspace.xProvider.trySendLocal(workspacePerformPasteboardService(), routedRequest)
  if response.isSome:
    result = response.get()
    result.supported = true

proc completePromisedFile*(
    workspace: Workspace, request: PromisedFileRequest
): PromisedFileResponse =
  if not workspace.supports(wfPromisedFiles):
    return
  result.supported = true
  if workspace.isNil or workspace.xProvider.isNil:
    return
  var routedRequest = request
  routedRequest.workspace = workspace
  let response =
    workspace.xProvider.trySendLocal(workspaceCompletePromisedFile(), routedRequest)
  if response.isSome:
    result = response.get()
    result.supported = true

proc handoffFiles*(
    workspace: Workspace, request: FileHandoffRequest
): FileHandoffResponse =
  if not workspace.supports(wfFileHandoff):
    return
  result.supported = true
  if workspace.isNil or workspace.xProvider.isNil:
    return
  var routedRequest = request
  routedRequest.workspace = workspace
  let response =
    workspace.xProvider.trySendLocal(workspaceHandoffFiles(), routedRequest)
  if response.isSome:
    result = response.get()
    result.supported = true

proc updateRecentDocument*(
    workspace: Workspace, request: RecentDocumentRequest
): RecentDocumentResponse =
  if not workspace.supports(wfRecentDocuments):
    return
  result.supported = true
  if workspace.isNil or workspace.xProvider.isNil:
    return
  var routedRequest = request
  routedRequest.workspace = workspace
  let response =
    workspace.xProvider.trySendLocal(workspaceUpdateRecentDocument(), routedRequest)
  if response.isSome:
    result = response.get()
    result.supported = true

proc updateRecentDocument*(
    workspace: Workspace, action: RecentDocumentAction, fileUrl = ""
): RecentDocumentResponse =
  workspace.updateRecentDocument(
    RecentDocumentRequest(workspace: workspace, action: action, fileUrl: fileUrl)
  )
