import std/[unicode, unittest]

import figdraw/fignodes

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes

type CustomDrawView = ref object of View

var customDrawCount: int

const ExtraChromeName = "render-extra-chrome"

let ExtraChromeFill = fill(initColor(0.72, 0.10, 0.48, 1.0))

type ExtraChrome = ref object of Chrome

func aquaChoiceSelectedFill(): Fill =
  linear(initColor(0.48, 0.91, 1.0, 1.0), initColor(0.0, 0.49, 0.93, 1.0), fgaDiagTLBR)

func aquaRadioShellFill(): Fill =
  linear(initColor(0.99, 0.99, 0.98, 1.0), initColor(0.65, 0.66, 0.64, 1.0), fgaY)

protocol CustomDrawing of ViewDrawingProtocol:
  method draw(view: CustomDrawView, context: DrawContext) =
    inc customDrawCount
    context.addRectangle(initRect(4, 5, 20, 10), initColor(0.8, 0.1, 0.1))
    context.addText(initRect(4, 5, 20, 10), "C", initColor(1, 1, 1))

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
      extras.layer,
      extras.parent,
      extras.rect.inset(initEdgeInsets(5.0)),
      ExtraChromeFill,
    )

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
  nimkitTypes.initRect(
    node.screenBox.x.float32, node.screenBox.y.float32, node.screenBox.w.float32,
    node.screenBox.h.float32,
  )

proc rectsClose(left, right: nimkitTypes.Rect): bool =
  abs(left.origin.x - right.origin.x) <= 0.01'f32 and
    abs(left.origin.y - right.origin.y) <= 0.01'f32 and
    abs(left.size.width - right.size.width) <= 0.01'f32 and
    abs(left.size.height - right.size.height) <= 0.01'f32

