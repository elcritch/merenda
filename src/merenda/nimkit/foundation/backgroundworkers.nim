## Shared background execution for NimKit text parsing, highlighting and layout.
## Resolve on the owning UI thread; widgets borrow the pool and never stop it.

import std/exitprocs
import sigils/threads
import sigils/threadChronos

var
  backgroundPool {.threadvar.}: SigilThreadPoolPtr
  backgroundTimers {.threadvar.}: SigilChronosThreadPtr
  exitRegistered {.threadvar.}: bool

proc stopBackgroundPool() {.noconv.} =
  if not backgroundTimers.isNil:
    backgroundTimers.stop(immediate = true)
    backgroundTimers.join()
    backgroundTimers = nil
  if not backgroundPool.isNil:
    backgroundPool.stop(immediate = true)
    backgroundPool.join()
    backgroundPool = nil

proc nimkitWorkerPool*(): SigilThreadPoolPtr =
  ## Borrow the shared pool. Its lifetime belongs to NimKit, not a widget.
  startLocalThreadDefault()
  if backgroundPool.isNil:
    backgroundPool = newSigilThreadPool(workers = 2)
    backgroundPool.start()
  if not exitRegistered:
    addExitProc(stopBackgroundPool)
    exitRegistered = true
  backgroundPool

proc nimkitTimerThread*(): SigilChronosThreadPtr =
  ## Borrow the application-lifetime timer thread; clients cancel their own timers.
  discard nimkitWorkerPool()
  if backgroundTimers.isNil:
    backgroundTimers = newSigilChronosThread()
    backgroundTimers.start()
  backgroundTimers
