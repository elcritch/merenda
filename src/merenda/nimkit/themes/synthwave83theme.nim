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

func synthwave83PanelFill(): Fill =
  linear(
    initColor(0.22, 0.23, 0.29, 0.82),
    initColor(0.28, 0.23, 0.31, 0.74),
    initColor(0.18, 0.19, 0.25, 0.82),
    fgaY,
    104'u8,
  )

func synthwave83GlassFill(): Fill =
  linear(
    initColor(0.33, 0.28, 0.36, 0.56),
    initColor(0.25, 0.25, 0.32, 0.46),
    initColor(0.38, 0.19, 0.33, 0.38),
    fgaDiagTLBR,
    112'u8,
  )

func synthwave83GlassHotFill(): Fill =
  linear(
    initColor(0.68, 0.31, 0.50, 0.68),
    initColor(0.44, 0.27, 0.44, 0.54),
    initColor(0.94, 0.53, 0.35, 0.40),
    fgaDiagTLBR,
    112'u8,
  )

func synthwave83GlassPressedFill(): Fill =
  linear(
    initColor(0.24, 0.21, 0.28, 0.76),
    initColor(0.20, 0.18, 0.25, 0.68),
    initColor(0.58, 0.24, 0.42, 0.52),
    fgaY,
    120'u8,
  )

func synthwave83FieldFill(): Fill =
  linear(
    initColor(0.18, 0.19, 0.25, 0.76),
    initColor(0.24, 0.21, 0.29, 0.60),
    initColor(0.15, 0.16, 0.22, 0.70),
    fgaY,
    96'u8,
  )

func synthwave83SelectionFill(): Fill =
  linear(
    initColor(0.72, 0.28, 0.46, 0.82),
    initColor(0.58, 0.24, 0.42, 0.74),
    initColor(0.94, 0.52, 0.34, 0.58),
    fgaDiagTLBR,
    110'u8,
  )

func synthwave83DisabledFill(): Fill =
  linear(initColor(0.18, 0.18, 0.23, 0.30), initColor(0.11, 0.12, 0.16, 0.24), fgaY)

func synthwave83GlowShadows(): seq[BoxShadow] =
  @[
    dropShadow(initColor(0.95, 0.35, 0.52, 0.10), y = 1.0, blur = 9.0),
    insetShadow(initColor(1.0, 0.74, 0.52, 0.18), y = 1.0, blur = 4.0),
    insetShadow(initColor(0.82, 0.24, 0.50, 0.11), y = -2.0, blur = 8.0),
  ]

func synthwave83PressedShadows(): seq[BoxShadow] =
  @[
    insetShadow(initColor(0.0, 0.0, 0.0, 0.30), y = 2.0, blur = 7.0),
    insetShadow(initColor(1.0, 0.56, 0.36, 0.12), y = -1.0, blur = 4.0),
  ]

func synthwave83InsetShadows(): seq[BoxShadow] =
  @[
    insetShadow(initColor(0.0, 0.0, 0.0, 0.34), y = 1.0, blur = 5.0),
    insetShadow(initColor(1.0, 0.64, 0.46, 0.15), y = -1.0, blur = 4.0),
  ]

func synthwave83KnobShadows(): seq[BoxShadow] =
  @[
    dropShadow(initColor(1.0, 0.34, 0.52, 0.14), y = 1.0, blur = 7.0),
    insetShadow(initColor(1.0, 0.80, 0.60, 0.24), y = 1.0, blur = 3.0),
  ]

proc installSynthwave83Tokens(theme: var Theme) =
  theme["accent"] = initColor(0.10, 0.92, 1.0, 0.92)
  theme["accent.pressed"] = initColor(0.78, 0.18, 1.0, 0.82)
  theme["disabled.fill"] = synthwave83DisabledFill()
  theme["disabled.text.color"] = initColor(0.44, 0.58, 0.70, 0.66)
  theme["focus.ring.color"] = initColor(0.18, 0.92, 1.0, 0.88)
  theme["indicator.size"] = 18.0

  theme["button.fill"] = synthwave83GlassFill()
  theme["button.fill.highlighted"] = synthwave83GlassHotFill()
  theme["button.fill.disabled"] = synthwave83DisabledFill()
  theme["button.fill.accent"] = synthwave83GlassHotFill()
  theme["button.fill.accent.highlighted"] = synthwave83GlassPressedFill()
  theme["button.text.color"] = initColor(0.82, 0.98, 1.0, 0.96)
  theme["button.text.color.disabled"] = styleToken("disabled.text.color")
  theme["button.border.color"] = initColor(0.20, 0.92, 1.0, 0.62)
  theme["button.border.color.highlighted"] = initColor(0.62, 0.98, 1.0, 0.88)
  theme["button.border.color.disabled"] = initColor(0.22, 0.34, 0.44, 0.42)
  theme["button.border.color.accent"] = initColor(0.66, 0.20, 1.0, 0.78)
  theme["button.border.color.accent.highlighted"] = initColor(0.96, 0.36, 1.0, 0.88)
  theme["button.focus.ring.color"] = initColor(0.24, 0.96, 1.0, 0.86)
  theme["button.shadows"] = synthwave83GlowShadows()
  theme["button.shadows.highlighted"] = synthwave83PressedShadows()
  theme["button.shadows.disabled"] = newSeq[BoxShadow]()

  theme["choice.indicator.fill"] = synthwave83FieldFill()
  theme["choice.indicator.fill.highlighted"] = synthwave83GlassFill()
  theme["choice.indicator.fill.disabled"] = synthwave83DisabledFill()
  theme["choice.indicator.fill.selected"] = synthwave83SelectionFill()
  theme["choice.indicator.fill.selected.highlighted"] = synthwave83GlassHotFill()
  theme["choice.indicator.fill.selected.disabled"] = synthwave83DisabledFill()
  theme["choice.indicator.border.color"] = initColor(0.20, 0.92, 1.0, 0.56)
  theme["choice.indicator.border.color.selected"] = initColor(0.58, 0.96, 1.0, 0.94)
  theme["choice.indicator.border.color.highlighted"] = initColor(0.70, 0.98, 1.0, 0.82)
  theme["choice.indicator.border.color.disabled"] = initColor(0.22, 0.34, 0.44, 0.36)
  theme["choice.mark.color"] = initColor(0.01, 0.07, 0.14, 1.0)
  theme["choice.mark.color.disabled"] = styleToken("disabled.text.color")
  theme["choice.text.color"] = initColor(0.78, 0.92, 1.0, 0.94)
  theme["choice.text.color.disabled"] = styleToken("disabled.text.color")

  theme["textField.fill"] = synthwave83FieldFill()
  theme["textField.border.color"] = initColor(0.18, 0.86, 1.0, 0.54)
  theme["textField.text.color"] = initColor(0.84, 0.98, 1.0, 0.96)
  theme["textField.selection.color"] = initColor(0.20, 0.88, 1.0, 0.34)
  theme["comboBox.fill"] = styleToken("textField.fill")
  theme["comboBox.border.color"] = styleToken("textField.border.color")
  theme["comboBox.border.color.open"] = initColor(0.78, 0.24, 1.0, 0.86)
  theme["comboBox.text.color"] = styleToken("textField.text.color")
  theme["comboBox.arrow.color"] = initColor(0.42, 0.96, 1.0, 0.96)
  theme["comboBox.item.fill"] = fill(initColor(0.02, 0.06, 0.13, 0.86))
  theme["comboBox.item.fill.highlighted"] = synthwave83GlassFill()
  theme["comboBox.item.fill.selected"] = synthwave83SelectionFill()
  theme["comboBox.item.fill.selected.highlighted"] = synthwave83GlassHotFill()
  theme["comboBox.item.text.color"] = initColor(0.78, 0.92, 1.0, 0.94)
  theme["comboBox.item.text.color.selected"] = initColor(0.94, 1.0, 1.0, 1.0)

  theme["tableView.fill"] = synthwave83PanelFill()
  theme["tableView.border.color"] = initColor(0.14, 0.76, 1.0, 0.46)
  theme["rowItem.fill"] = fill(initColor(0.02, 0.06, 0.13, 0.10))
  theme["rowItem.fill.highlighted"] = fill(initColor(0.12, 0.46, 0.72, 0.26))
  theme["rowItem.fill.selected"] = synthwave83SelectionFill()
  theme["rowItem.fill.selected.highlighted"] = synthwave83GlassHotFill()
  theme["rowItem.fill.disabled"] = fill(initColor(0.08, 0.10, 0.14, 0.18))
  theme["rowItem.text.color"] = initColor(0.80, 0.94, 1.0, 0.94)
  theme["rowItem.text.color.selected"] = initColor(0.98, 1.0, 1.0, 1.0)
  theme["rowItem.text.color.disabled"] = styleToken("disabled.text.color")
  theme["rowItem.separator.color"] = initColor(0.18, 0.78, 1.0, 0.18)

  theme["tab.panel.fill"] = synthwave83PanelFill()
  theme["tab.panel.border.color"] = initColor(0.20, 0.80, 1.0, 0.44)
  theme["tab.fill"] = fill(initColor(0.05, 0.14, 0.24, 0.42))
  theme["tab.fill.highlighted"] = synthwave83GlassFill()
  theme["tab.fill.selected"] = synthwave83GlassHotFill()
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

