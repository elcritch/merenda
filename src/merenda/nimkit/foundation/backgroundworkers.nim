## Shared background execution for NimKit text parsing, highlighting and layout.
## Resolve on the owning UI thread; widgets borrow the pool and never stop it.

import std/exitprocs
import sigils/threads
import sigils/threadChronos
import terminex/workerthreads

var
  backgroundPool {.threadvar.}: SigilThreadPoolPtr
  backgroundTimers {.threadvar.}: SigilChronosThreadPtr
  exitRegistered {.threadvar.}: bool

proc stopDispatcher(dispatcher: var SigilChronosThreadPtr) =
  if not dispatcher.isNil:
    try:
      dispatcher.stop(immediate = true)
    finally:
      try:
        dispatcher.join()
      finally:
        dispatcher = nil

proc shutdownNimkitBackgroundWorkers*() {.noconv.} =
  ## Stop and join every shared dispatcher even when one shutdown raises.
  ## Call on the owning UI thread. Repeated calls are harmless.
  try:
    shutdownTerminalWorkers()
  finally:
    try:
      stopDispatcher(backgroundTimers)
    finally:
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
