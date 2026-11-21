## Timer dispatcher shared by NimKit's background services and animation clocks.

when defined(features.merenda.chronos):
  import sigils/threadChronos
  export threadChronos

  type NimkitTimerThreadPtr* = SigilChronosThreadPtr

  proc newNimkitTimerThread*(): NimkitTimerThreadPtr =
    newSigilChronosThread()

  proc joinTimerThread*(thread: NimkitTimerThreadPtr) =
    thread.join()

else:
  import std/[locks, selectors, tables]
  import sigils/core
  import sigils/threadSelectors
  export threadSelectors

  type
    NimkitTimerThreadPtr* = SigilSelectorThreadPtr

    TimerUpdate = object
      timer: WeakRef[SigilTimer]
      cancel: bool
      lock: Lock
      completed: Cond
      finished: bool
      error: ref Exception

  proc newNimkitTimerThread*(): NimkitTimerThreadPtr =
    newSigilSelectorThread()

  proc joinTimerThread*(thread: NimkitTimerThreadPtr) =
    thread.join()
    thread.closeSelectorThread()

  proc applyTimerUpdate(thread: NimkitTimerThreadPtr, timer: SigilTimer, cancel: bool) =
    if not cancel:
      thread.setTimer(timer)
    elif timer in thread.timerHandles:
      when defined(windows):
        # Windows tracks deadlines in memory and has no timer descriptor to close.
        thread.cancelTimer(timer)
      else:
        thread.sel.unregister(thread.timerHandles[timer])
        thread.timerHandles.del(timer)

  proc applyTimerUpdate(context: Agent, params: SigilParams) {.nimcall.} =
    var update: ptr TimerUpdate
    rpcUnpack(update, params)
    let thread = cast[NimkitTimerThreadPtr](getCurrentSigilThread())
    try:
      thread.applyTimerUpdate(update.timer[], update.cancel)
    except Exception as error:
      update.error = error
    finally:
      withLock update.lock:
        update.finished = true
        update.completed.signal()

  proc updateTimer(thread: NimkitTimerThreadPtr, timer: SigilTimer, cancel: bool) =
    if hasLocalSigilThread() and getCurrentSigilThread() == thread.toSigilThread():
      thread.applyTimerUpdate(timer, cancel)
      return

    # Selector registration and cancellation belong to the selector thread.
    # Wait for cancellation before the caller disconnects the timer's signals.
    var update = TimerUpdate(timer: timer.unsafeWeakRef(), cancel: cancel)
    update.lock.initLock()
    update.completed.initCond()
    defer:
      update.completed.deinitCond()
      update.lock.deinitLock()
    withLock update.lock:
      thread.send ThreadSignal(
        kind: Call,
        tgt: thread.agent.unsafeWeakRef().asAgent(),
        slot: applyTimerUpdate,
        req: initSigilRequest[ptr TimerUpdate, ptr TimerUpdate](
          sigName("nimkitTimerUpdate"), addr update
        ),
      )
      while not update.finished:
        update.completed.wait(update.lock)
    if not update.error.isNil:
      raise update.error

  proc start*(timer: SigilTimer, thread: NimkitTimerThreadPtr) =
    thread.updateTimer(timer, cancel = false)

  proc cancel*(timer: SigilTimer, thread: NimkitTimerThreadPtr) =
    thread.updateTimer(timer, cancel = true)
