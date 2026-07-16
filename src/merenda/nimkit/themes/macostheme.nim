import ./defaulttheme
import ./themecore
import ../foundation/types

func controlShadow(): seq[BoxShadow] =
  @[dropShadow(color(0.0, 0.0, 0.0, 0.08), y = 1.0, blur = 2.0)]

func knobShadow(): seq[BoxShadow] =
  @[dropShadow(color(0.0, 0.0, 0.0, 0.18), y = 1.0, blur = 3.0)]

func darkControlShadow(): seq[BoxShadow] =
  @[dropShadow(color(0.0, 0.0, 0.0, 0.38), y = 1.0, blur = 3.0)]

func darkKnobShadow(): seq[BoxShadow] =
  @[dropShadow(color(0.0, 0.0, 0.0, 0.52), y = 1.0, blur = 4.0)]

proc addMacOSLabelRule(
    theme: var Theme,
    className: string,
    fillValue: Fill,
    borderColor: Color,
    borderWidth: float32,
    cornerRadius: float32,
    textColor: Color,
    textInsets: EdgeInsets,
    minSize: Size,
    fontSize: float32,
) =
  let selector = initStyleSelector(srTextField, classes = @[className])
  theme[selector, StyleFill] = fillValue
  theme[selector, StyleBorderColor] = borderColor
  theme[selector, StyleBorderWidth] = borderWidth
  theme[selector, StyleCornerRadius] = cornerRadius
  theme[selector, StyleTextColor] = textColor
  theme[selector, StyleTextInsets] = textInsets
  theme[selector, StyleMinimumSize] = minSize
  theme[selector, StyleFontSize] = fontSize
  theme[selector, StyleFocusRingWidth] = 0.0
  theme[selector, StyleFocusRingInset] = 0.0
  theme[selector, StyleBoxShadows] = newSeq[BoxShadow]()
  theme[selector, StyleChrome] = styleKeyword(DefaultChromeName)

