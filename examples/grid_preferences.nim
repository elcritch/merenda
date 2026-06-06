import merenda/nimkit

let
  app = sharedApplication()
  window = newWindow("Nimkit Grid Preferences", frame = initRect(180, 160, 520, 340))
  root = newView()
  layout = newStackView(laVertical)
  grid = newGridView()
  actionRow = newStackView(laHorizontal)

  title = newTitleLabel("Preferences")
  nameLabel = newFormLabel("Name")
  emailLabel = newFormLabel("Email")
  themeLabel = newFormLabel("Theme")
  nameField = newTextField("Ada Lovelace")
  emailField = newTextField("ada@example.com")
  themeChoice = newComboBox(["System", "Light", "Dark"])
  notifications = newCheckBox("Send notifications")
  sync = newCheckBox("Sync settings")
  cancelButton = newButton("Cancel")
  saveButton = newButton("Save")

root.background = initColor(0.95, 0.96, 0.98)

themeChoice.selectedIndex = 0
nameLabel.huggingPriority[dcol] = LayoutPriorityHigh
emailLabel.huggingPriority[dcol] = LayoutPriorityHigh
themeLabel.huggingPriority[dcol] = LayoutPriorityHigh

layout.spacing = 14.0
layout.alignment = svaFill

grid.edgeInsets = initEdgeInsets(12.0, 14.0)
grid.spacing[dcol] = 12.0
grid.spacing[drow] = 10.0
grid.alignment[drow] = gaCenter

actionRow.spacing = 8.0
actionRow.alignment = svaTrailing
actionRow.distribution = svdFill

grid.addSubview(nameLabel, row = 0, col = 0)
grid.addSubview(nameField, row = 0, col = 1)
grid.addSubview(emailLabel, row = 1, col = 0)
grid.addSubview(emailField, row = 1, col = 1)
grid.addSubview(themeLabel, row = 2, col = 0)
grid.addSubview(themeChoice, row = 2, col = 1)
grid.addSubview(notifications, row = 3, col = 1)
grid.addSubview(sync, row = 4, col = 1)

actionRow.addArrangedSubview(cancelButton, saveButton)
layout.addArrangedSubview(title, grid, actionRow)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.makeFirstResponder(nameField)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
