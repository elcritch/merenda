import std/[unicode, unittest]

import sigils/core

import figdraw/fignodes

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes

type
  TabDelegateSpy = ref object of Responder
    allowSecond: bool
    shouldCount: int
    didCount: int
    lastItem: TabViewItem

  TabViewDemoFixture = object
    root: View
    tabView: TabView

protocol TabDelegateSpyProtocol of TabViewDelegate:
  method shouldSelectTabViewItem(
      spy: TabDelegateSpy, tabView: TabView, item: TabViewItem
  ): bool =
    discard tabView
    inc spy.shouldCount
    item.label != "Second" or spy.allowSecond

  method didSelectTabViewItem(
      spy: TabDelegateSpy, tabView: TabView, item: TabViewItem
  ) =
    discard tabView
    inc spy.didCount
    spy.lastItem = item

proc newTabDelegateSpy(): TabDelegateSpy =
  result = TabDelegateSpy()
  initResponder(result)
  discard result.withProtocol(TabDelegateSpyProtocol)

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add(rune)

func screenBoxClose(node: Fig, rect: nimkitTypes.Rect): bool =
  abs(node.screenBox.x - rect.origin.x) <= 0.01'f32 and
    abs(node.screenBox.y - rect.origin.y) <= 0.01'f32 and
    abs(node.screenBox.w - rect.size.width) <= 0.01'f32 and
    abs(node.screenBox.h - rect.size.height) <= 0.01'f32

func drawsOpaquePanelFill(node: Fig, rect: nimkitTypes.Rect): bool =
  node.kind == nkRectangle and node.screenBoxClose(rect)

proc newTabViewDemoPane(): View =
  let
    stack = newStackView(laVertical)
    title = newHeadingLabel("General")
    summary = newTextField("Application preferences live in tab view items.")
    option = newCheckBox("Open recent documents on launch")
    button = newButton("Reset Warnings")

  stack.background = initColor(0.98, 0.98, 0.96, 0.0)
  stack.edgeInsets = insets(18.0, 20.0)
  stack.spacing = 12.0
  stack.alignment = svaFill

  summary.editable = false
  summary.selectable = false
  option.state = bsOn
  stack.addArrangedSubview(title, summary, option, button)
  stack.addFlexibleSpacer()
  View(stack)

proc newTabViewDemoFixture(): TabViewDemoFixture =
  let
    root = newView()
    layout = newStackView(laVertical)
    header = newTitleLabel("Tab View Demo")
    status = newStatusLabel("Selected tab: General")
    tabView = newTabView()
    controls = newStackView(laHorizontal)
    disabledItem = newTabViewItem("Disabled", newStackView(laVertical), "disabled")

  root.background = initColor(0.95, 0.96, 0.98)
  layout.spacing = 12.0
  layout.alignment = svaFill
  layout.edgeInsets = insets(22.0, 24.0)

  controls.spacing = 8.0
  controls.alignment = svaCenter
  controls.distribution = svdNatural
  controls.setHuggingPriority(LayoutPriorityRequired, laVertical)
  controls.setCompressionPriority(LayoutPriorityRequired, laVertical)
  tabView.setHuggingPriority(LayoutPriorityLow, laVertical)
  tabView.setCompressionPriority(LayoutPriorityLow, laVertical)

  discard
    tabView.addTabViewItem(newTabViewItem("General", newTabViewDemoPane(), "general"))
  discard
    tabView.addTabViewItem(newTabViewItem("Editor", newTabViewDemoPane(), "editor"))
  discard
    tabView.addTabViewItem(newTabViewItem("Account", newTabViewDemoPane(), "account"))
  disabledItem.enabled = false
  discard tabView.addTabViewItem(disabledItem)

  controls.addArrangedSubview(
    newButton("Previous"), newButton("Next"), newCheckBox("Tabs on bottom")
  )
  controls.addFlexibleSpacer()

  layout.addArrangedSubview(header, status, tabView, controls)
  root.addSubview(layout)
  layout.pinEdges(
    toGuide = root.contentLayoutGuide(), edges = {leLeft, leTop, leRight, leBottom}
  )
  TabViewDemoFixture(root: root, tabView: tabView)