proc installMacOSTokens(theme: var Theme) =
  theme["accent"] = color(0.04, 0.52, 1.0, 1.0)
  theme["accent.pressed"] = color(0.0, 0.38, 0.82, 1.0)
  theme["progress.fill"] = styleToken("accent")
  theme["progress.border.color"] = styleToken("accent.pressed")
  theme["disabled.fill"] = color(0.93, 0.93, 0.94, 1.0)
  theme["disabled.text.color"] = color(0.56, 0.56, 0.58, 1.0)
  theme["focus.ring.color"] = color(0.04, 0.52, 1.0, 0.48)
  theme["indicator.size"] = 16.0

  theme["button.fill"] = color(1.0, 1.0, 1.0, 0.94)
  theme["button.fill.hovered"] = color(1.0, 1.0, 1.0, 1.0)
  theme["button.fill.highlighted"] = color(0.86, 0.86, 0.88, 1.0)
  theme["button.fill.disabled"] = styleToken("disabled.fill")
  theme["button.fill.accent"] = styleToken("accent")
  theme["button.fill.accent.hovered"] = color(0.16, 0.60, 1.0, 1.0)
  theme["button.fill.accent.highlighted"] = styleToken("accent.pressed")
  theme["button.text.color"] = color(0.12, 0.12, 0.13, 1.0)
  theme["button.text.color.disabled"] = styleToken("disabled.text.color")
  theme["button.border.color"] = color(0.0, 0.0, 0.0, 0.20)
  theme["button.border.color.hovered"] = color(0.0, 0.0, 0.0, 0.25)
  theme["button.border.color.highlighted"] = color(0.0, 0.0, 0.0, 0.28)
  theme["button.border.color.disabled"] = color(0.0, 0.0, 0.0, 0.10)
  theme["button.border.color.accent"] = color(0.0, 0.34, 0.78, 0.78)
  theme["button.border.color.accent.hovered"] = color(0.0, 0.38, 0.82, 0.82)
  theme["button.border.color.accent.highlighted"] = color(0.0, 0.28, 0.68, 0.86)
  theme["button.focus.ring.color"] = styleToken("focus.ring.color")
  theme["button.shadows"] = controlShadow()
  theme["button.shadows.highlighted"] = newSeq[BoxShadow]()
  theme["button.shadows.disabled"] = newSeq[BoxShadow]()

  theme["choice.indicator.fill"] = color(1.0, 1.0, 1.0, 1.0)
  theme["choice.indicator.fill.highlighted"] = color(0.95, 0.95, 0.96, 1.0)
  theme["choice.indicator.fill.disabled"] = styleToken("disabled.fill")
  theme["choice.indicator.fill.selected"] = styleToken("accent")
  theme["choice.indicator.fill.selected.highlighted"] = styleToken("accent.pressed")
  theme["choice.indicator.fill.selected.disabled"] = color(0.58, 0.76, 0.96, 1.0)
  theme["choice.indicator.border.color"] = color(0.0, 0.0, 0.0, 0.28)
  theme["choice.indicator.border.color.selected"] = color(0.0, 0.34, 0.78, 0.82)
  theme["choice.indicator.border.color.highlighted"] = color(0.0, 0.0, 0.0, 0.36)
  theme["choice.indicator.border.color.disabled"] = color(0.0, 0.0, 0.0, 0.12)
  theme["choice.mark.color"] = color(1.0, 1.0, 1.0, 1.0)
  theme["choice.mark.color.disabled"] = color(1.0, 1.0, 1.0, 0.78)
  theme["choice.text.color"] = color(0.12, 0.12, 0.13, 1.0)
  theme["choice.text.color.disabled"] = styleToken("disabled.text.color")

  theme["textField.fill"] = color(1.0, 1.0, 1.0, 0.96)
  theme["textField.border.color"] = color(0.0, 0.0, 0.0, 0.22)
  theme["textField.text.color"] = color(0.10, 0.10, 0.11, 1.0)
  theme["textField.selection.color"] = color(0.04, 0.52, 1.0, 0.26)
  theme["monoText.fill"] = styleToken("textField.fill")
  theme["monoText.border.color"] = styleToken("textField.border.color")
  theme["monoText.text.color"] = styleToken("textField.text.color")
  theme["monoText.cursor.color"] = styleToken("accent")

  theme["comboBox.fill"] = styleToken("button.fill")
  theme["comboBox.border.color"] = styleToken("button.border.color")
  theme["comboBox.border.color.open"] = styleToken("accent")
  theme["comboBox.text.color"] = styleToken("textField.text.color")
  theme["comboBox.arrow.fill"] = color(0.0, 0.0, 0.0, 0.04)
  theme["comboBox.arrow.color"] = color(0.30, 0.30, 0.32, 1.0)
  theme["comboBox.item.fill"] = color(1.0, 1.0, 1.0, 0.98)
  theme["comboBox.item.fill.highlighted"] = color(0.92, 0.92, 0.94, 1.0)
  theme["comboBox.item.fill.selected"] = styleToken("accent")
  theme["comboBox.item.fill.selected.highlighted"] = styleToken("accent.pressed")
  theme["comboBox.item.text.color"] = styleToken("textField.text.color")
  theme["comboBox.item.text.color.selected"] = color(1.0, 1.0, 1.0, 1.0)

  theme["tableView.fill"] = color(1.0, 1.0, 1.0, 0.92)
  theme["tableView.border.color"] = color(0.0, 0.0, 0.0, 0.16)
  theme["tableView.column.selection.fill"] = color(0.04, 0.52, 1.0, 0.10)
  theme["tableView.column.hover.fill"] = color(0.0, 0.0, 0.0, 0.035)
  theme["scrollView.fill"] = styleToken("tableView.fill")
  theme["scrollView.border.color"] = styleToken("tableView.border.color")
  theme["scroller.track.fill"] = color(0.0, 0.0, 0.0, 0.0)
  theme["scroller.track.border.color"] = color(0.0, 0.0, 0.0, 0.0)
  theme["scroller.track.shadows"] = newSeq[BoxShadow]()
  theme["scroller.knob.fill"] = color(0.35, 0.35, 0.37, 0.46)
  theme["scroller.knob.border.color"] = color(0.0, 0.0, 0.0, 0.08)
  theme["scroller.knob.shadows"] = newSeq[BoxShadow]()
  theme["splitView.divider.fill"] = color(0.0, 0.0, 0.0, 0.08)
  theme["splitView.divider.border.color"] = color(0.0, 0.0, 0.0, 0.12)

  theme["rowItem.fill"] = color(1.0, 1.0, 1.0, 0.0)
  theme["rowItem.fill.highlighted"] = color(0.0, 0.0, 0.0, 0.055)
  theme["rowItem.fill.selected"] = styleToken("accent")
  theme["rowItem.fill.selected.highlighted"] = styleToken("accent.pressed")
  theme["rowItem.fill.disabled"] = color(0.0, 0.0, 0.0, 0.025)
  theme["rowItem.text.color"] = styleToken("textField.text.color")
  theme["rowItem.text.color.selected"] = color(1.0, 1.0, 1.0, 1.0)
  theme["rowItem.text.color.disabled"] = styleToken("disabled.text.color")
  theme["rowItem.separator.color"] = color(0.0, 0.0, 0.0, 0.08)

  theme["tab.panel.fill"] = color(1.0, 1.0, 1.0, 0.72)
  theme["tab.panel.border.color"] = color(0.0, 0.0, 0.0, 0.14)
  theme["tab.fill"] = color(0.0, 0.0, 0.0, 0.0)
  theme["tab.fill.highlighted"] = color(0.0, 0.0, 0.0, 0.06)
  theme["tab.fill.selected"] = color(1.0, 1.0, 1.0, 0.96)
  theme["tab.fill.disabled"] = color(0.0, 0.0, 0.0, 0.025)
  theme["tab.highlight.fill"] = color(0.0, 0.0, 0.0, 0.0)
  theme["tab.highlight.fill.disabled"] = color(0.0, 0.0, 0.0, 0.0)
  theme["tab.text.color"] = color(0.24, 0.24, 0.26, 1.0)
  theme["tab.text.color.selected"] = color(0.08, 0.08, 0.09, 1.0)
  theme["tab.text.color.disabled"] = styleToken("disabled.text.color")
  theme["tab.border.color"] = color(0.0, 0.0, 0.0, 0.0)
  theme["tab.border.color.highlighted"] = color(0.0, 0.0, 0.0, 0.10)
  theme["tab.border.color.selected"] = color(0.0, 0.0, 0.0, 0.18)
  theme["tab.border.color.disabled"] = color(0.0, 0.0, 0.0, 0.0)

  theme["documentTab.bar.fill"] = styleToken("tab.panel.fill")
  theme["documentTab.bar.border.color"] = styleToken("tab.panel.border.color")
  theme["documentTab.fill"] = styleToken("tab.fill")
  theme["documentTab.fill.highlighted"] = styleToken("tab.fill.highlighted")
  theme["documentTab.fill.pressed"] = color(0.0, 0.0, 0.0, 0.10)
  theme["documentTab.fill.selected"] = styleToken("tab.fill.selected")
  theme["documentTab.fill.disabled"] = styleToken("tab.fill.disabled")
  theme["documentTab.highlight.fill"] = styleToken("tab.highlight.fill")
  theme["documentTab.highlight.fill.disabled"] =
    styleToken("tab.highlight.fill.disabled")
  theme["documentTab.text.color"] = styleToken("tab.text.color")
  theme["documentTab.text.color.selected"] = styleToken("tab.text.color.selected")
  theme["documentTab.text.color.disabled"] = styleToken("tab.text.color.disabled")
  theme["documentTab.border.color"] = styleToken("tab.border.color")
  theme["documentTab.border.color.highlighted"] =
    styleToken("tab.border.color.highlighted")
  theme["documentTab.border.color.pressed"] = styleToken("tab.border.color.highlighted")
  theme["documentTab.border.color.selected"] = styleToken("tab.border.color.selected")
  theme["documentTab.border.color.disabled"] = styleToken("tab.border.color.disabled")
  theme["documentTab.button.fill"] = styleToken("tab.fill")
  theme["documentTab.button.fill.highlighted"] = styleToken("tab.fill.highlighted")
  theme["documentTab.button.fill.disabled"] = styleToken("tab.fill.disabled")
  theme["documentTab.button.border.color"] = styleToken("tab.border.color")
  theme["documentTab.button.border.color.highlighted"] =
    styleToken("tab.border.color.highlighted")
  theme["documentTab.button.border.color.disabled"] =
    styleToken("tab.border.color.disabled")
  theme["documentTab.button.mark.color"] = styleToken("tab.text.color")
  theme["documentTab.button.mark.color.disabled"] =
    styleToken("tab.text.color.disabled")

