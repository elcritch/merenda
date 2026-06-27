import ./defaulttheme
import ./themecore
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

func nebulaPanelFill(): Fill =
  linear(
    initColor(0.04, 0.10, 0.18, 0.52),
    initColor(0.10, 0.22, 0.34, 0.30),
    initColor(0.03, 0.04, 0.12, 0.46),
    fgaY,
    104'u8,
  )

func nebulaGlassFill(): Fill =
  linear(
    initColor(0.18, 0.46, 0.62, 0.42),
    initColor(0.08, 0.18, 0.32, 0.30),
    initColor(0.18, 0.05, 0.30, 0.26),
    fgaDiagTLBR,
    112'u8,
  )

func nebulaGlassHotFill(): Fill =
  linear(
    initColor(0.28, 0.86, 1.0, 0.56),
    initColor(0.12, 0.38, 0.72, 0.44),
    initColor(0.44, 0.10, 0.72, 0.32),
    fgaDiagTLBR,
    112'u8,
  )

func nebulaGlassPressedFill(): Fill =
  linear(
    initColor(0.10, 0.24, 0.44, 0.60),
    initColor(0.06, 0.10, 0.24, 0.52),
    initColor(0.34, 0.04, 0.45, 0.42),
    fgaY,
    120'u8,
  )

func nebulaFieldFill(): Fill =
  linear(
    initColor(0.02, 0.07, 0.14, 0.58),
    initColor(0.06, 0.18, 0.28, 0.34),
    initColor(0.02, 0.03, 0.08, 0.48),
    fgaY,
    96'u8,
  )

func nebulaSelectionFill(): Fill =
  linear(
    initColor(0.14, 0.92, 1.0, 0.58),
    initColor(0.06, 0.36, 0.90, 0.46),
    initColor(0.50, 0.08, 0.92, 0.34),
    fgaDiagTLBR,
    110'u8,
  )

func nebulaDisabledFill(): Fill =
  linear(initColor(0.08, 0.12, 0.18, 0.24), initColor(0.04, 0.05, 0.08, 0.20), fgaY)

func nebulaGlowShadows(): seq[BoxShadow] =
  @[
    dropShadow(initColor(0.0, 0.92, 1.0, 0.18), y = 1.0, blur = 8.0),
    insetShadow(initColor(0.62, 0.96, 1.0, 0.30), y = 1.0, blur = 4.0),
    insetShadow(initColor(0.82, 0.18, 1.0, 0.18), y = -2.0, blur = 7.0),
  ]

func nebulaPressedShadows(): seq[BoxShadow] =
  @[
    insetShadow(initColor(0.0, 0.0, 0.0, 0.38), y = 2.0, blur = 7.0),
    insetShadow(initColor(0.28, 0.92, 1.0, 0.18), y = -1.0, blur = 4.0),
  ]

func nebulaInsetShadows(): seq[BoxShadow] =
  @[
    insetShadow(initColor(0.0, 0.0, 0.0, 0.42), y = 1.0, blur = 5.0),
    insetShadow(initColor(0.24, 0.88, 1.0, 0.22), y = -1.0, blur = 4.0),
  ]

func nebulaKnobShadows(): seq[BoxShadow] =
  @[
    dropShadow(initColor(0.0, 0.95, 1.0, 0.24), y = 1.0, blur = 7.0),
    insetShadow(initColor(0.80, 1.0, 1.0, 0.42), y = 1.0, blur = 3.0),
  ]

