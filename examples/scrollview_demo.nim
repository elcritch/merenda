import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Scroll View", frame = initRect(180, 160, 520, 380))
  root = newView()
  contentGuide = root.contentLayoutGuide(initEdgeInsets(22.0, 24.0, 22.0, 24.0))
  title = newTitleLabel("Scroll View")
  status = newStatusLabel("")
  details = newStatusLabel("")
  scrollView = newScrollView()
  document = newView(frame = initRect(0, 0, 760, 660))
  headerView = newStatusLabel(
    "  Document header view - scroller insets, border, background, and headers are owned by ScrollView",
    frame = initRect(0, 0, 760, 24),
  )
  cornerView = newStatusLabel("Corner", frame = initRect(0, 0, 72, 24))
  controls = newStackView(laHorizontal)
  topButton = newButton("Top")
  middleButton = newButton("Middle")
  bottomButton = newButton("Bottom")
  rightButton = newButton("Right Edge")
  topAction = actionSelector("scrollToTop")
  middleAction = actionSelector("scrollToMiddle")
  bottomAction = actionSelector("scrollToBottom")
  rightAction = actionSelector("scrollToRightEdge")

proc updateStatus() =
  let offset = scrollView.contentOffset()
  let visible = scrollView.clipView().documentVisibleRect()
  status.text =
    "Offset: " & $offset.x.int & ", " & $offset.y.int & "  visible: " &
    $visible.size.width.int & " x " & $visible.size.height.int
  details.text =
    "line scroll H/V: " & $scrollView.horizontalLineScroll().int & "/" &
    $scrollView.verticalLineScroll().int & "  page scroll H/V: " &
    $scrollView.horizontalPageScroll().int & "/" & $scrollView.verticalPageScroll().int

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

proc scrollToRightEdge(sender: DynamicAgent) =
  if sender == DynamicAgent(rightButton):
    scrollView.scrollToFraction(x = 1.0)
    updateStatus()

root.background = initColor(0.95, 0.96, 0.98)
document.background = initColor(1.0, 1.0, 1.0, 1.0)
headerView.background = initColor(0.88, 0.91, 0.96, 1.0)
cornerView.background = initColor(0.82, 0.87, 0.94, 1.0)

scrollView.documentView = document
scrollView.hasHorizontalScroller = true
scrollView.hasVerticalScroller = true
scrollView.autohidePolicy = sapWhenNeeded
scrollView.horizontalLineScroll = 28.0
scrollView.verticalLineScroll = 18.0
scrollView.horizontalPageScroll = 180.0
scrollView.verticalPageScroll = 140.0
scrollView.borderType = svbLineBorder
scrollView.drawsBackground = true
scrollView.scrollerInsets = initEdgeInsets(4.0, 4.0, 4.0, 4.0)
scrollView.horizontalHeaderView = headerView
scrollView.cornerView = cornerView
scrollView.setRulerPlaceholder(
  laHorizontal, initRulerPlaceholder(visible = true, thickness = 18.0)
)
scrollView.dynamicScrolling = true

controls.spacing = 8.0
controls.alignment = svaCenter
controls.distribution = svdFill

topButton.target = newActionTarget(topAction, scrollToTop)
topButton.action = topAction
middleButton.target = newActionTarget(middleAction, scrollToMiddle)
middleButton.action = middleAction
bottomButton.target = newActionTarget(bottomAction, scrollToBottom)
bottomButton.action = bottomAction
rightButton.target = newActionTarget(rightAction, scrollToRightEdge)
rightButton.action = rightAction

addDocumentRow(0, "Document Header", "The document is larger than the viewport.")
addDocumentRow(
  1, "Clip View",
  "scrollToPoint and constrained content offsets are routed through ClipView.",
)
addDocumentRow(
  2, "Preview",
  "The scroll view clips its document view and reports the visible document rect.",
)
addDocumentRow(
  3, "Assets", "Horizontal scrolling has its own line and page increments."
)
addDocumentRow(
  4, "Inspector", "Autohide policy is explicit: never, when needed, or always hidden."
)
addDocumentRow(
  5, "Timeline", "Border, background, and scroller insets are ScrollView chrome policy."
)
addDocumentRow(
  6, "Header", "Header and corner views are plumbed in as owned chrome views."
)
addDocumentRow(
  7, "Rulers",
  "Ruler placeholders store visibility and thickness before native rulers exist.",
)
addDocumentRow(
  8, "Autoscroll",
  "ClipView autoscroll uses axis line-scroll values near the viewport edge.",
)
addDocumentRow(
  9, "Debug Log",
  "Dynamic scrolling is stored separately from scroller visibility policy.",
)

controls.addArrangedSubview(topButton, middleButton, bottomButton, rightButton)
root.addSubview(title, status, details, scrollView, controls)

title.pinEdges(toGuide = contentGuide, edges = {leLeft, leTop, leRight})

activate(
  status[atTop].equalTo(title[atBottom], constant = 8.0),
  status[atLeft].equalTo(title[atLeft]),
  status[atRight].equalTo(title[atRight]),
  details[atTop].equalTo(status[atBottom], constant = 4.0),
  details[atLeft].equalTo(title[atLeft]),
  details[atRight].equalTo(title[atRight]),
  scrollView[atTop].equalTo(details[atBottom], constant = 12.0),
  scrollView[atLeft].equalTo(title[atLeft]),
  scrollView[atRight].equalTo(title[atRight]),
  controls[atTop].equalTo(scrollView[atBottom], constant = 12.0),
  controls[atLeft].equalTo(title[atLeft]),
  controls[atRight].equalTo(title[atRight]),
  controls[atBottom].equalTo(contentGuide[atBottom]),
)

updateStatus()
window.setContentView(root)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
