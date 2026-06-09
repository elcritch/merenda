import std/os

import sigils/selectors

import ./responders
import ./selectors as nimkitSelectors
import ./theme
import ./windows

type Application* = ref object of Responder
  xWindows: seq[Window]
  xDelegate: DynamicAgent
  xAppearance: Appearance
  xHasAppearance: bool
  xRunning: bool

var sharedApplicationInstance: Application

proc applicationForwardingTarget(app: Application, selector: SigilName): DynamicAgent =
  if not app.xDelegate.isNil and app.xDelegate.respondsTo(selector):
    return app.xDelegate

proc installApplicationForwarding(app: Application) =
  app.setForwardingTarget(
    proc(self: DynamicAgent, selector: SigilName): DynamicAgent =
      applicationForwardingTarget(Application(self), selector)
  )

proc newApplication*(): Application =
  result = Application()
  initResponder(result)
  result.installApplicationForwarding()

proc sharedApplication*(): Application =
  if sharedApplicationInstance.isNil:
    sharedApplicationInstance = newApplication()
  sharedApplicationInstance

proc hasAppearance*(app: Application): bool =
  (not app.isNil) and app.xHasAppearance

proc appearance*(app: Application): Appearance =
  if app.isNil or not app.xHasAppearance:
    return initAppearance()
  app.xAppearance

proc effectiveAppearance*(app: Application): Appearance =
  if app.isNil or not app.xHasAppearance:
    return initAppearance()
  app.xAppearance

proc delegate*(app: Application): DynamicAgent =
  if app.isNil: nil else: app.xDelegate

proc `delegate=`*(app: Application, delegate: DynamicAgent) =
  if app.isNil:
    return
  app.xDelegate = delegate

proc `delegate=`*(app: Application, delegate: Responder) =
  app.delegate = DynamicAgent(delegate)

proc propagateAppearance(app: Application) =
  let inherited = app.effectiveAppearance()
  for window in app.xWindows:
    window.setInheritedAppearance(inherited)

proc setAppearance*(app: Application, appearance: Appearance) =
  app.xAppearance = appearance
  app.xHasAppearance = true
  app.propagateAppearance()

proc clearAppearance*(app: Application) =
  if app.isNil or not app.xHasAppearance:
    return
  app.xAppearance = Appearance()
  app.xHasAppearance = false
  app.propagateAppearance()

proc addWindow*(app: Application, window: Window) =
  if app.isNil or window.isNil:
    return
  if window notin app.xWindows:
    app.xWindows.add window
  window.setNextResponder(app)
  window.setInheritedAppearance(app.effectiveAppearance())

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
        if not window.isNil and window.nextResponder() == Responder(app):
          window.clearNextResponder()
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
        if not window.isNil and window.nextResponder() == Responder(app):
          window.clearNextResponder()
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
