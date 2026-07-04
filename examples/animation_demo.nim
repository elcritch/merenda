import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Animation Demo", frame = initRect(120, 120, 560, 360))
  root = newView()
  layout = newStackView(laVertical)
  buttonRow = newStackView(laHorizontal)
  title = newTitleLabel("Animations")
  status = newStatusLabel("Ready")
  stage = newView(frame = initRect(0.0, 0.0, 480.0, 150.0))
  tile = newView(frame = initRect(20.0, 40.0, 90.0, 70.0))
  propertyButton = newButton("Property")
  sequenceButton = newButton("Sequence")
  transactionButton = newButton("Transaction")
  resetButton = newButton("Reset")
  propertyAction = actionSelector("animationProperty")
  sequenceAction = actionSelector("animationSequence")
  transactionAction = actionSelector("animationTransaction")
  resetAction = actionSelector("animationReset")

const
  TileHome = initRect(20.0'f32, 40.0'f32, 90.0'f32, 70.0'f32)
  TileFar = initRect(330.0'f32, 28.0'f32, 120.0'f32, 94.0'f32)
  TileHigh = initRect(180.0'f32, 14.0'f32, 110.0'f32, 84.0'f32)

var runningAnimation: Animation

proc stopRunningAnimation() =
  if runningAnimation.isNil:
    return
  discard app.stopAnimation(runningAnimation)
  runningAnimation = nil

proc play(animation: Animation, message: string) =
  stopRunningAnimation()
  runningAnimation = animation
  discard app.startAnimation(animation)
  status.text = message

proc resetTile(sender: DynamicAgent = nil) =
  discard sender
  stopRunningAnimation()
  tile.frame = TileHome
  tile.alphaValue = 1.0'f32
  status.text = "Ready"

proc playPropertyAnimation(sender: DynamicAgent) =
  discard sender
  let move =
    newFrameAnimation(tile, TileFar, duration = 280.ms, timing = easeInOutTiming())
  let fade = newAlphaValueAnimation(tile, 0.45'f32, duration = 280.ms)
  play(newParallelAnimationGroup([Animation(move), Animation(fade)]), "Property group")

proc playSequenceAnimation(sender: DynamicAgent) =
  discard sender
  resetTile()
  let outGroup = newParallelAnimationGroup(
    [
      Animation(newFrameAnimation(tile, TileHigh, duration = 220.ms)),
      Animation(newAlphaValueAnimation(tile, 0.65'f32, duration = 220.ms)),
    ]
  )
  let backGroup = newParallelAnimationGroup(
    [
      Animation(newFrameAnimation(tile, TileHome, duration = 260.ms)),
      Animation(newAlphaValueAnimation(tile, 1.0'f32, duration = 260.ms)),
    ]
  )
  play(
    newSequentialAnimationGroup(
      [Animation(outGroup), Animation(newPauseAnimation(80.ms)), Animation(backGroup)]
    ),
    "Sequential group",
  )

proc playTransactionAnimation(sender: DynamicAgent) =
  discard sender
  stopRunningAnimation()
  let group = animationGroup(duration = 300.ms, curve = acEaseInOut):
    tile.frame = TileFar
    tile.alphaValue = 0.35'f32
  play(group, "Transaction group")

stage.background = color(0.92, 0.93, 0.95, 1.0)
stage.clipsToBounds = true
tile.background = color(0.22, 0.48, 0.86, 1.0)
tile.shadow = [dropShadow(color(0.0, 0.0, 0.0, 0.24), 0.0, 8.0, 18.0)]
stage.addSubview(tile)

propertyButton.target = newActionTarget(propertyAction, playPropertyAnimation)
propertyButton.action = propertyAction
sequenceButton.target = newActionTarget(sequenceAction, playSequenceAnimation)
sequenceButton.action = sequenceAction
transactionButton.target = newActionTarget(transactionAction, playTransactionAnimation)
transactionButton.action = transactionAction
resetButton.target = newActionTarget(resetAction, resetTile)
resetButton.action = resetAction

buttonRow.spacing = 8.0
buttonRow.alignment = svaFill
buttonRow.distribution = svdFillEqually
buttonRow.addArrangedSubview(
  propertyButton, sequenceButton, transactionButton, resetButton
)

layout.spacing = 14.0
layout.alignment = svaFill
layout.addArrangedSubview(title, status, stage, buttonRow)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
