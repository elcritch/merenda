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

func peachyPanelFill(): Fill =
  linear(
    color(0.22, 0.23, 0.29, 0.82),
    color(0.28, 0.23, 0.31, 0.74),
    color(0.18, 0.19, 0.25, 0.82),
    fgaY,
    104'u8,
  )

func peachyGlassFill(): Fill =
  linear(
    color(0.33, 0.28, 0.36, 0.56),
    color(0.25, 0.25, 0.32, 0.46),
    color(0.38, 0.19, 0.33, 0.38),
    fgaDiagTLBR,
    112'u8,
  )

func peachyGlassHotFill(): Fill =
  linear(
    color(0.68, 0.31, 0.50, 0.68),
    color(0.44, 0.27, 0.44, 0.54),
    color(0.94, 0.53, 0.35, 0.40),
    fgaDiagTLBR,
    112'u8,
  )

func peachyGlassPressedFill(): Fill =
  linear(
    color(0.24, 0.21, 0.28, 0.76),
    color(0.20, 0.18, 0.25, 0.68),
    color(0.58, 0.24, 0.42, 0.52),
    fgaY,
    120'u8,
  )

func peachyFieldFill(): Fill =
  linear(
    color(0.18, 0.19, 0.25, 0.76),
    color(0.24, 0.21, 0.29, 0.60),
    color(0.15, 0.16, 0.22, 0.70),
    fgaY,
    96'u8,
  )

func peachySelectionFill(): Fill =
  linear(
    color(0.72, 0.28, 0.46, 0.82),
    color(0.58, 0.24, 0.42, 0.74),
    color(0.94, 0.52, 0.34, 0.58),
    fgaDiagTLBR,
    110'u8,
  )

func peachyDisabledFill(): Fill =
  linear(color(0.18, 0.18, 0.23, 0.30), color(0.11, 0.12, 0.16, 0.24), fgaY)

func peachyGlowShadows(): seq[BoxShadow] =
  @[
    dropShadow(color(0.95, 0.35, 0.52, 0.10), y = 1.0, blur = 9.0),
    insetShadow(color(1.0, 0.74, 0.52, 0.18), y = 1.0, blur = 4.0),
    insetShadow(color(0.82, 0.24, 0.50, 0.11), y = -2.0, blur = 8.0),
  ]

func peachyPressedShadows(): seq[BoxShadow] =
  @[
    insetShadow(color(0.0, 0.0, 0.0, 0.30), y = 2.0, blur = 7.0),
    insetShadow(color(1.0, 0.56, 0.36, 0.12), y = -1.0, blur = 4.0),
  ]

func peachyInsetShadows(): seq[BoxShadow] =
  @[
    insetShadow(color(0.0, 0.0, 0.0, 0.34), y = 1.0, blur = 5.0),
    insetShadow(color(1.0, 0.64, 0.46, 0.15), y = -1.0, blur = 4.0),
  ]

func peachyKnobShadows(): seq[BoxShadow] =
  @[
    dropShadow(color(1.0, 0.34, 0.52, 0.14), y = 1.0, blur = 7.0),
    insetShadow(color(1.0, 0.80, 0.60, 0.24), y = 1.0, blur = 3.0),
  ]

