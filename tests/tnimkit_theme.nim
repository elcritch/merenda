import std/unittest

import knutella/nimkit

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
      enabled = false,
      highlighted = true,
      hovered = true,
      active = true,
      focused = true,
      focusVisible = true,
      focusWithin = true,
      selected = true,
      opened = true,
      id = "primary",
      classes = @["default", "toolbar"],
    )

    check context.role == srButton
    check context.id == "primary"
    check context.classes == @["default", "toolbar"]
    check context.states == {
      ssDisabled, ssHighlighted, ssHovered, ssActive, ssFocused, ssFocusVisible,
      ssFocusWithin, ssSelected, ssOpen,
    }

  test "style token store resolves typed values and nested references":
    let
      parent = newStyleTokenStore()
      child = newStyleTokenStore(parent)
      accent = initColor(0.7, 0.2, 0.3, 1.0)
      padding = initEdgeInsets(1, 2, 3, 4)

    parent.setToken("accent", accent)
    parent.setToken("space", 6.0)
    parent.setToken("padding", padding)
    child.setToken("nested.accent", styleToken("accent"))

    var value: StyleValue
    check child.resolveToken("nested.accent", value)
    check value.kind == svColor
    check value.color == accent

    let appearance = Appearance(theme: Theme(tokens: child))
    check appearance.colorToken("nested.accent", initColor(0, 0, 0, 1)) == accent
    check appearance.lengthToken("space", 0.0) == 6.0
    check appearance.insetsToken("padding", initEdgeInsets(0)) == padding
    check appearance.colorToken("missing", accent) == accent

  test "appearance tokens and style patches resolve into concrete styles":
    var appearance = initAppearance()
    let
      buttonFill = initColor(0.11, 0.22, 0.33, 1.0)
      focusRing = initColor(0.24, 0.42, 0.90, 0.75)
      fieldText = initColor(0.44, 0.55, 0.66, 1.0)
      buttonInsets = initEdgeInsets(2.0, 10.0)

    appearance.setToken("field.text.override", fieldText)
    appearance[srButton, StyleFill] = buttonFill
    appearance[srButton, StyleCornerRadius] = 9.0
    appearance[srButton, StyleFocusRingColor] = focusRing
    appearance[srButton, StyleTextInsets] = buttonInsets
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
    check buttonStyle.text.insets == buttonInsets
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

    firstAppearance.setToken(ButtonFillToken, overrideFill)
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
      buttonStyle = appearance.resolveButtonStyle(
        initControlStyleContext(srButton, highlighted = true)
      )
      checkBoxStyle = appearance.resolveChoiceButtonStyle(
        initControlStyleContext(srCheckBox, selected = true)
      )
      radioStyle = appearance.resolveChoiceButtonStyle(
        initControlStyleContext(srRadioButton, selected = true)
      )
      textFieldStyle = theme.resolveTextFieldStyle(
        initControlStyleContext(srTextField), initColor(0.2, 0.3, 0.4, 1.0)
      )

    check appearance.theme.rules.len == theme.rules.len
    check theme.tokens != nil
    check theme.rules.len > 0
    check buttonStyle.box.borderWidth > 0.0
    check buttonStyle.box.cornerRadius > 0.0
    check buttonStyle.box.focusRingWidth > 0.0
    check buttonStyle.box.focusRingInset < 0.0
    check buttonStyle.box.focusRingColor.a > 0.0
    check buttonStyle.box.focusRingColor != buttonStyle.box.fill
    check buttonStyle.box.fill == initColor(0.12, 0.34, 0.68, 1.0)
    check buttonStyle.box.borderColor == initColor(0.06, 0.18, 0.36, 1.0)
    check buttonStyle.text.color == initColor(1.0, 1.0, 1.0, 1.0)
    check buttonStyle.buttonTextRect(initRect(0, 0, 100, 30)) == initRect(8, 0, 84, 30)

    check checkBoxStyle.indicatorSize > 0.0
    check checkBoxStyle.indicatorSpacing > 0.0
    check checkBoxStyle.indicator.fill == initColor(0.20, 0.48, 0.86, 1.0)
    check checkBoxStyle.indicator.cornerRadius == 3.0
    check checkBoxStyle.indicator.focusRingColor == initColor(0.24, 0.48, 0.92, 0.58)
    check radioStyle.indicator.cornerRadius == 7.0
    check radioStyle.indicator.focusRingColor == initColor(0.24, 0.48, 0.92, 0.58)
    check checkBoxStyle.choiceIndicatorRect(initRect(0, 0, 100, 24)) ==
      initRect(2, 5, 14, 14)
    check checkBoxStyle.choiceTextRect(initRect(0, 0, 100, 24)) ==
      initRect(23, 0, 75, 24)

    check textFieldStyle.box.borderWidth > 0.0
    check textFieldStyle.box.cornerRadius > 0.0
    check textFieldStyle.box.focusRingWidth > 0.0
    check textFieldStyle.box.fill == initColor(1.0, 1.0, 1.0, 1.0)
    check textFieldStyle.box.borderColor == initColor(0.72, 0.75, 0.80, 1.0)
    check textFieldStyle.box.focusRingColor == initColor(0.24, 0.48, 0.92, 0.58)
    check textFieldStyle.text.color == initColor(0.2, 0.3, 0.4, 1.0)
    check textFieldStyle.textFieldTextRect(initRect(0, 0, 100, 30)) ==
      initRect(6, 0, 88, 30)
