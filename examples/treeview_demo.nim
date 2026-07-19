import std/[algorithm, strutils]

import merenda/nimkit

import sigils/core
import sigils/selectors

type TreeViewDemo* = ref object of Responder
  app*: Application
  window*: Window
  root*: View
  tree*: OutlineView
  selectionLabel*: Label
  pathLabel*: Label
  activityLabel*: Label
  expandButton*: Button
  collapseButton*: Button

proc treeItem(
    identifier, title, parentIdentifier, kind, tooltip: string, expandable = false
): OutlineItem =
  initOutlineItem(
    identifier,
    title,
    parentIdentifier = parentIdentifier,
    expandable = expandable,
    leaf = not expandable,
    objectValue = toObj(kind),
    tooltip = tooltip,
  )

proc treeItems(): seq[OutlineItem] =
  @[
    treeItem(
      "bundle",
      "Resource Bundle",
      "",
      "Bundle",
      "The root of the declarative UI resources.",
      expandable = true,
    ),
    treeItem(
      "windows",
      "Windows",
      "bundle",
      "Group",
      "Window resources in the bundle.",
      expandable = true,
    ),
    treeItem(
      "window.main",
      "Main Window",
      "windows",
      "Window",
      "The application's primary document window.",
      expandable = true,
    ),
    treeItem(
      "view.root",
      "Root View",
      "window.main",
      "View",
      "The content view installed in the main window.",
      expandable = true,
    ),
    treeItem(
      "view.toolbar",
      "Toolbar",
      "view.root",
      "StackView",
      "A horizontal stack of document actions.",
      expandable = true,
    ),
    treeItem(
      "button.add", "Add Widget", "view.toolbar", "Button",
      "Adds a widget to the selected container.",
    ),
    treeItem(
      "button.delete", "Delete Widget", "view.toolbar", "Button",
      "Removes the selected widget.",
    ),
    treeItem(
      "view.content",
      "Editor Split View",
      "view.root",
      "SplitView",
      "Hosts the resource hierarchy and preview surface.",
      expandable = true,
    ),
    treeItem(
      "view.hierarchy", "Resource Hierarchy", "view.content", "OutlineView",
      "The collapsible tree used by the resource editor.",
    ),
    treeItem(
      "view.preview",
      "Preview Surface",
      "view.content",
      "View",
      "Displays the latest valid resource revision.",
      expandable = true,
    ),
    treeItem(
      "label.preview", "Welcome Label", "view.preview", "Label",
      "A label instantiated from the resource document.",
    ),
    treeItem(
      "commands",
      "Commands",
      "bundle",
      "Group",
      "Selector-backed actions available to the UI.",
      expandable = true,
    ),
    treeItem(
      "command.save", "Save Document", "commands", "Command",
      "Saves the current resource document.",
    ),
    treeItem(
      "assets",
      "Assets",
      "bundle",
      "Group",
      "Images, localized strings, and theme fragments.",
      expandable = true,
    ),
    treeItem(
      "image.app-icon", "Application Icon", "assets", "Image",
      "The application icon resource.",
    ),
    treeItem(
      "theme.default", "Default Theme", "assets", "Theme",
      "The default appearance fragment.",
    ),
  ]

proc titleForItem(demo: TreeViewDemo, identifier: string): string =
  demo.tree.outlineItemWithIdentifier(identifier).displayTitle()

proc selectedPath(demo: TreeViewDemo, identifier: string): string =
  var
    current = identifier
    titles: seq[string]
  while current.len > 0:
    let item = demo.tree.outlineItemWithIdentifier(current)
    if item.identifier.len == 0:
      break
    titles.add item.displayTitle()
    current = item.parentIdentifier
  titles.reverse()
  titles.join(" › ")

proc updateSelection(demo: TreeViewDemo) =
  let identifier = demo.tree.selectedItemIdentifier()
  if identifier.len == 0:
    demo.selectionLabel.text = "No item selected"
    demo.pathLabel.text = "Select a visible row to inspect its path."
    return

  let
    item = demo.tree.outlineItemWithIdentifier(identifier)
    kind = item.objectValue.formatObjectValue(initObjectFormatContext(role = ovrLabel))
    childCount = demo.tree.childIdentifiersForItem(identifier).len
  demo.selectionLabel.text =
    item.displayTitle() & "\n" & kind & " · " & identifier & "\n" & (
      if childCount == 0:
        "Leaf item"
      else:
        $childCount & " child item" & (if childCount == 1: "" else: "s")
    )
  demo.pathLabel.text = demo.selectedPath(identifier)

proc updateActivity(demo: TreeViewDemo, message: string) =
  demo.activityLabel.text = message