proc installPeachyTokens(theme: var Theme) =
  theme["accent"] = color(0.10, 0.92, 1.0, 0.92)
  theme["accent.pressed"] = color(0.78, 0.18, 1.0, 0.82)
  theme["disabled.fill"] = peachyDisabledFill()
  theme["disabled.text.color"] = color(0.44, 0.58, 0.70, 0.66)
  theme["focus.ring.color"] = color(0.18, 0.92, 1.0, 0.88)
  theme["indicator.size"] = 18.0

  theme["button.fill"] = peachyGlassFill()
  theme["button.fill.highlighted"] = peachyGlassHotFill()
  theme["button.fill.disabled"] = peachyDisabledFill()
  theme["button.fill.accent"] = peachyGlassHotFill()
  theme["button.fill.accent.highlighted"] = peachyGlassPressedFill()
  theme["button.text.color"] = color(0.82, 0.98, 1.0, 0.96)
  theme["button.text.color.disabled"] = styleToken("disabled.text.color")
  theme["button.border.color"] = color(0.20, 0.92, 1.0, 0.62)
  theme["button.border.color.highlighted"] = color(0.62, 0.98, 1.0, 0.88)
  theme["button.border.color.disabled"] = color(0.22, 0.34, 0.44, 0.42)
  theme["button.border.color.accent"] = color(0.66, 0.20, 1.0, 0.78)
  theme["button.border.color.accent.highlighted"] = color(0.96, 0.36, 1.0, 0.88)
  theme["button.focus.ring.color"] = color(0.24, 0.96, 1.0, 0.86)
  theme["button.shadows"] = peachyGlowShadows()
  theme["button.shadows.highlighted"] = peachyPressedShadows()
  theme["button.shadows.disabled"] = newSeq[BoxShadow]()

  theme["choice.indicator.fill"] = peachyFieldFill()
  theme["choice.indicator.fill.highlighted"] = peachyGlassFill()
  theme["choice.indicator.fill.disabled"] = peachyDisabledFill()
  theme["choice.indicator.fill.selected"] = peachySelectionFill()
  theme["choice.indicator.fill.selected.highlighted"] = peachyGlassHotFill()
  theme["choice.indicator.fill.selected.disabled"] = peachyDisabledFill()
  theme["choice.indicator.border.color"] = color(0.20, 0.92, 1.0, 0.56)
  theme["choice.indicator.border.color.selected"] = color(0.58, 0.96, 1.0, 0.94)
  theme["choice.indicator.border.color.highlighted"] = color(0.70, 0.98, 1.0, 0.82)
  theme["choice.indicator.border.color.disabled"] = color(0.22, 0.34, 0.44, 0.36)
  theme["choice.mark.color"] = color(0.01, 0.07, 0.14, 1.0)
  theme["choice.mark.color.disabled"] = styleToken("disabled.text.color")
  theme["choice.text.color"] = color(0.78, 0.92, 1.0, 0.94)
  theme["choice.text.color.disabled"] = styleToken("disabled.text.color")

  theme["textField.fill"] = peachyFieldFill()
  theme["textField.border.color"] = color(0.18, 0.86, 1.0, 0.54)
  theme["textField.text.color"] = color(0.84, 0.98, 1.0, 0.96)
  theme["textField.selection.color"] = color(0.20, 0.88, 1.0, 0.34)
  theme["comboBox.fill"] = styleToken("textField.fill")
  theme["comboBox.border.color"] = styleToken("textField.border.color")
  theme["comboBox.border.color.open"] = color(0.78, 0.24, 1.0, 0.86)
  theme["comboBox.text.color"] = styleToken("textField.text.color")
  theme["comboBox.arrow.color"] = color(0.42, 0.96, 1.0, 0.96)
  theme["comboBox.item.fill"] = fill(color(0.02, 0.06, 0.13, 0.86))
  theme["comboBox.item.fill.highlighted"] = peachyGlassFill()
  theme["comboBox.item.fill.selected"] = peachySelectionFill()
  theme["comboBox.item.fill.selected.highlighted"] = peachyGlassHotFill()
  theme["comboBox.item.text.color"] = color(0.78, 0.92, 1.0, 0.94)
  theme["comboBox.item.text.color.selected"] = color(0.94, 1.0, 1.0, 1.0)

  theme["tableView.fill"] = peachyPanelFill()
  theme["tableView.border.color"] = color(0.14, 0.76, 1.0, 0.46)
  theme["rowItem.fill"] = fill(color(0.02, 0.06, 0.13, 0.10))
  theme["rowItem.fill.highlighted"] = fill(color(0.12, 0.46, 0.72, 0.26))
  theme["rowItem.fill.selected"] = peachySelectionFill()
  theme["rowItem.fill.selected.highlighted"] = peachyGlassHotFill()
  theme["rowItem.fill.disabled"] = fill(color(0.08, 0.10, 0.14, 0.18))
  theme["rowItem.text.color"] = color(0.80, 0.94, 1.0, 0.94)
  theme["rowItem.text.color.selected"] = color(0.98, 1.0, 1.0, 1.0)
  theme["rowItem.text.color.disabled"] = styleToken("disabled.text.color")
  theme["rowItem.separator.color"] = color(0.18, 0.78, 1.0, 0.18)

  theme["tab.panel.fill"] = peachyPanelFill()
  theme["tab.panel.border.color"] = color(0.20, 0.80, 1.0, 0.44)
  theme["tab.fill"] = fill(color(0.05, 0.14, 0.24, 0.42))
  theme["tab.fill.highlighted"] = peachyGlassFill()
  theme["tab.fill.selected"] = peachyGlassHotFill()
  theme["tab.fill.disabled"] = fill(color(0.08, 0.10, 0.16, 0.24))
  theme["tab.highlight.fill"] = styleFill(color(0.46, 1.0, 1.0, 0.30))
  theme["tab.highlight.fill.disabled"] = styleFill(color(0.38, 0.48, 0.56, 0.16))
  theme["tab.text.color"] = color(0.72, 0.90, 1.0, 0.90)
  theme["tab.text.color.selected"] = color(0.98, 1.0, 1.0, 1.0)
  theme["tab.text.color.disabled"] = styleToken("disabled.text.color")
  theme["tab.border.color"] = color(0.18, 0.74, 1.0, 0.48)
  theme["tab.border.color.highlighted"] = color(0.42, 0.94, 1.0, 0.76)
  theme["tab.border.color.selected"] = color(0.78, 0.24, 1.0, 0.74)
  theme["tab.border.color.disabled"] = color(0.22, 0.34, 0.44, 0.32)

