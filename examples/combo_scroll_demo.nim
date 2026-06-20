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
  title[atTop].equalTo(root[atTop], constant = 24.0),
  title[atLeft].equalTo(root[atLeft], constant = 28.0),
  title[atRight].equalTo(root[atRight], constant = -28.0),
  status[atTop].equalTo(title[atBottom], constant = 10.0),
  status[atLeft].equalTo(title[atLeft]),
  status[atRight].equalTo(title[atRight]),
  projectLabel[atTop].equalTo(status[atBottom], constant = 24.0),
  projectLabel[atLeft].equalTo(title[atLeft]),
  projectLabel[atWidth].equalTo(104.0),
  projectChoice[atLeft].equalTo(projectLabel[atRight], constant = 12.0),
  projectChoice[atTop].equalTo(projectLabel[atTop]),
  projectChoice[atWidth].equalTo(260.0),
  sizeLabel[atTop].equalTo(projectChoice[atBottom], constant = 150.0),
  sizeLabel[atLeft].equalTo(projectLabel[atLeft]),
  sizeLabel[atWidth].equalTo(projectLabel[atWidth]),
  sizeChoice[atLeft].equalTo(projectChoice[atLeft]),
  sizeChoice[atTop].equalTo(sizeLabel[atTop]),
  sizeChoice[atWidth].equalTo(projectChoice[atWidth]),
)

updateStatus()
window.setContentView(root)
discard window.makeFirstResponder(projectChoice)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
