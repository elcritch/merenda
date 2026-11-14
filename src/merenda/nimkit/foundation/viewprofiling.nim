## Optional per-thread inclusive timings for NimKit view work.
## Compile with -d:merendaProfile. Nested phases overlap and must not be summed.
when defined(merendaProfile):
  import std/[monotimes, times]

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

  ViewProfileSample* = object
    calls*: int
    nanoseconds*: int64

  ViewProfile* = object
    phases*: array[ViewProfilePhase, ViewProfileSample]
    solverViews*, solverConstraints*, solverPasses*: int

var viewProfile {.threadvar.}: ViewProfile

proc resetViewProfile*() =
  viewProfile = ViewProfile()

proc currentViewProfile*(): ViewProfile =
  viewProfile

template profileViewPhase*(phase: ViewProfilePhase) =
  when defined(merendaProfile):
    let profileStarted = getMonoTime()
    defer:
      inc viewProfile.phases[phase].calls
      viewProfile.phases[phase].nanoseconds +=
        (getMonoTime() - profileStarted).inNanoseconds

template recordSolverSize*(views, constraints: int) =
  when defined(merendaProfile):
    inc viewProfile.solverPasses
    viewProfile.solverViews = max(viewProfile.solverViews, views)
    viewProfile.solverConstraints = max(viewProfile.solverConstraints, constraints)