proc installPeachyControlStyles(theme: var Theme) =
  theme[srButton, StyleCornerRadius] = 9.0
  theme[srButton, StyleTextHighlightColor] = color(0.64, 1.0, 1.0, 0.28)
  theme[srButton, StyleTextShadowColor] = color(0.0, 0.0, 0.0, 0.46)
  theme[srButton, StyleFocusRingColor] = styleToken("button.focus.ring.color")
  theme[srButton, StyleBoxShadows] = styleToken("button.shadows")
  theme[srButton, {ssHighlighted}, StyleBoxShadows] =
    styleToken("button.shadows.highlighted")
  theme[srButton, {ssActive}, StyleBoxShadows] =
    styleToken("button.shadows.highlighted")
  theme[srButton, {ssDisabled}, StyleBoxShadows] = styleToken("button.shadows.disabled")
  theme[srButton, StyleChrome] = styleKeyword(FlatTransparentChromeName)

  theme[srSwitch, StyleFill] = peachyFieldFill()
  theme[srSwitch, StyleBorderColor] = color(0.16, 0.86, 1.0, 0.54)
  theme[srSwitch, StyleFocusRingColor] = styleToken("focus.ring.color")
  theme[srSwitch, StyleBoxShadows] = peachyInsetShadows()
  theme[srSwitch, StyleKnobFill] = peachyGlassFill()
  theme[srSwitch, StyleKnobBorderColor] = color(0.58, 0.96, 1.0, 0.82)
  theme[srSwitch, StyleKnobShadows] = peachyKnobShadows()
  theme[srSwitch, {ssSelected}, StyleFill] = peachySelectionFill()
  theme[srSwitch, {ssSelected}, StyleBorderColor] = color(0.80, 0.24, 1.0, 0.80)
  theme[srSwitch, {ssHighlighted}, StyleKnobFill] = peachyGlassHotFill()
  theme[srSwitch, {ssDisabled}, StyleFill] = peachyDisabledFill()
  theme[srSwitch, {ssDisabled}, StyleBorderColor] = color(0.22, 0.34, 0.44, 0.34)
  theme[srSwitch, {ssDisabled}, StyleBoxShadows] = newSeq[BoxShadow]()
  theme[srSwitch, {ssDisabled}, StyleKnobFill] = peachyDisabledFill()
  theme[srSwitch, {ssDisabled}, StyleKnobBorderColor] = color(0.22, 0.34, 0.44, 0.38)
  theme[srSwitch, {ssDisabled}, StyleKnobShadows] = newSeq[BoxShadow]()
  theme[srSwitch, {ssSelected, ssDisabled}, StyleFill] = peachyDisabledFill()
  theme[srSwitch, {ssSelected, ssDisabled}, StyleBorderColor] =
    color(0.22, 0.34, 0.44, 0.38)

  for role in [srCheckBox, srRadioButton]:
    theme[role, StyleFocusRingColor] = styleToken("focus.ring.color")
    theme[role, StyleBoxShadows] = peachyInsetShadows()
    theme[role, StyleChrome] = styleKeyword(FlatTransparentChromeName)

  theme[srTextField, StyleBoxShadows] = peachyInsetShadows()
  theme[srComboBox, StyleBoxShadows] = peachyInsetShadows()
  theme[srTableView, StyleBoxShadows] = peachyInsetShadows()
  theme[srTableView, StyleDropIndicatorFill] = peachySelectionFill()
  theme[srTableView, StyleFocusRingColor] = styleToken("focus.ring.color")

proc installPeachyLabels(theme: var Theme) =
  theme.addLabelRule(
    LabelStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(0.78, 0.92, 1.0, 0.92),
    insets(0.0),
    initSize(0.0, 18.0),
  )
  theme.addLabelRule(
    LabelTitleStyleClass,
    linear(color(0.12, 0.36, 0.58, 0.42), color(0.04, 0.10, 0.22, 0.22), fgaY),
    color(0.28, 0.88, 1.0, 0.44),
    1.0,
    8.0,
    color(0.84, 0.98, 1.0, 0.96),
    insets(0.0, 12.0),
    initSize(0.0, 28.0),
  )
  theme.addLabelRule(
    LabelHeadingStyleClass,
    fill(color(0.02, 0.08, 0.16, 0.22)),
    color(0.18, 0.78, 1.0, 0.28),
    1.0,
    6.0,
    color(0.76, 0.96, 1.0, 0.96),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelStatusStyleClass,
    fill(color(0.02, 0.18, 0.20, 0.24)),
    color(0.28, 0.98, 0.82, 0.34),
    1.0,
    6.0,
    color(0.74, 1.0, 0.92, 0.94),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelFormStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(0.58, 0.82, 0.94, 0.86),
    insets(0.0, 2.0),
    initSize(0.0, 18.0),
  )

proc installPeachyTables(theme: var Theme) =
  theme[srTableHeader, StyleFill] = fill(color(0.04, 0.14, 0.24, 0.66))
  theme[srTableHeader, StyleBorderColor] = color(0.16, 0.80, 1.0, 0.38)
  theme[srTableHeader, StyleInsertionIndicatorFill] = peachySelectionFill()
  theme[srTableHeaderCell, StyleFill] = fill(color(0.07, 0.18, 0.30, 0.46))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = peachyGlassFill()
  theme[srTableHeaderCell, {ssPressed}, StyleFill] = peachyGlassPressedFill()
  theme[srTableHeaderCell, StyleBorderColor] = color(0.16, 0.72, 1.0, 0.34)
  theme[srTableHeaderCell, StyleTextColor] = color(0.78, 0.94, 1.0, 0.94)
  theme[srTableHeaderCell, StyleMarkColor] = color(0.66, 0.98, 1.0, 0.96)
  theme[srRowItem, StyleAlternatingFill] = fill(color(0.10, 0.30, 0.42, 0.10))

