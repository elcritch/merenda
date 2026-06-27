import std/strutils

import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Matrix Demo", frame = initRect(160, 140, 520, 420))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("Matrix")
  status = newStatusLabel("")
  packageLabel = newHeadingLabel("Package")
  featureLabel = newHeadingLabel("Features")
  commandLabel = newHeadingLabel("Commands")
  packageMatrix = newRadioMatrix(["Standard", "Pro", "Enterprise"])
  featureMatrix =
    newCheckMatrix(["Autosave", "Diagnostics", "Cloud Sync", "Beta Tools"], columns = 2)
  commandMatrix = newButtonMatrix(["Apply", "Reset", "Inspect"], columns = 3)
  matrixAction = actionSelector("matrixDemoChanged")

var lastCommand = "None"

proc selectedTitle(matrix: Matrix): string =
  let cell = matrix.selectedCell()
  if cell.isNil:
    "None"
  else:
    cell.title()

proc selectedTitles(matrix: Matrix): string =
  var titles: seq[string]
  for cell in matrix.selectedCells():
    if not cell.isNil and cell.title().len > 0:
      titles.add cell.title()
  if titles.len == 0:
    "None"
  else:
    titles.join(", ")

proc leadTitle(matrix: Matrix): string =
  let cell = matrix.cellAtIndex(matrix.leadIndex())
  if cell.isNil:
    "None"
  else:
    cell.title()

proc updateStatus() =
  status.text =
    "Package: " & packageMatrix.selectedTitle() & " / Features: " &
    featureMatrix.selectedTitles() & " / Last command: " & lastCommand

proc onMatrixAction(sender: DynamicAgent) =
  if sender == DynamicAgent(commandMatrix):
    lastCommand = commandMatrix.leadTitle()
  updateStatus()

let target = newActionTarget(matrixAction, onMatrixAction)

packageMatrix.cellSize = initSize(180.0, 24.0)
featureMatrix.cellSize = initSize(140.0, 24.0)
commandMatrix.cellSize = initSize(90.0, 28.0)
packageMatrix.target = target
packageMatrix.action = matrixAction
featureMatrix.target = target
featureMatrix.action = matrixAction
commandMatrix.target = target
commandMatrix.action = matrixAction

layout.spacing = 9.0
layout.alignment = svaFill
layout.addArrangedSubview(
  title, status, packageLabel, packageMatrix, featureLabel, featureMatrix, commandLabel,
  commandMatrix,
)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 24.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

updateStatus()
window.setContentView(root)
discard window.makeFirstResponder(packageMatrix)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
