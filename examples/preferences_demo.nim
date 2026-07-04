import merenda/nimkit

import sigils/core
import sigils/selectors

type
  PreferenceRow = object
    name: string
    area: string
    value: string
    restart: string

  PreferencesController = ref object of Responder
    rows: seq[PreferenceRow]
    status: Label

const
  PreferenceButtonRowHeight = 44.0'f32
  PreferenceButtonBottomGap = PreferenceButtonRowHeight * 1.5'f32

func valueForColumn(row: PreferenceRow, column: TableColumn): string =
  if column.isNil:
    return ""
  case column.identifier
  of "name": row.name
  of "area": row.area
  of "value": row.value
  of "restart": row.restart
  else: ""

proc onOff(button: Button): string =
  if button.state == bsOn: "On" else: "Off"

proc newPreferencesController(): PreferencesController =
  result = PreferencesController(
    rows:
      @[
        PreferenceRow(
          name: "Open recent documents",
          area: "General",
          value: "Enabled",
          restart: "No",
        ),
        PreferenceRow(
          name: "Default launch view",
          area: "General",
          value: "Documents",
          restart: "No",
        ),
        PreferenceRow(
          name: "Accent intensity", area: "Appearance", value: "62%", restart: "No"
        ),
        PreferenceRow(
          name: "Reduce transparency",
          area: "Appearance",
          value: "Disabled",
          restart: "No",
        ),
        PreferenceRow(
          name: "Sync interval", area: "Accounts", value: "15 minutes", restart: "No"
        ),
        PreferenceRow(
          name: "Offline cache budget", area: "Accounts", value: "4 GB", restart: "No"
        ),
        PreferenceRow(
          name: "Developer diagnostics",
          area: "Advanced",
          value: "Verbose",
          restart: "Yes",
        ),
        PreferenceRow(
          name: "Experimental rendering path",
          area: "Advanced",
          value: "Off",
          restart: "Yes",
        ),
      ]
  )
  initResponder(result)

proc makeTabPage(): tuple[view: View, stack: StackView] =
  result.view = newView()
  result.stack = newStackView(laVertical)
  result.stack.spacing = 12.0
  result.stack.alignment = svaFill
  result.stack.distribution = svdNatural
  result.view.addSubview(result.stack)
  discard result.stack.pinEdges(
    toGuide = result.view.contentLayoutGuide(insets(18.0, 20.0, 18.0, 20.0)),
    edges = {leLeft, leTop, leRight, leBottom},
  )

proc makeSection(title: string): StackView =
  result = newStackView(laVertical)
  result.spacing = 8.0
  result.alignment = svaFill
  result.distribution = svdNatural
  result.addArrangedSubview(newHeadingLabel(title))

proc makeFieldRow(labelText: string, control: View): StackView =
  result = newStackView(laHorizontal)
  result.spacing = 12.0
  result.alignment = svaCenter
  result.distribution = svdFill
  result.addArrangedSubview(newFormLabel(labelText), control)

proc addScrollDocumentRow(document: View, index: int, heading, detail: string) =
  let
    y = 12.0'f32 + index.float32 * 54.0'f32
    row = newView(frame = rect(12, y, 520, 44))
    title = newHeadingLabel(heading, frame = rect(12, 4, 220, 18))
    body = newStatusLabel(detail, frame = rect(12, 24, 460, 16))
  row.addSubviews(autoNames(title, body))
  document.addSubview(row)

protocol PreferenceTableDataSource of TableViewDataSource:
  method numberOfRows(source: PreferencesController, tableView: TableView): int =
    source.rows.len

  method textForCell(
      source: PreferencesController, tableView: TableView, row: int, column: TableColumn
  ): string =
    if row in 0 ..< source.rows.len:
      source.rows[row].valueForColumn(column)
    else:
      ""

