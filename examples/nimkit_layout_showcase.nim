import merenda/nimkit

proc makeLabel(text: string): TextField =
  result = newTextField(text)
  result.editable = false
  result.selectable = false
  result.textColor = initColor(0.09, 0.12, 0.18)

let
  app = sharedApplication()
  window = newWindow("Nimkit Layout Showcase", frame = initRect(180, 160, 540, 300))
  root = newView()

  title = makeLabel("Intrinsic, Stack, and Constraint Layout")
  layout = newStackView(laVertical)
  form = newFormView()
  actionRow = newStackView(laHorizontal)

  nameLabel = makeLabel("Name")
  nameField = newTextField("Ada Lovelace")
  priorityLabel = makeLabel("Priority")
  priority = newComboBox(["Low", "Medium", "High"])
  downloads = newCheckBox("Enable downloads")
  runButton = newButton("Run")
  cancelButton = newButton("Cancel")

root.background = initColor(0.95, 0.96, 0.98)

title.alignment = taCenter

layout.spacing = 12.0
layout.alignment = svaFill

form.edgeInsets = initEdgeInsets(12.0, 14.0)
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
form.addRow(makeLabel("Options"), downloads)
actionRow.addArrangedSubview(runButton, cancelButton)

layout.addArrangedSubview(title, form, actionRow)

root.addSubview(layout)
activateConstraints(
  layout.pinEdges(
    toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 24.0, 0.0, 24.0)),
    edges = {leLeft, leTop, leRight},
  )
)

window.setContentView(root)
discard window.makeFirstResponder(nameField)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
