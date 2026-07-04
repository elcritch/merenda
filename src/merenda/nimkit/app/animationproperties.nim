import std/times

import sigils/core

import ./animations
import ../containers/cascadingviews
import ../containers/scrollviews
import ../containers/splitviews
import ../controls/progressindicators
import ../foundation/selectors
import ../foundation/types
import ../view/views

type SplitDividerAnimationTarget = ref object of DynamicAgent
  splitView: SplitView
  dividerIndex: int

protocol ViewAnimProtocol:
  method animFrame*(frame: Rect)
  method animBounds*(bounds: Rect)
  method animAlpha*(alphaValue: float32)

protocol ViewAnim of ViewAnimProtocol:
  method animFrame(view: View, frame: Rect) =
    view.frame = frame

  method animBounds(view: View, bounds: Rect) =
    view.bounds = bounds

  method animAlpha(view: View, alphaValue: float32) =
    view.alphaValue = alphaValue

protocol ScrollAnimProtocol:
  method animOffset*(offset: Point)

protocol ScrollAnim of ScrollAnimProtocol:
  method animOffset(scrollView: ScrollView, offset: Point) =
    scrollView.contentOffset = offset

protocol ProgressAnimProtocol:
  method animValue*(value: float32)

protocol ProgressAnim of ProgressAnimProtocol:
  method animValue(indicator: ProgressIndicator, value: float32) =
    indicator.value = value

protocol CascadeAnimProtocol:
  method animColumnWidth*(width: float32)
  method animMinColumnWidth*(width: float32)
  method animColumnSpacing*(spacing: float32)

protocol CascadeAnim of CascadeAnimProtocol:
  method animColumnWidth(view: CascadingView, width: float32) =
    view.columnWidth = width

  method animMinColumnWidth(view: CascadingView, width: float32) =
    view.minColumnWidth = width

  method animColumnSpacing(view: CascadingView, spacing: float32) =
    view.columnSpacing = spacing

protocol SplitDivAnimProtocol:
  method animDividerPos*(position: float32)

protocol SplitDivAnim of SplitDivAnimProtocol:
  method animDividerPos(target: SplitDividerAnimationTarget, position: float32) =
    if not target.splitView.isNil:
      target.splitView.setPositionOfDivider(target.dividerIndex, position)

proc applyTiming[T](animation: PropertyAnimation[T], timing: AnimationTiming) =
  if not animation.isNil:
    animation.timing = timing

proc currentFrame(view: View): Rect =
  if view.isNil:
    rect(0.0, 0.0, 0.0, 0.0)
  else:
    view.frame()

proc currentBounds(view: View): Rect =
  if view.isNil:
    rect(0.0, 0.0, 0.0, 0.0)
  else:
    view.bounds()

proc currentAlphaValue(view: View): float32 =
  if view.isNil:
    1.0'f32
  else:
    view.alphaValue()

proc currentContentOffset(scrollView: ScrollView): Point =
  if scrollView.isNil:
    initPoint(0.0, 0.0)
  else:
    scrollView.contentOffset()

proc currentProgressValue(indicator: ProgressIndicator): float32 =
  if indicator.isNil:
    0.0'f32
  else:
    indicator.value()

proc currentColumnWidth(view: CascadingView): float32 =
  if view.isNil:
    0.0'f32
  else:
    view.columnWidth()

proc currentMinColumnWidth(view: CascadingView): float32 =
  if view.isNil:
    0.0'f32
  else:
    view.minColumnWidth()

proc currentColumnSpacing(view: CascadingView): float32 =
  if view.isNil:
    0.0'f32
  else:
    view.columnSpacing()

proc ensureViewAnimationProtocol(view: View) =
  if not view.isNil:
    discard view.withProtocol(ViewAnim)

proc ensureScrollViewAnimationProtocol(scrollView: ScrollView) =
  if not scrollView.isNil:
    discard scrollView.withProtocol(ScrollAnim)

proc ensureProgressIndicatorAnimationProtocol(indicator: ProgressIndicator) =
  if not indicator.isNil:
    discard indicator.withProtocol(ProgressAnim)

proc ensureCascadingViewAnimationProtocol(view: CascadingView) =
  if not view.isNil:
    discard view.withProtocol(CascadeAnim)