proc installPeachyRetroPalette(theme: var Theme) =
  theme["accent"] = color(1.0, 0.18, 0.72, 0.94)
  theme["accent.pressed"] = color(1.0, 0.56, 0.12, 0.90)
  theme["focus.ring.color"] = color(0.10, 0.98, 1.0, 0.88)

  theme["button.fill"] = linear(
    color(0.24, 0.04, 0.42, 0.62),
    color(0.64, 0.10, 0.62, 0.42),
    color(1.0, 0.34, 0.18, 0.30),
    fgaDiagTLBR,
    112'u8,
  )
  theme["button.fill.highlighted"] = linear(
    color(1.0, 0.24, 0.76, 0.66),
    color(0.36, 0.16, 0.82, 0.48),
    color(0.08, 0.94, 1.0, 0.34),
    fgaDiagTLBR,
    116'u8,
  )
  theme["button.fill.accent"] = styleToken("button.fill.highlighted")
  theme["button.fill.accent.highlighted"] = linear(
    color(1.0, 0.54, 0.12, 0.72),
    color(1.0, 0.14, 0.68, 0.58),
    color(0.22, 0.08, 0.68, 0.44),
    fgaY,
    112'u8,
  )
  theme["button.border.color"] = color(1.0, 0.22, 0.76, 0.66)
  theme["button.border.color.highlighted"] = color(0.18, 0.96, 1.0, 0.88)
  theme["button.border.color.accent"] = color(1.0, 0.62, 0.16, 0.82)
  theme["button.border.color.accent.highlighted"] = color(1.0, 0.92, 0.28, 0.90)
  theme["button.text.color"] = color(1.0, 0.92, 1.0, 0.98)

  theme["choice.indicator.fill.selected"] = linear(
    color(1.0, 0.22, 0.72, 0.68),
    color(0.42, 0.08, 0.88, 0.52),
    color(0.08, 0.86, 1.0, 0.40),
    fgaDiagTLBR,
    108'u8,
  )
  theme["choice.indicator.border.color"] = color(1.0, 0.24, 0.74, 0.58)
  theme["choice.indicator.border.color.selected"] = color(0.18, 0.98, 1.0, 0.92)
  theme["choice.mark.color"] = color(0.04, 0.02, 0.12, 1.0)

  theme["textField.fill"] = linear(
    color(0.05, 0.02, 0.14, 0.64),
    color(0.14, 0.04, 0.28, 0.44),
    color(0.02, 0.10, 0.22, 0.42),
    fgaY,
    96'u8,
  )
  theme["textField.border.color"] = color(1.0, 0.20, 0.76, 0.52)
  theme["textField.text.color"] = color(1.0, 0.90, 1.0, 0.96)
  theme["textField.selection.color"] = color(0.98, 0.18, 0.78, 0.36)
  theme["comboBox.border.color.open"] = color(1.0, 0.62, 0.16, 0.86)
  theme["comboBox.arrow.color"] = color(0.16, 0.96, 1.0, 0.96)

  theme["tableView.fill"] = linear(
    color(0.02, 0.02, 0.12, 0.58),
    color(0.16, 0.04, 0.30, 0.34),
    color(0.04, 0.12, 0.26, 0.42),
    fgaY,
    102'u8,
  )
  theme["tableView.border.color"] = color(1.0, 0.22, 0.76, 0.44)
  theme["rowItem.fill.highlighted"] = fill(color(0.90, 0.16, 0.68, 0.22))
  theme["rowItem.fill.selected"] = linear(
    color(1.0, 0.22, 0.76, 0.56),
    color(0.38, 0.12, 0.86, 0.44),
    color(0.04, 0.76, 1.0, 0.36),
    fgaDiagTLBR,
    110'u8,
  )
  theme["rowItem.text.color"] = color(1.0, 0.86, 1.0, 0.92)
  theme["rowItem.separator.color"] = color(0.98, 0.24, 0.76, 0.18)

  theme["tab.panel.fill"] = styleToken("tableView.fill")
  theme["tab.panel.border.color"] = color(1.0, 0.24, 0.76, 0.44)
  theme["tab.fill"] = fill(color(0.10, 0.03, 0.24, 0.44))
  theme["tab.fill.highlighted"] = styleToken("button.fill")
  theme["tab.fill.selected"] = styleToken("button.fill.highlighted")
  theme["tab.highlight.fill"] = styleFill(color(1.0, 0.78, 0.24, 0.28))
  theme["tab.text.color"] = color(0.98, 0.78, 1.0, 0.90)
  theme["tab.text.color.selected"] = color(1.0, 0.98, 0.82, 1.0)
  theme["tab.border.color"] = color(1.0, 0.22, 0.76, 0.52)
  theme["tab.border.color.selected"] = color(1.0, 0.72, 0.20, 0.82)

  theme[srTableHeader, StyleFill] = fill(color(0.16, 0.04, 0.30, 0.68))
  theme[srTableHeader, StyleBorderColor] = color(1.0, 0.22, 0.76, 0.42)
  theme[srTableHeader, StyleInsertionIndicatorFill] =
    styleToken("rowItem.fill.selected")
  theme[srTableHeaderCell, StyleFill] = fill(color(0.24, 0.04, 0.34, 0.48))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = styleToken("button.fill")
  theme[srTableHeaderCell, {ssPressed}, StyleFill] =
    styleToken("button.fill.accent.highlighted")
  theme[srTableHeaderCell, StyleBorderColor] = color(1.0, 0.24, 0.76, 0.34)
  theme[srTableHeaderCell, StyleTextColor] = color(1.0, 0.84, 1.0, 0.94)
  theme[srTableHeaderCell, StyleMarkColor] = color(0.18, 0.98, 1.0, 0.96)
  theme[srRowItem, StyleAlternatingFill] = fill(color(0.98, 0.22, 0.74, 0.08))

  theme["accent"] = color(0.94, 0.34, 0.58, 0.92)
  theme["accent.pressed"] = color(1.0, 0.62, 0.34, 0.88)
  theme["disabled.text.color"] = color(0.55, 0.60, 0.56, 0.72)
  theme["focus.ring.color"] = color(1.0, 0.58, 0.34, 0.68)

  theme["button.fill"] = peachyGlassFill()
  theme["button.fill.highlighted"] = peachyGlassHotFill()
  theme["button.fill.accent"] = peachyGlassHotFill()
  theme["button.fill.accent.highlighted"] = peachyGlassPressedFill()
  theme["button.text.color"] = color(1.0, 0.74, 0.50, 0.98)
  theme["button.border.color"] = color(1.0, 0.56, 0.38, 0.76)
  theme["button.border.color.highlighted"] = color(1.0, 0.72, 0.48, 0.90)
  theme["button.border.color.accent"] = color(1.0, 0.38, 0.62, 0.84)
  theme["button.border.color.accent.highlighted"] = color(1.0, 0.78, 0.42, 0.92)
  theme["button.focus.ring.color"] = styleToken("focus.ring.color")
  theme["button.shadows"] = peachyGlowShadows()
  theme["button.shadows.highlighted"] = peachyPressedShadows()

  theme["choice.indicator.fill"] = peachyFieldFill()
  theme["choice.indicator.fill.highlighted"] = peachyGlassFill()
  theme["choice.indicator.fill.selected"] = peachySelectionFill()
  theme["choice.indicator.fill.selected.highlighted"] = peachyGlassHotFill()
  theme["choice.indicator.border.color"] = color(1.0, 0.58, 0.40, 0.74)
  theme["choice.indicator.border.color.selected"] = color(1.0, 0.74, 0.45, 0.92)
  theme["choice.indicator.border.color.highlighted"] = color(1.0, 0.70, 0.46, 0.86)
  theme["choice.mark.color"] = color(0.06, 0.08, 0.12, 1.0)
  theme["choice.text.color"] = color(1.0, 0.54, 0.78, 0.98)

  theme["textField.fill"] = peachyFieldFill()
  theme["textField.border.color"] = color(1.0, 0.58, 0.40, 0.72)
  theme["textField.text.color"] = color(1.0, 0.80, 0.64, 0.98)
  theme["textField.selection.color"] = color(0.94, 0.34, 0.58, 0.40)
  theme["comboBox.fill"] = styleToken("textField.fill")
  theme["comboBox.border.color"] = styleToken("textField.border.color")
  theme["comboBox.border.color.open"] = color(1.0, 0.74, 0.42, 0.88)
  theme["comboBox.text.color"] = styleToken("textField.text.color")
  theme["comboBox.arrow.color"] = color(1.0, 0.74, 0.46, 0.96)
  theme["comboBox.item.fill"] = fill(color(0.18, 0.19, 0.25, 0.94))
  theme["comboBox.item.fill.highlighted"] = peachyGlassFill()
  theme["comboBox.item.fill.selected"] = peachySelectionFill()
  theme["comboBox.item.fill.selected.highlighted"] = peachyGlassHotFill()
  theme["comboBox.item.text.color"] = color(1.0, 0.48, 0.76, 0.98)
  theme["comboBox.item.text.color.selected"] = color(1.0, 0.86, 0.52, 1.0)

  theme["tableView.fill"] = peachyPanelFill()
  theme["tableView.border.color"] = color(1.0, 0.58, 0.40, 0.66)
  theme["scrollView.fill"] = styleToken("tableView.fill")
  theme["scrollView.border.color"] = styleToken("tableView.border.color")
  theme["scroller.track.fill"] = fill(color(0.18, 0.19, 0.25, 0.34))
  theme["scroller.track.border.color"] = color(1.0, 0.58, 0.40, 0.34)
  theme["scroller.knob.fill"] = linear(
    color(0.94, 0.34, 0.58, 0.78),
    color(0.62, 0.30, 0.48, 0.60),
    color(1.0, 0.60, 0.40, 0.44),
    fgaDiagTLBR,
    108'u8,
  )
  theme["scroller.knob.border.color"] = color(1.0, 0.74, 0.46, 0.84)
  theme["rowItem.fill"] = fill(color(0.18, 0.19, 0.25, 0.14))
  theme["rowItem.fill.highlighted"] = fill(color(0.50, 0.26, 0.38, 0.38))
  theme["rowItem.fill.selected"] = peachySelectionFill()
  theme["rowItem.fill.selected.highlighted"] = peachyGlassHotFill()
  theme["rowItem.text.color"] = color(1.0, 0.48, 0.76, 0.98)
  theme["rowItem.text.color.selected"] = color(1.0, 0.86, 0.46, 1.0)
  theme["rowItem.separator.color"] = color(1.0, 0.58, 0.40, 0.24)

  theme["tab.panel.fill"] = styleToken("tableView.fill")
  theme["tab.panel.border.color"] = color(1.0, 0.58, 0.40, 0.68)
  theme["tab.fill"] = fill(color(0.20, 0.20, 0.27, 0.66))
  theme["tab.fill.highlighted"] = peachyGlassFill()
  theme["tab.fill.selected"] = peachyGlassHotFill()
  theme["tab.highlight.fill"] = styleFill(color(1.0, 0.78, 0.46, 0.18))
  theme["tab.text.color"] = color(1.0, 0.62, 0.82, 0.96)
  theme["tab.text.color.selected"] = color(1.0, 0.84, 0.52, 1.0)
  theme["tab.border.color"] = color(1.0, 0.58, 0.40, 0.72)
  theme["tab.border.color.highlighted"] = color(1.0, 0.70, 0.46, 0.86)
  theme["tab.border.color.selected"] = color(1.0, 0.78, 0.46, 0.94)

  theme[srButton, StyleBorderWidth] = 1.25
  theme[srButton, StyleTextHighlightColor] = color(1.0, 0.76, 0.52, 0.16)
  theme[srButton, StyleTextShadowColor] = color(0.0, 0.0, 0.0, 0.34)
  theme[srTextField, StyleBorderWidth] = 1.25
  theme[srComboBox, StyleBorderWidth] = 1.25
  theme[srTableView, StyleBorderWidth] = 1.25
  theme[srScrollView, StyleFill] = styleToken("scrollView.fill")
  theme[srScrollView, StyleBorderColor] = styleToken("scrollView.border.color")
  theme[srScrollView, StyleBorderWidth] = 1.25
  theme[srScrollView, StyleCornerRadius] = 5.0
  theme[srScrollView, StyleBoxShadows] = peachyInsetShadows()
  theme[srScroller, StyleFill] = styleToken("scroller.track.fill")
  theme[srScroller, StyleBorderColor] = styleToken("scroller.track.border.color")
  theme[srScroller, StyleKnobFill] = styleToken("scroller.knob.fill")
  theme[srScroller, StyleKnobBorderColor] = styleToken("scroller.knob.border.color")
  theme[srScroller, StyleBorderWidth] = 1.0
  theme[srScroller, StyleCornerRadius] = 4.0
  theme[srScroller, StyleKnobShadows] =
    @[
      dropShadow(color(1.0, 0.34, 0.52, 0.20), y = 1.0, blur = 7.0),
      insetShadow(color(1.0, 0.78, 0.52, 0.22), y = 1.0, blur = 3.0),
    ]
  theme[srTab, StyleBorderWidth] = 1.25
  theme[srTabPanel, StyleBorderWidth] = 1.25
  for role in [srCheckBox, srRadioButton]:
    theme[role, StyleBorderWidth] = 1.25
    theme[role, StyleBoxShadows] = peachyInsetShadows()

  theme[srTableHeader, StyleFill] = fill(color(0.28, 0.23, 0.31, 0.78))
  theme[srTableHeader, StyleBorderColor] = color(1.0, 0.58, 0.40, 0.70)
  theme[srTableHeader, StyleInsertionIndicatorFill] =
    styleToken("rowItem.fill.selected")
  theme[srTableHeaderCell, StyleFill] = fill(color(0.24, 0.22, 0.30, 0.70))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = peachyGlassFill()
  theme[srTableHeaderCell, {ssPressed}, StyleFill] = peachyGlassPressedFill()
  theme[srTableHeaderCell, StyleBorderColor] = color(1.0, 0.58, 0.40, 0.62)
  theme[srTableHeaderCell, StyleTextColor] = color(1.0, 0.54, 0.78, 0.98)
  theme[srTableHeaderCell, StyleMarkColor] = color(1.0, 0.78, 0.46, 0.96)
  theme[srRowItem, StyleAlternatingFill] = fill(color(0.42, 0.24, 0.36, 0.12))

  theme.addLabelRule(
    LabelStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(1.0, 0.60, 0.82, 0.96),
    insets(0.0),
    initSize(0.0, 18.0),
  )
  theme.addLabelRule(
    LabelTitleStyleClass,
    peachyGlassFill(),
    color(1.0, 0.58, 0.40, 0.62),
    1.25,
    8.0,
    color(1.0, 0.76, 0.50, 0.98),
    insets(0.0, 12.0),
    initSize(0.0, 28.0),
  )
  theme.addLabelRule(
    LabelHeadingStyleClass,
    fill(color(0.25, 0.23, 0.31, 0.42)),
    color(1.0, 0.58, 0.40, 0.54),
    1.25,
    6.0,
    color(1.0, 0.58, 0.82, 0.98),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelStatusStyleClass,
    fill(color(0.25, 0.23, 0.31, 0.38)),
    color(1.0, 0.58, 0.40, 0.50),
    1.25,
    6.0,
    color(1.0, 0.74, 0.50, 0.98),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelFormStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(1.0, 0.58, 0.40, 0.90),
    insets(0.0, 2.0),
    initSize(0.0, 18.0),
  )

