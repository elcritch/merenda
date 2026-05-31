import merenda/nimkit

proc makeLabel(text: string): TextField =
  result = newTextField(text)
  result.setEditable(false)
  result.setSelectable(false)
  result.setTextColor(initColor(0.09, 0.12, 0.18))

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

root.setBackgroundColor(initColor(0.95, 0.96, 0.98))

title.setAlignment(taCenter)

layout.setSpacing(12.0)
layout.setAlignment(svaFill)

form.setEdgeInsets(initEdgeInsets(12.0, 14.0))
form.setColumnSpacing(12.0)
form.setRowSpacing(10.0)
form.setMinimumFieldWidth(180.0)

actionRow.setSpacing(8.0)
actionRow.setAlignment(svaCenter)
actionRow.setDistribution(svdFill)

nameLabel.setContentHuggingPriority(LayoutPriorityDefaultHigh, laHorizontal)
priorityLabel.setContentHuggingPriority(LayoutPriorityDefaultHigh, laHorizontal)
nameField.setContentHuggingPriority(LayoutPriorityDefaultLow, laHorizontal)
priority.setContentHuggingPriority(LayoutPriorityDefaultLow, laHorizontal)

priority.selectItemAtIndex(1)

form.addRow(nameLabel, nameField)
form.addRow(priorityLabel, priority)
form.addRow(makeLabel("Options"), downloads)
actionRow.addArrangedSubview(runButton)
actionRow.addArrangedSubview(cancelButton)

layout.addArrangedSubview(title)
layout.addArrangedSubview(form)
layout.addArrangedSubview(actionRow)

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
