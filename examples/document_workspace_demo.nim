import std/[algorithm, strutils]

import merenda/nimkit

import sigils/core
import sigils/selectors

type
  FeatureRow = object
    name: string
    layer: string
    status: string
    note: string

  FeatureDocument = ref object of Document
    rows: seq[FeatureRow]
    table: TableView
    editor: TextView
    subtitle: Label
    activity: Label
    pasteboardInfo: Label
    accessibilityInfo: Label

  FeatureDocumentController = ref object of DocumentController
    sampleIndex: int

const
  DemoDocumentType = "nimkit-feature-workspace"
  NewDocumentAction = "demoNewDocument"
  OpenSampleAction = "demoOpenSample"
  ReopenRecentAction = "demoReopenRecent"
  SaveAction = "saveDocument"
  RevertAction = "revertDocumentToSaved"
  CloseAction = "performClose"
  CloseAllAction = "demoCloseAll"
  MarkEditedAction = "demoMarkEdited"
  CopySummaryAction = "demoCopySummary"
  BeginDragAction = "demoBeginDrag"
  ShowAccessibilityAction = "demoShowAccessibility"

let sampleUrls =
  @[
    "file:///tmp/nimkit-documents.workspace", "file:///tmp/nimkit-dragging.workspace",
    "file:///tmp/nimkit-accessibility.workspace",
  ]

proc seedRows(kind: string): seq[FeatureRow] =
  case kind
  of "dragging":
    @[
      FeatureRow(
        name: "Typed pasteboard payloads",
        layer: "Pasteboard",
        status: "Bridged",
        note: "Strings, URLs, files, images, colors, fonts, and data items",
      ),
      FeatureRow(
        name: "Table drag sessions",
        layer: "Dragging",
        status: "Active",
        note: "Rows and columns produce DraggingSession and DraggingInfo payloads",
      ),
      FeatureRow(
        name: "Visible drop targets",
        layer: "Containers",
        status: "Rendered",
        note: "List, table, and outline destinations keep row/cell target state",
      ),
      FeatureRow(
        name: "Promised files",
        layer: "Backend",
        status: "Staged",
        note: "Native sessions can request promised-file materialization",
      ),
    ]
  of "accessibility":
    @[
      FeatureRow(
        name: "Semantic roles",
        layer: "Accessibility",
        status: "Covered",
        note: "Views, controls, menus, lists, tables, and outlines expose roles",
      ),
      FeatureRow(
        name: "Value notifications",
        layer: "Accessibility",
        status: "Wired",
        note: "Widget mutation routes through accessibility notifications",
      ),
      FeatureRow(
        name: "Action dispatch",
        layer: "Accessibility",
        status: "Usable",
        note: "Buttons, popups, tabs, rows, and disclosure controls expose actions",
      ),
      FeatureRow(
        name: "Flattened children",
        layer: "Accessibility",
        status: "Neutral",
        note: "Ignored containers flatten into semantic descendants",
      ),
    ]
  else:
    @[
      FeatureRow(
        name: "DocumentController",
        layer: "Documents",
        status: "New",
        note: "Shared controller, recents, lookup, review, and menu validation",
      ),
      FeatureRow(
        name: "Document",
        layer: "Documents",
        status: "New",
        note: "File metadata, edited state, explicit read/write hooks, lifecycle",
      ),
      FeatureRow(
        name: "WindowController",
        layer: "Windows",
        status: "Recent",
        note: "Lazy loading, title sync, close/show lifecycle, delegate bridge",
      ),
      FeatureRow(
        name: "Menu validation",
        layer: "Application",
        status: "Recent",
        note: "Responder-chain commands validate through protocol-backed items",
      ),
    ]

proc seedKeyForUrl(fileUrl: string): string =
  if fileUrl.contains("dragging"):
    "dragging"
  elif fileUrl.contains("accessibility"):
    "accessibility"
  else:
    "documents"

proc sampleDisplayName(fileUrl: string): string =
  case fileUrl.seedKeyForUrl()
  of "dragging": "Dragging.workspace"
  of "accessibility": "Accessibility.workspace"
  else: "Documents.workspace"

proc documentSubtitle(document: FeatureDocument): string =
  let kind = if document.fileUrl.len > 0: "Opened document" else: "Untitled document"
  let location = if document.fileUrl.len > 0: document.fileUrl else: "not saved yet"
  kind & " / type: " & document.fileType() & " / " & location