proc installSynthwave83ControlStyles(theme: var Theme) =
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
  theme[srButton, StyleChrome] = styleKeyword(FlatTransparentChromeName)

  theme[srSwitch, StyleFill] = synthwave83FieldFill()
  theme[srSwitch, StyleBorderColor] = initColor(0.16, 0.86, 1.0, 0.54)
  theme[srSwitch, StyleFocusRingColor] = styleToken("focus.ring.color")
  theme[srSwitch, StyleBoxShadows] = synthwave83InsetShadows()
  theme[srSwitch, StyleKnobFill] = synthwave83GlassFill()
  theme[srSwitch, StyleKnobBorderColor] = initColor(0.58, 0.96, 1.0, 0.82)
  theme[srSwitch, StyleKnobShadows] = synthwave83KnobShadows()
  theme[srSwitch, {ssSelected}, StyleFill] = synthwave83SelectionFill()
  theme[srSwitch, {ssSelected}, StyleBorderColor] = initColor(0.80, 0.24, 1.0, 0.80)
  theme[srSwitch, {ssHighlighted}, StyleKnobFill] = synthwave83GlassHotFill()
  theme[srSwitch, {ssDisabled}, StyleFill] = synthwave83DisabledFill()
  theme[srSwitch, {ssDisabled}, StyleBorderColor] = initColor(0.22, 0.34, 0.44, 0.34)
  theme[srSwitch, {ssDisabled}, StyleBoxShadows] = newSeq[BoxShadow]()
  theme[srSwitch, {ssDisabled}, StyleKnobFill] = synthwave83DisabledFill()
  theme[srSwitch, {ssDisabled}, StyleKnobBorderColor] =
    initColor(0.22, 0.34, 0.44, 0.38)
  theme[srSwitch, {ssDisabled}, StyleKnobShadows] = newSeq[BoxShadow]()
  theme[srSwitch, {ssSelected, ssDisabled}, StyleFill] = synthwave83DisabledFill()
  theme[srSwitch, {ssSelected, ssDisabled}, StyleBorderColor] =
    initColor(0.22, 0.34, 0.44, 0.38)

  for role in [srCheckBox, srRadioButton]:
    theme[role, StyleFocusRingColor] = styleToken("focus.ring.color")
    theme[role, StyleBoxShadows] = synthwave83InsetShadows()
    theme[role, StyleChrome] = styleKeyword(FlatTransparentChromeName)

  theme[srTextField, StyleBoxShadows] = synthwave83InsetShadows()
  theme[srComboBox, StyleChrome] = styleKeyword(FlatTransparentChromeName)
  theme[srComboBox, StyleBoxShadows] = synthwave83InsetShadows()
  theme[srSlider, StyleChrome] = styleKeyword(FlatTransparentChromeName)
  theme[srSlider, StyleFocusRingColor] = styleToken("focus.ring.color")
  theme[srSlider, StyleBoxShadows] = synthwave83InsetShadows()
  theme[srTableView, StyleBoxShadows] = synthwave83InsetShadows()
  theme[srTableView, StyleDropIndicatorFill] = synthwave83SelectionFill()
  theme[srTableView, StyleFocusRingColor] = styleToken("focus.ring.color")

proc installSynthwave83Labels(theme: var Theme) =
  theme.addLabelRule(
    LabelStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(0.78, 0.92, 1.0, 0.92),
    initEdgeInsets(0.0),
    initSize(0.0, 18.0),
  )
  theme.addLabelRule(
    LabelTitleStyleClass,
    linear(initColor(0.12, 0.36, 0.58, 0.42), initColor(0.04, 0.10, 0.22, 0.22), fgaY),
    initColor(0.28, 0.88, 1.0, 0.44),
    1.0,
    8.0,
    initColor(0.84, 0.98, 1.0, 0.96),
    initEdgeInsets(0.0, 12.0),
    initSize(0.0, 28.0),
  )
  theme.addLabelRule(
    LabelHeadingStyleClass,
    fill(initColor(0.02, 0.08, 0.16, 0.22)),
    initColor(0.18, 0.78, 1.0, 0.28),
    1.0,
    6.0,
    initColor(0.76, 0.96, 1.0, 0.96),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelStatusStyleClass,
    fill(initColor(0.02, 0.18, 0.20, 0.24)),
    initColor(0.28, 0.98, 0.82, 0.34),
    1.0,
    6.0,
    initColor(0.74, 1.0, 0.92, 0.94),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelFormStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(0.58, 0.82, 0.94, 0.86),
    initEdgeInsets(0.0, 2.0),
    initSize(0.0, 18.0),
  )

proc installSynthwave83Tables(theme: var Theme) =
  theme[srTableHeader, StyleFill] = fill(initColor(0.04, 0.14, 0.24, 0.66))
  theme[srTableHeader, StyleBorderColor] = initColor(0.16, 0.80, 1.0, 0.38)
  theme[srTableHeader, StyleInsertionIndicatorFill] = synthwave83SelectionFill()
  theme[srTableHeaderCell, StyleFill] = fill(initColor(0.07, 0.18, 0.30, 0.46))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = synthwave83GlassFill()
  theme[srTableHeaderCell, {ssPressed}, StyleFill] = synthwave83GlassPressedFill()
  theme[srTableHeaderCell, StyleBorderColor] = initColor(0.16, 0.72, 1.0, 0.34)
  theme[srTableHeaderCell, StyleTextColor] = initColor(0.78, 0.94, 1.0, 0.94)
  theme[srTableHeaderCell, StyleMarkColor] = initColor(0.66, 0.98, 1.0, 0.96)
  theme[srRowItem, StyleAlternatingFill] = fill(initColor(0.10, 0.30, 0.42, 0.10))

