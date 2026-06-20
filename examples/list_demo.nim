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

type ListDemoDelegate = ref object of Responder

protocol ListDemoDelegateEvents from ListDemoDelegate:
  includes ListViewEvents

  proc selectionDidChange(delegate: ListDemoDelegate, sender: DynamicAgent) {.slot.} =
    if sender == DynamicAgent(list):
      updateDetail()

proc newListDemoDelegate(): ListDemoDelegate =
  result = ListDemoDelegate()
  initResponder(result)
  result = result.withProto()

let selectionDelegate = newListDemoDelegate()

root.background = initColor(0.95, 0.96, 0.98)

list.visibleRows = 6
list.rowHeight = 24.0
list.selectionMode = lsmExtended
list.usesAlternatingRowBackgrounds = true
list.showsRowSeparators = true
list.selectedIndex = 0
list.delegate = selectionDelegate

root.addSubview(title, list, detailTitle, detail)

title.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

activate(
  cx(list[anTop] == title[anBottom] + 18.0),
  cx(list[anLeft] == title[anLeft]),
  cx(list[anWidth] == 188.0),
  cx(detailTitle[anTop] == list[anTop] + 4.0),
  cx(detailTitle[anLeft] == list[anRight] + 18.0),
  cx(detailTitle[anRight] == title[anRight]),
  cx(detail[anTop] == detailTitle[anBottom] + 10.0),
  cx(detail[anLeft] == detailTitle[anLeft]),
  cx(detail[anRight] == detailTitle[anRight]),
)

updateDetail()
window.setContentView(root)
discard window.makeFirstResponder(list)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