proc rowAt(document: FeatureDocument, row: int): FeatureRow =
  if row in 0 ..< document.rows.len:
    document.rows[row]
  else:
    FeatureRow()

proc fieldText(row: FeatureRow, column: TableColumn): string =
  if column.isNil:
    return ""
  case column.identifier
  of "name": row.name
  of "layer": row.layer
  of "status": row.status
  of "note": row.note
  else: ""

proc summary(document: FeatureDocument): string =
  var lines = @[document.displayName() & " (" & $document.rows.len & " features)"]
  for row in document.rows:
    lines.add "- " & row.layer & ": " & row.name & " [" & row.status & "]"
  lines.join("\n")

proc documentText(document: FeatureDocument): string =
  var lines =
    @[
      document.displayName(),
      document.documentSubtitle(),
      "",
      "This editable sample document was opened through DocumentController.",
      "The content is generated by the Nim-side read hook for the sample URL.",
      "",
    ]
  for row in document.rows:
    lines.add row.name
    lines.add "Layer: " & row.layer & "    Status: " & row.status
    lines.add row.note
    lines.add ""
  lines.join("\n")

proc updateActivity(document: FeatureDocument, message: string) =
  if document.isNil or document.activity.isNil:
    return
  if not document.subtitle.isNil:
    document.subtitle.text = document.documentSubtitle()
  document.activity.text =
    message & "\nName: " & document.displayName() & "\nEdited: " &
    $document.isDocumentEdited() & "\nFile: " &
    (if document.fileUrl.len > 0: document.fileUrl else: "untitled")

proc updatePasteboardInfo(document: FeatureDocument) =
  if document.isNil or document.pasteboardInfo.isNil:
    return
  let pasteboard = generalPasteboard()
  document.pasteboardInfo.text =
    "Pasteboard change count: " & $pasteboard.changeCount() & "\nTypes: " &
    pasteboard.types().join(", ")

proc updateAccessibilityInfo(document: FeatureDocument) =
  if document.isNil or document.accessibilityInfo.isNil or document.table.isNil:
    return
  document.accessibilityInfo.text =
    "Table role: " & $document.table.accessibilityRole() & "\nValue: " &
    document.table.accessibilityValue()

proc reloadFeatureTable(document: FeatureDocument) =
  if document.isNil or document.table.isNil:
    return
  ListView(document.table).reloadData()
  document.updateAccessibilityInfo()

proc sortRows(
    document: FeatureDocument, column: TableColumn, direction: TableSortDirection
) =
  if column.isNil or direction == tsdNone:
    return
  let identifier = column.identifier
  document.rows.sort(
    proc(left, right: FeatureRow): int =
      let
        leftValue = left.fieldText(column)
        rightValue = right.fieldText(column)
      result = cmp(leftValue, rightValue)
      if direction == tsdDescending:
        result = -result
  )
  document.reloadFeatureTable()
  document.updateActivity("Sorted " & identifier & " " & $direction)

proc copySummary(document: FeatureDocument) =
  if document.isNil:
    return
  let pasteboard = generalPasteboard()
  let text = document.summary()
  discard pasteboard.setString(PasteboardTypeString, text)
  discard pasteboard.setUrl(
    PasteboardTypeUrl,
    if document.fileUrl.len > 0: document.fileUrl else: "nimkit://untitled",
  )
  discard pasteboard.setPropertyList(
    PasteboardTypePropertyList,
    [
      initPasteboardProperty("displayName", document.displayName()),
      initPasteboardProperty("featureCount", document.rows.len),
      initPasteboardProperty("edited", document.isDocumentEdited()),
    ],
  )
  discard pasteboard.setColor(PasteboardTypeColor, initColor(0.12, 0.32, 0.58, 1.0))
  discard pasteboard.setFont(
    PasteboardTypeFont,
    initPasteboardFontDescriptor("IBMPlexSans-Regular", "IBM Plex Sans", 13.0),
  )
  document.updatePasteboardInfo()
  document.updateActivity("Copied document summary to the general pasteboard")