suite "nimkit tab views":
  test "tab view items select content views through lifecycle helpers":
    let
      tabView = newTabView(frame = initRect(0, 0, 320, 180))
      firstView = newView()
      secondView = newView()
      first = newTabViewItem("First", firstView, "first")
      second = newTabViewItem("Second", secondView, "second")

    discard tabView.addTabViewItem(first)
    discard tabView.addTabViewItem(second)

    check tabView.len == 2
    check tabView[0] == first
    check tabView.selectedIndex == 0
    check tabView.selectedTabViewItem == first
    check firstView.superview == View(tabView)
    check secondView.superview.isNil

    tabView.layoutSubtreeIfNeeded()
    check firstView.frame == tabView.contentViewRect()

    check tabView.selectTabViewItem(second)
    check tabView.selectedIndex == 1
    check firstView.superview.isNil
    check secondView.superview == View(tabView)

    check tabView.removeTabViewItem(second)
    check tabView.len == 1
    check tabView.selectedTabViewItem == first
    check firstView.superview == View(tabView)
    check secondView.superview.isNil

  test "tab view delegates can veto selection and observe changes":
    let
      tabView = newTabView(frame = initRect(0, 0, 320, 180))
      first = newTabViewItem("First", newView())
      second = newTabViewItem("Second", newView())
      spy = newTabDelegateSpy()

    tabView.delegate = spy
    discard tabView.addTabViewItem(first)
    discard tabView.addTabViewItem(second)

    check not tabView.selectTabViewItem(second)
    check tabView.selectedTabViewItem == first
    check spy.shouldCount == 1
    check spy.didCount == 0

    spy.allowSecond = true
    check tabView.selectTabViewItem(second)
    check tabView.selectedTabViewItem == second
    check spy.shouldCount == 2
    check spy.didCount == 1
    check spy.lastItem == second

  test "tab view mouse and keyboard selection skip disabled tabs":
    let
      tabView = newTabView(frame = initRect(0, 0, 360, 180))
      first = newTabViewItem("First", newView())
      disabled = newTabViewItem("Disabled", newView())
      third = newTabViewItem("Third", newView())

    disabled.enabled = false
    discard tabView.addTabViewItem(first)
    discard tabView.addTabViewItem(disabled)
    discard tabView.addTabViewItem(third)

    let disabledRect = tabView.tabRect(1)
    check not tabView.clickAt(
      initPoint(disabledRect.origin.x + 6, disabledRect.origin.y + 6)
    )
    check tabView.selectedTabViewItem == first

    check tabView.keyDown(KeyEvent(key: keyArrowRight))
    check tabView.selectedTabViewItem == third

    check tabView.keyDown(KeyEvent(key: keyArrowLeft))
    check tabView.selectedTabViewItem == first

    let thirdRect = tabView.tabRect(2)
    check tabView.clickAt(initPoint(thirdRect.origin.x + 6, thirdRect.origin.y + 6))
    check tabView.selectedTabViewItem == third

  test "arrow keys in selected pane child keep focus in the pane":
    let
      window = newWindow("Tab pane focus", frame = initRect(0, 0, 360, 180))
      root = newView(frame = initRect(0, 0, 360, 180))
      tabView = newTabView(frame = initRect(0, 0, 360, 180))
      firstPane = newStackView(laVertical)
      secondPane = newStackView(laVertical)
      firstButton = newButton("First option")
      secondButton = newButton("Second option")
      first = newTabViewItem("First", firstPane, "first")
      second = newTabViewItem("Second", secondPane, "second")

    firstPane.addArrangedSubview(firstButton)
    secondPane.addArrangedSubview(secondButton)
    discard tabView.addTabViewItem(first)
    discard tabView.addTabViewItem(second)
    root.addSubview(tabView)
    window.setContentView(root)

    check window.makeFirstResponder(tabView)
    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord)
    )
    check tabView.selectedTabViewItem == second

    check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.firstResponder == secondButton
    check secondButton.isFocused
    check secondButton.window == window

    check not window.dispatchKeyDown(
      KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord)
    )
    check tabView.selectedTabViewItem == second
    check window.firstResponder == secondButton
    check secondButton.isFocused
    check secondButton.isFocusVisible
    check secondButton.window == window

  test "tab view exposes top and bottom geometry":
    let tabView = newTabView(frame = initRect(0, 0, 320, 180))
    discard tabView.addTabViewItem(newTabViewItem("Top", newView()))

    check tabView.contentRect.origin.y == 12.0
    check tabView.tabRect(0).origin.y == 2.0

    tabView.tabPosition = tpBottom
    check tabView.contentRect.origin.y == 0.0
    check tabView.tabRect(0).origin.y == 158.0

  test "tab view intrinsic height includes child pane content":
    let
      tabView = newTabView(frame = initRect(0, 0, 320, 180))
      pane = newStackView(laVertical)

    pane.edgeInsets = insets(18.0, 20.0)
    pane.spacing = 12.0
    pane.alignment = svaFill
    pane.addArrangedSubview(newHeadingLabel("Account"))
    pane.addArrangedSubview(newFormLabel("Display Name"))
    pane.addArrangedSubview(newTextField("Ada Lovelace"))
    pane.addArrangedSubview(newFormLabel("Email"))
    pane.addArrangedSubview(newTextField("ada@example.com"))
    pane.addArrangedSubview(newCheckBox("Sync preferences across devices"))
    pane.addArrangedSubview(newButton("Save Account"))
    discard tabView.addTabViewItem(newTabViewItem("Account", pane))

    let
      paneHeight = pane
        .resolvedIntrinsicContentSize()
        .resolveIntrinsicSize(initSize(0.0, 0.0)).height
      tabHeight = tabView
        .resolvedIntrinsicContentSize()
        .resolveIntrinsicSize(initSize(0.0, 0.0)).height

    check tabHeight > 120.0'f32
    tabView.frame = initRect(0, 0, 320, tabHeight)
    tabView.layoutSubtreeIfNeeded()
    check pane.frame.size.height >= paneHeight - 0.01'f32

  test "tab view renders panel tab labels and selected content":
    let
      tabView = newTabView(frame = initRect(0, 0, 320, 180))
      content = newView()
      item = newTabViewItem("General", content)

    content.background = initColor(0.20, 0.40, 0.80)
    discard tabView.addTabViewItem(item)

    let renders = buildRenders(tabView)
    var
      labelFound = false
      panelFound = false
      contentFound = false

    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkText:
        labelFound = true
        check node.screenBox.y < tabView.contentRect.origin.y
      if node.kind == nkRectangle and node.screenBox.y == tabView.contentRect.origin.y and
          node.screenBox.w == 320.0:
        panelFound = true
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == initColor(0.20, 0.40, 0.80).rgba:
        contentFound = true

    check labelFound
    check panelFound
    check contentFound

  test "tab face fill comes from selected chrome":
    let
      appearance = initAppearance()
      baseFill = fill(initColor(0.98, 0.98, 0.96, 1.0))
      highlightFill = fill(initColor(0.82, 0.84, 0.88, 0.73))
      selectedAqua = appearance.chromeFill(
        chromeContext(AquaChromeName, crTab, cpFace, baseFill, {ssSelected})
      )
      highlightAqua = appearance.chromeFill(
        chromeContext(AquaChromeName, crTab, cpHighlight, highlightFill)
      )
      defaultChrome = appearance.chromeFill(
        chromeContext(DefaultChromeName, crTab, cpFace, baseFill, {ssSelected})
      )

    check selectedAqua.kind == flLinear3
    check selectedAqua.lin3.stop == initColor(0.94, 0.94, 0.92, 1.0).rgba
    check highlightAqua == highlightFill
    check defaultChrome == baseFill

  test "selected tab only rounds the edge away from the pane":
    let tabView = newTabView(frame = initRect(0, 0, 320, 180))
    tabView.tabMode = tvmTraditional
    discard tabView.addTabViewItem(newTabViewItem("General", newView()))

    var topTabFound = false
    for node in buildRenders(tabView)[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.screenBoxClose(tabView.tabRect(0)):
        topTabFound = true
        check node.corners[dcTopLeft] > 0'u16
        check node.corners[dcTopRight] > 0'u16
        check node.corners[dcBottomLeft] == 0'u16
        check node.corners[dcBottomRight] == 0'u16
    check topTabFound

    tabView.tabPosition = tpBottom
    var bottomTabFound = false
    for node in buildRenders(tabView)[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.screenBoxClose(tabView.tabRect(0)):
        bottomTabFound = true
        check node.corners[dcTopLeft] == 0'u16
        check node.corners[dcTopRight] == 0'u16
        check node.corners[dcBottomLeft] > 0'u16
        check node.corners[dcBottomRight] > 0'u16
    check bottomTabFound

  test "tab view selected pane does not redraw panel over resized content":
    let fixture = newTabViewDemoFixture()

    fixture.root.frame = initRect(0, 0, 560, 500)
    let
      renders = buildRenders(fixture.root)
      panelRect = fixture.tabView.rectToWindow(fixture.tabView.contentRect())

    var
      panelFillCount = 0
      resetWarningsTextFound = false

    for node in renders[DefaultDrawLevel].nodes:
      if node.drawsOpaquePanelFill(panelRect):
        inc panelFillCount
      if node.kind == nkText and node.renderedText() == "Reset Warnings":
        resetWarningsTextFound = true

    check panelFillCount == 1
    check resetWarningsTextFound
