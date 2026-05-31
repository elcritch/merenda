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
  form = newStackView(24, 24, 1, 1, laVertical)
  nameRow = newStackView(0, 0, 1, 1, laHorizontal)
  choiceRow = newStackView(0, 0, 1, 1, laHorizontal)
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

form.setSpacing(10.0)
form.setEdgeInsets(initEdgeInsets(12.0, 14.0))
form.setAlignment(svaFill)
form.setTranslatesAutoresizingMaskIntoConstraints(false)

for row in [nameRow, choiceRow, actionRow]:
  row.setSpacing(8.0)
  row.setAlignment(svaFill)
  row.setDistribution(svdFill)

nameLabel.setContentHuggingPriority(LayoutPriorityDefaultHigh, laHorizontal)
priorityLabel.setContentHuggingPriority(LayoutPriorityDefaultHigh, laHorizontal)
nameField.setContentHuggingPriority(LayoutPriorityDefaultLow, laHorizontal)
priority.setContentHuggingPriority(LayoutPriorityDefaultLow, laHorizontal)

runButton.sizeToFit()
cancelButton.sizeToFit()
priority.selectItemAtIndex(1)

nameRow.addArrangedSubview(nameLabel)
nameRow.addArrangedSubview(nameField)
choiceRow.addArrangedSubview(priorityLabel)
choiceRow.addArrangedSubview(priority)
actionRow.addArrangedSubview(downloads)
actionRow.addArrangedSubview(runButton)
actionRow.addArrangedSubview(cancelButton)

form.addArrangedSubview(title)
form.addArrangedSubview(nameRow)
form.addArrangedSubview(choiceRow)
form.addArrangedSubview(actionRow)
form.sizeToFit()

root.addSubview(form)
activateConstraints(
  [
    newLayoutConstraint(form, latLeft, lrEqual, root, latLeft, constant = 24.0),
    newLayoutConstraint(form, latTop, lrEqual, root, latTop, constant = 24.0),
    newLayoutConstraint(form, latRight, lrEqual, root, latRight, constant = -24.0),
  ]
)

window.setContentView(root)
discard window.makeFirstResponder(nameField)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
