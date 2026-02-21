import std/[os, strutils]

import nutella/appkit

proc maxFramesFromEnv(defaultValue = -1): int =
  let raw = getEnv("NUTELLA_EXAMPLE_FRAMES").strip()
  if raw.len == 0:
    return defaultValue
  try:
    parseInt(raw)
  except ValueError:
    defaultValue

proc debugRenderDumpEnabled(): bool =
  getEnv("NUTELLA_APPKIT_DEBUG_RENDER").strip().toLowerAscii() in
    ["1", "true", "yes", "on"]

const
  titleTag = 1001
  badgeTag = 1002
  statusTag = 1003

proc stateName(state: int): string =
  case state
  of NSOnState: "On"
  of NSMixedState: "Mixed"
  else: "Off"

when isMainModule:
  var app = NSApp()
  var window = newWindow(120, 120, 720, 460, "Nutella AppKit Hello")
  window.setFrameOrigin(nsPoint(120, 120))
  window.setContentSize(nsSize(720, 460))

  var root = newView(0, 0, 720, 460)
  root.setTag(1)
  root.setBackgroundColor(0.95, 0.96, 0.98, 1.0)

  var title = newTextField(28, 28, 520, 48, "Hello from Nutella/AppKit")
  title.setTag(titleTag)
  title.setAlignment(NSCenterTextAlignment)
  title.setTextColor(nsColor(0.13, 0.20, 0.34, 1.0))
  title.setDrawsBackground(false)
  root.addSubview(title)

  var subtitle = newTextField(
    28, 86, 620, 36,
    "Ported APIs: setTag/viewWithTag/removeFromSuperview/alignment/state/contentSize",
  )
  subtitle.setAlignment(NSLeftTextAlignment)
  subtitle.setTextColor(nsColor(0.20, 0.24, 0.31, 1.0))
  subtitle.setBackgroundColor(nsColor(0.98, 0.98, 0.99, 1.0))
  root.addSubview(subtitle)

  var badge = newTextField(560, 30, 132, 28, "Temporary Tag")
  badge.setTag(badgeTag)
  badge.setAlignment(NSCenterTextAlignment)
  badge.setBackgroundColor(nsColor(0.91, 0.95, 1.0, 1.0))
  root.addSubview(badge)

  var taggedBadge = root.viewWithTag(badgeTag)
  if not taggedBadge.isNil:
    taggedBadge.removeFromSuperview()
  taggedBadge.value = nil
  badge.value = nil

  var status = newTextField(28, 132, 420, 30, "Button state cycle: Off -> On -> Mixed")
  status.setTag(statusTag)
  status.setDrawsBackground(false)
  status.setTextColor(nsColor(0.12, 0.28, 0.20, 1.0))
  root.addSubview(status)

  var button = newButton(28, 172, 220, 44, "Cycle State")
  button.setAllowsMixedState(true)
  button.setState(NSOffState.cint)
  button.setAlignment(NSCenterTextAlignment)
  echo "initial button state: ", button.state()
  let initialStateLabel = stateName(button.state())
  status.setStringValue("Button state: " & initialStateLabel & " (click to cycle)")
  button.setTitle("Cycle State (" & initialStateLabel & ")")
  button.setOnClick(
    proc(sender: NSButton) =
      let label = stateName(sender.state())
      status.setStringValue("Button state: " & label & " (click to cycle)")
      sender.setTitle("Cycle State (" & label & ")")
      echo "button clicked, state=", label
  )
  root.addSubview(button)

  var lookedUpTitle = root.viewWithTag(titleTag)
  if not lookedUpTitle.isNil:
    lookedUpTitle.setFrameOrigin(nsPoint(28, 20))
  lookedUpTitle.value = nil

  var parent = button.superview()
  if not parent.isNil:
    echo "button superview tag: ", parent.tag()
  parent.value = nil

  window.setContentView(root)
  app.addWindow(window)
  window.makeKeyAndOrderFront(app)
  echo "window title: ", window.title(), ", tracked windows: ", app.windows().len
  if debugRenderDumpEnabled():
    debugDumpWindowRenderTree(window)

  try:
    let maxFrames = maxFramesFromEnv()
    if maxFrames < 0:
      app.run()
    else:
      discard app.runForFrames(maxFrames)
  except Exception as exc:
    echo "Unable to run AppKit example: ", exc.msg
  finally:
    status.value = nil
    button.value = nil
    subtitle.value = nil
    title.value = nil
    root.value = nil
    window.value = nil
    app.value = nil
