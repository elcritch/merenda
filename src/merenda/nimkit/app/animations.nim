import std/[algorithm, math, times]

import sigils/reactive

import ../foundation/selectors
import ../foundation/types

export reactive

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

  AnimationTiming* = object
    curve*: AnimationCurve
    controlPoint1*: Point
    controlPoint2*: Point
    springResponse*: float32
    springDampingRatio*: float32

  AnimationSetterSelector*[T] = Selector[T, EmptyArgs]

  Animation* = ref object of DynamicAgent
    xDuration: Duration
    xLoopCount: int
    xDirection: AnimationDirection
    xDeletionPolicy: AnimationDeletionPolicy
    xTiming: AnimationTiming
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

func clampProgress(value: float32): float32 =
  min(max(value, 0.0'f32), 1.0'f32)

func lerp(a, b, progress: float32): float32 =
  a + (b - a) * progress

func lerpPoint(a, b: Point, progress: float32): Point =
  initPoint(lerp(a.x, b.x, progress), lerp(a.y, b.y, progress))

func lerpSize(a, b: Size, progress: float32): Size =
  initSize(lerp(a.width, b.width, progress), lerp(a.height, b.height, progress))

func lerpRect(a, b: Rect, progress: float32): Rect =
  initRect(lerpPoint(a.origin, b.origin, progress), lerpSize(a.size, b.size, progress))

func lerpColor(a, b: Color, progress: float32): Color =
  initColor(
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

proc rawState(animation: Animation): AnimationState =
  if animation.isNil or animation.state.isNil:
    asStopped
  else:
    animation.state{}

proc rawCurrentTime(animation: Animation): Duration =
  if animation.isNil or animation.currentTime.isNil:
    initDuration()
  else:
    animation.currentTime{}

proc rawProgress(animation: Animation): float32 =
  if animation.isNil or animation.progress.isNil:
    0.0'f32
  else:
    animation.progress{}

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
  if animation.isNil:
    return
  let previous = animation.rawState()
  if previous == nextState:
    return
  animation.state <- nextState
  emit animation.stateChanged(nextState, previous)

method applyValue*(animation: Animation) {.base.} =
  discard

method adjustedProgress*(animation: Animation, progress: float32): float32 {.base.} =
  if animation.isNil:
    progress.clampProgress()
  else:
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
    discard animation.target.sendIfHandled(animation.setter, animation.currentValue{})

method applyValue*(animation: PropertyAnimation[Point]) =
  procCall ValueAnimation[Point](animation).applyValue()
  if not animation.target.isNil:
    discard animation.target.sendIfHandled(animation.setter, animation.currentValue{})

method applyValue*(animation: PropertyAnimation[Size]) =
  procCall ValueAnimation[Size](animation).applyValue()
  if not animation.target.isNil:
    discard animation.target.sendIfHandled(animation.setter, animation.currentValue{})

method applyValue*(animation: PropertyAnimation[Rect]) =
  procCall ValueAnimation[Rect](animation).applyValue()
  if not animation.target.isNil:
    discard animation.target.sendIfHandled(animation.setter, animation.currentValue{})

method applyValue*(animation: PropertyAnimation[Color]) =
  procCall ValueAnimation[Color](animation).applyValue()
  if not animation.target.isNil:
    discard animation.target.sendIfHandled(animation.setter, animation.currentValue{})

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
    if animation.isNil:
      initDuration()
    else:
      animation.xDuration

  method totalDuration*(animation: Animation): Duration =
    if animation.isNil:
      initDuration()
    elif animation.xLoopCount < 0:
      initDuration(nanoseconds = -1)
    else:
      initDuration(
        nanoseconds = animation.naturalDuration().inNanoseconds * animation.xLoopCount
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

protocol ParallelAnimationGroupProtocol of AnimationProtocol:
  method naturalDuration*(animation: ParallelAnimationGroup): Duration =
    if animation.isNil:
      return initDuration()
    result = Animation(animation).xDuration
    for child in animation.children:
      let childDuration = child.totalDuration()
      if childDuration.inNanoseconds < 0:
        return childDuration
      if childDuration > result:
        result = childDuration

protocol SequentialAnimationGroupProtocol of AnimationProtocol:
  method naturalDuration*(animation: SequentialAnimationGroup): Duration =
    if animation.isNil:
      return initDuration()
    result = Animation(animation).xDuration
    for child in animation.children:
      let childDuration = child.totalDuration()
      if childDuration.inNanoseconds < 0:
        return childDuration
      result = result + childDuration

proc initAnimationFields*(
    animation: Animation,
    duration = initDuration(milliseconds = 250),
    loopCount = 1,
    direction = adForward,
) =
  if animation.isNil:
    return
  animation.xDuration = duration
  animation.xLoopCount = loopCount
  animation.xDirection = direction
  animation.xDeletionPolicy = adpKeepWhenStopped
  animation.xTiming = linearTiming()
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
  if group.isNil:
    return
  initAnimationFields(group, duration)
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

proc duration*(animation: Animation): Duration =
  animation.naturalDuration()

proc `duration=`*(animation: Animation, duration: Duration) =
  if animation.isNil:
    return
  animation.xDuration = duration

proc loopCount*(animation: Animation): int =
  if animation.isNil: 0 else: animation.xLoopCount

proc `loopCount=`*(animation: Animation, loopCount: int) =
  if not animation.isNil:
    animation.xLoopCount = loopCount

proc direction*(animation: Animation): AnimationDirection =
  if animation.isNil: adForward else: animation.xDirection

proc `direction=`*(animation: Animation, direction: AnimationDirection) =
  if not animation.isNil:
    animation.xDirection = direction

proc deletionPolicy*(animation: Animation): AnimationDeletionPolicy =
  if animation.isNil: adpKeepWhenStopped else: animation.xDeletionPolicy

proc `deletionPolicy=`*(animation: Animation, deletionPolicy: AnimationDeletionPolicy) =
  if not animation.isNil:
    animation.xDeletionPolicy = deletionPolicy

proc timing*(animation: Animation): AnimationTiming =
  if animation.isNil:
    linearTiming()
  else:
    animation.xTiming

proc `timing=`*(animation: Animation, timing: AnimationTiming) =
  if not animation.isNil:
    animation.xTiming = timing

proc curve*(animation: Animation): AnimationCurve =
  animation.timing.curve

proc `curve=`*(animation: Animation, curve: AnimationCurve) =
  if not animation.isNil:
    animation.xTiming.curve = curve

proc setCubicBezierTiming*(animation: Animation, controlPoint1, controlPoint2: Point) =
  if not animation.isNil:
    animation.xTiming = cubicBezierTiming(controlPoint1, controlPoint2)

proc setSpringTiming*(
    animation: Animation, response = 0.45'f32, dampingRatio = 0.75'f32
) =
  if not animation.isNil:
    animation.xTiming = springTiming(response, dampingRatio)

proc isRunning*(animation: Animation): bool =
  animation.rawState() == asRunning

proc isPaused*(animation: Animation): bool =
  animation.rawState() == asPaused

proc isStopped*(animation: Animation): bool =
  animation.rawState() == asStopped

proc currentLoop*(animation: Animation): int =
  if animation.isNil or animation.xDuration.inNanoseconds <= 0:
    return 0
  let elapsed = animation.rawCurrentTime().inNanoseconds
  int(elapsed div animation.xDuration.inNanoseconds)

proc currentLoopTime*(animation: Animation): Duration =
  if animation.isNil:
    return initDuration()
  let durationNs = animation.xDuration.inNanoseconds
  if durationNs <= 0:
    return initDuration()
  let elapsed = animation.rawCurrentTime().inNanoseconds
  initDuration(nanoseconds = elapsed mod durationNs)

proc progressMarks*(animation: Animation): seq[float32] =
  if animation.isNil:
    @[]
  else:
    animation.xProgressMarks

proc `progressMarks=`*(animation: Animation, marks: openArray[float32]) =
  if animation.isNil:
    return
  animation.xProgressMarks = @marks
  animation.xProgressMarks.sortAndDedupeMarks()
  animation.resetDeliveredMarks()

proc addProgressMark*(animation: Animation, mark: float32) =
  if animation.isNil:
    return
  animation.xProgressMarks.add mark.clampProgress()
  animation.xProgressMarks.sortAndDedupeMarks()
  animation.resetDeliveredMarks()

proc removeProgressMark*(animation: Animation, mark: float32) =
  if animation.isNil:
    return
  let normalized = mark.clampProgress()
  for index in countdown(animation.xProgressMarks.len - 1, 0):
    if abs(animation.xProgressMarks[index] - normalized) <= 0.00001'f32:
      animation.xProgressMarks.delete(index)
  animation.resetDeliveredMarks()

proc clearProgressMarks*(animation: Animation) =
  if not animation.isNil:
    animation.xProgressMarks.setLen(0)
    animation.xDeliveredMarks.setLen(0)

proc emitProgressMarks(animation: Animation, previous, next: float32) =
  if animation.isNil:
    return
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
  if animation.isNil:
    return
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
  if animation.isNil:
    return
  let previousProgress = animation.rawProgress()
  let duration = animation.duration()
  let nextTime =
    if duration.inNanoseconds >= 0 and currentTime > duration:
      duration
    elif currentTime.inNanoseconds < 0:
      initDuration()
    else:
      currentTime
  let nextProgress = nextTime.durationRatio(duration)
  animation.progress <- nextProgress
  animation.currentTime <- nextTime
  animation.emitProgressMarks(previousProgress, nextProgress)
  animation.updateCurrentTime(nextTime)
  emit animation.progressChanged(nextProgress)

proc start*(animation: Animation) =
  if animation.isNil or animation.isRunning:
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
  if animation.isNil or animation.rawState() != asRunning:
    return
  let oldState = animation.rawState()
  animation.setAnimationState(asPaused)
  animation.updateState(asPaused, oldState)
  emit animation.paused()

proc resume*(animation: Animation) =
  if animation.isNil or animation.rawState() != asPaused:
    return
  let oldState = animation.rawState()
  animation.setAnimationState(asRunning)
  animation.updateState(asRunning, oldState)
  emit animation.resumed()

proc stop*(animation: Animation, finished = false) =
  if animation.isNil or animation.rawState() == asStopped:
    return
  let oldState = animation.rawState()
  if finished:
    animation.setProgress(if animation.xDirection == adBackward: 0.0'f32 else: 1.0'f32)
  animation.setAnimationState(asStopped)
  animation.updateState(asStopped, oldState)
  emit animation.stopped(finished)
  if finished:
    emit animation.finished()

proc addAnimation*(group: AnimationGroup, animation: Animation) =
  if group.isNil or animation.isNil:
    return
  group.children.add(animation)

proc insertAnimation*(group: AnimationGroup, index: int, animation: Animation) =
  if group.isNil or animation.isNil:
    return
  group.children.insert(animation, min(max(index, 0), group.children.len))

proc removeAnimation*(group: AnimationGroup, animation: Animation): bool =
  if group.isNil or animation.isNil:
    return false
  for index, child in group.children:
    if child == animation:
      group.children.delete(index)
      return true

proc clearAnimations*(group: AnimationGroup) =
  if not group.isNil:
    group.children.setLen(0)
