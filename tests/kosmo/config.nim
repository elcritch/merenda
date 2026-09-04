import std/[json, os, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

suite "Kosmo configuration":
  test "round trips the persisted appearance choices as JSON":
    let
      root = createTempDir("merenda-kosmo-config-", "")
      path = root / "config.json"
      config = KosmoConfig(
        moeTheme: KosmoMoeDefaultThemeIdentifier,
        merendaTheme: "aqua",
        merendaFont: "Iosevka",
        merendaMonoFont: "JetBrains Mono",
      )
    defer:
      removeDir(root)

    check config.saveKosmoConfig(path)
    let node = parseJson(readFile(path))
    check node["moeTheme"].getStr() == KosmoMoeDefaultThemeIdentifier
    check node["merendaTheme"].getStr() == "aqua"
    check node["merendaFont"].getStr() == "Iosevka"
    check node["merendaMonoFont"].getStr() == "JetBrains Mono"
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
    check frontend.editorView.editor.activeMoeThemeIdentifier() == config.moeTheme

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
