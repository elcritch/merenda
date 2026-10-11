import std/[os, strutils]

import merenda/nimkit

proc configureHtmlUiDemo*(
    app: Application, instance: ResourceInstance, customTheme: Theme
) =
  ## Connect the GUI actions and apply the selected CSS appearance to both windows.
  let
    window = instance.window(resourceId("window"))
    name = TextField(instance.view(resourceId("name")))
    updates = Button(instance.view(resourceId("updates")))
    language = ComboBox(instance.view(resourceId("language")))
    themePicker = ComboBox(instance.view(resourceId("theme")))
    preview = Button(instance.view(resourceId("preview")))
    reset = Button(instance.view(resourceId("reset")))
    progress = ProgressIndicator(instance.view(resourceId("progress")))
    status = TextField(instance.view(resourceId("status")))
    about = instance.window(resourceId("about"))
    showAbout = Button(instance.view(resourceId("show-about")))
    closeAbout = Button(instance.view(resourceId("close-about")))
    customStyles = customTheme

  proc applyTheme() =
    let index = themePicker.selectedIndex
    if index < 0 or index >= themePicker.numberOfItems:
      return
    let themeName = themePicker.itemObjectValueAtIndex(index).requireString()
    let theme =
      if themeName == "custom":
        customStyles
      else:
        initThemeByName(themeName)
    window.setAppearance(initAppearance(theme))
    about.setAppearance(initAppearance(theme))
    window.contentView.layoutSubtreeIfNeeded()

  themePicker.target = newActionTarget(
    themePicker.action,
    proc(sender: DynamicAgent) =
      applyTheme(),
  )
  applyTheme()

  showAbout.target = newActionTarget(
    showAbout.action,
    proc(sender: DynamicAgent) =
      app.addWindow(about)
      about.makeKeyAndOrderFront(),
  )
  closeAbout.target = newActionTarget(
    closeAbout.action,
    proc(sender: DynamicAgent) =
      about.close(),
  )

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
      themePicker.selectedIndex = 0
      applyTheme()
      updates.state = bsOn
      progress.value = 0
      status.stringValue = "Your preview will appear here.",
  )

when isMainModule:
  let path = currentSourcePath().parentDir / "html_ui_demo.html"
  let loaded = loadGuiResourceBundle(path)
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

  let stylesheet =
    loadCssTheme(path.changeFileExt("css"), initThemeByName("macos-dark"))
  if stylesheet.diagnostics.len > 0:
    for diagnostic in stylesheet.diagnostics:
      echo "CSS line ", diagnostic.line, ": ", diagnostic.message
    quit 1

  let
    app = newApplication("GUI resources")
    window = built.instance.window(resourceId("window"))
  app.configureHtmlUiDemo(built.instance, stylesheet.theme)
  app.addWindow(built.instance.window(resourceId("about")))
  app.runWindow(window, window.contentView)
