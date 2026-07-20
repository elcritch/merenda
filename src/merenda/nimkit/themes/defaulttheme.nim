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
    shadows: seq[BoxShadow] = @[],
    chrome = "",
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
  theme[selector, StyleBoxShadows] = shadows
  if chrome.len > 0:
    theme[selector, StyleChrome] = styleKeyword(chrome)

func rgbaColor(r, g, b, a: int): Color =
  color(
    r.float32 / 255.0'f32,
    g.float32 / 255.0'f32,
    b.float32 / 255.0'f32,
    a.float32 / 255.0'f32,
  )

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
    rgbaColor(86, 167, 233, 163),
    rgbaColor(59, 166, 240, 141),
    rgbaColor(62, 160, 229, 134),
    fgaY,
    132'u8,
  )

func aquaButtonHoverFill(): Fill =
  linear(
    rgbaColor(128, 224, 255, 210),
    rgbaColor(82, 198, 252, 188),
    rgbaColor(92, 196, 246, 178),
    fgaY,
    132'u8,
  )

func aquaButtonPressedFill(): Fill =
  linear(
    rgbaColor(68, 146, 211, 163),
    rgbaColor(42, 140, 213, 141),
    rgbaColor(37, 124, 197, 134),
    fgaY,
    132'u8,
  )

func aquaAccentButtonFill(): Fill =
  aquaButtonFill()

func aquaAccentButtonHoverFill(): Fill =
  aquaButtonHoverFill()

func aquaAccentButtonPressedFill(): Fill =
  aquaButtonPressedFill()

func aquaWindowBackgroundFill(): Fill =
  linear(rgbaColor(239, 240, 239, 255), rgbaColor(211, 214, 214, 255), fgaY)

func aquaButtonDisabledFill(): Fill =
  linear(
    rgbaColor(86, 167, 233, 68),
    rgbaColor(59, 166, 240, 59),
    rgbaColor(62, 160, 229, 56),
    fgaY,
    132'u8,
  )

func aquaChoiceFill(): Fill =
  linear(rgbaColor(255, 255, 255, 255), rgbaColor(214, 215, 212, 255), fgaY)

func aquaChoiceHighlightedFill(): Fill =
  linear(rgbaColor(255, 255, 255, 255), rgbaColor(235, 235, 232, 255), fgaY)

func aquaChoiceSelectedFill(): Fill =
  linear(rgbaColor(122, 232, 255, 255), rgbaColor(0, 124, 238, 255), fgaDiagTLBR)

func aquaChoiceSelectedHighlightedFill(): Fill =
  linear(
    rgbaColor(120, 230, 255, 255),
    rgbaColor(38, 171, 251, 255),
    rgbaColor(0, 112, 224, 255),
    fgaY,
    104'u8,
  )

func aquaTextFieldFill(): Fill =
  linear(
    rgbaColor(255, 255, 255, 222),
    rgbaColor(236, 247, 255, 208),
    rgbaColor(197, 222, 242, 188),
    fgaY,
    116'u8,
  )

func aquaSliderKnobFill(): Fill =
  linear(
    rgbaColor(255, 255, 255, 250),
    rgbaColor(238, 248, 255, 246),
    rgbaColor(204, 226, 244, 240),
    fgaY,
    116'u8,
  )

func aquaSliderProgressFill(): Fill =
  linear(
    rgbaColor(86, 167, 233, 215),
    rgbaColor(59, 166, 240, 202),
    rgbaColor(62, 160, 229, 198),
    fgaY,
    132'u8,
  )

func aquaComboBoxFill(): Fill =
  linear(
    rgbaColor(255, 255, 255, 226),
    rgbaColor(238, 242, 244, 214),
    rgbaColor(196, 207, 212, 196),
    fgaY,
    92'u8,
  )

func aquaDocumentTabBarFill(): Fill =
  linear(color(0.88, 0.93, 1.0, 0.44), color(0.58, 0.68, 0.82, 0.34), fgaY)

func aquaDocumentTabFill(): Fill =
  linear(
    color(0.88, 0.93, 0.99, 0.92),
    color(0.70, 0.80, 0.92, 0.90),
    color(0.54, 0.66, 0.82, 0.88),
    fgaY,
    112'u8,
  )

func aquaDocumentTabHighlightedFill(): Fill =
  linear(
    color(0.94, 0.97, 1.0, 0.94),
    color(0.76, 0.86, 0.96, 0.92),
    color(0.60, 0.72, 0.88, 0.90),
    fgaY,
    112'u8,
  )

func aquaSelectedDocumentTabFill(): Fill =
  linear(
    color(0.99, 1.0, 1.0, 0.98),
    color(0.88, 0.94, 1.0, 0.96),
    color(0.74, 0.84, 0.96, 0.94),
    fgaY,
    112'u8,
  )

func aquaPressedDocumentTabFill(): Fill =
  linear(color(0.66, 0.76, 0.90, 0.94), color(0.46, 0.58, 0.76, 0.92), fgaY)

func aquaTitleLabelFill(): Fill =
  linear(
    rgbaColor(255, 255, 255, 218),
    rgbaColor(232, 248, 255, 166),
    rgbaColor(62, 180, 250, 142),
    fgaY,
    78'u8,
  )

func aquaHeadingLabelFill(): Fill =
  linear(
    rgbaColor(255, 255, 255, 206),
    rgbaColor(222, 244, 255, 154),
    rgbaColor(58, 168, 240, 132),
    fgaY,
    82'u8,
  )

