import std/unittest
import merenda/nimkit/foundation/viewprofiling

when defined(merendaProfile):
  import merenda/nimkit
  import merenda/nimkit/directviews
  import merenda/nimkit/intrinsicprofiling
  import merenda/nimkit/view/viewgeometry

  type ProfileCountingView = ref object of View
    invalidateDuringMeasure: bool
    failDuringMeasure: bool

  protocol ProfileCountingLayout of ViewLayoutProtocol:
    method layoutIntrinsicContentSize(view: ProfileCountingView): IntrinsicSize =
      if view.failDuringMeasure:
        raise newException(ValueError, "measurement failed")
      if view.invalidateDuringMeasure:
        view.invalidateDuringMeasure = false
        view.invalidateIntrinsicContentSize()
      initIntrinsicSize(40, 20)

  proc classifyProfileView(view: View): string {.nimcall, raises: [].} =
    if view of ProfileCountingView: "ProfileCountingView" else: "OtherView"

  proc intrinsicCount(event: IntrinsicProfileEvent, reason = ""): int =
    for entry in currentIntrinsicProfile():
      if entry.widgetType == "ProfileCountingView" and entry.event == event and
          entry.reason == reason:
        result += entry.count

  proc measuredChild() =
    profileViewPhase(vppDrawing)
    var value = 0
    for index in 0 ..< 1000:
      value += index
    doAssert value == 499500

  proc measuredParent() =
    profileViewPhase(vppRenderBuild)
    measuredChild()
    measuredChild()

  proc measuredFailure() =
    profileViewPhase(vppBindingUpdate)
    raise newException(ValueError, "test failure")

  proc resetInsidePhase() =
    profileViewPhase(vppSolve)
    resetViewProfile()

  proc recursivePhase(depth: int) =
    profileViewPhase(vppArrangement)
    if depth > 0:
      recursivePhase(depth - 1)

  suite "view profiling":
    test "exclusive time subtracts nested phases and failed scopes close":
      resetViewProfile()
      measuredParent()
      let sample = currentViewProfile()
      let parent = sample.phases[vppRenderBuild]
      let child = sample.phases[vppDrawing]
      check parent.calls == 1
      check child.calls == 2
      check parent.nanoseconds == parent.exclusiveNanoseconds + child.nanoseconds
      check child.nanoseconds == child.exclusiveNanoseconds
      expect ValueError:
        measuredFailure()
      expect ValueError:
        resetInsidePhase()
      check currentViewProfile().phases[vppBindingUpdate].calls == 1
      check currentViewProfile().phases[vppSolve].calls == 1
      resetViewProfile()
      check currentViewProfile().phases[vppDrawing].calls == 0

    test "recursive calls retain their count and exclusive accounting":
      resetViewProfile()
      recursivePhase(2)
      let sample = currentViewProfile().phases[vppArrangement]
      check sample.calls == 3
      check sample.nanoseconds >= sample.exclusiveNanoseconds

    test "a budget failure is recorded even when layout catches it":
      let root = newView(frame = rect(0, 0, 200, 120))
      root.addSubview(newView(frame = rect(0, 0, 40, 24)))
      root.xLayoutSolveLimits = LayoutSolveLimits(maxViews: 1)
      resetViewProfile()
      root.layoutSubtreeIfNeeded()
      let profile = currentViewProfile()
      check root.xLastLayoutSolveDiagnostic.failed
      check profile.solverFailures == 1
      check profile.solverPasses == 1
      check profile.phases[vppSolve].calls == 1

    when defined(merendaIntrinsicCache):
      test "intrinsic counters distinguish cache decisions and invalidation causes":
        setIntrinsicProfileClassifier(classifyProfileView)
        defer:
          setIntrinsicProfileClassifier(nil)
          resetViewProfile()
        resetViewProfile()
        let view = ProfileCountingView()
        initViewFields(view, rect(0, 0, 25, 15))
        discard view.withProtocol(ProfileCountingLayout)
        discard view.resolvedIntrinsicContentSize()
        view{vpCacheIntrinsicSize} = true
        discard view.resolvedIntrinsicContentSize()
        discard view.resolvedIntrinsicContentSize()
        view.invalidateIntrinsicContentSize()
        discard view.resolvedIntrinsicContentSize()
        view.applyLayoutFrame(rect(2, 3, 60, 35), lfoContainer)
        discard view.resolvedIntrinsicContentSize()
        view.invalidateIntrinsicContentSize()
        view.invalidateDuringMeasure = true
        discard view.resolvedIntrinsicContentSize()
        discard view.resolvedIntrinsicContentSize()
        inc view.xIntrinsicMeasurement.revision
        discard view.resolvedIntrinsicContentSize()
        check intrinsicCount(ipeCacheDisabled) == 1
        check intrinsicCount(ipeColdMiss) == 1
        check intrinsicCount(ipeCacheHit) == 1
        check intrinsicCount(ipeInvalidatedMiss, "lirIntrinsic") == 3
        check intrinsicCount(ipeInvalidatedMiss, "layoutFrame") == 1
        check intrinsicCount(ipeRevisionMismatch) == 1
        check intrinsicCount(ipeDiscardedMeasurement, "invalidatedDuringMeasurement") ==
          1
        view.invalidateIntrinsicContentSize()
        view.failDuringMeasure = true
        expect ValueError:
          discard view.resolvedIntrinsicContentSize()
        check intrinsicCount(ipeMeasurementFailed) == 1
        view.failDuringMeasure = false
        discard view.resolvedIntrinsicContentSize()

    test "built-in classification separates labels from text fields and stacks":
      let label = newLabel("Label")
      let field = newTextField("Field")
      let button = newButton("Button")
      let stack = newStackView()
      let direct = newDirectView()
      useDefaultIntrinsicProfileCategories()
      defer:
        setIntrinsicProfileClassifier(nil)
        resetViewProfile()
      resetViewProfile()
      for view in [View(label), View(field), View(button), View(stack), View(direct)]:
        discard view.resolvedIntrinsicContentSize()
      var seen: set[range[0 .. 4]]
      for entry in currentIntrinsicProfile():
        if entry.event == ipeCacheDisabled:
          case entry.widgetType
          of "Label":
            seen.incl 0
          of "TextField":
            seen.incl 1
          of "Button":
            seen.incl 2
          of "StackView":
            seen.incl 3
          of "DirectView":
            seen.incl 4
          else:
            discard
      check seen == {0, 1, 2, 3, 4}