let
  app = sharedApplication()
  window = newWindow("NimKit Preferences Demo", frame = rect(120, 90, 810, 544))
  root = newView()
  contentGuide = root.contentLayoutGuide(insets(26.0, 32.0, 24.0, 32.0))
  controller = newPreferencesController()
  title = newTitleLabel("Preferences")
  status = newStatusLabel("Adjust preferences to update this summary.")
  tabView = newTabView()
  resetButton = newButton("Reset")
  applyButton = newButton("Apply")
  buttonBox = newDialogButtonBox(
    [
      initDialogButtonSpec(resetButton, dbrReset),
      initDialogButtonSpec(applyButton, dbrApply),
    ]
  )

controller.status = status

let generalPage = makeTabPage()
let identitySection = makeSection("Identity")
let behaviorSection = makeSection("Startup Behavior")
let updateSection = makeSection("Update Channel")
let userNameField = newTextField("Ada")
let emailField = newTextField("ada@example.test")
let launchChoice = newComboBox(["Documents", "Last workspace", "Empty window"])
let recentCheck = newCheckBox("Open recent documents")
let notificationCheck = newCheckBox("Show notification badges")
let confirmQuitCheck = newCheckBox("Ask before quitting")
let stableRadio = newRadioButton("Stable")
let betaRadio = newRadioButton("Beta")
let nightlyRadio = newRadioButton("Nightly")

launchChoice.selectItemAtIndex(0)
recentCheck.state = bsOn
notificationCheck.state = bsOn
confirmQuitCheck.state = bsOff
stableRadio.state = bsOn

identitySection.addArrangedSubview(
  makeFieldRow("Full name", userNameField), makeFieldRow("Email", emailField)
)
behaviorSection.addArrangedSubview(
  makeFieldRow("Launch into", launchChoice),
  recentCheck,
  notificationCheck,
  confirmQuitCheck,
)
updateSection.addArrangedSubview(stableRadio, betaRadio, nightlyRadio)
generalPage.stack.addArrangedSubview(identitySection, behaviorSection, updateSection)
generalPage.stack.addFlexibleSpacer()

let appearancePage = makeTabPage()
let themeSection = makeSection("Theme")
let tabsSection = makeSection("Tabs")
let accentSection = makeSection("Accent")
let themeProfile = newComboBox(["System default", "Synthwave 83", "Peachy"])
let tabStyleChoice = newComboBox(["Inset", "Traditional"])
let transparencyCheck = newCheckBox("Reduce transparency")
let animatedAccentSwitch = newSwitchButton(true)
let accentSlider = newSlider(0.0, 100.0, 62.0)
let accentValue = newStatusLabel("Accent intensity: 62%")

themeProfile.selectItemAtIndex(0)
tabStyleChoice.selectItemAtIndex(0)
transparencyCheck.state = bsOff
accentSlider.stepValue = 1.0
themeSection.addArrangedSubview(makeFieldRow("Theme profile", themeProfile))
tabsSection.addArrangedSubview(makeFieldRow("Tab style", tabStyleChoice))
accentSection.addArrangedSubview(
  transparencyCheck,
  makeFieldRow("Animated accent", animatedAccentSwitch),
  accentSlider,
  accentValue,
)
appearancePage.stack.addArrangedSubview(themeSection, tabsSection, accentSection)
appearancePage.stack.addFlexibleSpacer()

let accountsPage = makeTabPage()
let syncSection = makeSection("Sync")
let cacheSection = makeSection("Storage")
let syncSwitch = newSwitchButton(true)
let intervalChoice = newComboBox(["5 minutes", "15 minutes", "Hourly", "Manual"])
let cacheSlider = newSlider(1.0, 12.0, 4.0)
let cacheValue = newStatusLabel("Offline cache: 4 GB")
let syncDocument = newView(frame = rect(0, 0, 560, 390))
let syncScrollView =
  newScrollView(frame = rect(0, 0, 560, 170), documentView = syncDocument)

