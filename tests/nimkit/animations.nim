import std/[math, os, times, unittest]

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

  FixedIntrinsicView = ref object of View
    naturalSize: Size

protocol AnimationTargetProtocol from AnimationTarget:
  method setAnimatedFloat*(target: AnimationTarget, value: float32) =
    target.floatValue = value

protocol FixedIntrinsicLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: FixedIntrinsicView): IntrinsicSize =
    initIntrinsicSize(view.naturalSize)

proc newFixedIntrinsicView(width, height: float32): FixedIntrinsicView =
  result = FixedIntrinsicView()
  initViewFields(result, rect(0.0, 0.0, width, height))
  result.naturalSize = initSize(width, height)
  result.autoresizingMaskConstraints = false
  discard result.withProtocol(FixedIntrinsicLayout)

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

proc openFileDescriptorCount(): int =
  when defined(posix):
    let fdDir =
      if dirExists("/proc/self/fd"):
        "/proc/self/fd"
      elif dirExists("/dev/fd"):
        "/dev/fd"
      else:
        ""
    if fdDir.len == 0:
      return -1
    for _ in walkDir(fdDir):
      inc result
  else:
    -1

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
      rect(0.0'f32, 10.0'f32, 100.0'f32, 50.0'f32),
      rect(20.0'f32, 30.0'f32, 140.0'f32, 90.0'f32),
      duration = initDuration(milliseconds = 100),
    )
    rectAnimation.start()
    rectAnimation.setProgress(0.5'f32)
    checkClose(rectAnimation.currentValue{}.origin.x, 10.0'f32)
    checkClose(rectAnimation.currentValue{}.origin.y, 20.0'f32)
    checkClose(rectAnimation.currentValue{}.size.width, 120.0'f32)
    checkClose(rectAnimation.currentValue{}.size.height, 70.0'f32)

    let colorAnimation = newValueAnimation[Color](
      color(0.0'f32, 0.25'f32, 0.5'f32, 0.75'f32),
      color(1.0'f32, 0.75'f32, 0.0'f32, 0.25'f32),
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

  test "property animation helpers route view geometry and alpha through setters":
    let
      scheduler = newAnimationScheduler()
      view = newView(frame = rect(0.0, 0.0, 100.0, 40.0))
      frameAnimation = newFrameAnimation(
        view, rect(10.0, 20.0, 140.0, 80.0), duration = initDuration(milliseconds = 100)
      )

    view.clearNeedsDisplayTree()
    check view.conformsTo(ViewAnimProtocol)
    check scheduler.startAnimation(frameAnimation)
    check scheduler.tick(initDuration(milliseconds = 50)) == 1
    check view.frame() == rect(5.0, 10.0, 120.0, 60.0)
    check view.bounds().size == initSize(120.0, 60.0)
    check view.needsDisplay()

    let boundsAnimation = newBoundsAnimation(
      view, rect(20.0, 30.0, 120.0, 60.0), duration = initDuration(milliseconds = 100)
    )
    boundsAnimation.start()
    boundsAnimation.setProgress(0.5)
    check view.bounds() == rect(10.0, 15.0, 120.0, 60.0)

    let alphaAnimation =
      newAlphaValueAnimation(view, 0.2'f32, duration = initDuration(milliseconds = 100))
    alphaAnimation.start()
    alphaAnimation.setProgress(0.5)
    checkClose(view.alphaValue(), 0.6'f32)

  test "property animation helpers route scroll and progress setters":
    let
      document = newView(frame = rect(0.0, 0.0, 320.0, 240.0))
      scrollView =
        newScrollView(frame = rect(0.0, 0.0, 120.0, 80.0), documentView = document)

    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.autohidePolicy = sapNever
    scrollView.tile()

    let offsetAnimation = newContentOffsetAnimation(
      scrollView, initPoint(40.0, 60.0), duration = initDuration(milliseconds = 100)
    )
    offsetAnimation.start()
    offsetAnimation.setProgress(0.5)
    check scrollView.conformsTo(ScrollAnimProtocol)
    check scrollView.contentOffset() == initPoint(20.0, 30.0)
    check scrollView.clipView().bounds().origin == initPoint(20.0, 30.0)

    let
      indicator = newProgressIndicator(0.0, 100.0, 25.0)
      valueAnimation = newProgressValueAnimation(
        indicator, 125.0'f32, duration = initDuration(milliseconds = 100)
      )

    valueAnimation.start()
    valueAnimation.setProgress(0.5)
    check indicator.conformsTo(ProgressAnimProtocol)
    checkClose(indicator.value(), 75.0'f32)
    valueAnimation.setProgress(1.0)
    checkClose(indicator.value(), 100.0'f32)

  test "property animation helpers route split and cascading setters":
    let
      splitView = newSplitView(laHorizontal, rect(0.0, 0.0, 306.0, 100.0))
      left = newFixedIntrinsicView(80.0, 40.0)
      right = newFixedIntrinsicView(90.0, 40.0)

    splitView.addPane(left)
    splitView.addPane(right)
    splitView.layoutSubtreeIfNeeded()

    let dividerAnimation = newSplitDividerPositionAnimation(
      splitView, 0, 210.0'f32, duration = initDuration(milliseconds = 100)
    )
    dividerAnimation.start()
    dividerAnimation.setProgress(0.5)
    splitView.layoutSubtreeIfNeeded()
    checkClose(splitView.positionOfDivider(0), 180.0'f32)
    checkClose(left.frame().size.width, 180.0'f32)

    let cascadingView = newCascadingView(rect(0.0, 0.0, 400.0, 160.0))
    let widthAnimation = newCascadingColumnWidthAnimation(
      cascadingView, 240.0'f32, duration = initDuration(milliseconds = 100)
    )
    widthAnimation.start()
    widthAnimation.setProgress(0.5)
    check cascadingView.conformsTo(CascadeAnimProtocol)
    checkClose(cascadingView.columnWidth(), 200.0'f32)

    let spacingAnimation = newCascadingColumnSpacingAnimation(
      cascadingView, 5.0'f32, duration = initDuration(milliseconds = 100)
    )
    spacingAnimation.start()
    spacingAnimation.setProgress(0.5)
    checkClose(cascadingView.columnSpacing(), 3.0'f32)

  test "manual scheduler ticks running animations deterministically":
    let
      scheduler = newAnimationScheduler(frameInterval = initDuration(milliseconds = 20))
      animation = newValueAnimation[float32](
        0.0'f32, 1.0'f32, duration = initDuration(milliseconds = 100)
      )

    check scheduler.startAnimation(animation)
    check scheduler.animationCount == 1

    check scheduler.tick(initDuration(milliseconds = 40)) == 1
    check animation.currentTime{} == initDuration(milliseconds = 40)
    checkClose(animation.currentValue{}, 0.4'f32)

    animation.pause()
    check scheduler.tick(initDuration(milliseconds = 20)) == 0
    check animation.currentTime{} == initDuration(milliseconds = 40)
    check scheduler.animationCount == 1

    animation.resume()
    check scheduler.tick(initDuration(milliseconds = 60)) == 1
    check animation.state{} == asStopped
    check animation.progress{} == 1.0'f32
    check scheduler.animationCount == 0

  test "manual scheduler advances repeated animations over total duration":
    let
      scheduler = newAnimationScheduler()
      animation = newValueAnimation[float32](
        0.0'f32, 10.0'f32, duration = initDuration(milliseconds = 100)
      )

    animation.loopCount = 2
    check scheduler.startAnimation(animation)

    check scheduler.tick(initDuration(milliseconds = 150)) == 1
    check animation.currentTime{} == initDuration(milliseconds = 150)
    checkClose(animation.progress{}, 0.5'f32)
    checkClose(animation.currentValue{}, 5.0'f32)
    check scheduler.animationCount == 1

    check scheduler.tick(initDuration(milliseconds = 50)) == 1
    check animation.currentTime{} == initDuration(milliseconds = 200)
    check animation.progress{} == 1.0'f32
    check animation.state{} == asStopped
    check scheduler.animationCount == 0

  test "manual scheduler uses protocol natural duration for groups":
    let
      scheduler = newAnimationScheduler()
      short = newAnimation(duration = initDuration(milliseconds = 100))
      long = newAnimation(duration = initDuration(milliseconds = 200))
      group = newParallelAnimationGroup([short, long])

    check scheduler.startAnimation(group)

    check scheduler.tick(initDuration(milliseconds = 100)) == 1
    check group.currentTime{} == initDuration(milliseconds = 100)
    checkClose(group.progress{}, 0.5'f32)
    check group.state{} == asRunning

    check scheduler.tick(initDuration(milliseconds = 100)) == 1
    check group.currentTime{} == initDuration(milliseconds = 200)
    check group.progress{} == 1.0'f32
    check group.state{} == asStopped
    check scheduler.animationCount == 0

  test "selector clock queues ticks and scheduler drains them locally":
    let
      scheduler = newAnimationScheduler(frameInterval = initDuration(milliseconds = 2))
      animation = newValueAnimation[float32](
        0.0'f32, 1.0'f32, duration = initDuration(milliseconds = 20)
      )
      clock = newAnimationSchedulerClock(frameInterval = initDuration(milliseconds = 2))

    check scheduler.startAnimation(animation)
    clock.start()
    try:
      for _ in 0 ..< 50:
        discard clock.pollQueuedTicks()
        if clock.pendingTickCount > 0:
          break
        sleep(2)

      check clock.pendingTickCount > 0
      check animation.currentTime{} == initDuration()

      let drained = scheduler.drain(clock)
      check drained > 0
      check animation.currentTime{}.inNanoseconds > 0
    finally:
      clock.stop()

  test "application drains scheduler clock ticks during run loop frames":
    let
      app = newApplication()
      view = newView(frame = rect(0.0, 0.0, 100.0, 40.0))
      animation =
        newFrameAnimation(view, rect(20.0, 10.0, 140.0, 60.0), duration = 20.ms)

    app.animationClock().frameInterval = 2.ms
    check app.startAnimation(animation)
    try:
      for _ in 0 ..< 50:
        discard app.animationClock().pollQueuedTicks()
        if app.animationClock().pendingTickCount > 0:
          break
        sleep(2)

      check app.animationClock().pendingTickCount > 0
      check app.runForFrames(1) == 1
      check animation.currentTime{}.inNanoseconds > 0
      check view.frame() != rect(0.0, 0.0, 100.0, 40.0)
    finally:
      discard app.stopAnimation(animation)
      app.stopAnimationClock()

  test "repeated selector clock lifetimes do not leak selector file descriptors":
    let before = openFileDescriptorCount()
    for _ in 0 ..< 12:
      let clock = newAnimationSchedulerClock(frameInterval = 2.ms)
      clock.start()
      clock.stop()
    let after = openFileDescriptorCount()

    if before >= 0 and after >= 0:
      check after <= before + 1

  test "shared selector clock remains alive until all clock users stop":
    let
      first = newAnimationSchedulerClock(frameInterval = 2.ms)
      second = newAnimationSchedulerClock(frameInterval = 2.ms)

    first.start()
    second.start()
    try:
      first.stop()
      for _ in 0 ..< 50:
        discard second.pollQueuedTicks()
        if second.pendingTickCount > 0:
          break
        sleep(2)

      check second.pendingTickCount > 0
    finally:
      first.stop()
      second.stop()

  test "transaction template captures view property assignments":
    let
      scheduler = newAnimationScheduler()
      view = newView(frame = rect(0.0, 0.0, 100.0, 40.0))

    let group = animationGroup(duration = 100.ms, curve = acEaseInOut):
      view.frame = rect(10.0, 20.0, 140.0, 80.0)
      view.alphaValue = 0.5'f32
      view.alphaValue = 0.25'f32

    check group.children.len == 2
    check view.frame() == rect(10.0, 20.0, 140.0, 80.0)
    checkClose(view.alphaValue(), 0.25'f32)

    check scheduler.startAnimation(group)
    check view.frame() == rect(0.0, 0.0, 100.0, 40.0)
    checkClose(view.alphaValue(), 1.0'f32)

    check scheduler.tick(50.ms) == 1
    check view.frame() == rect(5.0, 10.0, 120.0, 60.0)
    checkClose(view.alphaValue(), 0.625'f32)

    check scheduler.tick(50.ms) == 1
    check view.frame() == rect(10.0, 20.0, 140.0, 80.0)
    checkClose(view.alphaValue(), 0.25'f32)

  test "explicit transactions capture control and scroll mutations":
    let
      scheduler = newAnimationScheduler()
      indicator = newProgressIndicator(0.0, 100.0, 25.0)
      document = newView(frame = rect(0.0, 0.0, 320.0, 240.0))
      scrollView =
        newScrollView(frame = rect(0.0, 0.0, 120.0, 80.0), documentView = document)

    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.autohidePolicy = sapNever
    scrollView.tile()

    discard beginAnimationTransaction(duration = 100.ms, timing = linearTiming())
    indicator.value = 75.0'f32
    scrollView.contentOffset = initPoint(40.0, 60.0)
    let group = commitAnimationTransaction()

    check group.children.len == 2
    checkClose(indicator.value(), 75.0'f32)
    check scrollView.contentOffset() == initPoint(40.0, 60.0)

    check scheduler.startAnimation(group)
    checkClose(indicator.value(), 25.0'f32)
    check scrollView.contentOffset() == initPoint(0.0, 0.0)

    check scheduler.tick(50.ms) == 1
    checkClose(indicator.value(), 50.0'f32)
    check scrollView.contentOffset() == initPoint(20.0, 30.0)

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
