import std/unittest

import merenda/nimkit

type CyclicIntrinsicView = ref object of View

protocol CyclicIntrinsicLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: CyclicIntrinsicView): IntrinsicSize =
    initIntrinsicSize(view.sizeThatFits())

proc newCyclicIntrinsicView(): CyclicIntrinsicView =
  result = CyclicIntrinsicView()
  initViewFields(result, rect(0.0, 0.0, 10.0, 10.0))
  result.name = "cyclic"
  discard result.withProtocol(CyclicIntrinsicLayout)

suite "nimkit sizing":
  test "plain views expose no intrinsic metric and preserve frame on sizeToFit":
    let view = newView(frame = rect(10, 20, 80, 30))
    let initialFrame = view.frame()

    check view.intrinsicContentSize() == NoIntrinsicContentSize
    check not view.intrinsicContentSize().hasWidth
    check not view.intrinsicContentSize().hasHeight
    check view.sizeThatFits() == initSize(80, 30)
    check view.huggingPriority[dcol] == LayoutPriorityLow
    check view.compressionPriority[dcol] == LayoutPriorityHigh

    view.sizeToFit()
    check view.frame() == initialFrame

  test "fitting size resolves a constraint-wrapped intrinsic subtree":
    let
      root = newView(frame = rect(0, 0, 40, 30))
      stack = newStackView(laVertical)
      button = newButton("Constraint fitting")

    stack.addArrangedSubview(button)
    root.addSubview(stack)
    discard stack.pinEdges(
      toGuide = root.contentLayoutGuide(insets(12.0, 18.0)),
      edges = {leLeft, leTop, leRight, leBottom},
    )

    let
      rootFrame = root.frame()
      stackFrame = stack.frame()
      natural = button.sizeThatFits()
      fitting = root.fittingSize()

    check fitting == initSize(natural.width + 36.0, natural.height + 24.0)
    check root.frame() == rootFrame
    check stack.frame() == stackFrame

  test "fitting size uses intrinsic dimensions for an unconstrained control":
    let button = newButton("Natural")

    check button.fittingSize() == button.sizeThatFits()

  test "cyclic intrinsic sizing fails with a layout resolution defect":
    let view = newCyclicIntrinsicView()

    expect LayoutResolutionDefect:
      discard view.sizeThatFits()

  test "button sizeToFit uses cell intrinsic size and preserves origin":
    let button = newButton("Resize", frame = rect(10, 20, 12, 10))
    let natural = button.intrinsicContentSize()

    check natural.hasWidth
    check natural.hasHeight
    check natural.width > button.frame().size.width
    check natural.height >= 32.0

    button.sizeToFit()
    check button.frame().origin == initPoint(10, 20)
    check button.frame().size == natural.resolveIntrinsicSize(initSize(0, 0))

  test "auto frame metrics resolve from intrinsic content":
    let
      plain = newView()
      button = newButton("Auto", frame = rect(10, 20, AutoMetric, AutoMetric))
      field = newTextField("Height", frame = rect(4, 5, 120, AutoMetric))
      explicit = newButton("Explicit", frame = rect(1, 2, 30, 10))

    check AutoMetric.isAutoMetric
    check initSize().hasAutoMetric
    check plain.frame() == rect(0, 0, 0, 0)
    check not plain.autoresizingMaskConstraints

    let buttonNatural =
      button.intrinsicContentSize().resolveIntrinsicSize(initSize(0, 0))
    check button.frame().origin == initPoint(10, 20)
    check button.frame().size == buttonNatural
    check not button.autoresizingMaskConstraints

    let fieldNatural = field.intrinsicContentSize().resolveIntrinsicSize(initSize(0, 0))
    check field.frame() == rect(4, 5, 120, fieldNatural.height)
    check not field.autoresizingMaskConstraints

    check explicit.frame() == rect(1, 2, 30, 10)
    check explicit.autoresizingMaskConstraints

  test "content changes invalidate parent layout without mutating frames":
    let
      root = newView(frame = rect(0, 0, 240, 120))
      button = newButton("Go", frame = rect(10, 10, 48, 24))

    root.addSubview(button)
    root.layoutSubtreeIfNeeded()
    root.needsLayout = false
    button.needsLayout = false

    let initialFrame = button.frame()
    button.title = "A much longer title"

    check button.frame() == initialFrame
    check root.needsLayout
    check button.needsLayout

    let natural = button.intrinsicContentSize().resolveIntrinsicSize(initSize(0, 0))
    button.sizeToFit()
    check button.frame().size == natural

  test "button reserved titles stabilize intrinsic width":
    let button = newButton("Toggle Off")

    let offWidth = button.intrinsicContentSize().width
    button.title = "Toggle Mixed"
    let mixedWidth = button.intrinsicContentSize().width
    check mixedWidth > offWidth

    button.title = "Toggle Off"
    button.reservedTitles = ["Toggle Off", "Toggle On", "Toggle Mixed"]
    let reservedWidth = button.intrinsicContentSize().width
    check reservedWidth == mixedWidth

    button.title = "Toggle On"
    check button.intrinsicContentSize().width == reservedWidth
    button.title = "Toggle Mixed"
    check button.intrinsicContentSize().width == reservedWidth
    check button.reservedTitles == @["Toggle Off", "Toggle On", "Toggle Mixed"]

  test "choice controls include indicators and hug horizontally":
    let
      checkbox = newCheckBox("Enabled", frame = rect(0, 0, 20, 18))
      radio = newRadioButton("Option", frame = rect(0, 0, 20, 18))
      textSize = textNaturalSize("Enabled")

    check checkbox.huggingPriority[dcol] == LayoutPriorityHigh
    check radio.huggingPriority[dcol] == LayoutPriorityHigh
    check checkbox.intrinsicContentSize().width > textSize.width
    check radio.intrinsicContentSize().width > textNaturalSize("Option").width

  test "text fields and combo boxes measure text and chrome":
    let
      field = newTextField("Name", frame = rect(0, 0, 10, 10))
      combo = newComboBox(["Short", "Much longer item"], frame = rect(0, 0, 10, 10))

    check field.huggingPriority[dcol] == LayoutPriorityLow
    check field.intrinsicContentSize().width >= 80.0
    check field.intrinsicContentSize().height >= 24.0

    let comboSize = combo.intrinsicContentSize()
    check comboSize.width >= 90.0
    check comboSize.width > textNaturalSize("Much longer item").width
    check comboSize.height >= 24.0

  test "undersized fitting proposals preserve natural control sizes":
    let
      button = newButton("Long button title", frame = rect(0, 0, 10, 10))
      field = newTextField("Long field value", frame = rect(0, 0, 10, 10))
      combo = newComboBox(["Long combo item"], frame = rect(0, 0, 10, 10))
      proposed = initFittingSize(4.0, 4.0)

    check button.sizeThatFits(proposed) == button.sizeThatFits()
    check field.sizeThatFits(proposed) == field.sizeThatFits()
    check combo.sizeThatFits(proposed) == combo.sizeThatFits()

  test "theme metrics affect measurement and agree with text rects":
    let button = newButton("Pad", frame = rect(0, 0, 10, 10))
    let base = button.intrinsicContentSize()

    var appearance = initAppearance()
    appearance[srButton, StyleTextInsets] = insets(0.0, 24.0)
    appearance[srButton, StyleMinimumSize] = initSize(0.0, 40.0)
    button.appearance = appearance

    let styled = button.intrinsicContentSize()
    check styled.width > base.width
    check styled.height >= 40.0

    button.sizeToFit()
    let style = button.effectiveAppearance().resolveButtonStyle(
        controlStyle(srButton, id = button.styleId, classes = button.styleClasses)
      )
    check style.buttonTextRect(button.bounds()).size.width >=
      textNaturalSize("Pad").width

  test "theme metric changes invalidate container layout for controls":
    let
      root = newView(frame = rect(0, 0, 360, 220))
      stack = newStackView(laVertical)
      button = newButton("Metric")
      checkbox = newCheckBox("Choice")
      field = newTextField("Field")
      combo = newComboBox(["Short", "Longest metric item"])

    combo.selectedIndex = 1
    stack.addArrangedSubview(button, checkbox, field, combo)
    root.addSubview(stack)
    stack.sizeToFit()
    root.layoutSubtreeIfNeeded()

    let
      baseButton = button.intrinsicContentSize()
      baseCheck = checkbox.intrinsicContentSize()
      baseField = field.intrinsicContentSize()
      baseCombo = combo.intrinsicContentSize()

    root.needsLayout = false
    stack.needsLayout = false
    button.needsLayout = false
    checkbox.needsLayout = false
    field.needsLayout = false
    combo.needsLayout = false

    var appearance = initAppearance()
    appearance[srButton, StyleTextInsets] = insets(6.0, 26.0)
    appearance[srButton, StyleMinimumSize] = initSize(0.0, 48.0)
    appearance[srCheckBox, StyleIndicatorSize] = 28.0
    appearance[srCheckBox, StyleIndicatorSpacing] = 14.0
    appearance[srCheckBox, StyleTextInsets] = insets(4.0, 10.0)
    appearance[srTextField, StyleTextInsets] = insets(5.0, 22.0)
    appearance[srTextField, StyleMinimumSize] = initSize(120.0, 38.0)
    appearance[srComboBox, StyleTextInsets] = insets(4.0, 18.0)
    appearance[srComboBox, StyleIndicatorSize] = 34.0
    appearance[srComboBox, StyleMinimumSize] = initSize(140.0, 36.0)
    root.appearance = appearance

    check root.needsLayout
    check stack.needsLayout
    check button.needsLayout
    check checkbox.needsLayout
    check field.needsLayout
    check combo.needsLayout

    check button.intrinsicContentSize().height > baseButton.height
    check checkbox.intrinsicContentSize().width > baseCheck.width
    check field.intrinsicContentSize().width > baseField.width
    check combo.intrinsicContentSize().width > baseCombo.width

  test "replacing a control cell detaches the old cell":
    let
      root = newView(frame = rect(0, 0, 240, 120))
      button = newButton("Old")
      oldCell = button.buttonCell()
      nextCell = newButtonCell("New")

    root.addSubview(button)
    root.layoutSubtreeIfNeeded()
    root.needsLayout = false
    button.needsLayout = false

    button.setCell(nextCell)
    check oldCell.controlView().isNil
    check nextCell.controlView() == button
    check root.needsLayout
    check button.needsLayout

    root.needsLayout = false
    button.needsLayout = false
    oldCell.title = "Detached"
    check not root.needsLayout
    check not button.needsLayout

    nextCell.title = "Attached and wider"
    check root.needsLayout
    check button.needsLayout