proc installMacOSControlStyles(theme: var Theme) =
  theme.clearBackgroundPinstripes()
  theme[srView, StyleBackgroundColor] = color(0.93, 0.93, 0.94, 1.0)
  theme[srView, StyleBackgroundFill] = fill(color(0.93, 0.93, 0.94, 1.0))

  let flatRoles = [
    srButton, srStepper, srCheckBox, srRadioButton, srSwitch, srSlider,
    srProgressIndicator, srTab, srTabPanel, srDocumentTab, srDocumentTabBar,
    srDocumentTabButton, srTextField, srMonoTextView, srComboBox,
  ]
  for role in flatRoles:
    theme[role, StyleChrome] = styleKeyword(DefaultChromeName)

  theme[srButton, StyleCornerRadius] = 7.0
  theme[srButton, StyleBorderWidth] = 1.0
  theme[srButton, StyleMinimumSize] = initSize(0.0, 28.0)
  theme[srButton, StyleTextInsets] = insets(0.0, 12.0)
  theme[srButton, StyleTextHighlightColor] = color(0.0, 0.0, 0.0, 0.0)
  theme[srButton, StyleTextShadowColor] = color(0.0, 0.0, 0.0, 0.0)
  for states in [
    {ssAccent}, {ssAccent, ssHovered}, {ssAccent, ssHighlighted}, {ssAccent, ssActive}
  ]:
    theme[srButton, states, StyleTextColor] = color(1.0, 1.0, 1.0, 1.0)

  theme[srStepper, StyleFill] = fill(color(0.89, 0.89, 0.90, 1.0))
  theme[srStepper, StyleBorderColor] = color(0.0, 0.0, 0.0, 0.12)
  theme[srStepper, StyleBorderWidth] = 1.0
  theme[srStepper, StyleCornerRadius] = 8.0
  theme[srStepper, StyleMinimumSize] = initSize(72.0, 28.0)
  theme[srStepper, StyleTextColor] = color(0.16, 0.16, 0.17, 1.0)
  theme[srStepper, StyleTextInsets] = insets(0.0)
  theme[srStepper, StyleBoxShadows] =
    @[dropShadow(color(0.0, 0.0, 0.0, 0.08), y = 1.0, blur = 2.0)]
  theme[srStepper, StyleSeparatorThickness] = 1.0
  theme[srStepper, {ssHighlighted}, StyleFill] = fill(color(0.80, 0.80, 0.82, 1.0))
  theme[srStepper, {ssHighlighted}, StyleBoxShadows] = newSeq[BoxShadow]()
  theme[srStepper, {ssDisabled}, StyleTextColor] = color(0.58, 0.58, 0.60, 1.0)

  for role in [srCheckBox, srRadioButton]:
    theme[role, StyleIndicatorSize] = 16.0
    theme[role, StyleBorderWidth] = 1.0
    theme[role, StyleBoxShadows] = newSeq[BoxShadow]()
  theme[srCheckBox, StyleCornerRadius] = 4.0
  theme[srRadioButton, StyleCornerRadius] = 8.0

  theme[srSwitch, StyleFill] = fill(color(0.47, 0.47, 0.49, 0.32))
  theme[srSwitch, StyleBorderColor] = color(0.0, 0.0, 0.0, 0.08)
  theme[srSwitch, StyleBoxShadows] = newSeq[BoxShadow]()
  theme[srSwitch, StyleKnobFill] = fill(color(1.0, 1.0, 1.0, 1.0))
  theme[srSwitch, StyleKnobBorderColor] = color(0.0, 0.0, 0.0, 0.08)
  theme[srSwitch, StyleKnobShadows] = knobShadow()
  theme[srSwitch, {ssSelected}, StyleFill] = fill(color(0.20, 0.78, 0.35, 1.0))
  theme[srSwitch, {ssSelected}, StyleBorderColor] = color(0.12, 0.64, 0.26, 1.0)

  for role in [srSlider, srProgressIndicator]:
    theme[role, StyleIndicatorSize] = 4.0
    theme[role, StyleKnobSize] = 18.0
    theme[role, StyleFill] = fill(color(0.47, 0.47, 0.49, 0.24))
    theme[role, StyleHighlightFill] = fill(color(0.04, 0.52, 1.0, 1.0))
    theme[role, StyleBorderColor] = color(0.0, 0.0, 0.0, 0.06)
    theme[role, StyleKnobFill] = fill(color(1.0, 1.0, 1.0, 1.0))
    theme[role, StyleKnobBorderColor] = color(0.0, 0.0, 0.0, 0.14)
    theme[role, StyleKnobShadows] = knobShadow()
  theme[srProgressIndicator, StyleHighlightFill] = styleToken("progress.fill")
  theme[srProgressIndicator, StyleFocusRingColor] = styleToken("progress.border.color")

  theme[srTextField, StyleCornerRadius] = 6.0
  theme[srTextField, StyleMinimumSize] = initSize(80.0, 28.0)
  theme[srTextField, StyleTextColor] = styleToken("textField.text.color")
  theme[srTextField, StyleBoxShadows] = newSeq[BoxShadow]()
  theme[srMonoTextView, StyleCornerRadius] = 8.0
  theme[srMonoTextView, StyleBoxShadows] = newSeq[BoxShadow]()
  theme[srComboBox, StyleCornerRadius] = 7.0
  theme[srComboBox, StyleMinimumSize] = initSize(90.0, 28.0)
  theme[srComboBox, StyleIndicatorSize] = 24.0
  theme[srComboBox, StyleBoxShadows] = controlShadow()

  theme[srTab, StyleCornerRadius] = 7.0
  theme[srTab, StyleMinimumSize] = initSize(52.0, 28.0)
  theme[srTab, StyleSegmentSize] = initSize(0.0, 24.0)
  theme[srTab, StyleOverlap] = 0.0
  theme[srTabPanel, StyleCornerRadius] = 8.0
  theme[srDocumentTab, StyleCornerRadius] = 7.0
  theme[srDocumentTab, StyleSelectionIndicatorPosition] = styleKeyword("bottom")
  theme[srDocumentTab, StyleSelectionIndicatorInsets] = insets(2.0, 11.0, 1.0, 11.0)
  theme[srDocumentTab, StyleSelectionIndicatorSize] = 2.0
  theme[srDocumentTab, StyleSelectionIndicatorCornerRadius] = 1.0
  theme[srDocumentTab, StyleCloseButtonPosition] = styleKeyword("left")
  theme[srDocumentTabBar, StyleCornerRadius] = 8.0

  theme[srScrollView, StyleCornerRadius] = 8.0
  theme[srScroller, StyleBorderWidth] = 0.0
  theme[srScroller, StyleCornerRadius] = 4.0
  theme[srCascadingScroller, StyleBorderWidth] = 0.0
  theme[srCascadingScroller, StyleCornerRadius] = 4.0
  theme[srSplitView, StyleSeparatorThickness] = 1.0

  theme[srTableHeader, StyleFill] = fill(color(0.96, 0.96, 0.97, 0.96))
  theme[srTableHeader, StyleBorderColor] = color(0.0, 0.0, 0.0, 0.12)
  theme[srTableHeaderCell, StyleFill] = fill(color(0.0, 0.0, 0.0, 0.0))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = fill(color(0.0, 0.0, 0.0, 0.04))
  theme[srTableHeaderCell, {ssPressed}, StyleFill] = fill(color(0.0, 0.0, 0.0, 0.08))
  theme[srTableHeaderCell, StyleBorderColor] = color(0.0, 0.0, 0.0, 0.10)
  theme[srTableHeaderCell, StyleTextColor] = color(0.24, 0.24, 0.26, 1.0)
  theme[srTableHeaderCell, StyleMarkColor] = color(0.35, 0.35, 0.37, 1.0)
  theme[srRowItem, StyleAlternatingFill] = fill(color(0.0, 0.0, 0.0, 0.025))

