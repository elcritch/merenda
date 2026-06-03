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
  title.topAnchor.constraintEqualTo(root.topAnchor, constant = 24.0),
  title.leftAnchor.constraintEqualTo(root.leftAnchor, constant = 28.0),
  title.rightAnchor.constraintEqualTo(root.rightAnchor, constant = -28.0),
  status.topAnchor.constraintEqualTo(title.bottomAnchor, constant = 10.0),
  status.leftAnchor.constraintEqualTo(title.leftAnchor),
  status.rightAnchor.constraintEqualTo(title.rightAnchor),
  projectLabel.topAnchor.constraintEqualTo(status.bottomAnchor, constant = 24.0),
  projectLabel.leftAnchor.constraintEqualTo(title.leftAnchor),
  projectLabel.widthAnchor.constraintEqualTo(104.0),
  projectChoice.leftAnchor.constraintEqualTo(projectLabel.rightAnchor, constant = 12.0),
  projectChoice.topAnchor.constraintEqualTo(projectLabel.topAnchor),
  projectChoice.widthAnchor.constraintEqualTo(260.0),
  sizeLabel.topAnchor.constraintEqualTo(projectChoice.bottomAnchor, constant = 150.0),
  sizeLabel.leftAnchor.constraintEqualTo(projectLabel.leftAnchor),
  sizeLabel.widthAnchor.constraintEqualTo(projectLabel.widthAnchor),
  sizeChoice.leftAnchor.constraintEqualTo(projectChoice.leftAnchor),
  sizeChoice.topAnchor.constraintEqualTo(sizeLabel.topAnchor),
  sizeChoice.widthAnchor.constraintEqualTo(projectChoice.widthAnchor),
)

updateStatus()
window.setContentView(root)
discard window.makeFirstResponder(projectChoice)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
