import std/[unicode, unittest]

import figdraw/fignodes

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes

type CustomDrawView = ref object of View
type SingleColumnRenderTableSource = ref object of Responder
  rows: seq[string]

var customDrawCount: int

const ExtraChromeName = "render-extra-chrome"

let
  ExtraChromeFill = fill(color(0.72, 0.10, 0.48, 1.0))
  CustomLineFill = fill(color(0.10, 0.55, 0.86, 1.0))
  CustomCircleFill = fill(color(0.16, 0.70, 0.28, 1.0))

type ExtraChrome = ref object of Chrome

func rgbaColor(r, g, b, a: int): Color =
  color(
    r.float32 / 255.0'f32,
    g.float32 / 255.0'f32,
    b.float32 / 255.0'f32,
    a.float32 / 255.0'f32,
  )

func aquaChoiceSelectedFill(): Fill =
  linear(rgbaColor(122, 232, 255, 255), rgbaColor(0, 124, 238, 255), fgaDiagTLBR)

func aquaRadioShellFill(): Fill =
  linear(rgbaColor(253, 253, 250, 255), rgbaColor(166, 168, 164, 255), fgaY)

protocol CustomDrawing of ViewDrawingProtocol:
  method draw(view: CustomDrawView, context: DrawContext) =
    inc customDrawCount
    context.addRectangle(rect(4, 5, 20, 10), color(0.8, 0.1, 0.1))
    context.addText(rect(4, 5, 20, 10), "C", color(1, 1, 1))
    context.addRenderLine(
      initPoint(4.0, 22.0), initPoint(24.0, 30.0), CustomLineFill, 2.0
    )
    context.addRenderCircle(initPoint(35.0, 18.0), CustomCircleFill, 6.0)

protocol ExtraChromeProtocol of ChromeProtocol:
  method drawChromeExtrasFor(
      chrome: ExtraChrome,
      context: DrawContext,
      chromeContext: ChromeContext,
      extras: ChromeExtras,
  ) =
    discard chrome
    discard chromeContext
    discard context.addRenderRectangle(
      extras.layer, extras.parent, extras.rect.inset(insets(5.0)), ExtraChromeFill
    )

protocol SingleColumnRenderTableSourceMethods of TableViewDataSource:
  method numberOfRows(
      source: SingleColumnRenderTableSource, tableView: TableView
  ): int =
    source.rows.len

  method textForCell(
      source: SingleColumnRenderTableSource,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ): string =
    if row < 0 or row >= source.rows.len:
      ""
    else:
      source.rows[row]

proc newSingleColumnRenderTableSource(
    rows: openArray[string]
): SingleColumnRenderTableSource =
  result = SingleColumnRenderTableSource(rows: @rows)
  initResponder(result)
  discard result.withProtocol(SingleColumnRenderTableSourceMethods)

proc newSingleColumnRenderTable(
    rows: openArray[string], frame: nimkitTypes.Rect
): TableView =
  result = newTableView(frame = frame)
  let source = newSingleColumnRenderTableSource(rows)
  result.showsHeader = false
  result.rowCount = rows.len
  result.dataSource = source
  result.addColumn(newTableColumn("item", "Item", width = 120.0))

proc newCustomDrawView(frame: nimkitTypes.Rect): CustomDrawView =
  result = CustomDrawView()
  initViewFields(result, frame)
  discard result.withProtocol(CustomDrawing)

proc newExtraChrome(): Chrome =
  let chrome = ExtraChrome()
  discard chrome.withProtocol(ExtraChromeProtocol)
  Chrome(chrome)

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add(rune)

proc renderedRect(node: Fig): nimkitTypes.Rect =
  nimkitTypes.rect(
    node.screenBox.x.float32, node.screenBox.y.float32, node.screenBox.w.float32,
    node.screenBox.h.float32,
  )

func approx(a, b: float32): bool =
  abs(a - b) <= 0.01'f32

func approxColor(left, right: ColorRGBA, tolerance: int = 1): bool =
  abs(int(left.r) - int(right.r)) <= tolerance and
    abs(int(left.g) - int(right.g)) <= tolerance and
    abs(int(left.b) - int(right.b)) <= tolerance and
    abs(int(left.a) - int(right.a)) <= tolerance

func inCustomSubtree(nodes: seq[Fig], parent: FigIdx, target: FigIdx): bool =
  if target.int < 0 or target.int >= nodes.len:
    return false
  var current = target
  while true:
    if current == parent:
      return true
    let parentIdx = nodes[current.int].parent
    if parentIdx.int < 0:
      return false
    current = parentIdx
  false

proc rectsClose(left, right: nimkitTypes.Rect): bool =
  abs(left.origin.x - right.origin.x) <= 0.01'f32 and
    abs(left.origin.y - right.origin.y) <= 0.01'f32 and
    abs(left.size.width - right.size.width) <= 0.01'f32 and
    abs(left.size.height - right.size.height) <= 0.01'f32

