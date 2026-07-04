import ./themecore
import std/[os, strutils, tables]
import ../foundation/types

proc addRoleRule(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    fill: StyleValue,
    borderColor: StyleValue,
    textColor: StyleValue,
) =
  let selector = initStyleSelector(role, states)
  theme[selector, StyleFill] = fill
  theme[selector, StyleBorderColor] = borderColor
  theme[selector, StyleTextColor] = textColor

proc addChoiceRule(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    fill: StyleValue,
    borderColor: StyleValue,
    markColor: StyleValue,
    textColor: StyleValue,
) =
  let selector = initStyleSelector(role, states)
  theme[selector, StyleFill] = fill
  theme[selector, StyleBorderColor] = borderColor
  theme[selector, StyleMarkColor] = markColor
  theme[selector, StyleTextColor] = textColor

proc addLabelRule(
    theme: var Theme,
    className: string,
    fillValue: Fill,
    borderColor: Color,
    borderWidth: float32,
    cornerRadius: float32,
    textColor: Color,
    textInsets: EdgeInsets,
    minSize: Size,
) =
  let selector = initStyleSelector(srTextField, classes = @[className])
  theme[selector, StyleFill] = fillValue
  theme[selector, StyleBorderColor] = borderColor
  theme[selector, StyleBorderWidth] = borderWidth
  theme[selector, StyleCornerRadius] = cornerRadius
  theme[selector, StyleTextColor] = textColor
  theme[selector, StyleTextInsets] = textInsets
  theme[selector, StyleMinimumSize] = minSize
  theme[selector, StyleFocusRingWidth] = 0.0
  theme[selector, StyleFocusRingInset] = 0.0
  theme[selector, StyleBoxShadows] = newSeq[BoxShadow]()

func defaultButtonShadows(): seq[BoxShadow] =
  @[
    insetShadow(color(1.0, 1.0, 1.0, 0.30), x = 2.0, y = 1.0, blur = 5.0),
    insetShadow(color(0.0, 0.0, 0.0, 0.24), x = -1.0, y = -2.0, blur = 5.0),
  ]

func highlightedButtonShadows(): seq[BoxShadow] =
  @[
    insetShadow(color(1.0, 1.0, 1.0, 0.12), x = 2.0, y = 1.0, blur = 3.0),
    insetShadow(color(0.0, 0.0, 0.0, 0.38), x = -1.0, y = -2.0, blur = 9.0),
  ]

func aquaButtonFill(): Fill =
  linear(
    color(0.88, 0.98, 1.0, 0.60),
    color(0.24, 0.70, 1.0, 0.60),
    color(0.0, 0.36, 0.92, 0.60),
    fgaY,
    112'u8,
  )

func aquaButtonPressedFill(): Fill =
  linear(
    color(0.18, 0.58, 0.96, 0.66),
    color(0.0, 0.34, 0.86, 0.66),
    color(0.0, 0.17, 0.58, 0.66),
    fgaY,
    104'u8,
  )

func aquaAccentButtonFill(): Fill =
  linear(
    color(0.96, 1.0, 1.0, 0.60),
    color(0.34, 0.77, 1.0, 0.60),
    color(0.0, 0.42, 0.98, 0.60),
    fgaY,
    112'u8,
  )

func aquaAccentButtonPressedFill(): Fill =
  linear(
    color(0.12, 0.52, 0.96, 0.66),
    color(0.0, 0.28, 0.78, 0.66),
    color(0.0, 0.11, 0.46, 0.66),
    fgaY,
    104'u8,
  )

func aquaWindowBackgroundFill(): Fill =
  linear(
    color(0.97, 0.97, 0.96, 1.0),
    color(0.93, 0.93, 0.92, 1.0),
    color(0.88, 0.88, 0.87, 1.0),
    fgaY,
    104'u8,
  )

func aquaButtonDisabledFill(): Fill =
  linear(color(0.90, 0.91, 0.93, 0.56), color(0.76, 0.78, 0.82, 0.56), fgaY)

func aquaChoiceFill(): Fill =
  linear(color(1.0, 1.0, 0.99, 0.86), color(0.84, 0.85, 0.83, 0.86), fgaY)

func aquaChoiceHighlightedFill(): Fill =
  linear(color(1.0, 1.0, 1.0, 0.90), color(0.78, 0.90, 1.0, 0.90), fgaY)

func aquaChoiceSelectedFill(): Fill =
  linear(color(0.48, 0.91, 1.0, 0.90), color(0.0, 0.49, 0.93, 0.90), fgaDiagTLBR)

func aquaChoiceSelectedHighlightedFill(): Fill =
  linear(
    color(0.45, 0.80, 1.0, 0.92),
    color(0.0, 0.32, 0.86, 0.92),
    color(0.0, 0.18, 0.58, 0.92),
    fgaY,
    104'u8,
  )

func aquaTextFieldFill(): Fill =
  linear(color(1.0, 1.0, 1.0, 0.84), color(0.90, 0.96, 1.0, 0.84), fgaY)

func aquaComboItemHighlightFill(): Fill =
  linear(color(0.90, 0.96, 1.0, 0.88), color(0.72, 0.87, 1.0, 0.88), fgaY)

func aquaComboItemSelectedFill(): Fill =
  linear(
    color(0.45, 0.75, 1.0, 0.90),
    color(0.10, 0.45, 0.95, 0.90),
    color(0.02, 0.26, 0.76, 0.90),
    fgaY,
    104'u8,
  )

func aquaComboItemSelectedHighlightedFill(): Fill =
  linear(
    color(0.20, 0.57, 0.98, 0.92),
    color(0.03, 0.33, 0.82, 0.92),
    color(0.01, 0.18, 0.58, 0.92),
    fgaY,
    104'u8,
  )

func aquaButtonShadows(): seq[BoxShadow] =
  @[
    dropShadow(color(0.0, 0.14, 0.42, 0.32), y = 2.0, blur = 5.0),
    insetShadow(color(1.0, 1.0, 1.0, 0.86), y = 1.0, blur = 2.0),
    insetShadow(color(0.78, 0.96, 1.0, 0.34), y = 3.0, blur = 5.0),
    insetShadow(color(0.0, 0.05, 0.26, 0.24), y = -2.0, blur = 6.0),
  ]

func aquaPressedButtonShadows(): seq[BoxShadow] =
  @[
    dropShadow(color(0.0, 0.08, 0.24, 0.22), y = 1.0, blur = 3.0),
    insetShadow(color(0.0, 0.04, 0.24, 0.36), y = 2.0, blur = 6.0),
    insetShadow(color(1.0, 1.0, 1.0, 0.24), y = -1.0, blur = 3.0),
  ]

func aquaInsetControlShadows(): seq[BoxShadow] =
  @[
    insetShadow(color(0.0, 0.05, 0.18, 0.20), y = 1.0, blur = 3.0),
    insetShadow(color(1.0, 1.0, 1.0, 0.80), y = -1.0, blur = 2.0),
  ]

