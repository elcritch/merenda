## Shared worker and timer dispatchers for the calling thread.

import std/exitprocs
import sigils/threads
import ./timerthreads

type BackgroundWorkerShutdownHook* = proc() {.noconv.}

var
  backgroundPool {.threadvar.}: SigilThreadPoolPtr
  backgroundTimers {.threadvar.}: NimkitTimerThreadPtr
  exitRegistered {.threadvar.}: bool
  shutdownHooks {.threadvar.}: seq[BackgroundWorkerShutdownHook]
  shuttingDown {.threadvar.}: bool

proc shutdownBackgroundWorkers*() {.noconv.}

proc registerBackgroundWorkerShutdownHook*(hook: BackgroundWorkerShutdownHook) =
  ## Register a noncapturing hook on the owning thread for the current cycle.
  ## Duplicate registrations are ignored; registrations during shutdown are ignored.
  if not shuttingDown and not hook.isNil and hook notin shutdownHooks:
    shutdownHooks.add hook
    if not exitRegistered:
      addExitProc(shutdownBackgroundWorkers)
      exitRegistered = true

proc stopDispatcher(dispatcher: var NimkitTimerThreadPtr) =
  if not dispatcher.isNil:
    try:
      dispatcher.stop(immediate = true)
    finally:
      try:
        dispatcher.joinTimerThread()
      finally:
        dispatcher = nil

proc shutdownBackgroundWorkers*() {.noconv.} =
  ## Run hooks in reverse registration order, then stop and join dispatchers.
  ## A hook exception does not interrupt the remaining cleanup. Call on the
  ## owning thread. Repeated and reentrant calls are harmless.
  if shuttingDown:
    return
  shuttingDown = true
  try:
    while shutdownHooks.len > 0:
      let hook = shutdownHooks.pop()
      try:
        hook()
      except Exception:
        discard
    try:
      stopDispatcher(backgroundTimers)
    finally:
      if not backgroundPool.isNil:
        try:
          backgroundPool.stop(immediate = true)
        finally:
          try:
            backgroundPool.join()
          finally:
            backgroundPool = nil
  finally:
    shuttingDown = false

type BackgroundWorkerLifetime* = object
  ## Internal module guard. Declare as a worker module's final global so workers
  ## join before that module's globals and imported dependencies are destroyed.

proc `=destroy`*(lifetime: BackgroundWorkerLifetime) {.raises: [].} =
  discard lifetime
  try:
    shutdownBackgroundWorkers()
  except Exception:
    # Destructors cannot propagate cleanup failures. Shutdown's finally blocks
    # ensure all joins have been attempted before suppressing an error.
    discard

proc backgroundWorkerPool*(): SigilThreadPoolPtr =
  ## Borrow the calling thread's shared pool until dispatcher shutdown.
  startLocalThreadDefault()
  if backgroundPool.isNil:
    backgroundPool = newSigilThreadPool(workers = 2)
    backgroundPool.start()
  if not exitRegistered:
    addExitProc(shutdownBackgroundWorkers)
    exitRegistered = true
  backgroundPool

proc backgroundTimerThread*(): NimkitTimerThreadPtr =
  ## Borrow the application-lifetime timer thread; clients cancel their own timers.
  discard backgroundWorkerPool()
  if backgroundTimers.isNil:
    backgroundTimers = newNimkitTimerThread()
    backgroundTimers.start()
  backgroundTimers

var backgroundWorkerLifetime {.used.}: BackgroundWorkerLifetime
