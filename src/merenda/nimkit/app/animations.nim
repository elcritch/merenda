import std/[algorithm, locks, math, monotimes, options, times]

import sigils/reactive
import sigils/threadProxies
when defined(windows):
  import sigils/threadChronos
else:
  import sigils/threadSelectors

import ../foundation/selectors
import ../foundation/types

export reactive

when defined(windows):
  type AnimationClockThreadPtr = SigilChronosThreadPtr
else:
  type AnimationClockThreadPtr = SigilSelectorThreadPtr

type
  AnimationState* = enum
    asStopped
    asPaused
    asRunning

  AnimationDirection* = enum
    adForward
    adBackward

  AnimationCurve* = enum
    acLinear
    acEaseIn
    acEaseOut
    acEaseInOut
    acCubicBezier
    acSpring

  AnimationDeletionPolicy* = enum
    adpKeepWhenStopped
    adpDeleteWhenStopped

  AnimationCadenceKind* = enum
    ackEveryFrame
    ackInterval
    ackEvents

  AnimationCadence* = object
    kind*: AnimationCadenceKind
    interval*: Duration

  AnimationDeadlineKind* = enum
    adkCadence
    adkEvent
    adkCompletion

  AnimationDeadline* = object
    time*: Duration
    kind*: AnimationDeadlineKind

  AnimationTiming* = object
    curve*: AnimationCurve
    controlPoint1*: Point
    controlPoint2*: Point
    springResponse*: float32
    springDampingRatio*: float32

  AnimationSetterSelector*[T] = Selector[T, EmptyArgs]

  AnimationScheduler* = ref object of DynamicAgent
    xAnimations: seq[Animation]
    xSchedules: seq[AnimationSchedule]
    xElapsed: Duration
    xFrameInterval: Duration
    xLastWallTick: MonoTime
    xHasWallTick: bool

  AnimationSchedule = object
    anchor: MonoTime
    anchorTime: Duration
    observedState: AnimationState

  AnimationClockTicker = ref object of AgentActor
    xFrameInterval: Duration

  AnimationSchedulerClock* = ref object of Agent
    xFrameInterval: Duration
    xThread: AnimationClockThreadPtr
    xOwnsThread: bool
    xUsesSharedThread: bool
    xTimer: SigilTimer
    xTicker: AgentProxy[AnimationClockTicker]
    xPendingDeltas: seq[Duration]

  Animation* = ref object of DynamicAgent
    xDuration: Duration
    xLoopCount: int
    xDirection: AnimationDirection
    xDeletionPolicy: AnimationDeletionPolicy
    xTiming: AnimationTiming
    xCadence: AnimationCadence
    xProgressMarks: seq[float32]
    xDeliveredMarks: seq[bool]
    state*: Sigil[AnimationState]
    currentTime*: Sigil[Duration]
    progress*: Sigil[float32]

  ValueAnimation*[T] = ref object of Animation
    startValue*: T
    endValue*: T
    currentValue*: Sigil[T]

  PropertyAnimation*[T] = ref object of ValueAnimation[T]
    target*: DynamicAgent
    setter*: AnimationSetterSelector[T]

  AnimationGroup* = ref object of Animation
    children*: seq[Animation]

  ParallelAnimationGroup* = ref object of AnimationGroup

  SequentialAnimationGroup* = ref object of AnimationGroup

  PauseAnimation* = ref object of Animation

  AnimationTransactionEntry = object
    target: DynamicAgent
    selector: SigilName
    animation: Animation

  AnimationTransaction* = ref object of DynamicAgent
    xDuration: Duration
    xTiming: AnimationTiming
    xGroup: ParallelAnimationGroup
    xEntries: seq[AnimationTransactionEntry]

proc started*(animation: Animation) {.signal.}
proc paused*(animation: Animation) {.signal.}
proc resumed*(animation: Animation) {.signal.}
proc stopped*(animation: Animation, finished: bool) {.signal.}
proc finished*(animation: Animation) {.signal.}
proc stateChanged*(
  animation: Animation, state: AnimationState, oldState: AnimationState
) {.signal.}

proc progressChanged*(animation: Animation, progress: float32) {.signal.}
proc progressMarkReached*(animation: Animation, mark: float32) {.signal.}
proc valueChanged*[T](animation: ValueAnimation[T], value: T) {.signal.}
proc schedulerTicked*(scheduler: AnimationScheduler, delta: Duration) {.signal.}
proc clockTickQueued*(clock: AnimationSchedulerClock, delta: Duration) {.signal.}
proc clockTicked(ticker: AnimationClockTicker, delta: Duration) {.signal.}

var
  animationTransactionStack {.threadvar.}: seq[AnimationTransaction]
  animationTransactionApplyDepth {.threadvar.}: int
  sharedAnimationThreadLock: Lock
  sharedAnimationThread: AnimationClockThreadPtr
  sharedAnimationThreadUseCount: int

sharedAnimationThreadLock.initLock()

func everyFrameCadence*(): AnimationCadence =
  AnimationCadence(kind: ackEveryFrame)

func intervalCadence*(interval: Duration): AnimationCadence =
  AnimationCadence(kind: ackInterval, interval: interval)

func eventCadence*(): AnimationCadence =
  AnimationCadence(kind: ackEvents)

func earlierDeadline(
    current: Option[AnimationDeadline], candidate: AnimationDeadline
): Option[AnimationDeadline] =
  if current.isNone or candidate.time < current.get().time or
      (candidate.time == current.get().time and candidate.kind > current.get().kind):
    some(candidate)
  else:
    current