func aquaSwitchTrackShadows(enabled: bool): seq[BoxShadow] =
  @[
    insetShadow(
      color(0.0, 0.0, 0.0, if enabled: 0.14'f32 else: 0.05'f32), y = 1.0, blur = 2.0
    )
  ]

func aquaSwitchKnobShadows(enabled: bool): seq[BoxShadow] =
  @[
    dropShadow(
      color(0.0, 0.0, 0.0, if enabled: 0.22'f32 else: 0.08'f32), y = 1.0, blur = 3.0
    ),
    insetShadow(
      color(1.0, 1.0, 1.0, if enabled: 0.82'f32 else: 0.26'f32), y = 1.0, blur = 2.0
    ),
  ]

const TextStyleRoles = [
  srBox, srButton, srCheckBox, srRadioButton, srTextField, srTextView, srMonoTextView,
  srComboBox, srComboBoxItem, srTab, srTableHeaderCell, srRowItem, srCascadingRowItem,
]

proc initTheme*(): Theme =
  result.tokens = newStyleTokenStore()
  result.chromes = initTable[string, Chrome]()
  for role in TextStyleRoles:
    result[role, StyleFontName] = styleKeyword(defaultFontName())
    result[role, StyleFontSize] = defaultFontSize()
  result["accent"] = styleColor(color(0.0, 0.46, 0.98, 1.0))
  result["accent.pressed"] = styleColor(color(0.0, 0.22, 0.70, 1.0))
  result["disabled.fill"] = styleColor(color(0.70, 0.76, 0.84, 1.0))
  result["disabled.text.color"] = styleColor(color(0.88, 0.92, 0.97, 1.0))
  result["focus.ring.color"] = styleColor(color(0.28, 0.64, 1.0, 0.82))
  result["indicator.size"] = 18.0

  result["button.fill"] = aquaButtonFill()
  result["button.fill.highlighted"] = aquaButtonPressedFill()
  result["button.fill.disabled"] = aquaButtonDisabledFill()
  result["button.fill.accent"] = aquaAccentButtonFill()
  result["button.fill.accent.highlighted"] = aquaAccentButtonPressedFill()
  result["button.text.color"] = styleColor(color(0.08, 0.08, 0.07, 0.95))
  result["button.text.color.disabled"] = styleToken("disabled.text.color")
  result["button.border.color"] = styleColor(color(0.0, 0.18, 0.68, 0.92))
  result["button.border.color.highlighted"] = styleColor(color(0.0, 0.12, 0.52, 0.96))
  result["button.border.color.disabled"] = styleColor(color(0.52, 0.57, 0.64, 1.0))
  result["button.border.color.accent"] = styleColor(color(0.0, 0.14, 0.72, 1.0))
  result["button.border.color.accent.highlighted"] =
    styleColor(color(0.0, 0.08, 0.42, 1.0))
  result["button.focus.ring.color"] = styleColor(color(1.0, 1.0, 1.0, 0.90))
  result["button.shadows"] = aquaButtonShadows()
  result["button.shadows.highlighted"] = aquaPressedButtonShadows()
  result["button.shadows.disabled"] = newSeq[BoxShadow]()

  result["choice.indicator.fill"] = aquaChoiceFill()
  result["choice.indicator.fill.highlighted"] = aquaChoiceHighlightedFill()
  result["choice.indicator.fill.disabled"] = aquaButtonDisabledFill()
  result["choice.indicator.fill.selected"] = aquaChoiceSelectedFill()
  result["choice.indicator.fill.selected.highlighted"] =
    aquaChoiceSelectedHighlightedFill()
  result["choice.indicator.fill.selected.disabled"] = aquaButtonDisabledFill()
  result["choice.indicator.border.color"] = styleColor(color(0.42, 0.50, 0.62, 1.0))
  result["choice.indicator.border.color.selected"] =
    styleColor(color(0.0, 0.32, 0.75, 0.96))
  result["choice.indicator.border.color.highlighted"] =
    styleColor(color(0.16, 0.38, 0.72, 1.0))
  result["choice.indicator.border.color.disabled"] =
    styleColor(color(0.64, 0.68, 0.74, 1.0))
  result["choice.mark.color"] = styleColor(color(0.02, 0.15, 0.30, 0.96))
  result["choice.mark.color.disabled"] = styleToken("disabled.text.color")
  result["choice.text.color"] = styleColor(color(0.08, 0.09, 0.11, 1.0))
  result["choice.text.color.disabled"] = styleColor(color(0.48, 0.52, 0.58, 1.0))

  result["textField.fill"] = aquaTextFieldFill()
  result["textField.border.color"] = styleColor(color(0.48, 0.63, 0.84, 1.0))
  result["textField.text.color"] = styleColor(color(0.08, 0.09, 0.11, 1.0))
  result["textField.selection.color"] = styleColor(color(0.24, 0.56, 1.0, 0.34))
  result["monoText.fill"] = styleToken("textField.fill")
  result["monoText.border.color"] = styleToken("textField.border.color")
  result["monoText.text.color"] = styleToken("textField.text.color")
  result["monoText.cursor.color"] = styleColor(color(0.08, 0.45, 0.95, 0.45))
  result["comboBox.fill"] = styleToken("textField.fill")
  result["comboBox.border.color"] = styleToken("textField.border.color")
  result["comboBox.border.color.open"] = styleColor(color(0.0, 0.34, 0.86, 1.0))
  result["comboBox.text.color"] = styleToken("textField.text.color")
  result["comboBox.arrow.color"] = styleColor(color(0.0, 0.12, 0.34, 1.0))
  result["comboBox.arrow.fill"] = aquaAccentButtonFill()
  result["comboBox.item.fill"] = fill(color(1.0, 1.0, 1.0, 0.88))
  result["comboBox.item.fill.highlighted"] = aquaComboItemHighlightFill()
  result["comboBox.item.fill.selected"] = aquaComboItemSelectedFill()
  result["comboBox.item.fill.selected.highlighted"] =
    aquaComboItemSelectedHighlightedFill()
  result["comboBox.item.text.color"] = styleColor(color(0.08, 0.09, 0.11, 1.0))
  result["comboBox.item.text.color.selected"] = styleColor(color(1.0, 1.0, 1.0, 1.0))
  result["tableView.fill"] = styleToken("textField.fill")
  result["tableView.border.color"] = styleToken("textField.border.color")
  result["scrollView.fill"] = styleToken("tableView.fill")
  result["scrollView.border.color"] = styleToken("tableView.border.color")
  result["box.fill"] = styleColor(color(0.0, 0.0, 0.0, 0.0))
  result["box.border.color"] = styleColor(color(0.61, 0.65, 0.72, 1.0))
  result["box.text.color"] = styleColor(color(0.12, 0.15, 0.20, 1.0))
  result["scroller.track.fill"] = styleFill(color(0.84, 0.89, 0.96, 0.78))
  result["scroller.track.border.color"] = styleColor(color(0.57, 0.68, 0.84, 0.86))
  result["scroller.knob.fill"] = styleFill(color(0.34, 0.58, 0.86, 0.72))
  result["scroller.knob.border.color"] = styleColor(color(0.10, 0.28, 0.58, 0.58))
  result["splitView.divider.fill"] = styleFill(color(0.83, 0.89, 0.97, 0.86))
  result["splitView.divider.border.color"] = styleColor(color(0.52, 0.64, 0.82, 1.0))
  result["rowItem.fill"] = styleToken("comboBox.item.fill")
  result["rowItem.fill.highlighted"] = styleToken("comboBox.item.fill.highlighted")
  result["rowItem.fill.selected"] = styleToken("comboBox.item.fill.selected")
  result["rowItem.fill.selected.highlighted"] =
    styleToken("comboBox.item.fill.selected.highlighted")
  result["rowItem.fill.disabled"] = styleColor(color(0.80, 0.82, 0.86, 0.56))
  result["rowItem.text.color"] = styleToken("comboBox.item.text.color")
  result["rowItem.text.color.selected"] =
    styleToken("comboBox.item.text.color.selected")
  result["rowItem.text.color.disabled"] = styleColor(color(0.32, 0.35, 0.41, 1.0))
  result["rowItem.separator.color"] = styleColor(color(0.86, 0.88, 0.91, 1.0))
  result["tab.panel.fill"] = styleColor(color(0.88, 0.94, 1.0, 0.88))
  result["tab.panel.border.color"] = styleColor(color(0.56, 0.70, 0.88, 1.0))
  result["tab.fill"] = styleColor(color(0.84, 0.90, 0.98, 0.86))
  result["tab.fill.highlighted"] = styleColor(color(0.72, 0.80, 0.90, 0.88))
  result["tab.fill.selected"] = styleColor(color(0.72, 0.86, 1.0, 0.90))
  result["tab.fill.disabled"] = styleColor(color(0.78, 0.80, 0.84, 0.56))
  result["tab.highlight.fill"] = styleFill(color(1.0, 1.0, 1.0, 0.52))
  result["tab.highlight.fill.disabled"] = styleFill(color(1.0, 1.0, 1.0, 0.30))
  result["tab.text.color"] = styleColor(color(0.14, 0.15, 0.18, 1.0))
  result["tab.text.color.selected"] = styleColor(color(0.06, 0.10, 0.16, 1.0))
  result["tab.text.color.disabled"] = styleColor(color(0.48, 0.50, 0.54, 1.0))
  result["tab.border.color"] = styleColor(color(0.48, 0.52, 0.56, 1.0))
  result["tab.border.color.highlighted"] = styleColor(color(0.34, 0.48, 0.66, 1.0))
  result["tab.border.color.selected"] = styleColor(color(0.14, 0.40, 0.82, 1.0))
  result["tab.border.color.disabled"] = styleColor(color(0.65, 0.67, 0.70, 1.0))

  result[srView, StyleBackgroundColor] = color(0.93, 0.93, 0.92)
  result[srView, StyleBackgroundFill] = aquaWindowBackgroundFill()
  result[srView, StyleBackgroundPinstripeHighlightColor] = color(0.96, 0.96, 0.96, 1.0)
  result[srView, StyleBackgroundPinstripeColor] = color(0.62, 0.62, 0.62, 0.18)
  result[srView, StyleBackgroundPinstripePeriod] = 2.0
  result[srView, StyleBackgroundPinstripeHeight] = 2.0

  result.addRoleRule(
    srBox,
    {},
    styleToken("box.fill"),
    styleToken("box.border.color"),
    styleToken("box.text.color"),
  )
  result[srBox, StyleBorderWidth] = 1.0
  result[srBox, StyleCornerRadius] = 5.0
  result[srBox, StyleTextInsets] = insets(0.0, 8.0)
  result[srBox, StylePadding] = insets(14.0, 12.0)
  result[srBox, StyleTitleHeight] = 18.0
  result[srBox, StyleTitleGap] = 4.0
  result[srBox, StyleSeparatorThickness] = 1.0
  result[srBox, StyleMinimumSize] = initSize(0.0, 0.0)
  result[srBox, StyleFocusRingWidth] = 0.0
  result[srBox, StyleFocusRingInset] = 0.0
  result[srBox, StyleBoxShadows] = newSeq[BoxShadow]()

  result.addRoleRule(
    srButton,
    {},
    styleToken("button.fill"),
    styleToken("button.border.color"),
    styleToken("button.text.color"),
  )
  result.addRoleRule(
    srButton,
    {ssHovered},
    styleToken("button.fill.highlighted"),
    styleToken("button.border.color.highlighted"),
    styleToken("button.text.color"),
  )
  result.addRoleRule(
    srButton,
    {ssHighlighted},
    styleToken("button.fill.highlighted"),
    styleToken("button.border.color.highlighted"),
    styleToken("button.text.color"),
  )
  result.addRoleRule(
    srButton,
    {ssActive},
    styleToken("button.fill.highlighted"),
    styleToken("button.border.color.highlighted"),
    styleToken("button.text.color"),
  )
  result.addRoleRule(
    srButton,
    {ssDisabled},
    styleToken("button.fill.disabled"),
    styleToken("button.border.color.disabled"),
    styleToken("button.text.color.disabled"),
  )
  result.addRoleRule(
    srButton,
    {ssAccent},
    styleToken("button.fill.accent"),
    styleToken("button.border.color.accent"),
    styleToken("button.text.color"),
  )
  result.addRoleRule(
    srButton,
    {ssAccent, ssHovered},
    styleToken("button.fill.accent.highlighted"),
    styleToken("button.border.color.accent.highlighted"),
    styleToken("button.text.color"),
  )
  result.addRoleRule(
    srButton,
    {ssAccent, ssHighlighted},
    styleToken("button.fill.accent.highlighted"),
    styleToken("button.border.color.accent.highlighted"),
    styleToken("button.text.color"),
  )
  result.addRoleRule(
    srButton,
    {ssAccent, ssActive},
    styleToken("button.fill.accent.highlighted"),
    styleToken("button.border.color.accent.highlighted"),
    styleToken("button.text.color"),
  )
  result.addRoleRule(
    srButton,
    {ssAccent, ssDisabled},
    styleToken("button.fill.disabled"),
    styleToken("button.border.color.disabled"),
    styleToken("button.text.color.disabled"),
  )
  result[srButton, StyleBorderWidth] = 1.0
  result[srButton, StyleCornerRadius] = 14.0
  result[srButton, StyleTextInsets] = insets(0.0, 8.0)
  result[srButton, StyleTextHighlightColor] = color(1.0, 1.0, 1.0, 0.42)
  result[srButton, StyleTextShadowColor] = color(0.0, 0.0, 0.0, 0.20)
  result[srButton, StyleMinimumSize] = initSize(0.0, 32.0)
  result[srButton, StyleFocusRingWidth] = 3.0
  result[srButton, StyleFocusRingInset] = -2.0
  result[srButton, StyleFocusRingColor] = styleToken("button.focus.ring.color")
  result[srButton, StyleBoxShadows] = styleToken("button.shadows")
  result[srButton, StyleChrome] = styleKeyword(AquaChromeName)
  result[srButton, {ssHighlighted}, StyleBoxShadows] =
    styleToken("button.shadows.highlighted")
  result[srButton, {ssActive}, StyleBoxShadows] =
    styleToken("button.shadows.highlighted")
  result[srButton, {ssDisabled}, StyleBoxShadows] =
    styleToken("button.shadows.disabled")
  result[srButton, {ssDisabled}, StyleTextHighlightColor] = color(1.0, 1.0, 1.0, 0.16)
  result[srButton, {ssDisabled}, StyleTextShadowColor] = color(0.0, 0.0, 0.0, 0.08)
  result[srStepper, StyleMinimumSize] = initSize(52.0, 23.0)

  result[srSwitch, StyleFill] = fill(color(0.72, 0.78, 0.84, 0.82))
  result[srSwitch, StyleBorderColor] = color(0.38, 0.45, 0.53, 0.70)
  result[srSwitch, StyleBorderWidth] = 1.0
  result[srSwitch, StyleFocusRingWidth] = 3.0
  result[srSwitch, StyleFocusRingInset] = -3.0
  result[srSwitch, StyleFocusRingColor] = color(0.28, 0.62, 1.0, 0.80)
  result[srSwitch, StyleBoxShadows] = aquaSwitchTrackShadows(enabled = true)
  result[srSwitch, StyleKnobFill] = fill(color(0.96, 0.97, 0.99, 0.90))
  result[srSwitch, StyleKnobBorderColor] = color(0.32, 0.36, 0.44, 0.78)
  result[srSwitch, StyleKnobInset] = 1.7
  result[srSwitch, StyleKnobSizeFactor] = 2.0
  result[srSwitch, StyleKnobShadows] = aquaSwitchKnobShadows(enabled = true)
  result[srSwitch, StyleIndicatorSize] = styleToken("indicator.size")
  result[srSwitch, StyleWidthFactor] = 1.67
  result[srSwitch, StyleMinimumSize] = initSize(0.0, 0.0)
  result[srSwitch, StyleChrome] = styleKeyword(AquaChromeName)
  result[srSwitch, {ssSelected}, StyleFill] = fill(color(0.08, 0.54, 0.96, 0.88))
  result[srSwitch, {ssSelected}, StyleBorderColor] = color(0.02, 0.24, 0.62, 0.70)
  result[srSwitch, {ssHighlighted}, StyleKnobFill] = fill(color(0.91, 0.97, 1.0, 0.92))
  result[srSwitch, {ssDisabled}, StyleFill] = fill(color(0.72, 0.78, 0.84, 0.42))
  result[srSwitch, {ssDisabled}, StyleBorderColor] = color(0.38, 0.45, 0.53, 0.32)
  result[srSwitch, {ssDisabled}, StyleBoxShadows] =
    aquaSwitchTrackShadows(enabled = false)
  result[srSwitch, {ssDisabled}, StyleKnobFill] = fill(color(0.96, 0.97, 0.99, 0.68))
  result[srSwitch, {ssDisabled}, StyleKnobBorderColor] = color(0.32, 0.36, 0.44, 0.34)
  result[srSwitch, {ssDisabled}, StyleKnobShadows] =
    aquaSwitchKnobShadows(enabled = false)
  result[srSwitch, {ssSelected, ssDisabled}, StyleFill] =
    fill(color(0.08, 0.54, 0.96, 0.42))
  result[srSwitch, {ssSelected, ssDisabled}, StyleBorderColor] =
    color(0.02, 0.24, 0.62, 0.32)

  result[srSlider, StyleIndicatorSize] = 6.0
  result[srSlider, StyleKnobSize] = 18.0
  result[srSlider, StyleMinimumSize] = initSize(160.0, 24.0)
  result[srSlider, StyleFill] = fill(color(0.76, 0.84, 0.94, 0.82))
  result[srSlider, StyleHighlightFill] = aquaAccentButtonFill()
  result[srSlider, StyleBorderColor] = color(0.38, 0.52, 0.70, 0.78)
  result[srSlider, StyleFocusRingColor] = color(0.0, 0.24, 0.72, 0.70)
  result[srSlider, StyleKnobFill] = aquaTextFieldFill()
  result[srSlider, StyleKnobBorderColor] = color(0.46, 0.58, 0.74, 0.94)
  result[srSlider, StyleChrome] = styleKeyword(AquaChromeName)
  result[srProgressIndicator, StyleIndicatorSize] = 6.0
  result[srProgressIndicator, StyleKnobSize] = 18.0
  result[srProgressIndicator, StyleMinimumSize] = initSize(160.0, 24.0)
  result[srProgressIndicator, StyleFill] = fill(color(0.76, 0.84, 0.94, 0.82))
  result[srProgressIndicator, StyleHighlightFill] = aquaAccentButtonFill()
  result[srProgressIndicator, StyleBorderColor] = color(0.38, 0.52, 0.70, 0.78)
  result[srProgressIndicator, StyleFocusRingColor] = color(0.0, 0.24, 0.72, 0.70)
  result[srProgressIndicator, StyleKnobFill] = aquaTextFieldFill()
  result[srProgressIndicator, StyleKnobBorderColor] = color(0.46, 0.58, 0.74, 0.94)
  result[srProgressIndicator, StyleChrome] = styleKeyword(AquaChromeName)

  result.addRoleRule(
    srTab,
    {},
    styleToken("tab.fill"),
    styleToken("tab.border.color"),
    styleToken("tab.text.color"),
  )
  result.addRoleRule(
    srTab,
    {ssHighlighted},
    styleToken("tab.fill.highlighted"),
    styleToken("tab.border.color.highlighted"),
    styleToken("tab.text.color"),
  )
  result.addRoleRule(
    srTab,
    {ssSelected},
    styleToken("tab.fill.selected"),
    styleToken("tab.border.color.selected"),
    styleToken("tab.text.color.selected"),
  )
  result.addRoleRule(
    srTab,
    {ssDisabled},
    styleToken("tab.fill.disabled"),
    styleToken("tab.border.color.disabled"),
    styleToken("tab.text.color.disabled"),
  )
  result[srTab, StyleHighlightFill] = styleToken("tab.highlight.fill")
  result[srTab, {ssDisabled}, StyleHighlightFill] =
    styleToken("tab.highlight.fill.disabled")
  result[srTab, StyleBorderWidth] = 1.0
  result[srTab, StyleCornerRadius] = 4.0
  result[srTab, StyleTextInsets] = insets(1.0, 8.0)
  result[srTab, StylePadding] = insets(0.0, 12.0)
  result[srTab, StyleMinimumSize] = initSize(48.0, 24.0)
  result[srTab, StyleMaximumSize] = initSize(180.0, 0.0)
  result[srTab, StyleSegmentSize] = initSize(0.0, 20.0)
  result[srTab, StyleEdgeInset] = 8.0
  result[srTab, StyleItemGap] = 1.0
  result[srTab, StyleOverlap] = 12.0
  result[srTab, StyleChrome] = styleKeyword(AquaChromeName)
  result[srTabPanel, StyleFill] = styleToken("tab.panel.fill")
  result[srTabPanel, StyleBorderColor] = styleToken("tab.panel.border.color")
  result[srTabPanel, StyleBorderWidth] = 1.0
  result[srTabPanel, StyleCornerRadius] = 4.0
  result[srTabPanel, StyleChrome] = styleKeyword(AquaChromeName)

  for role in [srCheckBox, srRadioButton]:
    let
      radius = if role == srCheckBox: 3.0'f32 else: 8.0'f32
      selectedBorder =
        if role == srCheckBox:
          styleToken("choice.indicator.border.color.selected")
        else:
          styleToken("choice.indicator.border.color")
    result.addChoiceRule(
      role,
      {},
      styleToken("choice.indicator.fill"),
      styleToken("choice.indicator.border.color"),
      styleToken("choice.mark.color"),
      styleToken("choice.text.color"),
    )
    result.addChoiceRule(
      role,
      {ssHovered},
      styleToken("choice.indicator.fill.highlighted"),
      styleToken("choice.indicator.border.color.highlighted"),
      styleToken("choice.mark.color"),
      styleToken("choice.text.color"),
    )
    result.addChoiceRule(
      role,
      {ssHighlighted},
      styleToken("choice.indicator.fill.highlighted"),
      styleToken("choice.indicator.border.color.highlighted"),
      styleToken("choice.mark.color"),
      styleToken("choice.text.color"),
    )
    result.addChoiceRule(
      role,
      {ssSelected},
      styleToken("choice.indicator.fill.selected"),
      selectedBorder,
      styleToken("choice.mark.color"),
      styleToken("choice.text.color"),
    )
    result.addChoiceRule(
      role,
      {ssSelected, ssHovered},
      styleToken("choice.indicator.fill.selected.highlighted"),
      selectedBorder,
      styleToken("choice.mark.color"),
      styleToken("choice.text.color"),
    )
    result.addChoiceRule(
      role,
      {ssSelected, ssHighlighted},
      styleToken("choice.indicator.fill.selected.highlighted"),
      selectedBorder,
      styleToken("choice.mark.color"),
      styleToken("choice.text.color"),
    )
    result.addChoiceRule(
      role,
      {ssDisabled},
      styleToken("choice.indicator.fill.disabled"),
      styleToken("choice.indicator.border.color.disabled"),
      styleToken("choice.mark.color.disabled"),
      styleToken("choice.text.color.disabled"),
    )
    result.addChoiceRule(
      role,
      {ssSelected, ssDisabled},
      styleToken("choice.indicator.fill.selected.disabled"),
      styleToken("choice.indicator.border.color.disabled"),
      styleToken("choice.mark.color.disabled"),
      styleToken("choice.text.color.disabled"),
    )
    result[role, StyleIndicatorSize] = styleToken("indicator.size")
    result[role, StyleBorderWidth] = 1.0
    result[role, StyleCornerRadius] = radius
    result[role, StyleIndicatorSpacing] = 7.0
    result[role, StyleTextInsets] = insets(0.0, 2.0)
    result[role, StyleMinimumSize] = initSize(0.0, 20.0)
    result[role, StyleFocusRingWidth] = 3.0
    result[role, StyleFocusRingInset] = 2.0
    result[role, StyleFocusRingColor] = styleToken("focus.ring.color")
    result[role, StyleBoxShadows] = aquaInsetControlShadows()
    result[role, StyleChrome] = styleKeyword(AquaChromeName)

  result[srTextField, StyleFill] = styleToken("textField.fill")
  result[srTextField, StyleBorderColor] = styleToken("textField.border.color")
  result[srTextField, StyleBorderWidth] = 1.0
  result[srTextField, StyleCornerRadius] = 6.0
  result[srTextField, StyleTextInsets] = insets(0.0, 6.0)
  result[srTextField, StyleMinimumSize] = initSize(80.0, 24.0)
  result[srTextField, StyleSelectionColor] = styleToken("textField.selection.color")
  result[srTextField, StyleFocusRingWidth] = 3.0
  result[srTextField, StyleFocusRingInset] = -2.0
  result[srTextField, StyleFocusRingColor] = styleToken("focus.ring.color")
  result[srTextField, StyleBoxShadows] = aquaInsetControlShadows()

  result[srMonoTextView, StyleFill] = styleToken("monoText.fill")
  result[srMonoTextView, StyleBorderColor] = styleToken("monoText.border.color")
  result[srMonoTextView, StyleBorderWidth] = 1.0
  result[srMonoTextView, StyleCornerRadius] = 6.0
  result[srMonoTextView, StyleTextColor] = styleToken("monoText.text.color")
  result[srMonoTextView, StyleTextInsets] = insets(6.0)
  result[srMonoTextView, StyleCursorColor] = styleToken("monoText.cursor.color")
  result[srMonoTextView, StyleMinimumSize] = initSize(80.0, 24.0)
  result[srMonoTextView, StyleFocusRingWidth] = 3.0
  result[srMonoTextView, StyleFocusRingInset] = -2.0
  result[srMonoTextView, StyleFocusRingColor] = styleToken("focus.ring.color")
  result[srMonoTextView, StyleBoxShadows] = aquaInsetControlShadows()
  result[srMonoTextView, StyleChrome] = styleKeyword(AquaChromeName)

  result.addLabelRule(
    LabelStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(0.09, 0.12, 0.18, 1.0),
    insets(0.0),
    initSize(0.0, 18.0),
  )
  result.addLabelRule(
    LabelTitleStyleClass,
    linear(color(0.94, 0.98, 1.0, 0.86), color(0.84, 0.91, 0.98, 0.86), fgaY),
    color(0.62, 0.70, 0.84, 1.0),
    1.0,
    6.0,
    color(0.09, 0.14, 0.26, 1.0),
    insets(0.0, 12.0),
    initSize(0.0, 28.0),
  )
  result.addLabelRule(
    LabelHeadingStyleClass,
    linear(color(0.90, 0.95, 1.0, 0.86), color(0.78, 0.86, 0.96, 0.86), fgaY),
    color(0.74, 0.82, 0.93, 1.0),
    1.0,
    5.0,
    color(0.10, 0.18, 0.32, 1.0),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  result.addLabelRule(
    LabelStatusStyleClass,
    linear(color(0.94, 0.99, 0.95, 0.86), color(0.84, 0.94, 0.87, 0.86), fgaY),
    color(0.68, 0.82, 0.72, 1.0),
    1.0,
    6.0,
    color(0.09, 0.27, 0.18, 1.0),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  result.addLabelRule(
    LabelFormStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(0.10, 0.14, 0.22, 1.0),
    insets(0.0, 2.0),
    initSize(0.0, 18.0),
  )

  result.addRoleRule(
    srComboBox,
    {},
    styleToken("comboBox.fill"),
    styleToken("comboBox.border.color"),
    styleToken("comboBox.text.color"),
  )
  result.addRoleRule(
    srComboBox,
    {ssOpen},
    styleToken("comboBox.fill"),
    styleToken("comboBox.border.color.open"),
    styleToken("comboBox.text.color"),
  )
  result.addRoleRule(
    srComboBox,
    {ssDisabled},
    styleToken("textField.fill"),
    styleToken("textField.border.color"),
    styleToken("disabled.text.color"),
  )
  result[srComboBox, StyleBorderWidth] = 1.0
  result[srComboBox, StyleCornerRadius] = 6.0
  result[srComboBox, StyleTextInsets] = insets(0.0, 8.0)
  result[srComboBox, StyleFocusRingWidth] = 3.0
  result[srComboBox, StyleFocusRingInset] = -2.0
  result[srComboBox, StyleFocusRingColor] = styleToken("focus.ring.color")
  result[srComboBox, StyleIndicatorSize] = 24.0
  result[srComboBox, StyleMinimumSize] = initSize(90.0, 24.0)
  result[srComboBox, StyleIndicatorFill] = styleToken("comboBox.arrow.fill")
  result[srComboBox, StyleMarkColor] = styleToken("comboBox.arrow.color")
  result[srComboBox, StyleBoxShadows] = aquaInsetControlShadows()
  result[srComboBox, StyleChrome] = styleKeyword(AquaChromeName)

  result.addRoleRule(
    srComboBoxItem,
    {},
    styleToken("comboBox.item.fill"),
    styleColor(color(0.0, 0.0, 0.0, 0.0)),
    styleToken("comboBox.item.text.color"),
  )
  result.addRoleRule(
    srComboBoxItem,
    {ssHovered},
    styleToken("comboBox.item.fill.highlighted"),
    styleColor(color(0.0, 0.0, 0.0, 0.0)),
    styleToken("comboBox.item.text.color"),
  )
  result.addRoleRule(
    srComboBoxItem,
    {ssSelected},
    styleToken("comboBox.item.fill.selected"),
    styleColor(color(0.0, 0.0, 0.0, 0.0)),
    styleToken("comboBox.item.text.color.selected"),
  )
  result.addRoleRule(
    srComboBoxItem,
    {ssSelected, ssHovered},
    styleToken("comboBox.item.fill.selected.highlighted"),
    styleColor(color(0.0, 0.0, 0.0, 0.0)),
    styleToken("comboBox.item.text.color.selected"),
  )
  result[srComboBoxItem, StyleBorderWidth] = 0.0
  result[srComboBoxItem, StyleCornerRadius] = 0.0
  result[srComboBoxItem, StyleTextInsets] = insets(0.0, 6.0)
  result[srComboBoxItem, StyleMinimumSize] = initSize(0.0, 22.0)

  result[srTableView, StyleFill] = styleToken("tableView.fill")
  result[srTableView, StyleBorderColor] = styleToken("tableView.border.color")
  result[srTableView, StyleBorderWidth] = 1.0
  result[srTableView, StyleCornerRadius] = 6.0
  result[srTableView, StyleMinimumSize] = initSize(120.0, 24.0)
  result[srTableView, StyleRowHeight] = 22.0
  result[srTableView, StyleHeaderHeight] = 24.0
  result[srTableView, StyleColumnWidth] = 120.0
  result[srTableView, StyleColumnMinWidth] = 24.0
  result[srTableView, StyleColumnMaxWidth] = 10000.0
  result[srTableView, StyleResizeHandleWidth] = 5.0
  result[srTableView, StyleDragThreshold] = 3.0
  result[srTableView, StyleAutoscrollEdge] = 18.0
  result[srTableView, StyleFocusRingWidth] = 3.0
  result[srTableView, StyleFocusRingInset] = 2.0
  result[srTableView, StyleFocusRingColor] = styleToken("focus.ring.color")
  result[srTableView, StyleBoxShadows] = aquaInsetControlShadows()
  result[srTableView, StyleDropIndicatorFill] = fill(color(0.18, 0.42, 0.88, 0.95))
  for role in [srCascadingView, srCascadingColumn]:
    result[role, StyleFill] = styleToken("tableView.fill")
    result[role, StyleBorderColor] = styleToken("tableView.border.color")
    result[role, StyleBorderWidth] = 1.0
    result[role, StyleCornerRadius] = 6.0
    result[role, StyleMinimumSize] = initSize(120.0, 24.0)
    result[role, StyleRowHeight] = 22.0
    result[role, StyleHeaderHeight] = 24.0
    result[role, StyleColumnWidth] = 120.0
    result[role, StyleColumnMinWidth] = 24.0
    result[role, StyleColumnMaxWidth] = 10000.0
    result[role, StyleResizeHandleWidth] = 5.0
    result[role, StyleDragThreshold] = 3.0
    result[role, StyleAutoscrollEdge] = 18.0
    result[role, StyleFocusRingWidth] = 3.0
    result[role, StyleFocusRingInset] = 2.0
    result[role, StyleFocusRingColor] = styleToken("focus.ring.color")
    result[role, StyleBoxShadows] = aquaInsetControlShadows()
    result[role, StyleDropIndicatorFill] = fill(color(0.18, 0.42, 0.88, 0.95))

  result[srScrollView, StyleFill] = styleToken("scrollView.fill")
  result[srScrollView, StyleBorderColor] = styleToken("scrollView.border.color")
  result[srScrollView, StyleBorderWidth] = 1.0
  result[srScrollView, StyleCornerRadius] = 0.0

  result[srCascadingScrollView, StyleFill] = styleToken("tableView.fill")
  result[srCascadingScrollView, StyleBorderColor] = styleToken("tableView.border.color")
  result[srCascadingScrollView, StyleBorderWidth] = 0.0
  result[srCascadingScrollView, StyleCornerRadius] = 0.0

  result[srScroller, StyleFill] = styleToken("scroller.track.fill")
  result[srScroller, StyleBorderColor] = styleToken("scroller.track.border.color")
  result[srScroller, StyleKnobFill] = styleToken("scroller.knob.fill")
  result[srScroller, StyleKnobBorderColor] = styleToken("scroller.knob.border.color")
  result[srScroller, StyleBorderWidth] = 1.0
  result[srScroller, StyleCornerRadius] = 3.0

  result[srCascadingScroller, StyleFill] = styleToken("tableView.fill")
  result[srCascadingScroller, StyleBorderColor] =
    styleToken("scroller.track.border.color")
  result[srCascadingScroller, StyleKnobFill] = styleToken("scroller.knob.fill")
  result[srCascadingScroller, StyleKnobBorderColor] =
    styleToken("scroller.knob.border.color")
  result[srCascadingScroller, StyleBorderWidth] = 0.0
  result[srCascadingScroller, StyleCornerRadius] = 0.0

  result[srSplitView, StyleFill] = styleToken("splitView.divider.fill")
  result[srSplitView, StyleBorderColor] = styleToken("splitView.divider.border.color")
  result[srSplitView, StyleBorderWidth] = 1.0
  result[srSplitView, StyleCornerRadius] = 2.0
  result[srSplitView, StyleSeparatorThickness] = 6.0
  result[srSplitView, StyleFocusRingWidth] = 0.0
  result[srSplitView, StyleFocusRingInset] = 0.0
  result[srSplitView, StyleBoxShadows] = newSeq[BoxShadow]()

  result[srTableHeader, StyleFill] = fill(color(0.88, 0.90, 0.94, 0.84))
  result[srTableHeader, StyleBorderColor] = color(0.60, 0.64, 0.70, 1.0)
  result[srTableHeader, StyleInsertionIndicatorFill] =
    fill(color(0.16, 0.36, 0.84, 0.95))
  result[srTableHeaderCell, StyleFill] = fill(color(0.90, 0.92, 0.96, 0.86))
  result[srTableHeaderCell, {ssHovered}, StyleFill] =
    fill(color(0.84, 0.88, 0.95, 0.88))
  result[srTableHeaderCell, {ssPressed}, StyleFill] =
    fill(color(0.76, 0.82, 0.91, 0.90))
  result[srTableHeaderCell, StyleBorderColor] = color(0.62, 0.66, 0.72, 1.0)
  result[srTableHeaderCell, StyleTextColor] = color(0.14, 0.18, 0.25, 1.0)
  result[srTableHeaderCell, StyleMarkColor] = color(0.12, 0.20, 0.34, 0.95)

  result.addRoleRule(
    srRowItem,
    {},
    styleToken("rowItem.fill"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color"),
  )
  result.addRoleRule(
    srRowItem,
    {ssHovered},
    styleToken("rowItem.fill.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color"),
  )
  result.addRoleRule(
    srRowItem,
    {ssHighlighted},
    styleToken("rowItem.fill.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color"),
  )
  result.addRoleRule(
    srRowItem,
    {ssPressed},
    styleToken("rowItem.fill.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color"),
  )
  result.addRoleRule(
    srRowItem,
    {ssDisabled},
    styleToken("rowItem.fill.disabled"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color.disabled"),
  )
  result.addRoleRule(
    srRowItem,
    {ssSelected},
    styleToken("rowItem.fill.selected"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color.selected"),
  )
  result.addRoleRule(
    srRowItem,
    {ssSelected, ssHovered},
    styleToken("rowItem.fill.selected.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color.selected"),
  )
  result.addRoleRule(
    srRowItem,
    {ssSelected, ssHighlighted},
    styleToken("rowItem.fill.selected.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color.selected"),
  )
  result.addRoleRule(
    srRowItem,
    {ssSelected, ssPressed},
    styleToken("rowItem.fill.selected.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color.selected"),
  )
  result[srRowItem, StyleBorderWidth] = 0.0
  result[srRowItem, StyleCornerRadius] = 0.0
  result[srRowItem, StyleTextInsets] = insets(0.0, 6.0)
  result[srRowItem, StyleMinimumSize] = initSize(0.0, 22.0)
  result[srRowItem, StyleAlternatingFill] = fill(color(0.96, 0.97, 0.99, 1.0))
  result.addRoleRule(
    srCascadingRowItem,
    {},
    styleToken("rowItem.fill"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color"),
  )
  result.addRoleRule(
    srCascadingRowItem,
    {ssHovered},
    styleToken("rowItem.fill.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color"),
  )
  result.addRoleRule(
    srCascadingRowItem,
    {ssHighlighted},
    styleToken("rowItem.fill.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color"),
  )
  result.addRoleRule(
    srCascadingRowItem,
    {ssPressed},
    styleToken("rowItem.fill.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color"),
  )
  result.addRoleRule(
    srCascadingRowItem,
    {ssDisabled},
    styleToken("rowItem.fill.disabled"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color.disabled"),
  )
  result.addRoleRule(
    srCascadingRowItem,
    {ssSelected},
    styleToken("rowItem.fill.selected"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color.selected"),
  )
  result.addRoleRule(
    srCascadingRowItem,
    {ssSelected, ssHovered},
    styleToken("rowItem.fill.selected.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color.selected"),
  )
  result.addRoleRule(
    srCascadingRowItem,
    {ssSelected, ssHighlighted},
    styleToken("rowItem.fill.selected.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color.selected"),
  )
  result.addRoleRule(
    srCascadingRowItem,
    {ssSelected, ssPressed},
    styleToken("rowItem.fill.selected.highlighted"),
    styleToken("rowItem.separator.color"),
    styleToken("rowItem.text.color.selected"),
  )
  result[srCascadingRowItem, StyleBorderWidth] = 0.0
  result[srCascadingRowItem, StyleCornerRadius] = 0.0
  result[srCascadingRowItem, StyleTextInsets] = insets(0.0, 6.0)
  result[srCascadingRowItem, StyleMinimumSize] = initSize(0.0, 22.0)
  result[srCascadingRowItem, StyleAlternatingFill] = fill(color(0.96, 0.97, 0.99, 1.0))
  result.installThemeExtensions()

proc initBannerTheme*(): Theme =
  result = initTheme()
  result[srButton, StyleChrome] = styleKeyword(DefaultChromeName)
  result[srCheckBox, StyleChrome] = styleKeyword(DefaultChromeName)
  result[srRadioButton, StyleChrome] = styleKeyword(DefaultChromeName)
  result[srComboBox, StyleChrome] = styleKeyword(DefaultChromeName)
  result[srButton, StyleTextHighlightColor] = color(0.0, 0.0, 0.0, 0.0)
  result[srButton, StyleTextShadowColor] = color(0.0, 0.0, 0.0, 0.0)
  result[srTab, StyleChrome] = styleKeyword(DefaultChromeName)
  result[srTabPanel, StyleChrome] = styleKeyword(DefaultChromeName)

  result["accent"] = color(0.89, 0.38, 0.21, 1.0)
  result["accent.pressed"] = color(0.62, 0.24, 0.14, 1.0)
  result["disabled.fill"] = color(0.52, 0.50, 0.45, 1.0)
  result["disabled.text.color"] = color(0.94, 0.91, 0.86, 1.0)
  result["focus.ring.color"] = color(0.31, 0.58, 0.54, 0.60)
  result["rowItem.separator.color"] = color(0.74, 0.70, 0.63, 1.0)
  result["tab.panel.fill"] = color(1.0, 0.97, 0.94, 1.0)
  result["tab.panel.border.color"] = color(0.84, 0.80, 0.75, 1.0)
  result["tab.fill"] = color(0.86, 0.82, 0.75, 1.0)
  result["tab.fill.highlighted"] = color(0.78, 0.70, 0.62, 1.0)
  result["tab.fill.selected"] = styleToken("tab.panel.fill")
  result["tab.fill.disabled"] = color(0.82, 0.78, 0.72, 1.0)
  result["tab.highlight.fill"] = color(1.0, 0.97, 0.94, 0.0)
  result["tab.highlight.fill.disabled"] = color(1.0, 0.97, 0.94, 0.0)
  result["tab.text.color"] = color(0.11, 0.10, 0.10, 1.0)
  result["tab.text.color.selected"] = color(0.11, 0.10, 0.10, 1.0)
  result["tab.text.color.disabled"] = color(0.48, 0.45, 0.40, 1.0)
  result["tab.border.color"] = color(0.54, 0.49, 0.42, 1.0)
  result["tab.border.color.highlighted"] = color(0.42, 0.36, 0.30, 1.0)
  result["tab.border.color.selected"] = styleToken("tab.panel.border.color")
  result["tab.border.color.disabled"] = color(0.70, 0.65, 0.58, 1.0)

  result["button.fill"] = styleToken("accent")
  result["button.fill.highlighted"] = styleToken("accent.pressed")
  result["button.fill.disabled"] = styleToken("disabled.fill")
  result["button.fill.accent"] = styleToken("accent")
  result["button.fill.accent.highlighted"] = styleToken("accent.pressed")
  result["button.text.color"] = color(1.0, 0.97, 0.94, 1.0)
  result["button.border.color"] = color(0.18, 0.12, 0.08, 1.0)
  result["button.border.color.highlighted"] = color(0.12, 0.08, 0.05, 1.0)
  result["button.border.color.disabled"] = color(0.40, 0.37, 0.33, 1.0)
  result["button.border.color.accent"] = color(0.18, 0.12, 0.08, 1.0)
  result["button.border.color.accent.highlighted"] = color(0.12, 0.08, 0.05, 1.0)
  result["button.focus.ring.color"] = color(1.0, 0.97, 0.94, 0.90)
  result["button.shadows"] = defaultButtonShadows()
  result["button.shadows.highlighted"] = highlightedButtonShadows()

  result["choice.indicator.fill"] = color(1.0, 0.97, 0.94, 1.0)
  result["choice.indicator.fill.highlighted"] = color(0.98, 0.93, 0.84, 1.0)
  result["choice.indicator.fill.disabled"] = color(0.86, 0.82, 0.75, 1.0)
  result["choice.indicator.fill.selected"] = styleToken("accent")
  result["choice.indicator.fill.selected.highlighted"] = styleToken("accent.pressed")
  result["choice.indicator.fill.selected.disabled"] = styleToken("disabled.fill")
  result["choice.indicator.border.color"] = color(0.54, 0.49, 0.42, 1.0)
  result["choice.indicator.border.color.highlighted"] = color(0.26, 0.51, 0.47, 1.0)
  result["choice.indicator.border.color.disabled"] = color(0.70, 0.65, 0.58, 1.0)
  result["choice.mark.color"] = color(1.0, 0.97, 0.94, 1.0)
  result["choice.text.color"] = color(0.11, 0.10, 0.10, 1.0)
  result["choice.text.color.disabled"] = color(0.48, 0.45, 0.40, 1.0)

  result["textField.fill"] = color(1.0, 0.97, 0.94, 1.0)
  result["textField.border.color"] = color(0.84, 0.80, 0.75, 1.0)
  result["scrollView.fill"] = styleToken("tableView.fill")
  result["scrollView.border.color"] = color(0.74, 0.70, 0.63, 1.0)
  result["scroller.track.fill"] = color(0.86, 0.82, 0.75, 0.70)
  result["scroller.track.border.color"] = color(0.66, 0.61, 0.54, 0.80)
  result["scroller.knob.fill"] = color(0.54, 0.49, 0.42, 0.68)
  result["scroller.knob.border.color"] = color(0.40, 0.34, 0.28, 0.70)
  result["textField.text.color"] = color(0.11, 0.10, 0.10, 1.0)
  result["textField.selection.color"] = color(0.31, 0.58, 0.54, 0.32)

  result["comboBox.border.color.open"] = color(0.31, 0.58, 0.54, 1.0)
  result["comboBox.arrow.color"] = color(0.16, 0.15, 0.15, 1.0)
  result["comboBox.item.fill"] = color(1.0, 0.97, 0.94, 1.0)
  result["comboBox.item.fill.highlighted"] = color(0.99, 0.93, 0.84, 1.0)
  result["comboBox.item.fill.selected"] = color(0.26, 0.51, 0.47, 1.0)
  result["comboBox.item.fill.selected.highlighted"] = color(0.19, 0.38, 0.35, 1.0)
  result["comboBox.item.text.color"] = color(0.11, 0.10, 0.10, 1.0)
  result["comboBox.item.text.color.selected"] = color(1.0, 0.97, 0.94, 1.0)
  result[srTableView, StyleDropIndicatorFill] = fill(color(0.31, 0.58, 0.54, 0.95))
  result[srTableHeader, StyleFill] = fill(color(0.86, 0.82, 0.75, 1.0))
  result[srTableHeader, StyleBorderColor] = color(0.74, 0.70, 0.63, 1.0)
  result[srTableHeader, StyleInsertionIndicatorFill] =
    fill(color(0.31, 0.58, 0.54, 0.95))
  result[srTableHeaderCell, StyleFill] = fill(color(0.90, 0.86, 0.78, 1.0))
  result[srTableHeaderCell, {ssHovered}, StyleFill] = fill(color(0.98, 0.93, 0.84, 1.0))
  result[srTableHeaderCell, {ssPressed}, StyleFill] = fill(color(0.78, 0.70, 0.62, 1.0))
  result[srTableHeaderCell, StyleBorderColor] = color(0.74, 0.70, 0.63, 1.0)
  result[srTableHeaderCell, StyleTextColor] = color(0.11, 0.10, 0.10, 1.0)
  result[srTableHeaderCell, StyleMarkColor] = color(0.16, 0.15, 0.15, 1.0)
  result[srRowItem, StyleAlternatingFill] = fill(color(0.98, 0.95, 0.90, 1.0))

type ThemeFactory* = proc(): Theme

var
  themeFactories {.threadvar.}: Table[string, ThemeFactory]
  themeFactoriesInitialized {.threadvar.}: bool

proc normalizedThemeName(name: string): string =
  name.strip().toLowerAscii()

proc ensureThemeFactories() =
  if themeFactoriesInitialized:
    return
  themeFactories = initTable[string, ThemeFactory]()
  themeFactoriesInitialized = true

proc registerThemeFactory*(name: string, factory: ThemeFactory) =
  let key = name.normalizedThemeName()
  if key.len == 0:
    return
  ensureThemeFactories()
  themeFactories[key] = factory

proc initThemeByName*(name: string): Theme =
  let key = name.normalizedThemeName()
  if key.len == 0 or key in ["default", "aqua", "system"]:
    return initTheme()
  if key == "banner":
    return initBannerTheme()
  ensureThemeFactories()
  if key in themeFactories:
    return themeFactories[key]()
  initTheme()

const NimKitThemeEnv* = "NIMKIT_THEME"

proc themeNameFromEnv*(): string =
  if not envOverrideAllowed(NimKitThemeEnv):
    return ""
  getEnv(NimKitThemeEnv)

proc initThemeFromEnv*(): Theme =
  initThemeByName(themeNameFromEnv())

proc initAppearance*(theme: Theme): Appearance =
  Appearance(theme: theme.clone)

proc initAppearance*(): Appearance =
  initAppearance(initThemeFromEnv())
