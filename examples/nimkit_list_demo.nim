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
  let index = list.selectedIndex
  detail.text =
    if index >= 0:
      "Selected: " & list[index]
    else:
      "No selection"

proc onListChanged(sender: DynamicAgent) =
  if sender == DynamicAgent(list):
    updateDetail()

root.background = initColor(0.95, 0.96, 0.98)

list.visibleRows = 6
list.rowHeight = 24.0
list.selectedIndex = 0
list.target = newActionTarget(changedAction, onListChanged)
list.action = changedAction

root.addSubview(title, list, detailTitle, detail)

title.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

activate(
  cx(list.topAnchor == title.bottomAnchor, constant = 18.0),
  cx(list.leftAnchor == title.leftAnchor),
  cx(list.widthAnchor == 188.0),
  cx(detailTitle.topAnchor == list.topAnchor + 4.0),
  cx(detailTitle.leftAnchor == list.rightAnchor, constant = 18.0),
  cx(detailTitle.rightAnchor == title.rightAnchor),
  cx(detail.topAnchor == detailTitle.bottomAnchor, constant = 10.0),
  cx(detail.leftAnchor == detailTitle.leftAnchor),
  cx(detail.rightAnchor == detailTitle.rightAnchor),
)

updateDetail()
window.setContentView(root)
discard window.makeFirstResponder(list)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
