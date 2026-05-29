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
      srButton, enabled = false, highlighted = true, focused = true
    )

    check context.role == srButton
    check context.states == {ssDisabled, ssHighlighted, ssFocused}
    check buttonThemeState(context) == tcsDisabled

  test "default theme exposes resolved button and text field styles":
    let theme = initTheme()
    let
      appearance = initAppearance(theme)
      buttonStyle = appearance.resolveButtonStyle(
        initControlStyleContext(srButton, highlighted = true)
      )
      textFieldStyle = theme.resolveTextFieldStyle(
        initControlStyleContext(srTextField), initColor(0.2, 0.3, 0.4, 1.0)
      )

    check appearance.theme == theme
    check theme.button.borderWidth > 0.0
    check theme.button.cornerRadius > 0.0
    check theme.button.focusRingWidth > 0.0
    check buttonStyle.box.fill == theme.button.fill[tcsHighlighted]
    check buttonStyle.box.borderColor == theme.button.borderColor[tcsHighlighted]
    check buttonStyle.text.color == theme.button.textColor[tcsHighlighted]
    check buttonStyle.buttonTextRect(initRect(0, 0, 100, 30)) == initRect(8, 0, 84, 30)
    check theme.buttonTextRect(initRect(0, 0, 100, 30)) == initRect(8, 0, 84, 30)

    check theme.textField.borderWidth > 0.0
    check theme.textField.cornerRadius > 0.0
    check theme.textField.focusRingWidth > 0.0
    check textFieldStyle.box.fill == theme.textField.fill
    check textFieldStyle.box.borderColor == theme.textField.borderColor
    check textFieldStyle.text.color == initColor(0.2, 0.3, 0.4, 1.0)
    check textFieldStyle.textFieldTextRect(initRect(0, 0, 100, 30)) ==
      initRect(6, 0, 88, 30)
    check theme.textFieldTextRect(initRect(0, 0, 100, 30)) == initRect(6, 0, 88, 30)
