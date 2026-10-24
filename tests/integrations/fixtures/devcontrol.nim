## Runs before the shared integration suites in a child process.
when defined(merenda.devControl) and defined(posix):
  import std/os
  import merenda/nimkit
  import merenda/nimkit/app/backend

  const DevControlProbe* = "--merenda-dev-control-probe"

  if paramCount() == 3 and paramStr(1) == DevControlProbe:
    if paramStr(2) == "pid":
      putEnv("MERENDA_DEV_CONTROL", "1")
      delEnv("MERENDA_DEV_SOCKET")
    else:
      putEnv("MERENDA_DEV_SOCKET", paramStr(2))
    putEnv("MERENDA_BACKGROUND", "1")
    let app = newApplication("Development Control Probe")
    app.renderExecutionMode =
      if paramStr(3) == "main": remMainThread else: remDedicatedThread
    let window = newWindow("Control Probe", frame = rect(80, 80, 320, 240))
    let root = newView(frame = rect(0, 0, 320, 240))
    root.backgroundColor = color(1, 0, 0, 1)
    let lower = newView(frame = rect(0, 120, 320, 120))
    lower.backgroundColor = color(0, 0, 1, 1)
    root.addSubview(lower)
    let field = newTextField("Ready", frame = rect(20, 30, 240, 36))
    root.addSubview(field)
    let themeProbe = newView(frame = rect(275, 20, 30, 30))
    themeProbe.styleId = "dev-theme-probe"
    root.addSubview(themeProbe)
    let button = newButton("Change", frame = rect(20, 80, 100, 30))
    let action = actionSelector("changeProbe")
    button.action = action
    button.target = newActionTarget(
      action,
      proc(sender: DynamicAgent) =
        lower.backgroundColor = color(0, 1, 0, 1),
    )
    root.addSubview(button)
    let secondButton = newButton("Window", frame = rect(130, 80, 80, 30))
    let secondAction = actionSelector("secondProbe")
    secondButton.action = secondAction
    secondButton.target = newActionTarget(
      secondAction,
      proc(sender: DynamicAgent) =
        let second = newWindow("Second Probe", frame = rect(120, 120, 240, 140))
        let content = newView(frame = rect(0, 0, 240, 140))
        let anchor = newButton("Popup", frame = rect(20, 20, 120, 30))
        content.addSubview(anchor)
        let popup = newPopupHost(
          second,
          anchor,
          newLabel("Popup probe"),
          initSize(140, 60),
          presentation = ppWindow,
        )
        let popupAction = actionSelector("popupProbe")
        anchor.action = popupAction
        anchor.target = newActionTarget(
          popupAction,
          proc(sender: DynamicAgent) =
            discard popup.presentPopup(),
        )
        app.showWindow(second, content),
    )
    root.addSubview(secondButton)
    let stopButton = newButton("Stop", frame = rect(220, 80, 80, 30))
    let stopAction = actionSelector("stopProbe")
    stopButton.action = stopAction
    stopButton.target = newActionTarget(
      stopAction,
      proc(sender: DynamicAgent) =
        app.stop(),
    )
    root.addSubview(stopButton)
    app.runWindow(window, root, field)
    quit(0)
