import std/unittest

import merenda/nimkit

suite "nimkit sizing":
  test "plain views expose no intrinsic metric and preserve frame on sizeToFit":
    let view = newView(frame = initRect(10, 20, 80, 30))
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
    let button = newButton("Resize", frame = initRect(10, 20, 12, 10))
    let natural = button.intrinsicContentSize()

    check natural.hasWidth
    check natural.hasHeight
    check natural.width > button.frame().size.width
    check natural.height >= 24.0

    button.sizeToFit()
    check button.frame().origin == initPoint(10, 20)
    check button.frame().size == natural.resolveIntrinsicSize(initSize(0, 0))

  test "auto frame metrics resolve from intrinsic content":
    let
      plain = newView()
      button = newButton("Auto", frame = initRect(10, 20))
      field = newTextField("Height", frame = initRect(4, 5, 120))
      explicit = newButton("Explicit", frame = initRect(1, 2, 30, 10))

    check AutoMetric.isAutoMetric
    check initSize().hasAutoMetric
    check plain.frame() == initRect(0, 0, 0, 0)
    check not plain.translatesAutoresizingMaskIntoConstraints()

    let buttonNatural =
      button.intrinsicContentSize().resolveIntrinsicSize(initSize(0, 0))
    check button.frame().origin == initPoint(10, 20)
    check button.frame().size == buttonNatural
    check not button.translatesAutoresizingMaskIntoConstraints()

    let fieldNatural = field.intrinsicContentSize().resolveIntrinsicSize(initSize(0, 0))
    check field.frame() == initRect(4, 5, 120, fieldNatural.height)
    check not field.translatesAutoresizingMaskIntoConstraints()

    check explicit.frame() == initRect(1, 2, 30, 10)
    check explicit.translatesAutoresizingMaskIntoConstraints()

  test "content changes invalidate parent layout without mutating frames":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      button = newButton("Go", frame = initRect(10, 10, 48, 24))

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
      checkbox = newCheckBox("Enabled", frame = initRect(0, 0, 20, 18))
      radio = newRadioButton("Option", frame = initRect(0, 0, 20, 18))
      textSize = textNaturalSize("Enabled")

    check checkbox.contentHuggingPriority(laHorizontal) == LayoutPriorityDefaultHigh
    check radio.contentHuggingPriority(laHorizontal) == LayoutPriorityDefaultHigh
    check checkbox.intrinsicContentSize().width > textSize.width
    check radio.intrinsicContentSize().width > textNaturalSize("Option").width

  test "text fields and combo boxes measure text and chrome":
    let
      field = newTextField("Name", frame = initRect(0, 0, 10, 10))
      combo = newComboBox(["Short", "Much longer item"], frame = initRect(0, 0, 10, 10))

    check field.contentHuggingPriority(laHorizontal) == LayoutPriorityDefaultLow
    check field.intrinsicContentSize().width >= 80.0
    check field.intrinsicContentSize().height >= 24.0

    let comboSize = combo.intrinsicContentSize()
    check comboSize.width >= 90.0
    check comboSize.width > textNaturalSize("Much longer item").width
    check comboSize.height >= 24.0

  test "undersized fitting proposals preserve natural control sizes":
    let
      button = newButton("Long button title", frame = initRect(0, 0, 10, 10))
      field = newTextField("Long field value", frame = initRect(0, 0, 10, 10))
      combo = newComboBox(["Long combo item"], frame = initRect(0, 0, 10, 10))
      proposed = initFittingSize(4.0, 4.0)

    check button.sizeThatFits(proposed) == button.sizeThatFits()
    check field.sizeThatFits(proposed) == field.sizeThatFits()
    check combo.sizeThatFits(proposed) == combo.sizeThatFits()

  test "theme metrics affect measurement and agree with text rects":
    let button = newButton("Pad", frame = initRect(0, 0, 10, 10))
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
