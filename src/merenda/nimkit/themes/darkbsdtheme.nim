import ./[defaulttheme, macostheme, themecore]
import ../foundation/types

func rubyButtonFill(): Fill =
  fill(color(0.56, 0.018, 0.052, 0.98))

func rubyButtonHoverFill(): Fill =
  fill(color(0.66, 0.030, 0.074, 1.0))

func rubyButtonPressedFill(): Fill =
  fill(color(0.36, 0.005, 0.022, 1.0))

func rubyButtonDisabledFill(): Fill =
  fill(color(0.29, 0.07, 0.09, 0.82))

func rubyAccentButtonFill(): Fill =
  fill(color(0.63, 0.022, 0.060, 1.0))

func rubyAccentButtonHoverFill(): Fill =
  fill(color(0.74, 0.040, 0.088, 1.0))

func rubyAccentButtonPressedFill(): Fill =
  fill(color(0.42, 0.006, 0.026, 1.0))

func rubyButtonShadows(): seq[BoxShadow] =
  @[
    dropShadow(color(0.0, 0.0, 0.0, 0.52), y = 1.5, blur = 4.0),
    insetShadow(color(1.0, 0.42, 0.48, 0.10), y = 1.0, blur = 2.0),
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
  theme["comboBox.item.fill.highlighted"] = color(0.31, 0.20, 0.23, 1.0)

  # Keep combo boxes on the original macOS dark surface instead of following
  # the button tokens that they normally alias.
  theme["comboBox.fill"] = color(0.25, 0.25, 0.27, 0.98)
  theme["comboBox.border.color"] = color(1.0, 1.0, 1.0, 0.14)

proc installDarkBSDButtonStyle(theme: var Theme) =
  theme[srButton, StyleChrome] = styleKeyword(RubyAquaChromeName)
  theme[srButton, StyleCornerRadius] = 5.0
  theme[srButton, StyleBorderWidth] = 0.8
  theme[srButton, StyleMinimumSize] = initSize(0.0, 30.0)
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