func aquaStatusLabelFill(): Fill =
  linear(
    rgbaColor(255, 255, 255, 212),
    rgbaColor(224, 255, 238, 162),
    rgbaColor(58, 214, 128, 138),
    fgaY,
    78'u8,
  )

func aquaComboItemHighlightFill(): Fill =
  linear(rgbaColor(230, 245, 255, 212), rgbaColor(184, 222, 255, 212), fgaY)

func aquaComboItemSelectedFill(): Fill =
  linear(
    rgbaColor(46, 128, 230, 217),
    rgbaColor(0, 71, 184, 217),
    rgbaColor(0, 31, 117, 217),
    fgaY,
    104'u8,
  )

func aquaComboItemSelectedHighlightedFill(): Fill =
  linear(
    rgbaColor(31, 102, 219, 222),
    rgbaColor(0, 56, 168, 222),
    rgbaColor(0, 20, 97, 222),
    fgaY,
    104'u8,
  )

func aquaRowItemSelectedFill(): Fill =
  linear(
    rgbaColor(98, 160, 236, 217),
    rgbaColor(64, 117, 202, 217),
    rgbaColor(64, 87, 152, 217),
    fgaY,
    104'u8,
  )

func aquaRowItemSelectedHighlightedFill(): Fill =
  linear(
    rgbaColor(87, 140, 228, 222),
    rgbaColor(64, 106, 190, 222),
    rgbaColor(64, 79, 137, 222),
    fgaY,
    104'u8,
  )

func aquaComboArrowFill(): Fill =
  linear(
    rgbaColor(125, 230, 255, 230),
    rgbaColor(38, 171, 251, 224),
    rgbaColor(0, 112, 224, 226),
    fgaY,
    104'u8,
  )

func aquaScrollerTrackFill(): Fill =
  linear(
    rgbaColor(255, 255, 255, 118),
    rgbaColor(225, 238, 249, 96),
    rgbaColor(183, 204, 225, 88),
    fgaY,
    116'u8,
  )

func aquaInsetControlShadows(): seq[BoxShadow] =
  @[
    insetShadow(rgbaColor(0, 42, 112, 38), y = 1.0, blur = 3.0),
    insetShadow(rgbaColor(255, 255, 255, 132), y = -1.0, blur = 2.4),
  ]

func aquaChoiceIndicatorShadows(): seq[BoxShadow] =
  @[
    dropShadow(rgbaColor(0, 0, 0, 36), y = 1.0, blur = 2.5),
    insetShadow(rgbaColor(0, 0, 0, 32), y = 1.0, blur = 2.5),
    insetShadow(rgbaColor(255, 255, 255, 112), y = -1.0, blur = 2.0),
  ]

func aquaComboBoxShadows(): seq[BoxShadow] =
  @[
    insetShadow(rgbaColor(40, 54, 148, 46), y = 1.0, blur = 3.0),
    insetShadow(rgbaColor(255, 255, 255, 138), y = -1.0, blur = 2.4),
    insetShadow(rgbaColor(42, 50, 138, 30), x = 1.0, blur = 2.2),
    insetShadow(rgbaColor(255, 255, 255, 58), x = -1.0, blur = 1.4),
  ]

func aquaKnobShadows(): seq[BoxShadow] =
  @[
    insetShadow(rgbaColor(255, 255, 255, 162), y = 1.0, blur = 2.4),
    insetShadow(rgbaColor(0, 44, 122, 38), y = -1.0, blur = 3.0),
    insetShadow(rgbaColor(0, 72, 160, 22), x = 1.0, blur = 3.0),
  ]

func aquaScrollerTrackShadows(): seq[BoxShadow] =
  @[
    insetShadow(rgbaColor(255, 255, 255, 102), y = 1.0, blur = 2.0),
    insetShadow(rgbaColor(0, 42, 112, 28), y = -1.0, blur = 3.0),
  ]

func aquaScrollerKnobShadows(): seq[BoxShadow] =
  @[
    dropShadow(rgbaColor(0, 0, 0, 32), y = 1.0, blur = 2.8),
    insetShadow(rgbaColor(255, 255, 255, 78), y = 1.0, blur = 2.2),
    insetShadow(rgbaColor(0, 44, 122, 32), y = -1.0, blur = 3.0),
    insetShadow(rgbaColor(0, 68, 160, 24), x = 1.0, blur = 3.2),
  ]

func aquaLabelShadows(): seq[BoxShadow] =
  @[
    dropShadow(rgbaColor(255, 255, 255, 102), y = -1.0, blur = 1.5),
    insetShadow(rgbaColor(0, 36, 112, 26), y = 1.2, blur = 3.0),
    insetShadow(rgbaColor(255, 255, 255, 212), y = 2.0, blur = 2.6),
    insetShadow(rgbaColor(255, 255, 255, 118), y = -1.0, blur = 2.1),
    insetShadow(rgbaColor(0, 82, 190, 24), x = 2.0, blur = 7.0),
    insetShadow(rgbaColor(0, 82, 190, 24), x = -2.0, blur = 7.0),
    insetShadow(rgbaColor(98, 224, 255, 92), y = -3.0, blur = 7.4),
  ]

