## macOS-styled chrome that follows a shared content palette.
##
## The adaptive theme keeps the macOS Dark structure - metrics, borders,
## shadows, and control shapes - and derives every chrome color from a
## `ContentThemePalette` such as Catppuccin Mocha. Surfaces mix the palette
## background with its foreground, borders tint the foreground with low
## alpha, and the accent comes from the palette's function color.

import std/[strutils]

import ../contentthemepalettes
import ./[defaulttheme, macostheme, themecore]
import ./private/csscompiler

type
  ChromeRgb* = tuple[r, g, b: float32]

  AdaptivePaletteProvider* = proc(): ContentThemePalette {.closure.}

  AdaptiveThemeCache = object
    palette: ContentThemePalette
    theme: Theme
    baseGeneration: ThemeGeneration

var
  adaptiveCache {.threadvar.}: AdaptiveThemeCache
  adaptivePaletteProvider {.threadvar.}: AdaptivePaletteProvider

func channels(color: ContentThemeColor): ChromeRgb =
  (color.red.float32, color.green.float32, color.blue.float32)

func rgbaText(color: ChromeRgb, alpha = 1.0'f32): string =
  "rgba(" & $color.r.int & ", " & $color.g.int & ", " & $color.b.int & ", " &
    formatFloat(alpha, ffDecimal, 3) & ")"

func mix(base, other: ChromeRgb, ratio: float32): ChromeRgb =
  (
    base.r + (other.r - base.r) * ratio,
    base.g + (other.g - base.g) * ratio,
    base.b + (other.b - base.b) * ratio,
  )

func darken(color: ChromeRgb, ratio: float32): ChromeRgb =
  mix(color, (0.0'f32, 0.0'f32, 0.0'f32), ratio)

func lighten(color: ChromeRgb, ratio: float32): ChromeRgb =
  mix(color, (255.0'f32, 255.0'f32, 255.0'f32), ratio)

func luminance(color: ChromeRgb): float32 =
  (0.2126'f32 * color.r + 0.7152'f32 * color.g + 0.0722'f32 * color.b) / 255.0'f32

func contrast(first, second: ChromeRgb): float32 =
  abs(first.luminance() - second.luminance())

func keepContrast(candidate, background, fallback: ChromeRgb): ChromeRgb =
  if candidate.contrast(background) >= 0.18'f32: candidate else: fallback

type AdaptiveChrome = object ## Chrome colors derived from one content palette.
  base, ink: ChromeRgb
  accent, accentPressed, onAccent: ChromeRgb
  positive: ChromeRgb

func initAdaptiveChrome(palette: ContentThemePalette): AdaptiveChrome =
  result.base = palette.background.channels()
  result.ink = palette.foreground.channels()
  result.accent = palette.functionName.channels().keepContrast(
      result.base,
      palette.keyword.channels().keepContrast(result.base, palette.cyan.channels()),
    )
  result.accentPressed = result.accent.darken(0.18'f32)
  result.onAccent =
    if result.accent.luminance() < 0.55'f32:
      (255.0'f32, 255.0'f32, 255.0'f32)
    else:
      (17.0'f32, 17.0'f32, 19.0'f32)
  result.positive =
    palette.stringLiteral.channels().keepContrast(result.base, result.accent)

func tone(chrome: AdaptiveChrome, ratio: float32): ChromeRgb =
  mix(chrome.base, chrome.ink, ratio)

template decl(name, value: string) =
  result.add "  " & name & ": " & value & ";\n"

template rule(selector: string, body: untyped) =
  result.add selector & " {\n"
  body
  result.add "}\n\n"

proc adaptiveThemeCss*(palette: ContentThemePalette): string =
  ## A stylesheet that recolors the macOS Dark chrome from `palette`.
  let chrome = palette.initAdaptiveChrome()
  result = "/* Adaptive chrome derived from a content palette. */\n\n"

  result.add ":root {\n"
  decl "--accent", chrome.accent.rgbaText()
  decl "--accent-pressed", chrome.accentPressed.rgbaText()
  decl "--box-border-color", chrome.ink.rgbaText(0.14)
  decl "--button-border-color", chrome.ink.rgbaText(0.14)
  decl "--button-border-color-accent", chrome.accent.rgbaText(0.82)
  decl "--button-border-color-accent-highlighted", chrome.accentPressed.rgbaText(0.92)
  decl "--button-border-color-accent-hovered", chrome.accent.rgbaText(0.88)
  decl "--button-border-color-disabled", chrome.ink.rgbaText(0.06)
  decl "--button-border-color-highlighted", chrome.ink.rgbaText(0.10)
  decl "--button-border-color-hovered", chrome.ink.rgbaText(0.19)
  decl "--button-fill", chrome.tone(0.13).rgbaText(0.98)
  decl "--button-fill-accent-hovered", chrome.accent.lighten(0.10).rgbaText()
  decl "--button-fill-highlighted", chrome.tone(0.09).rgbaText()
  decl "--button-fill-hovered", chrome.tone(0.17).rgbaText()
  decl "--button-text-color", chrome.ink.rgbaText()
  decl "--choice-indicator-border-color", chrome.ink.rgbaText(0.22)
  decl "--choice-indicator-border-color-disabled", chrome.ink.rgbaText(0.08)
  decl "--choice-indicator-border-color-highlighted", chrome.ink.rgbaText(0.30)
  decl "--choice-indicator-border-color-selected", chrome.accent.rgbaText(0.86)
  decl "--choice-indicator-fill", chrome.tone(0.06).rgbaText()
  decl "--choice-indicator-fill-highlighted", chrome.tone(0.09).rgbaText()
  decl "--choice-indicator-fill-selected-disabled", chrome.accentPressed.rgbaText(0.55)
  decl "--choice-mark-color", chrome.onAccent.rgbaText()
  decl "--choice-mark-color-disabled", chrome.ink.rgbaText(0.48)
  decl "--choice-text-color", chrome.ink.rgbaText()
  decl "--combo-box-arrow-color", chrome.tone(0.60).rgbaText()
  decl "--combo-box-arrow-fill", chrome.ink.rgbaText(0.05)
  decl "--combo-box-item-fill", chrome.tone(0.20).rgbaText(0.99)
  decl "--combo-box-item-fill-highlighted", chrome.tone(0.17).rgbaText()
  decl "--combo-box-item-text-color-selected", chrome.onAccent.rgbaText()
  decl "--disabled-fill", chrome.tone(0.07).rgbaText()
  decl "--disabled-text-color", chrome.tone(0.42).rgbaText()
  decl "--document-tab-fill-pressed", chrome.ink.rgbaText(0.08)
  decl "--focus-ring-color", chrome.accent.rgbaText(0.58)
  decl "--row-item-fill-disabled", chrome.ink.rgbaText(0.02)
  decl "--row-item-fill-highlighted", chrome.ink.rgbaText(0.065)
  decl "--row-item-separator-color", chrome.ink.rgbaText(0.08)
  decl "--row-item-text-color-selected", chrome.onAccent.rgbaText()
  decl "--scroller-knob-border-color", chrome.ink.rgbaText(0.10)
  decl "--scroller-knob-fill", chrome.ink.rgbaText(0.45)
  decl "--split-view-divider-border-color", chrome.ink.rgbaText(0.20)
  decl "--split-view-divider-fill", chrome.ink.rgbaText(0.08)
  decl "--split-view-divider-mark-color", chrome.ink.rgbaText(0.60)
  decl "--tab-border-color-highlighted", chrome.ink.rgbaText(0.10)
  decl "--tab-border-color-selected", chrome.ink.rgbaText(0.16)
  decl "--tab-fill-disabled", chrome.ink.rgbaText(0.02)
  decl "--tab-fill-highlighted", chrome.ink.rgbaText(0.07)
  decl "--tab-fill-selected", chrome.tone(0.13).rgbaText(0.98)
  decl "--tab-panel-border-color", chrome.ink.rgbaText(0.12)
  decl "--tab-panel-fill", chrome.tone(0.06).rgbaText(0.96)
  decl "--tab-text-color", chrome.tone(0.60).rgbaText()
  decl "--tab-text-color-selected", chrome.ink.rgbaText()
  decl "--table-view-border-color", chrome.ink.rgbaText(0.14)
  decl "--table-view-column-hover-fill", chrome.ink.rgbaText(0.045)
  decl "--table-view-column-selection-fill", chrome.accent.rgbaText(0.16)
  decl "--table-view-fill", chrome.tone(0.02).rgbaText(0.98)
  decl "--text-field-border-color", chrome.ink.rgbaText(0.18)
  decl "--text-field-fill", chrome.tone(0.045).rgbaText(0.98)
  decl "--text-field-selection-color", chrome.accent.rgbaText(0.38)
  decl "--text-field-text-color", chrome.ink.rgbaText()
  result.add "}\n\n"

  rule "table-header-cell":
    decl "border-color", chrome.ink.rgbaText(0.10)
    decl "-nimkit-mark-color", chrome.tone(0.60).rgbaText()
    decl "color", chrome.tone(0.70).rgbaText()

  rule "row-item":
    decl "-nimkit-alternating-fill", chrome.ink.rgbaText(0.024)

  rule "view":
    decl "-nimkit-window-background-color", chrome.base.rgbaText(0.97)
    decl "-nimkit-window-background", chrome.base.rgbaText()

  rule "stepper":
    decl "border-color", chrome.ink.rgbaText(0.14)
    decl "background", chrome.tone(0.13).rgbaText()
    decl "color", chrome.ink.rgbaText()

  rule "stepper:highlighted":
    decl "background", chrome.tone(0.17).rgbaText()

  rule "stepper:disabled":
    decl "color", chrome.tone(0.42).rgbaText()

  rule "switch":
    decl "border-color", chrome.ink.rgbaText(0.10)
    decl "background", chrome.ink.rgbaText(0.28)
    decl "-nimkit-knob-border-color", chrome.ink.rgbaText(0.12)
    decl "-nimkit-knob-fill", chrome.ink.rgbaText(0.94)

  rule "switch:highlighted":
    decl "-nimkit-knob-fill", chrome.ink.rgbaText(0.94)

  rule "switch:selected":
    decl "border-color", chrome.positive.darken(0.25).rgbaText()
    decl "background", chrome.positive.rgbaText()

  rule "switch:disabled":
    decl "border-color", chrome.ink.rgbaText(0.08)
    decl "background", chrome.ink.rgbaText(0.10)
    decl "-nimkit-knob-border-color", chrome.ink.rgbaText(0.08)
    decl "-nimkit-knob-fill", chrome.ink.rgbaText(0.60)

  rule "switch:disabled:selected":
    decl "border-color", chrome.accent.rgbaText(0.35)
    decl "background", chrome.accent.rgbaText(0.35)

  rule "slider,\nprogress-indicator":
    decl "border-color", chrome.ink.rgbaText(0.08)
    decl "background", chrome.ink.rgbaText(0.25)
    decl "-nimkit-highlight-fill", "var(--accent)"
    decl "-nimkit-knob-border-color", chrome.ink.rgbaText(0.12)
    decl "-nimkit-knob-fill", chrome.ink.rgbaText(0.94)

  rule "table-header":
    decl "border-color", chrome.ink.rgbaText(0.10)
    decl "background", chrome.tone(0.06).rgbaText(0.98)
    decl "-nimkit-insertion-indicator-fill", chrome.accent.rgbaText(0.95)

  rule "table-header-cell:hover":
    decl "background", chrome.ink.rgbaText(0.05)

  rule "table-header-cell:pressed":
    decl "background", chrome.ink.rgbaText(0.09)

  rule "table-view":
    decl "-nimkit-drop-indicator-fill", chrome.accent.rgbaText(0.95)

  rule "cascading-view,\ncascading-column":
    decl "-nimkit-drop-indicator-fill", chrome.accent.rgbaText(0.95)

  rule "button:active:accent":
    decl "color", chrome.onAccent.rgbaText()

  rule "button.toolbar-button:selected":
    decl "color", chrome.onAccent.rgbaText()

  rule "text-field.label":
    decl "color", chrome.ink.rgbaText(0.92)

  rule "text-field.label-title":
    decl "color", chrome.ink.rgbaText()

  rule "text-field.label-heading":
    decl "color", chrome.tone(0.62).rgbaText()

  rule "text-field.label-status":
    decl "color", chrome.tone(0.70).rgbaText()

  rule "text-field.label-form":
    decl "color", chrome.tone(0.70).rgbaText()

  rule "text-field.label.icon-label":
    decl "color", chrome.ink.rgbaText(0.92)
    decl "-nimkit-mark-color", "var(--accent)"

proc initMacOSAdaptiveTheme*(palette: ContentThemePalette): Theme =
  ## The macOS Dark structure recolored from `palette`.
  let base = initMacOSDarkTheme()
  if adaptiveCache.theme.isInitialized and adaptiveCache.palette == palette and
      adaptiveCache.baseGeneration == base.generation:
    return adaptiveCache.theme
  let compiled = compileCssTheme(adaptiveThemeCss(palette), base)
  if compiled.diagnostics.len > 0:
    raise
      newException(ValueError, "Invalid adaptive theme CSS: " & $compiled.diagnostics)
  result = compiled.theme
  adaptiveCache =
    AdaptiveThemeCache(palette: palette, theme: result, baseGeneration: base.generation)

proc adaptiveContentPalette*(): ContentThemePalette =
  ## The palette the adaptive theme follows; the shared default until registered.
  if not adaptivePaletteProvider.isNil:
    adaptivePaletteProvider()
  else:
    initContentPalette()

proc registerAdaptivePaletteProvider*(provider: AdaptivePaletteProvider) =
  ## Supply the live palette for `initMacOSAdaptiveTheme` without arguments.
  adaptivePaletteProvider = provider

proc initMacOSAdaptiveTheme*(): Theme =
  initMacOSAdaptiveTheme(adaptiveContentPalette())

registerThemeFactory("macos-adaptive", initMacOSAdaptiveTheme)
registerThemeFactory("adaptive", initMacOSAdaptiveTheme)
registerThemeFactory("adaptive-macos", initMacOSAdaptiveTheme)
