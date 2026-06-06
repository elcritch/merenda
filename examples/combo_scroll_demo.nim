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
  title.topAnchor.equalTo(root.topAnchor, constant = 24.0),
  title.leftAnchor.equalTo(root.leftAnchor, constant = 28.0),
  title.rightAnchor.equalTo(root.rightAnchor, constant = -28.0),
  status.topAnchor.equalTo(title.bottomAnchor, constant = 10.0),
  status.leftAnchor.equalTo(title.leftAnchor),
  status.rightAnchor.equalTo(title.rightAnchor),
  projectLabel.topAnchor.equalTo(status.bottomAnchor, constant = 24.0),
  projectLabel.leftAnchor.equalTo(title.leftAnchor),
  projectLabel.widthAnchor.equalTo(104.0),
  projectChoice.leftAnchor.equalTo(projectLabel.rightAnchor, constant = 12.0),
  projectChoice.topAnchor.equalTo(projectLabel.topAnchor),
  projectChoice.widthAnchor.equalTo(260.0),
  sizeLabel.topAnchor.equalTo(projectChoice.bottomAnchor, constant = 150.0),
  sizeLabel.leftAnchor.equalTo(projectLabel.leftAnchor),
  sizeLabel.widthAnchor.equalTo(projectLabel.widthAnchor),
  sizeChoice.leftAnchor.equalTo(projectChoice.leftAnchor),
  sizeChoice.topAnchor.equalTo(sizeLabel.topAnchor),
  sizeChoice.widthAnchor.equalTo(projectChoice.widthAnchor),
)

updateStatus()
window.setContentView(root)
discard window.makeFirstResponder(projectChoice)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
