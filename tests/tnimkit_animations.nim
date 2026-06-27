import std/[math, times, unittest]

import sigils/core

import merenda/nimkit

type
  AnimationSignalSpy = ref object of Agent
    startedCount: int
    pausedCount: int
    resumedCount: int
    stopped: seq[bool]
    finishedCount: int
    states: seq[tuple[nextState, oldState: AnimationState]]
    progressValues: seq[float32]
    marks: seq[float32]
    values: seq[float32]

  AnimationTarget = ref object of DynamicAgent
    floatValue: float32

protocol AnimationTargetProtocol from AnimationTarget:
  method setAnimatedFloat*(target: AnimationTarget, value: float32) =
    target.floatValue = value

proc rememberStarted(spy: AnimationSignalSpy) {.slot.} =
  inc spy.startedCount

proc rememberPaused(spy: AnimationSignalSpy) {.slot.} =
  inc spy.pausedCount

proc rememberResumed(spy: AnimationSignalSpy) {.slot.} =
  inc spy.resumedCount

proc rememberStopped(spy: AnimationSignalSpy, finished: bool) {.slot.} =
  spy.stopped.add finished

proc rememberFinished(spy: AnimationSignalSpy) {.slot.} =
  inc spy.finishedCount

proc rememberState(
    spy: AnimationSignalSpy, nextState: AnimationState, oldState: AnimationState
) {.slot.} =
  spy.states.add (nextState: nextState, oldState: oldState)

proc rememberProgress(spy: AnimationSignalSpy, progress: float32) {.slot.} =
  spy.progressValues.add progress

proc rememberMark(spy: AnimationSignalSpy, mark: float32) {.slot.} =
  spy.marks.add mark

proc rememberValue(spy: AnimationSignalSpy, value: float32) {.slot.} =
  spy.values.add value

template checkClose(actual, expected: float32) =
  check abs(actual - expected) <= 0.0001'f32