proc installNebulaTokens(theme: var Theme) =
  theme[srView, StyleBackgroundColor] = initColor(0.04, 0.06, 0.12)

  theme["accent"] = initColor(0.10, 0.92, 1.0, 0.92)
  theme["accent.pressed"] = initColor(0.78, 0.18, 1.0, 0.82)
  theme["disabled.fill"] = nebulaDisabledFill()
  theme["disabled.text.color"] = initColor(0.44, 0.58, 0.70, 0.66)
  theme["focus.ring.color"] = initColor(0.18, 0.92, 1.0, 0.88)
  theme["indicator.size"] = 18.0

  theme["button.fill"] = nebulaGlassFill()
  theme["button.fill.highlighted"] = nebulaGlassHotFill()
  theme["button.fill.disabled"] = nebulaDisabledFill()
  theme["button.fill.accent"] = nebulaGlassHotFill()
  theme["button.fill.accent.highlighted"] = nebulaGlassPressedFill()
  theme["button.text.color"] = initColor(0.82, 0.98, 1.0, 0.96)
  theme["button.text.color.disabled"] = styleToken("disabled.text.color")
  theme["button.border.color"] = initColor(0.20, 0.92, 1.0, 0.62)
  theme["button.border.color.highlighted"] = initColor(0.62, 0.98, 1.0, 0.88)
  theme["button.border.color.disabled"] = initColor(0.22, 0.34, 0.44, 0.42)
  theme["button.border.color.accent"] = initColor(0.66, 0.20, 1.0, 0.78)
  theme["button.border.color.accent.highlighted"] = initColor(0.96, 0.36, 1.0, 0.88)
  theme["button.focus.ring.color"] = initColor(0.24, 0.96, 1.0, 0.86)
  theme["button.shadows"] = nebulaGlowShadows()
  theme["button.shadows.highlighted"] = nebulaPressedShadows()
  theme["button.shadows.disabled"] = newSeq[BoxShadow]()

  theme["choice.indicator.fill"] = nebulaFieldFill()
  theme["choice.indicator.fill.highlighted"] = nebulaGlassFill()
  theme["choice.indicator.fill.disabled"] = nebulaDisabledFill()
  theme["choice.indicator.fill.selected"] = nebulaSelectionFill()
  theme["choice.indicator.fill.selected.highlighted"] = nebulaGlassHotFill()
  theme["choice.indicator.fill.selected.disabled"] = nebulaDisabledFill()
  theme["choice.indicator.border.color"] = initColor(0.20, 0.92, 1.0, 0.56)
  theme["choice.indicator.border.color.selected"] = initColor(0.58, 0.96, 1.0, 0.94)
  theme["choice.indicator.border.color.highlighted"] = initColor(0.70, 0.98, 1.0, 0.82)
  theme["choice.indicator.border.color.disabled"] = initColor(0.22, 0.34, 0.44, 0.36)
  theme["choice.mark.color"] = initColor(0.01, 0.07, 0.14, 1.0)
  theme["choice.mark.color.disabled"] = styleToken("disabled.text.color")
  theme["choice.text.color"] = initColor(0.78, 0.92, 1.0, 0.94)
  theme["choice.text.color.disabled"] = styleToken("disabled.text.color")

  theme["textField.fill"] = nebulaFieldFill()
  theme["textField.border.color"] = initColor(0.18, 0.86, 1.0, 0.54)
  theme["textField.text.color"] = initColor(0.84, 0.98, 1.0, 0.96)
  theme["textField.selection.color"] = initColor(0.20, 0.88, 1.0, 0.34)
  theme["comboBox.fill"] = styleToken("textField.fill")
  theme["comboBox.border.color"] = styleToken("textField.border.color")
  theme["comboBox.border.color.open"] = initColor(0.78, 0.24, 1.0, 0.86)
  theme["comboBox.text.color"] = styleToken("textField.text.color")
  theme["comboBox.arrow.color"] = initColor(0.42, 0.96, 1.0, 0.96)
  theme["comboBox.item.fill"] = fill(initColor(0.02, 0.06, 0.13, 0.86))
  theme["comboBox.item.fill.highlighted"] = nebulaGlassFill()
  theme["comboBox.item.fill.selected"] = nebulaSelectionFill()
  theme["comboBox.item.fill.selected.highlighted"] = nebulaGlassHotFill()
  theme["comboBox.item.text.color"] = initColor(0.78, 0.92, 1.0, 0.94)
  theme["comboBox.item.text.color.selected"] = initColor(0.94, 1.0, 1.0, 1.0)

  theme["tableView.fill"] = nebulaPanelFill()
  theme["tableView.border.color"] = initColor(0.14, 0.76, 1.0, 0.46)
  theme["rowItem.fill"] = fill(initColor(0.02, 0.06, 0.13, 0.10))
  theme["rowItem.fill.highlighted"] = fill(initColor(0.12, 0.46, 0.72, 0.26))
  theme["rowItem.fill.selected"] = nebulaSelectionFill()
  theme["rowItem.fill.selected.highlighted"] = nebulaGlassHotFill()
  theme["rowItem.fill.disabled"] = fill(initColor(0.08, 0.10, 0.14, 0.18))
  theme["rowItem.text.color"] = initColor(0.80, 0.94, 1.0, 0.94)
  theme["rowItem.text.color.selected"] = initColor(0.98, 1.0, 1.0, 1.0)
  theme["rowItem.text.color.disabled"] = styleToken("disabled.text.color")
  theme["rowItem.separator.color"] = initColor(0.18, 0.78, 1.0, 0.18)

  theme["tab.panel.fill"] = nebulaPanelFill()
  theme["tab.panel.border.color"] = initColor(0.20, 0.80, 1.0, 0.44)
  theme["tab.fill"] = fill(initColor(0.05, 0.14, 0.24, 0.42))
  theme["tab.fill.highlighted"] = nebulaGlassFill()
  theme["tab.fill.selected"] = nebulaGlassHotFill()
  theme["tab.fill.disabled"] = fill(initColor(0.08, 0.10, 0.16, 0.24))
  theme["tab.highlight.fill"] = styleFill(initColor(0.46, 1.0, 1.0, 0.30))
  theme["tab.highlight.fill.disabled"] = styleFill(initColor(0.38, 0.48, 0.56, 0.16))
  theme["tab.text.color"] = initColor(0.72, 0.90, 1.0, 0.90)
  theme["tab.text.color.selected"] = initColor(0.98, 1.0, 1.0, 1.0)
  theme["tab.text.color.disabled"] = styleToken("disabled.text.color")
  theme["tab.border.color"] = initColor(0.18, 0.74, 1.0, 0.48)
  theme["tab.border.color.highlighted"] = initColor(0.42, 0.94, 1.0, 0.76)
  theme["tab.border.color.selected"] = initColor(0.78, 0.24, 1.0, 0.74)
  theme["tab.border.color.disabled"] = initColor(0.22, 0.34, 0.44, 0.32)

