## macOS native-menu retention diagnostic.
## Run: atlas-run tests tests/benchmarks/nativemenumemory.nim
##
## Event polling and menu replacement deliberately use separate scopes, as they
## do when Kosmo handles queued work between native event polls. The live heap
## should stabilize after AppKit warms up, and retired items should be released
## before the outer pool drains. There is no machine-dependent memory threshold.

when defined(macosx):
  import darwin/app_kit/[nsapplication, nseventmask, nsmenu]
  import darwin/foundation/[nsautoreleasepool, nsdate, nsrunloop]
  import darwin/objc/runtime

  import merenda/nimkit/controls/nativemenus

  proc submenu(item: NSMenuItem): NSMenu {.objc: "submenu".}
  proc objc_initWeak(location: ptr pointer, value: pointer): pointer {.importc, cdecl.}
  proc objc_destroyWeak(location: ptr pointer) {.importc, cdecl.}

  {.
    emit:
      """
#include <malloc/malloc.h>
static size_t menuHeapBytes(void) {
  malloc_statistics_t stats;
  malloc_zone_statistics(NULL, &stats);
  return stats.size_in_use;
}
"""
  .}
  proc heapBytes(): uint {.importc: "menuHeapBytes", nodecl.}

  proc pollEvents(application: NSApplication) =
    let pool = NSAutoreleasePool.alloc().init()
    defer:
      pool.drain()
    while true:
      let event = application.nextEventMatchingMask(
        NSEventMaskAny, NSDate.distantPast, NSDefaultRunLoopMode, true
      )
      if event.isNil:
        break
      application.sendEvent(event)

  proc measureMenuReplacements() =
    let outerPool = NSAutoreleasePool.alloc().init()
    defer:
      outerPool.drain()
    let application = NSApplication.sharedApplication()
    application.finishLaunching()
    var rootIdentity, childIdentity: int
    let child = NativeMenuDescription(identity: addr childIdentity, title: "File")
    for index in 0 ..< 40:
      child.items.add NativeMenuItemDescription(
        title: "Action " & $index, enabled: true
      )
    let menu = NativeMenuDescription(
      identity: addr rootIdentity,
      title: "Main",
      items: @[NativeMenuItemDescription(title: "File", enabled: true, submenu: child)],
    )
    var observed: array[20, pointer]
    defer:
      installNativeMenus(nil, nil, nil)
      for item in observed.mitems:
        objc_destroyWeak(addr item)
    let initial = heapBytes().int
    for index in 0 ..< 500:
      application.pollEvents()
      installNativeMenus(menu, nil, nil)
      if index < observed.len:
        discard objc_initWeak(
          addr observed[index],
          cast[pointer](application.mainMenu().itemAtIndex(0).submenu().itemAtIndex(0)),
        )
      if (index + 1) mod 100 == 0:
        echo "replacements=", index + 1, " heapDeltaBytes=", heapBytes().int - initial
    installNativeMenus(nil, nil, nil)
    application.pollEvents()
    var retained: int
    for item in observed:
      if not item.isNil:
        inc retained
    echo "retired items retained before outer pool drains=", retained

  measureMenuReplacements()
else:
  echo "Native-menu memory diagnostics require macOS."