proc installSynthwave83RetroPalette(theme: var Theme) =
  theme["accent"] = initColor(1.0, 0.18, 0.72, 0.94)
  theme["accent.pressed"] = initColor(1.0, 0.56, 0.12, 0.90)
  theme["focus.ring.color"] = initColor(0.10, 0.98, 1.0, 0.88)

  theme["button.fill"] = linear(
    initColor(0.24, 0.04, 0.42, 0.62),
    initColor(0.64, 0.10, 0.62, 0.42),
    initColor(1.0, 0.34, 0.18, 0.30),
    fgaDiagTLBR,
    112'u8,
  )
  theme["button.fill.highlighted"] = linear(
    initColor(1.0, 0.24, 0.76, 0.66),
    initColor(0.36, 0.16, 0.82, 0.48),
    initColor(0.08, 0.94, 1.0, 0.34),
    fgaDiagTLBR,
    116'u8,
  )
  theme["button.fill.accent"] = styleToken("button.fill.highlighted")
  theme["button.fill.accent.highlighted"] = linear(
    initColor(1.0, 0.54, 0.12, 0.72),
    initColor(1.0, 0.14, 0.68, 0.58),
    initColor(0.22, 0.08, 0.68, 0.44),
    fgaY,
    112'u8,
  )
  theme["button.border.color"] = initColor(1.0, 0.22, 0.76, 0.66)
  theme["button.border.color.highlighted"] = initColor(0.18, 0.96, 1.0, 0.88)
  theme["button.border.color.accent"] = initColor(1.0, 0.62, 0.16, 0.82)
  theme["button.border.color.accent.highlighted"] = initColor(1.0, 0.92, 0.28, 0.90)
  theme["button.text.color"] = initColor(1.0, 0.92, 1.0, 0.98)

  theme["choice.indicator.fill.selected"] = linear(
    initColor(1.0, 0.22, 0.72, 0.68),
    initColor(0.42, 0.08, 0.88, 0.52),
    initColor(0.08, 0.86, 1.0, 0.40),
    fgaDiagTLBR,
    108'u8,
  )
  theme["choice.indicator.border.color"] = initColor(1.0, 0.24, 0.74, 0.58)
  theme["choice.indicator.border.color.selected"] = initColor(0.18, 0.98, 1.0, 0.92)
  theme["choice.mark.color"] = initColor(0.04, 0.02, 0.12, 1.0)

  theme["textField.fill"] = linear(
    initColor(0.05, 0.02, 0.14, 0.64),
    initColor(0.14, 0.04, 0.28, 0.44),
    initColor(0.02, 0.10, 0.22, 0.42),
    fgaY,
    96'u8,
  )
  theme["textField.border.color"] = initColor(1.0, 0.20, 0.76, 0.52)
  theme["textField.text.color"] = initColor(1.0, 0.90, 1.0, 0.96)
  theme["textField.selection.color"] = initColor(0.98, 0.18, 0.78, 0.36)
  theme["comboBox.border.color.open"] = initColor(1.0, 0.62, 0.16, 0.86)
  theme["comboBox.arrow.color"] = initColor(0.16, 0.96, 1.0, 0.96)

  theme["tableView.fill"] = linear(
    initColor(0.02, 0.02, 0.12, 0.58),
    initColor(0.16, 0.04, 0.30, 0.34),
    initColor(0.04, 0.12, 0.26, 0.42),
    fgaY,
    102'u8,
  )
  theme["tableView.border.color"] = initColor(1.0, 0.22, 0.76, 0.44)
  theme["rowItem.fill.highlighted"] = fill(initColor(0.90, 0.16, 0.68, 0.22))
  theme["rowItem.fill.selected"] = linear(
    initColor(1.0, 0.22, 0.76, 0.56),
    initColor(0.38, 0.12, 0.86, 0.44),
    initColor(0.04, 0.76, 1.0, 0.36),
    fgaDiagTLBR,
    110'u8,
  )
  theme["rowItem.text.color"] = initColor(1.0, 0.86, 1.0, 0.92)
  theme["rowItem.separator.color"] = initColor(0.98, 0.24, 0.76, 0.18)

  theme["tab.panel.fill"] = styleToken("tableView.fill")
  theme["tab.panel.border.color"] = initColor(1.0, 0.24, 0.76, 0.44)
  theme["tab.fill"] = fill(initColor(0.10, 0.03, 0.24, 0.44))
  theme["tab.fill.highlighted"] = styleToken("button.fill")
  theme["tab.fill.selected"] = styleToken("button.fill.highlighted")
  theme["tab.highlight.fill"] = styleFill(initColor(1.0, 0.78, 0.24, 0.28))
  theme["tab.text.color"] = initColor(0.98, 0.78, 1.0, 0.90)
  theme["tab.text.color.selected"] = initColor(1.0, 0.98, 0.82, 1.0)
  theme["tab.border.color"] = initColor(1.0, 0.22, 0.76, 0.52)
  theme["tab.border.color.selected"] = initColor(1.0, 0.72, 0.20, 0.82)

  theme[srTableHeader, StyleFill] = fill(initColor(0.16, 0.04, 0.30, 0.68))
  theme[srTableHeader, StyleBorderColor] = initColor(1.0, 0.22, 0.76, 0.42)
  theme[srTableHeader, StyleInsertionIndicatorFill] =
    styleToken("rowItem.fill.selected")
  theme[srTableHeaderCell, StyleFill] = fill(initColor(0.24, 0.04, 0.34, 0.48))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = styleToken("button.fill")
  theme[srTableHeaderCell, {ssPressed}, StyleFill] =
    styleToken("button.fill.accent.highlighted")
  theme[srTableHeaderCell, StyleBorderColor] = initColor(1.0, 0.24, 0.76, 0.34)
  theme[srTableHeaderCell, StyleTextColor] = initColor(1.0, 0.84, 1.0, 0.94)
  theme[srTableHeaderCell, StyleMarkColor] = initColor(0.18, 0.98, 1.0, 0.96)
  theme[srRowItem, StyleAlternatingFill] = fill(initColor(0.98, 0.22, 0.74, 0.08))

  theme["accent"] = initColor(0.94, 0.34, 0.58, 0.92)
  theme["accent.pressed"] = initColor(1.0, 0.62, 0.34, 0.88)
  theme["disabled.text.color"] = initColor(0.55, 0.60, 0.56, 0.72)
  theme["focus.ring.color"] = initColor(1.0, 0.58, 0.34, 0.68)

  theme["button.fill"] = synthwave83GlassFill()
  theme["button.fill.highlighted"] = synthwave83GlassHotFill()
  theme["button.fill.accent"] = synthwave83GlassHotFill()
  theme["button.fill.accent.highlighted"] = synthwave83GlassPressedFill()
  theme["button.text.color"] = initColor(1.0, 0.74, 0.50, 0.98)
  theme["button.border.color"] = initColor(1.0, 0.56, 0.38, 0.76)
  theme["button.border.color.highlighted"] = initColor(1.0, 0.72, 0.48, 0.90)
  theme["button.border.color.accent"] = initColor(1.0, 0.38, 0.62, 0.84)
  theme["button.border.color.accent.highlighted"] = initColor(1.0, 0.78, 0.42, 0.92)
  theme["button.focus.ring.color"] = styleToken("focus.ring.color")
  theme["button.shadows"] = synthwave83GlowShadows()
  theme["button.shadows.highlighted"] = synthwave83PressedShadows()

  theme["choice.indicator.fill"] = synthwave83FieldFill()
  theme["choice.indicator.fill.highlighted"] = synthwave83GlassFill()
  theme["choice.indicator.fill.selected"] = synthwave83SelectionFill()
  theme["choice.indicator.fill.selected.highlighted"] = synthwave83GlassHotFill()
  theme["choice.indicator.border.color"] = initColor(1.0, 0.58, 0.40, 0.74)
  theme["choice.indicator.border.color.selected"] = initColor(1.0, 0.74, 0.45, 0.92)
  theme["choice.indicator.border.color.highlighted"] = initColor(1.0, 0.70, 0.46, 0.86)
  theme["choice.mark.color"] = initColor(0.06, 0.08, 0.12, 1.0)
  theme["choice.text.color"] = initColor(1.0, 0.54, 0.78, 0.98)

  theme["textField.fill"] = synthwave83FieldFill()
  theme["textField.border.color"] = initColor(1.0, 0.58, 0.40, 0.72)
  theme["textField.text.color"] = initColor(1.0, 0.80, 0.64, 0.98)
  theme["textField.selection.color"] = initColor(0.94, 0.34, 0.58, 0.40)
  theme["comboBox.fill"] = styleToken("textField.fill")
  theme["comboBox.border.color"] = styleToken("textField.border.color")
  theme["comboBox.border.color.open"] = initColor(1.0, 0.74, 0.42, 0.88)
  theme["comboBox.text.color"] = styleToken("textField.text.color")
  theme["comboBox.arrow.color"] = initColor(1.0, 0.74, 0.46, 0.96)
  theme["comboBox.item.fill"] = fill(initColor(0.18, 0.19, 0.25, 0.94))
  theme["comboBox.item.fill.highlighted"] = synthwave83GlassFill()
  theme["comboBox.item.fill.selected"] = synthwave83SelectionFill()
  theme["comboBox.item.fill.selected.highlighted"] = synthwave83GlassHotFill()
  theme["comboBox.item.text.color"] = initColor(1.0, 0.48, 0.76, 0.98)
  theme["comboBox.item.text.color.selected"] = initColor(1.0, 0.86, 0.52, 1.0)

  theme["tableView.fill"] = synthwave83PanelFill()
  theme["tableView.border.color"] = initColor(1.0, 0.58, 0.40, 0.66)
  theme["rowItem.fill"] = fill(initColor(0.18, 0.19, 0.25, 0.14))
  theme["rowItem.fill.highlighted"] = fill(initColor(0.50, 0.26, 0.38, 0.38))
  theme["rowItem.fill.selected"] = synthwave83SelectionFill()
  theme["rowItem.fill.selected.highlighted"] = synthwave83GlassHotFill()
  theme["rowItem.text.color"] = initColor(1.0, 0.48, 0.76, 0.98)
  theme["rowItem.text.color.selected"] = initColor(1.0, 0.86, 0.46, 1.0)
  theme["rowItem.separator.color"] = initColor(1.0, 0.58, 0.40, 0.24)

  theme["tab.panel.fill"] = styleToken("tableView.fill")
  theme["tab.panel.border.color"] = initColor(1.0, 0.58, 0.40, 0.68)
  theme["tab.fill"] = fill(initColor(0.20, 0.20, 0.27, 0.66))
  theme["tab.fill.highlighted"] = synthwave83GlassFill()
  theme["tab.fill.selected"] = synthwave83GlassHotFill()
  theme["tab.highlight.fill"] = styleFill(initColor(1.0, 0.78, 0.46, 0.18))
  theme["tab.text.color"] = initColor(1.0, 0.62, 0.82, 0.96)
  theme["tab.text.color.selected"] = initColor(1.0, 0.84, 0.52, 1.0)
  theme["tab.border.color"] = initColor(1.0, 0.58, 0.40, 0.72)
  theme["tab.border.color.highlighted"] = initColor(1.0, 0.70, 0.46, 0.86)
  theme["tab.border.color.selected"] = initColor(1.0, 0.78, 0.46, 0.94)

  theme[srButton, StyleBorderWidth] = 1.25
  theme[srButton, StyleTextHighlightColor] = initColor(1.0, 0.76, 0.52, 0.16)
  theme[srButton, StyleTextShadowColor] = initColor(0.0, 0.0, 0.0, 0.34)
  theme[srTextField, StyleBorderWidth] = 1.25
  theme[srComboBox, StyleBorderWidth] = 1.25
  theme[srTableView, StyleBorderWidth] = 1.25
  theme[srTab, StyleBorderWidth] = 1.25
  theme[srTabPanel, StyleBorderWidth] = 1.25
  for role in [srCheckBox, srRadioButton]:
    theme[role, StyleBorderWidth] = 1.25
    theme[role, StyleBoxShadows] = synthwave83InsetShadows()

  theme[srTableHeader, StyleFill] = fill(initColor(0.28, 0.23, 0.31, 0.78))
  theme[srTableHeader, StyleBorderColor] = initColor(1.0, 0.58, 0.40, 0.70)
  theme[srTableHeader, StyleInsertionIndicatorFill] =
    styleToken("rowItem.fill.selected")
  theme[srTableHeaderCell, StyleFill] = fill(initColor(0.24, 0.22, 0.30, 0.70))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = synthwave83GlassFill()
  theme[srTableHeaderCell, {ssPressed}, StyleFill] = synthwave83GlassPressedFill()
  theme[srTableHeaderCell, StyleBorderColor] = initColor(1.0, 0.58, 0.40, 0.62)
  theme[srTableHeaderCell, StyleTextColor] = initColor(1.0, 0.54, 0.78, 0.98)
  theme[srTableHeaderCell, StyleMarkColor] = initColor(1.0, 0.78, 0.46, 0.96)
  theme[srRowItem, StyleAlternatingFill] = fill(initColor(0.42, 0.24, 0.36, 0.12))

  theme.addLabelRule(
    LabelStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(1.0, 0.60, 0.82, 0.96),
    initEdgeInsets(0.0),
    initSize(0.0, 18.0),
  )
  theme.addLabelRule(
    LabelTitleStyleClass,
    synthwave83GlassFill(),
    initColor(1.0, 0.58, 0.40, 0.62),
    1.25,
    8.0,
    initColor(1.0, 0.76, 0.50, 0.98),
    initEdgeInsets(0.0, 12.0),
    initSize(0.0, 28.0),
  )
  theme.addLabelRule(
    LabelHeadingStyleClass,
    fill(initColor(0.25, 0.23, 0.31, 0.42)),
    initColor(1.0, 0.58, 0.40, 0.54),
    1.25,
    6.0,
    initColor(1.0, 0.58, 0.82, 0.98),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelStatusStyleClass,
    fill(initColor(0.25, 0.23, 0.31, 0.38)),
    initColor(1.0, 0.58, 0.40, 0.50),
    1.25,
    6.0,
    initColor(1.0, 0.74, 0.50, 0.98),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelFormStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(1.0, 0.58, 0.40, 0.90),
    initEdgeInsets(0.0, 2.0),
    initSize(0.0, 18.0),
  )