proc installNebulaControlStyles(theme: var Theme) =
  theme[srButton, StyleCornerRadius] = 9.0
  theme[srButton, StyleTextHighlightColor] = initColor(0.64, 1.0, 1.0, 0.28)
  theme[srButton, StyleTextShadowColor] = initColor(0.0, 0.0, 0.0, 0.46)
  theme[srButton, StyleFocusRingColor] = styleToken("button.focus.ring.color")
  theme[srButton, StyleBoxShadows] = styleToken("button.shadows")
  theme[srButton, {ssHighlighted}, StyleBoxShadows] =
    styleToken("button.shadows.highlighted")
  theme[srButton, {ssActive}, StyleBoxShadows] =
    styleToken("button.shadows.highlighted")
  theme[srButton, {ssDisabled}, StyleBoxShadows] = styleToken("button.shadows.disabled")
  theme[srButton, StyleChrome] = styleKeyword(AquaChromeName)

  theme[srSwitch, StyleFill] = nebulaFieldFill()
  theme[srSwitch, StyleBorderColor] = initColor(0.16, 0.86, 1.0, 0.54)
  theme[srSwitch, StyleFocusRingColor] = styleToken("focus.ring.color")
  theme[srSwitch, StyleBoxShadows] = nebulaInsetShadows()
  theme[srSwitch, StyleKnobFill] = nebulaGlassFill()
  theme[srSwitch, StyleKnobBorderColor] = initColor(0.58, 0.96, 1.0, 0.82)
  theme[srSwitch, StyleKnobShadows] = nebulaKnobShadows()
  theme[srSwitch, {ssSelected}, StyleFill] = nebulaSelectionFill()
  theme[srSwitch, {ssSelected}, StyleBorderColor] = initColor(0.80, 0.24, 1.0, 0.80)
  theme[srSwitch, {ssHighlighted}, StyleKnobFill] = nebulaGlassHotFill()
  theme[srSwitch, {ssDisabled}, StyleFill] = nebulaDisabledFill()
  theme[srSwitch, {ssDisabled}, StyleBorderColor] = initColor(0.22, 0.34, 0.44, 0.34)
  theme[srSwitch, {ssDisabled}, StyleBoxShadows] = newSeq[BoxShadow]()
  theme[srSwitch, {ssDisabled}, StyleKnobFill] = nebulaDisabledFill()
  theme[srSwitch, {ssDisabled}, StyleKnobBorderColor] =
    initColor(0.22, 0.34, 0.44, 0.38)
  theme[srSwitch, {ssDisabled}, StyleKnobShadows] = newSeq[BoxShadow]()
  theme[srSwitch, {ssSelected, ssDisabled}, StyleFill] = nebulaDisabledFill()
  theme[srSwitch, {ssSelected, ssDisabled}, StyleBorderColor] =
    initColor(0.22, 0.34, 0.44, 0.38)

  for role in [srCheckBox, srRadioButton]:
    theme[role, StyleFocusRingColor] = styleToken("focus.ring.color")
    theme[role, StyleBoxShadows] = nebulaInsetShadows()
    theme[role, StyleChrome] = styleKeyword(AquaChromeName)

  theme[srTextField, StyleBoxShadows] = nebulaInsetShadows()
  theme[srComboBox, StyleBoxShadows] = nebulaInsetShadows()
  theme[srTableView, StyleBoxShadows] = nebulaInsetShadows()
  theme[srTableView, StyleDropIndicatorFill] = nebulaSelectionFill()
  theme[srTableView, StyleFocusRingColor] = styleToken("focus.ring.color")

