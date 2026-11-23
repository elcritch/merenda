## Cooperative work scheduling for incremental application-thread operations.

import std/[heapqueue, monotimes, times]

type
  MainThreadWork* = proc(): bool {.closure.}
    ## Perform one chunk and return whether another frame is required.

  MainThreadTimer = ref object
    deadline: MonoTime
    fire: proc() {.closure.}

var
  pendingMainThreadWork {.threadvar.}: seq[MainThreadWork]
  mainThreadTimers {.threadvar.}: HeapQueue[MainThreadTimer]
  mainThreadTimerWake {.threadvar.}: proc() {.nimcall.}

template withMainThreadTimerWake*(wake: proc() {.nimcall.}, body: untyped) =
  ## Let an earlier timer interrupt the application's current native wait.
  block:
    let previous = mainThreadTimerWake
    mainThreadTimerWake = wake
    try:
      body
    finally:
      mainThreadTimerWake = previous

proc `<`(left, right: MainThreadTimer): bool =
  left.deadline < right.deadline

proc scheduleMainThreadTimer*(
    delay: Duration, fire: proc() {.closure.}
): proc() {.closure, gcsafe.} =
  ## Arm a one-shot application-thread callback and return its cancellation proc.
  let now = getMonoTime()
  if fire.isNil:
    raise newException(ValueError, "main-thread timer callback must not be nil")
  if delay < initDuration() or delay > MonoTime.high - now:
    raise newException(ValueError, "main-thread timer delay is out of range")
  let timer = MainThreadTimer(deadline: now + delay, fire: fire)
  let earlier = mainThreadTimers.len == 0 or timer < mainThreadTimers[0]
  mainThreadTimers.push(timer)
  if earlier and not mainThreadTimerWake.isNil:
    mainThreadTimerWake()
  result = proc() =
    let index = mainThreadTimers.find(timer)
    if index >= 0:
      mainThreadTimers.del(index)
    timer.fire = nil

proc mainThreadTimerDelay*(now: MonoTime): Duration =
  ## Return the delay until timed work is ready, or Duration.high when idle.
  if mainThreadTimers.len == 0:
    return Duration.high
  max(mainThreadTimers[0].deadline - now, initDuration())

proc scheduleMainThreadWork*(work: sink MainThreadWork) =
  ## Schedule `work` to run once during the next application-frame drain.
  if work.isNil:
    raise newException(ValueError, "main-thread work must not be nil")
  pendingMainThreadWork.add move work

proc hasPendingMainThreadWork*(): bool =
  ## Return whether the calling thread has cooperative work ready for a frame.
  pendingMainThreadWork.len > 0 or
    (mainThreadTimers.len > 0 and mainThreadTimers[0].deadline <= getMonoTime())

proc drainMainThreadWork*(): int {.discardable.} =
  ## Run one chunk from each item that was ready at the start of this frame.
  ## Continuations remain queued for the next drain so other frame work can run.
  var ready = move pendingMainThreadWork
  pendingMainThreadWork = @[]
  let now = getMonoTime()
  var readyTimers: seq[MainThreadTimer]
  while mainThreadTimers.len > 0 and mainThreadTimers[0].deadline <= now:
    readyTimers.add mainThreadTimers.pop()
  defer:
    for timer in readyTimers:
      if not timer.fire.isNil:
        mainThreadTimers.push(timer)

  for index in 0 ..< ready.len:
    var work = move ready[index]
    try:
      if work():
        pendingMainThreadWork.add move work
      inc result
    except CatchableError:
      # Work queued during this drain follows the untouched frame work.
      var remaining: seq[MainThreadWork]
      for next in index + 1 ..< ready.len:
        remaining.add move ready[next]
      remaining.add move pendingMainThreadWork
      pendingMainThreadWork = move remaining
      raise

  for timer in readyTimers:
    let fire = move timer.fire
    if not fire.isNil:
      fire()
      inc result
