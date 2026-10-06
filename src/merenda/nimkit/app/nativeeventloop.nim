## Service application frames while AppKit owns a nested tracking or modal loop.
## Normal application waits remain event driven; timers follow actual deadlines.

import std/times

type NativeEventPump* = proc(): Duration {.closure.}
  ## Drain one application frame and return its next wait, or Duration.high.

when defined(macosx):
  import darwin/foundation/[nsautoreleasepool, nsstring]
  import darwin/objc/runtime

  {.passL: "-framework CoreFoundation".}

  const CoreFoundationHeader = "<CoreFoundation/CoreFoundation.h>"

  type
    CFIndex = clong
    CFOptionFlags = culong
    Boolean = uint8
    CFString {.importc: "CFStringRef", header: CoreFoundationHeader.} = ptr object
    CFRunLoop {.importc: "CFRunLoopRef", header: CoreFoundationHeader.} = ptr object
    CFAllocator {.importc: "CFAllocatorRef", header: CoreFoundationHeader.} = ptr object
    CFRunLoopMode = CFString
    RunLoopObserver {.importc: "CFRunLoopObserverRef", header: CoreFoundationHeader.} =
      ptr object
    RunLoopTimer {.importc: "CFRunLoopTimerRef", header: CoreFoundationHeader.} =
      ptr object

    ObserverContext {.
      importc: "CFRunLoopObserverContext", header: CoreFoundationHeader, bycopy
    .} = object
      version: CFIndex
      info: pointer
      retain: proc(info: pointer): pointer {.cdecl.}
      release: proc(info: pointer) {.cdecl.}
      copyDescription: proc(info: pointer): CFString {.cdecl.}

    TimerContext {.
      importc: "CFRunLoopTimerContext", header: CoreFoundationHeader, bycopy
    .} = object
      version: CFIndex
      info: pointer
      retain: proc(info: pointer): pointer {.cdecl.}
      release: proc(info: pointer) {.cdecl.}
      copyDescription: proc(info: pointer): CFString {.cdecl.}

    NativeEventLoop = object
      frame: NativeEventPump
      observer: RunLoopObserver
      timer: RunLoopTimer
      error: ref Exception
      previous: ptr NativeEventLoop
      pumping: bool

  {.push cdecl, header: CoreFoundationHeader.}
  proc CFRunLoopGetCurrent(): CFRunLoop {.importc.}
  proc CFRelease(value: pointer) {.importc.}
  proc CFAbsoluteTimeGetCurrent(): cdouble {.importc.}
  proc CFRunLoopObserverCreate(
    allocator: CFAllocator,
    activities: CFOptionFlags,
    repeats: Boolean,
    order: CFIndex,
    callback: proc(observer: RunLoopObserver, activity: CFOptionFlags, info: pointer) {.
      cdecl, raises: []
    .},
    context: ptr ObserverContext,
  ): RunLoopObserver {.importc.}

  proc CFRunLoopAddObserver(
    loop: CFRunLoop, observer: RunLoopObserver, mode: CFRunLoopMode
  ) {.importc.}

  proc CFRunLoopObserverInvalidate(observer: RunLoopObserver) {.importc.}
  proc CFRunLoopTimerCreate(
    allocator: CFAllocator,
    fireDate, interval: cdouble,
    flags: CFOptionFlags,
    order: CFIndex,
    callback: proc(timer: RunLoopTimer, info: pointer) {.cdecl, raises: [].},
    context: ptr TimerContext,
  ): RunLoopTimer {.importc.}

  proc CFRunLoopAddTimer(
    loop: CFRunLoop, timer: RunLoopTimer, mode: CFRunLoopMode
  ) {.importc.}

  proc CFRunLoopTimerInvalidate(timer: RunLoopTimer) {.importc.}
  proc CFRunLoopTimerSetNextFireDate(timer: RunLoopTimer, fireDate: cdouble) {.importc.}
  {.pop.}

  var activeLoop {.threadvar.}: ptr NativeEventLoop

  proc checkNativeEventLoop*() =
    ## Rethrow callback failures once control returns from native dispatch.
    if not activeLoop.isNil and not activeLoop.error.isNil:
      raise activeLoop.error

  proc pump(loop: ptr NativeEventLoop) {.raises: [].} =
    if loop != activeLoop or loop.pumping or not loop.error.isNil:
      return
    loop.pumping = true
    defer:
      loop.pumping = false
    try:
      let delay = loop.frame()
      let seconds =
        if delay == Duration.high:
          1.0e9
        else:
          max(delay.inNanoseconds.float64 / 1.0e9, 0.0)
      CFRunLoopTimerSetNextFireDate(loop.timer, CFAbsoluteTimeGetCurrent() + seconds)
    except Exception as error:
      # Never unwind through AppKit. The owning Nim event loop rethrows after
      # native dispatch returns, and stops calling the failed frame meanwhile.
      loop.error = error
      CFRunLoopObserverInvalidate(loop.observer)
      CFRunLoopTimerInvalidate(loop.timer)

  proc beforeWaiting(
      observer: RunLoopObserver, activity: CFOptionFlags, info: pointer
  ) {.cdecl, raises: [].} =
    cast[ptr NativeEventLoop](info).pump()

  proc timerFired(timer: RunLoopTimer, info: pointer) {.cdecl, raises: [].} =
    cast[ptr NativeEventLoop](info).pump()

  proc start(loop: var NativeEventLoop, pump: sink NativeEventPump) =
    let pool = NSAutoreleasePool.alloc().init()
    defer:
      pool.drain()
    loop.frame = pump
    loop.previous = activeLoop
    var observerContext = ObserverContext(info: addr loop)
    var timerContext = TimerContext(info: addr loop)
    loop.observer =
      CFRunLoopObserverCreate(nil, 1'u shl 5, 1, 0, beforeWaiting, addr observerContext)
    # A reusable timer is parked far in the future when no work is scheduled.
    # It never imposes a periodic polling interval on an idle native loop.
    loop.timer = CFRunLoopTimerCreate(
      nil,
      CFAbsoluteTimeGetCurrent() + 1.0e9,
      1.0e9,
      0,
      0,
      timerFired,
      addr timerContext,
    )
    activeLoop = addr loop
    for name in ["NSEventTrackingRunLoopMode", "NSModalPanelRunLoopMode"]:
      let mode = cast[CFRunLoopMode](toNSString(name))
      CFRunLoopAddObserver(CFRunLoopGetCurrent(), loop.observer, mode)
      CFRunLoopAddTimer(CFRunLoopGetCurrent(), loop.timer, mode)

  proc stop(loop: var NativeEventLoop) =
    if activeLoop == addr loop:
      activeLoop = loop.previous
    if not loop.observer.isNil:
      CFRunLoopObserverInvalidate(loop.observer)
      CFRelease(loop.observer)
    if not loop.timer.isNil:
      CFRunLoopTimerInvalidate(loop.timer)
      CFRelease(loop.timer)

  template withNativeEventLoop*(pump: NativeEventPump, body: untyped) =
    ## Keep the callback and its native registrations alive for this scope.
    block:
      var loop: NativeEventLoop
      try:
        loop.start(pump)
        body
        if not loop.error.isNil:
          raise loop.error
      finally:
        loop.stop()

else:
  template checkNativeEventLoop*() =
    discard

  template withNativeEventLoop*(pump: NativeEventPump, body: untyped) =
    body
