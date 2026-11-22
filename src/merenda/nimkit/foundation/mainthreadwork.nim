## Cooperative work scheduling for incremental application-thread operations.

type MainThreadWork* = proc(): bool {.closure.}
  ## Perform one chunk and return whether another frame is required.

var pendingMainThreadWork {.threadvar.}: seq[MainThreadWork]

proc scheduleMainThreadWork*(work: sink MainThreadWork) =
  ## Schedule `work` to run once during the next application-frame drain.
  if work.isNil:
    raise newException(ValueError, "main-thread work must not be nil")
  pendingMainThreadWork.add move work

proc hasPendingMainThreadWork*(): bool =
  ## Return whether the calling thread has cooperative work ready for a frame.
  pendingMainThreadWork.len > 0

proc drainMainThreadWork*(): int {.discardable.} =
  ## Run one chunk from each item that was ready at the start of this frame.
  ## Continuations remain queued for the next drain so other frame work can run.
  var ready = move pendingMainThreadWork
  pendingMainThreadWork = @[]
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