proc expandAll(demo: TreeViewDemo) =
  for identifier in demo.tree.outlineItemIdentifiers():
    if demo.tree.isItemExpandable(identifier):
      demo.tree.expandItem(identifier)
  demo.updateSelection()
  demo.updateActivity("Expanded every container")

proc collapseAll(demo: TreeViewDemo) =
  for identifier in demo.tree.expandedItemIdentifiers():
    demo.tree.collapseItem(identifier)
  demo.updateSelection()
  demo.updateActivity("Collapsed every container")

proc treeSelectionDidChange(demo: TreeViewDemo, sender: DynamicAgent) {.slot.} =
  if sender == DynamicAgent(demo.tree):
    demo.updateSelection()

protocol TreeViewDemoOutlineDelegate of OutlineViewDelegate:
  method didExpandItem(
      demo: TreeViewDemo, outlineView: OutlineView, identifier: string
  ) =
    discard outlineView
    demo.updateActivity("Expanded " & demo.titleForItem(identifier))

  method didCollapseItem(
      demo: TreeViewDemo, outlineView: OutlineView, identifier: string
  ) =
    discard outlineView
    demo.updateActivity("Collapsed " & demo.titleForItem(identifier))

proc configureTree(tree: OutlineView) =
  tree.outlineColumn().title = "Resource"
  tree.outlineColumn().width = 326.0
  tree.outlineItems = treeItems()
  tree.expandedItemIdentifiers =
    ["bundle", "windows", "window.main", "view.root", "view.content"]
  tree.selectedItemIdentifier = "view.preview"
  tree.visibleRows = 11
  tree.showsHeader = true
  tree.tableHeaderHeight = 26.0
  tree.rowHeight = 28.0
  tree.selectionMode = tsmSingle
  tree.usesAlternatingRowBackgrounds = true
  tree.showsRowSeparators = true
  tree.autosaveName = "tree-view-demo"

proc newTreeViewDemo*(app = newApplication()): TreeViewDemo =
  result = TreeViewDemo(app: app)
  initResponder(result)
  discard result.withProtocol(TreeViewDemoOutlineDelegate)

  result.window = newWindow("NimKit Tree View", frame = rect(140, 120, 760, 460))
  result.root = newView(frame = rect(0, 0, 760, 460))
  result.tree = newOutlineView(frame = rect(24, 116, 340, 318))
  result.selectionLabel = newStatusLabel("", frame = rect(392, 160, 344, 74))
  result.pathLabel = newStatusLabel("", frame = rect(392, 278, 344, 58))
  result.activityLabel = newStatusLabel(
    "Click a disclosure arrow, or use Left and Right while the tree has focus.",
    frame = rect(392, 382, 344, 52),
  )
  result.expandButton = newButton("Expand All", frame = rect(24, 70, 104, 30))
  result.collapseButton = newButton("Collapse All", frame = rect(138, 70, 112, 30))

  result.tree.configureTree()
  result.tree.outlineDelegate = result
  result.tree.connect(selectionDidChange, result, treeSelectionDidChange)

  let
    demo = result
    expandAction = actionSelector("treeViewDemoExpandAll")
    collapseAction = actionSelector("treeViewDemoCollapseAll")
  result.expandButton.target = newActionTarget(
    expandAction,
    proc(sender: DynamicAgent) =
      discard sender
      demo.expandAll(),
  )
  result.expandButton.action = expandAction
  result.collapseButton.target = newActionTarget(
    collapseAction,
    proc(sender: DynamicAgent) =
      discard sender
      demo.collapseAll(),
  )
  result.collapseButton.action = collapseAction

  result.root.addSubviews(
    autoNames(
      newTitleLabel("Collapsible Tree View", frame = rect(24, 20, 712, 32)),
      newStatusLabel(
        "OutlineView turns flat items with stable parent identifiers into a tree.",
        frame = rect(24, 48, 712, 20),
      ),
      result.expandButton,
      result.collapseButton,
      result.tree,
      newHeadingLabel("Selection", frame = rect(392, 120, 344, 26)),
      result.selectionLabel,
      newHeadingLabel("Stable Path", frame = rect(392, 244, 344, 26)),
      result.pathLabel,
      newHeadingLabel("Interaction", frame = rect(392, 348, 344, 26)),
      result.activityLabel,
    )
  )
  result.window.setContentView(result.root)
  result.updateSelection()

proc showTreeViewDemo*(demo: TreeViewDemo) =
  if not demo.isNil:
    discard demo.app.showWindow(demo.window, demo.root)

when isMainModule:
  let demo = newTreeViewDemo(sharedApplication())
  demo.app.runWindow(demo.window, demo.root, demo.tree)
