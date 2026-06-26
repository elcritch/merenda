import std/[strutils]

import merenda/nimkit

import sigils/core

type
  BrowserDemoNode = object
    item: BrowserItem
    kind: string
    owner: string
    status: string
    detail: string

  BrowserDemoController = ref object of Responder
    nodes: seq[BrowserDemoNode]
    browser: Browser
    title: Label
    metadata: Label
    detail: Label
    activity: Label

proc initNode(
    identifier, title, parentIdentifier, kind, owner, status, detail: string,
    leaf = false,
): BrowserDemoNode =
  BrowserDemoNode(
    item: initBrowserItem(identifier, title, parentIdentifier, leaf),
    kind: kind,
    owner: owner,
    status: status,
    detail: detail,
  )

proc demoNodes(): seq[BrowserDemoNode] =
  @[
    initNode(
      "apps", "Applications", "", "Workspace", "Application", "Ready",
      "Application-level demos built from NimKit views, windows, menus, and documents.",
    ),
    initNode(
      "framework", "Framework", "", "Library", "NimKit", "Active",
      "Core framework areas organized by the same domains as src/merenda/nimkit.",
    ),
    initNode(
      "assets", "Resources", "", "Bundle", "Renderer", "Available",
      "Fonts, images, and theme resources used by the examples and rendering tests.",
    ),
    initNode(
      "document-workspace",
      "Document Workspace",
      "apps",
      "Demo",
      "Documents",
      "Recent",
      "Shows DocumentController, Document, WindowController, pasteboards, and tables.",
      leaf = true,
    ),
    initNode(
      "table-dashboard",
      "Table Dashboard",
      "apps",
      "Demo",
      "Containers",
      "Stable",
      "Exercises sorting, hosted cells, editing, persistence, and drag state.",
      leaf = true,
    ),
    initNode(
      "preferences",
      "Preferences",
      "apps",
      "Demo",
      "Controls",
      "Stable",
      "Combines forms, boxes, choices, popup controls, and sliders in a settings panel.",
      leaf = true,
    ),
    initNode(
      "view-layer", "Views", "framework", "Framework Area", "View", "Covered",
      "Hierarchy management, layout invalidation, coordinate conversion, and rendering.",
    ),
    initNode(
      "control-layer", "Controls", "framework", "Framework Area", "Control", "Covered",
      "Buttons, text fields, sliders, choices, popups, target/action, and field editors.",
    ),
    initNode(
      "container-layer", "Containers", "framework", "Framework Area", "Container",
      "Active",
      "Stack, form, grid, tab, split, scroll, table, outline, box, and browser views.",
    ),
    initNode(
      "browser-widget",
      "Browser",
      "container-layer",
      "Widget",
      "Containers",
      "New",
      "Miller-column browser backed by BrowserDataSource and BrowserDelegate protocols.",
      leaf = true,
    ),
    initNode(
      "table-widget",
      "TableView",
      "container-layer",
      "Widget",
      "Containers",
      "Mature",
      "Reusable row, column, selection, editing, drag, and persistence infrastructure.",
      leaf = true,
    ),
    initNode(
      "outline-widget",
      "OutlineView",
      "container-layer",
      "Widget",
      "Containers",
      "Mature",
      "Expandable tree view layered on top of table behavior and row rendering.",
      leaf = true,
    ),
    initNode(
      "fonts",
      "Fonts",
      "assets",
      "Resource",
      "Text",
      "Loaded",
      "Bundled typefaces used by text layout, controls, and rendering examples.",
      leaf = true,
    ),
    initNode(
      "images",
      "Images",
      "assets",
      "Resource",
      "Drawing",
      "Loaded",
      "Bitmap and vector source assets used by image resources and demos.",
      leaf = true,
    ),
  ]

proc nodeForIdentifier(
    controller: BrowserDemoController, identifier: string
): BrowserDemoNode =
  for node in controller.nodes:
    if node.item.identifier == identifier:
      return node