proc installNebulaLabels(theme: var Theme) =
  theme.addLabelRule(
    LabelStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(0.78, 0.92, 1.0, 0.92),
    insets(0.0),
    initSize(0.0, 18.0),
  )
  theme.addLabelRule(
    LabelTitleStyleClass,
    linear(initColor(0.12, 0.36, 0.58, 0.42), initColor(0.04, 0.10, 0.22, 0.22), fgaY),
    initColor(0.28, 0.88, 1.0, 0.44),
    1.0,
    8.0,
    initColor(0.84, 0.98, 1.0, 0.96),
    insets(0.0, 12.0),
    initSize(0.0, 28.0),
  )
  theme.addLabelRule(
    LabelHeadingStyleClass,
    fill(initColor(0.02, 0.08, 0.16, 0.22)),
    initColor(0.18, 0.78, 1.0, 0.28),
    1.0,
    6.0,
    initColor(0.76, 0.96, 1.0, 0.96),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelStatusStyleClass,
    fill(initColor(0.02, 0.18, 0.20, 0.24)),
    initColor(0.28, 0.98, 0.82, 0.34),
    1.0,
    6.0,
    initColor(0.74, 1.0, 0.92, 0.94),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelFormStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(0.58, 0.82, 0.94, 0.86),
    insets(0.0, 2.0),
    initSize(0.0, 18.0),
  )

proc installNebulaTables(theme: var Theme) =
  theme[srTableHeader, StyleFill] = fill(initColor(0.04, 0.14, 0.24, 0.66))
  theme[srTableHeader, StyleBorderColor] = initColor(0.16, 0.80, 1.0, 0.38)
  theme[srTableHeader, StyleInsertionIndicatorFill] = nebulaSelectionFill()
  theme[srTableHeaderCell, StyleFill] = fill(initColor(0.07, 0.18, 0.30, 0.46))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = nebulaGlassFill()
  theme[srTableHeaderCell, {ssPressed}, StyleFill] = nebulaGlassPressedFill()
  theme[srTableHeaderCell, StyleBorderColor] = initColor(0.16, 0.72, 1.0, 0.34)
  theme[srTableHeaderCell, StyleTextColor] = initColor(0.78, 0.94, 1.0, 0.94)
  theme[srTableHeaderCell, StyleMarkColor] = initColor(0.66, 0.98, 1.0, 0.96)
  theme[srRowItem, StyleAlternatingFill] = fill(initColor(0.10, 0.30, 0.42, 0.10))

proc initNebulaTheme*(): Theme =
  result = initTheme()
  result.installNebulaTokens()
  result.installNebulaControlStyles()
  result.installNebulaLabels()
  result.installNebulaTables()

registerThemeFactory("nebula", initNebulaTheme)
registerThemeFactory("nebula-glass", initNebulaTheme)
