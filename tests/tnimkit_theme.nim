import std/unittest

import merenda/nimkit

func brightness(color: Color): float32 =
  color.r + color.g + color.b

proc checkAquaButtonShadows(shadows: seq[BoxShadow]) =
  check shadows.len >= 3

  var
    hasDrop = false
    hasLightInset = false
    hasDarkInset = false

  for shadow in shadows:
    if shadow.kind == bskDrop and shadow.color.a > 0.0 and shadow.blur > 0.0:
      hasDrop = true
    if shadow.kind == bskInset and shadow.color.brightness > 2.5 and shadow.color.a > 0.0 and
        shadow.blur > 0.0:
      hasLightInset = true
    if shadow.kind == bskInset and shadow.color.brightness < 0.5 and shadow.color.a > 0.0 and
        shadow.blur > 0.0:
      hasDarkInset = true

  check hasDrop
  check hasLightInset
  check hasDarkInset

func aquaButtonFill(): Fill =
  linear(
    initColor(0.72, 0.91, 1.0, 1.0),
    initColor(0.18, 0.61, 0.98, 1.0),
    initColor(0.02, 0.30, 0.82, 1.0),
    fgaY,
    88'u8,
  )

func aquaButtonPressedFill(): Fill =
  linear(
    initColor(0.11, 0.48, 0.92, 1.0),
    initColor(0.02, 0.28, 0.75, 1.0),
    initColor(0.01, 0.14, 0.46, 1.0),
    fgaY,
    96'u8,
  )

func aquaTextFieldFill(): Fill =
  linear(initColor(1.0, 1.0, 1.0, 1.0), initColor(0.95, 0.98, 1.0, 1.0), fgaY)

func aquaComboItemSelectedFill(): Fill =
  linear(
    initColor(0.45, 0.75, 1.0, 1.0),
    initColor(0.10, 0.45, 0.95, 1.0),
    initColor(0.02, 0.26, 0.76, 1.0),
    fgaY,
    104'u8,
  )