proc beginTableDrag(document: FeatureDocument) =
  if document.isNil or document.table.isNil:
    return
  var rows = ListView(document.table).selectedIndexes()
  if rows.len == 0 and document.rows.len > 0:
    rows = @[0]
    ListView(document.table).selectedIndexes = rows
  let session = document.table.beginDraggingRows(rows, {dgoCopy, dgoMove})
  if session.isNil:
    document.updateActivity("No drag session could be created")
    return
  let target = initRowDropTarget(min(rows[0] + 1, document.rows.high))
  discard updateDraggingSession(
    session, initPoint(48.0, 82.0), DynamicAgent(document.table), target
  )
  document.updateActivity(
    "Started drag session: rows " & rows.join(", ") & ", ops " &
      $session.selectedOperations()
  )

proc markEdited(document: FeatureDocument) =
  if document.isNil:
    return
  document.documentEdited = true
  document.updateActivity("Marked document edited")

proc currentFeatureDocument(controller: FeatureDocumentController): FeatureDocument =
  let document = controller.currentDocument()
  if document of FeatureDocument:
    FeatureDocument(document)
  else:
    nil

proc openNextSample(controller: FeatureDocumentController, app: Application) =
  let index = controller.sampleIndex mod sampleUrls.len
  inc controller.sampleIndex
  discard controller.openDocument(sampleUrls[index], app = app)

proc cascadeFrame(
    controller: FeatureDocumentController, width = 980.0'f32, height = 520.0'f32
): Rect =
  let index =
    if controller.isNil:
      0
    else:
      min(max(controller.documentCount() - 1, 0), 8)
  let offset = 28.0'f32 * index.float32
  initRect(120.0 + offset, 120.0 + offset, width, height)

proc makeButton(
    title: string, action: string, callback: proc(sender: DynamicAgent)
): Button =
  result = newButton(title)
  let selector = actionSelector(action)
  result.action = selector
  result.target = newActionTarget(selector, callback)

proc configureTable(document: FeatureDocument, table: TableView) =
  table.addColumn(newTableColumn("name", "Feature", width = 190.0, minWidth = 150.0))
  table.addColumn(newTableColumn("layer", "Layer", width = 110.0))
  table.addColumn(
    newTableColumn("status", "Status", width = 92.0, alignment = taCenter)
  )
  table.addColumn(newTableColumn("note", "Why it matters", width = 260.0))
  table.dataSource = document
  table.delegate = document
  table.autosaveName = "document-workspace-demo"
  table.visibleRows = 8
  table.showsHeader = true
  table.tableHeaderHeight = 26.0
  table.rowHeight = 30.0
  table.selectionMode = lsmExtended
  table.allowsColumnSelection = true
  table.usesAlternatingRowBackgrounds = true
  table.showsRowSeparators = true
  table.selectedIndex = 0
  table.selectedColumns = [table.columnWithIdentifier("name")]
  table.accessibilityLabel = "Document workspace feature table"

