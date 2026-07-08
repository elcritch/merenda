import std/[math, times]

import merenda/nimkit

import sigils/selectors

type TimerController = ref object of Responder
  app: Application
  elapsedGauge: ProgressIndicator
  elapsedLabel: Label
  durationLabel: Label
  durationSlider: Slider
  heartbeat: Animation
  xElapsed: float32
  duration: float32

proc updateTimerViews(controller: TimerController)
proc stopTimer(controller: TimerController)
proc startTimer(controller: TimerController)
proc syncTimerState(controller: TimerController)

proc setElapsed(controller: TimerController, value: float32) =
  if controller.isNil:
    return
  controller.xElapsed = max(value, 0.0'f32)
  controller.updateTimerViews()

func secondsText(value: float32): string =
  $(round(value * 10.0'f32) / 10.0'f32) & "s"

func seconds(delta: Duration): float32 =
  delta.inNanoseconds.float32 / 1_000_000_000.0'f32

proc updateTimerViews(controller: TimerController) =
  if controller.isNil:
    return
  controller.elapsedGauge.maxValue = max(controller.duration, 0.1'f32)
  controller.elapsedGauge.value = min(controller.xElapsed, controller.duration)
  controller.elapsedLabel.text = "Elapsed: " & controller.xElapsed.secondsText()
  controller.durationLabel.text = "Duration: " & controller.duration.secondsText()

proc stopTimer(controller: TimerController) =
  if controller.isNil or controller.heartbeat.isNil:
    return
  discard controller.app.stopAnimation(controller.heartbeat)
  controller.heartbeat = nil

proc startTimer(controller: TimerController) =
  if controller.isNil:
    return
  if not controller.heartbeat.isNil or controller.xElapsed >= controller.duration:
    controller.updateTimerViews()
    return

  controller.heartbeat = newAnimation(duration = 1000.ms)
  controller.heartbeat.loopCount = -1
  discard controller.app.startAnimation(controller.heartbeat)
  controller.updateTimerViews()

proc syncTimerState(controller: TimerController) =
  if controller.isNil:
    return
  if controller.xElapsed < controller.duration:
    controller.startTimer()
  else:
    controller.stopTimer()
    controller.updateTimerViews()

proc timerTicked(controller: TimerController, delta: Duration) {.slot.} =
  if controller.isNil or controller.heartbeat.isNil:
    return
  controller.setElapsed(min(controller.xElapsed + delta.seconds(), controller.duration))
  if controller.xElapsed >= controller.duration:
    controller.stopTimer()

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
  result.app.animationScheduler().connect(schedulerTicked, result, timerTicked)

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
  controller.syncTimerState()

proc resetTimer(sender: DynamicAgent) =
  discard sender
  controller.setElapsed(0.0'f32)
  controller.syncTimerState()

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

controller.startTimer()
app.runWindow(window, root)
