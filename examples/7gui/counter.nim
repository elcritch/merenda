import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("7GUIs Counter", frame = rect(140, 140, 300, 150))
  root = newView()
  layout = newStackView(laVertical)
  row = newStackView(laHorizontal)
  title = newTitleLabel("Counter")
  countLabel = newStatusLabel("0")
  countButton = newButton("Count")
  countAction = actionSelector("sevenGuiCounterIncrement")

var count = 0

proc incrementCounter(sender: DynamicAgent) =
  discard sender
  inc count
  countLabel.text = $count

countButton.target = newActionTarget(countAction, incrementCounter)
countButton.action = countAction

row.spacing = 10.0
row.alignment = svaFill
row.distribution = svdFillEqually
row.addArrangedSubview(countLabel, countButton)

layout.spacing = 14.0
layout.alignment = svaFill
layout.addArrangedSubview(title, row)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

app.runWindow(window, root)