suite "nimkit rendering":
  test "buildRenders emits root, text field, and button nodes":
    let root = newView(frame = initRect(0, 0, 320, 200))
    root.setBackgroundColor(initColor(1, 1, 1))
    root.addSubview(newTextField("Ready", frame = initRect(16, 16, 180, 32)))
    root.addSubview(newButton("Click", frame = initRect(16, 64, 120, 36)))

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
      root = newView(frame = initRect(0, 0, 120, 80))
      shadow = dropShadow(initColor(0, 0, 0, 0.4), y = 3.0, blur = 7.0)

    root.backgroundColor = initColor(0.2, 0.4, 0.6, 0.8)
    root.alphaValue = 0.5
    root.shadow = [shadow]

    let list = buildRenders(root)[DefaultDrawLevel]
    check list.rootIds.len == 1

    let node = list.nodes[list.rootIds[0].int]
    check node.kind == nkRectangle
    check node.fill.kind == flColor
    check node.fill.color == initColor(0.2, 0.4, 0.6, 0.4).rgba
    check node.shadows[0].style == DropShadow
    check node.shadows[0].fill.kind == flColor
    check node.shadows[0].fill.color == initColor(0, 0, 0, 0.4).rgba
    check node.shadows[0].y == 3.0
    check node.shadows[0].blur == 7.0

  test "buildRenders uses theme colors and metrics for built-in controls":
    let
      root = newView(frame = initRect(0, 0, 180, 120))
      field = newTextField("Field", frame = initRect(10, 20, 100, 30))
      button = newButton("Button", frame = initRect(10, 60, 80, 24))

    let
      buttonFill = initColor(0.31, 0.42, 0.53, 1.0)
      buttonBorder = initColor(0.11, 0.12, 0.13, 1.0)
      fieldFill = initColor(0.91, 0.92, 0.93, 1.0)
      fieldBorder = initColor(0.21, 0.22, 0.23, 1.0)
      buttonShadows =
        @[
          dropShadow(initColor(0, 0, 0, 0.40), y = 2.0, blur = 5.0),
          insetShadow(initColor(1, 1, 1, 0.20), y = -1.0, blur = 1.0),
        ]

    var theme = initTheme()
    theme[srButton, StyleFill] = buttonFill
    theme[srButton, StyleBorderColor] = buttonBorder
    theme[srButton, StyleBorderWidth] = 3.0
    theme[srButton, StyleCornerRadius] = 6.0
    theme[srButton, StyleTextInsets] = initEdgeInsets(1.0, 9.0)
    theme[srButton, StyleBoxShadows] = buttonShadows
    theme[srTextField, StyleFill] = fieldFill
    theme[srTextField, StyleBorderColor] = fieldBorder
    theme[srTextField, StyleBorderWidth] = 2.0
    theme[srTextField, StyleCornerRadius] = 5.0
    theme[srTextField, StyleTextInsets] = initEdgeInsets(2.0, 7.0)

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
        check node.shadows[0].fill.color == initColor(0, 0, 0, 0.40).rgba
        check node.shadows[0].y == 2.0
        check node.shadows[0].blur == 5.0
        check node.shadows[1].style == InnerShadow
        check node.shadows[1].fill.kind == flColor
        check node.shadows[1].fill.color == initColor(1, 1, 1, 0.20).rgba
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
      root = newView(frame = initRect(0, 0, 360, 220))
      button = newButton("Metric", frame = initRect(12, 14, 20, 10))
      checkbox = newCheckBox("Choice", frame = initRect(12, 62, 20, 10))
      field = newTextField("Field", frame = initRect(12, 104, 20, 10))
      combo =
        newComboBox(["Short", "Longest metric item"], frame = initRect(12, 148, 20, 10))
      checkFill = initColor(0.64, 0.22, 0.17, 1.0)

    var appearance = initAppearance()
    appearance[srButton, StyleTextInsets] = initEdgeInsets(5.0, 18.0, 7.0, 22.0)
    appearance[srButton, StyleMinimumSize] = initSize(0.0, 46.0)
    appearance[srCheckBox, StyleFill] = checkFill
    appearance[srCheckBox, StyleChrome] = styleKeyword(DefaultChromeName)
    appearance[srCheckBox, StyleIndicatorSize] = 20.0
    appearance[srCheckBox, StyleIndicatorSpacing] = 11.0
    appearance[srCheckBox, StyleTextInsets] = initEdgeInsets(3.0, 8.0, 5.0, 10.0)
    appearance[srTextField, StyleTextInsets] = initEdgeInsets(4.0, 16.0, 6.0, 14.0)
    appearance[srTextField, StyleMinimumSize] = initSize(116.0, 36.0)
    appearance[srComboBox, StyleTextInsets] = initEdgeInsets(4.0, 15.0, 6.0, 13.0)
    appearance[srComboBox, StyleIndicatorSize] = 32.0
    appearance[srComboBox, StyleMinimumSize] = initSize(142.0, 36.0)

    root.appearance = appearance
    root.addSubviews(button, checkbox, field, combo)
    combo.selectedIndex = 1
    button.sizeToFit()
    checkbox.sizeToFit()
    field.sizeToFit()
    combo.sizeToFit()

    let
      buttonStyle = button.effectiveAppearance().resolveButtonStyle(
          initControlStyleContext(
            srButton, id = button.styleId, classes = button.styleClasses
          )
        )
      checkStyle = checkbox.effectiveAppearance().resolveChoiceButtonStyle(
          initControlStyleContext(
            srCheckBox, id = checkbox.styleId, classes = checkbox.styleClasses
          )
        )
      fieldStyle = field.effectiveAppearance().resolveTextFieldStyle(
          initControlStyleContext(
            srTextField, id = field.styleId, classes = field.styleClasses
          ),
          field.textColor(),
        )
      comboStyle = combo.effectiveAppearance().resolveComboBoxStyle(
          initControlStyleContext(
            srComboBox, id = combo.styleId, classes = combo.styleClasses
          )
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

  test "buildRenders draws Aqua push button layers":
    let
      root = newView(frame = initRect(0, 0, 180, 90))
      button = newButton("OK", frame = initRect(20, 24, 120, 32))

    root.addSubview(button)

    let
      style = button.effectiveAppearance().resolveButtonStyle(
          initControlStyleContext(
            srButton, id = button.styleId, classes = button.styleClasses
          )
        )
      expectedButtonRect = button.rectToWindow(button.bounds)
      expectedTextRect = button.rectToWindow(style.buttonTextRect(button.bounds))
      list = buildRenders(root)[DefaultDrawLevel]

    var buttonRoot = (-1).FigIdx
    for idx, node in list.nodes:
      if node.kind == nkRectangle and node.fill == style.box.fill and
          node.renderedRect().rectsClose(expectedButtonRect):
        buttonRoot = idx.FigIdx
        check NfRectMaskContent in node.flags
        check node.stroke.weight == style.box.borderWidth
        check node.stroke.fill.kind == flColor
        check node.stroke.fill.color == style.box.borderColor.rgba

    check buttonRoot != (-1).FigIdx

    var innerRoot = (-1).FigIdx
    for idx in childIndex(list.nodes, buttonRoot):
      let node = list.nodes[int(idx)]
      if node.kind == nkRectangle and NfRectMaskContent in node.flags and
          node.fill.kind == flLinear2:
        innerRoot = idx

    check innerRoot != (-1).FigIdx

    var glossFound = false
    for idx in childIndex(list.nodes, innerRoot):
      let node = list.nodes[int(idx)]
      if node.kind == nkRectangle and node.fill.kind == flLinear2 and
          node.fill.lin2.start.a > 0'u8 and node.fill.lin2.stop.a == 0'u8:
        glossFound = true

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
      root = newView(frame = initRect(0, 0, 180, 90))
      button = newButton("OK", frame = initRect(20, 24, 120, 32))

    var theme = initTheme()
    theme[srButton, StyleChrome] = styleKeyword(DefaultChromeName)
    theme[srButton, StyleTextHighlightColor] = initColor(0.0, 0.0, 0.0, 0.0)
    theme[srButton, StyleTextShadowColor] = initColor(0.0, 0.0, 0.0, 0.0)
    root.addSubview(button)

    let
      style = initAppearance(theme).resolveButtonStyle(
          initControlStyleContext(
            srButton, id = button.styleId, classes = button.styleClasses
          )
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

  test "buildRenders uses installed chrome extras selected per button":
    let
      root = newView(frame = initRect(0, 0, 260, 120))
      normalButton = newButton("Default", frame = initRect(20, 20, 100, 32))
      specialButton = newButton("Special", frame = initRect(140, 20, 100, 32))

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
        specialButton.rectToWindow(specialButton.bounds).inset(initEdgeInsets(5.0))

    var extraFound = false
    for node in list.nodes:
      if node.kind == nkRectangle and node.fill == ExtraChromeFill and
          node.renderedRect().rectsClose(expectedExtraRect):
        extraFound = true

    check extraFound

  test "buildRenders uses installed chrome extras for choices and combo popups":
    let
      root = newView(frame = initRect(0, 0, 240, 150))
      checkbox = newCheckBox("Choice", frame = initRect(12, 16, 120, 24))
      combo = newComboBox(["One", "Two"], frame = initRect(12, 52, 120, 26))

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
        initControlStyleContext(
          srCheckBox, id = checkbox.styleId, classes = checkbox.styleClasses
        )
      )
      expectedChoiceExtra = checkbox
        .rectToWindow(checkStyle.choiceIndicatorRect(checkbox.bounds))
        .inset(initEdgeInsets(5.0))
      expectedComboExtra = combo.rectToWindow(combo.bounds).inset(initEdgeInsets(5.0))
      expectedPopupExtra =
        combo.rectToWindow(combo.popupRect(combo.bounds)).inset(initEdgeInsets(5.0))
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
      root = newView(frame = initRect(0, 0, 220, 110))
      checkbox = newCheckBox("Check", frame = initRect(10, 20, 120, 24))
      radio = newRadioButton("Radio", frame = initRect(10, 56, 120, 24))

    checkbox.setState(bsOn)
    radio.setState(bsOn)
    root.addSubview(checkbox)
    root.addSubview(radio)

    let
      appearance = initAppearance(initTheme())
      checkStyle = appearance.resolveChoiceButtonStyle(
        initControlStyleContext(srCheckBox, {ssSelected})
      )
      radioStyle = appearance.resolveChoiceButtonStyle(
        initControlStyleContext(srRadioButton, {ssSelected})
      )
      checkboxIndicator =
        checkbox.rectToWindow(checkStyle.choiceIndicatorRect(checkbox.bounds))
      radioIndicator = radio.rectToWindow(radioStyle.choiceIndicatorRect(radio.bounds))
      radioInner = radioIndicator.inset(initEdgeInsets(1.6))
      radioGlossWidth = max(radioInner.size.width * 0.52'f32, 1.0'f32)
      radioGloss = initRect(
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
          check node.stroke.fill.color == initColor(0.0, 0.32, 0.75, 0.96).rgba
        if nodeRect.rectsClose(radioIndicator):
          radioShellFound = true
          check node.fill == aquaRadioShellFill()
        if nodeRect.rectsClose(radioInner):
          radioInnerAccentFound = true
          check node.fill == aquaChoiceSelectedFill()
          check node.stroke.fill.kind == flColor
          check node.stroke.fill.color == initColor(0.0, 0.32, 0.75, 0.96).rgba
        if nodeRect.rectsClose(radioGloss):
          radioGlossFound = true
          check nodeRect.size.width < radioInner.size.width * 0.60'f32

    check checkboxAccentFound
    check radioShellFound
    check radioInnerAccentFound
    check radioGlossFound

  test "buildRenders centers push button text by default":
    let
      root = newView(frame = initRect(0, 0, 160, 80))
      button = newButton("OK", frame = initRect(10, 20, 120, 30))

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
      root = newView(frame = initRect(0, 0, 220, 150))
      combo = newComboBox(["One", "Two", "Three"], frame = initRect(10, 20, 120, 26))

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
          node.fill.color == initColor(0.10, 0.16, 0.26, 1.0).rgba and
          node.screenBox.h == 1.0:
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
            initColor(0.20, 0.57, 0.98, 1.0),
            initColor(0.03, 0.33, 0.82, 1.0),
            initColor(0.01, 0.18, 0.58, 1.0),
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
      root = newView(frame = initRect(0, 0, 220, 150))
      menu = newMenu("Actions")
      button = newPopupMenuButton("Actions", menu, initRect(10, 4, 82, 24))

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
        check node.corners[dcTopLeft] == 6'u16
        check node.corners[dcTopRight] == 6'u16
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
      root = newView(frame = initRect(0, 0, 240, 80))
      mainMenu = newMenu("Main")
      actionsMenu = newMenu("Actions")
      actionsItem = newMenuItem("Actions")

    actionsItem.submenu = actionsMenu
    discard mainMenu.addItem(actionsItem)
    root.addSubview(newMenuBar(mainMenu, initRect(0, 0, 240, 28)))

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
      root = newView(frame = initRect(0, 0, 240, 80))
      mainMenu = newMenu("Main")
      actionsMenu = newMenu("Actions")
      actionsItem = newMenuItem("Actions")
      menuBar = newMenuBar(mainMenu, initRect(0, 0, 240, 28))

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
          node.fill.color == initColor(0.76, 0.81, 0.91).rgba:
        hoverFound = true
        check node.stroke.weight == 1.0
        check node.corners[dcTopLeft] == 4'u16

    check hoverFound

  test "buildRenders draws standalone list views with list roles":
    let
      root = newView(frame = initRect(0, 0, 220, 140))
      listView =
        newListView(["One", "Two", "Three", "Four"], frame = initRect(10, 20, 130, 68))
      listFill = initColor(0.77, 0.79, 0.81, 1.0)
      listBorder = initColor(0.24, 0.28, 0.34, 1.0)
      selectedFill = initColor(0.23, 0.48, 0.92, 1.0)
      hoverFill = initColor(0.90, 0.95, 1.0, 1.0)
      selectedText = initColor(1.0, 1.0, 1.0, 1.0)
      focusColor = initColor(0.91, 0.38, 0.18, 0.66)

    var theme = initTheme()
    theme[srListView, StyleFill] = listFill
    theme[srListView, StyleBorderColor] = listBorder
    theme[srListView, StyleBorderWidth] = 2.0
    theme[srListView, StyleCornerRadius] = 4.0
    theme[srListView, StyleFocusRingWidth] = 3.0
    theme[srListView, StyleFocusRingInset] = -1.0
    theme[srListView, StyleFocusRingColor] = focusColor
    theme[srListItem, {ssSelected}, StyleFill] = selectedFill
    theme[srListItem, {ssSelected}, StyleTextColor] = selectedText
    theme[srListItem, {ssHovered}, StyleFill] = hoverFill
    theme[srListItem, StyleTextInsets] = initEdgeInsets(0.0, 5.0)

    listView.rowHeight = 20.0
    listView.selectedIndex = 1
    listView.highlightedIndex = 2
    listView.focusVisible = true
    root.addSubview(listView)

    let list = buildRenders(root, initAppearance(theme))[DefaultDrawLevel]

    var
      listBoxFound = false
      selectedRowFound = false
      highlightedRowFound = false
      selectedTextFound = false
      focusRingFound = false

    for node in list.nodes:
      case node.kind
      of nkRectangle:
        if node.fill.kind == flColor and node.fill.color == listFill.rgba and
            node.screenBox.x == 10.0 and node.screenBox.y == 20.0 and
            node.screenBox.w == 130.0 and node.screenBox.h == 68.0:
          listBoxFound = true
          check node.stroke.weight == 2.0
          check node.stroke.fill.kind == flColor
          check node.stroke.fill.color == listBorder.rgba
          check node.corners[dcTopLeft] == 4'u16
          check NfClipContent in node.flags

        if node.fill.kind == flColor and node.fill.color == selectedFill.rgba and
            node.screenBox.x == 11.0 and node.screenBox.y == 41.0 and
            node.screenBox.w == 116.0 and node.screenBox.h == 20.0:
          selectedRowFound = true

        if node.fill.kind == flColor and node.fill.color == hoverFill.rgba and
            node.screenBox.x == 11.0 and node.screenBox.y == 61.0 and
            node.screenBox.w == 116.0 and node.screenBox.h == 20.0:
          highlightedRowFound = true

        if node.stroke.fill.kind == flColor and node.stroke.fill.color == focusColor.rgba:
          focusRingFound = true
          check node.stroke.weight == 3.0
          check node.screenBox.x == 9.0
          check node.screenBox.y == 19.0
          check node.screenBox.w == 132.0
          check node.screenBox.h == 70.0
      of nkText:
        if node.renderedText() == "Two" and node.textLayout.spanColors.len > 0 and
            node.textLayout.spanColors[0].kind == flColor and
            node.textLayout.spanColors[0].color == selectedText.rgba:
          selectedTextFound = true
          check node.screenBox.x == 16.0
          check node.screenBox.y == 41.0
          check node.screenBox.w == 106.0
          check node.screenBox.h == 20.0
      else:
        discard

    check listBoxFound
    check selectedRowFound
    check highlightedRowFound
    check selectedTextFound
    check focusRingFound

  test "buildRenders draws focused text field selection and caret":
    let
      root = newView(frame = initRect(0, 0, 180, 80))
      field = newTextField("Field", frame = initRect(10, 20, 120, 30))

    root.addSubview(field)
    discard field.becomeFirstResponder()
    field.setSelectedRange(initTextRange(1, 2))

    let selectionRenders = buildRenders(root)
    var selectionFound = false
    for node in selectionRenders[DefaultDrawLevel].nodes:
      if node.kind == nkText and NfSelectText in node.flags and node.fill.kind == flColor and
          node.fill.color == initColor(0.24, 0.56, 1.0, 0.34).rgba and
          node.selectionRange.a == 1'i16 and node.selectionRange.b == 2'i16:
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
      root = newView(frame = initRect(0, 0, 140, 80))
      button = newButton("Button", frame = initRect(10, 20, 80, 24))

    let activeFill = initColor(0.8, 0.2, 0.1, 1.0)
    var theme = initTheme()
    theme[srButton, StyleFill] = initColor(0.1, 0.1, 0.1, 1.0)
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

  test "buildRenders draws focus visible control rings":
    let
      root = newView(frame = initRect(0, 0, 140, 80))
      button = newButton("Button", frame = initRect(10, 20, 80, 24))
      focusColor = initColor(0.24, 0.48, 0.92, 0.58)

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
      root = newView(frame = initRect(0, 0, 220, 110))
      checkbox = newCheckBox("Check", frame = initRect(10, 20, 120, 24))
      radio = newRadioButton("Radio", frame = initRect(10, 56, 120, 24))

    let
      selectedFill = initColor(0.23, 0.45, 0.67, 1.0)
      markFill = initColor(0.91, 0.82, 0.13, 1.0)

    var theme = initTheme()
    for role in [srCheckBox, srRadioButton]:
      theme[role, {ssSelected}, StyleFill] = selectedFill
      theme[role, {ssSelected}, StyleMarkColor] = markFill
      theme[role, StyleChrome] = styleKeyword(DefaultChromeName)
      theme[role, StyleIndicatorSize] = 12.0
      theme[role, StyleCornerRadius] = if role == srRadioButton: 6.0 else: 3.0
      theme[role, StyleIndicatorSpacing] = 5.0
      theme[role, StyleTextInsets] = initEdgeInsets(0.0, 3.0)

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
    check checkmarkTextCount == 2
    check radioIndicatorFound

  test "buildRenders uses effective appearance from view hierarchy":
    let
      root = newView(frame = initRect(0, 0, 140, 80))
      button = newButton("Button", frame = initRect(10, 20, 80, 24))
      rootFill = initColor(0.2, 0.3, 0.4, 1.0)
      buttonFill = initColor(0.7, 0.1, 0.2, 1.0)

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
      root = newView(frame = initRect(0, 0, 200, 160))
      child = newView(frame = initRect(20, 30, 80, 50))

    root.addSubview(child)
    root.setNeedsDisplay(false)
    child.setNeedsDisplay(false)
    child.setNeedsDisplayInRect(initRect(5, 6, 10, 11))

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
      root = newView(frame = initRect(0, 0, 120, 90))
      custom = newCustomDrawView(initRect(10, 12, 50, 30))

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
    theme[srView, StyleFill] = initColor(0.1, 0.2, 0.3, 1.0)
    let themedRenders = buildRenders(root, initAppearance(theme))
    check themedRenders != invalidatedRenders
    check customDrawCount == 3

  test "buildRenders does not clip view subtrees by default":
    let
      root = newView(frame = initRect(0, 0, 100, 80))
      child = newView(frame = initRect(90, 90, 50, 40))

    root.setBounds(initRect(10, 20, 100, 80))
    root.addSubview(child)

    let renders = buildRenders(root)
    let list = renders[DefaultDrawLevel]
    let rootIdx = list.rootIds[0]

    check list.nodes[int(rootIdx)].screenBox.x == 0.0
    check list.nodes[int(rootIdx)].screenBox.y == 0.0
    check list.nodes[int(rootIdx)].screenBox.w == 100.0
    check list.nodes[int(rootIdx)].screenBox.h == 80.0
    check NfClipContent notin list.nodes[int(rootIdx)].flags

    var transformIdx = (-1).FigIdx
    for idx in childIndex(list.nodes, rootIdx):
      if list.nodes[int(idx)].kind == nkTransform:
        transformIdx = idx

    check transformIdx != (-1).FigIdx
    check list.nodes[int(transformIdx)].transform.translation.x == -10.0
    check list.nodes[int(transformIdx)].transform.translation.y == -20.0

    var childIdx = (-1).FigIdx
    for idx in childIndex(list.nodes, transformIdx):
      if list.nodes[int(idx)].kind == nkRectangle:
        childIdx = idx

    check childIdx != (-1).FigIdx
    check list.nodes[int(childIdx)].parent == transformIdx
    check list.nodes[int(childIdx)].screenBox.x == 90.0
    check list.nodes[int(childIdx)].screenBox.y == 90.0
    check list.nodes[int(childIdx)].screenBox.w == 50.0
    check list.nodes[int(childIdx)].screenBox.h == 40.0
    check NfClipContent notin list.nodes[int(childIdx)].flags

  test "buildRenders adds FigDraw clipping when views clip to bounds":
    let
      root = newView(frame = initRect(0, 0, 100, 80))
      child = newView(frame = initRect(90, 90, 50, 40))

    root.setBounds(initRect(10, 20, 100, 80))
    root.setClipsToBounds(true)
    child.setClipsToBounds(true)
    root.addSubview(child)

    let renders = buildRenders(root)
    let list = renders[DefaultDrawLevel]
    let rootIdx = list.rootIds[0]

    check NfClipContent in list.nodes[int(rootIdx)].flags

    var transformIdx = (-1).FigIdx
    for idx in childIndex(list.nodes, rootIdx):
      if list.nodes[int(idx)].kind == nkTransform:
        transformIdx = idx

    check transformIdx != (-1).FigIdx

    var childIdx = (-1).FigIdx
    for idx in childIndex(list.nodes, transformIdx):
      if list.nodes[int(idx)].kind == nkRectangle:
        childIdx = idx

    check childIdx != (-1).FigIdx
    check NfClipContent in list.nodes[int(childIdx)].flags

  test "buildRenders calls selector-backed custom drawing":
    let
      root = newView(frame = initRect(0, 0, 100, 80))
      custom = newCustomDrawView(initRect(10, 20, 50, 40))

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
    for idx in childIndex(list.nodes, customRoot):
      let node = list.nodes[int(idx)]
      if node.kind == nkRectangle and node.screenBox.x == 14.0 and
          node.screenBox.y == 25.0 and node.screenBox.w == 20.0 and
          node.screenBox.h == 10.0:
        customRectFound = true
      if node.kind == nkText and node.screenBox.x == 14.0 and node.screenBox.y == 25.0 and
          node.screenBox.w == 20.0 and node.screenBox.h == 10.0:
        customTextFound = true

    check customRectFound
    check customTextFound