intervalChoice.selectItemAtIndex(1)
cacheSlider.stepValue = 1.0
syncScrollView.hasVerticalScroller = true
syncScrollView.hasHorizontalScroller = false
syncScrollView.autohidePolicy = sapWhenNeeded
syncScrollView.borderType = svbLineBorder
syncScrollView.drawsBackground = true
syncScrollView.verticalLineScroll = 18.0
syncScrollView.verticalPageScroll = 120.0
addScrollDocumentRow(
  syncDocument, 0, "Documents",
  "Keep project notes and preference exports available offline.",
)
addScrollDocumentRow(
  syncDocument, 1, "Window Layouts", "Sync saved workspaces between devices."
)
addScrollDocumentRow(
  syncDocument, 2, "Theme Presets", "Download custom theme overrides on launch."
)
addScrollDocumentRow(
  syncDocument, 3, "Key Bindings", "Share keyboard shortcuts with signed-in devices."
)
addScrollDocumentRow(
  syncDocument, 4, "Diagnostics", "Attach recent logs when reporting rendering issues."
)
addScrollDocumentRow(
  syncDocument, 5, "Local Snapshots", "Retain the last ten preference revisions."
)
syncSection.addArrangedSubview(
  makeFieldRow("Enable sync", syncSwitch),
  makeFieldRow("Sync interval", intervalChoice),
  syncScrollView,
)
cacheSection.addArrangedSubview(cacheSlider, cacheValue)
accountsPage.stack.addArrangedSubview(syncSection, cacheSection)
accountsPage.stack.addFlexibleSpacer()

let advancedPage = makeTabPage()
let tableSection = makeSection("Advanced Settings")
let preferencesTable = newTableView(frame = rect(0, 0, 760, 230))
let advancedHint = newStatusLabel(
  "Resize columns, scroll horizontally, and select rows to inspect themed table chrome."
)

preferencesTable.addColumn(newTableColumn("name", "Preference", width = 260.0))
preferencesTable.addColumn(newTableColumn("area", "Area", width = 140.0))
preferencesTable.addColumn(newTableColumn("value", "Value", width = 180.0))
preferencesTable.addColumn(newTableColumn("restart", "Restart", width = 110.0))
preferencesTable.rowHeight = 28.0
preferencesTable.allowsColumnSelection = true
preferencesTable.dataSource = controller
tableSection.addArrangedSubview(preferencesTable, advancedHint)
advancedPage.stack.addArrangedSubview(tableSection)
advancedPage.stack.addFlexibleSpacer()

tabView.tabMode = tvmInset
tabView.allowsTabDragging = true
tabView.addTabViewItem(newTabViewItem("General", generalPage.view, "general"))
tabView.addTabViewItem(newTabViewItem("Appearance", appearancePage.view, "appearance"))
tabView.addTabViewItem(newTabViewItem("Accounts", accountsPage.view, "accounts"))
tabView.addTabViewItem(newTabViewItem("Advanced", advancedPage.view, "advanced"))

proc chooseUpdateChannel(index: int) =
  stableRadio.state = if index == 0: bsOn else: bsOff
  betaRadio.state = if index == 1: bsOn else: bsOff
  nightlyRadio.state = if index == 2: bsOn else: bsOff

proc updateSummary() =
  accentValue.text = "Accent intensity: " & $accentSlider.value.int & "%"
  cacheValue.text = "Offline cache: " & $cacheSlider.value.int & " GB"
  controller.status.text =
    "User: " & userNameField.stringValue & " / Launch: " & launchChoice.stringValue &
    " / Recent: " & recentCheck.onOff() & " / Theme profile: " & themeProfile.stringValue &
    " / Cache: " & $cacheSlider.value.int & " GB"

proc resetPreferences(sender: DynamicAgent) =
  discard sender
  userNameField.text = "Ada"
  emailField.text = "ada@example.test"
  launchChoice.selectItemAtIndex(0)
  themeProfile.selectItemAtIndex(0)
  tabStyleChoice.selectItemAtIndex(0)
  recentCheck.state = bsOn
  notificationCheck.state = bsOn
  confirmQuitCheck.state = bsOff
  transparencyCheck.state = bsOff
  chooseUpdateChannel(0)
  accentSlider.value = 62.0
  intervalChoice.selectItemAtIndex(1)
  cacheSlider.value = 4.0
  tabView.tabMode = tvmInset
  updateSummary()

