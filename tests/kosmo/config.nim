import std/[json, os, strutils, tempfiles, unittest]

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
      interfaceFace = app.appearance().fontFace(frUI)
      monospaceFace = app.appearance().fontFace(frMonospace)
    check app.appearance().fontName(frUI) == KosmoInterfaceFontName
    check app.appearance().fontName(frMonospace) == KosmoMonospaceFontName
    check interfaceFace.file.path.extractFilename().endsWith(KosmoInterfaceFontFileName)
    check monospaceFace.file.path.extractFilename().endsWith(KosmoMonospaceFontFileName)
    check sha256(readFile(interfaceFace.file.path)).toHex().toLowerAscii() ==
      KosmoInterfaceFontSha256
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
    check app.appearance().fontName(frUI) == defaultFontName(frUI)
    check app.appearance().fontName(frMonospace) == defaultFontName(frMonospace)
    check app.appearance().fontFace(frUI).file.path.len == 0
    check app.appearance().fontFace(frMonospace).file.path.len == 0

  test "round trips the persisted appearance choices as JSON":
    let
      root = createTempDir("merenda-kosmo-config-", "")
      path = root / "config.json"
      config = KosmoConfig(
        moeTheme: KosmoMoeDefaultThemeIdentifier,
        merendaTheme: "aqua",
        merendaFont: "Iosevka",
        merendaMonoFont: "JetBrains Mono",
        merendaFontSize: 17.0'f32,
      )
    defer:
      removeDir(root)

    check config.saveKosmoConfig(path)
    let node = parseJson(readFile(path))
    check node["moeTheme"].getStr() == KosmoMoeDefaultThemeIdentifier
    check node["merendaTheme"].getStr() == "aqua"
    check node["merendaFont"].getStr() == "Iosevka"
    check node["merendaMonoFont"].getStr() == "JetBrains Mono"
    check node["merendaFontSize"].getFloat() == float(config.merendaFontSize)
    check loadKosmoConfig(path) == config

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
    check frontend.editorView.editor.activeMoeThemeIdentifier() == config.moeTheme

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
    appearance.theme = builder.finish()
    app.setAppearance(appearance)

    check frontend.editorView.fontName == "Kosmo Test Mono"
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