suite "NimKit animations":
  test "animation exposes observable lifecycle state and signals":
    let
      animation = newAnimation(duration = initDuration(milliseconds = 100))
      spy = AnimationSignalSpy()

    animation.connect(started, spy, rememberStarted)
    animation.connect(paused, spy, rememberPaused)
    animation.connect(resumed, spy, rememberResumed)
    animation.connect(stopped, spy, rememberStopped)
    animation.connect(finished, spy, rememberFinished)
    animation.connect(stateChanged, spy, rememberState)

    check animation.state{} == asStopped
    check animation.currentTime{} == initDuration()
    check animation.progress{} == 0.0'f32
    check animation.duration == initDuration(milliseconds = 100)
    check animation.loopCount == 1
    check animation.direction == adForward
    check animation.conformsTo(AnimationProtocol)

    animation.start()
    check animation.state{} == asRunning
    check spy.startedCount == 1
    check spy.states[^1] == (nextState: asRunning, oldState: asStopped)

    animation.pause()
    check animation.state{} == asPaused
    check spy.pausedCount == 1

    animation.resume()
    check animation.state{} == asRunning
    check spy.resumedCount == 1

    animation.stop(finished = true)
    check animation.state{} == asStopped
    check animation.progress{} == 1.0'f32
    check spy.stopped == @[true]
    check spy.finishedCount == 1

  test "current time updates progress and emits progress marks":
    let
      animation = newAnimation(duration = initDuration(milliseconds = 100))
      spy = AnimationSignalSpy()

    animation.progressMarks = [0.25'f32, 0.5'f32, 0.75'f32]
    animation.connect(progressChanged, spy, rememberProgress)
    animation.connect(progressMarkReached, spy, rememberMark)

    animation.start()
    animation.setCurrentTime(initDuration(milliseconds = 50))
    check animation.currentTime{} == initDuration(milliseconds = 50)
    check animation.progress{} == 0.5'f32
    check spy.marks == @[0.25'f32, 0.5'f32]
    check spy.progressValues[^1] == 0.5'f32

    animation.setCurrentTime(initDuration(milliseconds = 100))
    check animation.progress{} == 1.0'f32
    check spy.marks == @[0.25'f32, 0.5'f32, 0.75'f32]

  test "value animation writes interpolated Sigil value and emits value signal":
    let
      animation = newValueAnimation[float32](
        10.0'f32, 20.0'f32, duration = initDuration(milliseconds = 100)
      )
      spy = AnimationSignalSpy()

    animation.connect(valueChanged, spy, rememberValue)
    animation.start()
    animation.setProgress(0.5)

    check animation.currentValue{} == 15.0'f32
    check spy.values[^1] == 15.0'f32

  test "timing curves adjust interpolation progress":
    checkClose(linearTiming().easedProgress(0.5'f32), 0.5'f32)
    checkClose(easeInTiming().easedProgress(0.5'f32), 0.25'f32)
    checkClose(easeOutTiming().easedProgress(0.5'f32), 0.75'f32)
    checkClose(easeInOutTiming().easedProgress(0.25'f32), 0.125'f32)
    checkClose(
      cubicBezierTiming(initPoint(0.0'f32, 0.0'f32), initPoint(1.0'f32, 1.0'f32))
      .easedProgress(0.5'f32),
      0.5'f32,
    )

    let spring = springTiming(response = 0.45'f32, dampingRatio = 0.75'f32)
    check spring.easedProgress(0.0'f32) == 0.0'f32
    check spring.easedProgress(1.0'f32) == 1.0'f32
    check spring.easedProgress(0.5'f32) > 0.0'f32

    let animation = newValueAnimation[float32](
      0.0'f32, 100.0'f32, duration = initDuration(milliseconds = 100)
    )
    animation.timing = easeInTiming()
    animation.start()
    animation.setProgress(0.5'f32)
    checkClose(animation.currentValue{}, 25.0'f32)

    animation.timing = easeOutTiming()
    animation.setProgress(0.25'f32)
    checkClose(animation.currentValue{}, 43.75'f32)

    animation.curve = acEaseInOut
    check animation.curve == acEaseInOut

  test "typed value animations interpolate geometry and colors":
    let pointAnimation = newValueAnimation[Point](
      initPoint(0.0'f32, 10.0'f32),
      initPoint(10.0'f32, 30.0'f32),
      duration = initDuration(milliseconds = 100),
    )
    pointAnimation.start()
    pointAnimation.setProgress(0.5'f32)
    checkClose(pointAnimation.currentValue{}.x, 5.0'f32)
    checkClose(pointAnimation.currentValue{}.y, 20.0'f32)

    let sizeAnimation = newValueAnimation[Size](
      initSize(20.0'f32, 40.0'f32),
      initSize(60.0'f32, 100.0'f32),
      duration = initDuration(milliseconds = 100),
    )
    sizeAnimation.start()
    sizeAnimation.setProgress(0.25'f32)
    checkClose(sizeAnimation.currentValue{}.width, 30.0'f32)
    checkClose(sizeAnimation.currentValue{}.height, 55.0'f32)

    let rectAnimation = newValueAnimation[Rect](
      initRect(0.0'f32, 10.0'f32, 100.0'f32, 50.0'f32),
      initRect(20.0'f32, 30.0'f32, 140.0'f32, 90.0'f32),
      duration = initDuration(milliseconds = 100),
    )
    rectAnimation.start()
    rectAnimation.setProgress(0.5'f32)
    checkClose(rectAnimation.currentValue{}.origin.x, 10.0'f32)
    checkClose(rectAnimation.currentValue{}.origin.y, 20.0'f32)
    checkClose(rectAnimation.currentValue{}.size.width, 120.0'f32)
    checkClose(rectAnimation.currentValue{}.size.height, 70.0'f32)

    let colorAnimation = newValueAnimation[Color](
      initColor(0.0'f32, 0.25'f32, 0.5'f32, 0.75'f32),
      initColor(1.0'f32, 0.75'f32, 0.0'f32, 0.25'f32),
      duration = initDuration(milliseconds = 100),
    )
    colorAnimation.start()
    colorAnimation.setProgress(0.5'f32)
    checkClose(colorAnimation.currentValue{}.r, 0.5'f32)
    checkClose(colorAnimation.currentValue{}.g, 0.5'f32)
    checkClose(colorAnimation.currentValue{}.b, 0.25'f32)
    checkClose(colorAnimation.currentValue{}.a, 0.5'f32)

  test "property animation applies values through its selector":
    let
      target = AnimationTarget()
      animation = newPropertyAnimation[float32](
        DynamicAgent(target),
        setAnimatedFloat(),
        0.0'f32,
        1.0'f32,
        duration = initDuration(milliseconds = 100),
      )

    discard target.withProto()
    animation.start()
    animation.setProgress(0.25)
    check target.floatValue == 0.25'f32

  test "animation groups report natural duration from children":
    let
      short = newAnimation(duration = initDuration(milliseconds = 100))
      long = newAnimation(duration = initDuration(milliseconds = 250))
      parallel = newParallelAnimationGroup([short, long])
      sequential = newSequentialAnimationGroup([short, long])

    check parallel.duration == initDuration(milliseconds = 250)
    check sequential.duration == initDuration(milliseconds = 350)
    check parallel.conformsTo(AnimationProtocol)
    check sequential.conformsTo(AnimationProtocol)

    let pause = newPauseAnimation(initDuration(milliseconds = 80))
    sequential.addAnimation(pause)
    check sequential.duration == initDuration(milliseconds = 430)