proc applyPreferences(sender: DynamicAgent) =
  discard sender
  updateSummary()
  controller.status.text = "Applied preferences. " & controller.status.text

proc setTabStyleFromCombo(sender: DynamicAgent) =
  discard sender
  if tabStyleChoice.indexOfSelectedItem() == 1:
    tabView.tabMode = tvmTraditional
  else:
    tabView.tabMode = tvmInset
  updateSummary()

proc connectButton(
    button: Button, actionName: string, callback: proc(sender: DynamicAgent)
) =
  let action = actionSelector(actionName)
  button.target = newActionTarget(action, callback)
  button.action = action

proc connectCombo(
    comboBox: ComboBox, actionName: string, callback: proc(sender: DynamicAgent)
) =
  let action = actionSelector(actionName)
  comboBox.target = newActionTarget(action, callback)
  comboBox.action = action

proc preferenceTextChanged(field: TextField, sender: DynamicAgent) {.slot.} =
  discard field
  discard sender
  updateSummary()

proc preferenceSliderChanged(slider: Slider, sender: DynamicAgent) {.slot.} =
  discard slider
  discard sender
  updateSummary()

connectButton(resetButton, "resetPreferences", resetPreferences)
connectButton(applyButton, "applyPreferences", applyPreferences)
connectCombo(
  launchChoice,
  "launchPreferenceChanged",
  proc(sender: DynamicAgent) =
    discard sender
    updateSummary(),
)
connectCombo(
  themeProfile,
  "themeProfileChanged",
  proc(sender: DynamicAgent) =
    discard sender
    updateSummary(),
)
connectCombo(
  intervalChoice,
  "syncIntervalChanged",
  proc(sender: DynamicAgent) =
    discard sender
    updateSummary(),
)
connectCombo(tabStyleChoice, "tabStyleChanged", setTabStyleFromCombo)

connectButton(
  stableRadio,
  "stableChannel",
  proc(sender: DynamicAgent) =
    discard sender
    chooseUpdateChannel(0)
    updateSummary(),
)
connectButton(
  betaRadio,
  "betaChannel",
  proc(sender: DynamicAgent) =
    discard sender
    chooseUpdateChannel(1)
    updateSummary(),
)
connectButton(
  nightlyRadio,
  "nightlyChannel",
  proc(sender: DynamicAgent) =
    discard sender
    chooseUpdateChannel(2)
    updateSummary(),
)

for button in [recentCheck, notificationCheck, confirmQuitCheck, transparencyCheck]:
  connectButton(
    button,
    "preferenceCheckboxChanged",
    proc(sender: DynamicAgent) =
      discard sender
      updateSummary(),
  )

userNameField.connect(textDidChange, userNameField, preferenceTextChanged)
emailField.connect(textDidChange, emailField, preferenceTextChanged)
accentSlider.connect(actionDidSend, accentSlider, preferenceSliderChanged)
cacheSlider.connect(actionDidSend, cacheSlider, preferenceSliderChanged)

root.addSubviews(autoNames(title, status, tabView, buttonBox))
title.pinEdges(toGuide = contentGuide, edges = {leLeft, leTop, leRight})
activateConstraints:
  status[atTop] == title[atBottom] + 10.0
  status[atLeft] == title[atLeft]
  status[atRight] == title[atRight]
  tabView[atTop] == status[atBottom] + 14.0
  tabView[atLeft] == title[atLeft]
  tabView[atRight] == title[atRight]
  tabView[atBottom] == buttonBox[atTop] - 12.0
  buttonBox[atLeft] == title[atLeft]
  buttonBox[atRight] == title[atRight]
  buttonBox[atHeight] == PreferenceButtonRowHeight
  buttonBox[atBottom] == contentGuide[atBottom] - PreferenceButtonBottomGap

updateSummary()
app.runWindow(window, root)