func nextAlignedTime(after, interval: Duration): Duration =
  let intervalNs = interval.inNanoseconds
  if intervalNs <= 0:
    return after
  let afterNs = max(after.inNanoseconds, 0'i64)
  initDuration(nanoseconds = (afterNs div intervalNs + 1) * intervalNs)

func clampProgress(value: float32): float32 =
  min(max(value, 0.0'f32), 1.0'f32)

func lerp(a, b, progress: float32): float32 =
  a + (b - a) * progress

func lerpPoint(a, b: Point, progress: float32): Point =
  initPoint(lerp(a.x, b.x, progress), lerp(a.y, b.y, progress))

func lerpSize(a, b: Size, progress: float32): Size =
  initSize(lerp(a.width, b.width, progress), lerp(a.height, b.height, progress))

func lerpRect(a, b: Rect, progress: float32): Rect =
  rect(lerpPoint(a.origin, b.origin, progress), lerpSize(a.size, b.size, progress))

func lerpColor(a, b: Color, progress: float32): Color =
  color(
    lerp(a.r, b.r, progress),
    lerp(a.g, b.g, progress),
    lerp(a.b, b.b, progress),
    lerp(a.a, b.a, progress),
  )

func initAnimationTiming*(
    curve = acLinear,
    controlPoint1 = initPoint(0.25'f32, 0.1'f32),
    controlPoint2 = initPoint(0.25'f32, 1.0'f32),
    springResponse = 0.45'f32,
    springDampingRatio = 0.75'f32,
): AnimationTiming =
  AnimationTiming(
    curve: curve,
    controlPoint1: controlPoint1,
    controlPoint2: controlPoint2,
    springResponse: max(springResponse, 0.001'f32),
    springDampingRatio: max(springDampingRatio, 0.0'f32),
  )

func linearTiming*(): AnimationTiming =
  initAnimationTiming(
    acLinear, initPoint(0.0'f32, 0.0'f32), initPoint(1.0'f32, 1.0'f32)
  )

func easeInTiming*(): AnimationTiming =
  initAnimationTiming(acEaseIn)

func easeOutTiming*(): AnimationTiming =
  initAnimationTiming(acEaseOut)

func easeInOutTiming*(): AnimationTiming =
  initAnimationTiming(acEaseInOut)

func cubicBezierTiming*(controlPoint1, controlPoint2: Point): AnimationTiming =
  initAnimationTiming(
    acCubicBezier,
    initPoint(controlPoint1.x.clampProgress(), controlPoint1.y),
    initPoint(controlPoint2.x.clampProgress(), controlPoint2.y),
  )

func springTiming*(response = 0.45'f32, dampingRatio = 0.75'f32): AnimationTiming =
  initAnimationTiming(
    acSpring, springResponse = response, springDampingRatio = dampingRatio
  )

func cubicBezierCoordinate(t, p1, p2: float32): float32 =
  let
    u = 1.0'f32 - t
    tt = t * t
    uu = u * u
  3.0'f32 * uu * t * p1 + 3.0'f32 * u * tt * p2 + tt * t

func cubicBezierDerivative(t, p1, p2: float32): float32 =
  let u = 1.0'f32 - t
  3.0'f32 * u * u * p1 + 6.0'f32 * u * t * (p2 - p1) + 3.0'f32 * t * t * (1.0'f32 - p2)

func cubicBezierProgress(timing: AnimationTiming, progress: float32): float32 =
  var t = progress.clampProgress()
  let
    x1 = timing.controlPoint1.x.clampProgress()
    y1 = timing.controlPoint1.y
    x2 = timing.controlPoint2.x.clampProgress()
    y2 = timing.controlPoint2.y

  for _ in 0 ..< 8:
    let
      x = cubicBezierCoordinate(t, x1, x2) - progress
      derivative = cubicBezierDerivative(t, x1, x2)
    if abs(x) < 0.00001'f32 or abs(derivative) < 0.00001'f32:
      break
    t = (t - x / derivative).clampProgress()

  cubicBezierCoordinate(t, y1, y2)

func springProgress(timing: AnimationTiming, progress: float32): float32 =
  let t = progress.clampProgress()
  if t <= 0.0'f32:
    return 0.0'f32
  if t >= 1.0'f32:
    return 1.0'f32

  let
    response = max(timing.springResponse.float64, 0.001)
    dampingRatio = max(timing.springDampingRatio.float64, 0.0)
    omega = 2.0 * PI / response
    time = t.float64
  var value: float64
  if dampingRatio < 1.0:
    let
      damped = omega * sqrt(max(1.0 - dampingRatio * dampingRatio, 0.000001))
      envelope = exp(-dampingRatio * omega * time)
      correction = dampingRatio / sqrt(max(1.0 - dampingRatio * dampingRatio, 0.000001))
    value = 1.0 - envelope * (cos(damped * time) + correction * sin(damped * time))
  elif abs(dampingRatio - 1.0) <= 0.000001:
    value = 1.0 - exp(-omega * time) * (1.0 + omega * time)
  else:
    value = 1.0 - exp(-(omega / dampingRatio) * time)
  value.float32

func easedProgress*(timing: AnimationTiming, progress: float32): float32 =
  let t = progress.clampProgress()
  case timing.curve
  of acLinear:
    t
  of acEaseIn:
    t * t
  of acEaseOut:
    1.0'f32 - (1.0'f32 - t) * (1.0'f32 - t)
  of acEaseInOut:
    if t < 0.5'f32:
      2.0'f32 * t * t
    else:
      1.0'f32 - pow(-2.0'f32 * t + 2.0'f32, 2.0'f32) / 2.0'f32
  of acCubicBezier:
    timing.cubicBezierProgress(t)
  of acSpring:
    timing.springProgress(t)

func durationRatio(value, total: Duration): float32 =
  let totalNs = total.inNanoseconds
  if totalNs <= 0:
    return 1.0'f32
  clampProgress(value.inNanoseconds.float32 / totalNs.float32)

func durationAtProgress(total: Duration, progress: float32): Duration =
  initDuration(nanoseconds = int64(total.inNanoseconds.float64 * progress.float64))

func ms*(milliseconds: SomeInteger): Duration =
  initDuration(milliseconds = milliseconds.int64)

proc newPropertyAnimation*[T](
  target: DynamicAgent,
  setter: AnimationSetterSelector[T],
  startValue, endValue: T,
  duration = initDuration(milliseconds = 250),
): PropertyAnimation[T]

proc newParallelAnimationGroup*(
  children: openArray[Animation] = []
): ParallelAnimationGroup

proc currentAnimationTransaction*(): AnimationTransaction =
  if animationTransactionStack.len == 0:
    nil
  else:
    animationTransactionStack[^1]

proc isCapturingAnimationTransactions*(): bool =
  animationTransactionStack.len > 0 and animationTransactionApplyDepth == 0

template withoutAnimationTransactionCapture(body: untyped): untyped =
  inc animationTransactionApplyDepth
  try:
    body
  finally:
    dec animationTransactionApplyDepth

proc removeTransactionEntry(transaction: AnimationTransaction, index: int) =
  if index < 0 or index >= transaction.xEntries.len:
    return
  let animation = transaction.xEntries[index].animation
  transaction.xEntries.delete(index)
  if not transaction.xGroup.isNil:
    for childIndex, child in transaction.xGroup.children:
      if child == animation:
        transaction.xGroup.children.delete(childIndex)
        break

proc registerTransactionAnimation(
    transaction: AnimationTransaction,
    target: DynamicAgent,
    selector: SigilName,
    animation: Animation,
) =
  if animation.isNil:
    return
  for index, entry in transaction.xEntries:
    if entry.target == target and entry.selector == selector:
      transaction.xEntries[index].animation = animation
      if not transaction.xGroup.isNil:
        for childIndex, child in transaction.xGroup.children:
          if child == entry.animation:
            transaction.xGroup.children[childIndex] = animation
            return
      break
  transaction.xEntries.add(
    AnimationTransactionEntry(target: target, selector: selector, animation: animation)
  )
  if not transaction.xGroup.isNil:
    transaction.xGroup.children.add(animation)

proc newAnimationTransaction*(
    duration = initDuration(milliseconds = 250), timing = linearTiming()
): AnimationTransaction =
  result = AnimationTransaction(
    xDuration: duration, xTiming: timing, xGroup: newParallelAnimationGroup()
  )

proc newAnimationTransaction*(
    duration: Duration, curve: AnimationCurve
): AnimationTransaction =
  newAnimationTransaction(duration, initAnimationTiming(curve))

proc duration*(transaction: AnimationTransaction): Duration =
  transaction.xDuration

proc timing*(transaction: AnimationTransaction): AnimationTiming =
  transaction.xTiming

proc animationGroup*(transaction: AnimationTransaction): ParallelAnimationGroup =
  transaction.xGroup

proc animationCount*(transaction: AnimationTransaction): int =
  if transaction.xGroup.isNil: 0 else: transaction.xGroup.children.len

proc addTransactionAnimation*(
    transaction: AnimationTransaction, animation: Animation
): bool {.discardable.} =
  if animation.isNil:
    return false
  transaction.xGroup.children.add(animation)
  true

proc beginAnimationTransaction*(transaction: AnimationTransaction) =
  animationTransactionStack.add(transaction)

proc beginAnimationTransaction*(
    duration = initDuration(milliseconds = 250), timing = linearTiming()
): AnimationTransaction {.discardable.} =
  result = newAnimationTransaction(duration, timing)
  beginAnimationTransaction(result)

proc beginAnimationTransaction*(
    duration: Duration, curve: AnimationCurve
): AnimationTransaction {.discardable.} =
  result = newAnimationTransaction(duration, curve)
  beginAnimationTransaction(result)

proc cancelAnimationTransaction*(): AnimationTransaction {.discardable.} =
  if animationTransactionStack.len == 0:
    return nil
  result = animationTransactionStack.pop()

proc commitAnimationTransaction*(): ParallelAnimationGroup {.discardable.} =
  let transaction = cancelAnimationTransaction()
  if transaction.isNil:
    return nil
  result = transaction.xGroup
  let parent = currentAnimationTransaction()
  if not parent.isNil and not result.isNil:
    discard parent.addTransactionAnimation(result)

proc recordPropertyAnimation*[T](
    target: DynamicAgent, setter: AnimationSetterSelector[T], startValue, endValue: T
): bool {.discardable.} =
  let transaction = currentAnimationTransaction()
  if transaction.isNil or target.isNil or not isCapturingAnimationTransactions():
    return false
  let selector = selectorName(setter)
  for index, entry in transaction.xEntries:
    if entry.target == target and entry.selector == selector:
      if entry.animation of PropertyAnimation[T]:
        let animation = PropertyAnimation[T](entry.animation)
        when compiles(animation.startValue == endValue):
          if animation.startValue == endValue:
            transaction.removeTransactionEntry(index)
            return true
        animation.endValue = endValue
        animation.xDuration = transaction.xDuration
        animation.xTiming = transaction.xTiming
        return true
      transaction.removeTransactionEntry(index)
      break

  when compiles(startValue == endValue):
    if startValue == endValue:
      return true

  let animation =
    newPropertyAnimation[T](target, setter, startValue, endValue, transaction.xDuration)
  animation.xTiming = transaction.xTiming
  transaction.registerTransactionAnimation(target, selector, animation)
  true

template animationGroup*(
    duration: Duration = initDuration(milliseconds = 250),
    curve: AnimationCurve = acLinear,
    body: untyped,
): ParallelAnimationGroup =
  block:
    discard beginAnimationTransaction(duration, curve)
    try:
      body
      commitAnimationTransaction()
    except:
      discard cancelAnimationTransaction()
      raise

proc rawState(animation: Animation): AnimationState =
  if animation.state.isNil:
    asStopped
  else:
    animation.state{}

proc rawCurrentTime(animation: Animation): Duration =
  if animation.currentTime.isNil:
    initDuration()
  else:
    animation.currentTime{}

proc rawProgress(animation: Animation): float32 =
  if animation.progress.isNil:
    0.0'f32
  else:
    animation.progress{}

proc emitClockTick(ticker: AnimationClockTicker) {.slot.} =
  emit ticker.clockTicked(ticker.xFrameInterval)

proc queueClockTick(clock: AnimationSchedulerClock, delta: Duration) {.slot.} =
  clock.xPendingDeltas.add(delta)
  emit clock.clockTickQueued(delta)

proc resetDeliveredMarks(animation: Animation) =
  animation.xDeliveredMarks.setLen(animation.xProgressMarks.len)
  for index in 0 ..< animation.xDeliveredMarks.len:
    animation.xDeliveredMarks[index] = false

proc sortAndDedupeMarks(marks: var seq[float32]) =
  marks.sort()
  var writeIndex = 0
  for mark in marks:
    let normalized = mark.clampProgress()
    if writeIndex == 0 or abs(marks[writeIndex - 1] - normalized) > 0.00001'f32:
      marks[writeIndex] = normalized
      inc writeIndex
  marks.setLen(writeIndex)

proc setAnimationState(animation: Animation, nextState: AnimationState) =
  let previous = animation.rawState()
  if previous == nextState:
    return
  animation.state <- nextState
  emit animation.stateChanged(nextState, previous)

method applyValue*(animation: Animation) {.base.} =
  discard

method adjustedProgress*(animation: Animation, progress: float32): float32 {.base.} =
  animation.xTiming.easedProgress(progress)

func steppedValue[T](animation: ValueAnimation[T], progress: float32): T =
  if progress >= 1.0'f32: animation.endValue else: animation.startValue

method interpolatedValue*(
    animation: ValueAnimation[float32], progress: float32
): float32 {.base.} =
  lerp(animation.startValue, animation.endValue, progress)

method interpolatedValue*(
    animation: ValueAnimation[Point], progress: float32
): Point {.base.} =
  lerpPoint(animation.startValue, animation.endValue, progress)

method interpolatedValue*(
    animation: ValueAnimation[Size], progress: float32
): Size {.base.} =
  lerpSize(animation.startValue, animation.endValue, progress)

method interpolatedValue*(
    animation: ValueAnimation[Rect], progress: float32
): Rect {.base.} =
  lerpRect(animation.startValue, animation.endValue, progress)

method interpolatedValue*(
    animation: ValueAnimation[Color], progress: float32
): Color {.base.} =
  lerpColor(animation.startValue, animation.endValue, progress)

proc updateCurrentValue[T](animation: ValueAnimation[T]) =
  if animation.isNil or animation.currentValue.isNil:
    return
  let progress = animation.adjustedProgress(animation.rawProgress())
  let nextValue =
    when T is float32:
      animation.interpolatedValue(progress)
    elif T is Point:
      animation.interpolatedValue(progress)
    elif T is Size:
      animation.interpolatedValue(progress)
    elif T is Rect:
      animation.interpolatedValue(progress)
    elif T is Color:
      animation.interpolatedValue(progress)
    else:
      animation.steppedValue(progress)
  animation.currentValue <- nextValue
  emit animation.valueChanged(nextValue)

method applyValue*(animation: ValueAnimation[float32]) =
  animation.updateCurrentValue()

method applyValue*(animation: ValueAnimation[Point]) =
  animation.updateCurrentValue()

method applyValue*(animation: ValueAnimation[Size]) =
  animation.updateCurrentValue()

method applyValue*(animation: ValueAnimation[Rect]) =
  animation.updateCurrentValue()

method applyValue*(animation: ValueAnimation[Color]) =
  animation.updateCurrentValue()

method applyValue*(animation: PropertyAnimation[float32]) =
  procCall ValueAnimation[float32](animation).applyValue()
  if not animation.target.isNil:
    withoutAnimationTransactionCapture:
      discard animation.target.sendIfHandled(animation.setter, animation.currentValue{})

method applyValue*(animation: PropertyAnimation[Point]) =
  procCall ValueAnimation[Point](animation).applyValue()
  if not animation.target.isNil:
    withoutAnimationTransactionCapture:
      discard animation.target.sendIfHandled(animation.setter, animation.currentValue{})

method applyValue*(animation: PropertyAnimation[Size]) =
  procCall ValueAnimation[Size](animation).applyValue()
  if not animation.target.isNil:
    withoutAnimationTransactionCapture:
      discard animation.target.sendIfHandled(animation.setter, animation.currentValue{})

method applyValue*(animation: PropertyAnimation[Rect]) =
  procCall ValueAnimation[Rect](animation).applyValue()
  if not animation.target.isNil:
    withoutAnimationTransactionCapture:
      discard animation.target.sendIfHandled(animation.setter, animation.currentValue{})

method applyValue*(animation: PropertyAnimation[Color]) =
  procCall ValueAnimation[Color](animation).applyValue()
  if not animation.target.isNil:
    withoutAnimationTransactionCapture:
      discard animation.target.sendIfHandled(animation.setter, animation.currentValue{})

proc setCurrentTime*(animation: Animation, currentTime: Duration)

proc baseNextDeadline(
    animation: Animation, after, frameInterval, duration, total: Duration
): Option[AnimationDeadline] =
  let
    durationNs = duration.inNanoseconds
    totalNs = total.inNanoseconds

  case animation.xCadence.kind
  of ackEveryFrame:
    result = result.earlierDeadline(
      AnimationDeadline(time: nextAlignedTime(after, frameInterval), kind: adkCadence)
    )
  of ackInterval:
    if animation.xCadence.interval.inNanoseconds > 0:
      result = result.earlierDeadline(
        AnimationDeadline(
          time: nextAlignedTime(after, animation.xCadence.interval), kind: adkCadence
        )
      )
  of ackEvents:
    discard

  if durationNs > 0:
    let afterNs = max(after.inNanoseconds, 0'i64)
    if animation.xLoopCount < 0 or animation.xLoopCount > 1:
      let loopBoundary =
        initDuration(nanoseconds = (afterNs div durationNs + 1) * durationNs)
      if totalNs < 0 or loopBoundary.inNanoseconds <= totalNs:
        result =
          result.earlierDeadline(AnimationDeadline(time: loopBoundary, kind: adkEvent))

    for mark in animation.xProgressMarks:
      let normalizedMark = mark.clampProgress()
      let markProgress =
        if animation.xDirection == adBackward:
          1.0'f32 - normalizedMark
        else:
          normalizedMark
      let markOffset = int64(round(markProgress.float64 * durationNs.float64))
      var markTimeNs = (afterNs div durationNs) * durationNs + markOffset
      if markTimeNs <= afterNs:
        markTimeNs += durationNs
      if totalNs < 0 or markTimeNs <= totalNs:
        result = result.earlierDeadline(
          AnimationDeadline(
            time: initDuration(nanoseconds = markTimeNs), kind: adkEvent
          )
        )

  if totalNs >= 0 and (total > after or (totalNs == 0 and after.inNanoseconds <= 0)):
    result = result.earlierDeadline(AnimationDeadline(time: total, kind: adkCompletion))

protocol AnimationProtocol {.selectorScope: protocol.} from Animation:
  method updateCurrentTime*(animation: Animation, currentTime: Duration) =
    discard currentTime
    animation.applyValue()

  method updateState*(
      animation: Animation, state: AnimationState, oldState: AnimationState
  ) =
    discard animation
    discard state
    discard oldState

  method naturalDuration*(animation: Animation): Duration =
    animation.xDuration

  method totalDuration*(animation: Animation): Duration =
    if animation.xLoopCount < 0:
      initDuration(nanoseconds = -1)
    else:
      initDuration(
        nanoseconds = animation.naturalDuration().inNanoseconds * animation.xLoopCount
      )

  method nextDeadline*(
      animation: Animation, after, frameInterval: Duration
  ): Option[AnimationDeadline] =
    animation.baseNextDeadline(
      after, frameInterval, animation.naturalDuration(), animation.totalDuration()
    )

protocol FloatValueAnimationProtocol of AnimationProtocol:
  method updateCurrentTime*(animation: ValueAnimation[float32], currentTime: Duration) =
    discard currentTime
    animation.applyValue()

protocol PointValueAnimationProtocol of AnimationProtocol:
  method updateCurrentTime*(animation: ValueAnimation[Point], currentTime: Duration) =
    discard currentTime
    animation.applyValue()

protocol SizeValueAnimationProtocol of AnimationProtocol:
  method updateCurrentTime*(animation: ValueAnimation[Size], currentTime: Duration) =
    discard currentTime
    animation.applyValue()

protocol RectValueAnimationProtocol of AnimationProtocol:
  method updateCurrentTime*(animation: ValueAnimation[Rect], currentTime: Duration) =
    discard currentTime
    animation.applyValue()

protocol ColorValueAnimationProtocol of AnimationProtocol:
  method updateCurrentTime*(animation: ValueAnimation[Color], currentTime: Duration) =
    discard currentTime
    animation.applyValue()

protocol FloatPropertyAnimationProtocol of AnimationProtocol:
  method updateCurrentTime*(
      animation: PropertyAnimation[float32], currentTime: Duration
  ) =
    discard currentTime
    animation.applyValue()

protocol PointPropertyAnimationProtocol of AnimationProtocol:
  method updateCurrentTime*(
      animation: PropertyAnimation[Point], currentTime: Duration
  ) =
    discard currentTime
    animation.applyValue()

protocol SizePropertyAnimationProtocol of AnimationProtocol:
  method updateCurrentTime*(animation: PropertyAnimation[Size], currentTime: Duration) =
    discard currentTime
    animation.applyValue()

protocol RectPropertyAnimationProtocol of AnimationProtocol:
  method updateCurrentTime*(animation: PropertyAnimation[Rect], currentTime: Duration) =
    discard currentTime
    animation.applyValue()

protocol ColorPropertyAnimationProtocol of AnimationProtocol:
  method updateCurrentTime*(
      animation: PropertyAnimation[Color], currentTime: Duration
  ) =
    discard currentTime
    animation.applyValue()

proc boundedChildTime(child: Animation, currentTime: Duration): Duration =
  if currentTime.inNanoseconds <= 0:
    return initDuration()
  let total = child.totalDuration()
  if total.inNanoseconds >= 0 and currentTime > total: total else: currentTime

protocol ParallelAnimationGroupProtocol of AnimationProtocol:
  method updateCurrentTime*(animation: ParallelAnimationGroup, currentTime: Duration) =
    for child in animation.children:
      child.setCurrentTime(child.boundedChildTime(currentTime))

  method naturalDuration*(animation: ParallelAnimationGroup): Duration =
    result = Animation(animation).xDuration
    for child in animation.children:
      let childDuration = child.totalDuration()
      if childDuration.inNanoseconds < 0:
        return childDuration
      if childDuration > result:
        result = childDuration

  method nextDeadline*(
      animation: ParallelAnimationGroup, after, frameInterval: Duration
  ): Option[AnimationDeadline] =
    result = Animation(animation).baseNextDeadline(
        after, frameInterval, animation.naturalDuration(), animation.totalDuration()
      )
    for child in animation.children:
      if child.isNil:
        continue
      let childDeadline = child.nextDeadline(after, frameInterval)
      if childDeadline.isSome:
        result = result.earlierDeadline(childDeadline.get())

protocol SequentialAnimationGroupProtocol of AnimationProtocol:
  method updateCurrentTime*(
      animation: SequentialAnimationGroup, currentTime: Duration
  ) =
    var remaining = currentTime
    for child in animation.children:
      if child.isNil:
        continue
      child.setCurrentTime(child.boundedChildTime(remaining))
      let childDuration = child.totalDuration()
      if childDuration.inNanoseconds < 0:
        break
      remaining = remaining - childDuration

  method naturalDuration*(animation: SequentialAnimationGroup): Duration =
    result = Animation(animation).xDuration
    for child in animation.children:
      let childDuration = child.totalDuration()
      if childDuration.inNanoseconds < 0:
        return childDuration
      result = result + childDuration

  method nextDeadline*(
      animation: SequentialAnimationGroup, after, frameInterval: Duration
  ): Option[AnimationDeadline] =
    result = Animation(animation).baseNextDeadline(
        after, frameInterval, animation.naturalDuration(), animation.totalDuration()
      )
    var offset = initDuration()
    for child in animation.children:
      if child.isNil:
        continue
      let childDuration = child.totalDuration()
      if childDuration.inNanoseconds == 0:
        continue
      if childDuration.inNanoseconds < 0 or after < offset + childDuration:
        let localAfter =
          if after > offset:
            after - offset
          else:
            initDuration()
        let childDeadline = child.nextDeadline(localAfter, frameInterval)
        if childDeadline.isSome:
          var translated = childDeadline.get()
          translated.time = translated.time + offset
          result = result.earlierDeadline(translated)
        break
      offset = offset + childDuration

proc initAnimationFields*(
    animation: Animation,
    duration = initDuration(milliseconds = 250),
    loopCount = 1,
    direction = adForward,
) =
  animation.xDuration = duration
  animation.xLoopCount = loopCount
  animation.xDirection = direction
  animation.xDeletionPolicy = adpKeepWhenStopped
  animation.xTiming = linearTiming()
  animation.xCadence = everyFrameCadence()
  animation.state = newSigil(asStopped)
  animation.currentTime = newSigil(initDuration())
  animation.progress = newSigil(0.0'f32)
  discard animation.withProto()

proc newAnimation*(
    duration = initDuration(milliseconds = 250), loopCount = 1, direction = adForward
): Animation =
  result = Animation()
  initAnimationFields(result, duration, loopCount, direction)

proc initValueAnimationFields*[T](
    animation: ValueAnimation[T],
    startValue, endValue: T,
    duration = initDuration(milliseconds = 250),
) =
  if animation.isNil:
    return
  initAnimationFields(animation, duration)
  animation.startValue = startValue
  animation.endValue = endValue
  animation.currentValue = newSigil(startValue)
  when T is float32:
    discard animation.withProtocol(FloatValueAnimationProtocol)
  elif T is Point:
    discard animation.withProtocol(PointValueAnimationProtocol)
  elif T is Size:
    discard animation.withProtocol(SizeValueAnimationProtocol)
  elif T is Rect:
    discard animation.withProtocol(RectValueAnimationProtocol)
  elif T is Color:
    discard animation.withProtocol(ColorValueAnimationProtocol)

proc newValueAnimation*[T](
    startValue, endValue: T, duration = initDuration(milliseconds = 250)
): ValueAnimation[T] =
  result = ValueAnimation[T]()
  initValueAnimationFields(result, startValue, endValue, duration)

proc initPropertyAnimationFields*[T](
    animation: PropertyAnimation[T],
    target: DynamicAgent,
    setter: AnimationSetterSelector[T],
    startValue, endValue: T,
    duration = initDuration(milliseconds = 250),
) =
  if animation.isNil:
    return
  initValueAnimationFields(animation, startValue, endValue, duration)
  animation.target = target
  animation.setter = setter
  when T is float32:
    discard animation.withProtocol(FloatPropertyAnimationProtocol)
  elif T is Point:
    discard animation.withProtocol(PointPropertyAnimationProtocol)
  elif T is Size:
    discard animation.withProtocol(SizePropertyAnimationProtocol)
  elif T is Rect:
    discard animation.withProtocol(RectPropertyAnimationProtocol)
  elif T is Color:
    discard animation.withProtocol(ColorPropertyAnimationProtocol)

proc newPropertyAnimation*[T](
    target: DynamicAgent,
    setter: AnimationSetterSelector[T],
    startValue, endValue: T,
    duration = initDuration(milliseconds = 250),
): PropertyAnimation[T] =
  result = PropertyAnimation[T]()
  initPropertyAnimationFields(result, target, setter, startValue, endValue, duration)

proc initAnimationGroupFields*(
    group: AnimationGroup,
    children: openArray[Animation] = [],
    duration = initDuration(),
) =
  initAnimationFields(group, duration)
  group.xCadence = eventCadence()
  group.children = @children

proc newParallelAnimationGroup*(
    children: openArray[Animation] = []
): ParallelAnimationGroup =
  result = ParallelAnimationGroup()
  initAnimationGroupFields(result, children)
  discard result.withProtocol(ParallelAnimationGroupProtocol)

proc newSequentialAnimationGroup*(
    children: openArray[Animation] = []
): SequentialAnimationGroup =
  result = SequentialAnimationGroup()
  initAnimationGroupFields(result, children)
  discard result.withProtocol(SequentialAnimationGroupProtocol)

proc newPauseAnimation*(duration: Duration): PauseAnimation =
  result = PauseAnimation()
  initAnimationFields(result, duration)
  result.xCadence = eventCadence()

proc duration*(animation: Animation): Duration =
  animation.naturalDuration()

proc `duration=`*(animation: Animation, duration: Duration) =
  animation.xDuration = duration

proc loopCount*(animation: Animation): int =
  animation.xLoopCount

proc `loopCount=`*(animation: Animation, loopCount: int) =
  animation.xLoopCount = loopCount

proc progressAtTime(animation: Animation, currentTime: Duration): float32 =
  let durationNs = animation.duration().inNanoseconds
  if durationNs <= 0:
    return if animation.xDirection == adBackward: 0.0'f32 else: 1.0'f32

  let
    elapsedNs = max(currentTime.inNanoseconds, 0)
    totalNs = animation.totalDuration().inNanoseconds
  if totalNs >= 0 and elapsedNs >= totalNs:
    return if animation.xDirection == adBackward: 0.0'f32 else: 1.0'f32

  let loopNs = elapsedNs mod durationNs
  let forwardProgress = clampProgress(loopNs.float32 / durationNs.float32)
  if animation.xDirection == adBackward:
    1.0'f32 - forwardProgress
  else:
    forwardProgress

proc direction*(animation: Animation): AnimationDirection =
  animation.xDirection

proc `direction=`*(animation: Animation, direction: AnimationDirection) =
  animation.xDirection = direction

proc deletionPolicy*(animation: Animation): AnimationDeletionPolicy =
  animation.xDeletionPolicy

proc `deletionPolicy=`*(animation: Animation, deletionPolicy: AnimationDeletionPolicy) =
  animation.xDeletionPolicy = deletionPolicy

proc timing*(animation: Animation): AnimationTiming =
  animation.xTiming

proc `timing=`*(animation: Animation, timing: AnimationTiming) =
  animation.xTiming = timing

proc cadence*(animation: Animation): AnimationCadence =
  animation.xCadence

proc `cadence=`*(animation: Animation, cadence: AnimationCadence) =
  animation.xCadence = cadence

proc curve*(animation: Animation): AnimationCurve =
  animation.timing.curve

proc `curve=`*(animation: Animation, curve: AnimationCurve) =
  animation.xTiming.curve = curve

proc setCubicBezierTiming*(animation: Animation, controlPoint1, controlPoint2: Point) =
  animation.xTiming = cubicBezierTiming(controlPoint1, controlPoint2)

proc setSpringTiming*(
    animation: Animation, response = 0.45'f32, dampingRatio = 0.75'f32
) =
  animation.xTiming = springTiming(response, dampingRatio)

proc isRunning*(animation: Animation): bool =
  animation.rawState() == asRunning

proc isPaused*(animation: Animation): bool =
  animation.rawState() == asPaused

proc isStopped*(animation: Animation): bool =
  animation.rawState() == asStopped

proc currentLoop*(animation: Animation): int =
  if animation.xDuration.inNanoseconds <= 0:
    return 0
  let elapsed = animation.rawCurrentTime().inNanoseconds
  int(elapsed div animation.xDuration.inNanoseconds)

proc currentLoopTime*(animation: Animation): Duration =
  let durationNs = animation.xDuration.inNanoseconds
  if durationNs <= 0:
    return initDuration()
  let elapsed = animation.rawCurrentTime().inNanoseconds
  initDuration(nanoseconds = elapsed mod durationNs)

proc progressMarks*(animation: Animation): seq[float32] =
  animation.xProgressMarks

proc `progressMarks=`*(animation: Animation, marks: openArray[float32]) =
  animation.xProgressMarks = @marks
  animation.xProgressMarks.sortAndDedupeMarks()
  animation.resetDeliveredMarks()

proc addProgressMark*(animation: Animation, mark: float32) =
  animation.xProgressMarks.add mark.clampProgress()
  animation.xProgressMarks.sortAndDedupeMarks()
  animation.resetDeliveredMarks()

proc removeProgressMark*(animation: Animation, mark: float32) =
  let normalized = mark.clampProgress()
  for index in countdown(animation.xProgressMarks.len - 1, 0):
    if abs(animation.xProgressMarks[index] - normalized) <= 0.00001'f32:
      animation.xProgressMarks.delete(index)
  animation.resetDeliveredMarks()

proc clearProgressMarks*(animation: Animation) =
  animation.xProgressMarks.setLen(0)
  animation.xDeliveredMarks.setLen(0)

proc emitProgressMarks(animation: Animation, previous, next: float32) =
  if animation.xDeliveredMarks.len != animation.xProgressMarks.len:
    animation.resetDeliveredMarks()
  let movingBackward = next < previous
  if movingBackward:
    for index, mark in animation.xProgressMarks:
      if mark >= next:
        animation.xDeliveredMarks[index] = false
  for index, mark in animation.xProgressMarks:
    if animation.xDeliveredMarks[index]:
      continue
    let reached =
      if movingBackward:
        next <= mark and mark < previous
      else:
        previous < mark and mark <= next
    if reached:
      animation.xDeliveredMarks[index] = true
      emit animation.progressMarkReached(mark)

proc setProgress*(animation: Animation, progress: float32) =
  let
    previous = animation.rawProgress()
    next = progress.clampProgress()
  if abs(previous - next) <= 0.00001'f32:
    return
  animation.progress <- next
  animation.currentTime <- animation.duration.durationAtProgress(next)
  animation.emitProgressMarks(previous, next)
  animation.updateCurrentTime(animation.rawCurrentTime())
  emit animation.progressChanged(next)

proc setCurrentTime*(animation: Animation, currentTime: Duration) =
  let previousProgress = animation.rawProgress()
  let totalDuration = animation.totalDuration()
  let nextTime =
    if totalDuration.inNanoseconds >= 0 and currentTime > totalDuration:
      totalDuration
    elif currentTime.inNanoseconds < 0:
      initDuration()
    else:
      currentTime
  let nextProgress = animation.progressAtTime(nextTime)
  animation.progress <- nextProgress
  animation.currentTime <- nextTime
  animation.emitProgressMarks(previousProgress, nextProgress)
  animation.updateCurrentTime(nextTime)
  emit animation.progressChanged(nextProgress)

proc start*(animation: Animation) =
  if animation.isRunning:
    return
  let oldState = animation.rawState()
  animation.currentTime <- initDuration()
  animation.progress <- (if animation.xDirection == adBackward: 1.0'f32 else: 0.0'f32)
  animation.resetDeliveredMarks()
  animation.setAnimationState(asRunning)
  animation.updateState(asRunning, oldState)
  animation.updateCurrentTime(animation.rawCurrentTime())
  emit animation.started()

proc pause*(animation: Animation) =
  if animation.rawState() != asRunning:
    return
  let oldState = animation.rawState()
  animation.setAnimationState(asPaused)
  animation.updateState(asPaused, oldState)
  emit animation.paused()

proc resume*(animation: Animation) =
  if animation.rawState() != asPaused:
    return
  let oldState = animation.rawState()
  animation.setAnimationState(asRunning)
  animation.updateState(asRunning, oldState)
  emit animation.resumed()

proc stop*(animation: Animation, finished = false) =
  if animation.rawState() == asStopped:
    return
  let oldState = animation.rawState()
  if finished:
    animation.setProgress(if animation.xDirection == adBackward: 0.0'f32 else: 1.0'f32)
  animation.setAnimationState(asStopped)
  animation.updateState(asStopped, oldState)
  emit animation.stopped(finished)
  if finished:
    emit animation.finished()

proc initAnimationSchedulerFields*(
    scheduler: AnimationScheduler, frameInterval = initDuration(milliseconds = 16)
) =
  scheduler.xFrameInterval =
    if frameInterval.inNanoseconds <= 0:
      initDuration(milliseconds = 16)
    else:
      frameInterval
  scheduler.xElapsed = initDuration()
  scheduler.xHasWallTick = false

proc newAnimationScheduler*(
    frameInterval = initDuration(milliseconds = 16)
): AnimationScheduler =
  result = AnimationScheduler()
  initAnimationSchedulerFields(result, frameInterval)

proc frameInterval*(scheduler: AnimationScheduler): Duration =
  scheduler.xFrameInterval

proc `frameInterval=`*(scheduler: AnimationScheduler, interval: Duration) =
  scheduler.xFrameInterval =
    if interval.inNanoseconds <= 0:
      initDuration(milliseconds = 16)
    else:
      interval

proc elapsed*(scheduler: AnimationScheduler): Duration =
  scheduler.xElapsed

proc scheduledAnimations*(scheduler: AnimationScheduler): seq[Animation] =
  for animation in scheduler.xAnimations:
    result.add(animation)

proc animationCount*(scheduler: AnimationScheduler): int =
  scheduler.xAnimations.len

proc containsAnimation*(scheduler: AnimationScheduler, animation: Animation): bool =
  if animation.isNil:
    return false
  for scheduled in scheduler.xAnimations:
    if scheduled == animation:
      return true

proc scheduleIndex(scheduler: AnimationScheduler, animation: Animation): int =
  if animation.isNil:
    return -1
  for index, scheduled in scheduler.xAnimations:
    if scheduled == animation:
      return index
  -1

proc resetSchedule(scheduler: AnimationScheduler, index: int, now: MonoTime) =
  scheduler.xSchedules[index] = AnimationSchedule(
    anchor: now,
    anchorTime: scheduler.xAnimations[index].rawCurrentTime(),
    observedState: scheduler.xAnimations[index].rawState(),
  )

proc deleteSchedule(scheduler: AnimationScheduler, index: int) =
  scheduler.xAnimations.delete(index)
  scheduler.xSchedules.delete(index)
  if scheduler.xAnimations.len == 0:
    scheduler.xHasWallTick = false

proc syncSchedule(
    schedule: var AnimationSchedule, animation: Animation, now: MonoTime
) =
  let state = animation.rawState()
  if state == schedule.observedState:
    return
  schedule.anchor = now
  schedule.anchorTime = animation.rawCurrentTime()
  schedule.observedState = state

proc scheduleTime(schedule: AnimationSchedule, animationTime: Duration): MonoTime =
  schedule.anchor + (animationTime - schedule.anchorTime)

proc currentScheduleTime(schedule: AnimationSchedule, now: MonoTime): Duration =
  let elapsed = now - schedule.anchor
  if elapsed.inNanoseconds <= 0:
    schedule.anchorTime
  else:
    schedule.anchorTime + elapsed

proc addAnimation*(scheduler: AnimationScheduler, animation: Animation): bool =
  if animation.isNil or scheduler.containsAnimation(animation):
    return false
  let now = getMonoTime()
  scheduler.xAnimations.add(animation)
  scheduler.xSchedules.add(
    AnimationSchedule(
      anchor: now,
      anchorTime: animation.rawCurrentTime(),
      observedState: animation.rawState(),
    )
  )
  if scheduler.xAnimations.len == 1:
    scheduler.xLastWallTick = now
    scheduler.xHasWallTick = true
  true

proc removeAnimation*(scheduler: AnimationScheduler, animation: Animation): bool =
  if animation.isNil:
    return false
  for index, scheduled in scheduler.xAnimations:
    if scheduled == animation:
      scheduler.deleteSchedule(index)
      return true

proc clearAnimations*(scheduler: AnimationScheduler) =
  scheduler.xAnimations.setLen(0)
  scheduler.xSchedules.setLen(0)
  scheduler.xHasWallTick = false

proc startAnimationAt*(
    scheduler: AnimationScheduler, animation: Animation, now: MonoTime
): bool =
  if animation.isNil:
    return false
  var index = scheduler.scheduleIndex(animation)
  if index < 0:
    scheduler.xAnimations.add(animation)
    scheduler.xSchedules.add(default(AnimationSchedule))
    index = scheduler.xAnimations.high
  animation.start()
  scheduler.resetSchedule(index, now)
  if scheduler.xAnimations.len == 1:
    scheduler.xLastWallTick = now
    scheduler.xHasWallTick = true
  true

proc startAnimation*(scheduler: AnimationScheduler, animation: Animation): bool =
  scheduler.startAnimationAt(animation, getMonoTime())

proc stopAnimation*(
    scheduler: AnimationScheduler, animation: Animation, finished = false
): bool =
  if animation.isNil:
    return false
  animation.stop(finished)
  scheduler.removeAnimation(animation)

proc tick*(scheduler: AnimationScheduler, delta: Duration): int {.discardable.} =
  if delta.inNanoseconds <= 0:
    return 0

  scheduler.xElapsed = scheduler.xElapsed + delta
  var index = 0
  while index < scheduler.xAnimations.len:
    let animation = scheduler.xAnimations[index]
    if animation.isNil or animation.isStopped:
      scheduler.deleteSchedule(index)
      continue
    if not animation.isRunning:
      inc index
      continue

    let
      totalDuration = animation.totalDuration()
      nextTime = animation.rawCurrentTime() + delta
    if totalDuration.inNanoseconds == 0:
      animation.stop(finished = true)
      scheduler.deleteSchedule(index)
    elif totalDuration.inNanoseconds >= 0 and nextTime >= totalDuration:
      animation.setCurrentTime(totalDuration)
      animation.stop(finished = true)
      scheduler.deleteSchedule(index)
    else:
      animation.setCurrentTime(nextTime)
      inc index
    inc result

  emit scheduler.schedulerTicked(delta)

  let now = getMonoTime()
  for index in 0 ..< scheduler.xSchedules.len:
    scheduler.resetSchedule(index, now)
  if scheduler.xAnimations.len > 0:
    scheduler.xLastWallTick = now
    scheduler.xHasWallTick = true

proc tick*(scheduler: AnimationScheduler): int {.discardable.} =
  scheduler.tick(scheduler.frameInterval)

proc nextDeadline*(scheduler: AnimationScheduler, now: MonoTime): Option[MonoTime] =
  for index in 0 ..< scheduler.xAnimations.len:
    let animation = scheduler.xAnimations[index]
    if animation.isNil:
      continue
    scheduler.xSchedules[index].syncSchedule(animation, now)
    if animation.rawState() != asRunning:
      continue
    let deadline =
      animation.nextDeadline(animation.rawCurrentTime(), scheduler.frameInterval)
    if deadline.isNone:
      continue
    let candidate = scheduler.xSchedules[index].scheduleTime(deadline.get().time)
    if result.isNone or candidate < result.get():
      result = some(candidate)

proc nextDeadline*(scheduler: AnimationScheduler): Option[MonoTime] =
  scheduler.nextDeadline(getMonoTime())

proc advance*(scheduler: AnimationScheduler, now: MonoTime): int {.discardable.} =
  let
    hadWallTick = scheduler.xHasWallTick
    lastWallTick = scheduler.xLastWallTick
  var index = 0
  while index < scheduler.xAnimations.len:
    let animation = scheduler.xAnimations[index]
    if animation.isNil or animation.isStopped:
      scheduler.deleteSchedule(index)
      continue

    scheduler.xSchedules[index].syncSchedule(animation, now)
    if not animation.isRunning:
      inc index
      continue

    let deadline =
      animation.nextDeadline(animation.rawCurrentTime(), scheduler.frameInterval)
    if deadline.isNone or
        scheduler.xSchedules[index].scheduleTime(deadline.get().time) > now:
      inc index
      continue

    let
      totalDuration = animation.totalDuration()
      nextTime = scheduler.xSchedules[index].currentScheduleTime(now)
    if totalDuration.inNanoseconds == 0:
      animation.stop(finished = true)
      scheduler.deleteSchedule(index)
    elif totalDuration.inNanoseconds >= 0 and nextTime >= totalDuration:
      animation.setCurrentTime(totalDuration)
      animation.stop(finished = true)
      scheduler.deleteSchedule(index)
    else:
      animation.setCurrentTime(nextTime)
      inc index
    inc result

  if result > 0:
    let delta =
      if hadWallTick:
        now - lastWallTick
      else:
        scheduler.frameInterval
    scheduler.xElapsed = scheduler.xElapsed + delta
    scheduler.xLastWallTick = now
    scheduler.xHasWallTick = scheduler.xAnimations.len > 0
    emit scheduler.schedulerTicked(delta)

proc advance*(scheduler: AnimationScheduler): int {.discardable.} =
  scheduler.advance(getMonoTime())

proc initAnimationSchedulerClockFields*(
    clock: AnimationSchedulerClock, frameInterval = initDuration(milliseconds = 16)
) =
  clock.xFrameInterval =
    if frameInterval.inNanoseconds <= 0:
      initDuration(milliseconds = 16)
    else:
      frameInterval

proc newAnimationSchedulerClock*(
    frameInterval = initDuration(milliseconds = 16)
): AnimationSchedulerClock =
  result = AnimationSchedulerClock()
  initAnimationSchedulerClockFields(result, frameInterval)

proc frameInterval*(clock: AnimationSchedulerClock): Duration =
  clock.xFrameInterval

proc `frameInterval=`*(clock: AnimationSchedulerClock, interval: Duration) =
  clock.xFrameInterval =
    if interval.inNanoseconds <= 0:
      initDuration(milliseconds = 16)
    else:
      interval

proc isRunning*(clock: AnimationSchedulerClock): bool =
  not clock.xTimer.isNil

proc pendingTickCount*(clock: AnimationSchedulerClock): int =
  clock.xPendingDeltas.len

proc takePendingDeltas*(clock: AnimationSchedulerClock): seq[Duration] =
  result = clock.xPendingDeltas
  clock.xPendingDeltas.setLen(0)

proc ensureLocalAnimationDispatchThread() =
  if not hasLocalSigilThread():
    discard getCurrentSigilThread()

proc acquireSharedAnimationThread(): AnimationClockThreadPtr =
  withLock sharedAnimationThreadLock:
    if sharedAnimationThread.isNil:
      when defined(windows):
        sharedAnimationThread = newSigilChronosThread()
      else:
        sharedAnimationThread = newSigilSelectorThread()
      sharedAnimationThread.start()
    inc sharedAnimationThreadUseCount
    result = sharedAnimationThread

proc releaseSharedAnimationThread(thread: AnimationClockThreadPtr) =
  var toStop: AnimationClockThreadPtr
  withLock sharedAnimationThreadLock:
    if not thread.isNil and thread == sharedAnimationThread:
      if sharedAnimationThreadUseCount > 0:
        dec sharedAnimationThreadUseCount
      if sharedAnimationThreadUseCount == 0:
        toStop = sharedAnimationThread
        sharedAnimationThread = nil
  if not toStop.isNil:
    toStop.stop()
    toStop.join()
    when not defined(windows):
      toStop.closeSelectorThread()

proc pollQueuedTicks*(clock: AnimationSchedulerClock): int {.discardable.} =
  ensureLocalAnimationDispatchThread()
  getCurrentSigilThread().pollAll(NonBlocking)

proc start*(clock: AnimationSchedulerClock, thread: AnimationClockThreadPtr = nil) =
  if clock.isRunning:
    return
  ensureLocalAnimationDispatchThread()

  if thread.isNil:
    clock.xThread = acquireSharedAnimationThread()
    clock.xOwnsThread = false
    clock.xUsesSharedThread = true
  else:
    clock.xThread = thread
    clock.xOwnsThread = false
    clock.xUsesSharedThread = false

  var ticker = AnimationClockTicker(xFrameInterval: clock.xFrameInterval)
  clock.xTicker = ticker.moveToThread(clock.xThread)
  clock.xTimer = newSigilTimer(clock.xFrameInterval)
  connectThreaded(
    clock.xTimer, timeout, clock.xTicker, AnimationClockTicker.emitClockTick()
  )
  connectThreaded(
    clock.xTicker, clockTicked, clock, AnimationSchedulerClock.queueClockTick()
  )
  clock.xTimer.start(clock.xThread)

proc stop*(clock: AnimationSchedulerClock) =
  if clock.xTimer.isNil:
    return
  if not clock.xThread.isNil:
    clock.xTimer.cancel(clock.xThread)
  if clock.xUsesSharedThread and not clock.xThread.isNil:
    releaseSharedAnimationThread(clock.xThread)
  if clock.xOwnsThread and not clock.xThread.isNil:
    clock.xThread.stop()
    clock.xThread.join()
    when not defined(windows):
      clock.xThread.closeSelectorThread()
  clock.xTimer = nil
  clock.xTicker = nil
  clock.xThread = nil
  clock.xOwnsThread = false
  clock.xUsesSharedThread = false

proc drain*(
    scheduler: AnimationScheduler, clock: AnimationSchedulerClock, pollSignals = true
): int {.discardable.} =
  if clock.isNil:
    return 0
  if pollSignals:
    discard clock.pollQueuedTicks()
  for delta in clock.takePendingDeltas():
    discard scheduler.tick(delta)
    inc result

proc addAnimation*(group: AnimationGroup, animation: Animation) =
  if animation.isNil:
    return
  group.children.add(animation)

proc insertAnimation*(group: AnimationGroup, index: int, animation: Animation) =
  if animation.isNil:
    return
  group.children.insert(animation, min(max(index, 0), group.children.len))

proc removeAnimation*(group: AnimationGroup, animation: Animation): bool =
  if animation.isNil:
    return false
  for index, child in group.children:
    if child == animation:
      group.children.delete(index)
      return true

proc clearAnimations*(group: AnimationGroup) =
  group.children.setLen(0)
