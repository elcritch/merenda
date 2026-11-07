import std/[os, strutils, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo
import fixtures/ui

func closeTo(actual, expected: Color): bool =
  abs(actual.r - expected.r) < 0.004 and abs(actual.g - expected.g) < 0.004 and
    abs(actual.b - expected.b) < 0.004 and abs(actual.a - expected.a) < 0.01

proc windowBackground(app: Application): Color =
  app
    .appearance()
    .resolveFill(controlStyle(srView), fill(color(0, 0, 0, 0)), StyleBackgroundFill)
    .centerColor()

proc themeByName(themes: openArray[ContentTheme], name: string): ContentTheme =
  for theme in themes:
    if theme.name.toLowerAscii() == name:
      return theme

suite "Kosmo adaptive merenda theme":
  test "adaptive chrome follows the editor palette across changes":
    let
      root = createTempDir("kosmo-adaptive-theme-", "")
      path = root / "config.json"
      app = newApplication("Kosmo Adaptive Theme Test")
    defer:
      removeDir(root)
    let themes = standaloneMoeThemes()
    let
      mocha = themes.themeByName("catppuccin mocha")
      latte = themes.themeByName("catppuccin latte")
    require mocha.identifier.len > 0
    require latte.identifier.len > 0
    var config = KosmoConfig(merendaTheme: "macos-adaptive", moeTheme: mocha.identifier)
    require config.saveKosmoConfig(path)
    let manager = newKosmoWindowManager(
      app, configPath = path, assetCacheDirectory = root / "assets"
    )
    defer:
      manager.close()
    let frontend = newKosmoApplication(manager, monitorsGitStatus = false)

    check app.merendaSettingsThemeIdentifier == "macos-adaptive"
    check windowBackground(app).closeTo(mocha.palette.background.toColor())
    check not windowBackground(app).closeTo(
      initMacOSDarkTheme()
        .resolveFill(controlStyle(srView), fill(color(0, 0, 0, 0)), StyleBackgroundFill)
        .centerColor()
    )

    # Switching the editor palette recolors the chrome without a restart.
    require frontend.setMoeTheme(latte.identifier)
    check windowBackground(app).closeTo(latte.palette.background.toColor())
    check loadKosmoConfig(path).moeTheme == latte.identifier

    # Reapplying the same editor theme leaves the chrome untouched.
    let unchanged = app.appearance().theme.generation
    check frontend.setMoeTheme(latte.identifier)
    check app.appearance().theme.generation == unchanged

  test "non adaptive merenda themes ignore editor palette changes":
    let
      root = createTempDir("kosmo-static-theme-", "")
      path = root / "config.json"
      app = newApplication("Kosmo Static Theme Test")
    defer:
      removeDir(root)
    let themes = standaloneMoeThemes()
    let
      mocha = themes.themeByName("catppuccin mocha")
      latte = themes.themeByName("catppuccin latte")
    require mocha.identifier.len > 0
    require latte.identifier.len > 0
    var config = KosmoConfig(merendaTheme: "macos-dark", moeTheme: mocha.identifier)
    require config.saveKosmoConfig(path)
    let manager = newKosmoWindowManager(
      app, configPath = path, assetCacheDirectory = root / "assets"
    )
    defer:
      manager.close()
    let frontend = newKosmoApplication(manager, monitorsGitStatus = false)

    let staticBackground = windowBackground(app)
    require frontend.setMoeTheme(latte.identifier)
    check windowBackground(app).closeTo(staticBackground)
    check loadKosmoConfig(path).moeTheme == latte.identifier

  test "selecting macOS Adaptive in Merenda settings applies and persists":
    let
      root = createTempDir("kosmo-adaptive-settings-", "")
      path = root / "config.json"
      app = newApplication("Kosmo Adaptive Settings Test")
    defer:
      removeDir(root)
    let mocha = standaloneMoeThemes().themeByName("catppuccin mocha")
    require mocha.identifier.len > 0
    var config = KosmoConfig(moeTheme: mocha.identifier)
    require config.saveKosmoConfig(path)
    let manager = newKosmoWindowManager(
      app, configPath = path, assetCacheDirectory = root / "assets"
    )
    defer:
      manager.close()
    discard newKosmoApplication(manager, monitorsGitStatus = false)

    app.showMerendaSettings()
    let settingsWindow = app.windows[^1]
    let
      themeView =
        settingsWindow.contentView().viewWithIdentifier("settings-theme-picker")
      saveView =
        settingsWindow.contentView().viewWithIdentifier(SettingsSaveDefaultsIdentifier)
    require themeView of ComboBox
    require saveView of Button
    # macOS Adaptive follows DarkBSD, Aqua, macOS and macOS Dark in the picker.
    ComboBox(themeView).selectedIndex = 4
    check ComboBox(themeView).sendAction()
    check windowBackground(app).closeTo(mocha.palette.background.toColor())
    check Button(saveView).sendAction()
    check loadKosmoConfig(path).merendaTheme == "macos-adaptive"