func aquaStatusLabelShadows(): seq[BoxShadow] =
  @[
    dropShadow(rgbaColor(255, 255, 255, 98), y = -1.0, blur = 1.5),
    insetShadow(rgbaColor(10, 88, 38, 24), y = 1.2, blur = 3.0),
    insetShadow(rgbaColor(255, 255, 255, 206), y = 2.0, blur = 2.6),
    insetShadow(rgbaColor(255, 255, 255, 108), y = -1.0, blur = 2.1),
    insetShadow(rgbaColor(30, 136, 68, 22), x = 2.0, blur = 7.0),
    insetShadow(rgbaColor(30, 136, 68, 22), x = -2.0, blur = 7.0),
    insetShadow(rgbaColor(112, 248, 168, 90), y = -3.0, blur = 7.2),
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

proc clearBackgroundPinstripes*(theme: var Theme, selector: StyleSelector) =
  theme[selector, StyleBackgroundPinstripeHighlightColor] = color(0.0, 0.0, 0.0, 0.0)
  theme[selector, StyleBackgroundPinstripeColor] = color(0.0, 0.0, 0.0, 0.0)
  theme[selector, StyleBackgroundPinstripePeriod] = 0.0
  theme[selector, StyleBackgroundPinstripeHeight] = 0.0

proc clearBackgroundPinstripes*(theme: var Theme) =
  theme.clearBackgroundPinstripes(initStyleSelector(srView))

const TextStyleRoles = [
  srBox, srButton, srCheckBox, srRadioButton, srTextField, srTextView, srComboBox,
  srComboBoxItem, srTab, srTableHeaderCell, srRowItem, srCascadingRowItem,
]

proc initTheme*(): Theme =
  result.tokens = newStyleTokenStore()
  result.chromes = initTable[string, Chrome]()
  result.setFontName(frUI, defaultFontName(frUI))
  result.setFontName(frMonospace, defaultFontName(frMonospace))
  for role in TextStyleRoles:
    result[role, StyleFontName] = styleToken(UIFontNameToken)
    result[role, StyleFontSize] = defaultFontSize()
  result[srMonoTextView, StyleFontName] = styleToken(MonospaceFontNameToken)
  result[srMonoTextView, StyleFontSize] = defaultFontSize()
  result["accent"] = styleColor(rgbaColor(0, 124, 238, 255))
  result["accent.pressed"] = styleColor(rgbaColor(0, 82, 191, 255))
  result["documentTab.accent.color"] = styleToken("accent")
  result["progress.fill"] = aquaSliderProgressFill()
  result["progress.border.color"] = styleToken("accent.pressed")
  result["disabled.fill"] = styleColor(rgbaColor(178, 194, 214, 255))
  result["disabled.text.color"] = styleColor(color(0.88, 0.92, 0.97, 1.0))
  result["focus.ring.color"] = styleColor(color(0.28, 0.64, 1.0, 0.82))
  result["indicator.size"] = 18.0

  result["button.fill"] = aquaButtonFill()
  result["button.fill.hovered"] = aquaButtonHoverFill()
  result["button.fill.highlighted"] = aquaButtonPressedFill()
  result["button.fill.disabled"] = aquaButtonDisabledFill()
  result["button.fill.accent"] = aquaAccentButtonFill()
  result["button.fill.accent.hovered"] = aquaAccentButtonHoverFill()
  result["button.fill.accent.highlighted"] = aquaAccentButtonPressedFill()
  result["button.text.color"] = styleColor(rgbaColor(5, 16, 27, 248))
  result["button.text.color.disabled"] = styleToken("disabled.text.color")
  result["button.border.color"] = styleColor(rgbaColor(31, 112, 204, 145))
  result["button.border.color.hovered"] = styleColor(rgbaColor(38, 156, 232, 196))
  result["button.border.color.highlighted"] = styleColor(rgbaColor(19, 93, 180, 161))
  result["button.border.color.disabled"] = styleColor(color(0.52, 0.57, 0.64, 1.0))
  result["button.border.color.accent"] = styleToken("button.border.color")
  result["button.border.color.accent.hovered"] =
    styleToken("button.border.color.hovered")
  result["button.border.color.accent.highlighted"] =
    styleToken("button.border.color.highlighted")
  result["button.focus.ring.color"] = styleToken("focus.ring.color")
  result["button.shadows"] = newSeq[BoxShadow]()
  result["button.shadows.highlighted"] = newSeq[BoxShadow]()
  result["button.shadows.disabled"] = newSeq[BoxShadow]()

  result["choice.indicator.fill"] = aquaChoiceFill()
  result["choice.indicator.fill.highlighted"] = aquaChoiceHighlightedFill()
  result["choice.indicator.fill.disabled"] = aquaButtonDisabledFill()
  result["choice.indicator.fill.selected"] = aquaChoiceSelectedFill()
  result["choice.indicator.fill.selected.highlighted"] =
    aquaChoiceSelectedHighlightedFill()
  result["choice.indicator.fill.selected.disabled"] = aquaButtonDisabledFill()
  result["choice.indicator.border.color"] = styleColor(rgbaColor(88, 90, 88, 220))
  result["choice.indicator.border.color.selected"] =
    styleColor(rgbaColor(0, 82, 191, 245))
  result["choice.indicator.border.color.highlighted"] =
    styleColor(rgbaColor(0, 82, 191, 225))
  result["choice.indicator.border.color.disabled"] =
    styleColor(rgbaColor(110, 116, 122, 128))
  result["choice.mark.color"] = styleColor(rgbaColor(7, 76, 122, 245))
  result["choice.mark.color.disabled"] = styleToken("disabled.text.color")
  result["choice.text.color"] = styleColor(color(0.08, 0.09, 0.11, 1.0))
  result["choice.text.color.disabled"] = styleColor(color(0.48, 0.52, 0.58, 1.0))

  result["textField.fill"] = aquaTextFieldFill()
  result["textField.border.color"] = styleColor(rgbaColor(88, 116, 158, 220))
  result["textField.text.color"] = styleColor(color(0.08, 0.09, 0.11, 1.0))
  result["textField.selection.color"] = styleColor(color(0.24, 0.56, 1.0, 0.34))
  result["monoText.fill"] = styleToken("textField.fill")
  result["monoText.border.color"] = styleToken("textField.border.color")
  result["monoText.text.color"] = styleToken("textField.text.color")
  result["monoText.cursor.color"] = styleColor(color(0.08, 0.45, 0.95, 0.45))
  result["comboBox.fill"] = aquaComboBoxFill()
  result["comboBox.border.color"] = styleColor(rgbaColor(86, 108, 195, 205))
  result["comboBox.border.color.open"] = styleColor(rgbaColor(70, 88, 205, 228))
  result["comboBox.text.color"] = styleToken("textField.text.color")
  result["comboBox.arrow.color"] = styleColor(color(0.0, 0.12, 0.34, 1.0))
  result["comboBox.arrow.fill"] = aquaComboArrowFill()
  result["comboBox.item.fill"] = fill(color(1.0, 1.0, 1.0, 0.83))
  result["comboBox.item.fill.highlighted"] = aquaComboItemHighlightFill()
  result["comboBox.item.fill.selected"] = aquaComboItemSelectedFill()
  result["comboBox.item.fill.selected.highlighted"] =
    aquaComboItemSelectedHighlightedFill()
  result["comboBox.item.text.color"] = styleColor(color(0.08, 0.09, 0.11, 1.0))
  result["comboBox.item.text.color.selected"] = styleColor(color(1.0, 1.0, 1.0, 1.0))
  result["tableView.fill"] = styleToken("textField.fill")
  result["tableView.border.color"] = styleToken("textField.border.color")
  result["tableView.column.selection.fill"] = styleFill(color(0.24, 0.56, 1.0, 0.12))
  result["tableView.column.hover.fill"] = styleToken("tableView.column.selection.fill")
  result["scrollView.fill"] = styleToken("tableView.fill")
  result["scrollView.border.color"] = styleToken("tableView.border.color")
  result["box.fill"] = styleColor(color(0.0, 0.0, 0.0, 0.0))
  result["box.border.color"] = styleColor(color(0.61, 0.65, 0.72, 1.0))
  result["box.text.color"] = styleColor(color(0.12, 0.15, 0.20, 1.0))
  result["scroller.track.fill"] = aquaScrollerTrackFill()
  result["scroller.track.border.color"] = styleColor(rgbaColor(78, 108, 155, 138))
  result["scroller.track.shadows"] = aquaScrollerTrackShadows()
  result["scroller.knob.fill"] = aquaButtonFill()
  result["scroller.knob.border.color"] = styleColor(rgbaColor(30, 80, 180, 150))
  result["scroller.knob.shadows"] = aquaScrollerKnobShadows()
  result["splitView.divider.fill"] = styleFill(color(0.83, 0.89, 0.97, 0.81))
  result["splitView.divider.border.color"] = styleColor(color(0.52, 0.64, 0.82, 1.0))
  result["rowItem.fill"] = styleToken("comboBox.item.fill")
  result["rowItem.fill.highlighted"] = styleToken("comboBox.item.fill.highlighted")
  result["rowItem.fill.selected"] = aquaRowItemSelectedFill()
  result["rowItem.fill.selected.highlighted"] = aquaRowItemSelectedHighlightedFill()
  result["rowItem.fill.disabled"] = styleColor(color(0.80, 0.82, 0.86, 0.51))
  result["rowItem.text.color"] = styleToken("comboBox.item.text.color")
  result["rowItem.text.color.selected"] =
    styleToken("comboBox.item.text.color.selected")
  result["rowItem.text.color.disabled"] = styleColor(color(0.32, 0.35, 0.41, 1.0))
  result["rowItem.separator.color"] = styleColor(color(0.86, 0.88, 0.91, 1.0))
  result["tab.panel.fill"] = styleColor(rgbaColor(224, 241, 255, 206))
  result["tab.panel.border.color"] = styleColor(rgbaColor(104, 132, 176, 216))
  result["tab.fill"] = styleColor(rgbaColor(220, 238, 255, 198))
  result["tab.fill.highlighted"] = styleColor(rgbaColor(190, 218, 248, 206))
  result["tab.fill.selected"] = styleColor(rgbaColor(184, 226, 255, 214))
  result["tab.fill.disabled"] = styleColor(rgbaColor(202, 208, 218, 120))
  result["tab.highlight.fill"] = styleFill(rgbaColor(255, 255, 255, 136))
  result["tab.highlight.fill.disabled"] = styleFill(color(1.0, 1.0, 1.0, 0.25))
  result["tab.text.color"] = styleColor(color(0.14, 0.15, 0.18, 1.0))
  result["tab.text.color.selected"] = styleColor(color(0.06, 0.10, 0.16, 1.0))
  result["tab.text.color.disabled"] = styleColor(color(0.48, 0.50, 0.54, 1.0))
  result["tab.border.color"] = styleColor(rgbaColor(96, 112, 132, 214))
  result["tab.border.color.highlighted"] = styleColor(rgbaColor(70, 116, 178, 224))
  result["tab.border.color.selected"] = styleColor(rgbaColor(34, 102, 210, 232))
  result["tab.border.color.disabled"] = styleColor(rgbaColor(150, 156, 166, 148))
  result["documentTab.bar.fill"] = aquaDocumentTabBarFill()
  result["documentTab.bar.border.color"] = styleColor(color(0.45, 0.54, 0.68, 0.52))
  result["documentTab.fill"] = aquaDocumentTabFill()
  result["documentTab.fill.highlighted"] = aquaDocumentTabHighlightedFill()
  result["documentTab.fill.pressed"] = aquaPressedDocumentTabFill()
  result["documentTab.fill.selected"] = aquaSelectedDocumentTabFill()
  result["documentTab.fill.disabled"] = styleFill(color(0.70, 0.76, 0.84, 0.44))
  result["documentTab.highlight.fill"] = styleFill(color(1.0, 1.0, 1.0, 0.34))
  result["documentTab.highlight.fill.disabled"] = styleFill(color(1.0, 1.0, 1.0, 0.18))
  result["documentTab.text.color"] = styleColor(color(0.10, 0.14, 0.22, 1.0))
  result["documentTab.text.color.selected"] = styleColor(color(0.04, 0.08, 0.16, 1.0))
  result["documentTab.text.color.disabled"] = styleColor(color(0.46, 0.50, 0.58, 1.0))
  result["documentTab.border.color"] = styleColor(color(0.48, 0.58, 0.72, 0.88))
  result["documentTab.border.color.highlighted"] =
    styleColor(color(0.40, 0.56, 0.78, 0.92))
  result["documentTab.border.color.pressed"] = styleColor(color(0.30, 0.46, 0.70, 0.94))
  result["documentTab.border.color.selected"] =
    styleColor(color(0.32, 0.50, 0.78, 0.95))
  result["documentTab.border.color.disabled"] =
    styleColor(color(0.50, 0.56, 0.66, 0.42))
  result["documentTab.button.fill"] = styleToken("documentTab.fill")
  result["documentTab.button.fill.highlighted"] =
    styleToken("documentTab.fill.highlighted")
  result["documentTab.button.fill.disabled"] = styleToken("documentTab.fill.disabled")
  result["documentTab.button.border.color"] = styleColor(color(0.48, 0.58, 0.72, 0.76))
  result["documentTab.button.border.color.highlighted"] =
    styleColor(color(0.36, 0.52, 0.74, 0.84))
  result["documentTab.button.border.color.disabled"] =
    styleColor(color(0.48, 0.54, 0.64, 0.34))
  result["documentTab.button.mark.color"] = styleColor(color(0.12, 0.18, 0.28, 0.92))
  result["documentTab.button.mark.color.disabled"] =
    styleColor(color(0.44, 0.50, 0.58, 0.72))

  result[srView, StyleBackgroundColor] = color(0.93, 0.93, 0.92)
  result[srView, StyleBackgroundFill] = aquaWindowBackgroundFill()
  result[srView, StyleBackgroundPinstripeHighlightColor] = rgbaColor(255, 255, 255, 95)
  result[srView, StyleBackgroundPinstripeColor] = color(0.0, 0.0, 0.0, 0.0)
  result[srView, StyleBackgroundPinstripePeriod] = 4.0
  result[srView, StyleBackgroundPinstripeHeight] = 1.0

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
    styleToken("button.fill.hovered"),
    styleToken("button.border.color.hovered"),
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
    styleToken("button.fill.accent.hovered"),
    styleToken("button.border.color.accent.hovered"),
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
  result[srButton, StyleBorderWidth] = 0.55
  result[srButton, StyleCornerRadius] = 14.0
  result[srButton, StyleTextInsets] = insets(0.0, 8.0)
  result[srButton, StyleTextHighlightColor] = rgbaColor(255, 255, 255, 82)
  result[srButton, StyleTextShadowColor] = rgbaColor(0, 0, 0, 54)
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

  result[srSwitch, StyleFill] = aquaComboBoxFill()
  result[srSwitch, StyleBorderColor] = rgbaColor(82, 88, 96, 210)
  result[srSwitch, StyleBorderWidth] = 1.0
  result[srSwitch, StyleFocusRingWidth] = 3.0
  result[srSwitch, StyleFocusRingInset] = -3.0
  result[srSwitch, StyleFocusRingColor] = styleToken("focus.ring.color")
  result[srSwitch, StyleBoxShadows] = aquaSwitchTrackShadows(enabled = true)
  result[srSwitch, StyleKnobFill] = aquaTextFieldFill()
  result[srSwitch, StyleKnobBorderColor] = rgbaColor(82, 116, 170, 220)
  result[srSwitch, StyleKnobInset] = 1.7
  result[srSwitch, StyleKnobSizeFactor] = 2.0
  result[srSwitch, StyleKnobShadows] = aquaSwitchKnobShadows(enabled = true)
  result[srSwitch, StyleIndicatorSize] = styleToken("indicator.size")
  result[srSwitch, StyleWidthFactor] = 1.67
  result[srSwitch, StyleMinimumSize] = initSize(0.0, 0.0)
  result[srSwitch, StyleChrome] = styleKeyword(AquaChromeName)
  result[srSwitch, {ssSelected}, StyleFill] = aquaButtonFill()
  result[srSwitch, {ssSelected}, StyleBorderColor] = rgbaColor(31, 112, 204, 145)
  result[srSwitch, {ssHighlighted}, StyleKnobFill] = aquaComboBoxFill()
  result[srSwitch, {ssDisabled}, StyleFill] = fill(color(0.72, 0.78, 0.84, 0.37))
  result[srSwitch, {ssDisabled}, StyleBorderColor] = color(0.38, 0.45, 0.53, 0.32)
  result[srSwitch, {ssDisabled}, StyleBoxShadows] =
    aquaSwitchTrackShadows(enabled = false)
  result[srSwitch, {ssDisabled}, StyleKnobFill] = fill(color(0.96, 0.97, 0.99, 0.63))
  result[srSwitch, {ssDisabled}, StyleKnobBorderColor] = color(0.32, 0.36, 0.44, 0.34)
  result[srSwitch, {ssDisabled}, StyleKnobShadows] =
    aquaSwitchKnobShadows(enabled = false)
  result[srSwitch, {ssSelected, ssDisabled}, StyleFill] =
    fill(color(0.08, 0.54, 0.96, 0.37))
  result[srSwitch, {ssSelected, ssDisabled}, StyleBorderColor] =
    color(0.02, 0.24, 0.62, 0.32)

  result[srSlider, StyleIndicatorSize] = 6.0
  result[srSlider, StyleKnobSize] = 20.0
  result[srSlider, StyleMinimumSize] = initSize(160.0, 26.0)
  result[srSlider, StyleFill] = aquaComboBoxFill()
  result[srSlider, StyleHighlightFill] = aquaSliderProgressFill()
  result[srSlider, StyleBorderColor] = rgbaColor(82, 116, 170, 190)
  result[srSlider, StyleFocusRingColor] = styleToken("focus.ring.color")
  result[srSlider, StyleKnobFill] = aquaSliderKnobFill()
  result[srSlider, StyleKnobBorderColor] = rgbaColor(82, 116, 170, 220)
  result[srSlider, StyleKnobShadows] = aquaKnobShadows()
  result[srSlider, StyleChrome] = styleKeyword(AquaChromeName)
  result[srProgressIndicator, StyleIndicatorSize] = 6.0
  result[srProgressIndicator, StyleKnobSize] = 20.0
  result[srProgressIndicator, StyleMinimumSize] = initSize(160.0, 26.0)
  result[srProgressIndicator, StyleFill] = aquaComboBoxFill()
  result[srProgressIndicator, StyleHighlightFill] = styleToken("progress.fill")
  result[srProgressIndicator, StyleBorderColor] = rgbaColor(82, 116, 170, 190)
  result[srProgressIndicator, StyleFocusRingColor] = styleToken("progress.border.color")
  result[srProgressIndicator, StyleKnobFill] = aquaSliderKnobFill()
  result[srProgressIndicator, StyleKnobBorderColor] = rgbaColor(82, 116, 170, 220)
  result[srProgressIndicator, StyleKnobShadows] = aquaKnobShadows()
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
  result[srTab, StyleCornerRadius] = 9.0
  result[srTab, StyleTextInsets] = insets(1.0, 10.0)
  result[srTab, StylePadding] = insets(0.0, 14.0)
  result[srTab, StyleMinimumSize] = initSize(52.0, 26.0)
  result[srTab, StyleMaximumSize] = initSize(180.0, 0.0)
  result[srTab, StyleSegmentSize] = initSize(0.0, 22.0)
  result[srTab, StyleEdgeInset] = 10.0
  result[srTab, StyleItemGap] = 1.0
  result[srTab, StyleOverlap] = 12.0
  result[srTab, StyleChrome] = styleKeyword(AquaChromeName)
  result[srTabPanel, StyleFill] = styleToken("tab.panel.fill")
  result[srTabPanel, StyleBorderColor] = styleToken("tab.panel.border.color")
  result[srTabPanel, StyleBorderWidth] = 1.0
  result[srTabPanel, StyleCornerRadius] = 9.0
  result[srTabPanel, StyleChrome] = styleKeyword(AquaChromeName)

  result.addRoleRule(
    srDocumentTab,
    {},
    styleToken("documentTab.fill"),
    styleToken("documentTab.border.color"),
    styleToken("documentTab.text.color"),
  )
  result.addRoleRule(
    srDocumentTab,
    {ssHighlighted},
    styleToken("documentTab.fill.highlighted"),
    styleToken("documentTab.border.color.highlighted"),
    styleToken("documentTab.text.color"),
  )
  result.addRoleRule(
    srDocumentTab,
    {ssHighlighted, ssPressed},
    styleToken("documentTab.fill.pressed"),
    styleToken("documentTab.border.color.pressed"),
    styleToken("documentTab.text.color"),
  )
  result.addRoleRule(
    srDocumentTab,
    {ssSelected},
    styleToken("documentTab.fill.selected"),
    styleToken("documentTab.border.color.selected"),
    styleToken("documentTab.text.color.selected"),
  )
  result.addRoleRule(
    srDocumentTab,
    {ssDisabled},
    styleToken("documentTab.fill.disabled"),
    styleToken("documentTab.border.color.disabled"),
    styleToken("documentTab.text.color.disabled"),
  )
  result[srDocumentTab, StyleHighlightFill] = styleToken("documentTab.highlight.fill")
  result[srDocumentTab, {ssDisabled}, StyleHighlightFill] =
    styleToken("documentTab.highlight.fill.disabled")
  result[srDocumentTab, StyleMarkColor] = styleToken("documentTab.accent.color")
  result[srDocumentTab, StyleBorderWidth] = 1.0
  result[srDocumentTab, StyleCornerRadius] = 10.0
  result[srDocumentTab, StyleTextInsets] = insets(1.0, 13.0)
  result[srDocumentTab, StylePadding] = insets(0.0, 16.0)
  result[srDocumentTab, StyleMinimumSize] = initSize(96.0, 30.0)
  result[srDocumentTab, StyleMaximumSize] = initSize(198.0, 0.0)
  result[srDocumentTab, StyleItemGap] = 2.0
  result[srDocumentTab, StyleSelectionIndicatorPosition] = styleKeyword("bottom")
  result[srDocumentTab, StyleSelectionIndicatorInsets] = insets(2.0, 10.0, 1.0, 10.0)
  result[srDocumentTab, StyleSelectionIndicatorSize] = 2.0
  result[srDocumentTab, StyleSelectionIndicatorCornerRadius] = 1.0
  result[srDocumentTab, StyleCloseButtonPosition] = styleKeyword("left")
  result[srDocumentTab, StyleChrome] = styleKeyword(AquaChromeName)
  result[srDocumentTabBar, StyleFill] = styleToken("documentTab.bar.fill")
  result[srDocumentTabBar, StyleBorderColor] =
    styleToken("documentTab.bar.border.color")
  result[srDocumentTabBar, StyleBorderWidth] = 1.0
  result[srDocumentTabBar, StyleCornerRadius] = 10.0
  result[srDocumentTabBar, StyleChrome] = styleKeyword(AquaChromeName)
  result.addChoiceRule(
    srDocumentTabButton,
    {},
    styleToken("documentTab.button.fill"),
    styleToken("documentTab.button.border.color"),
    styleToken("documentTab.button.mark.color"),
    styleToken("documentTab.text.color"),
  )
  result.addChoiceRule(
    srDocumentTabButton,
    {ssHighlighted},
    styleToken("documentTab.button.fill.highlighted"),
    styleToken("documentTab.button.border.color.highlighted"),
    styleToken("documentTab.button.mark.color"),
    styleToken("documentTab.text.color"),
  )
  result.addChoiceRule(
    srDocumentTabButton,
    {ssHighlighted, ssPressed},
    styleToken("documentTab.fill.pressed"),
    styleToken("documentTab.border.color.pressed"),
    styleToken("documentTab.button.mark.color"),
    styleToken("documentTab.text.color"),
  )
  result.addChoiceRule(
    srDocumentTabButton,
    {ssDisabled},
    styleToken("documentTab.button.fill.disabled"),
    styleToken("documentTab.button.border.color.disabled"),
    styleToken("documentTab.button.mark.color.disabled"),
    styleToken("documentTab.text.color.disabled"),
  )
  result[srDocumentTabButton, StyleCornerRadius] = 7.0
  result[srDocumentTabButton, StyleChrome] = styleKeyword(AquaChromeName)

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
    result[role, StyleBoxShadows] = aquaChoiceIndicatorShadows()
    result[role, StyleChrome] = styleKeyword(AquaChromeName)

  result[srTextField, StyleFill] = styleToken("textField.fill")
  result[srTextField, StyleBorderColor] = styleToken("textField.border.color")
  result[srTextField, StyleBorderWidth] = 1.0
  result[srTextField, StyleCornerRadius] = 6.0
  result[srTextField, StyleTextInsets] = insets(0.0, 10.0)
  result[srTextField, StyleMinimumSize] = initSize(80.0, 26.0)
  result[srTextField, StyleSelectionColor] = styleToken("textField.selection.color")
  result[srTextField, StyleFocusRingWidth] = 3.0
  result[srTextField, StyleFocusRingInset] = -2.0
  result[srTextField, StyleFocusRingColor] = styleToken("focus.ring.color")
  result[srTextField, StyleBoxShadows] = newSeq[BoxShadow]()
  result[srTextField, StyleChrome] = styleKeyword(AquaChromeName)

  result[srTextView, StyleSelectionColor] = styleToken("textField.selection.color")

  result[srMonoTextView, StyleFill] = styleToken("monoText.fill")
  result[srMonoTextView, StyleBorderColor] = styleToken("monoText.border.color")
  result[srMonoTextView, StyleBorderWidth] = 1.0
  result[srMonoTextView, StyleCornerRadius] = 10.0
  result[srMonoTextView, StyleTextColor] = styleToken("monoText.text.color")
  result[srMonoTextView, StyleTextInsets] = insets(6.0)
  result[srMonoTextView, StyleCursorColor] = styleToken("monoText.cursor.color")
  result[srMonoTextView, StyleSelectionColor] = styleToken("textField.selection.color")
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
    aquaTitleLabelFill(),
    rgbaColor(92, 135, 196, 138),
    1.0,
    8.0,
    color(0.09, 0.14, 0.26, 1.0),
    insets(0.0, 12.0),
    initSize(0.0, 28.0),
    aquaLabelShadows(),
    AquaChromeName,
  )
  result.addLabelRule(
    LabelHeadingStyleClass,
    aquaHeadingLabelFill(),
    rgbaColor(104, 148, 205, 126),
    1.0,
    7.0,
    color(0.10, 0.18, 0.32, 1.0),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
    aquaLabelShadows(),
    AquaChromeName,
  )
  result.addLabelRule(
    LabelStatusStyleClass,
    aquaStatusLabelFill(),
    rgbaColor(88, 168, 112, 124),
    1.0,
    7.0,
    color(0.06, 0.25, 0.14, 1.0),
    insets(0.0, 10.0),
    initSize(0.0, 24.0),
    aquaStatusLabelShadows(),
    AquaChromeName,
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
  result[srComboBox, StyleCornerRadius] = 12.0
  result[srComboBox, StyleTextInsets] = insets(0.0, 10.0)
  result[srComboBox, StyleFocusRingWidth] = 3.0
  result[srComboBox, StyleFocusRingInset] = -2.0
  result[srComboBox, StyleFocusRingColor] = styleToken("focus.ring.color")
  result[srComboBox, StyleIndicatorSize] = 28.0
  result[srComboBox, StyleMinimumSize] = initSize(90.0, 26.0)
  result[srComboBox, StyleIndicatorFill] = styleToken("comboBox.arrow.fill")
  result[srComboBox, StyleMarkColor] = styleToken("comboBox.arrow.color")
  result[srComboBox, StyleBoxShadows] = aquaComboBoxShadows()
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
  result[srTableView, StyleFocusRingInset] = -2.0
  result[srTableView, StyleFocusRingColor] = styleToken("focus.ring.color")
  result[srTableView, StyleBoxShadows] = aquaInsetControlShadows()
  result[srTableView, StyleDropIndicatorFill] = fill(color(0.18, 0.42, 0.88, 0.95))
  result[srTableView, StyleColumnSelectionFill] =
    styleToken("tableView.column.selection.fill")
  result[srTableView, StyleColumnHoverFill] = styleToken("tableView.column.hover.fill")
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
  result[srScroller, StyleBorderWidth] = 0.7
  result[srScroller, StyleCornerRadius] = 6.0
  result[srScroller, StyleBoxShadows] = styleToken("scroller.track.shadows")
  result[srScroller, StyleKnobShadows] = styleToken("scroller.knob.shadows")

  result[srCascadingScroller, StyleFill] = styleToken("scroller.track.fill")
  result[srCascadingScroller, StyleBorderColor] =
    styleToken("scroller.track.border.color")
  result[srCascadingScroller, StyleKnobFill] = styleToken("scroller.knob.fill")
  result[srCascadingScroller, StyleKnobBorderColor] =
    styleToken("scroller.knob.border.color")
  result[srCascadingScroller, StyleBorderWidth] = 0.7
  result[srCascadingScroller, StyleCornerRadius] = 6.0
  result[srCascadingScroller, StyleBoxShadows] = styleToken("scroller.track.shadows")
  result[srCascadingScroller, StyleKnobShadows] = styleToken("scroller.knob.shadows")

  result[srSplitView, StyleFill] = styleToken("splitView.divider.fill")
  result[srSplitView, StyleBorderColor] = styleToken("splitView.divider.border.color")
  result[srSplitView, StyleBorderWidth] = 1.0
  result[srSplitView, StyleCornerRadius] = 2.0
  result[srSplitView, StyleSeparatorThickness] = 6.0
  result[srSplitView, StyleFocusRingWidth] = 0.0
  result[srSplitView, StyleFocusRingInset] = 0.0
  result[srSplitView, StyleBoxShadows] = newSeq[BoxShadow]()

  result[srTableHeader, StyleFill] =
    linear(color(0.97, 0.98, 0.99, 0.78), color(0.78, 0.81, 0.86, 0.78), fgaY)
  result[srTableHeader, StyleBorderColor] = color(0.52, 0.56, 0.62, 0.92)
  result[srTableHeader, StyleInsertionIndicatorFill] =
    fill(color(0.16, 0.36, 0.84, 0.95))
  result[srTableHeaderCell, StyleFill] =
    linear(color(1.0, 1.0, 1.0, 0.64), color(0.82, 0.84, 0.88, 0.64), fgaY)
  result[srTableHeaderCell, {ssHovered}, StyleFill] =
    linear(color(1.0, 1.0, 1.0, 0.72), color(0.74, 0.78, 0.84, 0.72), fgaY)
  result[srTableHeaderCell, {ssPressed}, StyleFill] =
    linear(color(0.72, 0.75, 0.80, 0.78), color(0.58, 0.62, 0.68, 0.78), fgaY)
  result[srTableHeaderCell, StyleBorderColor] = color(0.54, 0.58, 0.64, 0.76)
  result[srTableHeaderCell, StyleTextColor] = color(0.12, 0.14, 0.18, 1.0)
  result[srTableHeaderCell, StyleMarkColor] = color(0.10, 0.13, 0.18, 0.95)

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
  result[srRowItem, StyleAlternatingFill] = fill(color(0.96, 0.97, 0.99, 0.95))
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
  result[srCascadingRowItem, StyleAlternatingFill] = fill(color(0.96, 0.97, 0.99, 0.95))
  result.installThemeExtensions()

proc initBannerTheme*(): Theme =
  result = initTheme()
  result[srDocumentTab, StyleCloseButtonPosition] = styleKeyword("right")
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
  result["progress.fill"] = styleToken("accent")
  result["progress.border.color"] = styleToken("accent.pressed")
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
  themeFactories: Table[string, ThemeFactory]
  themeFactoriesInitialized: bool

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
