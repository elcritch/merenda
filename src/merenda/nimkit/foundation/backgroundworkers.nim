## Shared background execution for NimKit text parsing, highlighting and layout.
## Resolve on the owning UI thread; widgets borrow the pool and never stop it.

import std/exitprocs
import sigils/threads
import sigils/threadChronos

var
  backgroundPool {.threadvar.}: SigilThreadPoolPtr
  backgroundTimers {.threadvar.}: SigilChronosThreadPtr
  exitRegistered {.threadvar.}: bool

proc shutdownNimkitBackgroundWorkers*() {.noconv.} =
  ## Stop and join the shared pool before imported module globals are destroyed.
  ## Call on the owning UI thread. Repeated calls are harmless.
  try:
    if not backgroundTimers.isNil:
      try:
        backgroundTimers.stop(immediate = true)
      finally:
        # Joining must still happen if waking the timer dispatcher fails.
        try:
          backgroundTimers.join()
        finally:
          backgroundTimers = nil
  finally:
    # Timer handle cleanup can raise after its thread has already joined.
    # That must never leave the parsing and layout workers running.
    if not backgroundPool.isNil:
      try:
        backgroundPool.stop(immediate = true)
      finally:
        backgroundPool.join()
        backgroundPool = nil

type NimkitBackgroundWorkerLifetime* = object
  ## Internal module guard. Declare as a worker module's final global so workers
  ## join before that module's globals and imported dependencies are destroyed.

proc `=destroy`(lifetime: var NimkitBackgroundWorkerLifetime) {.raises: [].} =
  discard lifetime
  try:
    shutdownNimkitBackgroundWorkers()
  except Exception:
    # Destructors cannot propagate cleanup failures. Shutdown's finally blocks
    # ensure all joins have been attempted before suppressing an error.
    discard

proc nimkitWorkerPool*(): SigilThreadPoolPtr =
  ## Borrow the shared pool. Its lifetime belongs to NimKit, not a widget.
  startLocalThreadDefault()
  if backgroundPool.isNil:
    backgroundPool = newSigilThreadPool(workers = 2)
    backgroundPool.start()
  if not exitRegistered:
    addExitProc(shutdownNimkitBackgroundWorkers)
    exitRegistered = true
  backgroundPool

proc nimkitTimerThread*(): SigilChronosThreadPtr =
  ## Borrow the application-lifetime timer thread; clients cancel their own timers.
  discard nimkitWorkerPool()
  if backgroundTimers.isNil:
    backgroundTimers = newSigilChronosThread()
    backgroundTimers.start()
  backgroundTimers

var backgroundWorkerLifetime {.used.}: NimkitBackgroundWorkerLifetime
