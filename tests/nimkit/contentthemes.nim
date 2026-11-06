import std/[os, tempfiles, unittest]
import merenda/nimkit
import merenda/nimkit/contentthemes

suite "NimKit content themes":
  test "one palette applies to Markdown, the editor, and terminal without engine types":
    var palette = initContentPalette()
    palette.background = ContentThemeColor(red: 20, green: 30, blue: 40)
    palette.foreground = ContentThemeColor(red: 230, green: 240, blue: 250)
    palette.keyword = ContentThemeColor(red: 150, green: 100, blue: 200)
    let theme = initContentTheme("Custom", palette)
    let reader = newMarkdownView()
    let editor = newSynEditView()
    let terminal = newTerminalView()
    defer:
      terminal.close()
    var style = reader.markdownStyle()
    style.bodyFontSize = 21
    reader.markdownStyle = style
    reader.contentTheme = theme
    editor.contentTheme = theme
    terminal.contentTheme = theme
    check reader.markdownStyle().bodyFontSize == 21
    check reader.markdownStyle().backgroundColor == palette.background.toColor()
    check editor.theme().background == palette.background.toColor()
    check terminal.palette.background == palette.background.toColor()
    check editor.theme().foreground[stcKeyword] == palette.keyword.toColor()
    check reader.markdownStyle().syntaxTokenColors[stcKeyword] ==
      palette.keyword.toColor()
    check terminal.palette.colors[5] == palette.keyword.toColor()

  test "loads TOML palettes and rejects invalid recognized colors":
    let root = createTempDir("nimkit-contentthemes-", "")
    defer:
      removeDir(root)
    writeFile(
      root / "custom.toml",
      "[Colors]\nforeground = \"#123456\"\nbackground = \"#abcdef\"\n" &
        "keyword = { fg = \"#fedcba\" }\n",
    )
    let theme = loadContentTheme(root / "custom.toml")
    check theme.name == "Custom"
    check theme.validContentTheme()
    check theme.palette.foreground ==
      ContentThemeColor(red: 0x12, green: 0x34, blue: 0x56)
    check theme.palette.keyword == ContentThemeColor(red: 0xfe, green: 0xdc, blue: 0xba)
    let themes = discoverContentThemes(root)
    check themes.len == 2
    check themes[0].toTerminalPalette().background ==
      themes[0].palette.background.toColor()
    expect ValueError:
      discard parseContentPalette("[Colors]\nforeground = \"#zzzzzz\"")
    expect ValueError:
      discard parseContentPalette("[Other]\nvalue = 1")

  test "bundled palettes and licenses install without application-specific code":
    let root = createTempDir("nimkit-bundled-contentthemes-", "")
    defer:
      removeDir(root)
    let directory = installBundledContentThemes(root)
    let themes = discoverContentThemes(directory)
    check themes.len >= 26
    for theme in themes:
      check theme.validContentTheme()
    check fileExists(directory / "licenses" / "catppuccin.txt")
