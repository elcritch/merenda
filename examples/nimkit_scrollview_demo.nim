import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Scroll View", frame = initRect(180, 160, 520, 380))
  root = newView()
  contentGuide = root.contentLayoutGuide(initEdgeInsets(22.0, 24.0, 22.0, 24.0))
  title = newTitleLabel("Scroll View")
  status = newStatusLabel("")
  scrollView = newScrollView()
  document = newView(frame = initRect(0, 0, 620, 620))
  controls = newStackView(laHorizontal)
  topButton = newButton("Top")
  middleButton = newButton("Middle")
  bottomButton = newButton("Bottom")
  topAction = actionSelector("scrollToTop")
  middleAction = actionSelector("scrollToMiddle")
  bottomAction = actionSelector("scrollToBottom")

proc updateStatus() =
  let offset = scrollView.contentOffset()
  status.text = "Offset: " & $offset.x.int & ", " & $offset.y.int

proc addDocumentRow(index: int, heading, body: string) =
  let
    y = 22.0'f32 + index.float32 * 70.0'f32
    row = newView(frame = initRect(22, y, 540, 56))
    headingLabel = newHeadingLabel(heading, frame = initRect(12, 7, 220, 20))
    bodyLabel = newStatusLabel(body, frame = initRect(12, 30, 500, 18))

  if index mod 2 == 0:
    row.background = initColor(0.92, 0.95, 0.99, 1.0)
  else:
    row.background = initColor(0.98, 0.96, 0.91, 1.0)

  row.addSubview(headingLabel, bodyLabel)
  document.addSubview(row)

proc scrollToTop(sender: DynamicAgent) =
  if sender == DynamicAgent(topButton):
    scrollView.scrollToFraction(y = 0.0)
    updateStatus()

proc scrollToMiddle(sender: DynamicAgent) =
  if sender == DynamicAgent(middleButton):
    scrollView.scrollToFraction(y = 0.5)
    updateStatus()

proc scrollToBottom(sender: DynamicAgent) =
  if sender == DynamicAgent(bottomButton):
    scrollView.scrollToFraction(y = 1.0)
    updateStatus()

root.background = initColor(0.95, 0.96, 0.98)
document.background = initColor(1.0, 1.0, 1.0, 1.0)

scrollView.documentView = document
scrollView.hasHorizontalScroller = true
scrollView.hasVerticalScroller = true
scrollView.autohidesScrollers = true
scrollView.lineScroll = 18.0

controls.spacing = 8.0
controls.alignment = svaCenter
controls.distribution = svdFill

topButton.target = newActionTarget(topAction, scrollToTop)
topButton.action = topAction
middleButton.target = newActionTarget(middleAction, scrollToMiddle)
middleButton.action = middleAction
bottomButton.target = newActionTarget(bottomAction, scrollToBottom)
bottomButton.action = bottomAction

addDocumentRow(0, "Document Header", "The document is larger than the viewport.")
addDocumentRow(1, "Notebook", "Mouse-wheel scrolling changes the content offset.")
addDocumentRow(2, "Preview", "The scroll view clips its document view.")
addDocumentRow(3, "Assets", "Horizontal scrolling is enabled for wide content.")
addDocumentRow(4, "Inspector", "Autohiding scrollers appear only when needed.")
addDocumentRow(5, "Timeline", "Programmatic scrolling uses ScrollView APIs.")
addDocumentRow(6, "Search Results", "Rows can be ordinary NimKit views.")
addDocumentRow(7, "Debug Log", "The first pass keeps scrollers lightweight.")

controls.addArrangedSubview(topButton, middleButton, bottomButton)
root.addSubview(title, status, scrollView, controls)

title.pinEdges(toGuide = contentGuide, edges = {leLeft, leTop, leRight})

activate(
  status.topAnchor.equalTo(title.bottomAnchor, constant = 8.0),
  status.leftAnchor.equalTo(title.leftAnchor),
  status.rightAnchor.equalTo(title.rightAnchor),
  scrollView.topAnchor.equalTo(status.bottomAnchor, constant = 12.0),
  scrollView.leftAnchor.equalTo(title.leftAnchor),
  scrollView.rightAnchor.equalTo(title.rightAnchor),
  controls.topAnchor.equalTo(scrollView.bottomAnchor, constant = 12.0),
  controls.leftAnchor.equalTo(title.leftAnchor),
  controls.rightAnchor.equalTo(title.rightAnchor),
  controls.bottomAnchor.equalTo(contentGuide.bottomAnchor),
)

updateStatus()
window.setContentView(root)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