proc installSynthwave83ReferencePass(theme: var Theme) =
  theme[srView, StyleBackgroundColor] = initColor(0.20, 0.21, 0.27)

  theme["accent"] = initColor(0.88, 0.30, 0.52, 0.92)
  theme["accent.pressed"] = initColor(1.0, 0.62, 0.36, 0.88)
  theme["disabled.text.color"] = initColor(0.54, 0.58, 0.56, 0.72)
  theme["focus.ring.color"] = initColor(1.0, 0.58, 0.36, 0.58)

  theme["button.fill"] = linear(
    initColor(0.20, 0.21, 0.27, 0.82),
    initColor(0.34, 0.25, 0.34, 0.60),
    initColor(0.18, 0.19, 0.25, 0.78),
    fgaY,
    112'u8,
  )
  theme["button.fill.highlighted"] = linear(
    initColor(0.52, 0.27, 0.40, 0.74),
    initColor(0.40, 0.25, 0.36, 0.62),
    initColor(0.72, 0.40, 0.28, 0.42),
    fgaY,
    112'u8,
  )
  theme["button.fill.accent"] = styleToken("button.fill.highlighted")
  theme["button.fill.accent.highlighted"] = synthwave83GlassPressedFill()
  theme["button.text.color"] = initColor(1.0, 0.74, 0.50, 0.98)
  theme["button.border.color"] = initColor(1.0, 0.58, 0.40, 0.78)
  theme["button.border.color.highlighted"] = initColor(1.0, 0.74, 0.48, 0.90)
  theme["button.border.color.accent"] = initColor(0.92, 0.32, 0.54, 0.86)
  theme["button.border.color.accent.highlighted"] = initColor(1.0, 0.78, 0.42, 0.92)
  theme["button.focus.ring.color"] = styleToken("focus.ring.color")
  theme["button.shadows"] = synthwave83GlowShadows()
  theme["button.shadows.highlighted"] = synthwave83PressedShadows()

  theme["choice.indicator.fill"] = synthwave83FieldFill()
  theme["choice.indicator.fill.highlighted"] = synthwave83GlassFill()
  theme["choice.indicator.fill.selected"] = synthwave83SelectionFill()
  theme["choice.indicator.fill.selected.highlighted"] = synthwave83GlassHotFill()
  theme["choice.indicator.border.color"] = initColor(1.0, 0.58, 0.40, 0.74)
  theme["choice.indicator.border.color.selected"] = initColor(1.0, 0.76, 0.44, 0.92)
  theme["choice.indicator.border.color.highlighted"] = initColor(1.0, 0.70, 0.46, 0.86)
  theme["choice.mark.color"] = initColor(0.06, 0.08, 0.12, 1.0)
  theme["choice.text.color"] = initColor(1.0, 0.52, 0.76, 0.98)

  theme["textField.fill"] = synthwave83FieldFill()
  theme["textField.border.color"] = initColor(1.0, 0.58, 0.40, 0.72)
  theme["textField.text.color"] = initColor(1.0, 0.80, 0.64, 0.98)
  theme["textField.selection.color"] = initColor(0.88, 0.30, 0.52, 0.40)

  theme["comboBox.fill"] = styleToken("textField.fill")
  theme["comboBox.border.color"] = styleToken("textField.border.color")
  theme["comboBox.border.color.open"] = initColor(1.0, 0.74, 0.42, 0.88)
  theme["comboBox.text.color"] = styleToken("textField.text.color")
  theme["comboBox.arrow.color"] = initColor(1.0, 0.74, 0.46, 0.96)
  theme["comboBox.item.fill"] = fill(initColor(0.18, 0.19, 0.25, 0.94))
  theme["comboBox.item.fill.highlighted"] = synthwave83GlassFill()
  theme["comboBox.item.fill.selected"] = synthwave83SelectionFill()
  theme["comboBox.item.fill.selected.highlighted"] = synthwave83GlassHotFill()
  theme["comboBox.item.text.color"] = initColor(1.0, 0.48, 0.76, 0.98)
  theme["comboBox.item.text.color.selected"] = initColor(1.0, 0.86, 0.52, 1.0)

  theme["tableView.fill"] = synthwave83PanelFill()
  theme["tableView.border.color"] = initColor(1.0, 0.58, 0.40, 0.66)
  theme["rowItem.fill"] = fill(initColor(0.18, 0.19, 0.25, 0.14))
  theme["rowItem.fill.highlighted"] = fill(initColor(0.50, 0.26, 0.38, 0.38))
  theme["rowItem.fill.selected"] = synthwave83SelectionFill()
  theme["rowItem.fill.selected.highlighted"] = synthwave83GlassHotFill()
  theme["rowItem.text.color"] = initColor(1.0, 0.48, 0.76, 0.98)
  theme["rowItem.text.color.selected"] = initColor(1.0, 0.86, 0.46, 1.0)
  theme["rowItem.separator.color"] = initColor(1.0, 0.58, 0.40, 0.24)

  theme["tab.panel.fill"] = styleToken("tableView.fill")
  theme["tab.panel.border.color"] = initColor(1.0, 0.58, 0.40, 0.68)
  theme["tab.fill"] = fill(initColor(0.20, 0.20, 0.27, 0.66))
  theme["tab.fill.highlighted"] = synthwave83GlassFill()
  theme["tab.fill.selected"] = synthwave83GlassHotFill()
  theme["tab.highlight.fill"] = styleFill(initColor(1.0, 0.78, 0.46, 0.18))
  theme["tab.text.color"] = initColor(1.0, 0.62, 0.82, 0.96)
  theme["tab.text.color.selected"] = initColor(1.0, 0.84, 0.52, 1.0)
  theme["tab.border.color"] = initColor(1.0, 0.58, 0.40, 0.72)
  theme["tab.border.color.highlighted"] = initColor(1.0, 0.70, 0.46, 0.86)
  theme["tab.border.color.selected"] = initColor(1.0, 0.78, 0.46, 0.94)

  theme[srButton, StyleBorderWidth] = 1.25
  theme[srButton, StyleTextHighlightColor] = initColor(1.0, 0.76, 0.52, 0.16)
  theme[srButton, StyleTextShadowColor] = initColor(0.0, 0.0, 0.0, 0.34)
  theme[srTextField, StyleBorderWidth] = 1.25
  theme[srComboBox, StyleBorderWidth] = 1.25
  theme[srTableView, StyleBorderWidth] = 1.25
  theme[srTab, StyleBorderWidth] = 1.25
  theme[srTabPanel, StyleBorderWidth] = 1.25
  for role in [srCheckBox, srRadioButton]:
    theme[role, StyleBorderWidth] = 1.25
    theme[role, StyleBoxShadows] = synthwave83InsetShadows()

  theme[srTableHeader, StyleFill] = fill(initColor(0.28, 0.23, 0.31, 0.78))
  theme[srTableHeader, StyleBorderColor] = initColor(1.0, 0.58, 0.40, 0.70)
  theme[srTableHeader, StyleInsertionIndicatorFill] =
    styleToken("rowItem.fill.selected")
  theme[srTableHeaderCell, StyleFill] = fill(initColor(0.24, 0.22, 0.30, 0.70))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = synthwave83GlassFill()
  theme[srTableHeaderCell, {ssPressed}, StyleFill] = synthwave83GlassPressedFill()
  theme[srTableHeaderCell, StyleBorderColor] = initColor(1.0, 0.58, 0.40, 0.62)
  theme[srTableHeaderCell, StyleTextColor] = initColor(1.0, 0.54, 0.78, 0.98)
  theme[srTableHeaderCell, StyleMarkColor] = initColor(1.0, 0.78, 0.46, 0.96)
  theme[srRowItem, StyleAlternatingFill] = fill(initColor(0.42, 0.24, 0.36, 0.12))

  theme.addLabelRule(
    LabelStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(1.0, 0.60, 0.82, 0.96),
    initEdgeInsets(0.0),
    initSize(0.0, 18.0),
  )
  theme.addLabelRule(
    LabelTitleStyleClass,
    synthwave83GlassFill(),
    initColor(1.0, 0.58, 0.40, 0.62),
    1.25,
    8.0,
    initColor(1.0, 0.76, 0.50, 0.98),
    initEdgeInsets(0.0, 12.0),
    initSize(0.0, 28.0),
  )
  theme.addLabelRule(
    LabelHeadingStyleClass,
    fill(initColor(0.25, 0.23, 0.31, 0.42)),
    initColor(1.0, 0.58, 0.40, 0.54),
    1.25,
    6.0,
    initColor(1.0, 0.58, 0.82, 0.98),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelStatusStyleClass,
    fill(initColor(0.25, 0.23, 0.31, 0.38)),
    initColor(1.0, 0.58, 0.40, 0.50),
    1.25,
    6.0,
    initColor(1.0, 0.74, 0.50, 0.98),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelFormStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(1.0, 0.58, 0.40, 0.90),
    initEdgeInsets(0.0, 2.0),
    initSize(0.0, 18.0),
  )