proc childNodes(
    controller: BrowserDemoController, parentIdentifier: string
): seq[BrowserDemoNode] =
  for node in controller.nodes:
    if node.item.parentIdentifier == parentIdentifier:
      result.add node

proc selectedTrail(controller: BrowserDemoController): string =
  let path = controller.browser.selectedPath()
  if path.len == 0:
    return "No selection"
  var titles: seq[string]
  for identifier in path:
    let node = controller.nodeForIdentifier(identifier)
    if node.item.title.len > 0:
      titles.add node.item.title
  titles.join(" / ")

proc updateDetail(controller: BrowserDemoController, identifier: string) =
  let node = controller.nodeForIdentifier(identifier)
  if node.item.identifier.len == 0:
    controller.title.text = "NimKit Browser"
    controller.metadata.text = "No item selected"
    controller.detail.text = ""
    return

  controller.title.text = node.item.title
  controller.metadata.text =
    node.kind & " / " & node.owner & " / " & node.status & "\n" &
    controller.selectedTrail()
  controller.detail.text = node.detail

protocol BrowserDemoDataSource of BrowserDataSource:
  method browserNumberOfChildren(
      controller: BrowserDemoController, browser: Browser, parentIdentifier: string
  ): int =
    discard browser
    controller.childNodes(parentIdentifier).len

  method browserChildIdentifier(
      controller: BrowserDemoController,
      browser: Browser,
      parentIdentifier: string,
      index: int,
  ): string =
    discard browser
    let children = controller.childNodes(parentIdentifier)
    if index in 0 ..< children.len:
      result = children[index].item.identifier

  method browserItem(
      controller: BrowserDemoController, browser: Browser, identifier: string
  ): BrowserItem =
    discard browser
    controller.nodeForIdentifier(identifier).item

protocol BrowserDemoDelegate of BrowserDelegate:
  method didSelectBrowserItem(
      controller: BrowserDemoController,
      browser: Browser,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard browser
    discard column
    discard row
    controller.updateDetail(identifier)
    controller.activity.text = "Selected " & controller.selectedTrail()

  method didActivateBrowserItem(
      controller: BrowserDemoController,
      browser: Browser,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard browser
    discard column
    discard row
    let node = controller.nodeForIdentifier(identifier)
    if node.item.identifier.len > 0:
      controller.activity.text = "Activated " & node.item.title

proc newBrowserDemoController(): BrowserDemoController =
  result = BrowserDemoController(nodes: demoNodes())
  initResponder(result)
  discard result.withProtocol(BrowserDemoDataSource)
  discard result.withProtocol(BrowserDemoDelegate)

let
  app = sharedApplication()
  window = newWindow("NimKit Browser Demo", frame = initRect(140, 120, 760, 420))
  root = newView()
  split = newSplitView(laHorizontal)
  detailPane = newStackView(laVertical)
  controller = newBrowserDemoController()

controller.browser = newBrowser()
controller.browser.columnWidth = 170.0
controller.browser.minColumnWidth = 120.0
controller.browser.dataSource = controller
controller.browser.delegate = controller
controller.browser.accessibilityLabel = "NimKit Browser Demo"

controller.title = newTitleLabel("NimKit Browser")
controller.metadata = newStatusLabel("No item selected")
controller.detail = newStatusLabel("")
controller.activity = newStatusLabel("Ready")

detailPane.spacing = 12.0
detailPane.alignment = svaFill
detailPane.distribution = svdNatural
detailPane.edgeInsets = initEdgeInsets(18.0)
detailPane.addArrangedSubview(
  controller.title,
  controller.metadata,
  newHorizontalSeparator(),
  controller.detail,
  newHeadingLabel("Activity"),
  controller.activity,
)

split.addPane(controller.browser, minSize = 260.0)
split.addPane(detailPane, minSize = 240.0)
split.setPositionOfDivider(0, 380.0)

root.addSubview(split)
split.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(18.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

controller.browser.selectedPath = @["framework", "container-layer", "browser-widget"]
controller.updateDetail("browser-widget")

window.minSize = initSize(560.0, 320.0)
window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