proc installPeachyReferencePass(theme: var Theme) =
  theme[srView, StyleBackgroundColor] = color(0.20, 0.21, 0.27)
  theme[srView, StyleBackgroundFill] = fill(color(0.20, 0.21, 0.27, 1.0))

  theme["accent"] = color(0.88, 0.30, 0.52, 0.92)
  theme["accent.pressed"] = color(1.0, 0.62, 0.36, 0.88)
  theme["disabled.text.color"] = color(0.54, 0.58, 0.56, 0.72)
  theme["focus.ring.color"] = color(1.0, 0.58, 0.36, 0.58)

  theme["button.fill"] = linear(
    color(0.20, 0.21, 0.27, 0.82),
    color(0.34, 0.25, 0.34, 0.60),
    color(0.18, 0.19, 0.25, 0.78),
    fgaY,
    112'u8,
  )
  theme["button.fill.highlighted"] = linear(
    color(0.42, 0.22, 0.34, 0.78),
    color(0.32, 0.22, 0.32, 0.68),
    color(0.58, 0.32, 0.24, 0.48),
    fgaY,
    112'u8,
  )
  theme["button.fill.accent"] = styleToken("button.fill.highlighted")
  theme["button.fill.accent.highlighted"] = peachyGlassPressedFill()
  theme["button.text.color"] = color(1.0, 0.74, 0.50, 0.98)
  theme["button.border.color"] = color(1.0, 0.58, 0.40, 0.78)
  theme["button.border.color.highlighted"] = color(1.0, 0.74, 0.48, 0.90)
  theme["button.border.color.accent"] = color(0.92, 0.32, 0.54, 0.86)
  theme["button.border.color.accent.highlighted"] = color(1.0, 0.78, 0.42, 0.92)
  theme["button.focus.ring.color"] = styleToken("focus.ring.color")
  theme["button.shadows"] = peachyGlowShadows()
  theme["button.shadows.highlighted"] = peachyPressedShadows()

  theme["choice.indicator.fill"] = peachyFieldFill()
  theme["choice.indicator.fill.highlighted"] = peachyGlassFill()
  theme["choice.indicator.fill.selected"] = peachySelectionFill()
  theme["choice.indicator.fill.selected.highlighted"] = peachyGlassHotFill()
  theme["choice.indicator.border.color"] = color(1.0, 0.58, 0.40, 0.74)
  theme["choice.indicator.border.color.selected"] = color(1.0, 0.76, 0.44, 0.92)
  theme["choice.indicator.border.color.highlighted"] = color(1.0, 0.70, 0.46, 0.86)
  theme["choice.mark.color"] = color(0.06, 0.08, 0.12, 1.0)
  theme["choice.text.color"] = color(1.0, 0.52, 0.76, 0.98)

  theme["textField.fill"] = peachyFieldFill()
  theme["textField.border.color"] = color(1.0, 0.58, 0.40, 0.72)
  theme["textField.text.color"] = color(1.0, 0.80, 0.64, 0.98)
  theme["textField.selection.color"] = color(0.88, 0.30, 0.52, 0.40)

  theme["comboBox.fill"] = styleToken("textField.fill")
  theme["comboBox.border.color"] = styleToken("textField.border.color")
  theme["comboBox.border.color.open"] = color(1.0, 0.74, 0.42, 0.88)
  theme["comboBox.text.color"] = styleToken("textField.text.color")
  theme["comboBox.arrow.color"] = color(1.0, 0.74, 0.46, 0.96)
  theme["comboBox.item.fill"] = fill(color(0.18, 0.19, 0.25, 0.94))
  theme["comboBox.item.fill.highlighted"] = peachyGlassFill()
  theme["comboBox.item.fill.selected"] = peachySelectionFill()
  theme["comboBox.item.fill.selected.highlighted"] = peachyGlassHotFill()
  theme["comboBox.item.text.color"] = color(1.0, 0.48, 0.76, 0.98)
  theme["comboBox.item.text.color.selected"] = color(1.0, 0.86, 0.52, 1.0)

  theme["tableView.fill"] = peachyPanelFill()
  theme["tableView.border.color"] = color(1.0, 0.58, 0.40, 0.66)
  theme["rowItem.fill"] = fill(color(0.18, 0.19, 0.25, 0.14))
  theme["rowItem.fill.highlighted"] = fill(color(0.50, 0.26, 0.38, 0.38))
  theme["rowItem.fill.selected"] = peachySelectionFill()
  theme["rowItem.fill.selected.highlighted"] = peachyGlassHotFill()
  theme["rowItem.text.color"] = color(1.0, 0.48, 0.76, 0.98)
  theme["rowItem.text.color.selected"] = color(1.0, 0.86, 0.46, 1.0)
  theme["rowItem.separator.color"] = color(1.0, 0.58, 0.40, 0.24)

  theme["tab.panel.fill"] = styleToken("tableView.fill")
  theme["tab.panel.border.color"] = color(1.0, 0.58, 0.40, 0.68)
  theme["tab.fill"] = fill(color(0.20, 0.20, 0.27, 0.66))
  theme["tab.fill.highlighted"] = peachyGlassFill()
  theme["tab.fill.selected"] = peachyGlassHotFill()
  theme["tab.highlight.fill"] = styleFill(color(1.0, 0.78, 0.46, 0.18))
  theme["tab.text.color"] = color(1.0, 0.62, 0.82, 0.96)
  theme["tab.text.color.selected"] = color(1.0, 0.84, 0.52, 1.0)
  theme["tab.border.color"] = color(1.0, 0.58, 0.40, 0.72)
  theme["tab.border.color.highlighted"] = color(1.0, 0.70, 0.46, 0.86)
  theme["tab.border.color.selected"] = color(1.0, 0.78, 0.46, 0.94)

  theme[srButton, StyleBorderWidth] = 1.25
  theme[srButton, StyleTextHighlightColor] = color(0.38, 0.18, 0.14, 0.20)
  theme[srButton, StyleTextShadowColor] = color(0.0, 0.0, 0.0, 0.34)
  theme[srTextField, StyleBorderWidth] = 1.25
  theme[srComboBox, StyleBorderWidth] = 1.25
  theme[srTableView, StyleBorderWidth] = 1.25
  theme[srTab, StyleBorderWidth] = 1.25
  theme[srTabPanel, StyleBorderWidth] = 1.25
  for role in [srCheckBox, srRadioButton]:
    theme[role, StyleBorderWidth] = 1.25
    theme[role, StyleBoxShadows] = peachyInsetShadows()

  theme[srTableHeader, StyleFill] = fill(color(0.28, 0.23, 0.31, 0.78))
  theme[srTableHeader, StyleBorderColor] = color(1.0, 0.58, 0.40, 0.70)
  theme[srTableHeader, StyleInsertionIndicatorFill] =
    styleToken("rowItem.fill.selected")
  theme[srTableHeaderCell, StyleFill] = fill(color(0.24, 0.22, 0.30, 0.70))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = peachyGlassFill()
  theme[srTableHeaderCell, {ssPressed}, StyleFill] = peachyGlassPressedFill()
  theme[srTableHeaderCell, StyleBorderColor] = color(1.0, 0.58, 0.40, 0.62)
  theme[srTableHeaderCell, StyleTextColor] = color(1.0, 0.54, 0.78, 0.98)
  theme[srTableHeaderCell, StyleMarkColor] = color(1.0, 0.78, 0.46, 0.96)
  theme[srRowItem, StyleAlternatingFill] = fill(color(0.42, 0.24, 0.36, 0.12))

  theme.addLabelRule(
    LabelStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(1.0, 0.60, 0.82, 0.96),
    insets(0.0),
    initSize(0.0, 18.0),
  )
  theme.addLabelRule(
    LabelTitleStyleClass,
    peachyGlassFill(),
    color(1.0, 0.58, 0.40, 0.62),
    1.25,
    8.0,
    color(1.0, 0.76, 0.50, 0.98),
    insets(0.0, 12.0),
    initSize(0.0, 28.0),
  )
  theme.addLabelRule(
    LabelHeadingStyleClass,
    fill(color(0.25, 0.23, 0.31, 0.42)),
    color(1.0, 0.58, 0.40, 0.54),
    1.25,
    6.0,
    color(1.0, 0.58, 0.82, 0.98),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelStatusStyleClass,
    fill(color(0.25, 0.23, 0.31, 0.38)),
    color(1.0, 0.58, 0.40, 0.50),
    1.25,
    6.0,
    color(1.0, 0.74, 0.50, 0.98),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelFormStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(1.0, 0.58, 0.40, 0.90),
    insets(0.0, 2.0),
    initSize(0.0, 18.0),
  )

