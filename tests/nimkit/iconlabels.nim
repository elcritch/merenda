import std/unittest

import merenda/nimkit

suite "nimkit icon labels":
  test "Unicode icons use text layout with independent tint":
    let label = newIconLabel("↓", "Downloads", color(0.0, 0.62, 0.78, 1.0))

    check label.icon == "↓"
    check label.title == "Downloads"
    check label.iconColor == color(0.0, 0.62, 0.78, 1.0)
    check label.styleClasses == @[LabelStyleClass, IconLabelStyleClass]
    check label.intrinsicContentSize().width > 0.0'f32
    check label.intrinsicContentSize().height > 0.0'f32
    check label.accessibilityRole() == arStaticText
    check label.accessibilityLabel() == "Downloads"

    label.icon = "⌘"
    label.title = "Applications"
    label.iconColor = color(0.04, 0.52, 1.0, 1.0)
    check label.icon == "⌘"
    check label.title == "Applications"
    check label.iconColor == color(0.04, 0.52, 1.0, 1.0)

  test "macOS icon labels default to the theme accent":
    let
      theme = initMacOSTheme()
      context =
        controlStyle(srTextField, classes = @[LabelStyleClass, IconLabelStyleClass])

    check theme.resolveColor(context, StyleMarkColor, color(0.0, 0.0, 0.0, 1.0)) ==
      color(0.04, 0.52, 1.0, 1.0)
    check theme.resolveLength(context, StyleIndicatorSize, 0.0'f32) == 18.0'f32
    check theme.resolveLength(context, StyleIndicatorSpacing, 0.0'f32) == 8.0'f32
