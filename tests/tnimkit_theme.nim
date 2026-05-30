import std/unittest

import knutella/nimkit

suite "nimkit theme":
  test "edge insets shrink rectangles without negative sizes":
    check initRect(10, 20, 100, 50).inset(initEdgeInsets(2, 4, 6, 8)) ==
      initRect(14, 22, 88, 42)
    check initRect(0, 0, 10, 10).inset(initEdgeInsets(8)) == initRect(8, 8, 0, 0)

  test "button theme state follows enabled and highlighted flags":
    check buttonThemeState(enabled = true, highlighted = false) == tcsNormal
    check buttonThemeState(enabled = true, highlighted = true) == tcsHighlighted
    check buttonThemeState(enabled = false, highlighted = true) == tcsDisabled

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
    check buttonThemeState(context) == tcsDisabled

  test "style token store resolves typed values and nested references":
    let
      parent = newStyleTokenStore()
      child = newStyleTokenStore(parent)
      accent = initColor(0.7, 0.2, 0.3, 1.0)
      padding = initEdgeInsets(1, 2, 3, 4)

    parent.setToken("accent", styleColor(accent))
    parent.setToken("space", styleLength(6.0))
    parent.setToken("padding", styleInsets(padding))
    child.setToken("nested.accent", styleToken("accent"))

    var value: StyleValue
    check child.resolveToken("nested.accent", value)
    check value.kind == svColor
    check value.color == accent

    let appearance = Appearance(theme: initTheme(), tokens: child)
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

    appearance.tokens.setToken("field.text.override", styleColor(fieldText))
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

    check appearance.theme == theme
    check theme.button.borderWidth > 0.0
    check theme.button.cornerRadius > 0.0
    check theme.button.focusRingWidth > 0.0
    check theme.button.focusRingColor.a > 0.0
    check buttonStyle.box.fill == theme.button.fill[tcsHighlighted]
    check buttonStyle.box.borderColor == theme.button.borderColor[tcsHighlighted]
    check buttonStyle.box.focusRingColor == theme.button.focusRingColor
    check buttonStyle.text.color == theme.button.textColor[tcsHighlighted]
    check buttonStyle.buttonTextRect(initRect(0, 0, 100, 30)) == initRect(8, 0, 84, 30)
    check theme.buttonTextRect(initRect(0, 0, 100, 30)) == initRect(8, 0, 84, 30)

    check theme.choiceButton.indicatorSize > 0.0
    check theme.choiceButton.indicatorSpacing > 0.0
    check checkBoxStyle.indicator.fill ==
      theme.choiceButton.indicatorSelectedFill[tcsNormal]
    check checkBoxStyle.indicator.cornerRadius == theme.choiceButton.checkBoxCornerRadius
    check checkBoxStyle.indicator.focusRingColor == theme.choiceButton.focusRingColor
    check radioStyle.indicator.cornerRadius == theme.choiceButton.radioCornerRadius
    check radioStyle.indicator.focusRingColor == theme.choiceButton.focusRingColor
    check checkBoxStyle.choiceIndicatorRect(initRect(0, 0, 100, 24)) ==
      initRect(2, 5, 14, 14)
    check checkBoxStyle.choiceTextRect(initRect(0, 0, 100, 24)) ==
      initRect(23, 0, 75, 24)

    check theme.textField.borderWidth > 0.0
    check theme.textField.cornerRadius > 0.0
    check theme.textField.focusRingWidth > 0.0
    check textFieldStyle.box.fill == theme.textField.fill
    check textFieldStyle.box.borderColor == theme.textField.borderColor
    check textFieldStyle.box.focusRingColor == theme.textField.focusRingColor
    check textFieldStyle.text.color == initColor(0.2, 0.3, 0.4, 1.0)
    check textFieldStyle.textFieldTextRect(initRect(0, 0, 100, 30)) ==
      initRect(6, 0, 88, 30)
    check theme.textFieldTextRect(initRect(0, 0, 100, 30)) == initRect(6, 0, 88, 30)