proc installSynthwave83VaporwavePass(theme: var Theme) =
  theme[srView, StyleBackgroundColor] = initColor(0.08, 0.00, 0.16)
  theme[srView, StyleBackgroundFill] = linear(
    initColor(0.08, 0.00, 0.16, 1.0),
    initColor(0.13, 0.01, 0.24, 1.0),
    initColor(0.02, 0.00, 0.10, 1.0),
    fgaDiagTLBR,
    98'u8,
  )
  theme["accent"] = initColor(1.0, 0.08, 0.86, 0.94)
  theme["accent.pressed"] = initColor(0.12, 0.86, 1.0, 0.90)
  theme["disabled.text.color"] = initColor(0.45, 0.36, 0.58, 0.72)
  theme["focus.ring.color"] = initColor(1.0, 0.08, 0.92, 0.72)

  theme["button.fill"] = linear(
    initColor(0.16, 0.00, 0.28, 0.82),
    initColor(0.34, 0.02, 0.46, 0.62),
    initColor(0.04, 0.02, 0.18, 0.78),
    fgaY,
    112'u8,
  )
  theme["button.fill.highlighted"] = linear(
    initColor(0.74, 0.04, 0.78, 0.74),
    initColor(0.35, 0.06, 0.66, 0.62),
    initColor(0.00, 0.62, 0.96, 0.36),
    fgaDiagTLBR,
    116'u8,
  )
  theme["button.fill.accent"] = styleToken("button.fill.highlighted")
  theme["button.fill.accent.highlighted"] = linear(
    initColor(1.0, 0.06, 0.88, 0.80),
    initColor(0.46, 0.04, 0.92, 0.66),
    initColor(0.02, 0.92, 1.0, 0.42),
    fgaDiagTLBR,
    112'u8,
  )
  theme["button.text.color"] = initColor(0.82, 0.96, 1.0, 0.98)
  theme["button.border.color"] = initColor(0.92, 0.05, 1.0, 0.82)
  theme["button.border.color.highlighted"] = initColor(0.14, 0.92, 1.0, 0.90)
  theme["button.border.color.accent"] = initColor(1.0, 0.10, 0.88, 0.92)
  theme["button.border.color.accent.highlighted"] = initColor(0.18, 0.96, 1.0, 0.94)
  theme["button.focus.ring.color"] = styleToken("focus.ring.color")
  theme["button.shadows"] =
    @[
      dropShadow(initColor(1.0, 0.00, 0.88, 0.16), y = 1.0, blur = 10.0),
      insetShadow(initColor(0.30, 0.95, 1.0, 0.16), y = 1.0, blur = 5.0),
      insetShadow(initColor(1.0, 0.00, 0.92, 0.14), y = -2.0, blur = 8.0),
    ]
  theme["button.shadows.highlighted"] =
    @[
      insetShadow(initColor(0.0, 0.0, 0.0, 0.34), y = 2.0, blur = 7.0),
      insetShadow(initColor(0.22, 0.92, 1.0, 0.18), y = -1.0, blur = 4.0),
    ]

  theme["choice.indicator.fill"] = linear(
    initColor(0.10, 0.00, 0.22, 0.78),
    initColor(0.22, 0.02, 0.34, 0.56),
    initColor(0.03, 0.01, 0.14, 0.74),
    fgaY,
    98'u8,
  )
  theme["choice.indicator.fill.highlighted"] = styleToken("button.fill")
  theme["choice.indicator.fill.selected"] = linear(
    initColor(1.0, 0.04, 0.86, 0.82),
    initColor(0.42, 0.02, 0.92, 0.70),
    initColor(0.02, 0.74, 1.0, 0.52),
    fgaDiagTLBR,
    110'u8,
  )
  theme["choice.indicator.fill.selected.highlighted"] =
    styleToken("button.fill.accent.highlighted")
  theme["choice.indicator.border.color"] = initColor(0.86, 0.06, 1.0, 0.72)
  theme["choice.indicator.border.color.selected"] = initColor(0.18, 0.96, 1.0, 0.94)
  theme["choice.indicator.border.color.highlighted"] = initColor(1.0, 0.12, 0.92, 0.88)
  theme["choice.mark.color"] = initColor(0.04, 0.00, 0.12, 1.0)
  theme["choice.text.color"] = initColor(1.0, 0.34, 0.92, 0.98)

  theme["textField.fill"] = linear(
    initColor(0.08, 0.00, 0.18, 0.78),
    initColor(0.20, 0.02, 0.32, 0.58),
    initColor(0.04, 0.01, 0.14, 0.72),
    fgaY,
    96'u8,
  )
  theme["textField.border.color"] = initColor(0.92, 0.06, 1.0, 0.76)
  theme["textField.text.color"] = initColor(0.82, 0.96, 1.0, 0.98)
  theme["textField.selection.color"] = initColor(1.0, 0.08, 0.86, 0.40)

  theme["comboBox.fill"] = styleToken("textField.fill")
  theme["comboBox.border.color"] = styleToken("textField.border.color")
  theme["comboBox.border.color.open"] = initColor(0.16, 0.92, 1.0, 0.90)
  theme["comboBox.text.color"] = styleToken("textField.text.color")
  theme["comboBox.arrow.color"] = initColor(0.20, 0.94, 1.0, 0.98)
  theme["comboBox.item.fill"] = fill(initColor(0.08, 0.00, 0.18, 0.96))
  theme["comboBox.item.fill.highlighted"] = styleToken("button.fill")
  theme["comboBox.item.fill.selected"] = styleToken("choice.indicator.fill.selected")
  theme["comboBox.item.fill.selected.highlighted"] =
    styleToken("button.fill.accent.highlighted")
  theme["comboBox.item.text.color"] = initColor(0.82, 0.96, 1.0, 0.96)
  theme["comboBox.item.text.color.selected"] = initColor(1.0, 0.86, 0.28, 1.0)

  theme["tableView.fill"] = linear(
    initColor(0.06, 0.00, 0.16, 0.84),
    initColor(0.18, 0.01, 0.28, 0.66),
    initColor(0.03, 0.00, 0.12, 0.80),
    fgaY,
    104'u8,
  )
  theme["tableView.border.color"] = initColor(0.88, 0.04, 1.0, 0.78)
  theme["rowItem.fill"] = fill(initColor(0.06, 0.00, 0.16, 0.18))
  theme["rowItem.fill.highlighted"] = fill(initColor(0.44, 0.04, 0.62, 0.40))
  theme["rowItem.fill.selected"] = styleToken("choice.indicator.fill.selected")
  theme["rowItem.fill.selected.highlighted"] =
    styleToken("button.fill.accent.highlighted")
  theme["rowItem.text.color"] = initColor(1.0, 0.36, 0.92, 0.98)
  theme["rowItem.text.color.selected"] = initColor(1.0, 0.88, 0.30, 1.0)
  theme["rowItem.separator.color"] = initColor(0.90, 0.05, 1.0, 0.28)

  theme["tab.panel.fill"] = styleToken("tableView.fill")
  theme["tab.panel.border.color"] = initColor(0.92, 0.06, 1.0, 0.82)
  theme["tab.fill"] = fill(initColor(0.10, 0.00, 0.22, 0.70))
  theme["tab.fill.highlighted"] = styleToken("button.fill")
  theme["tab.fill.selected"] = styleToken("button.fill.highlighted")
  theme["tab.highlight.fill"] = styleFill(initColor(0.16, 0.92, 1.0, 0.20))
  theme["tab.text.color"] = initColor(0.84, 0.92, 1.0, 0.96)
  theme["tab.text.color.selected"] = initColor(1.0, 0.84, 0.30, 1.0)
  theme["tab.border.color"] = initColor(0.90, 0.04, 1.0, 0.80)
  theme["tab.border.color.highlighted"] = initColor(0.18, 0.94, 1.0, 0.88)
  theme["tab.border.color.selected"] = initColor(1.0, 0.08, 0.88, 0.96)

  theme[srButton, StyleBorderWidth] = 1.35
  theme[srTextField, StyleBorderWidth] = 1.35
  theme[srComboBox, StyleBorderWidth] = 1.35
  theme[srTableView, StyleBorderWidth] = 1.35
  theme[srTab, StyleBorderWidth] = 1.35
  theme[srTabPanel, StyleBorderWidth] = 1.35
  theme[srButton, StyleTextHighlightColor] = initColor(0.20, 0.94, 1.0, 0.16)
  theme[srButton, StyleTextShadowColor] = initColor(0.0, 0.0, 0.0, 0.42)
  theme[srTextField, StyleBoxShadows] =
    @[
      insetShadow(initColor(0.0, 0.0, 0.0, 0.38), y = 1.0, blur = 5.0),
      insetShadow(initColor(0.22, 0.88, 1.0, 0.12), y = -1.0, blur = 4.0),
    ]
  theme[srComboBox, StyleBoxShadows] = theme[srTextField, StyleBoxShadows]
  theme[srTableView, StyleBoxShadows] = theme[srTextField, StyleBoxShadows]
  for role in [srCheckBox, srRadioButton]:
    theme[role, StyleBorderWidth] = 1.35
    theme[role, StyleBoxShadows] = theme[srTextField, StyleBoxShadows]

  theme[srTableHeader, StyleFill] = fill(initColor(0.12, 0.00, 0.24, 0.82))
  theme[srTableHeader, StyleBorderColor] = initColor(0.92, 0.06, 1.0, 0.76)
  theme[srTableHeader, StyleInsertionIndicatorFill] =
    styleToken("rowItem.fill.selected")
  theme[srTableHeaderCell, StyleFill] = fill(initColor(0.16, 0.00, 0.28, 0.72))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = styleToken("button.fill")
  theme[srTableHeaderCell, {ssPressed}, StyleFill] =
    styleToken("button.fill.accent.highlighted")
  theme[srTableHeaderCell, StyleBorderColor] = initColor(0.90, 0.05, 1.0, 0.66)
  theme[srTableHeaderCell, StyleTextColor] = initColor(1.0, 0.36, 0.92, 0.98)
  theme[srTableHeaderCell, StyleMarkColor] = initColor(0.20, 0.94, 1.0, 0.98)
  theme[srRowItem, StyleAlternatingFill] = fill(initColor(0.24, 0.00, 0.40, 0.14))

  theme.addLabelRule(
    LabelStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(0.84, 0.94, 1.0, 0.96),
    initEdgeInsets(0.0),
    initSize(0.0, 18.0),
  )
  theme.addLabelRule(
    LabelTitleStyleClass,
    linear(initColor(0.18, 0.00, 0.32, 0.62), initColor(0.06, 0.00, 0.18, 0.48), fgaY),
    initColor(0.90, 0.05, 1.0, 0.72),
    1.35,
    8.0,
    initColor(1.0, 0.82, 0.28, 0.98),
    initEdgeInsets(0.0, 12.0),
    initSize(0.0, 28.0),
  )
  theme.addLabelRule(
    LabelHeadingStyleClass,
    fill(initColor(0.12, 0.00, 0.24, 0.46)),
    initColor(0.90, 0.05, 1.0, 0.62),
    1.35,
    6.0,
    initColor(1.0, 0.36, 0.92, 0.98),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelStatusStyleClass,
    fill(initColor(0.12, 0.00, 0.24, 0.42)),
    initColor(0.16, 0.92, 1.0, 0.56),
    1.35,
    6.0,
    initColor(0.20, 0.94, 1.0, 0.98),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  theme.addLabelRule(
    LabelFormStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(0.20, 0.94, 1.0, 0.92),
    initEdgeInsets(0.0, 2.0),
    initSize(0.0, 18.0),
  )

proc installSynthwave83ReadabilityPass(theme: var Theme) =
  theme["button.fill"] = linear(
    initColor(0.10, 0.00, 0.22, 0.90),
    initColor(0.24, 0.02, 0.40, 0.78),
    initColor(0.02, 0.48, 0.72, 0.28),
    fgaDiagTLBR,
    116'u8,
  )
  theme["button.fill.highlighted"] = linear(
    initColor(0.38, 0.02, 0.58, 0.90),
    initColor(0.72, 0.04, 0.78, 0.70),
    initColor(0.04, 0.76, 1.0, 0.38),
    fgaDiagTLBR,
    116'u8,
  )
  theme["button.fill.accent"] = styleToken("button.fill.highlighted")
  theme["button.fill.accent.highlighted"] = linear(
    initColor(0.98, 0.06, 0.86, 0.86),
    initColor(0.46, 0.03, 0.90, 0.74),
    initColor(0.06, 0.94, 1.0, 0.46),
    fgaDiagTLBR,
    116'u8,
  )
  theme["button.border.color"] = initColor(0.96, 0.04, 1.0, 0.84)
  theme["button.border.color.highlighted"] = initColor(0.18, 0.96, 1.0, 0.92)
  theme["button.text.color"] = initColor(0.84, 0.98, 1.0, 0.98)
  theme[srButton, StyleCornerRadius] = 5.0
  theme[srButton, StyleCornerRadiusTopLeft] = 5.0
  theme[srButton, StyleCornerRadiusTopRight] = 0.0
  theme[srButton, StyleCornerRadiusBottomLeft] = 0.0
  theme[srButton, StyleCornerRadiusBottomRight] = 12.0
  theme[srButton, StyleBoxShadows] =
    @[
      dropShadow(initColor(0.98, 0.00, 1.0, 0.18), y = 1.0, blur = 9.0),
      insetShadow(initColor(0.22, 0.96, 1.0, 0.20), y = 1.0, blur = 3.4),
      insetShadow(initColor(1.0, 0.00, 0.92, 0.12), y = -1.0, blur = 5.0),
    ]
  theme[srButton, {ssHighlighted}, StyleBoxShadows] =
    @[
      insetShadow(initColor(0.0, 0.0, 0.0, 0.38), y = 2.0, blur = 6.0),
      insetShadow(initColor(0.22, 0.94, 1.0, 0.20), y = -1.0, blur = 4.0),
      dropShadow(initColor(0.18, 0.90, 1.0, 0.18), y = 1.0, blur = 8.0),
    ]
  theme[srButton, {ssActive}, StyleBoxShadows] =
    @[
      insetShadow(initColor(0.0, 0.0, 0.0, 0.38), y = 2.0, blur = 6.0),
      insetShadow(initColor(0.22, 0.94, 1.0, 0.20), y = -1.0, blur = 4.0),
      dropShadow(initColor(0.18, 0.90, 1.0, 0.18), y = 1.0, blur = 8.0),
    ]

  theme["comboBox.fill"] = linear(
    initColor(0.08, 0.00, 0.18, 0.92),
    initColor(0.22, 0.02, 0.36, 0.78),
    initColor(0.03, 0.34, 0.58, 0.28),
    fgaDiagTLBR,
    116'u8,
  )
  theme["comboBox.border.color"] = initColor(0.18, 0.94, 1.0, 0.82)
  theme["comboBox.border.color.open"] = initColor(1.0, 0.08, 0.92, 0.92)
  theme["comboBox.arrow.color"] = initColor(0.34, 1.0, 1.0, 1.0)
  theme[srComboBox, StyleCornerRadius] = 6.0
  theme[srComboBox, StyleBoxShadows] =
    @[
      dropShadow(initColor(0.16, 0.88, 1.0, 0.16), y = 1.0, blur = 8.0),
      insetShadow(initColor(0.34, 0.98, 1.0, 0.18), y = 1.0, blur = 3.0),
      insetShadow(initColor(1.0, 0.02, 0.88, 0.12), y = -1.0, blur = 5.0),
    ]

  theme[srTextField, StyleTextColor] = initColor(0.84, 0.98, 1.0, 0.98)
  theme[srTextField, {ssFocused}, StyleTextColor] = initColor(0.90, 1.0, 1.0, 1.0)
  theme[srTextField, {ssDisabled}, StyleTextColor] = styleToken("disabled.text.color")
  theme[srTextView, StyleTextColor] = initColor(0.84, 0.98, 1.0, 0.98)
  theme[srTextView, {ssFocused}, StyleTextColor] = initColor(0.90, 1.0, 1.0, 1.0)
  theme[srTextView, {ssDisabled}, StyleTextColor] = styleToken("disabled.text.color")

  theme[srSlider, StyleFill] = linear(
    initColor(0.10, 0.00, 0.22, 0.90),
    initColor(0.22, 0.02, 0.38, 0.76),
    initColor(0.03, 0.14, 0.32, 0.82),
    fgaY,
    104'u8,
  )
  theme[srSlider, StyleHighlightFill] = linear(
    initColor(1.0, 0.06, 0.88, 0.90),
    initColor(0.42, 0.04, 0.92, 0.78),
    initColor(0.08, 0.92, 1.0, 0.64),
    fgaDiagTLBR,
    108'u8,
  )
  theme[srSlider, StyleKnobFill] = linear(
    initColor(0.34, 0.02, 0.50, 0.92),
    initColor(0.18, 0.00, 0.34, 0.86),
    initColor(0.04, 0.60, 0.82, 0.54),
    fgaDiagTLBR,
    112'u8,
  )
  theme[srSlider, StyleBorderColor] = initColor(0.92, 0.05, 1.0, 0.76)
  theme[srSlider, StyleFocusRingColor] = initColor(0.16, 0.94, 1.0, 0.84)
  theme[srSlider, StyleKnobBorderColor] = initColor(0.24, 0.96, 1.0, 0.92)
  theme[srSlider, StyleKnobShadows] =
    @[
      dropShadow(initColor(1.0, 0.00, 0.88, 0.22), y = 1.0, blur = 7.0),
      insetShadow(initColor(0.30, 0.96, 1.0, 0.24), y = 1.0, blur = 3.0),
      insetShadow(initColor(0.0, 0.0, 0.0, 0.30), y = -1.0, blur = 3.0),
    ]

  theme[srComboBox, StyleIndicatorFill] = linear(
    initColor(0.34, 0.02, 0.50, 0.88),
    initColor(0.20, 0.00, 0.34, 0.84),
    initColor(0.08, 0.00, 0.18, 0.90),
    fgaY,
    104'u8,
  )
  theme[srComboBox, {ssHighlighted}, StyleIndicatorFill] = linear(
    initColor(0.58, 0.05, 0.76, 0.90),
    initColor(0.30, 0.02, 0.46, 0.86),
    initColor(0.10, 0.00, 0.22, 0.92),
    fgaY,
    104'u8,
  )
  theme[srComboBox, {ssOpen}, StyleIndicatorFill] = linear(
    initColor(0.58, 0.05, 0.76, 0.90),
    initColor(0.30, 0.02, 0.46, 0.86),
    initColor(0.10, 0.00, 0.22, 0.92),
    fgaY,
    104'u8,
  )

  theme["choice.indicator.fill"] = linear(
    initColor(0.18, 0.02, 0.32, 0.92),
    initColor(0.30, 0.04, 0.46, 0.70),
    initColor(0.06, 0.00, 0.18, 0.92),
    fgaY,
    108'u8,
  )
  theme["choice.indicator.fill.highlighted"] = linear(
    initColor(0.32, 0.04, 0.48, 0.94),
    initColor(0.42, 0.06, 0.58, 0.76),
    initColor(0.08, 0.00, 0.22, 0.94),
    fgaY,
    108'u8,
  )
  theme["choice.indicator.fill.selected"] = linear(
    initColor(0.95, 0.06, 0.92, 0.94),
    initColor(0.30, 0.08, 0.92, 0.86),
    initColor(0.08, 0.88, 1.0, 0.72),
    fgaDiagTLBR,
    112'u8,
  )
  theme["choice.indicator.fill.selected.highlighted"] = linear(
    initColor(1.0, 0.20, 0.96, 0.96),
    initColor(0.42, 0.12, 1.0, 0.88),
    initColor(0.16, 0.94, 1.0, 0.78),
    fgaDiagTLBR,
    112'u8,
  )
  theme["choice.indicator.border.color"] = initColor(0.24, 0.94, 1.0, 0.90)
  theme["choice.indicator.border.color.highlighted"] = initColor(1.0, 0.24, 0.96, 0.94)
  theme["choice.indicator.border.color.selected"] = initColor(1.0, 0.30, 0.92, 0.98)
  theme["choice.mark.color"] = initColor(1.0, 0.92, 0.26, 1.0)

  for role in [srCheckBox, srRadioButton]:
    theme[role, StyleBoxShadows] =
      @[
        dropShadow(initColor(0.96, 0.00, 1.0, 0.18), y = 1.0, blur = 5.0),
        insetShadow(initColor(0.32, 0.96, 1.0, 0.24), y = 1.0, blur = 2.6),
        insetShadow(initColor(0.0, 0.0, 0.0, 0.30), y = -1.0, blur = 3.2),
      ]
    theme[role, {ssSelected}, StyleBoxShadows] =
      @[
        dropShadow(initColor(0.96, 0.00, 1.0, 0.28), y = 1.0, blur = 7.0),
        insetShadow(initColor(1.0, 0.86, 0.42, 0.30), y = 1.0, blur = 3.0),
        insetShadow(initColor(0.0, 0.0, 0.0, 0.24), y = -1.0, blur = 3.2),
      ]

proc initSynthwave83Theme*(): Theme =
  result = initTheme()
  result.installSynthwave83Tokens()
  result.installSynthwave83ControlStyles()
  result.installSynthwave83Labels()
  result.installSynthwave83Tables()
  result.installSynthwave83RetroPalette()
  result.installSynthwave83ReferencePass()
  result.installSynthwave83VaporwavePass()
  result.installSynthwave83ReadabilityPass()

registerThemeFactory("synthwave83", initSynthwave83Theme)
registerThemeFactory("synthwave", initSynthwave83Theme)
