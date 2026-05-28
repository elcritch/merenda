import std/os

import ./windows

type Application* = ref object
  xWindows: seq[Window]
  xRunning: bool

var sharedApplicationInstance: Application

proc newApplication*(): Application =
  Application()

proc sharedApplication*(): Application =
  if sharedApplicationInstance.isNil:
    sharedApplicationInstance = newApplication()
  sharedApplicationInstance

proc addWindow*(app: Application, window: Window) =
  if window notin app.xWindows:
    app.xWindows.add window

proc windows*(app: Application): lent seq[Window] =
  app.xWindows

proc isRunning*(app: Application): bool =
  app.xRunning

proc runForFrames*(app: Application, frames: Natural): int =
  if frames == 0:
    return 0
  app.xRunning = true
  while app.xRunning:
    var activeWindows = 0
    var idx = 0
    while idx < app.xWindows.len:
      let window = app.xWindows[idx]
      if window.isNil or window.isClosed:
        app.xWindows.delete(idx)
        continue
      if window.isVisible:
        window.pumpNativeWindowFrame()
        if not window.isClosed:
          inc activeWindows
      inc idx

    inc result
    if result >= frames.int:
      break
    if activeWindows == 0:
      break
    sleep(8)
  app.xRunning = false

proc run*(app: Application) =
  app.xRunning = true
  while app.xRunning:
    var activeWindows = 0
    var idx = 0
    while idx < app.xWindows.len:
      let window = app.xWindows[idx]
      if window.isNil or window.isClosed:
        app.xWindows.delete(idx)
        continue
      if window.isVisible:
        window.pumpNativeWindowFrame()
        if not window.isClosed:
          inc activeWindows
      inc idx

    if activeWindows == 0:
      break
    sleep(8)
  app.xRunning = false

proc stop*(app: Application) =
  app.xRunning = false
