## Optional per-thread timings for NimKit view work.
## Compile with -d:merendaProfile. Inclusive timings overlap; exclusive timings
## subtract time spent in nested instrumented phases. Both include timer overhead.
when defined(merendaProfile):
  import std/[monotimes, tables, times]

type
  ViewProfilePhase* = enum
    vppConstraintGeneration
    vppConstraintInsertion
    vppSolve
    vppIntrinsicMeasurement
    vppFrameApplication
    vppArrangement
    vppBindingUpdate
    vppDrawing
    vppConstraintConstruction
    vppSolverUpdate
    vppLayoutTransaction
    vppRenderBuild
    vppRenderCapture
    vppDragPreview

  ViewProfileSample* = object
    calls*: int
    ## Inclusive of nested instrumented work; recursive calls can overlap.
    nanoseconds*: int64
    ## Excludes direct and indirect nested instrumented work in this scope.
    exclusiveNanoseconds*: int64

  ViewProfile* = object
    phases*: array[ViewProfilePhase, ViewProfileSample]
    solverViews*, solverConstraints*, solverPasses*, solverFailures*: int
    persistentBuilds*, persistentReuses*, persistentFallbacks*: int

  IntrinsicProfileEvent* = enum
    ipeCacheDisabled
    ipeColdMiss
    ipeInvalidatedMiss
    ipeRevisionMismatch
    ipeCacheHit
    ipeDiscardedMeasurement
    ipeMeasurementFailed

  IntrinsicProfileCount* = object
    widgetType*: string
    event*: IntrinsicProfileEvent
    reason*: string
    count*: int

var viewProfile {.threadvar.}: ViewProfile

when defined(merendaProfile):
  type ProfileFrame = object
    phase: ViewProfilePhase
    started: MonoTime
    children: int64

  var profileFrames {.threadvar.}: seq[ProfileFrame]
  var intrinsicCounts {.threadvar.}:
    Table[tuple[widgetType: string, event: IntrinsicProfileEvent, reason: string], int]

  proc beginViewProfile(phase: ViewProfilePhase) =
    profileFrames.add ProfileFrame(phase: phase, started: getMonoTime())

  proc endViewProfile() =
    let finished = getMonoTime()
    let frame = profileFrames.pop()
    let elapsed = (finished - frame.started).inNanoseconds
    inc viewProfile.phases[frame.phase].calls
    viewProfile.phases[frame.phase].nanoseconds += elapsed
    viewProfile.phases[frame.phase].exclusiveNanoseconds +=
      max(0'i64, elapsed - frame.children)
    if profileFrames.len > 0:
      profileFrames[^1].children += elapsed

proc resetViewProfile*() =
  ## Start a new sample on this thread; cannot run inside an active phase.
  when defined(merendaProfile):
    if profileFrames.len > 0:
      raise newException(ValueError, "cannot reset an active view profile")
    intrinsicCounts.clear()
  viewProfile = ViewProfile()

proc currentViewProfile*(): ViewProfile =
  ## Return completed phase samples for the calling thread.
  viewProfile

proc currentIntrinsicProfile*(): seq[IntrinsicProfileCount] =
  ## Snapshot of per-thread intrinsic-cache decisions and their invalidation reasons.
  when defined(merendaProfile):
    for key, count in intrinsicCounts:
      result.add IntrinsicProfileCount(
        widgetType: key.widgetType, event: key.event, reason: key.reason, count: count
      )

proc recordIntrinsicProfile*(
    widgetType: string, event: IntrinsicProfileEvent, reason = ""
) =
  when defined(merendaProfile):
    if widgetType.len > 0:
      inc intrinsicCounts.mgetOrPut((widgetType, event, reason), 0)

template profileViewPhase*(phase: ViewProfilePhase) =
  when defined(merendaProfile):
    beginViewProfile(phase)
    defer:
      endViewProfile()

template recordSolverSize*(views, constraints: int) =
  when defined(merendaProfile):
    inc viewProfile.solverPasses
    viewProfile.solverViews = max(viewProfile.solverViews, views)
    viewProfile.solverConstraints = max(viewProfile.solverConstraints, constraints)

template recordSolverFailure*() =
  when defined(merendaProfile):
    inc viewProfile.solverFailures

template recordPersistentBuild*() =
  when defined(merendaProfile):
    inc viewProfile.persistentBuilds

template recordPersistentReuse*() =
  when defined(merendaProfile):
    inc viewProfile.persistentReuses

template recordPersistentFallback*() =
  when defined(merendaProfile):
    inc viewProfile.persistentFallbacks
