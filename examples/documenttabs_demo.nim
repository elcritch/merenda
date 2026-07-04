import merenda/nimkit

import sigils/core
import sigils/selectors

type DocumentTabsDemo = ref object of Responder
  tabs: DocumentTabs
  status: TextField
  styleChoice: ComboBox
  nextNumber: int

const DemoWindowWidth = 720.0'f32

protocol DocumentTabsDemoDelegate of DocumentTabsDelegate:
  method didMoveDocumentTab(
      demo: DocumentTabsDemo,
      tabs: DocumentTabs,
      item: DocumentTabItem,
      fromIndex: int,
      toIndex: int,
  ) =
    discard tabs
    demo.status.text = "Moved " & item.title & " from " & $fromIndex & " to " & $toIndex

  method didSelectDocumentTab(
      demo: DocumentTabsDemo, tabs: DocumentTabs, item: DocumentTabItem
  ) =
    discard tabs
    demo.status.text = "Selected " & item.title

  method shouldCloseDocumentTab(
      demo: DocumentTabsDemo, tabs: DocumentTabs, item: DocumentTabItem, index: int
  ): bool =
    discard tabs
    discard index
    if item.identifier == "pinned":
      demo.status.text = "Pinned tab cannot close"
      return false
    true

  method didCloseDocumentTab(
      demo: DocumentTabsDemo, tabs: DocumentTabs, item: DocumentTabItem, index: int
  ) =
    discard tabs
    demo.status.text = "Closed " & item.title & " at " & $index

protocol DocumentTabsDemoSignals from DocumentTabsDemo:
  includes DocumentTabsEvents

  proc documentTabsDidScroll(demo: DocumentTabsDemo, offset: float32) {.slot.} =
    demo.status.text = "Scrolled tabs to " & $int(offset)

proc newDemoTab(title, identifier: string, style: DocumentTabStyle): DocumentTabItem =
  result = newDocumentTabItem(title, identifier, closeable = identifier != "pinned")
  result.style = style
  case style
  of dtsPill:
    result.accentColor = color(0.10, 0.58, 0.95, 1.0)
  of dtsUnderline:
    result.accentColor = color(0.95, 0.42, 0.78, 1.0)
  of dtsCompact:
    result.accentColor = color(0.25, 0.66, 0.42, 1.0)
  else:
    result.accentColor = color(0.95, 0.56, 0.24, 1.0)

proc selectedStyle(demo: DocumentTabsDemo): DocumentTabStyle =
  case demo.styleChoice.indexOfSelectedItem()
  of 1: dtsPill
  of 2: dtsUnderline
  of 3: dtsCompact
  else: dtsRounded

proc addTab(demo: DocumentTabsDemo, sender: DynamicAgent) =
  discard sender
  inc demo.nextNumber
  let style = demo.selectedStyle()
  let tab = newDemoTab("Draft " & $demo.nextNumber, "draft-" & $demo.nextNumber, style)
  tab.modified = demo.nextNumber mod 2 == 0
  discard demo.tabs.addDocumentTabItem(tab)
  discard demo.tabs.selectDocumentTab(tab)
  demo.status.text = "Added " & tab.title

proc closeSelected(demo: DocumentTabsDemo, sender: DynamicAgent) =
  discard sender
  let item = demo.tabs.selectedDocumentTabItem()
  if item.isNil:
    demo.status.text = "No selected tab"
  else:
    discard demo.tabs.closeDocumentTab(item)

proc moveSelectedLeft(demo: DocumentTabsDemo, sender: DynamicAgent) =
  discard sender
  let index = demo.tabs.selectedIndex()
  if index > 0 and demo.tabs.moveDocumentTabItem(index, index - 1):
    discard demo.tabs.selectDocumentTabAtIndex(index - 1)

proc moveSelectedRight(demo: DocumentTabsDemo, sender: DynamicAgent) =
  discard sender
  let index = demo.tabs.selectedIndex()
  if index >= 0 and demo.tabs.moveDocumentTabItem(index, index + 1):
    discard demo.tabs.selectDocumentTabAtIndex(min(index + 1, demo.tabs.len() - 1))

proc applyStyle(demo: DocumentTabsDemo, sender: DynamicAgent) =
  discard sender
  let item = demo.tabs.selectedDocumentTabItem()
  if item.isNil:
    return
  item.style = demo.selectedStyle()
  demo.tabs.reloadDocumentTabs()
  demo.status.text = "Restyled " & item.title

