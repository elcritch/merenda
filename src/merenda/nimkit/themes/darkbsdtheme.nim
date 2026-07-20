import ./[defaulttheme, macostheme, themecore]
import ../foundation/types

func rubyButtonFill(): Fill =
  linear(
    color(0.34, 0.003, 0.020, 1.0),
    color(0.78, 0.008, 0.036, 1.0),
    color(0.40, 0.002, 0.018, 1.0),
    fgaY,
    142'u8,
  )

func rubyButtonHoverFill(): Fill =
  linear(
    color(0.42, 0.006, 0.026, 1.0),
    color(0.88, 0.016, 0.052, 1.0),
    color(0.49, 0.004, 0.024, 1.0),
    fgaY,
    142'u8,
  )

func rubyButtonPressedFill(): Fill =
  linear(
    color(0.22, 0.001, 0.012, 1.0),
    color(0.54, 0.004, 0.024, 1.0),
    color(0.28, 0.001, 0.012, 1.0),
    fgaY,
    136'u8,
  )

func rubyButtonDisabledFill(): Fill =
  linear(
    color(0.24, 0.07, 0.08, 0.78),
    color(0.40, 0.10, 0.12, 0.78),
    color(0.27, 0.06, 0.07, 0.78),
    fgaY,
    142'u8,
  )

func rubyAccentButtonFill(): Fill =
  linear(
    color(0.40, 0.004, 0.024, 1.0),
    color(0.84, 0.010, 0.044, 1.0),
    color(0.46, 0.003, 0.022, 1.0),
    fgaY,
    142'u8,
  )

func rubyAccentButtonHoverFill(): Fill =
  linear(
    color(0.47, 0.008, 0.030, 1.0),
    color(0.94, 0.022, 0.064, 1.0),
    color(0.54, 0.005, 0.028, 1.0),
    fgaY,
    142'u8,
  )

func rubyAccentButtonPressedFill(): Fill =
  linear(
    color(0.26, 0.001, 0.014, 1.0),
    color(0.60, 0.005, 0.028, 1.0),
    color(0.32, 0.001, 0.014, 1.0),
    fgaY,
    136'u8,
  )

func rubyButtonShadows(): seq[BoxShadow] =
  @[
    dropShadow(color(0.96, 0.18, 0.28, 0.20), blur = 3.2, spread = 0.7),
    dropShadow(color(0.0, 0.0, 0.0, 0.58), y = 2.0, blur = 5.5),
    insetShadow(color(0.12, 0.0, 0.012, 0.52), y = -1.0, blur = 2.8),
  ]

func rubyButtonPressedShadows(): seq[BoxShadow] =
  @[
    insetShadow(color(0.20, 0.0, 0.03, 0.62), y = 1.0, blur = 4.0),
    insetShadow(color(1.0, 0.38, 0.44, 0.07), y = -1.0, blur = 2.0),
  ]

func graphiteControlShadows(): seq[BoxShadow] =
  @[dropShadow(color(0.0, 0.0, 0.0, 0.38), y = 1.0, blur = 3.0)]

proc installDarkBSDTokens(theme: var Theme) =
  theme["accent"] = color(0.58, 0.022, 0.052, 1.0)
  theme["accent.pressed"] = color(0.36, 0.005, 0.020, 1.0)
  theme["focus.ring.color"] = color(0.70, 0.06, 0.24, 0.64)
  theme["textField.selection.color"] = color(0.34, 0.18, 0.23, 0.92)

  theme["button.fill"] = rubyButtonFill()
  theme["button.fill.hovered"] = rubyButtonHoverFill()
  theme["button.fill.highlighted"] = rubyButtonPressedFill()
  theme["button.fill.disabled"] = rubyButtonDisabledFill()
  theme["button.fill.accent"] = rubyAccentButtonFill()
  theme["button.fill.accent.hovered"] = rubyAccentButtonHoverFill()
  theme["button.fill.accent.highlighted"] = rubyAccentButtonPressedFill()
  theme["button.text.color"] = color(1.0, 0.97, 0.98, 1.0)
  theme["button.border.color"] = color(0.35, 0.0, 0.038, 0.96)
  theme["button.border.color.hovered"] = color(0.52, 0.008, 0.062, 1.0)
  theme["button.border.color.highlighted"] = color(0.24, 0.0, 0.025, 1.0)
  theme["button.border.color.disabled"] = color(0.28, 0.04, 0.07, 0.72)
  theme["button.border.color.accent"] = color(0.43, 0.0, 0.046, 1.0)
  theme["button.border.color.accent.hovered"] = color(0.60, 0.008, 0.072, 1.0)
  theme["button.border.color.accent.highlighted"] = color(0.28, 0.0, 0.030, 1.0)
  theme["button.shadows"] = rubyButtonShadows()
  theme["button.shadows.highlighted"] = rubyButtonPressedShadows()
  theme["button.shadows.disabled"] = newSeq[BoxShadow]()

  theme["choice.indicator.border.color.selected"] = color(0.68, 0.07, 0.14, 0.90)
  theme["choice.indicator.fill.selected.highlighted"] = color(0.72, 0.040, 0.080, 1.0)
  theme["comboBox.item.fill.highlighted"] = color(0.31, 0.20, 0.23, 1.0)

  # Keep combo boxes on the original macOS dark surface instead of following
  # the button tokens that they normally alias.
  theme["comboBox.fill"] = color(0.25, 0.25, 0.27, 0.98)
  theme["comboBox.border.color"] = color(1.0, 1.0, 1.0, 0.14)

proc installDarkBSDButtonStyle(theme: var Theme) =
  theme[srButton, StyleChrome] = styleKeyword(RubyAquaChromeName)
  theme[srButton, StyleCornerRadius] = 10.0
  theme[srButton, StyleBorderWidth] = 1.0
  theme[srButton, StyleMinimumSize] = initSize(0.0, 32.0)
  theme[srButton, StyleTextInsets] = insets(0.0, 12.0)
  theme[srButton, StyleTextHighlightColor] = color(1.0, 0.90, 0.92, 0.34)
  theme[srButton, StyleTextShadowColor] = color(0.16, 0.0, 0.025, 0.66)

proc installDarkBSDControlStyles(theme: var Theme) =
  theme[srSwitch, {ssSelected}, StyleFill] = styleToken("accent")
  theme[srSwitch, {ssSelected}, StyleBorderColor] = styleToken("accent.pressed")
  theme[srSlider, StyleKnobFill] = fill(color(0.25, 0.25, 0.27, 1.0))
  theme[srSlider, StyleKnobBorderColor] = color(1.0, 1.0, 1.0, 0.14)
  theme[srSlider, StyleKnobShadows] = graphiteControlShadows()
  theme[srSlider, StyleKnobValueTint] = 0.0
  theme[srSlider, StyleMaximumHighlightFill] = fill(color(0.78, 0.040, 0.095, 1.0))

proc initDarkBSDTheme*(): Theme =
  result = initMacOSDarkTheme()
  result.installDarkBSDTokens()
  result.installDarkBSDButtonStyle()
  result.installDarkBSDControlStyles()

registerThemeFactory("darkbsd", initDarkBSDTheme)
registerThemeFactory("dark-bsd", initDarkBSDTheme)
registerThemeFactory("ruby-bsd", initDarkBSDTheme)
