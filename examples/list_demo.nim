import std/strutils

import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit List Demo", frame = initRect(180, 160, 460, 320))
  root = newView()
  title = newTitleLabel("List View")
  list = newListView(
    ["Inbox", "Drafts", "Sent", "Archive", "Settings", "Updates", "Builds", "Logs"]
  )
  detailTitle = newHeadingLabel("Selection")
  detail = newStatusLabel("")
  changedAction = actionSelector("listSelectionChanged")

proc updateDetail() =
  let indexes = list.selectedIndexes()
  if indexes.len == 0:
    detail.text = "No selection"
    return

  var names: seq[string]
  for index in indexes:
    names.add list[index]

  let ranges = list.selectedRanges()
  let firstRangeLength =
    if ranges.len == 0:
      0
    else:
      ranges[0].b - ranges[0].a + 1
  detail.text =
    if ranges.len == 1 and firstRangeLength > 1:
      "Selected " & $firstRangeLength & ": " & names.join(", ")
    elif indexes.len == 1:
      "Selected: " & names[0]
    else:
      "Selected " & $indexes.len & ": " & names.join(", ")

proc onListChanged(sender: DynamicAgent) =
  if sender == DynamicAgent(list):
    updateDetail()

root.background = initColor(0.95, 0.96, 0.98)

list.visibleRows = 6
list.rowHeight = 24.0
list.selectionMode = lsmExtended
list.selectedIndex = 0
list.target = newActionTarget(changedAction, onListChanged)
list.action = changedAction

root.addSubview(title, list, detailTitle, detail)

title.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

activate(
  cx(list.topAnchor == title.bottomAnchor + 18.0),
  cx(list.leftAnchor == title.leftAnchor),
  cx(list.widthAnchor == 188.0),
  cx(detailTitle.topAnchor == list.topAnchor + 4.0),
  cx(detailTitle.leftAnchor == list.rightAnchor + 18.0),
  cx(detailTitle.rightAnchor == title.rightAnchor),
  cx(detail.topAnchor == detailTitle.bottomAnchor + 10.0),
  cx(detail.leftAnchor == detailTitle.leftAnchor),
  cx(detail.rightAnchor == detailTitle.rightAnchor),
)

updateDetail()
window.setContentView(root)
discard window.makeFirstResponder(list)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
