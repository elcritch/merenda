import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Combo Scroll Demo", frame = initRect(180, 160, 520, 360))
  root = newView()

  title = newTitleLabel("Scrollable Combo Box")
  status = newStatusLabel("")

  projectLabel = newFormLabel("Project")
  projectChoice = newComboBox(
    [
      "NimKit", "Merenda", "FigDraw", "Kiwiberry", "Cocoatron", "Cocoa", "GNUstep",
      "Atlas", "Sigils", "Siwin", "Pixie", "Chroma",
    ]
  )

  sizeLabel = newFormLabel("Size")
  sizeChoice = newComboBox(
    [
      "Compact", "Small", "Regular", "Large", "Inspector", "Palette", "Preferences",
      "Dashboard",
    ]
  )

  changedAction = actionSelector("comboScrollChoiceChanged")

proc updateStatus() =
  status.text =
    "Project: " & projectChoice.stringValue & " / Size: " & sizeChoice.stringValue

proc onChanged(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

let target = newActionTarget(changedAction, onChanged)

root.background = initColor(0.95, 0.96, 0.98)

projectChoice.maxVisibleItems = 5
projectChoice.itemHeight = 22.0
projectChoice.popupPresentation = ppInline
projectChoice.selectedIndex = 0
projectChoice.popupOpen = true

sizeChoice.maxVisibleItems = 4
sizeChoice.itemHeight = 22.0
sizeChoice.selectedIndex = 2

for combo in [projectChoice, sizeChoice]:
  combo.target = target
  combo.action = changedAction

root.addSubview(title, status, projectLabel, projectChoice, sizeLabel, sizeChoice)

activate(
  title[anTop].equalTo(root[anTop], constant = 24.0),
  title[anLeft].equalTo(root[anLeft], constant = 28.0),
  title[anRight].equalTo(root[anRight], constant = -28.0),
  status[anTop].equalTo(title[anBottom], constant = 10.0),
  status[anLeft].equalTo(title[anLeft]),
  status[anRight].equalTo(title[anRight]),
  projectLabel[anTop].equalTo(status[anBottom], constant = 24.0),
  projectLabel[anLeft].equalTo(title[anLeft]),
  projectLabel[anWidth].equalTo(104.0),
  projectChoice[anLeft].equalTo(projectLabel[anRight], constant = 12.0),
  projectChoice[anTop].equalTo(projectLabel[anTop]),
  projectChoice[anWidth].equalTo(260.0),
  sizeLabel[anTop].equalTo(projectChoice[anBottom], constant = 150.0),
  sizeLabel[anLeft].equalTo(projectLabel[anLeft]),
  sizeLabel[anWidth].equalTo(projectLabel[anWidth]),
  sizeChoice[anLeft].equalTo(projectChoice[anLeft]),
  sizeChoice[anTop].equalTo(sizeLabel[anTop]),
  sizeChoice[anWidth].equalTo(projectChoice[anWidth]),
)

updateStatus()
window.setContentView(root)
discard window.makeFirstResponder(projectChoice)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
