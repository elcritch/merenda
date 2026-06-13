import merenda/nimkit

import sigils/core
import sigils/selectors

type TabDemoDelegate = ref object of Responder
  status: TextField

protocol TabDemoDelegateProtocol of TabViewDelegate:
  method didSelectTabViewItem(
      delegate: TabDemoDelegate, tabView: TabView, item: TabViewItem
  ) =
    discard tabView
    if not delegate.status.isNil:
      delegate.status.text = "Selected tab: " & item.label

proc newTabDemoDelegate(status: TextField): TabDemoDelegate =
  result = TabDemoDelegate(status: status)
  initResponder(result)
  discard result.withProtocol(TabDemoDelegateProtocol)

proc paneStack(): StackView =
  result = newStackView(laVertical)
  result.background = initColor(0.98, 0.98, 0.96, 0.0)
  result.edgeInsets = initEdgeInsets(18.0, 20.0)
  result.spacing = 12.0
  result.alignment = svaFill

proc generalPane(): View =
  let
    stack = paneStack()
    title = newHeadingLabel("General")
    summary = newTextField("Application preferences live in tab view items.")
    option = newCheckBox("Open recent documents on launch")
    button = newButton("Reset Warnings")

  summary.editable = false
  summary.selectable = false
  option.state = bsOn
  stack.addArrangedSubview(title, summary, option, button)
  stack.addFlexibleSpacer()
  stack

proc editorPane(): View =
  let
    stack = paneStack()
    title = newHeadingLabel("Editor")
    form = newFormView()
    fontLabel = newFormLabel("Font")
    fontField = newTextField("IBM Plex Sans 13")
    wrapLabel = newFormLabel("Wrapping")
    wrapPopup = newComboBox(["None", "Word", "Character"])
    spaces = newCheckBox("Show invisible characters")

  form.edgeInsets = initEdgeInsets(0.0)
  form.spacing[dcol] = 12.0
  form.spacing[drow] = 10.0
  form.minFieldWidth = 220.0
  wrapPopup.selectedIndex = 1
  form.addRow(fontLabel, fontField)
  form.addRow(wrapLabel, wrapPopup)
  form.addRow(newFormLabel("Options"), spaces)

  stack.addArrangedSubview(title, form)
  stack.addFlexibleSpacer()
  stack

proc accountPane(): View =
  let
    stack = paneStack()
    title = newHeadingLabel("Account")
    name = newTextField("Ada Lovelace")
    email = newTextField("ada@example.com")
    sync = newCheckBox("Sync preferences across devices")
    save = newButton("Save Account")

  sync.state = bsOn
  stack.addArrangedSubview(title, newFormLabel("Display Name"), name)
  stack.addArrangedSubview(newFormLabel("Email"), email, sync, save)
  stack.addFlexibleSpacer()
  stack

let
  app = sharedApplication()
  window = newWindow("NimKit Tab View Demo", frame = initRect(160, 160, 560, 360))
  root = newView()
  layout = newStackView(laVertical)
  header = newTitleLabel("Tab View Demo")
  status = newStatusLabel("Selected tab: General")
  tabView = newTabView()
  controls = newStackView(laHorizontal)
  previousButton = newButton("Previous")
  nextButton = newButton("Next")
  bottomTabs = newCheckBox("Tabs on bottom")
  previousAction = actionSelector("selectPreviousTab")
  nextAction = actionSelector("selectNextTab")
  positionAction = actionSelector("toggleTabPosition")

proc updateStatus() =
  let item = tabView.selectedTabViewItem()
  if item.isNil:
    status.text = "No selected tab"
  else:
    status.text = "Selected tab: " & item.label

proc selectPrevious(sender: DynamicAgent) =
  discard sender
  discard tabView.selectPreviousTabViewItem()
  updateStatus()

proc selectNext(sender: DynamicAgent) =
  discard sender
  discard tabView.selectNextTabViewItem()
  updateStatus()

proc toggleTabPosition(sender: DynamicAgent) =
  discard sender
  if bottomTabs.state == bsOn:
    tabView.tabPosition = tpBottom
  else:
    tabView.tabPosition = tpTop
  updateStatus()

root.background = initColor(0.95, 0.96, 0.98)
layout.spacing = 12.0
layout.alignment = svaFill
layout.edgeInsets = initEdgeInsets(22.0, 24.0)

controls.spacing = 8.0
controls.alignment = svaCenter
controls.distribution = svdNatural

discard tabView.addTabViewItem(newTabViewItem("General", generalPane(), "general"))
discard tabView.addTabViewItem(newTabViewItem("Editor", editorPane(), "editor"))
discard tabView.addTabViewItem(newTabViewItem("Account", accountPane(), "account"))
let disabledItem = newTabViewItem("Disabled", paneStack(), "disabled")
disabledItem.enabled = false
discard tabView.addTabViewItem(disabledItem)
tabView.delegate = newTabDemoDelegate(status)

previousButton.target = newActionTarget(previousAction, selectPrevious)
previousButton.action = previousAction
nextButton.target = newActionTarget(nextAction, selectNext)
nextButton.action = nextAction
bottomTabs.target = newActionTarget(positionAction, toggleTabPosition)
bottomTabs.action = positionAction

controls.addArrangedSubview(previousButton, nextButton, bottomTabs)
controls.addFlexibleSpacer()

layout.addArrangedSubview(header, status, tabView, controls)
root.addSubview(layout)

layout.pinEdges(toGuide = root.contentLayoutGuide(), edges = {leLeft, leTop, leRight})
tabView.heightAnchor.equalTo(210.0).active = true

window.setContentView(root)
discard window.makeFirstResponder(tabView)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
