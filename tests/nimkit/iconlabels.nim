import std/unittest

import figdraw
import merenda/nimkit
import ./fixtures/rendergeometry

suite "nimkit icon labels":
  test "icon and title render independently and relayout after edits":
    let
      root = newStackView(laVertical, frame = rect(0, 0, 480, 160))
      label = newIconLabel("+", "Add")
      accent = color(0.2, 0.6, 0.3, 1)
      textColor = color(0.7, 0.2, 0.5, 1)
      explicitTint = color(0.1, 0.3, 0.9, 1)
    var appearance = initAppearance()
    let selector =
      initStyleSelector(srTextField, classes = @[LabelStyleClass, IconLabelStyleClass])
    appearance[selector, StyleMarkColor] = accent
    appearance[selector, StyleTextColor] = textColor
    root.appearance = appearance
    root.distribution = svdNatural
    root.addArrangedSubview(label)

    var previousWidth = 0.0'f32
    for edited in [false, true]:
      if edited:
        label.icon = "↓"
        label.title = "Download all selected documents"
        label.iconColor = explicitTint
      let list = buildRenders(root)[DefaultDrawLevel]
      check label.intrinsicContentSize().width > previousWidth
      previousWidth = label.intrinsicContentSize().width
      check label.frame().size.height >= label.intrinsicContentSize().height
      check label.accessibilityRole() == arStaticText
      check label.accessibilityLabel() == label.title

      var iconFound, titleFound: bool
      for node in list.nodes:
        if node.kind == nkText and node.textLayout.glyphCount() > 0:
          if node.textContent() == label.icon:
            iconFound = true
            require node.textLayout.spanColors.len > 0
            check node.textLayout.spanColors[0] ==
              fill(if edited: explicitTint else: accent)
          elif node.textContent() == label.title:
            titleFound = true
            require node.textLayout.spanColors.len > 0
            check node.textLayout.spanColors[0] == fill(textColor)
      check iconFound
      check titleFound
