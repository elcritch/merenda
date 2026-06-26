import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window =
    newWindow("Nimkit Progress Indicator Demo", frame = initRect(120, 120, 460, 280))
  root = newView()
  layout = newStackView(laVertical)
  buttonRow = newStackView(laHorizontal)
  title = newTitleLabel("Progress Indicators")
  status = newStatusLabel("")
  determinate = newProgressIndicator(0.0, 100.0, 35.0)
  indeterminateBar = newProgressIndicator(0.0, 1.0, 0.0)
  spinner = newProgressIndicator(0.0, 1.0, 0.0)
  advanceButton = newButton("Advance")
  toggleButton = newButton("Start")
  resetButton = newButton("Reset")
  advanceAction = actionSelector("progressAdvance")
  toggleAction = actionSelector("progressToggle")
  resetAction = actionSelector("progressReset")

proc updateStatus() =
  status.text =
    "Determinate: " & $int(determinate.value) & "%   Indeterminate: " &
    (if indeterminateBar.animating: "running" else: "stopped")

proc updateAnimationFrame() =
  indeterminateBar.stepAnimation()
  spinner.stepAnimation()

proc onAdvance(sender: DynamicAgent) =
  discard sender
  determinate.incrementBy(10.0)
  if determinate.value >= determinate.maxValue:
    determinate.value = determinate.minValue
  updateAnimationFrame()
  updateStatus()

proc onToggle(sender: DynamicAgent) =
  discard sender
  if indeterminateBar.animating:
    indeterminateBar.stopAnimation()
    spinner.stopAnimation()
    toggleButton.title = "Start"
  else:
    indeterminateBar.startAnimation()
    spinner.startAnimation()
    toggleButton.title = "Stop"
  updateAnimationFrame()
  updateStatus()

proc onReset(sender: DynamicAgent) =
  discard sender
  determinate.value = 35.0
  indeterminateBar.animationPhase = 0.0
  spinner.animationPhase = 0.0
  updateStatus()

indeterminateBar.indeterminate = true
spinner.indeterminate = true
spinner.progressIndicatorStyle = pisSpinning
spinner.displayedWhenStopped = true

advanceButton.target = newActionTarget(advanceAction, onAdvance)
advanceButton.action = advanceAction
toggleButton.target = newActionTarget(toggleAction, onToggle)
toggleButton.action = toggleAction
resetButton.target = newActionTarget(resetAction, onReset)
resetButton.action = resetAction

buttonRow.spacing = 8.0
buttonRow.alignment = svaFill
buttonRow.distribution = svdFillEqually
buttonRow.addArrangedSubview(advanceButton, toggleButton, resetButton)

layout.spacing = 14.0
layout.alignment = svaFill
layout.addArrangedSubview(
  title, status, determinate, indeterminateBar, spinner, buttonRow
)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

updateStatus()
window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