proc installMacOSLabels(theme: var Theme) =
  let
    bodySize = defaultFontSize()
    titleSize = bodySize + 4.0'f32
    secondarySize = max(bodySize - 1.0'f32, 10.0'f32)
  theme.addMacOSLabelRule(
    LabelStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(0.12, 0.12, 0.13, 1.0),
    insets(0.0),
    initSize(0.0, 18.0),
    bodySize,
  )

  let iconLabel =
    initStyleSelector(srTextField, classes = @[LabelStyleClass, IconLabelStyleClass])
  theme[iconLabel, StyleTextColor] = color(0.16, 0.16, 0.17, 1.0)
  theme[iconLabel, StyleMarkColor] = styleToken("accent")
  theme[iconLabel, StyleIndicatorSize] = 18.0
  theme[iconLabel, StyleIndicatorSpacing] = 8.0
  theme[iconLabel, StyleFontSize] = bodySize
  theme.addMacOSLabelRule(
    LabelTitleStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(0.10, 0.10, 0.11, 1.0),
    insets(0.0),
    initSize(0.0, 24.0),
    titleSize,
  )
  theme.addMacOSLabelRule(
    LabelHeadingStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(0.52, 0.52, 0.54, 1.0),
    insets(0.0),
    initSize(0.0, 18.0),
    secondarySize,
  )
  theme.addMacOSLabelRule(
    LabelStatusStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(0.40, 0.40, 0.42, 1.0),
    insets(0.0),
    initSize(0.0, 18.0),
    secondarySize,
  )
  theme.addMacOSLabelRule(
    LabelFormStyleClass,
    fill(color(0.0, 0.0, 0.0, 0.0)),
    color(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    color(0.40, 0.40, 0.42, 1.0),
    insets(0.0, 2.0),
    initSize(0.0, 18.0),
    bodySize,
  )

proc installMacOSDarkTokens(theme: var Theme) =
  theme["accent"] = color(0.04, 0.52, 1.0, 1.0)
  theme["accent.pressed"] = color(0.0, 0.38, 0.82, 1.0)
  theme["progress.fill"] = styleToken("accent")
  theme["progress.border.color"] = styleToken("accent.pressed")
  theme["disabled.fill"] = color(0.18, 0.18, 0.20, 1.0)
  theme["disabled.text.color"] = color(0.48, 0.48, 0.50, 1.0)
  theme["focus.ring.color"] = color(0.04, 0.52, 1.0, 0.58)

  theme["button.fill"] = color(0.25, 0.25, 0.27, 0.98)
  theme["button.fill.hovered"] = color(0.29, 0.29, 0.31, 1.0)
  theme["button.fill.highlighted"] = color(0.17, 0.17, 0.19, 1.0)
  theme["button.fill.disabled"] = styleToken("disabled.fill")
  theme["button.fill.accent"] = styleToken("accent")
  theme["button.fill.accent.hovered"] = color(0.16, 0.60, 1.0, 1.0)
  theme["button.fill.accent.highlighted"] = styleToken("accent.pressed")
  theme["button.text.color"] = color(0.93, 0.93, 0.95, 1.0)
  theme["button.text.color.disabled"] = styleToken("disabled.text.color")
  theme["button.border.color"] = color(1.0, 1.0, 1.0, 0.14)
  theme["button.border.color.hovered"] = color(1.0, 1.0, 1.0, 0.19)
  theme["button.border.color.highlighted"] = color(1.0, 1.0, 1.0, 0.10)
  theme["button.border.color.disabled"] = color(1.0, 1.0, 1.0, 0.06)
  theme["button.border.color.accent"] = color(0.10, 0.62, 1.0, 0.82)
  theme["button.border.color.accent.hovered"] = color(0.22, 0.68, 1.0, 0.88)
  theme["button.border.color.accent.highlighted"] = color(0.0, 0.38, 0.82, 0.92)
  theme["button.shadows"] = darkControlShadow()
  theme["button.shadows.highlighted"] = newSeq[BoxShadow]()
  theme["button.shadows.disabled"] = newSeq[BoxShadow]()

  theme["choice.indicator.fill"] = color(0.22, 0.22, 0.24, 1.0)
  theme["choice.indicator.fill.highlighted"] = color(0.28, 0.28, 0.30, 1.0)
  theme["choice.indicator.fill.disabled"] = styleToken("disabled.fill")
  theme["choice.indicator.fill.selected"] = styleToken("accent")
  theme["choice.indicator.fill.selected.highlighted"] = styleToken("accent.pressed")
  theme["choice.indicator.fill.selected.disabled"] = color(0.25, 0.42, 0.60, 1.0)
  theme["choice.indicator.border.color"] = color(1.0, 1.0, 1.0, 0.22)
  theme["choice.indicator.border.color.selected"] = color(0.14, 0.64, 1.0, 0.86)
  theme["choice.indicator.border.color.highlighted"] = color(1.0, 1.0, 1.0, 0.30)
  theme["choice.indicator.border.color.disabled"] = color(1.0, 1.0, 1.0, 0.08)
  theme["choice.mark.color"] = color(1.0, 1.0, 1.0, 1.0)
  theme["choice.mark.color.disabled"] = color(1.0, 1.0, 1.0, 0.48)
  theme["choice.text.color"] = color(0.93, 0.93, 0.95, 1.0)
  theme["choice.text.color.disabled"] = styleToken("disabled.text.color")

  theme["textField.fill"] = color(0.15, 0.15, 0.17, 0.98)
  theme["textField.border.color"] = color(1.0, 1.0, 1.0, 0.18)
  theme["textField.text.color"] = color(0.93, 0.93, 0.95, 1.0)
  theme["textField.selection.color"] = color(0.04, 0.52, 1.0, 0.38)
  theme["monoText.fill"] = styleToken("textField.fill")
  theme["monoText.border.color"] = styleToken("textField.border.color")
  theme["monoText.text.color"] = styleToken("textField.text.color")
  theme["monoText.cursor.color"] = styleToken("accent")

  theme["comboBox.fill"] = styleToken("button.fill")
  theme["comboBox.border.color"] = styleToken("button.border.color")
  theme["comboBox.border.color.open"] = styleToken("accent")
  theme["comboBox.text.color"] = styleToken("textField.text.color")
  theme["comboBox.arrow.fill"] = color(1.0, 1.0, 1.0, 0.05)
  theme["comboBox.arrow.color"] = color(0.76, 0.76, 0.78, 1.0)
  theme["comboBox.item.fill"] = color(0.20, 0.20, 0.22, 0.99)
  theme["comboBox.item.fill.highlighted"] = color(0.29, 0.29, 0.31, 1.0)
  theme["comboBox.item.fill.selected"] = styleToken("accent")
  theme["comboBox.item.fill.selected.highlighted"] = styleToken("accent.pressed")
  theme["comboBox.item.text.color"] = styleToken("textField.text.color")
  theme["comboBox.item.text.color.selected"] = color(1.0, 1.0, 1.0, 1.0)

  theme["tableView.fill"] = color(0.13, 0.13, 0.15, 0.98)
  theme["tableView.border.color"] = color(1.0, 1.0, 1.0, 0.14)
  theme["tableView.column.selection.fill"] = color(0.04, 0.52, 1.0, 0.16)
  theme["tableView.column.hover.fill"] = color(1.0, 1.0, 1.0, 0.045)
  theme["scrollView.fill"] = styleToken("tableView.fill")
  theme["scrollView.border.color"] = styleToken("tableView.border.color")
  theme["scroller.track.fill"] = color(0.0, 0.0, 0.0, 0.0)
  theme["scroller.track.border.color"] = color(0.0, 0.0, 0.0, 0.0)
  theme["scroller.track.shadows"] = newSeq[BoxShadow]()
  theme["scroller.knob.fill"] = color(0.72, 0.72, 0.74, 0.45)
  theme["scroller.knob.border.color"] = color(1.0, 1.0, 1.0, 0.10)
  theme["scroller.knob.shadows"] = newSeq[BoxShadow]()
  theme["splitView.divider.fill"] = color(1.0, 1.0, 1.0, 0.08)
  theme["splitView.divider.border.color"] = color(0.0, 0.0, 0.0, 0.42)

  theme["rowItem.fill"] = color(1.0, 1.0, 1.0, 0.0)
  theme["rowItem.fill.highlighted"] = color(1.0, 1.0, 1.0, 0.065)
  theme["rowItem.fill.selected"] = styleToken("accent")
  theme["rowItem.fill.selected.highlighted"] = styleToken("accent.pressed")
  theme["rowItem.fill.disabled"] = color(1.0, 1.0, 1.0, 0.02)
  theme["rowItem.text.color"] = styleToken("textField.text.color")
  theme["rowItem.text.color.selected"] = color(1.0, 1.0, 1.0, 1.0)
  theme["rowItem.text.color.disabled"] = styleToken("disabled.text.color")
  theme["rowItem.separator.color"] = color(1.0, 1.0, 1.0, 0.08)

  theme["tab.panel.fill"] = color(0.16, 0.16, 0.18, 0.96)
  theme["tab.panel.border.color"] = color(1.0, 1.0, 1.0, 0.12)
  theme["tab.fill"] = color(0.0, 0.0, 0.0, 0.0)
  theme["tab.fill.highlighted"] = color(1.0, 1.0, 1.0, 0.07)
  theme["tab.fill.selected"] = color(0.25, 0.25, 0.27, 0.98)
  theme["tab.fill.disabled"] = color(1.0, 1.0, 1.0, 0.02)
  theme["tab.highlight.fill"] = color(0.0, 0.0, 0.0, 0.0)
  theme["tab.highlight.fill.disabled"] = color(0.0, 0.0, 0.0, 0.0)
  theme["tab.text.color"] = color(0.72, 0.72, 0.74, 1.0)
  theme["tab.text.color.selected"] = color(0.96, 0.96, 0.97, 1.0)
  theme["tab.text.color.disabled"] = styleToken("disabled.text.color")
  theme["tab.border.color"] = color(0.0, 0.0, 0.0, 0.0)
  theme["tab.border.color.highlighted"] = color(1.0, 1.0, 1.0, 0.10)
  theme["tab.border.color.selected"] = color(1.0, 1.0, 1.0, 0.16)
  theme["tab.border.color.disabled"] = color(0.0, 0.0, 0.0, 0.0)
  theme["documentTab.fill.pressed"] = color(1.0, 1.0, 1.0, 0.08)

proc installMacOSDarkControlStyles(theme: var Theme) =
  let background = color(0.12, 0.12, 0.14, 1.0)
  theme[srView, StyleBackgroundColor] = background
  theme[srView, StyleBackgroundFill] = fill(background)

  theme[srStepper, StyleFill] = fill(color(0.25, 0.25, 0.27, 1.0))
  theme[srStepper, StyleBorderColor] = color(1.0, 1.0, 1.0, 0.14)
  theme[srStepper, StyleTextColor] = color(0.93, 0.93, 0.95, 1.0)
  theme[srStepper, StyleBoxShadows] = darkControlShadow()
  theme[srStepper, {ssHighlighted}, StyleFill] = fill(color(0.17, 0.17, 0.19, 1.0))
  theme[srStepper, {ssDisabled}, StyleTextColor] = color(0.48, 0.48, 0.50, 1.0)

  theme[srSwitch, StyleFill] = fill(color(0.72, 0.72, 0.74, 0.28))
  theme[srSwitch, StyleBorderColor] = color(1.0, 1.0, 1.0, 0.10)
  theme[srSwitch, StyleKnobFill] = fill(color(0.92, 0.92, 0.94, 1.0))
  theme[srSwitch, StyleKnobBorderColor] = color(1.0, 1.0, 1.0, 0.12)
  theme[srSwitch, StyleKnobShadows] = darkKnobShadow()

  for role in [srSlider, srProgressIndicator]:
    theme[role, StyleFill] = fill(color(0.72, 0.72, 0.74, 0.25))
    theme[role, StyleHighlightFill] = styleToken("accent")
    theme[role, StyleBorderColor] = color(1.0, 1.0, 1.0, 0.08)
    theme[role, StyleKnobFill] = fill(color(0.88, 0.88, 0.90, 1.0))
    theme[role, StyleKnobBorderColor] = color(1.0, 1.0, 1.0, 0.12)
    theme[role, StyleKnobShadows] = darkKnobShadow()

  theme[srComboBox, StyleBoxShadows] = darkControlShadow()

  theme[srTableHeader, StyleFill] = fill(color(0.18, 0.18, 0.20, 0.98))
  theme[srTableHeader, StyleBorderColor] = color(1.0, 1.0, 1.0, 0.10)
  theme[srTableHeaderCell, StyleFill] = fill(color(0.0, 0.0, 0.0, 0.0))
  theme[srTableHeaderCell, {ssHovered}, StyleFill] = fill(color(1.0, 1.0, 1.0, 0.05))
  theme[srTableHeaderCell, {ssPressed}, StyleFill] = fill(color(1.0, 1.0, 1.0, 0.09))
  theme[srTableHeaderCell, StyleBorderColor] = color(1.0, 1.0, 1.0, 0.10)
  theme[srTableHeaderCell, StyleTextColor] = color(0.78, 0.78, 0.80, 1.0)
  theme[srTableHeaderCell, StyleMarkColor] = color(0.65, 0.65, 0.68, 1.0)
  theme[srRowItem, StyleAlternatingFill] = fill(color(1.0, 1.0, 1.0, 0.025))

proc installMacOSDarkLabels(theme: var Theme) =
  let
    body = initStyleSelector(srTextField, classes = @[LabelStyleClass])
    title = initStyleSelector(srTextField, classes = @[LabelTitleStyleClass])
    heading = initStyleSelector(srTextField, classes = @[LabelHeadingStyleClass])
    status = initStyleSelector(srTextField, classes = @[LabelStatusStyleClass])
    form = initStyleSelector(srTextField, classes = @[LabelFormStyleClass])
    icon =
      initStyleSelector(srTextField, classes = @[LabelStyleClass, IconLabelStyleClass])
  theme[body, StyleTextColor] = color(0.90, 0.90, 0.92, 1.0)
  theme[title, StyleTextColor] = color(0.96, 0.96, 0.97, 1.0)
  theme[heading, StyleTextColor] = color(0.62, 0.62, 0.65, 1.0)
  theme[status, StyleTextColor] = color(0.70, 0.70, 0.72, 1.0)
  theme[form, StyleTextColor] = color(0.70, 0.70, 0.72, 1.0)
  theme[icon, StyleTextColor] = color(0.90, 0.90, 0.92, 1.0)
  theme[icon, StyleMarkColor] = styleToken("accent")

proc initMacOSTheme*(): Theme =
  result = initTheme()
  result.installMacOSTokens()
  result.installMacOSControlStyles()
  result.installMacOSLabels()

proc initMacOSDarkTheme*(): Theme =
  result = initMacOSTheme()
  result.installMacOSDarkTokens()
  result.installMacOSDarkControlStyles()
  result.installMacOSDarkLabels()

registerThemeFactory("macos", initMacOSTheme)
registerThemeFactory("mac", initMacOSTheme)
registerThemeFactory("modern-macos", initMacOSTheme)
registerThemeFactory("macos-dark", initMacOSDarkTheme)
registerThemeFactory("dark-macos", initMacOSDarkTheme)
registerThemeFactory("modern-macos-dark", initMacOSDarkTheme)
