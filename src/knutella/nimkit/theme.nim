import ./types

type
  EdgeInsets* = object
    top*: float32
    left*: float32
    bottom*: float32
    right*: float32

  ThemeControlState* = enum
    tcsNormal
    tcsHighlighted
    tcsDisabled

  ButtonTheme* = object
    fill*: array[ThemeControlState, Color]
    textColor*: array[ThemeControlState, Color]
    borderColor*: array[ThemeControlState, Color]
    borderWidth*: float32
    cornerRadius*: float32
    contentInsets*: EdgeInsets
    focusRingWidth*: float32
    focusRingInset*: float32

  TextFieldTheme* = object
    fill*: Color
    borderColor*: Color
    borderWidth*: float32
    cornerRadius*: float32
    textInsets*: EdgeInsets
    focusRingWidth*: float32
    focusRingInset*: float32

  Theme* = object
    button*: ButtonTheme
    textField*: TextFieldTheme

func initEdgeInsets*(top, left, bottom, right: float32): EdgeInsets =
  EdgeInsets(top: top, left: left, bottom: bottom, right: right)

func initEdgeInsets*(vertical, horizontal: float32): EdgeInsets =
  initEdgeInsets(vertical, horizontal, vertical, horizontal)

func initEdgeInsets*(all: float32): EdgeInsets =
  initEdgeInsets(all, all, all, all)

func inset*(rect: Rect, insets: EdgeInsets): Rect =
  initRect(
    rect.origin.x + insets.left,
    rect.origin.y + insets.top,
    rect.size.width - insets.left - insets.right,
    rect.size.height - insets.top - insets.bottom,
  )

func buttonThemeState*(enabled, highlighted: bool): ThemeControlState =
  if not enabled:
    tcsDisabled
  elif highlighted:
    tcsHighlighted
  else:
    tcsNormal

func buttonFillColor*(theme: Theme, enabled, highlighted: bool): Color =
  theme.button.fill[buttonThemeState(enabled, highlighted)]

func buttonTextColor*(theme: Theme, enabled, highlighted: bool): Color =
  theme.button.textColor[buttonThemeState(enabled, highlighted)]

func buttonBorderColor*(theme: Theme, enabled, highlighted: bool): Color =
  theme.button.borderColor[buttonThemeState(enabled, highlighted)]

func buttonTextRect*(theme: Theme, bounds: Rect): Rect =
  bounds.inset(theme.button.contentInsets)

func textFieldTextRect*(theme: Theme, bounds: Rect): Rect =
  bounds.inset(theme.textField.textInsets)

func initTheme*(): Theme =
  Theme(
    button: ButtonTheme(
      fill: [
        tcsNormal: initColor(0.20, 0.48, 0.86, 1.0),
        tcsHighlighted: initColor(0.12, 0.34, 0.68, 1.0),
        tcsDisabled: initColor(0.58, 0.62, 0.68, 1.0),
      ],
      textColor: [
        tcsNormal: initColor(1.0, 1.0, 1.0, 1.0),
        tcsHighlighted: initColor(1.0, 1.0, 1.0, 1.0),
        tcsDisabled: initColor(0.92, 0.94, 0.96, 1.0),
      ],
      borderColor: [
        tcsNormal: initColor(0.10, 0.25, 0.46, 1.0),
        tcsHighlighted: initColor(0.06, 0.18, 0.36, 1.0),
        tcsDisabled: initColor(0.46, 0.50, 0.56, 1.0),
      ],
      borderWidth: 1.0,
      cornerRadius: 4.0,
      contentInsets: initEdgeInsets(0.0, 8.0),
      focusRingWidth: 3.0,
      focusRingInset: 2.0,
    ),
    textField: TextFieldTheme(
      fill: initColor(1.0, 1.0, 1.0, 1.0),
      borderColor: initColor(0.72, 0.75, 0.80, 1.0),
      borderWidth: 1.0,
      cornerRadius: 3.0,
      textInsets: initEdgeInsets(0.0, 6.0),
      focusRingWidth: 3.0,
      focusRingInset: 2.0,
    ),
  )
