import ./themecore
import std/tables
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
    insetShadow(initColor(1.0, 1.0, 1.0, 0.30), x = 2.0, y = 1.0, blur = 5.0),
    insetShadow(initColor(0.0, 0.0, 0.0, 0.24), x = -1.0, y = -2.0, blur = 5.0),
  ]

func highlightedButtonShadows(): seq[BoxShadow] =
  @[
    insetShadow(initColor(1.0, 1.0, 1.0, 0.12), x = 2.0, y = 1.0, blur = 3.0),
    insetShadow(initColor(0.0, 0.0, 0.0, 0.38), x = -1.0, y = -2.0, blur = 9.0),
  ]

func aquaButtonFill(): Fill =
  linear(initColor(0.48, 0.48, 0.47, 1.0), initColor(0.93, 0.93, 0.92, 1.0), fgaY)

func aquaButtonPressedFill(): Fill =
  linear(
    initColor(0.53, 0.54, 0.55, 1.0),
    initColor(0.72, 0.74, 0.77, 1.0),
    initColor(0.55, 0.57, 0.61, 1.0),
    fgaY,
    112'u8,
  )

func aquaAccentButtonFill(): Fill =
  linear(initColor(0.04, 0.13, 0.57, 1.0), initColor(0.20, 0.62, 0.98, 1.0), fgaY)

func aquaAccentButtonPressedFill(): Fill =
  linear(
    initColor(0.10, 0.40, 0.88, 1.0),
    initColor(0.02, 0.24, 0.68, 1.0),
    initColor(0.01, 0.12, 0.42, 1.0),
    fgaY,
    104'u8,
  )

func aquaButtonDisabledFill(): Fill =
  linear(initColor(0.90, 0.91, 0.93, 1.0), initColor(0.76, 0.78, 0.82, 1.0), fgaY)

func aquaChoiceFill(): Fill =
  linear(initColor(1.0, 1.0, 0.99, 1.0), initColor(0.84, 0.85, 0.83, 1.0), fgaY)

func aquaChoiceHighlightedFill(): Fill =
  linear(initColor(1.0, 1.0, 1.0, 1.0), initColor(0.78, 0.90, 1.0, 1.0), fgaY)

func aquaChoiceSelectedFill(): Fill =
  linear(initColor(0.48, 0.91, 1.0, 1.0), initColor(0.0, 0.49, 0.93, 1.0), fgaDiagTLBR)

func aquaChoiceSelectedHighlightedFill(): Fill =
  linear(
    initColor(0.45, 0.80, 1.0, 1.0),
    initColor(0.0, 0.32, 0.86, 1.0),
    initColor(0.0, 0.18, 0.58, 1.0),
    fgaY,
    104'u8,
  )

func aquaTextFieldFill(): Fill =
  linear(initColor(1.0, 1.0, 1.0, 1.0), initColor(0.95, 0.98, 1.0, 1.0), fgaY)

func aquaComboItemHighlightFill(): Fill =
  linear(initColor(0.90, 0.96, 1.0, 1.0), initColor(0.72, 0.87, 1.0, 1.0), fgaY)

func aquaComboItemSelectedFill(): Fill =
  linear(
    initColor(0.45, 0.75, 1.0, 1.0),
    initColor(0.10, 0.45, 0.95, 1.0),
    initColor(0.02, 0.26, 0.76, 1.0),
    fgaY,
    104'u8,
  )

func aquaComboItemSelectedHighlightedFill(): Fill =
  linear(
    initColor(0.20, 0.57, 0.98, 1.0),
    initColor(0.03, 0.33, 0.82, 1.0),
    initColor(0.01, 0.18, 0.58, 1.0),
    fgaY,
    104'u8,
  )

func aquaButtonShadows(): seq[BoxShadow] =
  @[
    dropShadow(initColor(0.0, 0.0, 0.0, 0.17), y = 2.0, blur = 4.0),
    insetShadow(initColor(1.0, 1.0, 1.0, 0.72), y = 1.0, blur = 2.0),
    insetShadow(initColor(0.55, 0.86, 1.0, 0.17), y = 2.0, blur = 4.0),
    insetShadow(initColor(0.0, 0.05, 0.18, 0.15), y = -2.0, blur = 5.0),
  ]

func aquaPressedButtonShadows(): seq[BoxShadow] =
  @[
    dropShadow(initColor(0.0, 0.0, 0.0, 0.13), y = 1.0, blur = 3.0),
    insetShadow(initColor(0.0, 0.05, 0.20, 0.23), y = 2.0, blur = 5.0),
    insetShadow(initColor(1.0, 1.0, 1.0, 0.20), y = -1.0, blur = 3.0),
  ]

