import std/strutils

import merenda/nimkit

import sigils/core
import sigils/selectors

type
  DemoDocument = ref object of Document
  DemoDocumentController = ref object of DocumentController

const
  AlertAction = "panelDemoAlert"
  OpenAction = "panelDemoOpen"
  SaveAction = "panelDemoSave"
  ControllerOpenAction = "panelDemoControllerOpen"
  ControllerSaveAction = "panelDemoControllerSave"

var documentEvents: seq[string]

protocol DemoDocumentIO of DocumentFileProtocol:
  method canReadType(document: DemoDocument, fileType: string): bool =
    fileType in ["txt", "md"]

  method canWriteType(document: DemoDocument, fileType: string): bool =
    fileType in ["txt", "md"]

  method readContents(document: DemoDocument, fileUrl: string, fileType: string): bool =
    documentEvents.add "read " & fileUrl & " as " & fileType
    true

  method writeContents(
      document: DemoDocument, fileUrl: string, fileType: string
  ): bool =
    documentEvents.add "write " & fileUrl & " as " & fileType
    true

protocol DemoDocumentWindows of DocumentWindowProtocol:
  method makeWindowControllers(document: DemoDocument): seq[WindowController] =
    @[]

proc newDemoDocument(fileUrl = "", fileType = "txt"): DemoDocument =
  result = DemoDocument()
  result.initDocument(fileUrl = fileUrl, fileType = fileType)
  discard result.withProtocol(DemoDocumentIO)
  discard result.withProtocol(DemoDocumentWindows)

protocol DemoDocumentFactory of DocumentControllerFactory:
  method defaultDocumentType(controller: DemoDocumentController): string =
    "txt"

  method makeUntitledDocument(
      controller: DemoDocumentController, fileType: string
  ): Document =
    let resolvedType = if fileType.len > 0: fileType else: "txt"
    newDemoDocument(fileType = resolvedType)

  method makeDocumentForFileUrl(
      controller: DemoDocumentController, fileUrl: string, fileType: string
  ): Document =
    newDemoDocument(fileUrl = fileUrl, fileType = fileType)

proc newDemoDocumentController(app: Application): DemoDocumentController =
  result = DemoDocumentController()
  result.initDocumentController(app)
  discard result.withProtocol(DemoDocumentFactory)

let
  app = sharedApplication()
  controller = newDemoDocumentController(app)
  window = newWindow("Nimkit Panel Demo", frame = rect(120, 120, 620, 360))
  root = newView()
  layout = newStackView(laVertical)
  directRow = newStackView(laHorizontal)
  documentRow = newStackView(laHorizontal)
  title = newTitleLabel("Panels and Dialogs")
  status = newStatusLabel("Ready")
  documentStatus = newStatusLabel("Document controller ready")
  documentLog = newStatusLabel("No document events yet")
  alertButton = newButton("Alert")
  openButton = newButton("Open Panel")
  saveButton = newButton("Save Panel")
  controllerOpenButton = newButton("Controller Open")
  controllerSaveButton = newButton("Controller Save")

proc updateDocumentLog() =
  if documentEvents.len == 0:
    documentLog.text = "No document events yet"
  else:
    documentLog.text = documentEvents.join(" | ")

proc showAlert(sender: DynamicAgent) =
  discard sender
  let alert = newAlert(
    "Replace existing note?",
    "The first button maps to response 10.",
    asWarning,
    ["Replace", "Cancel"],
  )
  discard alert.setButtonResponse(0, 10)
  discard alert.setButtonResponse(1, PanelResponseCancel)
  alert.setAccessoryView(View(newStatusLabel("Accessory view attached.")))

  let response = app.runModal(alert)
  status.text = "Alert response: " & $response

proc showOpenPanel(sender: DynamicAgent) =
  discard sender
  let panel = newOpenPanel()
  panel.message = "Open a .nim, .md, or .txt URL."
  panel.allowedFileTypes = @["nim", "md", "txt"]
  panel.selectUrl("file:///tmp/panel_demo.nim")
  panel.setAccessoryView(View(newStatusLabel("Try changing the extension.")))

  if app.runModal(panel) == PanelResponseOk:
    status.text = "Open selected: " & panel.selectedUrl()
  else:
    status.text = "Open canceled"

proc showSavePanel(sender: DynamicAgent) =
  discard sender
  let panel = newSavePanel()
  panel.message = "Save as Markdown."
  panel.directoryUrl = "file:///tmp"
  panel.allowedFileTypes = @["md"]
  panel.nameFieldStringValue = "PanelDemo"
  panel.setAccessoryView(View(newStatusLabel("The .md extension is added if omitted.")))

  if app.runModal(panel) == PanelResponseOk:
    status.text = "Save selected: " & panel.selectedUrl()
  else:
    status.text = "Save canceled"

proc openControllerDocument(sender: DynamicAgent) =
  discard sender
  let panel = newOpenPanel()
  panel.message = "Open through DocumentController."
  panel.allowedFileTypes = @["txt", "md"]
  panel.selectUrl("file:///tmp/controller-open.txt")
  controller.openPanel = panel

  if app.runModal(panel) == PanelResponseOk:
    let document = controller.openDocumentWithPanel(panel, app)
    if document.isNil:
      documentStatus.text = "Document open failed"
    else:
      documentStatus.text = "Opened document: " & document.fileUrl
  else:
    documentStatus.text = "Controller open canceled"
  updateDocumentLog()

proc saveControllerDocument(sender: DynamicAgent) =
  discard sender
  let existing = controller.currentDocument()
  let document =
    if existing.isNil:
      controller.newDocument(app = app)
    else:
      existing

  let panel = newSavePanel()
  panel.message = "Save current document through DocumentController."
  panel.directoryUrl = "file:///tmp"
  panel.allowedFileTypes = @["md"]
  panel.nameFieldStringValue = "controller-save"
  controller.savePanel = panel

  if app.runModal(panel) == PanelResponseOk and
      controller.saveDocumentWithPanel(document, panel, app):
    documentStatus.text = "Saved document: " & document.fileUrl
  else:
    documentStatus.text = "Controller save canceled"
  updateDocumentLog()

alertButton.target = newActionTarget(actionSelector(AlertAction), showAlert)
alertButton.action = actionSelector(AlertAction)
openButton.target = newActionTarget(actionSelector(OpenAction), showOpenPanel)
openButton.action = actionSelector(OpenAction)
saveButton.target = newActionTarget(actionSelector(SaveAction), showSavePanel)
saveButton.action = actionSelector(SaveAction)
controllerOpenButton.target =
  newActionTarget(actionSelector(ControllerOpenAction), openControllerDocument)
controllerOpenButton.action = actionSelector(ControllerOpenAction)
controllerSaveButton.target =
  newActionTarget(actionSelector(ControllerSaveAction), saveControllerDocument)
controllerSaveButton.action = actionSelector(ControllerSaveAction)

directRow.spacing = 8.0
directRow.alignment = svaFill
directRow.distribution = svdFillEqually
directRow.addArrangedSubview(alertButton, openButton, saveButton)

documentRow.spacing = 8.0
documentRow.alignment = svaFill
documentRow.distribution = svdFillEqually
documentRow.addArrangedSubview(controllerOpenButton, controllerSaveButton)

layout.spacing = 12.0
layout.alignment = svaFill
layout.addArrangedSubview(
  title,
  status,
  directRow,
  newHeadingLabel("Document Controller"),
  documentStatus,
  documentRow,
  documentLog,
)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

app.runWindow(window, root)