proc makeWorkspaceWindow(
    document: FeatureDocument, controller: FeatureDocumentController, app: Application
): Window =
  result = newWindow("NimKit Document Workspace", frame = controller.cascadeFrame())
  let
    root = newView()
    menuBar = newMenuBar(app.mainMenu(), initRect(0, 0, 980, 28))
    title = newTitleLabel(document.displayName())
    subtitle = newStatusLabel(document.documentSubtitle())
    toolbar = newStackView(laHorizontal)
    table = newTableView()
    sideTitle = newHeadingLabel("Live State")
    activity = newStatusLabel("")
    pasteboardTitle = newHeadingLabel("Pasteboard")
    pasteboardInfo = newStatusLabel("")
    accessibilityTitle = newHeadingLabel("Accessibility")
    accessibilityInfo = newStatusLabel("")
    newButton = makeButton("New", NewDocumentAction) do(sender: DynamicAgent):
      discard controller.newDocument(app = app)
    openButton = makeButton("Open Sample", OpenSampleAction) do(sender: DynamicAgent):
      controller.openNextSample(app)
    reopenButton = makeButton("Reopen", ReopenRecentAction) do(sender: DynamicAgent):
      discard controller.reopenDocument(app = app)
    markButton = makeButton("Mark Edited", MarkEditedAction) do(sender: DynamicAgent):
      controller.currentFeatureDocument().markEdited()
    copyButton = makeButton("Copy", CopySummaryAction) do(sender: DynamicAgent):
      controller.currentFeatureDocument().copySummary()
    dragButton = makeButton("Stage Drag", BeginDragAction) do(sender: DynamicAgent):
      controller.currentFeatureDocument().beginTableDrag()
    accessButton = makeButton("Semantics", ShowAccessibilityAction) do(
      sender: DynamicAgent
    ):
      controller.currentFeatureDocument().updateAccessibilityInfo()
    closeButton = makeButton("Close All", CloseAllAction) do(sender: DynamicAgent):
      discard controller.closeAllDocuments()

  root.background = initColor(0.95, 0.96, 0.98)
  document.table = table
  document.subtitle = subtitle
  document.activity = activity
  document.pasteboardInfo = pasteboardInfo
  document.accessibilityInfo = accessibilityInfo
  document.configureTable(table)

  menuBar.reload()
  toolbar.spacing = 8.0
  toolbar.alignment = svaCenter
  toolbar.distribution = svdNatural
  toolbar.addArrangedSubview(
    newButton, openButton, reopenButton, markButton, copyButton, dragButton,
    accessButton, closeButton,
  )

  for label in [subtitle, activity, pasteboardInfo, accessibilityInfo]:
    label.accessibilityElement = true

  root.addSubview(
    menuBar, title, subtitle, toolbar, table, sideTitle, activity, pasteboardTitle,
    pasteboardInfo, accessibilityTitle, accessibilityInfo,
  )

  menuBar.pinEdges(
    toGuide = root.contentLayoutGuide(), edges = {leLeft, leTop, leRight}
  )
  menuBar[atHeight].equalTo(28.0).active = true
  title.pinEdges(
    toGuide = root.contentLayoutGuide(initEdgeInsets(46.0, 26.0, 0.0, 26.0)),
    edges = {leLeft, leTop, leRight},
  )
  activate(
    cx(title[atHeight] == 30.0),
    cx(subtitle[atTop] == title[atBottom] + 4.0),
    cx(subtitle[atLeft] == title[atLeft]),
    cx(subtitle[atRight] == title[atRight]),
    cx(subtitle[atHeight] == 20.0),
    cx(toolbar[atTop] == subtitle[atBottom] + 14.0),
    cx(toolbar[atLeft] == title[atLeft]),
    cx(toolbar[atRight] == title[atRight]),
    cx(toolbar[atHeight] == 30.0),
    cx(table[atTop] == toolbar[atBottom] + 18.0),
    cx(table[atLeft] == title[atLeft]),
    cx(table[atRight] == sideTitle[atLeft] - 22.0),
    cx(table[atBottom] == root[atBottom] - 26.0),
    cx(sideTitle[atTop] == table[atTop] + 4.0),
    cx(sideTitle[atRight] == title[atRight]),
    cx(sideTitle[atWidth] == 260.0),
    cx(sideTitle[atHeight] == 22.0),
    cx(activity[atTop] == sideTitle[atBottom] + 10.0),
    cx(activity[atLeft] == sideTitle[atLeft]),
    cx(activity[atRight] == sideTitle[atRight]),
    cx(activity[atHeight] == pasteboardInfo[atHeight]),
    cx(pasteboardTitle[atTop] == activity[atBottom] + 24.0),
    cx(pasteboardTitle[atLeft] == sideTitle[atLeft]),
    cx(pasteboardTitle[atRight] == sideTitle[atRight]),
    cx(pasteboardTitle[atHeight] == sideTitle[atHeight]),
    cx(pasteboardInfo[atTop] == pasteboardTitle[atBottom] + 10.0),
    cx(pasteboardInfo[atLeft] == sideTitle[atLeft]),
    cx(pasteboardInfo[atRight] == sideTitle[atRight]),
    cx(pasteboardInfo[atHeight] == accessibilityInfo[atHeight]),
    cx(accessibilityTitle[atTop] == pasteboardInfo[atBottom] + 24.0),
    cx(accessibilityTitle[atLeft] == sideTitle[atLeft]),
    cx(accessibilityTitle[atRight] == sideTitle[atRight]),
    cx(accessibilityTitle[atHeight] == sideTitle[atHeight]),
    cx(accessibilityInfo[atTop] == accessibilityTitle[atBottom] + 10.0),
    cx(accessibilityInfo[atLeft] == sideTitle[atLeft]),
    cx(accessibilityInfo[atRight] == sideTitle[atRight]),
    cx(accessibilityInfo[atBottom] == table[atBottom]),
  )

  document.updateActivity("Ready")
  document.updatePasteboardInfo()
  document.updateAccessibilityInfo()
  result.setContentView(root)
  discard result.makeFirstResponder(table)