func aquaInsetControlShadows(): seq[BoxShadow] =
  @[
    insetShadow(initColor(0.0, 0.05, 0.18, 0.20), y = 1.0, blur = 3.0),
    insetShadow(initColor(1.0, 1.0, 1.0, 0.80), y = -1.0, blur = 2.0),
  ]

proc initTheme*(): Theme =
  result.tokens = newStyleTokenStore()
  result.chromes = initTable[string, Chrome]()
  result[AccentToken] = styleColor(initColor(0.10, 0.48, 0.96, 1.0))
  result[AccentPressedToken] = styleColor(initColor(0.02, 0.25, 0.70, 1.0))
  result[DisabledFillToken] = styleColor(initColor(0.64, 0.68, 0.74, 1.0))
  result[DisabledTextColorToken] = styleColor(initColor(0.90, 0.92, 0.95, 1.0))
  result[FocusRingColorToken] = styleColor(initColor(0.34, 0.66, 1.0, 0.72))

  result[ButtonFillToken] = aquaButtonFill()
  result[ButtonHighlightedFillToken] = aquaButtonPressedFill()
  result[ButtonDisabledFillToken] = aquaButtonDisabledFill()
  result[ButtonAccentFillToken] = aquaAccentButtonFill()
  result[ButtonAccentHighlightedFillToken] = aquaAccentButtonPressedFill()
  result[ButtonTextColorToken] = styleColor(initColor(0.08, 0.08, 0.07, 0.95))
  result[ButtonDisabledTextColorToken] = styleToken(DisabledTextColorToken)
  result[ButtonBorderColorToken] = styleColor(initColor(0.39, 0.39, 0.38, 0.84))
  result[ButtonHighlightedBorderColorToken] =
    styleColor(initColor(0.30, 0.31, 0.33, 0.92))
  result[ButtonDisabledBorderColorToken] = styleColor(initColor(0.52, 0.57, 0.64, 1.0))
  result[ButtonAccentBorderColorToken] = styleColor(initColor(0.01, 0.11, 0.49, 1.0))
  result[ButtonAccentHighlightedBorderColorToken] =
    styleColor(initColor(0.0, 0.07, 0.32, 1.0))
  result[ButtonFocusRingColorToken] = styleColor(initColor(1.0, 1.0, 1.0, 0.90))
  result[ButtonShadowsToken] = aquaButtonShadows()
  result[ButtonHighlightedShadowsToken] = aquaPressedButtonShadows()
  result[ButtonDisabledShadowsToken] = newSeq[BoxShadow]()

  result[ChoiceIndicatorFillToken] = aquaChoiceFill()
  result[ChoiceIndicatorHighlightedFillToken] = aquaChoiceHighlightedFill()
  result[ChoiceIndicatorDisabledFillToken] = aquaButtonDisabledFill()
  result[ChoiceIndicatorSelectedFillToken] = aquaChoiceSelectedFill()
  result[ChoiceIndicatorSelectedHighlightedFillToken] =
    aquaChoiceSelectedHighlightedFill()
  result[ChoiceIndicatorSelectedDisabledFillToken] = aquaButtonDisabledFill()
  result[ChoiceIndicatorBorderColorToken] = styleColor(initColor(0.42, 0.50, 0.62, 1.0))
  result[ChoiceIndicatorSelectedBorderColorToken] =
    styleColor(initColor(0.0, 0.32, 0.75, 0.96))
  result[ChoiceIndicatorHighlightedBorderColorToken] =
    styleColor(initColor(0.16, 0.38, 0.72, 1.0))
  result[ChoiceIndicatorDisabledBorderColorToken] =
    styleColor(initColor(0.64, 0.68, 0.74, 1.0))
  result[ChoiceMarkColorToken] = styleColor(initColor(0.02, 0.15, 0.30, 0.96))
  result[ChoiceDisabledMarkColorToken] = styleToken(DisabledTextColorToken)
  result[ChoiceTextColorToken] = styleColor(initColor(0.08, 0.09, 0.11, 1.0))
  result[ChoiceDisabledTextColorToken] = styleColor(initColor(0.48, 0.52, 0.58, 1.0))

  result[TextFieldFillToken] = aquaTextFieldFill()
  result[TextFieldBorderColorToken] = styleColor(initColor(0.56, 0.64, 0.76, 1.0))
  result[TextFieldTextColorToken] = styleColor(initColor(0.08, 0.09, 0.11, 1.0))
  result[TextFieldSelectionColorToken] = styleColor(initColor(0.24, 0.56, 1.0, 0.34))
  result[ComboBoxFillToken] = styleToken(TextFieldFillToken)
  result[ComboBoxBorderColorToken] = styleToken(TextFieldBorderColorToken)
  result[ComboBoxOpenBorderColorToken] = styleColor(initColor(0.12, 0.42, 0.86, 1.0))
  result[ComboBoxTextColorToken] = styleToken(TextFieldTextColorToken)
  result[ComboBoxArrowColorToken] = styleColor(initColor(0.10, 0.16, 0.26, 1.0))
  result[ComboBoxItemFillToken] = fill(initColor(1.0, 1.0, 1.0, 1.0))
  result[ComboBoxItemHighlightedFillToken] = aquaComboItemHighlightFill()
  result[ComboBoxItemSelectedFillToken] = aquaComboItemSelectedFill()
  result[ComboBoxItemSelectedHighlightedFillToken] =
    aquaComboItemSelectedHighlightedFill()
  result[ComboBoxItemTextColorToken] = styleColor(initColor(0.08, 0.09, 0.11, 1.0))
  result[ComboBoxItemSelectedTextColorToken] = styleColor(initColor(1.0, 1.0, 1.0, 1.0))
  result[TableViewFillToken] = styleToken(TextFieldFillToken)
  result[TableViewBorderColorToken] = styleToken(TextFieldBorderColorToken)
  result[RowItemFillToken] = styleToken(ComboBoxItemFillToken)
  result[RowItemHighlightedFillToken] = styleToken(ComboBoxItemHighlightedFillToken)
  result[RowItemSelectedFillToken] = styleToken(ComboBoxItemSelectedFillToken)
  result[RowItemSelectedHighlightedFillToken] =
    styleToken(ComboBoxItemSelectedHighlightedFillToken)
  result[RowItemDisabledFillToken] = styleColor(initColor(0.80, 0.82, 0.86, 1.0))
  result[RowItemTextColorToken] = styleToken(ComboBoxItemTextColorToken)
  result[RowItemSelectedTextColorToken] = styleToken(ComboBoxItemSelectedTextColorToken)
  result[RowItemDisabledTextColorToken] = styleColor(initColor(0.32, 0.35, 0.41, 1.0))
  result[RowItemSeparatorColorToken] = styleColor(initColor(0.86, 0.88, 0.91, 1.0))
  result[TabPanelFillToken] = fill(initColor(0.98, 0.98, 0.96, 1.0))
  result[TabPanelBorderColorToken] = styleColor(initColor(0.42, 0.44, 0.48, 1.0))
  result[TabFillToken] = styleColor(initColor(0.70, 0.72, 0.76, 1.0))
  result[TabHighlightedFillToken] = styleColor(initColor(0.58, 0.61, 0.66, 1.0))
  result[TabSelectedFillToken] = styleToken(TabPanelFillToken)
  result[TabDisabledFillToken] = styleColor(initColor(0.78, 0.80, 0.84, 1.0))
  result[TabHighlightFillToken] = styleFill(initColor(1.0, 1.0, 1.0, 0.68))
  result[TabDisabledHighlightFillToken] = styleFill(initColor(1.0, 1.0, 1.0, 0.30))
  result[TabTextColorToken] = styleColor(initColor(0.14, 0.15, 0.18, 1.0))
  result[TabSelectedTextColorToken] = styleColor(initColor(0.07, 0.08, 0.10, 1.0))
  result[TabDisabledTextColorToken] = styleColor(initColor(0.48, 0.50, 0.54, 1.0))
  result[TabBorderColorToken] = styleColor(initColor(0.55, 0.57, 0.62, 1.0))
  result[TabHighlightedBorderColorToken] = styleColor(initColor(0.43, 0.45, 0.50, 1.0))
  result[TabSelectedBorderColorToken] = styleToken(TabPanelBorderColorToken)
  result[TabDisabledBorderColorToken] = styleColor(initColor(0.65, 0.67, 0.70, 1.0))

  result.addRoleRule(
    srButton,
    {},
    styleToken(ButtonFillToken),
    styleToken(ButtonBorderColorToken),
    styleToken(ButtonTextColorToken),
  )
  result.addRoleRule(
    srButton,
    {ssHighlighted},
    styleToken(ButtonHighlightedFillToken),
    styleToken(ButtonHighlightedBorderColorToken),
    styleToken(ButtonTextColorToken),
  )
  result.addRoleRule(
    srButton,
    {ssActive},
    styleToken(ButtonHighlightedFillToken),
    styleToken(ButtonHighlightedBorderColorToken),
    styleToken(ButtonTextColorToken),
  )
  result.addRoleRule(
    srButton,
    {ssDisabled},
    styleToken(ButtonDisabledFillToken),
    styleToken(ButtonDisabledBorderColorToken),
    styleToken(ButtonDisabledTextColorToken),
  )
  result.addRoleRule(
    srButton,
    {ssAccent},
    styleToken(ButtonAccentFillToken),
    styleToken(ButtonAccentBorderColorToken),
    styleToken(ButtonTextColorToken),
  )
  result.addRoleRule(
    srButton,
    {ssAccent, ssHighlighted},
    styleToken(ButtonAccentHighlightedFillToken),
    styleToken(ButtonAccentHighlightedBorderColorToken),
    styleToken(ButtonTextColorToken),
  )
  result.addRoleRule(
    srButton,
    {ssAccent, ssActive},
    styleToken(ButtonAccentHighlightedFillToken),
    styleToken(ButtonAccentHighlightedBorderColorToken),
    styleToken(ButtonTextColorToken),
  )
  result.addRoleRule(
    srButton,
    {ssAccent, ssDisabled},
    styleToken(ButtonDisabledFillToken),
    styleToken(ButtonDisabledBorderColorToken),
    styleToken(ButtonDisabledTextColorToken),
  )
  result[srButton, StyleBorderWidth] = 1.0
  result[srButton, StyleCornerRadius] = 14.0
  result[srButton, StyleTextInsets] = initEdgeInsets(0.0, 8.0)
  result[srButton, StyleTextHighlightColor] = initColor(1.0, 1.0, 1.0, 0.42)
  result[srButton, StyleTextShadowColor] = initColor(0.0, 0.0, 0.0, 0.20)
  result[srButton, StyleMinimumSize] = initSize(0.0, 32.0)
  result[srButton, StyleFocusRingWidth] = 3.0
  result[srButton, StyleFocusRingInset] = -2.0
  result[srButton, StyleFocusRingColor] = styleToken(ButtonFocusRingColorToken)
  result[srButton, StyleBoxShadows] = styleToken(ButtonShadowsToken)
  result[srButton, StyleChrome] = styleKeyword(AquaChromeName)
  result[srButton, {ssHighlighted}, StyleBoxShadows] =
    styleToken(ButtonHighlightedShadowsToken)
  result[srButton, {ssActive}, StyleBoxShadows] =
    styleToken(ButtonHighlightedShadowsToken)
  result[srButton, {ssDisabled}, StyleBoxShadows] =
    styleToken(ButtonDisabledShadowsToken)
  result[srButton, {ssDisabled}, StyleTextHighlightColor] =
    initColor(1.0, 1.0, 1.0, 0.16)
  result[srButton, {ssDisabled}, StyleTextShadowColor] = initColor(0.0, 0.0, 0.0, 0.08)

  result.addRoleRule(
    srTab,
    {},
    styleToken(TabFillToken),
    styleToken(TabBorderColorToken),
    styleToken(TabTextColorToken),
  )
  result.addRoleRule(
    srTab,
    {ssHighlighted},
    styleToken(TabHighlightedFillToken),
    styleToken(TabHighlightedBorderColorToken),
    styleToken(TabTextColorToken),
  )
  result.addRoleRule(
    srTab,
    {ssSelected},
    styleToken(TabSelectedFillToken),
    styleToken(TabSelectedBorderColorToken),
    styleToken(TabSelectedTextColorToken),
  )
  result.addRoleRule(
    srTab,
    {ssDisabled},
    styleToken(TabDisabledFillToken),
    styleToken(TabDisabledBorderColorToken),
    styleToken(TabDisabledTextColorToken),
  )
  result[srTab, StyleHighlightFill] = styleToken(TabHighlightFillToken)
  result[srTab, {ssDisabled}, StyleHighlightFill] =
    styleToken(TabDisabledHighlightFillToken)
  result[srTab, StyleChrome] = styleKeyword(AquaChromeName)
  result[srTabPanel, StyleFill] = styleToken(TabPanelFillToken)
  result[srTabPanel, StyleBorderColor] = styleToken(TabPanelBorderColorToken)
  result[srTabPanel, StyleChrome] = styleKeyword(AquaChromeName)

  for role in [srCheckBox, srRadioButton]:
    let
      radius = if role == srCheckBox: 3.0'f32 else: 8.0'f32
      selectedBorder =
        if role == srCheckBox:
          styleToken(ChoiceIndicatorSelectedBorderColorToken)
        else:
          styleToken(ChoiceIndicatorBorderColorToken)
    result.addChoiceRule(
      role,
      {},
      styleToken(ChoiceIndicatorFillToken),
      styleToken(ChoiceIndicatorBorderColorToken),
      styleToken(ChoiceMarkColorToken),
      styleToken(ChoiceTextColorToken),
    )
    result.addChoiceRule(
      role,
      {ssHighlighted},
      styleToken(ChoiceIndicatorHighlightedFillToken),
      styleToken(ChoiceIndicatorHighlightedBorderColorToken),
      styleToken(ChoiceMarkColorToken),
      styleToken(ChoiceTextColorToken),
    )
    result.addChoiceRule(
      role,
      {ssSelected},
      styleToken(ChoiceIndicatorSelectedFillToken),
      selectedBorder,
      styleToken(ChoiceMarkColorToken),
      styleToken(ChoiceTextColorToken),
    )
    result.addChoiceRule(
      role,
      {ssSelected, ssHighlighted},
      styleToken(ChoiceIndicatorSelectedHighlightedFillToken),
      selectedBorder,
      styleToken(ChoiceMarkColorToken),
      styleToken(ChoiceTextColorToken),
    )
    result.addChoiceRule(
      role,
      {ssDisabled},
      styleToken(ChoiceIndicatorDisabledFillToken),
      styleToken(ChoiceIndicatorDisabledBorderColorToken),
      styleToken(ChoiceDisabledMarkColorToken),
      styleToken(ChoiceDisabledTextColorToken),
    )
    result.addChoiceRule(
      role,
      {ssSelected, ssDisabled},
      styleToken(ChoiceIndicatorSelectedDisabledFillToken),
      styleToken(ChoiceIndicatorDisabledBorderColorToken),
      styleToken(ChoiceDisabledMarkColorToken),
      styleToken(ChoiceDisabledTextColorToken),
    )
    result[role, StyleIndicatorSize] = 16.0
    result[role, StyleBorderWidth] = 1.0
    result[role, StyleCornerRadius] = radius
    result[role, StyleIndicatorSpacing] = 7.0
    result[role, StyleTextInsets] = initEdgeInsets(0.0, 2.0)
    result[role, StyleMinimumSize] = initSize(0.0, 20.0)
    result[role, StyleFocusRingWidth] = 3.0
    result[role, StyleFocusRingInset] = 2.0
    result[role, StyleFocusRingColor] = styleToken(FocusRingColorToken)
    result[role, StyleBoxShadows] = aquaInsetControlShadows()
    result[role, StyleChrome] = styleKeyword(AquaChromeName)

  result[srTextField, StyleFill] = styleToken(TextFieldFillToken)
  result[srTextField, StyleBorderColor] = styleToken(TextFieldBorderColorToken)
  result[srTextField, StyleBorderWidth] = 1.0
  result[srTextField, StyleCornerRadius] = 6.0
  result[srTextField, StyleTextInsets] = initEdgeInsets(0.0, 6.0)
  result[srTextField, StyleMinimumSize] = initSize(80.0, 24.0)
  result[srTextField, StyleSelectionColor] = styleToken(TextFieldSelectionColorToken)
  result[srTextField, StyleFocusRingWidth] = 3.0
  result[srTextField, StyleFocusRingInset] = -2.0
  result[srTextField, StyleFocusRingColor] = styleToken(FocusRingColorToken)
  result[srTextField, StyleBoxShadows] = aquaInsetControlShadows()

  result.addLabelRule(
    LabelStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(0.09, 0.12, 0.18, 1.0),
    initEdgeInsets(0.0),
    initSize(0.0, 18.0),
  )
  result.addLabelRule(
    LabelTitleStyleClass,
    linear(initColor(0.94, 0.98, 1.0, 1.0), initColor(0.84, 0.91, 0.98, 1.0), fgaY),
    initColor(0.62, 0.70, 0.84, 1.0),
    1.0,
    6.0,
    initColor(0.09, 0.14, 0.26, 1.0),
    initEdgeInsets(0.0, 12.0),
    initSize(0.0, 28.0),
  )
  result.addLabelRule(
    LabelHeadingStyleClass,
    linear(initColor(0.90, 0.95, 1.0, 1.0), initColor(0.78, 0.86, 0.96, 1.0), fgaY),
    initColor(0.74, 0.82, 0.93, 1.0),
    1.0,
    5.0,
    initColor(0.10, 0.18, 0.32, 1.0),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  result.addLabelRule(
    LabelStatusStyleClass,
    linear(initColor(0.94, 0.99, 0.95, 1.0), initColor(0.84, 0.94, 0.87, 1.0), fgaY),
    initColor(0.68, 0.82, 0.72, 1.0),
    1.0,
    6.0,
    initColor(0.09, 0.27, 0.18, 1.0),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  result.addLabelRule(
    LabelFormStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(0.10, 0.14, 0.22, 1.0),
    initEdgeInsets(0.0, 2.0),
    initSize(0.0, 18.0),
  )

  result.addRoleRule(
    srComboBox,
    {},
    styleToken(ComboBoxFillToken),
    styleToken(ComboBoxBorderColorToken),
    styleToken(ComboBoxTextColorToken),
  )
  result.addRoleRule(
    srComboBox,
    {ssOpen},
    styleToken(ComboBoxFillToken),
    styleToken(ComboBoxOpenBorderColorToken),
    styleToken(ComboBoxTextColorToken),
  )
  result.addRoleRule(
    srComboBox,
    {ssDisabled},
    styleToken(TextFieldFillToken),
    styleToken(TextFieldBorderColorToken),
    styleToken(DisabledTextColorToken),
  )
  result[srComboBox, StyleBorderWidth] = 1.0
  result[srComboBox, StyleCornerRadius] = 6.0
  result[srComboBox, StyleTextInsets] = initEdgeInsets(0.0, 8.0)
  result[srComboBox, StyleFocusRingWidth] = 3.0
  result[srComboBox, StyleFocusRingInset] = -2.0
  result[srComboBox, StyleFocusRingColor] = styleToken(FocusRingColorToken)
  result[srComboBox, StyleIndicatorSize] = 24.0
  result[srComboBox, StyleMinimumSize] = initSize(90.0, 24.0)
  result[srComboBox, StyleMarkColor] = styleToken(ComboBoxArrowColorToken)
  result[srComboBox, StyleBoxShadows] = aquaInsetControlShadows()
  result[srComboBox, StyleChrome] = styleKeyword(AquaChromeName)

  result.addRoleRule(
    srComboBoxItem,
    {},
    styleToken(ComboBoxItemFillToken),
    styleColor(initColor(0.0, 0.0, 0.0, 0.0)),
    styleToken(ComboBoxItemTextColorToken),
  )
  result.addRoleRule(
    srComboBoxItem,
    {ssHovered},
    styleToken(ComboBoxItemHighlightedFillToken),
    styleColor(initColor(0.0, 0.0, 0.0, 0.0)),
    styleToken(ComboBoxItemTextColorToken),
  )
  result.addRoleRule(
    srComboBoxItem,
    {ssSelected},
    styleToken(ComboBoxItemSelectedFillToken),
    styleColor(initColor(0.0, 0.0, 0.0, 0.0)),
    styleToken(ComboBoxItemSelectedTextColorToken),
  )
  result.addRoleRule(
    srComboBoxItem,
    {ssSelected, ssHovered},
    styleToken(ComboBoxItemSelectedHighlightedFillToken),
    styleColor(initColor(0.0, 0.0, 0.0, 0.0)),
    styleToken(ComboBoxItemSelectedTextColorToken),
  )
  result[srComboBoxItem, StyleBorderWidth] = 0.0
  result[srComboBoxItem, StyleCornerRadius] = 0.0
  result[srComboBoxItem, StyleTextInsets] = initEdgeInsets(0.0, 6.0)
  result[srComboBoxItem, StyleMinimumSize] = initSize(0.0, 22.0)

  result[srTableView, StyleFill] = styleToken(TableViewFillToken)
  result[srTableView, StyleBorderColor] = styleToken(TableViewBorderColorToken)
  result[srTableView, StyleBorderWidth] = 1.0
  result[srTableView, StyleCornerRadius] = 6.0
  result[srTableView, StyleMinimumSize] = initSize(120.0, 24.0)
  result[srTableView, StyleFocusRingWidth] = 3.0
  result[srTableView, StyleFocusRingInset] = 2.0
  result[srTableView, StyleFocusRingColor] = styleToken(FocusRingColorToken)
  result[srTableView, StyleBoxShadows] = aquaInsetControlShadows()

  result.addRoleRule(
    srRowItem,
    {},
    styleToken(RowItemFillToken),
    styleToken(RowItemSeparatorColorToken),
    styleToken(RowItemTextColorToken),
  )
  result.addRoleRule(
    srRowItem,
    {ssHovered},
    styleToken(RowItemHighlightedFillToken),
    styleToken(RowItemSeparatorColorToken),
    styleToken(RowItemTextColorToken),
  )
  result.addRoleRule(
    srRowItem,
    {ssHighlighted},
    styleToken(RowItemHighlightedFillToken),
    styleToken(RowItemSeparatorColorToken),
    styleToken(RowItemTextColorToken),
  )
  result.addRoleRule(
    srRowItem,
    {ssPressed},
    styleToken(RowItemHighlightedFillToken),
    styleToken(RowItemSeparatorColorToken),
    styleToken(RowItemTextColorToken),
  )
  result.addRoleRule(
    srRowItem,
    {ssDisabled},
    styleToken(RowItemDisabledFillToken),
    styleToken(RowItemSeparatorColorToken),
    styleToken(RowItemDisabledTextColorToken),
  )
  result.addRoleRule(
    srRowItem,
    {ssSelected},
    styleToken(RowItemSelectedFillToken),
    styleToken(RowItemSeparatorColorToken),
    styleToken(RowItemSelectedTextColorToken),
  )
  result.addRoleRule(
    srRowItem,
    {ssSelected, ssHovered},
    styleToken(RowItemSelectedHighlightedFillToken),
    styleToken(RowItemSeparatorColorToken),
    styleToken(RowItemSelectedTextColorToken),
  )
  result.addRoleRule(
    srRowItem,
    {ssSelected, ssHighlighted},
    styleToken(RowItemSelectedHighlightedFillToken),
    styleToken(RowItemSeparatorColorToken),
    styleToken(RowItemSelectedTextColorToken),
  )
  result.addRoleRule(
    srRowItem,
    {ssSelected, ssPressed},
    styleToken(RowItemSelectedHighlightedFillToken),
    styleToken(RowItemSeparatorColorToken),
    styleToken(RowItemSelectedTextColorToken),
  )
  result[srRowItem, StyleBorderWidth] = 0.0
  result[srRowItem, StyleCornerRadius] = 0.0
  result[srRowItem, StyleTextInsets] = initEdgeInsets(0.0, 6.0)
  result[srRowItem, StyleMinimumSize] = initSize(0.0, 22.0)
  result.installThemeExtensions()

proc initBannerTheme*(): Theme =
  result = initTheme()
  result[srButton, StyleChrome] = styleKeyword(DefaultChromeName)
  result[srCheckBox, StyleChrome] = styleKeyword(DefaultChromeName)
  result[srRadioButton, StyleChrome] = styleKeyword(DefaultChromeName)
  result[srComboBox, StyleChrome] = styleKeyword(DefaultChromeName)
  result[srButton, StyleTextHighlightColor] = initColor(0.0, 0.0, 0.0, 0.0)
  result[srButton, StyleTextShadowColor] = initColor(0.0, 0.0, 0.0, 0.0)
  result[srTab, StyleChrome] = styleKeyword(DefaultChromeName)
  result[srTabPanel, StyleChrome] = styleKeyword(DefaultChromeName)

  result[AccentToken] = initColor(0.89, 0.38, 0.21, 1.0)
  result[AccentPressedToken] = initColor(0.62, 0.24, 0.14, 1.0)
  result[DisabledFillToken] = initColor(0.52, 0.50, 0.45, 1.0)
  result[DisabledTextColorToken] = initColor(0.94, 0.91, 0.86, 1.0)
  result[FocusRingColorToken] = initColor(0.31, 0.58, 0.54, 0.60)
  result[RowItemSeparatorColorToken] = initColor(0.74, 0.70, 0.63, 1.0)
  result[TabPanelFillToken] = initColor(1.0, 0.97, 0.94, 1.0)
  result[TabPanelBorderColorToken] = initColor(0.84, 0.80, 0.75, 1.0)
  result[TabFillToken] = initColor(0.86, 0.82, 0.75, 1.0)
  result[TabHighlightedFillToken] = initColor(0.78, 0.70, 0.62, 1.0)
  result[TabSelectedFillToken] = styleToken(TabPanelFillToken)
  result[TabDisabledFillToken] = initColor(0.82, 0.78, 0.72, 1.0)
  result[TabHighlightFillToken] = initColor(1.0, 0.97, 0.94, 0.0)
  result[TabDisabledHighlightFillToken] = initColor(1.0, 0.97, 0.94, 0.0)
  result[TabTextColorToken] = initColor(0.11, 0.10, 0.10, 1.0)
  result[TabSelectedTextColorToken] = initColor(0.11, 0.10, 0.10, 1.0)
  result[TabDisabledTextColorToken] = initColor(0.48, 0.45, 0.40, 1.0)
  result[TabBorderColorToken] = initColor(0.54, 0.49, 0.42, 1.0)
  result[TabHighlightedBorderColorToken] = initColor(0.42, 0.36, 0.30, 1.0)
  result[TabSelectedBorderColorToken] = styleToken(TabPanelBorderColorToken)
  result[TabDisabledBorderColorToken] = initColor(0.70, 0.65, 0.58, 1.0)

  result[ButtonFillToken] = styleToken(AccentToken)
  result[ButtonHighlightedFillToken] = styleToken(AccentPressedToken)
  result[ButtonDisabledFillToken] = styleToken(DisabledFillToken)
  result[ButtonAccentFillToken] = styleToken(AccentToken)
  result[ButtonAccentHighlightedFillToken] = styleToken(AccentPressedToken)
  result[ButtonTextColorToken] = initColor(1.0, 0.97, 0.94, 1.0)
  result[ButtonBorderColorToken] = initColor(0.18, 0.12, 0.08, 1.0)
  result[ButtonHighlightedBorderColorToken] = initColor(0.12, 0.08, 0.05, 1.0)
  result[ButtonDisabledBorderColorToken] = initColor(0.40, 0.37, 0.33, 1.0)
  result[ButtonAccentBorderColorToken] = initColor(0.18, 0.12, 0.08, 1.0)
  result[ButtonAccentHighlightedBorderColorToken] = initColor(0.12, 0.08, 0.05, 1.0)
  result[ButtonFocusRingColorToken] = initColor(1.0, 0.97, 0.94, 0.90)
  result[ButtonShadowsToken] = defaultButtonShadows()
  result[ButtonHighlightedShadowsToken] = highlightedButtonShadows()

  result[ChoiceIndicatorFillToken] = initColor(1.0, 0.97, 0.94, 1.0)
  result[ChoiceIndicatorHighlightedFillToken] = initColor(0.98, 0.93, 0.84, 1.0)
  result[ChoiceIndicatorDisabledFillToken] = initColor(0.86, 0.82, 0.75, 1.0)
  result[ChoiceIndicatorSelectedFillToken] = styleToken(AccentToken)
  result[ChoiceIndicatorSelectedHighlightedFillToken] = styleToken(AccentPressedToken)
  result[ChoiceIndicatorSelectedDisabledFillToken] = styleToken(DisabledFillToken)
  result[ChoiceIndicatorBorderColorToken] = initColor(0.54, 0.49, 0.42, 1.0)
  result[ChoiceIndicatorHighlightedBorderColorToken] = initColor(0.26, 0.51, 0.47, 1.0)
  result[ChoiceIndicatorDisabledBorderColorToken] = initColor(0.70, 0.65, 0.58, 1.0)
  result[ChoiceMarkColorToken] = initColor(1.0, 0.97, 0.94, 1.0)
  result[ChoiceTextColorToken] = initColor(0.11, 0.10, 0.10, 1.0)
  result[ChoiceDisabledTextColorToken] = initColor(0.48, 0.45, 0.40, 1.0)

  result[TextFieldFillToken] = initColor(1.0, 0.97, 0.94, 1.0)
  result[TextFieldBorderColorToken] = initColor(0.84, 0.80, 0.75, 1.0)
  result[TextFieldTextColorToken] = initColor(0.11, 0.10, 0.10, 1.0)
  result[TextFieldSelectionColorToken] = initColor(0.31, 0.58, 0.54, 0.32)

  result[ComboBoxOpenBorderColorToken] = initColor(0.31, 0.58, 0.54, 1.0)
  result[ComboBoxArrowColorToken] = initColor(0.16, 0.15, 0.15, 1.0)
  result[ComboBoxItemFillToken] = initColor(1.0, 0.97, 0.94, 1.0)
  result[ComboBoxItemHighlightedFillToken] = initColor(0.99, 0.93, 0.84, 1.0)
  result[ComboBoxItemSelectedFillToken] = initColor(0.26, 0.51, 0.47, 1.0)
  result[ComboBoxItemSelectedHighlightedFillToken] = initColor(0.19, 0.38, 0.35, 1.0)
  result[ComboBoxItemTextColorToken] = initColor(0.11, 0.10, 0.10, 1.0)
  result[ComboBoxItemSelectedTextColorToken] = initColor(1.0, 0.97, 0.94, 1.0)

proc initAppearance*(theme: Theme): Appearance =
  Appearance(theme: theme.clone)

proc initAppearance*(): Appearance =
  initAppearance(initTheme())
