import std/[os, unittest]

import sigils/core

import merenda/nimkit

func brightness(color: Color): float32 =
  color.r + color.g + color.b

func rgbaColor(r, g, b, a: int): Color =
  color(
    r.float32 / 255.0'f32,
    g.float32 / 255.0'f32,
    b.float32 / 255.0'f32,
    a.float32 / 255.0'f32,
  )

proc checkRootPinstripesDisabled(theme: Theme) =
  let
    appearance = initAppearance(theme)
    viewStyle = controlStyle(srView)

  check appearance.resolveColor(
    viewStyle, StyleBackgroundPinstripeHighlightColor, color(1.0, 1.0, 1.0, 1.0)
  ) == color(0.0, 0.0, 0.0, 0.0)
  check appearance.resolveColor(
    viewStyle, StyleBackgroundPinstripeColor, color(1.0, 1.0, 1.0, 1.0)
  ) == color(0.0, 0.0, 0.0, 0.0)
  check appearance.resolveLength(viewStyle, StyleBackgroundPinstripePeriod, 1.0'f32) ==
    0.0'f32
  check appearance.resolveLength(viewStyle, StyleBackgroundPinstripeHeight, 1.0'f32) ==
    0.0'f32

proc checkDocumentTabsUseThemeTabStyle(theme: Theme) =
  let
    appearance = initAppearance(theme)
    fallbackFill = fill(color(0.0, 0.0, 0.0, 0.0))
    fallbackColor = color(0.0, 0.0, 0.0, 1.0)
    tabStyle = controlStyle(srDocumentTab)
    selectedTabStyle = controlStyle(srDocumentTab, {ssSelected})
    tabBarStyle = controlStyle(srDocumentTabBar)
    tabButtonStyle = controlStyle(srDocumentTabButton)
    highlightedTabButtonStyle = controlStyle(srDocumentTabButton, {ssHighlighted})

  check appearance.resolveChromeName(tabStyle) == FlatTransparentChromeName
  check appearance.resolveChromeName(tabBarStyle) == FlatTransparentChromeName
  check appearance.resolveChromeName(tabButtonStyle) == FlatTransparentChromeName
  check appearance.resolveFill(tabBarStyle, fallbackFill) ==
    appearance.fillToken("tab.panel.fill", fallbackFill)
  check appearance.resolveColor(tabBarStyle, StyleBorderColor, fallbackColor) ==
    appearance.colorToken("tab.panel.border.color", fallbackColor)
  check appearance.resolveFill(tabStyle, fallbackFill) ==
    appearance.fillToken("tab.fill", fallbackFill)
  check appearance.resolveFill(selectedTabStyle, fallbackFill) ==
    appearance.fillToken("tab.fill.selected", fallbackFill)
  check appearance.resolveFill(tabStyle, fallbackFill, StyleHighlightFill) ==
    appearance.fillToken("tab.highlight.fill", fallbackFill)
  check appearance.resolveColor(tabStyle, StyleBorderColor, fallbackColor) ==
    appearance.colorToken("tab.border.color", fallbackColor)
  check appearance.resolveColor(selectedTabStyle, StyleBorderColor, fallbackColor) ==
    appearance.colorToken("tab.border.color.selected", fallbackColor)
  check appearance.resolveColor(tabStyle, StyleTextColor, fallbackColor) ==
    appearance.colorToken("tab.text.color", fallbackColor)
  check appearance.resolveColor(selectedTabStyle, StyleTextColor, fallbackColor) ==
    appearance.colorToken("tab.text.color.selected", fallbackColor)
  check appearance.resolveFill(tabButtonStyle, fallbackFill) ==
    appearance.fillToken("tab.fill", fallbackFill)
  check appearance.resolveFill(highlightedTabButtonStyle, fallbackFill) ==
    appearance.fillToken("tab.fill.highlighted", fallbackFill)
  check appearance.resolveColor(tabButtonStyle, StyleMarkColor, fallbackColor) ==
    appearance.colorToken("tab.text.color", fallbackColor)

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

func aquaChoiceSelectedFill(): Fill =
  linear(rgbaColor(122, 232, 255, 255), rgbaColor(0, 124, 238, 255), fgaDiagTLBR)

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

func aquaComboItemSelectedFill(): Fill =
  linear(
    rgbaColor(46, 128, 230, 217),
    rgbaColor(0, 71, 184, 217),
    rgbaColor(0, 31, 117, 217),
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

func aquaComboBoxFill(): Fill =
  linear(
    rgbaColor(255, 255, 255, 226),
    rgbaColor(238, 242, 244, 214),
    rgbaColor(196, 207, 212, 196),
    fgaY,
    92'u8,
  )

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

const CustomChromeName = "custom-widget-chrome"

let CustomChromeFill = fill(color(0.42, 0.10, 0.74, 1.0))

type CustomFillChrome = ref object of Chrome

protocol CustomFillChromeProtocol of ChromeProtocol:
  method chromeFillFor(chrome: CustomFillChrome, context: ChromeContext): Fill =
    discard chrome
    discard context
    CustomChromeFill

proc newCustomFillChrome(): Chrome =
  let chrome = CustomFillChrome()
  discard chrome.withProtocol(CustomFillChromeProtocol)
  Chrome(chrome)

proc withCleanThemeEnv(body: proc() {.closure.}) =
  let
    existed = existsEnv(NimKitThemeEnv)
    value = getEnv(NimKitThemeEnv)
  delEnv(NimKitThemeEnv)
  try:
    body()
  finally:
    if existed:
      putEnv(NimKitThemeEnv, value)
    else:
      delEnv(NimKitThemeEnv)

suite "nimkit theme":
  test "NimKit theme env obeys override ignore flag":
    withCleanThemeEnv(
      proc() =
        putEnv(NimKitThemeEnv, "banner")
        when defined(nimkitIgnoreEnvOverrides):
          check themeNameFromEnv() == ""
        else:
          check themeNameFromEnv() == "banner"
    )

  test "edge insets shrink rectangles without negative sizes":
    check rect(10, 20, 100, 50).inset(insets(2, 4, 6, 8)) == rect(14, 22, 88, 42)
    check rect(0, 0, 10, 10).inset(insets(8)) == rect(8, 8, 0, 0)

  test "style selectors match role state id and classes":
    let context = initStyleContext(
      srButton,
      {ssFocused, ssFocusVisible},
      id = "primary",
      classes = @["default", "toolbar"],
    )

    check initStyleSelector(srButton).matches(context)
    check initStyleSelector(srButton, {ssFocused}).matches(context)
    check initStyleSelector(srButton, id = "primary").matches(context)
    check initStyleSelector(srButton, classes = @["toolbar"]).matches(context)
    check not initStyleSelector(srTextField).matches(context)
    check not initStyleSelector(srButton, {ssDisabled}).matches(context)
    check not initStyleSelector(srButton, id = "secondary").matches(context)

  test "style rule specificity beats insertion order":
    var theme = initTheme()
    let
      fallback = color(0.0, 0.0, 0.0, 1.0)
      broadText = color(0.12, 0.13, 0.14, 1.0)
      highlightedText = color(0.82, 0.40, 0.12, 1.0)
      highlightedContext = controlStyle(srButton, {ssHighlighted})

    theme[srButton, {ssHighlighted}, StyleTextColor] = highlightedText
    theme[srButton, StyleTextColor] = broadText

    check theme.resolveColor(controlStyle(srButton), StyleTextColor, fallback) ==
      broadText
    check theme.resolveColor(highlightedContext, StyleTextColor, fallback) ==
      highlightedText

  test "style rules prefer more matching states over later weaker states":
    var theme = initTheme()
    let
      fallback = color(0.0, 0.0, 0.0, 1.0)
      pressedText = color(0.16, 0.38, 0.82, 1.0)
      highlightedPressedText = color(0.90, 0.24, 0.74, 1.0)
      context = controlStyle(srButton, {ssHighlighted, ssPressed})

    theme[srButton, {ssHighlighted, ssPressed}, StyleTextColor] = highlightedPressedText
    theme[srButton, {ssPressed}, StyleTextColor] = pressedText

    check theme.resolveColor(context, StyleTextColor, fallback) == highlightedPressedText

  test "style rules keep last-write-wins for equal specificity":
    var theme = initTheme()
    let
      fallback = color(0.0, 0.0, 0.0, 1.0)
      firstText = color(0.18, 0.24, 0.30, 1.0)
      secondText = color(0.44, 0.52, 0.62, 1.0)
      context = controlStyle(srButton, {ssHighlighted, ssPressed})

    theme[srButton, {ssHighlighted}, StyleTextColor] = firstText
    theme[srButton, {ssPressed}, StyleTextColor] = secondText

    check theme.resolveColor(context, StyleTextColor, fallback) == secondText

  test "style context stores role and control states":
    let context = controlStyle(
      srButton,
      {
        ssDisabled, ssHighlighted, ssHovered, ssActive, ssFocused, ssFocusVisible,
        ssFocusWithin, ssSelected, ssOpen, ssAlternating, ssPressed, ssAccent,
      },
      id = "primary",
      classes = @["default", "toolbar"],
    )

    check context.role == srButton
    check context.id == "primary"
    check context.classes == @["default", "toolbar"]
    check context.states == {
      ssDisabled, ssHighlighted, ssHovered, ssActive, ssFocused, ssFocusVisible,
      ssFocusWithin, ssSelected, ssOpen, ssAlternating, ssPressed, ssAccent,
    }

  test "chrome delegates install by name and selectors choose per widget":
    var theme = initTheme()
    theme.installChrome(CustomChromeName, newCustomFillChrome())
    theme[initStyleSelector(srButton, id = "special"), StyleChrome] =
      styleKeyword(CustomChromeName)

    let
      appearance = initAppearance(theme)
      normalContext = controlStyle(srButton)
      specialContext = controlStyle(srButton, id = "special")
      baseFill = fill(color(0.12, 0.20, 0.34, 1.0))

    check appearance.hasChrome(CustomChromeName)
    check appearance.resolveChromeName(normalContext) == AquaChromeName
    check appearance.resolveChromeName(specialContext) == CustomChromeName
    check appearance.chromeFill(
      chromeContext(CustomChromeName, crButton, cpFace, baseFill)
    ) == CustomChromeFill
    check appearance.chromeFill(
      chromeContext("missing-widget-chrome", crButton, cpFace, baseFill)
    ) == baseFill

  test "style token store resolves typed values and nested references":
    let
      parent = newStyleTokenStore()
      child = newStyleTokenStore(parent)
      accent = color(0.7, 0.2, 0.3, 1.0)
      minSize = initSize(24.0, 18.0)
      padding = insets(1, 2, 3, 4)
      shadows = @[dropShadow(color(0, 0, 0, 0.25), y = 2.0, blur = 4.0)]

    parent["accent"] = accent
    parent["space"] = 6.0
    parent["minimum.size"] = minSize
    parent["padding"] = padding
    parent["shadow"] = shadows
    child["nested.accent"] = styleToken("accent")

    var value: StyleValue
    check child.resolveToken("nested.accent", value)
    check value.kind == svColor
    check value.color == accent

    let appearance = Appearance(theme: Theme(tokens: child))
    check appearance.colorToken("nested.accent", color(0, 0, 0, 1)) == accent
    check appearance.lengthToken("space", 0.0) == 6.0
    check appearance.sizeToken("minimum.size", initSize(0, 0)) == minSize
    check appearance.insetsToken("padding", insets(0)) == padding
    check appearance.shadowsToken("shadow", @[]) == shadows
    check appearance.colorToken("missing", accent) == accent

  test "appearance tokens and style patches resolve into concrete styles":
    var appearance = initAppearance()
    let
      buttonFill = color(0.11, 0.22, 0.33, 1.0)
      focusRing = color(0.24, 0.42, 0.90, 0.75)
      fieldText = color(0.44, 0.55, 0.66, 1.0)
      buttonHighlight = color(0.95, 0.96, 0.97, 0.44)
      buttonShadow = color(0.04, 0.05, 0.06, 0.22)
      buttonMinimum = initSize(72.0, 32.0)
      buttonInsets = insets(2.0, 10.0)
      buttonShadows =
        @[
          dropShadow(color(0, 0, 0, 0.35), y = 2.0, blur = 5.0),
          insetShadow(color(1, 1, 1, 0.18), y = -1.0, blur = 1.0),
        ]

    appearance.theme["field.text.override"] = fieldText
    appearance[srButton, StyleFill] = buttonFill
    appearance[srButton, StyleCornerRadius] = 9.0
    appearance[srButton, StyleFocusRingColor] = focusRing
    appearance[srButton, StyleTextInsets] = buttonInsets
    appearance[srButton, StyleTextHighlightColor] = buttonHighlight
    appearance[srButton, StyleTextShadowColor] = buttonShadow
    appearance[srButton, StyleMinimumSize] = buttonMinimum
    appearance[srButton, StyleBoxShadows] = buttonShadows
    appearance[srButton, StyleChrome] = styleKeyword(DefaultChromeName)
    appearance[srTextField, StyleTextColor] = styleToken("field.text.override")
    appearance[srTextField, StyleBorderWidth] = 4.0

    let
      buttonStyle = appearance.resolveButtonStyle(controlStyle(srButton))
      textFieldStyle = appearance.resolveTextFieldStyle(
        controlStyle(srTextField), color(0.1, 0.1, 0.1, 1.0)
      )

    check buttonStyle.box.fill == buttonFill
    check buttonStyle.box.cornerRadius == 9.0
    check buttonStyle.box.focusRingColor == focusRing
    check buttonStyle.box.shadows == buttonShadows
    check buttonStyle.text.insets == buttonInsets
    check buttonStyle.textHighlightColor == buttonHighlight
    check buttonStyle.textShadowColor == buttonShadow
    check buttonStyle.minSize == buttonMinimum
    check buttonStyle.chrome == DefaultChromeName
    check textFieldStyle.text.color == fieldText
    check textFieldStyle.box.borderWidth == 4.0
    let textPatch = appearance[srTextField, StyleTextColor]
    check textPatch.kind == svToken
    check textPatch.token == "field.text.override"

  test "appearance overrides do not mutate the base theme":
    let theme = initTheme()
    var
      firstAppearance = initAppearance(theme)
      secondAppearance = initAppearance(theme)

    let
      baseStyle = theme.resolveButtonStyle(controlStyle(srButton))
      overrideFill = color(0.67, 0.18, 0.22, 1.0)

    firstAppearance.theme["button.fill"] = overrideFill
    firstAppearance[srButton, StyleCornerRadius] = 11.0

    check firstAppearance.resolveButtonStyle(controlStyle(srButton)).box.fill ==
      overrideFill
    check firstAppearance.resolveButtonStyle(controlStyle(srButton)).box.cornerRadius ==
      11.0
    check secondAppearance.resolveButtonStyle(controlStyle(srButton)).box.fill ==
      baseStyle.box.fill
    check secondAppearance.resolveButtonStyle(controlStyle(srButton)).box.cornerRadius ==
      baseStyle.box.cornerRadius
    check theme.resolveButtonStyle(controlStyle(srButton)).box.fill == baseStyle.box.fill
    check theme.resolveButtonStyle(controlStyle(srButton)).box.cornerRadius ==
      baseStyle.box.cornerRadius

  test "default theme exposes resolved button and text field styles":
    let theme = initTheme()
    let
      appearance = initAppearance(theme)
      defaultButtonStyle = appearance.resolveButtonStyle(controlStyle(srButton))
      hoveredButtonStyle =
        appearance.resolveButtonStyle(controlStyle(srButton, {ssHovered}))
      buttonStyle =
        appearance.resolveButtonStyle(controlStyle(srButton, {ssHighlighted}))
      accentButtonStyle =
        appearance.resolveButtonStyle(controlStyle(srButton, {ssAccent}))
      accentHoveredButtonStyle =
        appearance.resolveButtonStyle(controlStyle(srButton, {ssAccent, ssHovered}))
      accentHighlightedButtonStyle =
        appearance.resolveButtonStyle(controlStyle(srButton, {ssAccent, ssHighlighted}))
      checkBoxStyle =
        appearance.resolveChoiceButtonStyle(controlStyle(srCheckBox, {ssSelected}))
      checkBoxHoverStyle =
        appearance.resolveChoiceButtonStyle(controlStyle(srCheckBox, {ssHovered}))
      checkBoxSelectedHoverStyle = appearance.resolveChoiceButtonStyle(
        controlStyle(srCheckBox, {ssSelected, ssHovered})
      )
      radioStyle =
        appearance.resolveChoiceButtonStyle(controlStyle(srRadioButton, {ssSelected}))
      textFieldStyle = theme.resolveTextFieldStyle(
        controlStyle(srTextField), color(0.2, 0.3, 0.4, 1.0)
      )
      bodyLabelStyle = theme.resolveTextFieldStyle(
        controlStyle(srTextField, classes = @[LabelStyleClass])
      )
      titleLabelStyle = theme.resolveTextFieldStyle(
        controlStyle(srTextField, classes = @[LabelStyleClass, LabelTitleStyleClass])
      )
      headingLabelStyle = theme.resolveTextFieldStyle(
        controlStyle(srTextField, classes = @[LabelStyleClass, LabelHeadingStyleClass])
      )
      statusLabelStyle = theme.resolveTextFieldStyle(
        controlStyle(srTextField, classes = @[LabelStyleClass, LabelStatusStyleClass])
      )
      formLabelStyle = theme.resolveTextFieldStyle(
        controlStyle(srTextField, classes = @[LabelStyleClass, LabelFormStyleClass])
      )
      comboBoxStyle =
        appearance.resolveComboBoxStyle(controlStyle(srComboBox, {ssOpen}))
      comboBoxItemStyle =
        appearance.resolveTextFieldStyle(controlStyle(srComboBoxItem, {ssSelected}))
      sliderStyle = appearance.resolveSliderStyle(controlStyle(srSlider))
      progressStyle =
        appearance.resolveProgressIndicatorStyle(controlStyle(srProgressIndicator))
      selectedRowStyle = controlStyle(srRowItem, {ssSelected})
      selectedHighlightedRowStyle = controlStyle(srRowItem, {ssSelected, ssHighlighted})
      scrollViewStyle = appearance.resolveScrollViewStyle(controlStyle(srScroller))
      cascadingScrollViewStyle =
        appearance.resolveScrollViewStyle(controlStyle(srCascadingScroller))
      viewStyle = controlStyle(srView)
      tabStyle = controlStyle(srTab)
      selectedTabStyle = controlStyle(srTab, {ssSelected})

    check appearance.theme.rules.len == theme.rules.len
    check theme.tokens != nil
    check theme.rules.len > 0
    check buttonStyle.box.borderWidth > 0.0
    check buttonStyle.box.cornerRadius > 0.0
    check buttonStyle.box.focusRingWidth > 0.0
    check buttonStyle.box.focusRingInset < 0.0
    check buttonStyle.box.focusRingColor == color(0.28, 0.64, 1.0, 0.82)
    check buttonStyle.box.focusRingColor != buttonStyle.box.fill.centerColor()
    check appearance.hasChrome(DefaultChromeName)
    check appearance.hasChrome(AquaChromeName)
    check defaultButtonStyle.chrome == AquaChromeName
    check checkBoxStyle.chrome == AquaChromeName
    check radioStyle.chrome == AquaChromeName
    check comboBoxStyle.chrome == AquaChromeName
    check appearance.resolveChromeName(controlStyle(srTab)) == AquaChromeName
    check appearance.resolveChromeName(controlStyle(srTabPanel)) == AquaChromeName
    check appearance.resolveFill(
      viewStyle, fill(color(0.0, 0.0, 0.0, 1.0)), StyleBackgroundFill
    ) == aquaWindowBackgroundFill()
    check appearance.resolveColor(
      viewStyle, StyleBackgroundPinstripeHighlightColor, color(0.0, 0.0, 0.0, 0.0)
    ) == rgbaColor(255, 255, 255, 95)
    check appearance.resolveColor(
      viewStyle, StyleBackgroundPinstripeColor, color(0.0, 0.0, 0.0, 0.0)
    ) == color(0.0, 0.0, 0.0, 0.0)
    check appearance.resolveLength(viewStyle, StyleBackgroundPinstripePeriod, 0.0'f32) ==
      4.0'f32
    check appearance.resolveLength(viewStyle, StyleBackgroundPinstripeHeight, 0.0'f32) ==
      1.0'f32
    check appearance.resolveFill(tabStyle, fill(color(0.0, 0.0, 0.0, 1.0))) ==
      fill(rgbaColor(220, 238, 255, 198))
    check appearance.resolveFill(
      tabStyle, fill(color(0.0, 0.0, 0.0, 0.0)), StyleHighlightFill
    ) == fill(rgbaColor(255, 255, 255, 136))
    check appearance.resolveColor(tabStyle, StyleTextColor, color(0.0, 0.0, 0.0, 1.0)) ==
      color(0.14, 0.15, 0.18, 1.0)
    check appearance.resolveColor(
      selectedTabStyle, StyleBorderColor, color(0.0, 0.0, 0.0, 1.0)
    ) == rgbaColor(34, 102, 210, 232)
    check defaultButtonStyle.box.shadows.len == 0
    check buttonStyle.box.shadows.len == 0
    check defaultButtonStyle.box.fill == aquaButtonFill()
    check defaultButtonStyle.box.fill.centerColor().a < 1.0'f32
    check hoveredButtonStyle.box.fill == aquaButtonHoverFill()
    check buttonStyle.box.fill == aquaButtonPressedFill()
    check accentButtonStyle.box.fill == aquaAccentButtonFill()
    check accentHoveredButtonStyle.box.fill == aquaAccentButtonHoverFill()
    check accentHighlightedButtonStyle.box.fill == aquaAccentButtonPressedFill()
    check hoveredButtonStyle.box.borderColor == rgbaColor(38, 156, 232, 196)
    check buttonStyle.box.borderColor == rgbaColor(19, 93, 180, 161)
    check accentButtonStyle.box.borderColor == rgbaColor(31, 112, 204, 145)
    check accentHoveredButtonStyle.box.borderColor == rgbaColor(38, 156, 232, 196)
    check accentHighlightedButtonStyle.box.borderColor == rgbaColor(19, 93, 180, 161)
    check buttonStyle.box.borderWidth == 0.55'f32
    check buttonStyle.box.cornerRadius == 14.0
    check buttonStyle.text.color == rgbaColor(5, 16, 27, 248)
    check defaultButtonStyle.textHighlightColor == rgbaColor(255, 255, 255, 82)
    check defaultButtonStyle.textShadowColor == rgbaColor(0, 0, 0, 54)
    check theme.resolveButtonStyle(controlStyle(srButton, {ssDisabled})).textHighlightColor ==
      color(1.0, 1.0, 1.0, 0.16)
    check accentButtonStyle.text.color == rgbaColor(5, 16, 27, 248)
    check buttonStyle.minSize == initSize(0.0, 32.0)
    check buttonStyle.buttonTextRect(rect(0, 0, 100, 30)) == rect(8, 0, 84, 30)

    check checkBoxStyle.indicatorSize > 0.0
    check checkBoxStyle.indicatorSpacing > 0.0
    check checkBoxStyle.minSize == initSize(0.0, 20.0)
    check checkBoxHoverStyle.indicator.fill ==
      appearance.resolveChoiceButtonStyle(controlStyle(srCheckBox, {ssHighlighted})).indicator.fill
    check checkBoxSelectedHoverStyle.indicator.fill ==
      appearance.resolveChoiceButtonStyle(
        controlStyle(srCheckBox, {ssSelected, ssHighlighted})
      ).indicator.fill
    check checkBoxStyle.indicator.fill == aquaChoiceSelectedFill()
    check checkBoxStyle.indicator.borderColor == rgbaColor(0, 82, 191, 245)
    check checkBoxStyle.indicator.cornerRadius == 3.0
    check checkBoxStyle.indicator.focusRingColor == color(0.28, 0.64, 1.0, 0.82)
    check radioStyle.indicator.borderColor == rgbaColor(88, 90, 88, 220)
    check radioStyle.indicator.cornerRadius == 8.0
    check radioStyle.indicator.focusRingColor == color(0.28, 0.64, 1.0, 0.82)
    check checkBoxStyle.choiceIndicatorRect(rect(0, 0, 100, 24)) == rect(2, 3, 18, 18)
    check checkBoxStyle.choiceTextRect(rect(0, 0, 100, 24)) == rect(27, 0, 71, 24)

    check textFieldStyle.box.borderWidth > 0.0
    check textFieldStyle.box.cornerRadius == 6.0
    check textFieldStyle.box.focusRingWidth > 0.0
    check textFieldStyle.box.fill == aquaTextFieldFill()
    check textFieldStyle.box.fill.centerColor().a < 1.0'f32
    check textFieldStyle.box.borderColor == rgbaColor(88, 116, 158, 220)
    check textFieldStyle.box.shadows.len == 0
    check textFieldStyle.box.focusRingColor == color(0.28, 0.64, 1.0, 0.82)
    check textFieldStyle.text.color == color(0.2, 0.3, 0.4, 1.0)
    check textFieldStyle.selectionColor == color(0.24, 0.56, 1.0, 0.34)
    check textFieldStyle.minSize == initSize(80.0, 26.0)
    check textFieldStyle.textFieldTextRect(rect(0, 0, 100, 30)) == rect(10, 0, 80, 30)

    check bodyLabelStyle.box.fill.centerColor().a == 0.0
    check bodyLabelStyle.box.borderWidth == 0.0
    check bodyLabelStyle.box.focusRingWidth == 0.0
    check bodyLabelStyle.text.color == color(0.09, 0.12, 0.18, 1.0)
    check bodyLabelStyle.minSize == initSize(0.0, 18.0)
    check bodyLabelStyle.box.shadows.len == 0
    check titleLabelStyle.box.fill == aquaTitleLabelFill()
    check titleLabelStyle.box.fill.centerColor().a < 1.0'f32
    check titleLabelStyle.box.borderColor == rgbaColor(92, 135, 196, 138)
    check titleLabelStyle.box.borderWidth == 1.0
    check titleLabelStyle.box.cornerRadius == 8.0
    check titleLabelStyle.box.shadows == aquaLabelShadows()
    check titleLabelStyle.text.insets == insets(0.0, 12.0)
    check titleLabelStyle.minSize == initSize(0.0, 28.0)
    check headingLabelStyle.box.fill == aquaHeadingLabelFill()
    check headingLabelStyle.box.borderColor == rgbaColor(104, 148, 205, 126)
    check headingLabelStyle.box.cornerRadius == 7.0
    check headingLabelStyle.box.shadows == aquaLabelShadows()
    check headingLabelStyle.minSize == initSize(0.0, 24.0)
    check statusLabelStyle.box.fill == aquaStatusLabelFill()
    check statusLabelStyle.box.borderColor == rgbaColor(88, 168, 112, 124)
    check statusLabelStyle.box.cornerRadius == 7.0
    check statusLabelStyle.box.shadows == aquaStatusLabelShadows()
    check statusLabelStyle.text.color == color(0.06, 0.25, 0.14, 1.0)
    check formLabelStyle.box.borderWidth == 0.0
    check formLabelStyle.text.color == color(0.10, 0.14, 0.22, 1.0)

    check comboBoxStyle.box.fill == aquaComboBoxFill()
    check comboBoxStyle.box.borderColor == rgbaColor(70, 88, 205, 228)
    check comboBoxStyle.box.cornerRadius == 12.0
    check comboBoxStyle.minSize == initSize(90.0, 26.0)
    check comboBoxStyle.arrowWidth == 28.0
    check comboBoxStyle.arrowFill == aquaComboArrowFill()
    check comboBoxStyle.arrowColor == color(0.0, 0.12, 0.34, 1.0)
    check comboBoxStyle.comboBoxArrowRect(rect(0, 0, 100, 28)) == rect(72, 0, 28, 28)
    check comboBoxStyle.comboBoxTextRect(rect(0, 0, 100, 28)) == rect(10, 0, 52, 28)
    check comboBoxItemStyle.box.fill == aquaComboItemSelectedFill()
    check comboBoxItemStyle.text.color == color(1.0, 1.0, 1.0, 1.0)
    check comboBoxItemStyle.minSize == initSize(0.0, 22.0)
    check appearance.resolveFill(selectedRowStyle, fill(color(0.0, 0.0, 0.0, 0.0))) ==
      aquaRowItemSelectedFill()
    check appearance.resolveFill(
      selectedHighlightedRowStyle, fill(color(0.0, 0.0, 0.0, 0.0))
    ) == aquaRowItemSelectedHighlightedFill()
    check sliderStyle.knob.fill == aquaSliderKnobFill()
    check sliderStyle.knob.fill.centerColor().a > aquaTextFieldFill().centerColor().a
    check sliderStyle.activeTrack.fill == aquaSliderProgressFill()
    check sliderStyle.activeTrack.fill.centerColor().a >
      aquaAccentButtonFill().centerColor().a
    check progressStyle.knob.fill == aquaSliderKnobFill()
    check progressStyle.activeTrack.fill == aquaSliderProgressFill()

    check scrollViewStyle.scrollerTrack.fill == aquaScrollerTrackFill()
    check scrollViewStyle.scrollerTrack.fill.centerColor().a < 1.0'f32
    check scrollViewStyle.scrollerTrack.borderColor == rgbaColor(78, 108, 155, 138)
    check scrollViewStyle.scrollerTrack.borderWidth == 0.7'f32
    check scrollViewStyle.scrollerTrack.cornerRadius == 6.0
    check scrollViewStyle.scrollerTrack.shadows == aquaScrollerTrackShadows()
    check scrollViewStyle.scrollerKnob.fill == aquaButtonFill()
    check scrollViewStyle.scrollerKnob.borderColor == rgbaColor(30, 80, 180, 150)
    check scrollViewStyle.scrollerKnob.cornerRadius == 6.0
    check scrollViewStyle.scrollerKnob.shadows == aquaScrollerKnobShadows()
    check cascadingScrollViewStyle.scrollerTrack.fill == aquaScrollerTrackFill()
    check cascadingScrollViewStyle.scrollerKnob.fill == aquaButtonFill()
    check cascadingScrollViewStyle.scrollerKnob.shadows == aquaScrollerKnobShadows()

  test "peachy highlighted buttons keep contrast with peach text":
    let
      theme = initPeachyTheme()
      buttonStyle = theme.resolveButtonStyle(controlStyle(srButton))
      highlightedStyle =
        theme.resolveButtonStyle(controlStyle(srButton, {ssHighlighted}))

    check highlightedStyle.box.fill.centerColor().brightness <
      buttonStyle.text.color.brightness
    check highlightedStyle.textHighlightColor.brightness <
      highlightedStyle.text.color.brightness
    check highlightedStyle.textHighlightColor.a <= 0.20'f32

  test "peachy combo boxes use peach chrome instead of Aqua colors":
    let
      theme = initPeachyTheme()
      comboStyle = theme.resolveComboBoxStyle(controlStyle(srComboBox))
      openStyle = theme.resolveComboBoxStyle(controlStyle(srComboBox, {ssOpen}))
      arrowColor = comboStyle.arrowFill.centerColor()

    check comboStyle.chrome == FlatTransparentChromeName
    check openStyle.chrome == FlatTransparentChromeName
    check comboStyle.box.fill != aquaComboBoxFill()
    check comboStyle.arrowFill != aquaComboArrowFill()
    check arrowColor.r > arrowColor.g
    check arrowColor.r >= arrowColor.b

  test "peachy and synthwave themes do not inherit Aqua root pinstripes":
    checkRootPinstripesDisabled(initPeachyTheme())
    checkRootPinstripesDisabled(initSynthwave83Theme())

  test "peachy and synthwave document tabs use theme tab styling":
    checkDocumentTabsUseThemeTabStyle(initPeachyTheme())
    checkDocumentTabsUseThemeTabStyle(initSynthwave83Theme())

  test "banner theme exposes generated banner palette as an opt-in theme":
    let
      theme = initBannerTheme()
      buttonStyle = theme.resolveButtonStyle(controlStyle(srButton))
      highlightedButtonStyle =
        theme.resolveButtonStyle(controlStyle(srButton, {ssHighlighted}))
      checkBoxStyle =
        theme.resolveChoiceButtonStyle(controlStyle(srCheckBox, {ssSelected}))
      textFieldStyle = theme.resolveTextFieldStyle(controlStyle(srTextField))
      comboBoxStyle = theme.resolveComboBoxStyle(controlStyle(srComboBox, {ssOpen}))
      comboBoxItemStyle = theme.resolveTextFieldStyle(
        controlStyle(srComboBoxItem, {ssSelected, ssHovered})
      )
      tabStyle = controlStyle(srTab)

    check buttonStyle.box.fill == color(0.89, 0.38, 0.21, 1.0)
    check highlightedButtonStyle.box.fill == color(0.62, 0.24, 0.14, 1.0)
    check checkBoxStyle.indicator.fill == color(0.89, 0.38, 0.21, 1.0)
    check textFieldStyle.box.fill == color(1.0, 0.97, 0.94, 1.0)
    check textFieldStyle.selectionColor == color(0.31, 0.58, 0.54, 0.32)
    check comboBoxStyle.box.borderColor == color(0.31, 0.58, 0.54, 1.0)
    check comboBoxStyle.arrowColor == color(0.16, 0.15, 0.15, 1.0)
    check comboBoxItemStyle.box.fill == color(0.19, 0.38, 0.35, 1.0)
    check buttonStyle.chrome == DefaultChromeName
    check checkBoxStyle.chrome == DefaultChromeName
    check comboBoxStyle.chrome == DefaultChromeName
    check buttonStyle.textHighlightColor.a == 0.0
    check buttonStyle.textShadowColor.a == 0.0
    check theme.resolveChromeName(tabStyle) == DefaultChromeName
    check theme.resolveFill(tabStyle, fill(color(0.0, 0.0, 0.0, 1.0))) ==
      fill(color(0.86, 0.82, 0.75, 1.0))
    check theme.resolveColor(tabStyle, StyleTextColor, color(0.0, 0.0, 0.0, 1.0)) ==
      color(0.11, 0.10, 0.10, 1.0)

  test "macOS theme provides a modern flat control appearance":
    let
      theme = initMacOSTheme()
      buttonStyle = theme.resolveButtonStyle(controlStyle(srButton))
      accentStyle = theme.resolveButtonStyle(controlStyle(srButton, {ssAccent}))
      checkBoxStyle =
        theme.resolveChoiceButtonStyle(controlStyle(srCheckBox, {ssSelected}))
      textFieldStyle = theme.resolveTextFieldStyle(controlStyle(srTextField))
      switchStyle = theme.resolveSwitchButtonStyle(controlStyle(srSwitch, {ssSelected}))

    check buttonStyle.chrome == DefaultChromeName
    check buttonStyle.box.cornerRadius == 7.0'f32
    check buttonStyle.textHighlightColor.a == 0.0'f32
    check buttonStyle.textShadowColor.a == 0.0'f32
    check accentStyle.box.fill == color(0.04, 0.52, 1.0, 1.0)
    check accentStyle.text.color == color(1.0, 1.0, 1.0, 1.0)
    check checkBoxStyle.chrome == DefaultChromeName
    check checkBoxStyle.indicator.cornerRadius == 4.0'f32
    check checkBoxStyle.indicator.fill == color(0.04, 0.52, 1.0, 1.0)
    check theme.resolveChromeName(controlStyle(srTextField)) == DefaultChromeName
    check textFieldStyle.box.cornerRadius == 6.0'f32
    check switchStyle.chrome == DefaultChromeName
    check switchStyle.track.fill == color(0.20, 0.78, 0.35, 1.0)
    let
      stepperStyle = theme.resolveButtonStyle(controlStyle(srStepper))
      pressedStepperStyle =
        theme.resolveButtonStyle(controlStyle(srStepper, {ssHighlighted}))
      disabledStepperStyle =
        theme.resolveButtonStyle(controlStyle(srStepper, {ssDisabled}))
    check stepperStyle.chrome == DefaultChromeName
    check stepperStyle.box.fill == color(0.89, 0.89, 0.90, 1.0)
    check stepperStyle.box.cornerRadius == 8.0'f32
    check stepperStyle.minSize == initSize(72.0, 28.0)
    check pressedStepperStyle.box.fill == color(0.80, 0.80, 0.82, 1.0)
    check disabledStepperStyle.text.color == color(0.58, 0.58, 0.60, 1.0)
    checkRootPinstripesDisabled(theme)

    for labelClass in [
      LabelStyleClass, LabelTitleStyleClass, LabelHeadingStyleClass,
      LabelStatusStyleClass, LabelFormStyleClass,
    ]:
      let context = controlStyle(srTextField, classes = @[labelClass])
      check theme.resolveChromeName(context) == DefaultChromeName
      check theme.resolveTextFieldStyle(context).box.shadows.len == 0

  test "macOS labels use typographic hierarchy instead of bordered bands":
    let theme = initMacOSTheme()
    let transparent = fill(color(0.0, 0.0, 0.0, 0.0))
    let
      title = theme.resolveTextFieldStyle(
        controlStyle(srTextField, classes = @[LabelStyleClass, LabelTitleStyleClass])
      )
      heading = theme.resolveTextFieldStyle(
        controlStyle(srTextField, classes = @[LabelStyleClass, LabelHeadingStyleClass])
      )
      status = theme.resolveTextFieldStyle(
        controlStyle(srTextField, classes = @[LabelStyleClass, LabelStatusStyleClass])
      )
      form = theme.resolveTextFieldStyle(
        controlStyle(srTextField, classes = @[LabelStyleClass, LabelFormStyleClass])
      )

    for style in [title, heading, status, form]:
      check style.box.fill == transparent
      check style.box.borderWidth == 0.0'f32
      check style.box.borderColor.a == 0.0'f32
    check title.text.fontSize == defaultFontSize() + 4.0'f32
    check heading.text.fontSize == max(defaultFontSize() - 1.0'f32, 10.0'f32)
    check status.text.fontSize == max(defaultFontSize() - 1.0'f32, 10.0'f32)
    check heading.text.color == color(0.52, 0.52, 0.54, 1.0)
    check status.text.color == color(0.40, 0.40, 0.42, 1.0)
    check form.text.color == status.text.color

  test "non-Aqua themes do not inherit Aqua chrome":
    const ChromeRoles = [
      srButton, srCheckBox, srRadioButton, srSwitch, srSlider, srProgressIndicator,
      srTab, srTabPanel, srDocumentTab, srDocumentTabBar, srDocumentTabButton,
      srTextField, srMonoTextView, srComboBox,
    ]
    for theme in [initPeachyTheme(), initSynthwave83Theme()]:
      for role in ChromeRoles:
        check theme.resolveChromeName(controlStyle(role)) == FlatTransparentChromeName
      for labelClass in [
        LabelStyleClass, LabelTitleStyleClass, LabelHeadingStyleClass,
        LabelStatusStyleClass, LabelFormStyleClass,
      ]:
        let context = controlStyle(srTextField, classes = @[labelClass])
        check theme.resolveChromeName(context) == FlatTransparentChromeName
        check theme.resolveTextFieldStyle(context).box.shadows.len == 0

  test "macOS theme is available through runtime theme names":
    for name in ["macos", "mac", "modern-macos"]:
      let style = initThemeByName(name).resolveButtonStyle(controlStyle(srButton))
      check style.chrome == DefaultChromeName
      check style.box.cornerRadius == 7.0'f32