proc makeTextDocumentWindow(
    document: FeatureDocument, controller: FeatureDocumentController
): Window =
  result = newWindow(
    document.displayName(),
    frame = controller.cascadeFrame(width = 620.0, height = 420.0),
  )
  let
    root = newView()
    title = newTitleLabel(document.displayName())
    subtitle = newStatusLabel(document.documentSubtitle())
    editor = newTextView(document.documentText(), frame = initRect(0, 0, 560.0, 660.0))
    scroll = newScrollView(documentView = editor)

  root.background = initColor(0.97, 0.98, 0.99)
  scroll.borderType = svbLineBorder
  scroll.hasVerticalScroller = true
  scroll.autohidesScrollers = true
  editor.accessibilityLabel = "Document text"
  document.editor = editor

  root.addSubview(title, subtitle, scroll)
  title.pinEdges(
    toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 24.0, 0.0, 24.0)),
    edges = {leLeft, leTop, leRight},
  )
  activate(
    cx(title[atHeight] == 30.0),
    cx(subtitle[atTop] == title[atBottom] + 4.0),
    cx(subtitle[atLeft] == title[atLeft]),
    cx(subtitle[atRight] == title[atRight]),
    cx(subtitle[atHeight] == 20.0),
    cx(scroll[atTop] == subtitle[atBottom] + 18.0),
    cx(scroll[atLeft] == title[atLeft]),
    cx(scroll[atRight] == title[atRight]),
    cx(scroll[atBottom] == root[atBottom] - 24.0),
  )

  result.setContentView(root)
  discard result.makeFirstResponder(editor)

proc makeDocumentWindow(
    document: FeatureDocument, controller: FeatureDocumentController, app: Application
): Window =
  if document.fileUrl.len > 0:
    document.makeTextDocumentWindow(controller)
  else:
    document.makeWorkspaceWindow(controller, app)

protocol FeatureDocIO of DocumentFileProtocol:
  method canReadType(document: FeatureDocument, fileType: string): bool =
    fileType in ["", DemoDocumentType]

  method canWriteType(document: FeatureDocument, fileType: string): bool =
    fileType in ["", DemoDocumentType]

  method readContents(
      document: FeatureDocument, fileUrl: string, fileType: string
  ): bool =
    document.rows = seedRows(fileUrl.seedKeyForUrl())
    document.displayName = fileUrl.sampleDisplayName()
    document.reloadFeatureTable()
    document.updateActivity("Read " & fileUrl)
    true

  method writeContents(
      document: FeatureDocument, fileUrl: string, fileType: string
  ): bool =
    document.updateActivity("Saved " & fileUrl)
    true

protocol FeatureDocWindows of DocumentWindowProtocol:
  method makeWindowControllers(document: FeatureDocument): seq[WindowController] =
    let controller = FeatureDocumentController(sharedDocumentController())
    let app = controller.application()
    @[newWindowController(document.makeDocumentWindow(controller, app))]

protocol FeatureDocTableSource of TableViewDataSource:
  method numberOfRows(document: FeatureDocument, tableView: TableView): int =
    document.rows.len

  method textForCell(
      document: FeatureDocument, tableView: TableView, row: int, column: TableColumn
  ): string =
    document.rowAt(row).fieldText(column)

protocol FeatureDocTableDelegate of TableViewDelegate:
  method viewForCell(
      document: FeatureDocument, tableView: TableView, row: int, column: TableColumn
  ): View =
    if column.identifier == "status":
      result = newStatusLabel(document.rowAt(row).status)
      Label(result).alignment = taCenter

  method didActivateRow(document: FeatureDocument, tableView: TableView, row: int) =
    let feature = document.rowAt(row)
    if feature.name.len > 0:
      document.updateActivity("Activated " & feature.name & ": " & feature.note)

  method sortDescriptorsDidChange(
      document: FeatureDocument,
      tableView: TableView,
      column: TableColumn,
      direction: TableSortDirection,
  ) =
    document.sortRows(column, direction)

  method shouldEditCell(
      document: FeatureDocument, tableView: TableView, row: int, column: TableColumn
  ): bool =
    column.identifier in ["name", "layer", "status", "note"]

  method didCommitEditingCell(
      document: FeatureDocument,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ) =
    if row in 0 ..< document.rows.len:
      case column.identifier
      of "name":
        document.rows[row].name = value
      of "layer":
        document.rows[row].layer = value
      of "status":
        document.rows[row].status = value
      of "note":
        document.rows[row].note = value
      else:
        discard
      document.documentEdited = true
      document.reloadFeatureTable()
      document.updateActivity("Committed " & column.title & " edit")

  method validateDragOperation(
      document: FeatureDocument, tableView: TableView, info: DraggingInfo
  ): DragOperations =
    {dgoCopy, dgoMove} * info.allowedOperations

