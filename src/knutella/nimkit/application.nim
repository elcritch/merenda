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
  app.xWindows.add window

proc windows*(app: Application): lent seq[Window] =
  app.xWindows

proc isRunning*(app: Application): bool =
  app.xRunning

proc runForFrames*(app: Application, frames: Natural): int =
  app.xRunning = true
  result = frames.int
  app.xRunning = false

proc stop*(app: Application) =
  app.xRunning = false