proc installPeachyTextReadabilityPass(theme: var Theme) =
  theme[srTextField, StyleTextColor] = color(1.0, 0.80, 0.64, 0.98)
  theme[srTextField, {ssFocused}, StyleTextColor] = color(1.0, 0.88, 0.72, 1.0)
  theme[srTextField, {ssDisabled}, StyleTextColor] = styleToken("disabled.text.color")
  theme[srTextView, StyleTextColor] = color(1.0, 0.80, 0.64, 0.98)
  theme[srTextView, {ssFocused}, StyleTextColor] = color(1.0, 0.88, 0.72, 1.0)
  theme[srTextView, {ssDisabled}, StyleTextColor] = styleToken("disabled.text.color")

  theme[srSlider, StyleChrome] = styleKeyword(FlatTransparentChromeName)
  theme[srSlider, StyleFill] = linear(
    color(0.20, 0.21, 0.27, 0.88),
    color(0.34, 0.25, 0.34, 0.72),
    color(0.16, 0.18, 0.24, 0.86),
    fgaY,
    104'u8,
  )
  theme[srSlider, StyleHighlightFill] = linear(
    color(0.94, 0.34, 0.58, 0.86),
    color(0.68, 0.30, 0.48, 0.76),
    color(1.0, 0.58, 0.36, 0.62),
    fgaDiagTLBR,
    108'u8,
  )
  theme[srSlider, StyleKnobFill] = linear(
    color(0.52, 0.27, 0.40, 0.88),
    color(0.34, 0.25, 0.34, 0.80),
    color(0.82, 0.44, 0.34, 0.58),
    fgaDiagTLBR,
    112'u8,
  )
  theme[srSlider, StyleBorderColor] = color(1.0, 0.58, 0.40, 0.78)
  theme[srSlider, StyleFocusRingColor] = color(1.0, 0.74, 0.46, 0.84)
  theme[srSlider, StyleKnobBorderColor] = color(1.0, 0.74, 0.46, 0.92)
  theme[srSlider, StyleBoxShadows] =
    @[
      insetShadow(color(0.0, 0.0, 0.0, 0.30), y = 1.0, blur = 4.0),
      insetShadow(color(1.0, 0.68, 0.44, 0.14), y = -1.0, blur = 4.0),
    ]
  theme[srSlider, StyleKnobShadows] =
    @[
      dropShadow(color(1.0, 0.34, 0.52, 0.20), y = 1.0, blur = 7.0),
      insetShadow(color(1.0, 0.78, 0.52, 0.24), y = 1.0, blur = 3.0),
      insetShadow(color(0.0, 0.0, 0.0, 0.26), y = -1.0, blur = 3.0),
    ]

proc initPeachyTheme*(): Theme =
  result = initTheme()
  result.installPeachyTokens()
  result.installPeachyControlStyles()
  result.installPeachyLabels()
  result.installPeachyTables()
  result.installPeachyRetroPalette()
  result.installPeachyReferencePass()
  result.installPeachyTextReadabilityPass()
  result.clearBackgroundPinstripes()

registerThemeFactory("peachy", initPeachyTheme)
registerThemeFactory("peach", initPeachyTheme)
registerThemeFactory("peachy83", initPeachyTheme)