suite "nimkit theme":
  test "edge insets shrink rectangles without negative sizes":
    check initRect(10, 20, 100, 50).inset(initEdgeInsets(2, 4, 6, 8)) ==
      initRect(14, 22, 88, 42)
    check initRect(0, 0, 10, 10).inset(initEdgeInsets(8)) == initRect(8, 8, 0, 0)

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

  test "style context stores role and control states":
    let context = initControlStyleContext(
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

  test "style token store resolves typed values and nested references":
    let
      parent = newStyleTokenStore()
      child = newStyleTokenStore(parent)
      accent = initColor(0.7, 0.2, 0.3, 1.0)
      minSize = initSize(24.0, 18.0)
      padding = initEdgeInsets(1, 2, 3, 4)
      shadows = @[dropShadow(initColor(0, 0, 0, 0.25), y = 2.0, blur = 4.0)]

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
    check appearance.colorToken("nested.accent", initColor(0, 0, 0, 1)) == accent
    check appearance.lengthToken("space", 0.0) == 6.0
    check appearance.sizeToken("minimum.size", initSize(0, 0)) == minSize
    check appearance.insetsToken("padding", initEdgeInsets(0)) == padding
    check appearance.shadowsToken("shadow", @[]) == shadows
    check appearance.colorToken("missing", accent) == accent

  test "appearance tokens and style patches resolve into concrete styles":
    var appearance = initAppearance()
    let
      buttonFill = initColor(0.11, 0.22, 0.33, 1.0)
      focusRing = initColor(0.24, 0.42, 0.90, 0.75)
      fieldText = initColor(0.44, 0.55, 0.66, 1.0)
      buttonMinimum = initSize(72.0, 32.0)
      buttonInsets = initEdgeInsets(2.0, 10.0)
      buttonShadows =
        @[
          dropShadow(initColor(0, 0, 0, 0.35), y = 2.0, blur = 5.0),
          insetShadow(initColor(1, 1, 1, 0.18), y = -1.0, blur = 1.0),
        ]

    appearance.theme["field.text.override"] = fieldText
    appearance[srButton, StyleFill] = buttonFill
    appearance[srButton, StyleCornerRadius] = 9.0
    appearance[srButton, StyleFocusRingColor] = focusRing
    appearance[srButton, StyleTextInsets] = buttonInsets
    appearance[srButton, StyleMinimumSize] = buttonMinimum
    appearance[srButton, StyleBoxShadows] = buttonShadows
    appearance[srTextField, StyleTextColor] = styleToken("field.text.override")
    appearance[srTextField, StyleBorderWidth] = 4.0

    let
      buttonStyle = appearance.resolveButtonStyle(initControlStyleContext(srButton))
      textFieldStyle = appearance.resolveTextFieldStyle(
        initControlStyleContext(srTextField), initColor(0.1, 0.1, 0.1, 1.0)
      )

    check buttonStyle.box.fill == buttonFill
    check buttonStyle.box.cornerRadius == 9.0
    check buttonStyle.box.focusRingColor == focusRing
    check buttonStyle.box.shadows == buttonShadows
    check buttonStyle.text.insets == buttonInsets
    check buttonStyle.minSize == buttonMinimum
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
      baseStyle = theme.resolveButtonStyle(initControlStyleContext(srButton))
      overrideFill = initColor(0.67, 0.18, 0.22, 1.0)

    firstAppearance.theme[ButtonFillToken] = overrideFill
    firstAppearance[srButton, StyleCornerRadius] = 11.0

    check firstAppearance.resolveButtonStyle(initControlStyleContext(srButton)).box.fill ==
      overrideFill
    check firstAppearance.resolveButtonStyle(initControlStyleContext(srButton)).box.cornerRadius ==
      11.0
    check secondAppearance.resolveButtonStyle(initControlStyleContext(srButton)).box.fill ==
      baseStyle.box.fill
    check secondAppearance.resolveButtonStyle(initControlStyleContext(srButton)).box.cornerRadius ==
      baseStyle.box.cornerRadius
    check theme.resolveButtonStyle(initControlStyleContext(srButton)).box.fill ==
      baseStyle.box.fill
    check theme.resolveButtonStyle(initControlStyleContext(srButton)).box.cornerRadius ==
      baseStyle.box.cornerRadius

  test "default theme exposes resolved button and text field styles":
    let theme = initTheme()
    let
      appearance = initAppearance(theme)
      defaultButtonStyle =
        appearance.resolveButtonStyle(initControlStyleContext(srButton))
      buttonStyle = appearance.resolveButtonStyle(
        initControlStyleContext(srButton, {ssHighlighted})
      )
      checkBoxStyle = appearance.resolveChoiceButtonStyle(
        initControlStyleContext(srCheckBox, {ssSelected})
      )
      radioStyle = appearance.resolveChoiceButtonStyle(
        initControlStyleContext(srRadioButton, {ssSelected})
      )
      textFieldStyle = theme.resolveTextFieldStyle(
        initControlStyleContext(srTextField), initColor(0.2, 0.3, 0.4, 1.0)
      )
      bodyLabelStyle = theme.resolveTextFieldStyle(
        initControlStyleContext(srTextField, classes = @[LabelStyleClass])
      )
      titleLabelStyle = theme.resolveTextFieldStyle(
        initControlStyleContext(
          srTextField, classes = @[LabelStyleClass, LabelTitleStyleClass]
        )
      )
      headingLabelStyle = theme.resolveTextFieldStyle(
        initControlStyleContext(
          srTextField, classes = @[LabelStyleClass, LabelHeadingStyleClass]
        )
      )
      statusLabelStyle = theme.resolveTextFieldStyle(
        initControlStyleContext(
          srTextField, classes = @[LabelStyleClass, LabelStatusStyleClass]
        )
      )
      formLabelStyle = theme.resolveTextFieldStyle(
        initControlStyleContext(
          srTextField, classes = @[LabelStyleClass, LabelFormStyleClass]
        )
      )
      comboBoxStyle =
        appearance.resolveComboBoxStyle(initControlStyleContext(srComboBox, {ssOpen}))
      comboBoxItemStyle = appearance.resolveTextFieldStyle(
        initControlStyleContext(srComboBoxItem, {ssSelected})
      )

    check appearance.theme.rules.len == theme.rules.len
    check theme.tokens != nil
    check theme.rules.len > 0
    check buttonStyle.box.borderWidth > 0.0
    check buttonStyle.box.cornerRadius > 0.0
    check buttonStyle.box.focusRingWidth > 0.0
    check buttonStyle.box.focusRingInset < 0.0
    check buttonStyle.box.focusRingColor.a > 0.0
    check buttonStyle.box.focusRingColor != buttonStyle.box.fill.centerColor()
    checkAquaButtonShadows(defaultButtonStyle.box.shadows)
    checkAquaButtonShadows(buttonStyle.box.shadows)
    check defaultButtonStyle.box.fill == aquaButtonFill()
    check buttonStyle.box.fill == aquaButtonPressedFill()
    check buttonStyle.box.borderColor == initColor(0.01, 0.12, 0.42, 1.0)
    check buttonStyle.box.cornerRadius == 14.0
    check buttonStyle.text.color == initColor(1.0, 1.0, 1.0, 1.0)
    check buttonStyle.minSize == initSize(0.0, 32.0)
    check buttonStyle.buttonTextRect(initRect(0, 0, 100, 30)) == initRect(8, 0, 84, 30)

    check checkBoxStyle.indicatorSize > 0.0
    check checkBoxStyle.indicatorSpacing > 0.0
    check checkBoxStyle.minSize == initSize(0.0, 18.0)
    check checkBoxStyle.indicator.fill == aquaButtonFill()
    check checkBoxStyle.indicator.cornerRadius == 6.0
    check checkBoxStyle.indicator.focusRingColor == initColor(0.34, 0.66, 1.0, 0.72)
    check radioStyle.indicator.cornerRadius == 7.0
    check radioStyle.indicator.focusRingColor == initColor(0.34, 0.66, 1.0, 0.72)
    check checkBoxStyle.choiceIndicatorRect(initRect(0, 0, 100, 24)) ==
      initRect(2, 5, 14, 14)
    check checkBoxStyle.choiceTextRect(initRect(0, 0, 100, 24)) ==
      initRect(23, 0, 75, 24)

    check textFieldStyle.box.borderWidth > 0.0
    check textFieldStyle.box.cornerRadius == 6.0
    check textFieldStyle.box.focusRingWidth > 0.0
    check textFieldStyle.box.fill == aquaTextFieldFill()
    check textFieldStyle.box.borderColor == initColor(0.56, 0.64, 0.76, 1.0)
    check textFieldStyle.box.focusRingColor == initColor(0.34, 0.66, 1.0, 0.72)
    check textFieldStyle.text.color == initColor(0.2, 0.3, 0.4, 1.0)
    check textFieldStyle.selectionColor == initColor(0.24, 0.56, 1.0, 0.34)
    check textFieldStyle.minSize == initSize(80.0, 24.0)
    check textFieldStyle.textFieldTextRect(initRect(0, 0, 100, 30)) ==
      initRect(6, 0, 88, 30)

    check bodyLabelStyle.box.fill.centerColor().a == 0.0
    check bodyLabelStyle.box.borderWidth == 0.0
    check bodyLabelStyle.box.focusRingWidth == 0.0
    check bodyLabelStyle.text.color == initColor(0.09, 0.12, 0.18, 1.0)
    check bodyLabelStyle.minSize == initSize(0.0, 18.0)
    check titleLabelStyle.box.borderWidth == 1.0
    check titleLabelStyle.box.cornerRadius == 6.0
    check titleLabelStyle.text.insets == initEdgeInsets(0.0, 12.0)
    check titleLabelStyle.minSize == initSize(0.0, 28.0)
    check headingLabelStyle.box.cornerRadius == 5.0
    check headingLabelStyle.minSize == initSize(0.0, 24.0)
    check statusLabelStyle.text.color == initColor(0.09, 0.27, 0.18, 1.0)
    check formLabelStyle.box.borderWidth == 0.0
    check formLabelStyle.text.color == initColor(0.10, 0.14, 0.22, 1.0)

    check comboBoxStyle.box.fill == aquaTextFieldFill()
    check comboBoxStyle.box.borderColor == initColor(0.12, 0.42, 0.86, 1.0)
    check comboBoxStyle.box.cornerRadius == 6.0
    check comboBoxStyle.minSize == initSize(90.0, 24.0)
    check comboBoxStyle.arrowWidth == 24.0
    check comboBoxStyle.arrowColor == initColor(0.10, 0.16, 0.26, 1.0)
    check comboBoxStyle.comboBoxArrowRect(initRect(0, 0, 100, 28)) ==
      initRect(76, 0, 24, 28)
    check comboBoxStyle.comboBoxTextRect(initRect(0, 0, 100, 28)) ==
      initRect(8, 0, 60, 28)
    check comboBoxItemStyle.box.fill == aquaComboItemSelectedFill()
    check comboBoxItemStyle.text.color == initColor(1.0, 1.0, 1.0, 1.0)
    check comboBoxItemStyle.minSize == initSize(0.0, 22.0)

  test "banner theme exposes generated banner palette as an opt-in theme":
    let
      theme = initBannerTheme()
      buttonStyle = theme.resolveButtonStyle(initControlStyleContext(srButton))
      highlightedButtonStyle =
        theme.resolveButtonStyle(initControlStyleContext(srButton, {ssHighlighted}))
      checkBoxStyle = theme.resolveChoiceButtonStyle(
        initControlStyleContext(srCheckBox, {ssSelected})
      )
      textFieldStyle = theme.resolveTextFieldStyle(initControlStyleContext(srTextField))
      comboBoxStyle =
        theme.resolveComboBoxStyle(initControlStyleContext(srComboBox, {ssOpen}))
      comboBoxItemStyle = theme.resolveTextFieldStyle(
        initControlStyleContext(srComboBoxItem, {ssSelected, ssHovered})
      )

    check buttonStyle.box.fill == initColor(0.89, 0.38, 0.21, 1.0)
    check highlightedButtonStyle.box.fill == initColor(0.62, 0.24, 0.14, 1.0)
    check checkBoxStyle.indicator.fill == initColor(0.89, 0.38, 0.21, 1.0)
    check textFieldStyle.box.fill == initColor(1.0, 0.97, 0.94, 1.0)
    check textFieldStyle.selectionColor == initColor(0.31, 0.58, 0.54, 0.32)
    check comboBoxStyle.box.borderColor == initColor(0.31, 0.58, 0.54, 1.0)
    check comboBoxStyle.arrowColor == initColor(0.16, 0.15, 0.15, 1.0)
    check comboBoxItemStyle.box.fill == initColor(0.19, 0.38, 0.35, 1.0)