proc newDocumentTabsDemo(): DocumentTabsDemo =
  result = DocumentTabsDemo(nextNumber: 8)
  initResponder(result)
  discard result.withProtocol(DocumentTabsDemoDelegate)
  discard result.withProto()

let
  app = sharedApplication()
  demo = newDocumentTabsDemo()
  root = newView()
  layout = newStackView(laVertical)
  header = newTitleLabel("Document Tabs Demo")
  status = newStatusLabel("Selected Project Plan")
  tabs = newDocumentTabs()
  controls = newStackView(laHorizontal)
  addButton = newButton("Add")
  closeButton = newButton("Close")
  leftButton = newButton("Move Left")
  rightButton = newButton("Move Right")
  styleChoice = newComboBox(["Rounded", "Pill", "Underline", "Compact"])
  content =
    newTextField("Use the tab strip as a document switcher with app-owned content.")

demo.tabs = tabs
demo.status = status
demo.styleChoice = styleChoice
tabs.delegate = demo
demo.observeProtocol(tabs, DocumentTabsEvents)

layout.spacing = 12.0
layout.alignment = svaFill
layout.edgeInsets = insets(22.0, 24.0)

tabs.setHuggingPriority(LayoutPriorityRequired, laVertical)
tabs.setCompressionPriority(LayoutPriorityRequired, laVertical)
tabs.defaultTabStyle = dtsRounded

discard tabs.addDocumentTabItem(newDemoTab("Project Plan", "pinned", dtsRounded))
discard tabs.addDocumentTabItem(newDemoTab("Budget.xlsx", "budget", dtsPill))
discard tabs.addDocumentTabItem(newDemoTab("Launch Copy", "copy", dtsUnderline))
discard tabs.addDocumentTabItem(newDemoTab("Research Notes", "notes", dtsCompact))
discard tabs.addDocumentTabItem(newDemoTab("Screenshots", "screens", dtsRounded))
discard tabs.addDocumentTabItem(newDemoTab("Bug Triage", "bugs", dtsPill))
discard tabs.addDocumentTabItem(newDemoTab("Release Notes", "release", dtsUnderline))
discard tabs.addDocumentTabItem(newDemoTab("Archive", "archive", dtsCompact))
tabs[1].modified = true
tabs[5].modified = true

controls.spacing = 8.0
controls.alignment = svaCenter
controls.distribution = svdNatural
styleChoice.selectItemAtIndex(0)

addButton.target = newActionTarget(actionSelector("addDocumentTab")) do(
  sender: DynamicAgent
):
  demo.addTab(sender)
addButton.action = actionSelector("addDocumentTab")

closeButton.target = newActionTarget(actionSelector("closeDocumentTab")) do(
  sender: DynamicAgent
):
  demo.closeSelected(sender)
closeButton.action = actionSelector("closeDocumentTab")

leftButton.target = newActionTarget(actionSelector("moveDocumentTabLeft")) do(
  sender: DynamicAgent
):
  demo.moveSelectedLeft(sender)
leftButton.action = actionSelector("moveDocumentTabLeft")

rightButton.target = newActionTarget(actionSelector("moveDocumentTabRight")) do(
  sender: DynamicAgent
):
  demo.moveSelectedRight(sender)
rightButton.action = actionSelector("moveDocumentTabRight")

styleChoice.target = newActionTarget(actionSelector("styleDocumentTab")) do(
  sender: DynamicAgent
):
  demo.applyStyle(sender)
styleChoice.action = actionSelector("styleDocumentTab")

content.editable = false
content.selectable = false
content.setHuggingPriority(LayoutPriorityLow, laVertical)
content.setCompressionPriority(LayoutPriorityLow, laVertical)

controls.addArrangedSubview(
  addButton, closeButton, leftButton, rightButton, styleChoice
)
controls.addFlexibleSpacer()
layout.addArrangedSubview(header, status, tabs, controls, content)
root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(), edges = {leLeft, leTop, leRight, leBottom}
)

let
  minimumWindowHeight =
    layout
    .resolvedIntrinsicContentSize()
    .resolveIntrinsicSize(initSize(DemoWindowWidth, 0.0)).height + 80.0'f32
  window = newWindow(
    "NimKit Document Tabs Demo",
    frame = rect(160, 160, DemoWindowWidth, minimumWindowHeight),
  )

window.minSize = initSize(520.0, minimumWindowHeight)
window.setContentView(root)
discard window.makeFirstResponder(tabs)
app.addWindow(window)
window.makeKeyAndOrderFront()
app.run()
