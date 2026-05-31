import merenda/nimkit

proc makeLabel(text: string): TextField =
  result = newTextField(0, 0, 1, 1, text)
  result.setEditable(false)
  result.setSelectable(false)
  result.setTextColor(initColor(0.09, 0.12, 0.18))

let
  app = sharedApplication()
  window = newWindow(180, 160, 540, 300, "Nimkit Layout Showcase")
  root = newView(0, 0, 540, 300)

  title = makeLabel("Intrinsic, Stack, and Constraint Layout")
  layout = newStackView(24, 24, 1, 1, laVertical)
  form = newFormView(0, 0, 1, 1)
  actionRow = newStackView(0, 0, 1, 1, laHorizontal)

  nameLabel = makeLabel("Name")
  nameField = newTextField(0, 0, 1, 1, "Ada Lovelace")
  priorityLabel = makeLabel("Priority")
  priority = newComboBox(0, 0, 1, 1, ["Low", "Medium", "High"])
  downloads = newCheckBox(0, 0, 1, 1, "Enable downloads")
  runButton = newButton(0, 0, 1, 1, "Run")
  cancelButton = newButton(0, 0, 1, 1, "Cancel")

root.setBackgroundColor(initColor(0.95, 0.96, 0.98))

title.setAlignment(taCenter)
title.sizeToFit()

layout.setSpacing(12.0)
layout.setAlignment(svaFill)
layout.setTranslatesAutoresizingMaskIntoConstraints(false)

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

runButton.sizeToFit()
cancelButton.sizeToFit()
priority.selectItemAtIndex(1)

form.addRow(nameLabel, nameField)
form.addRow(priorityLabel, priority)
form.addRow(makeLabel("Options"), downloads)
actionRow.addArrangedSubview(runButton)
actionRow.addArrangedSubview(cancelButton)

layout.addArrangedSubview(title)
layout.addArrangedSubview(form)
layout.addArrangedSubview(actionRow)
layout.sizeToFit()

root.addSubview(layout)
activateConstraints(
  [
    newLayoutConstraint(layout, latLeft, lrEqual, root, latLeft, constant = 24.0),
    newLayoutConstraint(layout, latTop, lrEqual, root, latTop, constant = 24.0),
    newLayoutConstraint(layout, latRight, lrEqual, root, latRight, constant = -24.0),
  ]
)

window.setContentView(root)
discard window.makeFirstResponder(nameField)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