suite "nimkit rendering":
  test "buildRenders emits root, text field, and button nodes":
    let root = newView(frame = rect(0, 0, 320, 200))
    root.setBackgroundColor(color(1, 1, 1))
    root.addSubview(newTextField("Ready", frame = rect(16, 16, 180, 32)))
    root.addSubview(newButton("Click", frame = rect(16, 64, 120, 36)))

    let renders = buildRenders(root)

    check DefaultDrawLevel in renders
    let list = renders[DefaultDrawLevel]
    check list.rootIds.len >= 1
    check list.nodes.len >= 5

    var textNodeCount = 0
    var rectangleNodeCount = 0
    for node in list.nodes:
      case node.kind
      of nkText:
        inc textNodeCount
      of nkRectangle:
        inc rectangleNodeCount
      else:
        discard

    check textNodeCount >= 2
    check rectangleNodeCount >= 3

  test "buildRenders applies view alpha and shadow to view background node":
    let
      root = newView(frame = rect(0, 0, 120, 80))
      shadow = dropShadow(color(0, 0, 0, 0.4), y = 3.0, blur = 7.0)

    root.backgroundColor = color(0.2, 0.4, 0.6, 0.8)
    root.alphaValue = 0.5
    root.shadow = [shadow]

    let list = buildRenders(root)[DefaultDrawLevel]
    check list.rootIds.len == 1

    let node = list.nodes[list.rootIds[0].int]
    check node.kind == nkRectangle
    check node.fill.kind == flColor
    check node.fill.color == color(0.2, 0.4, 0.6, 0.4).rgba
    check node.shadows[0].style == DropShadow
    check node.shadows[0].fill.kind == flColor
    check node.shadows[0].fill.color == color(0, 0, 0, 0.4).rgba
    check node.shadows[0].y == 3.0
    check node.shadows[0].blur == 7.0

  test "buildRenders draws themed root background pinstripes":
    let
      root = newView(frame = rect(0, 0, 24, 10))
      child = newView(frame = rect(2, 3, 4, 4))
      baseFill = linear(color(0.9, 0.95, 1.0, 1.0), color(0.7, 0.8, 0.9, 1.0), fgaY)
      highlightColor = color(1.0, 1.0, 1.0, 0.4)
      stripeColor = color(0.2, 0.3, 0.4, 0.2)

    var theme = initTheme()
    theme[srView, StyleBackgroundFill] = baseFill
    theme[srView, StyleBackgroundPinstripeHighlightColor] = highlightColor
    theme[srView, StyleBackgroundPinstripeColor] = stripeColor
    theme[srView, StyleBackgroundPinstripePeriod] = 4.0
    theme[srView, StyleBackgroundPinstripeHeight] = 1.0

    root.addSubview(child)

    let
      list = buildRenders(root, initAppearance(theme))[DefaultDrawLevel]
      rootIdx = list.rootIds[0]

    check list.nodes[int(rootIdx)].fill == baseFill

    var
      highlightFound = false
      stripeFound = false
      childFound = false

    for idx in childIndex(list.nodes, rootIdx):
      let node = list.nodes[int(idx)]
      if node.kind == nkRectangle:
        let nodeRect = node.renderedRect()
        if node.fill.kind == flColor and node.fill.color == highlightColor.rgba:
          highlightFound = highlightFound or nodeRect.rectsClose(rect(0, 0, 24, 1))
        if node.fill.kind == flColor and node.fill.color == stripeColor.rgba:
          stripeFound = stripeFound or nodeRect.rectsClose(rect(0, 1, 24, 1))
        if nodeRect.rectsClose(rect(2, 3, 4, 4)):
          childFound = true

    check highlightFound
    check stripeFound
    check childFound

    let explicitRoot = newView(frame = rect(0, 0, 24, 10))
    explicitRoot.setBackgroundColor(color(0.2, 0.3, 0.4, 1.0))

    let
      explicitList = buildRenders(explicitRoot, initAppearance(theme))[DefaultDrawLevel]
      explicitRootIdx = explicitList.rootIds[0]

    var explicitPinstripeFound = false
    for idx in childIndex(explicitList.nodes, explicitRootIdx):
      let node = explicitList.nodes[int(idx)]
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color in [highlightColor.rgba, stripeColor.rgba]:
        explicitPinstripeFound = true

    check explicitList.nodes[int(explicitRootIdx)].fill.color ==
      color(0.2, 0.3, 0.4, 1.0).rgba
    check not explicitPinstripeFound

  test "buildRenders uses theme colors and metrics for built-in controls":
    let
      root = newView(frame = rect(0, 0, 180, 120))
      field = newTextField("Field", frame = rect(10, 20, 100, 30))
      button = newButton("Button", frame = rect(10, 60, 80, 24))

    let
      buttonFill = color(0.31, 0.42, 0.53, 1.0)
      buttonBorder = color(0.11, 0.12, 0.13, 1.0)
      fieldFill = color(0.91, 0.92, 0.93, 1.0)
      fieldBorder = color(0.21, 0.22, 0.23, 1.0)
      buttonShadows =
        @[
          dropShadow(color(0, 0, 0, 0.40), y = 2.0, blur = 5.0),
          insetShadow(color(1, 1, 1, 0.20), y = -1.0, blur = 1.0),
        ]

    var theme = initTheme()
    theme[srButton, StyleFill] = buttonFill
    theme[srButton, StyleBorderColor] = buttonBorder
    theme[srButton, StyleBorderWidth] = 3.0
    theme[srButton, StyleCornerRadius] = 6.0
    theme[srButton, StyleTextInsets] = insets(1.0, 9.0)
    theme[srButton, StyleBoxShadows] = buttonShadows
    theme[srTextField, StyleFill] = fieldFill
    theme[srTextField, StyleBorderColor] = fieldBorder
    theme[srTextField, StyleBorderWidth] = 2.0
    theme[srTextField, StyleCornerRadius] = 5.0
    theme[srTextField, StyleTextInsets] = insets(2.0, 7.0)

    root.addSubview(field)
    root.addSubview(button)

    let renders = buildRenders(root, initAppearance(theme))
    let list = renders[DefaultDrawLevel]

    var
      themedButtonFound = false
      themedTextFieldFound = false
      buttonTextBoxFound = false
      fieldTextBoxFound = false

    for node in list.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == buttonFill.rgba:
        themedButtonFound = true
        check node.stroke.weight == 3.0
        check node.stroke.fill.kind == flColor
        check node.stroke.fill.color == buttonBorder.rgba
        check node.corners[dcTopLeft] == 6'u16
        check node.shadows[0].style == DropShadow
        check node.shadows[0].fill.kind == flColor
        check node.shadows[0].fill.color == color(0, 0, 0, 0.40).rgba
        check node.shadows[0].y == 2.0
        check node.shadows[0].blur == 5.0
        check node.shadows[1].style == InnerShadow
        check node.shadows[1].fill.kind == flColor
        check node.shadows[1].fill.color == color(1, 1, 1, 0.20).rgba
        check node.shadows[1].y == -1.0

      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == fieldFill.rgba:
        themedTextFieldFound = true
        check node.stroke.weight == 2.0
        check node.stroke.fill.kind == flColor
        check node.stroke.fill.color == fieldBorder.rgba
        check node.corners[dcTopLeft] == 5'u16

      if node.kind == nkText and node.screenBox.x == 19.0 and node.screenBox.y == 61.0 and
          node.screenBox.w == 62.0 and node.screenBox.h == 22.0:
        buttonTextBoxFound = true

      if node.kind == nkText and node.screenBox.x == 17.0 and node.screenBox.y == 22.0 and
          node.screenBox.w == 86.0 and node.screenBox.h == 26.0:
        fieldTextBoxFound = true

    check themedButtonFound
    check themedTextFieldFound
    check buttonTextBoxFound
    check fieldTextBoxFound

  test "rendered control boxes agree with resolved metric styles":
    let
      root = newView(frame = rect(0, 0, 360, 220))
      button = newButton("Metric", frame = rect(12, 14, 20, 10))
      checkbox = newCheckBox("Choice", frame = rect(12, 62, 20, 10))
      field = newTextField("Field", frame = rect(12, 104, 20, 10))
      combo =
        newComboBox(["Short", "Longest metric item"], frame = rect(12, 148, 20, 10))
      checkFill = color(0.64, 0.22, 0.17, 1.0)

    var appearance = initAppearance()
    appearance[srButton, StyleTextInsets] = insets(5.0, 18.0, 7.0, 22.0)
    appearance[srButton, StyleMinimumSize] = initSize(0.0, 46.0)
    appearance[srCheckBox, StyleFill] = checkFill
    appearance[srCheckBox, StyleChrome] = styleKeyword(DefaultChromeName)
    appearance[srCheckBox, StyleIndicatorSize] = 20.0
    appearance[srCheckBox, StyleIndicatorSpacing] = 11.0
    appearance[srCheckBox, StyleTextInsets] = insets(3.0, 8.0, 5.0, 10.0)
    appearance[srTextField, StyleTextInsets] = insets(4.0, 16.0, 6.0, 14.0)
    appearance[srTextField, StyleMinimumSize] = initSize(116.0, 36.0)
    appearance[srComboBox, StyleTextInsets] = insets(4.0, 15.0, 6.0, 13.0)
    appearance[srComboBox, StyleIndicatorSize] = 32.0
    appearance[srComboBox, StyleMinimumSize] = initSize(142.0, 36.0)

    root.appearance = appearance
    root.addSubviews(autoNames(button, checkbox, field, combo))
    combo.selectedIndex = 1
    button.sizeToFit()
    checkbox.sizeToFit()
    field.sizeToFit()
    combo.sizeToFit()

    let
      buttonStyle = button.effectiveAppearance().resolveButtonStyle(
          controlStyle(srButton, id = button.styleId, classes = button.styleClasses)
        )
      checkStyle = checkbox.effectiveAppearance().resolveChoiceButtonStyle(
          controlStyle(
            srCheckBox, id = checkbox.styleId, classes = checkbox.styleClasses
          )
        )
      fieldStyle = field.effectiveAppearance().resolveTextFieldStyle(
          controlStyle(srTextField, id = field.styleId, classes = field.styleClasses),
          field.textColor(),
        )
      comboStyle = combo.effectiveAppearance().resolveComboBoxStyle(
          controlStyle(srComboBox, id = combo.styleId, classes = combo.styleClasses)
        )
      expectedButtonText =
        button.rectToWindow(buttonStyle.buttonTextRect(button.bounds))
      expectedCheckText =
        checkbox.rectToWindow(checkStyle.choiceTextRect(checkbox.bounds))
      expectedCheckIndicator =
        checkbox.rectToWindow(checkStyle.choiceIndicatorRect(checkbox.bounds))
      expectedFieldText = field.rectToWindow(fieldStyle.textFieldTextRect(field.bounds))
      expectedComboText = combo.rectToWindow(comboStyle.comboBoxTextRect(combo.bounds))

    let list = buildRenders(root)[DefaultDrawLevel]
    var
      buttonTextFound = false
      checkTextFound = false
      checkIndicatorFound = false
      fieldTextFound = false
      comboTextFound = false

    for node in list.nodes:
      case node.kind
      of nkText:
        let text = node.renderedText()
        if text == "Metric" and node.renderedRect().rectsClose(expectedButtonText):
          buttonTextFound = true
        elif text == "Choice":
          checkTextFound = true
          check node.renderedRect().rectsClose(expectedCheckText)
        elif text == "Field":
          fieldTextFound = true
          check node.renderedRect().rectsClose(expectedFieldText)
        elif text == "Longest metric item":
          comboTextFound = true
          check node.renderedRect().rectsClose(expectedComboText)
      of nkRectangle:
        if node.fill.kind == flColor and node.fill.color == checkFill.rgba:
          checkIndicatorFound = true
          check node.renderedRect().rectsClose(expectedCheckIndicator)
      else:
        discard

    check buttonTextFound
    check checkTextFound
    check checkIndicatorFound
    check fieldTextFound
    check comboTextFound

  test "slider thumb fill blends from knob fill toward active fill":
    let
      root = newView(frame = rect(0, 0, 180, 80))
      slider = newSlider(0.0, 100.0, 25.0, frame = rect(20, 20, 120, 30))
      knobFill = fill(color(0.20, 0.40, 0.60, 0.80))
      activeFill = fill(color(0.80, 0.20, 0.40, 1.00))
      expectedKnobFill = fill(color(0.35, 0.35, 0.55, 0.85))
      expectedKnobRect = rect(45.0, 25.0, 20.0, 20.0)

    var theme = initTheme()
    theme[srSlider, StyleChrome] = styleKeyword(DefaultChromeName)
    theme[srSlider, StyleKnobSize] = 20.0
    theme[srSlider, StyleIndicatorSize] = 6.0
    theme[srSlider, StyleKnobFill] = knobFill
    theme[srSlider, StyleHighlightFill] = activeFill
    theme[srSlider, StyleKnobBorderColor] = color(0.0, 0.0, 0.0, 0.0)
    theme[srSlider, StyleKnobShadows] = newSeq[BoxShadow]()

    root.addSubview(slider)

    let list = buildRenders(root, initAppearance(theme))[DefaultDrawLevel]

    var knobFound = false
    for node in list.nodes:
      if node.kind == nkRectangle and node.fill == expectedKnobFill and
          node.renderedRect().rectsClose(expectedKnobRect):
        knobFound = true
        check node.corners[dcTopLeft] == 10'u16

    check knobFound

  test "buildRenders draws Aqua push button layers":
    let
      root = newView(frame = rect(0, 0, 180, 90))
      button = newButton("OK", frame = rect(20, 24, 120, 32))

    root.addSubview(button)

    let
      style = button.effectiveAppearance().resolveButtonStyle(
          controlStyle(srButton, id = button.styleId, classes = button.styleClasses)
        )
      expectedButtonRect = button.rectToWindow(button.bounds)
      expectedShadowRect = rect(
        expectedButtonRect.origin.x,
        expectedButtonRect.origin.y + 1.1'f32,
        expectedButtonRect.size.width,
        expectedButtonRect.size.height,
      )
      expectedTextRect = button.rectToWindow(style.buttonTextRect(button.bounds))
      list = buildRenders(root)[DefaultDrawLevel]

    var
      buttonBackingFound = false
      buttonRoot = (-1).FigIdx
    for idx, node in list.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == rgbaColor(0, 0, 0, 40).rgba and
          node.renderedRect().rectsClose(expectedShadowRect):
        buttonBackingFound = true
        check node.corners[dcTopLeft] == 16'u16
        check node.shadows[0].style == DropShadow
        check node.shadows[0].fill.kind == flColor
        check node.shadows[0].fill.color == rgbaColor(0, 0, 0, 46).rgba
        check node.shadows[0].y == 1.2'f32
        check node.shadows[0].blur == 4.4'f32
      if node.kind == nkRectangle and node.fill == style.box.fill and
          node.renderedRect().rectsClose(expectedButtonRect):
        buttonRoot = idx.FigIdx
        check NfRectMaskContent in node.flags
        check NfClipContent notin node.flags
        check node.fill.centerColor().a <= 0.57'f32
        check node.stroke.weight == style.box.borderWidth
        check node.stroke.fill.kind == flColor
        check node.stroke.fill.color == style.box.borderColor.rgba
        check node.corners[dcTopLeft] == 16'u16

    check buttonBackingFound
    check buttonRoot != (-1).FigIdx

    var innerRoot = (-1).FigIdx
    for idx in childIndex(list.nodes, buttonRoot):
      let node = list.nodes[int(idx)]
      if node.kind == nkRectangle and NfRectMaskContent in node.flags and
          node.fill.kind == flLinear3:
        innerRoot = idx
        check node.fill.centerColor().a <= 0.55'f32

    check innerRoot != (-1).FigIdx

    var glossFound = false
    for idx in childIndex(list.nodes, innerRoot):
      let node = list.nodes[int(idx)]
      if node.kind == nkRectangle and node.fill.kind == flLinear2 and
          node.fill.lin2.start.a > 0'u8 and node.fill.lin2.stop.a == 0'u8:
        glossFound = true
        check node.fill.lin2.start.a <= 40'u8

    var
      okTextLayerCount = 0
      mainTextFound = false
    for node in list.nodes:
      if node.kind == nkText and node.renderedText() == "OK":
        inc okTextLayerCount
        if node.renderedRect().rectsClose(expectedTextRect):
          mainTextFound = true

    check glossFound
    check okTextLayerCount >= 3
    check mainTextFound

  test "buildRenders omits Aqua extras for default button chrome":
    let
      root = newView(frame = rect(0, 0, 180, 90))
      button = newButton("OK", frame = rect(20, 24, 120, 32))

    var theme = initTheme()
    theme[srButton, StyleChrome] = styleKeyword(DefaultChromeName)
    theme[srButton, StyleTextHighlightColor] = color(0.0, 0.0, 0.0, 0.0)
    theme[srButton, StyleTextShadowColor] = color(0.0, 0.0, 0.0, 0.0)
    root.addSubview(button)

    let
      style = initAppearance(theme).resolveButtonStyle(
          controlStyle(srButton, id = button.styleId, classes = button.styleClasses)
        )
      expectedButtonRect = button.rectToWindow(button.bounds)
      list = buildRenders(root, initAppearance(theme))[DefaultDrawLevel]

    var buttonRoot = (-1).FigIdx
    for idx, node in list.nodes:
      if node.kind == nkRectangle and node.fill == style.box.fill and
          node.renderedRect().rectsClose(expectedButtonRect):
        buttonRoot = idx.FigIdx

    check buttonRoot != (-1).FigIdx

    var buttonChildCount = 0
    for _ in childIndex(list.nodes, buttonRoot):
      inc buttonChildCount

    var okTextLayerCount = 0
    for node in list.nodes:
      if node.kind == nkText and node.renderedText() == "OK":
        inc okTextLayerCount

    check buttonChildCount == 0
    check okTextLayerCount == 1

  test "button rendering clips labels to the text rect":
    let
      root = newView(frame = rect(0, 0, 140, 80))
      button = newButton("Expand All", frame = rect(10, 20, 44, 28))
      appearance = initAppearance()
      style = appearance.resolveButtonStyle(controlStyle(srButton))

    root.addSubview(button)

    let
      textRect = style.buttonTextRect(button.bounds())
      expectedTitle = clippedText(button.title(), textRect.size.width, style.text)
      list = buildRenders(root, appearance)[DefaultDrawLevel]

    check expectedTitle.len > 0
    check expectedTitle != button.title()

    var clippedTitleFound = false
    for node in list.nodes:
      if node.kind == nkText and node.renderedText() == expectedTitle:
        clippedTitleFound = true

    check clippedTitleFound

  test "buildRenders uses installed chrome extras selected per button":
    let
      root = newView(frame = rect(0, 0, 260, 120))
      normalButton = newButton("Default", frame = rect(20, 20, 100, 32))
      specialButton = newButton("Special", frame = rect(140, 20, 100, 32))

    specialButton.styleId = "special"
    root.addSubview(normalButton)
    root.addSubview(specialButton)

    var theme = initTheme()
    theme.installChrome(ExtraChromeName, newExtraChrome())
    theme[initStyleSelector(srButton, id = "special"), StyleChrome] =
      styleKeyword(ExtraChromeName)

    let
      list = buildRenders(root, initAppearance(theme))[DefaultDrawLevel]
      expectedExtraRect =
        specialButton.rectToWindow(specialButton.bounds).inset(insets(5.0))

    var extraFound = false
    for node in list.nodes:
      if node.kind == nkRectangle and node.fill == ExtraChromeFill and
          node.renderedRect().rectsClose(expectedExtraRect):
        extraFound = true

    check extraFound

  test "buildRenders uses installed chrome extras for choices and combo popups":
    let
      root = newView(frame = rect(0, 0, 240, 150))
      checkbox = newCheckBox("Choice", frame = rect(12, 16, 120, 24))
      combo = newComboBox(["One", "Two"], frame = rect(12, 52, 120, 26))

    checkbox.styleId = "special-choice"
    combo.styleId = "special-combo"
    combo.selectedIndex = 0
    combo.openPopup()
    root.addSubview(checkbox)
    root.addSubview(combo)

    var theme = initTheme()
    theme.installChrome(ExtraChromeName, newExtraChrome())
    theme[initStyleSelector(srCheckBox, id = "special-choice"), StyleChrome] =
      styleKeyword(ExtraChromeName)
    theme[initStyleSelector(srComboBox, id = "special-combo"), StyleChrome] =
      styleKeyword(ExtraChromeName)

    let
      appearance = initAppearance(theme)
      checkStyle = appearance.resolveChoiceButtonStyle(
        controlStyle(srCheckBox, id = checkbox.styleId, classes = checkbox.styleClasses)
      )
      expectedChoiceExtra = checkbox
        .rectToWindow(checkStyle.choiceIndicatorRect(checkbox.bounds))
        .inset(insets(5.0))
      expectedComboExtra = combo.rectToWindow(combo.bounds).inset(insets(5.0))
      expectedPopupExtra =
        combo.rectToWindow(combo.popupRect(combo.bounds)).inset(insets(5.0))
      renders = buildRenders(root, appearance)

    var
      choiceExtraFound = false
      comboExtraFound = false
      popupExtraFound = false

    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill == ExtraChromeFill:
        if node.renderedRect().rectsClose(expectedChoiceExtra):
          choiceExtraFound = true
        if node.renderedRect().rectsClose(expectedComboExtra):
          comboExtraFound = true

    for node in renders[PopupDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill == ExtraChromeFill and
          node.renderedRect().rectsClose(expectedPopupExtra):
        popupExtraFound = true

    check choiceExtraFound
    check comboExtraFound
    check popupExtraFound

  test "buildRenders keeps Aqua radio accent inside neutral shell":
    let
      root = newView(frame = rect(0, 0, 220, 110))
      checkbox = newCheckBox("Check", frame = rect(10, 20, 120, 24))
      radio = newRadioButton("Radio", frame = rect(10, 56, 120, 24))

    checkbox.setState(bsOn)
    radio.setState(bsOn)
    root.addSubview(checkbox)
    root.addSubview(radio)

    let
      appearance = initAppearance(initTheme())
      checkStyle =
        appearance.resolveChoiceButtonStyle(controlStyle(srCheckBox, {ssSelected}))
      radioStyle =
        appearance.resolveChoiceButtonStyle(controlStyle(srRadioButton, {ssSelected}))
      checkboxIndicator =
        checkbox.rectToWindow(checkStyle.choiceIndicatorRect(checkbox.bounds))
      radioIndicator = radio.rectToWindow(radioStyle.choiceIndicatorRect(radio.bounds))
      radioInner = radioIndicator.inset(insets(1.6))
      radioGlossWidth = max(radioInner.size.width * 0.52'f32, 1.0'f32)
      radioGloss = rect(
        radioInner.origin.x + (radioInner.size.width - radioGlossWidth) / 2.0'f32,
        radioInner.origin.y + 1.0'f32,
        radioGlossWidth,
        max(radioInner.size.height * 0.18'f32, 1.0'f32),
      )
      list = buildRenders(root, appearance)[DefaultDrawLevel]

    var
      checkboxAccentFound = false
      radioShellFound = false
      radioInnerAccentFound = false
      radioGlossFound = false

    for node in list.nodes:
      if node.kind == nkRectangle:
        let nodeRect = node.renderedRect()
        if nodeRect.rectsClose(checkboxIndicator):
          checkboxAccentFound = true
          check node.fill == aquaChoiceSelectedFill()
          check node.stroke.fill.kind == flColor
          check node.stroke.fill.color == color(0.0, 0.32, 0.75, 0.96).rgba
        if nodeRect.rectsClose(radioIndicator):
          radioShellFound = true
          check node.fill == aquaRadioShellFill()
        if nodeRect.rectsClose(radioInner):
          radioInnerAccentFound = true
          check node.fill == aquaChoiceSelectedFill()
          check node.stroke.fill.kind == flColor
          check node.stroke.fill.color == color(0.0, 0.32, 0.75, 0.96).rgba
        if nodeRect.rectsClose(radioGloss):
          radioGlossFound = true
          check nodeRect.size.width < radioInner.size.width * 0.60'f32

    check checkboxAccentFound
    check radioShellFound
    check radioInnerAccentFound
    check radioGlossFound

  test "buildRenders centers push button text by default":
    let
      root = newView(frame = rect(0, 0, 160, 80))
      button = newButton("OK", frame = rect(10, 20, 120, 30))

    root.addSubview(button)

    let renders = buildRenders(root)
    var buttonTextFound = false
    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkText:
        buttonTextFound = true

        var
          minX = float32.high
          minY = float32.high
          maxX = -float32.high
          maxY = -float32.high
        for rect in node.textLayout.selectionRects:
          minX = min(minX, rect.x)
          minY = min(minY, rect.y)
          maxX = max(maxX, rect.x + rect.w)
          maxY = max(maxY, rect.y + rect.h)

        let
          contentCenterX = (minX + maxX) / 2.0'f32
          contentCenterY = (minY + maxY) / 2.0'f32
          textBoxCenterX = node.screenBox.w / 2.0'f32
          textBoxCenterY = node.screenBox.h / 2.0'f32

        check abs(contentCenterX - textBoxCenterX) <= 1.0'f32
        check abs(contentCenterY - textBoxCenterY) <= 1.0'f32
        check minX > 0.0'f32

    check buttonTextFound

  test "buildRenders draws combo box and open popup items":
    let
      root = newView(frame = rect(0, 0, 220, 150))
      combo = newComboBox(["One", "Two", "Three"], frame = rect(10, 20, 120, 26))

    combo.selectItemAtIndex(1)
    combo.openPopup()
    root.addSubview(combo)

    let renders = buildRenders(root)
    check DefaultDrawLevel in renders
    check PopupDrawLevel in renders

    let
      list = renders[DefaultDrawLevel]
      popupList = renders[PopupDrawLevel]
    var
      comboBoxFound = false
      popupInBaseLayer = false
      popupFound = false
      selectedItemFound = false
      textNodeCount = 0
      arrowTopWidth = 0.0'f32
      arrowBottomWidth = 0.0'f32

    for node in list.nodes:
      if node.kind == nkText:
        inc textNodeCount

      if node.kind == nkRectangle and node.screenBox.x == 10.0 and
          node.screenBox.y == 20.0 and node.screenBox.w == 120.0 and
          node.screenBox.h == 26.0:
        comboBoxFound = true

      if node.kind == nkRectangle and node.screenBox.x == 10.0 and
          node.screenBox.y == 46.0 and node.screenBox.w == 120.0 and
          node.screenBox.h == 68.0:
        popupInBaseLayer = true

      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == color(0.0, 0.12, 0.34, 1.0).rgba and node.screenBox.h == 1.0:
        if node.screenBox.y == 32.0:
          arrowTopWidth = node.screenBox.w
        elif node.screenBox.y == 34.0:
          arrowBottomWidth = node.screenBox.w

    for node in popupList.nodes:
      if node.kind == nkText:
        inc textNodeCount

      if node.kind == nkRectangle and node.screenBox.x == 10.0 and
          node.screenBox.y == 46.0 and node.screenBox.w == 120.0 and
          node.screenBox.h == 68.0:
        popupFound = true

      if node.kind == nkRectangle and
          node.fill ==
          linear(
            color(0.12, 0.40, 0.86, 0.87),
            color(0.0, 0.22, 0.66, 0.87),
            color(0.0, 0.08, 0.38, 0.87),
            fgaY,
            104'u8,
          ) and node.screenBox.x == 11.0 and node.screenBox.y == 69.0 and
          node.screenBox.w == 118.0 and node.screenBox.h == 22.0:
        selectedItemFound = true

    check comboBoxFound
    check not popupInBaseLayer
    check popupFound
    check selectedItemFound
    check arrowTopWidth > arrowBottomWidth
    check textNodeCount >= 4

  test "buildRenders draws popup menu button items":
    let
      root = newView(frame = rect(0, 0, 220, 150))
      menu = newMenu("Actions")
      button = newPopupMenuButton("Actions", menu, rect(10, 4, 82, 24))

    discard menu.addItem(
      newMenuItem("Run Menu Action", keyEquivalent = "r", modifiers = {kmCommand})
    )
    discard menu.addSeparator()
    discard menu.addItem(newMenuItem("Reset Count"))
    root.addSubview(button)
    button.popupPresentation = ppInline
    button.openPopup()

    let renders = buildRenders(root)
    check PopupDrawLevel in renders

    var
      panelFound = false
      runFound = false
      keyEquivalentFound = false
      separatorFound = false
      resetFound = false

    for node in renders[PopupDrawLevel].nodes:
      if node.kind == nkRectangle and node.screenBox.x == 10.0 and
          node.screenBox.y == 28.0 and node.screenBox.w == 180.0 and
          node.screenBox.h == 74.0 and node.stroke.weight == 1.0:
        panelFound = true
        check node.corners[dcTopLeft] == 12'u16
        check node.corners[dcTopRight] == 12'u16
      if node.kind == nkRectangle and node.screenBox.x == 19.0 and
          node.screenBox.y == 65.0 and node.screenBox.w == 162.0 and
          node.screenBox.h == 1.0:
        separatorFound = true
      if node.kind == nkText:
        case node.renderedText()
        of "Run Menu Action":
          runFound = true
        of "Cmd-r":
          keyEquivalentFound = true
        of "Reset Count":
          resetFound = true
        else:
          discard

    check panelFound
    check runFound
    check keyEquivalentFound
    check separatorFound
    check resetFound

  test "buildRenders draws a menu bar from a main menu":
    let
      root = newView(frame = rect(0, 0, 240, 80))
      mainMenu = newMenu("Main")
      actionsMenu = newMenu("Actions")
      actionsItem = newMenuItem("Actions")

    actionsItem.submenu = actionsMenu
    discard mainMenu.addItem(actionsItem)
    root.addSubview(newMenuBar(mainMenu, rect(0, 0, 240, 28)))

    let renders = buildRenders(root)
    var
      titleFound = false
      dividerFound = false

    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkText and node.renderedText() == "Actions":
        titleFound = true
      if node.kind == nkRectangle and node.screenBox.x == 0.0 and
          node.screenBox.y == 27.0 and node.screenBox.w == 240.0 and
          node.screenBox.h == 1.0:
        dividerFound = true

    check titleFound
    check dividerFound

  test "buildRenders draws hovered menu bar items as highlighted":
    let
      root = newView(frame = rect(0, 0, 240, 80))
      mainMenu = newMenu("Main")
      actionsMenu = newMenu("Actions")
      actionsItem = newMenuItem("Actions")
      menuBar = newMenuBar(mainMenu, rect(0, 0, 240, 28))

    actionsItem.submenu = actionsMenu
    discard mainMenu.addItem(actionsItem)
    menuBar.reload()
    root.addSubview(menuBar)
    root.layoutSubtreeIfNeeded()
    check menuBar.subviews.len == 1
    menuBar.subviews[0].hovered = true

    let renders = buildRenders(root)
    var hoverFound = false

    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.screenBox.y == 2.0 and
          node.screenBox.h == 24.0 and node.fill.kind == flColor and
          node.fill.color == color(0.76, 0.81, 0.91).rgba:
        hoverFound = true
        check node.stroke.weight == 1.0
        check node.corners[dcTopLeft] == 4'u16

    check hoverFound

  test "buildRenders draws standalone one-column table views with table roles":
    let
      root = newView(frame = rect(0, 0, 220, 140))
      tableView = newSingleColumnRenderTable(
        ["One", "Two", "Three", "Four"], frame = rect(10, 20, 130, 68)
      )
      tableFill = color(0.77, 0.79, 0.81, 1.0)
      tableBorder = color(0.24, 0.28, 0.34, 1.0)
      selectedFill = color(0.23, 0.48, 0.92, 1.0)
      hoverFill = color(0.90, 0.95, 1.0, 1.0)
      selectedText = color(1.0, 1.0, 1.0, 1.0)
      focusColor = color(0.91, 0.38, 0.18, 0.66)

    var theme = initTheme()
    theme[srTableView, StyleFill] = tableFill
    theme[srTableView, StyleBorderColor] = tableBorder
    theme[srTableView, StyleBorderWidth] = 2.0
    theme[srTableView, StyleCornerRadius] = 4.0
    theme[srTableView, StyleFocusRingWidth] = 3.0
    theme[srTableView, StyleFocusRingInset] = -1.0
    theme[srTableView, StyleFocusRingColor] = focusColor
    theme[srRowItem, {ssSelected}, StyleFill] = selectedFill
    theme[srRowItem, {ssSelected}, StyleTextColor] = selectedText
    theme[srRowItem, {ssHovered}, StyleFill] = hoverFill
    theme[srRowItem, StyleTextInsets] = insets(0.0, 5.0)

    tableView.rowHeight = 20.0
    tableView.selectedIndex = 1
    tableView.highlightedIndex = 2
    tableView.focusVisible = true
    root.addSubview(tableView)

    let list = buildRenders(root, initAppearance(theme))[DefaultDrawLevel]

    var
      selectedRowFound = false
      highlightedRowFound = false
      selectedTextFound = false

    for node in list.nodes:
      case node.kind
      of nkRectangle:
        if node.fill.kind == flColor and node.fill.color == selectedFill.rgba and
            node.screenBox.x == 11.0 and node.screenBox.y == 41.0 and
            node.screenBox.w == 120.0 and node.screenBox.h == 20.0:
          selectedRowFound = true

        if node.fill.kind == flColor and node.fill.color == hoverFill.rgba and
            node.screenBox.x == 11.0 and node.screenBox.y == 61.0 and
            node.screenBox.w == 120.0 and node.screenBox.h == 20.0:
          highlightedRowFound = true
      of nkText:
        if node.renderedText() == "Two" and node.textLayout.spanColors.len > 0 and
            node.textLayout.spanColors[0].kind == flColor and
            node.textLayout.spanColors[0].color == selectedText.rgba:
          selectedTextFound = true
          check node.screenBox.x == 16.0
          check node.screenBox.y == 41.0
          check node.screenBox.w == 110.0
          check node.screenBox.h == 20.0
          check node.parent != (-1).FigIdx
          let clipNode = list.nodes[int(node.parent)]
          check clipNode.kind == nkRectangle
          check NfClipContent in clipNode.flags
          check clipNode.screenBox == node.screenBox
      else:
        discard

    check selectedRowFound
    check highlightedRowFound
    check selectedTextFound

  test "buildRenders rounds no-header table row backgrounds at table corners":
    let
      root = newView(frame = rect(0, 0, 180, 130))
      tableView = newSingleColumnRenderTable(
        ["One", "Two", "Three"], frame = rect(10, 20, 130, 86)
      )
      rowFill = color(0.98, 0.99, 1.0, 1.0)

    tableView.rowHeight = 28.0
    tableView.visibleRows = 3
    root.addSubview(tableView)

    var theme = initTheme()
    theme[srTableView, StyleBorderWidth] = 1.0
    theme[srTableView, StyleCornerRadius] = 6.0
    theme[srRowItem, StyleFill] = rowFill

    let list = buildRenders(root, initAppearance(theme))[DefaultDrawLevel]
    var
      firstRowFound = false
      middleRowFound = false
      lastRowFound = false

    for node in list.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == rowFill.rgba and node.screenBox.x == 11.0 and
          node.screenBox.w == 128.0 and node.screenBox.h == 28.0:
        if node.screenBox.y == 21.0:
          firstRowFound = true
          check node.corners[dcTopLeft] == 5'u16
          check node.corners[dcTopRight] == 5'u16
          check node.corners[dcBottomLeft] == 0'u16
          check node.corners[dcBottomRight] == 0'u16
        elif node.screenBox.y == 49.0:
          middleRowFound = true
          check node.corners[dcTopLeft] == 0'u16
          check node.corners[dcTopRight] == 0'u16
          check node.corners[dcBottomLeft] == 0'u16
          check node.corners[dcBottomRight] == 0'u16
        elif node.screenBox.y == 77.0:
          lastRowFound = true
          check node.corners[dcTopLeft] == 0'u16
          check node.corners[dcTopRight] == 0'u16
          check node.corners[dcBottomLeft] == 5'u16
          check node.corners[dcBottomRight] == 5'u16

    check firstRowFound
    check middleRowFound
    check lastRowFound

  test "buildRenders keeps table focus ring below visible headers":
    let
      root = newView(frame = rect(0, 0, 220, 140))
      tableView = newTableView(frame = rect(10, 20, 130, 68))
      focusColor = color(0.91, 0.38, 0.18, 0.66)

    tableView.addColumn(newTableColumn("value", "Value", width = 120.0))
    tableView.focusVisible = true

    var theme = initTheme()
    theme[srTableView, StyleFocusRingWidth] = 3.0
    theme[srTableView, StyleFocusRingInset] = -1.0
    theme[srTableView, StyleFocusRingColor] = focusColor
    root.addSubview(tableView)

    let renders = buildRenders(root, initAppearance(theme))
    let list = renders[FocusRingDrawLevel]
    var
      bodyFocusRingFound = false
      fullTableFocusRingFound = false

    for node in list.nodes:
      if node.kind == nkRectangle and node.stroke.weight == 3.0 and
          node.stroke.fill.kind == flColor and node.stroke.fill.color == focusColor.rgba:
        check node.parent != (-1).FigIdx
        let clipNode = list.nodes[int(node.parent)]
        check clipNode.kind == nkRectangle
        check NfClipContent in clipNode.flags
        check clipNode.screenBox.x == 7.5
        check clipNode.screenBox.y == 41.5
        check clipNode.screenBox.w == 135.0
        check clipNode.screenBox.h == 49.0
        if node.screenBox.h >= tableView.frame.size.height:
          fullTableFocusRingFound = true
        if node.screenBox.h <=
            tableView.frame.size.height - tableView.tableHeaderHeight() + 2.0:
          bodyFocusRingFound = true

    check bodyFocusRingFound
    check not fullTableFocusRingFound

    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.stroke.weight == 3.0 and
          node.stroke.fill.kind == flColor and node.stroke.fill.color == focusColor.rgba:
        fail()

  test "buildRenders draws no-header table focus ring outside with gap":
    let
      root = newView(frame = rect(0, 0, 180, 120))
      tableView = newTableView(frame = rect(10, 20, 130, 68))
      focusColor = color(0.24, 0.48, 0.92, 0.58)

    tableView.addColumn(newTableColumn("value", "Value", width = 120.0))
    tableView.showsHeader = false
    tableView.focusVisible = true

    var theme = initTheme()
    theme[srTableView, StyleFocusRingWidth] = 3.0
    theme[srTableView, StyleFocusRingInset] = -5.0
    theme[srTableView, StyleFocusRingColor] = focusColor
    root.addSubview(tableView)

    let list = buildRenders(root, initAppearance(theme))[FocusRingDrawLevel]
    var focusRingFound = false

    for node in list.nodes:
      if node.kind == nkRectangle and node.stroke.weight == 3.0 and
          node.stroke.fill.kind == flColor and node.stroke.fill.color == focusColor.rgba:
        focusRingFound = true
        check node.parent != (-1).FigIdx
        check node.screenBox.x == 5.0
        check node.screenBox.y == 15.0
        check node.screenBox.w == 140.0
        check node.screenBox.h == 78.0
        let clipNode = list.nodes[int(node.parent)]
        check clipNode.kind == nkRectangle
        check NfClipContent in clipNode.flags
        check clipNode.screenBox.x == 3.5
        check clipNode.screenBox.y == 13.5
        check clipNode.screenBox.w == 143.0
        check clipNode.screenBox.h == 81.0

    check focusRingFound

  test "buildRenders clamps no-header table focus ring to stroke edge":
    let
      root = newView(frame = rect(0, 0, 180, 120))
      tableView = newTableView(frame = rect(10, 20, 130, 68))
      focusColor = color(0.24, 0.48, 0.92, 0.58)

    tableView.addColumn(newTableColumn("value", "Value", width = 120.0))
    tableView.showsHeader = false
    tableView.focusVisible = true

    var theme = initTheme()
    theme[srTableView, StyleFocusRingWidth] = 4.0
    theme[srTableView, StyleFocusRingInset] = 12.0
    theme[srTableView, StyleFocusRingColor] = focusColor
    root.addSubview(tableView)

    let list = buildRenders(root, initAppearance(theme))[FocusRingDrawLevel]
    var focusRingFound = false

    for node in list.nodes:
      if node.kind == nkRectangle and node.stroke.weight == 4.0 and
          node.stroke.fill.kind == flColor and node.stroke.fill.color == focusColor.rgba:
        focusRingFound = true
        check node.parent != (-1).FigIdx
        let clipNode = list.nodes[int(node.parent)]
        check clipNode.kind == nkRectangle
        check NfClipContent in clipNode.flags
        check clipNode.screenBox.x == 10.0
        check clipNode.screenBox.y == 20.0
        check clipNode.screenBox.w == 130.0
        check clipNode.screenBox.h == 68.0
        check node.screenBox.x == 12.0
        check node.screenBox.y == 22.0
        check node.screenBox.w == 126.0
        check node.screenBox.h == 64.0

    check focusRingFound

  test "buildRenders clips table focus ring to visible ancestor bounds":
    let
      root = newView(frame = rect(0, 0, 140, 100))
      clipView = newView(frame = rect(10, 20, 80, 70))
      tableView = newTableView(frame = rect(60, 0, 80, 60))
      focusColor = color(0.24, 0.48, 0.92, 0.58)

    tableView.addColumn(newTableColumn("value", "Value", width = 70.0))
    tableView.showsHeader = false
    tableView.focusVisible = true
    clipView.clipsToBounds = true
    clipView.addSubview(tableView)
    root.addSubview(clipView)

    var theme = initTheme()
    theme[srTableView, StyleFocusRingWidth] = 3.0
    theme[srTableView, StyleFocusRingColor] = focusColor

    let list = buildRenders(root, initAppearance(theme))[FocusRingDrawLevel]
    var focusRingFound = false

    for node in list.nodes:
      if node.kind == nkRectangle and node.stroke.weight == 3.0 and
          node.stroke.fill.kind == flColor and node.stroke.fill.color == focusColor.rgba:
        focusRingFound = true
        check node.parent != (-1).FigIdx
        let clipNode = list.nodes[int(node.parent)]
        check clipNode.kind == nkRectangle
        check NfClipContent in clipNode.flags
        check clipNode.screenBox.x == 66.5
        check clipNode.screenBox.y == 20.0
        check clipNode.screenBox.w == 23.5
        check clipNode.screenBox.h == 63.5

    check focusRingFound

  test "buildRenders keeps scrolled table focus ring in scroll coordinates":
    let
      root = newView(frame = rect(0, 0, 220, 130))
      document = newView(frame = rect(0, 0, 320, 100))
      tableView = newTableView(frame = rect(60, 0, 90, 60))
      scrollView = newScrollView(frame = rect(20, 20, 120, 80), documentView = document)
      focusColor = color(0.24, 0.48, 0.92, 0.58)

    tableView.addColumn(newTableColumn("value", "Value", width = 80.0))
    tableView.showsHeader = false
    tableView.focusVisible = true
    document.addSubview(tableView)
    root.addSubview(scrollView)
    scrollView.hasHorizontalScroller = true
    scrollView.contentOffset = initPoint(40, 0)

    var theme = initTheme()
    theme[srTableView, StyleFocusRingWidth] = 3.0
    theme[srTableView, StyleFocusRingColor] = focusColor

    let list = buildRenders(root, initAppearance(theme))[FocusRingDrawLevel]
    var focusRingFound = false

    for node in list.nodes:
      if node.kind == nkRectangle and node.stroke.weight == 3.0 and
          node.stroke.fill.kind == flColor and node.stroke.fill.color == focusColor.rgba:
        focusRingFound = true
        check node.parent != (-1).FigIdx
        let clipNode = list.nodes[int(node.parent)]
        check clipNode.kind == nkRectangle
        check NfClipContent in clipNode.flags
        check clipNode.screenBox.x == 36.5
        check clipNode.screenBox.y == 20.0
        check clipNode.screenBox.w == 97.0
        check clipNode.screenBox.h == 63.5

    check focusRingFound

  test "buildRenders draws focused text field selection and caret":
    let
      root = newView(frame = rect(0, 0, 180, 80))
      field = newTextField("Field", frame = rect(10, 20, 120, 30))

    root.addSubview(field)
    discard field.becomeFirstResponder()
    field.setSelectedRange(initTextRange(1, 2))

    let selectionRenders = buildRenders(root)
    var selectionFound = false
    for node in selectionRenders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == color(0.24, 0.56, 1.0, 0.34).rgba and node.screenBox.w > 1.0 and
          node.screenBox.h > 0.0:
        selectionFound = true

    field.setSelectedRange(initTextRange(3, 0))
    let caretRenders = buildRenders(root)
    var caretFound = false
    for node in caretRenders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == field.textColor.rgba and node.screenBox.w == 1.0:
        caretFound = true

    check selectionFound
    check caretFound

  test "buildRenders uses active view state for control styling":
    let
      root = newView(frame = rect(0, 0, 140, 80))
      button = newButton("Button", frame = rect(10, 20, 80, 24))

    let activeFill = color(0.8, 0.2, 0.1, 1.0)
    var theme = initTheme()
    theme[srButton, StyleFill] = color(0.1, 0.1, 0.1, 1.0)
    theme[srButton, {ssActive}, StyleFill] = activeFill

    root.addSubview(button)
    button.active = true

    let list = buildRenders(root, initAppearance(theme))[DefaultDrawLevel]

    var activeFillFound = false
    for node in list.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == activeFill.rgba:
        activeFillFound = true

    check activeFillFound

  test "matrix button cells do not inherit active state from the matrix":
    let
      root = newView(frame = rect(0, 0, 240, 80))
      matrix = newButtonMatrix(
        ["Apply", "Reset", "Inspect"], columns = 3, frame = rect(10, 20, 180, 28)
      )
      baseFill = color(0.1, 0.1, 0.1, 1.0)
      activeFill = color(0.8, 0.2, 0.1, 1.0)
      pressedFill = color(0.1, 0.2, 0.8, 1.0)

    matrix.cellSize = initSize(50.0, 24.0)
    matrix.active = true
    matrix.cellAtIndex(1).setHighlighted(true)

    var theme = initTheme()
    theme[srButton, StyleFill] = baseFill
    theme[srButton, {ssActive}, StyleFill] = activeFill
    theme[srButton, {ssHighlighted}, StyleFill] = pressedFill
    theme[srButton, {ssPressed}, StyleFill] = pressedFill

    root.addSubview(matrix)
    let list = buildRenders(root, initAppearance(theme))[DefaultDrawLevel]

    var
      baseCount = 0
      activeCount = 0
      pressedCount = 0
    for node in list.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor:
        if node.fill.color == baseFill.rgba:
          inc baseCount
        elif node.fill.color == activeFill.rgba:
          inc activeCount
        elif node.fill.color == pressedFill.rgba:
          inc pressedCount

    check baseCount >= 2
    check activeCount == 0
    check pressedCount == 1

  test "buildRenders draws focus visible control rings":
    let
      root = newView(frame = rect(0, 0, 140, 80))
      button = newButton("Button", frame = rect(10, 20, 80, 24))
      focusColor = color(0.24, 0.48, 0.92, 0.58)

    var theme = initTheme()
    theme[srButton, StyleFocusRingWidth] = 4.0
    theme[srButton, StyleFocusRingInset] = -2.0
    theme[srButton, StyleFocusRingColor] = focusColor
    theme[srButton, StyleCornerRadius] = 5.0

    root.addSubview(button)
    button.focused = true
    button.focusVisible = true

    let list = buildRenders(root, initAppearance(theme))[DefaultDrawLevel]

    var focusRingFound = false
    for node in list.nodes:
      if node.kind == nkRectangle and node.stroke.fill.kind == flColor and
          node.stroke.fill.color == focusColor.rgba:
        focusRingFound = true
        check node.stroke.weight == 4.0
        check node.screenBox.x == 8.0
        check node.screenBox.y == 18.0
        check node.screenBox.w == 84.0
        check node.screenBox.h == 28.0
        check node.corners[dcTopLeft] == 7'u16

    check focusRingFound

  test "buildRenders uses theme metrics for checkbox and radio buttons":
    let
      root = newView(frame = rect(0, 0, 220, 110))
      checkbox = newCheckBox("Check", frame = rect(10, 20, 120, 24))
      radio = newRadioButton("Radio", frame = rect(10, 56, 120, 24))

    let
      selectedFill = color(0.23, 0.45, 0.67, 1.0)
      markFill = color(0.91, 0.82, 0.13, 1.0)

    var theme = initTheme()
    for role in [srCheckBox, srRadioButton]:
      theme[role, {ssSelected}, StyleFill] = selectedFill
      theme[role, {ssSelected}, StyleMarkColor] = markFill
      theme[role, StyleChrome] = styleKeyword(DefaultChromeName)
      theme[role, StyleIndicatorSize] = 12.0
      theme[role, StyleCornerRadius] = if role == srRadioButton: 6.0 else: 3.0
      theme[role, StyleIndicatorSpacing] = 5.0
      theme[role, StyleTextInsets] = insets(0.0, 3.0)

    checkbox.setState(bsOn)
    radio.setState(bsOn)
    root.addSubview(checkbox)
    root.addSubview(radio)

    let list = buildRenders(root, initAppearance(theme))[DefaultDrawLevel]

    var
      selectedIndicatorCount = 0
      markCount = 0
      checkmarkTextCount = 0
      radioIndicatorFound = false

    for node in list.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor:
        if node.fill.color == selectedFill.rgba:
          inc selectedIndicatorCount
        if node.fill.color == markFill.rgba:
          inc markCount
        if node.screenBox.x == 13.0 and node.screenBox.y == 62.0 and
            node.screenBox.w == 12.0 and node.screenBox.h == 12.0:
          radioIndicatorFound = true
          check node.corners[dcTopLeft] == 6'u16
      elif node.kind == nkText and node.textLayout.runes.len > 0:
        var text = ""
        for rune in node.textLayout.runes:
          text.add(rune)
        if text == "✓":
          inc checkmarkTextCount
          check node.textLayout.selectionRects.len == 1
          check node.textLayout.selectionRects[0].w > 0.0
          check node.textLayout.selectionRects[0].h > 0.0
          check node.textLayout.spanColors.len == 1
          check node.textLayout.spanColors[0].kind == flColor
          check node.textLayout.spanColors[0].color == markFill.rgba

    check selectedIndicatorCount == 2
    check markCount == 1
    check checkmarkTextCount >= 2
    check radioIndicatorFound

  test "buildRenders uses effective appearance from view hierarchy":
    let
      root = newView(frame = rect(0, 0, 140, 80))
      button = newButton("Button", frame = rect(10, 20, 80, 24))
      rootFill = color(0.2, 0.3, 0.4, 1.0)
      buttonFill = color(0.7, 0.1, 0.2, 1.0)

    var rootAppearance = initAppearance()
    rootAppearance[srButton, StyleFill] = rootFill
    root.appearance = rootAppearance
    root.addSubview(button)

    var buttonAppearance = initAppearance()
    buttonAppearance[srButton, StyleFill] = buttonFill
    button.appearance = buttonAppearance

    let list = buildRenders(root)[DefaultDrawLevel]

    var
      buttonFillFound = false
      rootFillFound = false

    for node in list.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor:
        if node.fill.color == buttonFill.rgba:
          buttonFillFound = true
        if node.fill.color == rootFill.rgba:
          rootFillFound = true

    check buttonFillFound
    check not rootFillFound

  test "buildRenders uses FigDraw hierarchy and clears invalid state":
    let
      root = newView(frame = rect(0, 0, 200, 160))
      child = newView(frame = rect(20, 30, 80, 50))

    root.addSubview(child)
    root.setNeedsDisplay(false)
    child.setNeedsDisplay(false)
    child.setNeedsDisplayInRect(rect(5, 6, 10, 11))

    let renders = buildRenders(root)
    let list = renders[DefaultDrawLevel]

    check list.rootIds.len == 1
    check NfClipContent notin list.nodes[int(list.rootIds[0])].flags

    var childNodeCount = 0
    for node in list.nodes:
      if node.parent != (-1).FigIdx:
        inc childNodeCount
    check childNodeCount > 0
    check not root.needsDisplay
    check root.invalidRects.len == 0
    check not child.needsDisplay
    check child.invalidRects.len == 0

  test "buildRenders reuses cached renders until display or appearance changes":
    let
      root = newView(frame = rect(0, 0, 120, 90))
      custom = newCustomDrawView(rect(10, 12, 50, 30))

    customDrawCount = 0
    root.addSubview(custom)

    let firstRenders = buildRenders(root)
    check customDrawCount == 1
    let cachedRenders = buildRenders(root)
    check cachedRenders == firstRenders
    check customDrawCount == 1

    custom.setNeedsDisplay(true)
    let invalidatedRenders = buildRenders(root)
    check invalidatedRenders != firstRenders
    check customDrawCount == 2

    var theme = initTheme()
    theme[srView, StyleFill] = color(0.1, 0.2, 0.3, 1.0)
    let themedRenders = buildRenders(root, initAppearance(theme))
    check themedRenders != invalidatedRenders
    check customDrawCount == 3

  test "buildRenders does not clip view subtrees by default":
    let
      root = newView(frame = rect(0, 0, 100, 80))
      child = newView(frame = rect(90, 90, 50, 40))

    root.setBounds(rect(10, 20, 100, 80))
    root.addSubview(child)

    let renders = buildRenders(root)
    let list = renders[DefaultDrawLevel]
    let rootIdx = list.rootIds[0]

    check list.nodes[int(rootIdx)].screenBox.x == 0.0
    check list.nodes[int(rootIdx)].screenBox.y == 0.0
    check list.nodes[int(rootIdx)].screenBox.w == 100.0
    check list.nodes[int(rootIdx)].screenBox.h == 80.0
    check NfClipContent notin list.nodes[int(rootIdx)].flags

    var childIdx = (-1).FigIdx
    for idx in childIndex(list.nodes, rootIdx):
      if list.nodes[int(idx)].kind == nkRectangle:
        childIdx = idx

    check childIdx != (-1).FigIdx
    check list.nodes[int(childIdx)].parent == rootIdx
    check list.nodes[int(childIdx)].screenBox.x == 80.0
    check list.nodes[int(childIdx)].screenBox.y == 70.0
    check list.nodes[int(childIdx)].screenBox.w == 50.0
    check list.nodes[int(childIdx)].screenBox.h == 40.0
    check NfClipContent notin list.nodes[int(childIdx)].flags

  test "buildRenders adds FigDraw clipping when views clip to bounds":
    let
      root = newView(frame = rect(0, 0, 100, 80))
      child = newView(frame = rect(90, 90, 50, 40))

    root.setBounds(rect(10, 20, 100, 80))
    root.setClipsToBounds(true)
    child.setClipsToBounds(true)
    root.addSubview(child)

    let renders = buildRenders(root)
    let list = renders[DefaultDrawLevel]
    let rootIdx = list.rootIds[0]

    check NfClipContent in list.nodes[int(rootIdx)].flags

    var childIdx = (-1).FigIdx
    for idx in childIndex(list.nodes, rootIdx):
      if list.nodes[int(idx)].kind == nkRectangle:
        childIdx = idx

    check childIdx != (-1).FigIdx
    check list.nodes[int(childIdx)].screenBox.x == 80.0
    check list.nodes[int(childIdx)].screenBox.y == 70.0
    check NfClipContent in list.nodes[int(childIdx)].flags

  test "buildRenders calls selector-backed custom drawing":
    let
      root = newView(frame = rect(0, 0, 100, 80))
      custom = newCustomDrawView(rect(10, 20, 50, 40))

    customDrawCount = 0
    root.addSubview(custom)

    let renders = buildRenders(root)
    let list = renders[DefaultDrawLevel]

    check customDrawCount == 1

    var customRoot = (-1).FigIdx
    for idx in childIndex(list.nodes, list.rootIds[0]):
      if list.nodes[int(idx)].screenBox.x == 10.0 and
          list.nodes[int(idx)].screenBox.y == 20.0:
        customRoot = idx

    check customRoot != (-1).FigIdx

    var customRectFound = false
    var customTextFound = false
    var customLineFound = false
    var customCircleFound = false
    for idx, node in list.nodes:
      if not inCustomSubtree(list.nodes, customRoot, idx.FigIdx):
        continue
      if node.fill.kind != flColor:
        continue
      if node.kind == nkRectangle and node.screenBox.x == 14.0 and
          node.screenBox.y == 25.0 and node.screenBox.w == 20.0 and
          node.screenBox.h == 10.0:
        customRectFound = true
      if node.kind == nkText and node.screenBox.x == 14.0 and node.screenBox.y == 25.0 and
          node.screenBox.w == 20.0 and node.screenBox.h == 10.0:
        customTextFound = true
      if node.kind == nkRectangle and node.fill.kind == flColor and
          approxColor(node.fill.color, CustomLineFill.color) and
          abs(node.rotation) >= 10.0:
        customLineFound = true
      if node.kind == nkRectangle and node.fill.kind == flColor and
          approxColor(node.fill.color, CustomCircleFill.color) and
          approx(node.screenBox.x, 39.0) and approx(node.screenBox.y, 32.0) and
          approx(node.screenBox.w, 12.0) and approx(node.screenBox.h, 12.0):
        customCircleFound = true

    if not customRectFound:
      echo "custom rect not found"
    if not customTextFound:
      echo "custom text not found"
    if not customLineFound:
      echo "custom line not found"
    if not customCircleFound:
      echo "custom circle not found"
    if not (customRectFound and customTextFound and customLineFound and customCircleFound):
      echo "custom draw subtree nodes:"
      for idx, node in list.nodes:
        if not inCustomSubtree(list.nodes, customRoot, idx.FigIdx):
          continue
        let color = node.fill.color
        echo "  idx=", idx, " kind=", $node.kind, " fill=", $node.fill.kind,
          " fillRGBA=", color.r, ",", color.g, ",", color.b, ",", color.a, " rect=",
          node.screenBox.x, ",", node.screenBox.y, ",", node.screenBox.w, ",",
          node.screenBox.h, " rot=", node.rotation

    check customRectFound
    check customTextFound
    check customLineFound
    check customCircleFound
