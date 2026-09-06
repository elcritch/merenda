## Shared background execution for NimKit text parsing, highlighting and layout.
## Resolve on the owning UI thread; widgets borrow the pool and never stop it.

import std/exitprocs
import sigils/threads

var
  backgroundPool {.threadvar.}: SigilThreadPoolPtr
  exitRegistered {.threadvar.}: bool

proc stopBackgroundPool() {.noconv.} =
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
