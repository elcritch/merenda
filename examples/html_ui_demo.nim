import std/[os, strutils]

import merenda/nimkit

when isMainModule:
  let path = currentSourcePath().parentDir / "html_ui_demo.html"
  let loaded = loadHtmlResourceBundle(path)
  if not loaded.loaded:
    for diagnostic in loaded.diagnostics:
      echo diagnostic.path, ": ", diagnostic.message
    quit 1

  let built = loaded.bundle.instantiateResources(
    initResourceInstantiationContext(assetBasePath = path.parentDir)
  )
  if not built.instantiated:
    for diagnostic in built.diagnostics:
      echo diagnostic.path, ": ", diagnostic.message
    quit 1

  let
    app = newApplication("HTML GUI")
    window = built.instance.window(resourceId("window"))
    name = TextField(built.instance.view(resourceId("name")))
    updates = Button(built.instance.view(resourceId("updates")))
    language = ComboBox(built.instance.view(resourceId("language")))
    preview = Button(built.instance.view(resourceId("preview")))
    reset = Button(built.instance.view(resourceId("reset")))
    progress = ProgressIndicator(built.instance.view(resourceId("progress")))
    status = TextField(built.instance.view(resourceId("status")))
    stylesheet = loadCssTheme(path.changeFileExt("css"), initThemeByName("macos-dark"))

  if stylesheet.diagnostics.len > 0:
    for diagnostic in stylesheet.diagnostics:
      echo "CSS line ", diagnostic.line, ": ", diagnostic.message
    quit 1
  window.contentView.appearance = initAppearance(stylesheet.theme)

  preview.target = newActionTarget(
    preview.action,
    proc(sender: DynamicAgent) =
      let
        displayName = name.stringValue.strip()
        subscription = if updates.state == bsOn: "Updates on" else: "Updates off"
      status.stringValue =
        (if displayName.len > 0: displayName else: "Anonymous") & " · " &
        language.itemAtIndex(language.selectedIndex) & " · " & subscription
      progress.value = 100,
  )
  reset.target = newActionTarget(
    reset.action,
    proc(sender: DynamicAgent) =
      name.stringValue = "Ada"
      language.selectedIndex = 0
      updates.state = bsOn
      progress.value = 0
      status.stringValue = "Your preview will appear here.",
  )
  app.runWindow(window, window.contentView)
