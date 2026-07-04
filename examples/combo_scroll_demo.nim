import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Combo Scroll Demo", frame = rect(180, 160, 520, 360))
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

root.addSubviews(
  autoNames(title, status, projectLabel, projectChoice, sizeLabel, sizeChoice)
)

activateConstraints:
  title[atTop] == root[atTop] + 24.0
  title[atLeft] == root[atLeft] + 28.0
  title[atRight] == root[atRight] - 28.0
  status[atTop] == title[atBottom] + 10.0
  status[atLeft] == title[atLeft]
  status[atRight] == title[atRight]
  projectLabel[atTop] == status[atBottom] + 24.0
  projectLabel[atLeft] == title[atLeft]
  projectLabel[atWidth] == 104.0
  projectChoice[atLeft] == projectLabel[atRight] + 12.0
  projectChoice[atTop] == projectLabel[atTop]
  projectChoice[atWidth] == 260.0
  sizeLabel[atTop] == projectChoice[atBottom] + 150.0
  sizeLabel[atLeft] == projectLabel[atLeft]
  sizeLabel[atWidth] == projectLabel[atWidth]
  sizeChoice[atLeft] == projectChoice[atLeft]
  sizeChoice[atTop] == sizeLabel[atTop]
  sizeChoice[atWidth] == projectChoice[atWidth]

updateStatus()
app.runWindow(window, root, projectChoice)
