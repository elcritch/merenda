import std/[json, math, os, strutils, tempfiles, unittest]

import crunchy/[common, sha256]

import merenda/nimkit
import merenda/kosmo/kosmo

suite "Kosmo configuration":
  test "installs bundled fonts as Kosmo defaults":
    let
      root = createTempDir("merenda-kosmo-fonts-", "")
      app = newApplication("Kosmo Bundled Fonts Test")
      manager = newKosmoWindowManager(app, assetCacheDirectory = root)
    defer:
      manager.close()
      removeDir(root)

    let
      interfaceFaces = app.appearance().fontFaces(frUI)
      interfaceFace = interfaceFaces.regular
      monospaceFace = app.appearance().fontFace(frMonospace)
    check app.appearance().fontName(frUI) == KosmoInterfaceFontName
    check app.appearance().fontName(frMonospace) == KosmoMonospaceFontName
    check interfaceFace.file.path.extractFilename().endsWith(KosmoInterfaceFontFileName)
    check monospaceFace.file.path.extractFilename().endsWith(KosmoMonospaceFontFileName)
    check sha256(readFile(interfaceFace.file.path)).toHex().toLowerAscii() ==
      KosmoInterfaceFontSha256
    check sha256(readFile(interfaceFaces.italic.file.path)).toHex().toLowerAscii() ==
      KosmoInterfaceItalicFontSha256
    check sha256(readFile(interfaceFaces.bold.file.path)).toHex().toLowerAscii() ==
      KosmoInterfaceBoldFontSha256
    check interfaceFaces.boldItalic.file.path.len == 0
    check sha256(readFile(monospaceFace.file.path)).toHex().toLowerAscii() ==
      KosmoMonospaceFontSha256
    let
      interfaceStyle = app.appearance().resolveTextStyle(
          controlStyle(srTextView), color(0.0, 0.0, 0.0), insets(0.0)
        )
      monospaceStyle = app.appearance().resolveTextStyle(
          controlStyle(srMonoTextView), color(0.0, 0.0, 0.0), insets(0.0)
        )
    discard interfaceStyle.textFont(frUI)
    discard monospaceStyle.textFont(frMonospace)

    app.showMerendaSettings()
    check app.appearance().fontFace(frUI) == interfaceFace
    check app.appearance().fontFace(frMonospace) == monospaceFace
    app.windows[^1].close()

  test "falls back to system fonts when the asset cache cannot be written":
    let
      root = createTempDir("merenda-kosmo-font-fallback-", "")
      cachePath = root / "not-a-directory"
      app = newApplication("Kosmo Font Fallback Test")
    defer:
      removeDir(root)
    writeFile(cachePath, "occupied")

    let manager = newKosmoWindowManager(app, assetCacheDirectory = cachePath)
    defer:
      manager.close()
    check app.appearance().fontName(frUI) == platformDefaultFontName(frUI)
    check app.appearance().fontName(frMonospace) == platformDefaultFontName(frMonospace)
    check app.appearance().fontFace(frUI).file.path.len == 0
    check app.appearance().fontFace(frMonospace).file.path.len == 0

  test "defers unused bundled font installation until settings requests it":
    let
      root = createTempDir("merenda-kosmo-deferred-fonts-", "")
      cachePath = root / "assets"
      configPath = root / "config.json"
      config = KosmoConfig(
        merendaFont: "Configured Interface", merendaMonoFont: "Configured Monospace"
      )
      app = newApplication("Kosmo Deferred Fonts Test")
    defer:
      removeDir(root)
    require config.saveKosmoConfig(configPath)

    let manager = newKosmoWindowManager(
      app, configPath = configPath, assetCacheDirectory = cachePath
    )
    defer:
      manager.close()
    check not dirExists(cachePath)

    app.showMerendaSettings()
    check dirExists(cachePath)
    for fileName in [
      KosmoInterfaceFontFileName, KosmoInterfaceItalicFontFileName,
      KosmoInterfaceBoldFontFileName, KosmoMonospaceFontFileName,
    ]:
      var found = false
      for path in walkDirRec(cachePath):
        if path.extractFilename().endsWith(fileName):
          found = true
      check found
    app.windows[^1].close()

  test "does not install bundled fonts without an application":
    let
      root = createTempDir("merenda-kosmo-no-app-fonts-", "")
      cachePath = root / "assets"
      manager = newKosmoWindowManager(app = nil, assetCacheDirectory = cachePath)
    defer:
      manager.close()
      removeDir(root)

    check not dirExists(cachePath)

  test "round trips the persisted appearance choices as JSON":
    let
      root = createTempDir("merenda-kosmo-config-", "")
      path = root / "config.json"
      config = KosmoConfig(
        moeTheme: KosmoMoeDefaultThemeIdentifier,
        nimLspCommand: "custom-server --stdio",
        merendaTheme: "aqua",
        merendaFont: "Iosevka",
        merendaMonoFont: "JetBrains Mono",
        merendaFontSize: 17.0'f32,
        merendaInvertScrolling: true,
        merendaUiScale: 1.25'f32,
        merendaAutoSaveDefaults: true,
      )
    defer:
      removeDir(root)

    check config.saveKosmoConfig(path)
    let node = parseJson(readFile(path))
    check node["moeTheme"].getStr() == KosmoMoeDefaultThemeIdentifier
    check node["nimLspCommand"].getStr() == "custom-server --stdio"
    check node["merendaTheme"].getStr() == "aqua"
    check node["merendaFont"].getStr() == "Iosevka"
    check node["merendaMonoFont"].getStr() == "JetBrains Mono"
    check node["merendaFontSize"].getFloat() == float(config.merendaFontSize)
    check node["merendaInvertScrolling"].getBool()
    check node["merendaUiScale"].getFloat() == float(config.merendaUiScale)
    check node["merendaAutoSaveDefaults"].getBool()
    check loadKosmoConfig(path) == config

  test "passes the configured Nim server command to Moe":
    let
      root = createTempDir("merenda-kosmo-nim-lsp-", "")
      path = root / "config.json"
      app = newApplication("Kosmo Nim LSP Config Test")
      command = "custom-server --stdio"
      config = KosmoConfig(nimLspCommand: command)
    defer:
      removeDir(root)
    require config.saveKosmoConfig(path)
    let manager = newKosmoWindowManager(app, configPath = path)
    defer:
      manager.close()
    let frontend = newKosmoApplication(manager, monitorsGitStatus = false)
    check frontend.editorView.editor.nimLspConfiguration() ==
      (enabled: true, command: command)

  test "ignores malformed JSON configuration":
    let
      root = createTempDir("merenda-kosmo-invalid-config-", "")
      path = root / "config.json"
    defer:
      removeDir(root)
    writeFile(path, "{\"moeTheme\":")

    check loadKosmoConfig(path) == KosmoConfig()

  test "loads saved appearance and Moe theme preferences":
    let
      root = createTempDir("merenda-kosmo-load-config-", "")
      path = root / "config.json"
      config = KosmoConfig(
        moeTheme: KosmoMoeDefaultThemeIdentifier,
        merendaTheme: "aqua",
        merendaFont: "Iosevka",
        merendaMonoFont: "JetBrains Mono",
        merendaFontSize: 17.0'f32,
        merendaInvertScrolling: true,
        merendaUiScale: 1.25'f32,
        merendaAutoSaveDefaults: true,
      )
      app = newApplication("Kosmo Config Test")
    defer:
      removeDir(root)
    require config.saveKosmoConfig(path)

    let manager = newKosmoWindowManager(app, configPath = path)
    defer:
      manager.close()
    let frontend = newKosmoApplication(manager, monitorsGitStatus = false)

    check app.appearance().fontName(frUI) == config.merendaFont
    check app.appearance().fontName(frMonospace) == config.merendaMonoFont
    check app.appearance().fontFace(frUI).file.path.len == 0
    check app.appearance().fontFace(frMonospace).file.path.len == 0
    check app
    .appearance()
    .resolveTextStyle(controlStyle(srTextView), color(0.0, 0.0, 0.0), insets(0.0)).fontSize ==
      config.merendaFontSize
    check app
    .appearance()
    .resolveTextStyle(controlStyle(srMonoTextView), color(0.0, 0.0, 0.0), insets(0.0)).fontSize ==
      config.merendaFontSize
    check frontend.editorView.fontSize == config.merendaFontSize
    check frontend.editorView.editor.activeMoeThemeIdentifier() == config.moeTheme
    check app.invertScrolling == config.merendaInvertScrolling
    check abs(app.uiScale - config.merendaUiScale) < 0.0001'f32
    check app.merendaSettingsAutoSaveDefaults == config.merendaAutoSaveDefaults
    check app.merendaSettingsThemeIdentifier == config.merendaTheme

  test "saves Merenda settings for the next Kosmo launch":
    let
      root = createTempDir("merenda-kosmo-settings-save-", "")
      path = root / "config.json"
      assetCache = root / "assets"
      app = newApplication("Kosmo Settings Save Test")
      manager =
        newKosmoWindowManager(app, configPath = path, assetCacheDirectory = assetCache)
      frontend = newKosmoApplication(manager, monitorsGitStatus = false)
    defer:
      manager.close()
      removeDir(root)

    app.showMerendaSettings()
    let settingsWindow = app.windows[^1]
    let
      themeView =
        settingsWindow.contentView().viewWithIdentifier("settings-theme-picker")
      tabsView = settingsWindow.contentView().viewWithIdentifier("settings-tabs")
    require themeView of ComboBox
    require tabsView of TabView
    let themePicker = ComboBox(themeView)
    themePicker.selectedIndex = 1
    check themePicker.sendAction()
    let tabs = TabView(tabsView)
    check tabs.selectTabViewItemAtIndex(0)
    let scaleView =
      settingsWindow.contentView().viewWithIdentifier(SettingsUiScaleIdentifier)
    require scaleView of Stepper
    check tabs.selectTabViewItemAtIndex(2)
    let
      invertView = settingsWindow.contentView().viewWithIdentifier(
          SettingsInvertScrollingIdentifier
        )
      saveView =
        settingsWindow.contentView().viewWithIdentifier(SettingsSaveDefaultsIdentifier)
    require invertView of Button
    require saveView of Button
    let
      scaleStepper = Stepper(scaleView)
      invertButton = Button(invertView)
      saveButton = Button(saveView)
    check scaleStepper.incrementValue()
    invertButton.state = bsOn
    check invertButton.sendAction()
    check saveButton.sendAction()

    let saved = loadKosmoConfig(path)
    check saved.merendaTheme == "aqua"
    check abs(saved.merendaUiScale - 1.1'f32) < 0.0001'f32
    check saved.merendaInvertScrolling
    check saved.merendaAutoSaveDefaults == false
    check saved.merendaFont.len == 0
    check saved.merendaMonoFont.len == 0

    settingsWindow.close()
    let
      app2 = newApplication("Kosmo Settings Reload Test")
      manager2 = newKosmoWindowManager(
        app2, configPath = path, assetCacheDirectory = root / "assets-reload"
      )
    defer:
      manager2.close()
    check app2.merendaSettingsThemeIdentifier == "aqua"
    check abs(app2.uiScale - 1.1'f32) < 0.0001'f32
    check app2.invertScrolling

  when defined(posix):
    test "live monospace appearance changes reach the editor and terminal":
      let
        app = newApplication("Kosmo Live Font Test")
        frontend = newKosmoApplication(app, monitorsGitStatus = false)
      defer:
        frontend.close()
      frontend.show()
      require frontend.newTerminal()
      require frontend.editorPane.contentView of KosmoTerminalView
      let terminal = KosmoTerminalView(frontend.editorPane.contentView)

      var
        appearance = app.effectiveAppearance()
        builder = initThemeBuilder(appearance.theme)
      builder.setFontName(frMonospace, "Kosmo Test Mono")
      builder[srMonoTextView, StyleFontSize] = 19.0'f32
      appearance.theme = builder.finish()
      app.setAppearance(appearance)

      check frontend.editorView.fontName == "Kosmo Test Mono"
      check frontend.editorView.fontSize == 19.0'f32
      check terminal.fontName == "Kosmo Test Mono"

  test "persists a selected Moe theme":
    let
      root = createTempDir("merenda-kosmo-save-config-", "")
      path = root / "config.json"
      app = newApplication("Kosmo Config Save Test")
      manager = newKosmoWindowManager(app, configPath = path)
      frontend = newKosmoApplication(manager, monitorsGitStatus = false)
    defer:
      manager.close()
      removeDir(root)

    check frontend.setMoeTheme(KosmoMoeDefaultThemeIdentifier)
    check loadKosmoConfig(path).moeTheme == KosmoMoeDefaultThemeIdentifier
