import std/unittest

import merenda/nimkit

suite "nimkit sizing":
  test "plain views expose no intrinsic metric and preserve frame on sizeToFit":
    let view = newView(10, 20, 80, 30)
    let initialFrame = view.frame()

    check view.intrinsicContentSize() == NoIntrinsicContentSize
    check not view.intrinsicContentSize().hasWidth
    check not view.intrinsicContentSize().hasHeight
    check view.sizeThatFits() == initSize(80, 30)
    check view.contentHuggingPriority(laHorizontal) == LayoutPriorityDefaultLow
    check view.contentCompressionResistancePriority(laHorizontal) ==
      LayoutPriorityDefaultHigh

    view.sizeToFit()
    check view.frame() == initialFrame

  test "button sizeToFit uses cell intrinsic size and preserves origin":
    let button = newButton(10, 20, 12, 10, "Resize")
    let natural = button.intrinsicContentSize()

    check natural.hasWidth
    check natural.hasHeight
    check natural.width > button.frame().size.width
    check natural.height >= 24.0

    button.sizeToFit()
    check button.frame().origin == initPoint(10, 20)
    check button.frame().size == natural.resolveIntrinsicSize(initSize(0, 0))

  test "content changes invalidate parent layout without mutating frames":
    let
      root = newView(0, 0, 240, 120)
      button = newButton(10, 10, 48, 24, "Go")

    root.addSubview(button)
    root.layoutSubtreeIfNeeded()
    root.setNeedsLayout(false)
    button.setNeedsLayout(false)

    let initialFrame = button.frame()
    button.setTitle("A much longer title")

    check button.frame() == initialFrame
    check root.needsLayout
    check button.needsLayout

    let natural = button.intrinsicContentSize().resolveIntrinsicSize(initSize(0, 0))
    button.sizeToFit()
    check button.frame().size == natural

  test "choice controls include indicators and hug horizontally":
    let
      checkbox = newCheckBox(0, 0, 20, 18, "Enabled")
      radio = newRadioButton(0, 0, 20, 18, "Option")
      textSize = textNaturalSize("Enabled")

    check checkbox.contentHuggingPriority(laHorizontal) == LayoutPriorityDefaultHigh
    check radio.contentHuggingPriority(laHorizontal) == LayoutPriorityDefaultHigh
    check checkbox.intrinsicContentSize().width > textSize.width
    check radio.intrinsicContentSize().width > textNaturalSize("Option").width

  test "text fields and combo boxes measure text and chrome":
    let
      field = newTextField(0, 0, 10, 10, "Name")
      combo = newComboBox(0, 0, 10, 10, ["Short", "Much longer item"])

    check field.contentHuggingPriority(laHorizontal) == LayoutPriorityDefaultLow
    check field.intrinsicContentSize().width >= 80.0
    check field.intrinsicContentSize().height >= 24.0

    let comboSize = combo.intrinsicContentSize()
    check comboSize.width >= 90.0
    check comboSize.width > textNaturalSize("Much longer item").width
    check comboSize.height >= 24.0

  test "undersized fitting proposals preserve natural control sizes":
    let
      button = newButton(0, 0, 10, 10, "Long button title")
      field = newTextField(0, 0, 10, 10, "Long field value")
      combo = newComboBox(0, 0, 10, 10, ["Long combo item"])
      proposed = initFittingSize(4.0, 4.0)

    check button.sizeThatFits(proposed) == button.sizeThatFits()
    check field.sizeThatFits(proposed) == field.sizeThatFits()
    check combo.sizeThatFits(proposed) == combo.sizeThatFits()

  test "theme metrics affect measurement and agree with text rects":
    let button = newButton(0, 0, 10, 10, "Pad")
    let base = button.intrinsicContentSize()

    var appearance = initAppearance()
    appearance[srButton, StyleTextInsets] = initEdgeInsets(0.0, 24.0)
    appearance[srButton, StyleMinimumSize] = initSize(0.0, 40.0)
    button.setAppearance(appearance)

    let styled = button.intrinsicContentSize()
    check styled.width > base.width
    check styled.height >= 40.0

    button.sizeToFit()
    let style = button.effectiveAppearance().resolveButtonStyle(
        initControlStyleContext(
          srButton, id = button.styleId, classes = button.styleClasses
        )
      )
    check style.buttonTextRect(button.bounds()).size.width >=
      textNaturalSize("Pad").width