proc newFrameAnimation*(
    view: View,
    fromFrame, toFrame: Rect,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[Rect] =
  view.ensureViewAnimationProtocol()
  result = newPropertyAnimation[Rect](
    DynamicAgent(view), animFrame(), fromFrame, toFrame, duration
  )
  result.applyTiming(timing)

proc newFrameAnimation*(
    view: View,
    toFrame: Rect,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[Rect] =
  newFrameAnimation(view, view.currentFrame(), toFrame, duration, timing)

proc newBoundsAnimation*(
    view: View,
    fromBounds, toBounds: Rect,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[Rect] =
  view.ensureViewAnimationProtocol()
  result = newPropertyAnimation[Rect](
    DynamicAgent(view), animBounds(), fromBounds, toBounds, duration
  )
  result.applyTiming(timing)

proc newBoundsAnimation*(
    view: View,
    toBounds: Rect,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[Rect] =
  newBoundsAnimation(view, view.currentBounds(), toBounds, duration, timing)

proc newAlphaValueAnimation*(
    view: View,
    fromAlphaValue, toAlphaValue: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  view.ensureViewAnimationProtocol()
  result = newPropertyAnimation[float32](
    DynamicAgent(view), animAlpha(), fromAlphaValue, toAlphaValue, duration
  )
  result.applyTiming(timing)

proc newAlphaValueAnimation*(
    view: View,
    toAlphaValue: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  newAlphaValueAnimation(view, view.currentAlphaValue(), toAlphaValue, duration, timing)

proc newContentOffsetAnimation*(
    scrollView: ScrollView,
    fromOffset, toOffset: Point,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[Point] =
  scrollView.ensureScrollViewAnimationProtocol()
  result = newPropertyAnimation[Point](
    DynamicAgent(scrollView), animOffset(), fromOffset, toOffset, duration
  )
  result.applyTiming(timing)

proc newContentOffsetAnimation*(
    scrollView: ScrollView,
    toOffset: Point,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[Point] =
  newContentOffsetAnimation(
    scrollView, scrollView.currentContentOffset(), toOffset, duration, timing
  )

proc newProgressValueAnimation*(
    indicator: ProgressIndicator,
    fromValue, toValue: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  indicator.ensureProgressIndicatorAnimationProtocol()
  result = newPropertyAnimation[float32](
    DynamicAgent(indicator), animValue(), fromValue, toValue, duration
  )
  result.applyTiming(timing)

proc newProgressValueAnimation*(
    indicator: ProgressIndicator,
    toValue: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  newProgressValueAnimation(
    indicator, indicator.currentProgressValue(), toValue, duration, timing
  )

proc newSplitDividerPositionAnimation*(
    splitView: SplitView,
    dividerIndex: int,
    fromPosition, toPosition: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  let target =
    SplitDividerAnimationTarget(splitView: splitView, dividerIndex: dividerIndex)
  discard target.withProtocol(SplitDivAnim)
  result = newPropertyAnimation[float32](
    DynamicAgent(target), animDividerPos(), fromPosition, toPosition, duration
  )
  result.applyTiming(timing)

proc newSplitDividerPositionAnimation*(
    splitView: SplitView,
    dividerIndex: int,
    toPosition: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  let fromPosition =
    if splitView.isNil:
      0.0'f32
    else:
      splitView.positionOfDivider(dividerIndex)
  newSplitDividerPositionAnimation(
    splitView, dividerIndex, fromPosition, toPosition, duration, timing
  )

proc newCascadingColumnWidthAnimation*(
    view: CascadingView,
    fromWidth, toWidth: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  view.ensureCascadingViewAnimationProtocol()
  result = newPropertyAnimation[float32](
    DynamicAgent(view), animColumnWidth(), fromWidth, toWidth, duration
  )
  result.applyTiming(timing)

proc newCascadingColumnWidthAnimation*(
    view: CascadingView,
    toWidth: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  newCascadingColumnWidthAnimation(
    view, view.currentColumnWidth(), toWidth, duration, timing
  )

proc newCascadingMinColumnWidthAnimation*(
    view: CascadingView,
    fromWidth, toWidth: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  view.ensureCascadingViewAnimationProtocol()
  result = newPropertyAnimation[float32](
    DynamicAgent(view), animMinColumnWidth(), fromWidth, toWidth, duration
  )
  result.applyTiming(timing)

proc newCascadingMinColumnWidthAnimation*(
    view: CascadingView,
    toWidth: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  newCascadingMinColumnWidthAnimation(
    view, view.currentMinColumnWidth(), toWidth, duration, timing
  )

proc newCascadingColumnSpacingAnimation*(
    view: CascadingView,
    fromSpacing, toSpacing: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  view.ensureCascadingViewAnimationProtocol()
  result = newPropertyAnimation[float32](
    DynamicAgent(view), animColumnSpacing(), fromSpacing, toSpacing, duration
  )
  result.applyTiming(timing)

proc newCascadingColumnSpacingAnimation*(
    view: CascadingView,
    toSpacing: float32,
    duration = initDuration(milliseconds = 250),
    timing = linearTiming(),
): PropertyAnimation[float32] =
  newCascadingColumnSpacingAnimation(
    view, view.currentColumnSpacing(), toSpacing, duration, timing
  )
