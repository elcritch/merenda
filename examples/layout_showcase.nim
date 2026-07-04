import merenda/nimkit

let
  app = sharedApplication()
  window = newWindow("Nimkit Layout Showcase", frame = rect(180, 160, 540, 300))
  root = newView()

  title = newTitleLabel("Intrinsic, Stack, and Constraint Layout")
  layout = newStackView(laVertical)
  form = newFormView()
  actionRow = newStackView(laHorizontal)

  nameLabel = newFormLabel("Name")
  nameField = newTextField("Ada Lovelace")
  priorityLabel = newFormLabel("Priority")
  priority = newComboBox(["Low", "Medium", "High"])
  downloads = newCheckBox("Enable downloads")
  runButton = newButton("Run")
  cancelButton = newButton("Cancel")

layout.spacing = 12.0
layout.alignment = svaFill

form.edgeInsets = insets(12.0, 14.0)
form.spacing[dcol] = 12.0
form.spacing[drow] = 10.0
form.minFieldWidth = 180.0

actionRow.spacing = 8.0
actionRow.alignment = svaCenter
actionRow.distribution = svdFill

nameLabel.huggingPriority[dcol] = LayoutPriorityHigh
priorityLabel.huggingPriority[dcol] = LayoutPriorityHigh
nameField.huggingPriority[dcol] = LayoutPriorityLow
priority.huggingPriority[dcol] = LayoutPriorityLow

priority.selectedIndex = 1

form.addRow(nameLabel, nameField)
form.addRow(priorityLabel, priority)
form.addRow(newFormLabel("Options"), downloads)
actionRow.addArrangedSubview(runButton, cancelButton)

layout.addArrangedSubview(title, form, actionRow)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 24.0, 0.0, 24.0)),
  edges = {leLeft, leTop, leRight},
)

app.runWindow(window, root, nameField)
