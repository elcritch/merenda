import std/math

import merenda/nimkit

import sigils/selectors

type TimerController = ref object of Responder
  app: Application
  elapsedGauge: ProgressIndicator
  elapsedLabel: Label
  durationLabel: Label
  durationSlider: Slider
  timerAnimation: Animation
  xElapsed: float32
  duration: float32

proc updateTimerViews(controller: TimerController)
proc stopTimer(controller: TimerController)
proc restartTimer(controller: TimerController)

protocol TimerControllerAnimation from TimerController:
  property elapsed -> float32

  method elapsed(controller: TimerController): float32 =
    if controller.isNil: 0.0'f32 else: controller.xElapsed

  method setElapsed(controller: TimerController, value: float32) =
    if controller.isNil:
      return
    controller.xElapsed = min(max(value, 0.0'f32), controller.duration)
    controller.updateTimerViews()

func secondsText(value: float32): string =
  $(round(value * 10.0'f32) / 10.0'f32) & "s"

proc updateTimerViews(controller: TimerController) =
  if controller.isNil:
    return
  controller.elapsedGauge.maxValue = max(controller.duration, 0.1'f32)
  controller.elapsedGauge.value = controller.xElapsed
  controller.elapsedLabel.text = "Elapsed: " & controller.xElapsed.secondsText()
  controller.durationLabel.text = "Duration: " & controller.duration.secondsText()

proc stopTimer(controller: TimerController) =
  if controller.isNil or controller.timerAnimation.isNil:
    return
  discard controller.app.stopAnimation(controller.timerAnimation)
  controller.timerAnimation = nil

proc restartTimer(controller: TimerController) =
  if controller.isNil:
    return
  controller.stopTimer()
  if controller.xElapsed >= controller.duration:
    controller.updateTimerViews()
    return

  let
    remaining = max(controller.duration - controller.xElapsed, 0.05'f32)
    durationMs = max(50, int(round(remaining * 1000.0'f32)))
    animation = newPropertyAnimation[float32](
      DynamicAgent(controller),
      setElapsed(),
      controller.xElapsed,
      controller.duration,
      duration = durationMs.ms,
    )
  controller.timerAnimation = Animation(animation)
  discard controller.app.startAnimation(controller.timerAnimation)
  controller.updateTimerViews()

proc newTimerController(
    app: Application,
    elapsedGauge: ProgressIndicator,
    elapsedLabel, durationLabel: Label,
    durationSlider: Slider,
): TimerController =
  result = TimerController(
    app: app,
    elapsedGauge: elapsedGauge,
    elapsedLabel: elapsedLabel,
    durationLabel: durationLabel,
    durationSlider: durationSlider,
    duration: durationSlider.value,
  )
  initResponder(result)
  discard result.withProto()

let
  app = sharedApplication()
  window = newWindow("7GUIs Timer", frame = rect(140, 140, 440, 240))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("Timer")
  elapsedGauge = newProgressIndicator(0.0, 10.0, 0.0)
  elapsedLabel = newStatusLabel("Elapsed: 0.0s")
  durationRow = newStackView(laHorizontal)
  durationLabel = newStatusLabel("Duration: 10.0s")
  durationSlider = newSlider(1.0, 20.0, 10.0)
  resetButton = newButton("Reset")
  controller =
    newTimerController(app, elapsedGauge, elapsedLabel, durationLabel, durationSlider)
  durationAction = actionSelector("sevenGuiTimerDurationChanged")
  resetAction = actionSelector("sevenGuiTimerReset")

proc durationChanged(sender: DynamicAgent) =
  discard sender
  controller.duration = durationSlider.value
  controller.updateTimerViews()
  if controller.duration > controller.elapsed:
    controller.restartTimer()
  else:
    controller.stopTimer()

proc resetTimer(sender: DynamicAgent) =
  discard sender
  controller.setElapsed(0.0'f32)
  controller.restartTimer()

durationSlider.target = newActionTarget(durationAction, durationChanged)
durationSlider.action = durationAction
resetButton.target = newActionTarget(resetAction, resetTimer)
resetButton.action = resetAction

durationRow.spacing = 10.0
durationRow.alignment = svaFill
durationRow.distribution = svdFill
durationLabel.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
durationSlider.setHuggingPriority(LayoutPriorityLow, laHorizontal)
durationRow.addArrangedSubview(durationLabel, durationSlider)

layout.spacing = 14.0
layout.alignment = svaFill
layout.addArrangedSubview(title, elapsedGauge, elapsedLabel, durationRow, resetButton)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

controller.restartTimer()
app.runWindow(window, root)
