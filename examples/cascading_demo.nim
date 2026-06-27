import std/[strutils]

import merenda/nimkit

import sigils/core

type
  CascadingDemoNode = object
    item: CascadingItem
    kind: string
    owner: string
    status: string
    detail: string

  CascadingDemoController = ref object of Responder
    nodes: seq[CascadingDemoNode]
    cascadingView: CascadingView
    title: Label
    metadata: Label
    detail: Label
    activity: Label

proc initNode(
    identifier, title, parentIdentifier, kind, owner, status, detail: string,
    leaf = false,
): CascadingDemoNode =
  CascadingDemoNode(
    item: initCascadingItem(identifier, title, parentIdentifier, leaf),
    kind: kind,
    owner: owner,
    status: status,
    detail: detail,
  )

proc demoNodes(): seq[CascadingDemoNode] =
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
      "Stack, form, grid, tab, split, scroll, table, outline, box, and CascadingView presets.",
    ),
    initNode(
      "cascading-view",
      "CascadingView",
      "container-layer",
      "Widget",
      "Containers",
      "New",
      "CascadingView using the Miller Column preset from initCascadingMillerColumn(), backed by CascadingDataSource and CascadingDelegate protocols.",
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
    controller: CascadingDemoController, identifier: string
): CascadingDemoNode =
  for node in controller.nodes:
    if node.item.identifier == identifier:
      return node

proc childNodes(
    controller: CascadingDemoController, parentIdentifier: string
): seq[CascadingDemoNode] =
  for node in controller.nodes:
    if node.item.parentIdentifier == parentIdentifier:
      result.add node

proc selectedTrail(controller: CascadingDemoController): string =
  let path = controller.cascadingView.selectedPath()
  if path.len == 0:
    return "No selection"
  var titles: seq[string]
  for identifier in path:
    let node = controller.nodeForIdentifier(identifier)
    if node.item.title.len > 0:
      titles.add node.item.title
  titles.join(" / ")

proc updateDetail(controller: CascadingDemoController, identifier: string) =
  let node = controller.nodeForIdentifier(identifier)
  if node.item.identifier.len == 0:
    controller.title.text = "NimKit CascadingView"
    controller.metadata.text = "No item selected"
    controller.detail.text = ""
    return

  controller.title.text = node.item.title
  controller.metadata.text =
    node.kind & " / " & node.owner & " / " & node.status & "\n" &
    controller.selectedTrail()
  controller.detail.text = node.detail

protocol CascadingDemoDataSource of CascadingDataSource:
  method cascadingNumberOfChildren(
      controller: CascadingDemoController, view: CascadingView, parentIdentifier: string
  ): int =
    discard view
    controller.childNodes(parentIdentifier).len

  method cascadingChildIdentifier(
      controller: CascadingDemoController,
      view: CascadingView,
      parentIdentifier: string,
      index: int,
  ): string =
    discard view
    let children = controller.childNodes(parentIdentifier)
    if index in 0 ..< children.len:
      result = children[index].item.identifier

  method cascadingItem(
      controller: CascadingDemoController, view: CascadingView, identifier: string
  ): CascadingItem =
    discard view
    controller.nodeForIdentifier(identifier).item

protocol CascadingDemoDelegate of CascadingDelegate:
  method didSelectCascadingItem(
      controller: CascadingDemoController,
      view: CascadingView,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard view
    discard column
    discard row
    controller.updateDetail(identifier)
    controller.activity.text = "Selected " & controller.selectedTrail()

  method didActivateCascadingItem(
      controller: CascadingDemoController,
      view: CascadingView,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard view
    discard column
    discard row
    let node = controller.nodeForIdentifier(identifier)
    if node.item.identifier.len > 0:
      controller.activity.text = "Activated " & node.item.title

proc newCascadingDemoController(): CascadingDemoController =
  result = CascadingDemoController(nodes: demoNodes())
  initResponder(result)
  discard result.withProtocol(CascadingDemoDataSource)
  discard result.withProtocol(CascadingDemoDelegate)

let
  app = sharedApplication()
  window = newWindow("NimKit CascadingView Demo", frame = initRect(140, 120, 760, 420))
  root = newView()
  split = newSplitView(laHorizontal)
  detailPane = newStackView(laVertical)
  controller = newCascadingDemoController()

controller.cascadingView = newCascadingView()
controller.cascadingView.columnWidth = 170.0
controller.cascadingView.minColumnWidth = 120.0
controller.cascadingView.dataSource = controller
controller.cascadingView.delegate = controller
controller.cascadingView.accessibilityLabel = "NimKit CascadingView Demo"

controller.title = newTitleLabel("NimKit CascadingView")
controller.metadata = newStatusLabel("No item selected")
controller.detail = newStatusLabel("")
controller.activity = newStatusLabel("Ready")

detailPane.spacing = 12.0
detailPane.alignment = svaFill
detailPane.distribution = svdNatural
detailPane.edgeInsets = insets(18.0)
detailPane.addArrangedSubview(
  controller.title,
  controller.metadata,
  newHorizontalSeparator(),
  controller.detail,
  newHeadingLabel("Activity"),
  controller.activity,
)

split.addPane(controller.cascadingView, minSize = 260.0)
split.addPane(detailPane, minSize = 240.0)
split.setPositionOfDivider(0, 380.0)

root.addSubview(split)
split.pinEdges(
  toGuide = root.contentLayoutGuide(insets(18.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

controller.cascadingView.selectedPath =
  @["framework", "container-layer", "cascading-view"]
controller.updateDetail("cascading-view")

window.minSize = initSize(560.0, 320.0)
window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