protocol FeatureDocFactory of DocumentControllerFactory:
  method defaultDocumentType(controller: FeatureDocumentController): string =
    DemoDocumentType

  method makeUntitledDocument(
      controller: FeatureDocumentController, fileType: string
  ): Document =
    result = FeatureDocument(rows: seedRows("documents"))
    FeatureDocument(result).initDocument(fileType = DemoDocumentType)
    FeatureDocument(result).displayName = "Untitled Feature Workspace"
    discard FeatureDocument(result).withProtocol(FeatureDocIO)
    discard FeatureDocument(result).withProtocol(FeatureDocWindows)
    discard FeatureDocument(result).withProtocol(FeatureDocTableSource)
    discard FeatureDocument(result).withProtocol(FeatureDocTableDelegate)

  method makeDocumentForFileUrl(
      controller: FeatureDocumentController, fileUrl: string, fileType: string
  ): Document =
    result = FeatureDocument(rows: seedRows(fileUrl.seedKeyForUrl()))
    FeatureDocument(result).initDocument(fileUrl = fileUrl, fileType = DemoDocumentType)
    FeatureDocument(result).displayName = fileUrl.sampleDisplayName()
    discard FeatureDocument(result).withProtocol(FeatureDocIO)
    discard FeatureDocument(result).withProtocol(FeatureDocWindows)
    discard FeatureDocument(result).withProtocol(FeatureDocTableSource)
    discard FeatureDocument(result).withProtocol(FeatureDocTableDelegate)

protocol FeatureDocReview of DocumentControllerReview:
  method reviewUnsavedDocument(
      controller: FeatureDocumentController, document: Document
  ): DocumentCloseReviewAction =
    dcraDiscardChanges

proc makeFeatureDocumentController(app: Application): FeatureDocumentController =
  result = FeatureDocumentController()
  result.initDocumentController(app)
  discard result.withProtocol(FeatureDocFactory)
  discard result.withProtocol(FeatureDocReview)

proc installMainMenu(app: Application, controller: FeatureDocumentController) =
  let
    mainMenu = newMenu("Main")
    fileMenu = newMenu("File")
    fileItem = newMenuItem("File")
    newItem =
      newMenuItem("New Workspace", actionSelector(NewDocumentAction), "n", {kmCommand})
    openItem =
      newMenuItem("Open Sample", actionSelector(OpenSampleAction), "o", {kmCommand})
    reopenItem =
      newMenuItem("Reopen Recent", actionSelector(ReopenRecentAction), "r", {kmCommand})
    saveItem = newMenuItem("Save", actionSelector(SaveAction), "s", {kmCommand})
    revertItem = newMenuItem("Revert", actionSelector(RevertAction))
    closeItem = newMenuItem("Close", actionSelector(CloseAction), "w", {kmCommand})

  newItem.target = newActionTarget(actionSelector(NewDocumentAction)) do(
    sender: DynamicAgent
  ):
    discard controller.newDocument(app = app)
  openItem.target = newActionTarget(actionSelector(OpenSampleAction)) do(
    sender: DynamicAgent
  ):
    controller.openNextSample(app)
  reopenItem.target = newActionTarget(actionSelector(ReopenRecentAction)) do(
    sender: DynamicAgent
  ):
    discard controller.reopenDocument(app = app)
  saveItem.target = controller
  revertItem.target = controller
  closeItem.target = controller

  fileItem.submenu = fileMenu
  discard fileMenu.addItem(newItem)
  discard fileMenu.addItem(openItem)
  discard fileMenu.addItem(reopenItem)
  discard fileMenu.addSeparator()
  discard fileMenu.addItem(saveItem)
  discard fileMenu.addItem(revertItem)
  discard fileMenu.addSeparator()
  discard fileMenu.addItem(closeItem)
  discard mainMenu.addItem(fileItem)
  app.mainMenu = mainMenu

let
  app = sharedApplication()
  controller = makeFeatureDocumentController(app)

setSharedDocumentController(controller)
app.installMainMenu(controller)
for url in sampleUrls:
  controller.noteRecentDocumentUrl(url)
discard controller.newDocument(app = app)
app.run()
