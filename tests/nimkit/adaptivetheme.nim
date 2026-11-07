import std/unittest
import figdraw except CornerRadii
import merenda/nimkit

func mochaPalette(): ContentThemePalette =
  result = initContentPalette()
  result.background = ContentThemeColor(red: 0x1e, green: 0x1e, blue: 0x2e)
  result.foreground = ContentThemeColor(red: 0xcd, green: 0xd6, blue: 0xf4)
  result.keyword = ContentThemeColor(red: 0xcb, green: 0xa6, blue: 0xf7)
  result.functionName = ContentThemeColor(red: 0x89, green: 0xb4, blue: 0xfa)
  result.stringLiteral = ContentThemeColor(red: 0xa6, green: 0xe3, blue: 0xa1)
  result.comment = ContentThemeColor(red: 0x6c, green: 0x70, blue: 0x86)

func closeTo(actual, expected: Color): bool =
  abs(actual.r - expected.r) < 0.004 and abs(actual.g - expected.g) < 0.004 and
    abs(actual.b - expected.b) < 0.004 and abs(actual.a - expected.a) < 0.01

proc windowBackground(theme: Theme): Color =
  theme
    .resolveFill(controlStyle(srView), fill(color(0, 0, 0, 0)), StyleBackgroundFill)
    .centerColor()

proc buttonFill(theme: Theme): Color =
  theme.resolveBoxStyle(controlStyle(srButton)).box.fill.centerColor()

proc buttonTextColor(theme: Theme): Color =
  theme.resolveColor(controlStyle(srButton), StyleTextColor, color(0, 0, 0, 0))

suite "NimKit adaptive theme":
  test "macOS Adaptive keeps the structure and recolors from the palette":
    let
      palette = mochaPalette()
      adaptive = initMacOSAdaptiveTheme(palette)
      macosDark = initMacOSDarkTheme()

    check adaptive.windowBackground().closeTo(
      color(0x1e / 255, 0x1e / 255, 0x2e / 255, 1)
    )
    check adaptive.buttonTextColor().closeTo(
      color(0xcd / 255, 0xd6 / 255, 0xf4 / 255, 1)
    )
    # Buttons mix the palette background and foreground at the control ratio.
    check adaptive.buttonFill().closeTo(color(52 / 255, 53 / 255, 71 / 255, 0.98))
    check not adaptive.buttonFill().closeTo(macosDark.buttonFill())
    # The accent follows the palette function color.
    check adaptive.colorToken("--accent", color(0, 0, 0, 0)).closeTo(
      color(0x89 / 255, 0xb4 / 255, 0xfa / 255, 1)
    )
    # The macOS metrics stay untouched.
    let
      adaptiveStyle = adaptive.resolveButtonStyle(controlStyle(srButton))
      darkStyle = macosDark.resolveButtonStyle(controlStyle(srButton))
    check adaptiveStyle.box.cornerRadius == darkStyle.box.cornerRadius
    check adaptiveStyle.minSize == darkStyle.minSize
    check adaptiveStyle.text.fontFace == darkStyle.text.fontFace

  test "different palettes produce different chrome with a stable cache":
    let
      palette = mochaPalette()
      adaptive = initMacOSAdaptiveTheme(palette)
    check initMacOSAdaptiveTheme(palette).generation == adaptive.generation
    check initMacOSAdaptiveTheme(palette).buttonFill().closeTo(adaptive.buttonFill())
    let other = initMacOSAdaptiveTheme(initContentPalette())
    check not other.windowBackground().closeTo(adaptive.windowBackground())

  test "adaptive theme follows the registered palette provider":
    registerAdaptivePaletteProvider proc(): ContentThemePalette =
      mochaPalette()
    defer:
      registerAdaptivePaletteProvider(nil)
    check initThemeByName("macos-adaptive").windowBackground().closeTo(
      color(0x1e / 255, 0x1e / 255, 0x2e / 255, 1)
    )
    check initThemeByName("adaptive").windowBackground().closeTo(
      color(0x1e / 255, 0x1e / 255, 0x2e / 255, 1)
    )
    registerAdaptivePaletteProvider proc(): ContentThemePalette =
      initContentPalette()
    check initThemeByName("macos-adaptive").windowBackground().closeTo(
      color(0, 0, 0, 1)
    )

  test "adaptive chrome layers over an applied theme without losing fonts":
    let
      palette = mochaPalette()
      adaptive = initMacOSAdaptiveTheme(palette)
    var builder = initThemeBuilder(adaptive)
    builder.setFontName(frUI, "Adaptive Test Font")
    let layered = builder.finish()
    check layered.windowBackground().closeTo(
      color(0x1e / 255, 0x1e / 255, 0x2e / 255, 1)
    )
    check layered.fontName(frUI) == "Adaptive Test Font"
    let refreshed = parseCssTheme(adaptiveThemeCss(initContentPalette()), layered)
    check refreshed.diagnostics.len == 0
    check not refreshed.theme.windowBackground().closeTo(
      color(0x1e / 255, 0x1e / 255, 0x2e / 255, 1)
    )
    check refreshed.theme.fontName(frUI) == "Adaptive Test Font"
