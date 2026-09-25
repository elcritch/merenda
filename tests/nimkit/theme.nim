import std/[os, strutils, unittest]
import sigils/core
import figdraw

import merenda/nimkit
import ./fixtures/[rendergeometry, widgetflows]

const CustomChromeName = "custom-widget-chrome"

let CustomChromeFill = fill(color(0.42, 0.10, 0.74, 1.0))

type CustomFillChrome = ref object of Chrome

protocol CustomFillChromeProtocol of ChromeProtocol:
  method chromeFillFor(chrome: CustomFillChrome, context: ChromeContext): Fill =
    discard chrome
    discard context
    CustomChromeFill

proc newCustomFillChrome(): Chrome =
  let chrome = CustomFillChrome()
  discard chrome.withProtocol(CustomFillChromeProtocol)
  Chrome(chrome)

proc withCleanThemeEnv(body: proc() {.closure.}) =
  let
    existed = existsEnv(NimKitThemeEnv)
    value = getEnv(NimKitThemeEnv)
  delEnv(NimKitThemeEnv)
  try:
    body()
  finally:
    if existed:
      putEnv(NimKitThemeEnv, value)
    else:
      delEnv(NimKitThemeEnv)

suite "nimkit theme":
  test "default appearance and named default use the same theme":
    withCleanThemeEnv(
      proc() =
        let context = controlStyle(srButton)
        let expected = initTheme().resolveButtonStyle(context)
        check initAppearance().resolveButtonStyle(context) == expected
        check initThemeByName("default").resolveButtonStyle(context) == expected
    )

  test "NimKit theme env obeys override ignore flag":
    withCleanThemeEnv(
      proc() =
        putEnv(NimKitThemeEnv, "banner")
        when defined(nimkitIgnoreEnvOverrides):
          check themeNameFromEnv() == ""
        else:
          check themeNameFromEnv() == "banner"
    )

  test "edge insets shrink rectangles without negative sizes":
    check rect(10, 20, 100, 50).inset(insets(2, 4, 6, 8)) == rect(14, 22, 88, 42)
    check rect(0, 0, 10, 10).inset(insets(8)) == rect(8, 8, 0, 0)

  test "style selectors match role state id and classes":
    let context = initStyleContext(
      srButton,
      {ssFocused, ssFocusVisible},
      id = "primary",
      classes = @["default", "toolbar"],
    )

    check initStyleSelector(srButton).matches(context)
    check initStyleSelector(srButton, {ssFocused}).matches(context)
    check initStyleSelector(srButton, id = "primary").matches(context)
    check initStyleSelector(srButton, classes = @["toolbar"]).matches(context)
    check not initStyleSelector(srTextField).matches(context)
    check not initStyleSelector(srButton, {ssDisabled}).matches(context)
    check not initStyleSelector(srButton, id = "secondary").matches(context)

  test "style rule specificity beats insertion order":
    var builder = initThemeBuilder(initTheme())
    let
      fallback = color(0.0, 0.0, 0.0, 1.0)
      broadText = color(0.12, 0.13, 0.14, 1.0)
      highlightedText = color(0.82, 0.40, 0.12, 1.0)
      highlightedContext = controlStyle(srButton, {ssHighlighted})

    builder[srButton, {ssHighlighted}, StyleTextColor] = highlightedText
    builder[srButton, StyleTextColor] = broadText
    let theme = builder.finish()

    check theme.resolveColor(controlStyle(srButton), StyleTextColor, fallback) ==
      broadText
    check theme.resolveColor(highlightedContext, StyleTextColor, fallback) ==
      highlightedText

  test "style rules prefer more matching states over later weaker states":
    var builder = initThemeBuilder(initTheme())
    let
      fallback = color(0.0, 0.0, 0.0, 1.0)
      pressedText = color(0.16, 0.38, 0.82, 1.0)
      highlightedPressedText = color(0.90, 0.24, 0.74, 1.0)
      context = controlStyle(srButton, {ssHighlighted, ssPressed})

    builder[srButton, {ssHighlighted, ssPressed}, StyleTextColor] =
      highlightedPressedText
    builder[srButton, {ssPressed}, StyleTextColor] = pressedText
    let theme = builder.finish()

    check theme.resolveColor(context, StyleTextColor, fallback) == highlightedPressedText

  test "style rules keep last-write-wins for equal specificity":
    var builder = initThemeBuilder(initTheme())
    let
      fallback = color(0.0, 0.0, 0.0, 1.0)
      firstText = color(0.18, 0.24, 0.30, 1.0)
      secondText = color(0.44, 0.52, 0.62, 1.0)
      context = controlStyle(srButton, {ssHighlighted, ssPressed})

    builder[srButton, {ssHighlighted}, StyleTextColor] = firstText
    builder[srButton, {ssPressed}, StyleTextColor] = secondText
    let theme = builder.finish()

    check theme.resolveColor(context, StyleTextColor, fallback) == secondText

  test "style context stores role and control states":
    let context = controlStyle(
      srButton,
      {
        ssDisabled, ssHighlighted, ssHovered, ssActive, ssFocused, ssFocusVisible,
        ssFocusWithin, ssSelected, ssOpen, ssAlternating, ssPressed, ssAccent,
      },
      id = "primary",
      classes = @["default", "toolbar"],
    )

    check context.role == srButton
    check context.id == "primary"
    check context.classes == @["default", "toolbar"]
    check context.states == {
      ssDisabled, ssHighlighted, ssHovered, ssActive, ssFocused, ssFocusVisible,
      ssFocusWithin, ssSelected, ssOpen, ssAlternating, ssPressed, ssAccent,
    }

  test "chrome delegates install by name and selectors choose per widget":
    var builder = initThemeBuilder(initAquaTheme())
    builder.installChrome(CustomChromeName, newCustomFillChrome())
    builder[initStyleSelector(srButton, id = "special"), StyleChrome] =
      styleKeyword(CustomChromeName)

    let
      theme = builder.finish()
      appearance = initAppearance(theme)
      normalContext = controlStyle(srButton)
      specialContext = controlStyle(srButton, id = "special")
      baseFill = fill(color(0.12, 0.20, 0.34, 1.0))

    check appearance.hasChrome(CustomChromeName)
    check appearance.resolveChromeName(normalContext) == AquaChromeName
    check appearance.resolveChromeName(specialContext) == CustomChromeName
    check appearance.chromeFill(
      chromeContext(CustomChromeName, crButton, cpFace, baseFill)
    ) == CustomChromeFill
    check appearance.chromeFill(
      chromeContext("missing-widget-chrome", crButton, cpFace, baseFill)
    ) == baseFill

  test "style token store resolves typed values and nested references":
    let
      parent = newStyleTokenStore()
      child = newStyleTokenStore(parent)
      accent = color(0.7, 0.2, 0.3, 1.0)
      minSize = initSize(24.0, 18.0)
      padding = insets(1, 2, 3, 4)
      shadows = @[dropShadow(color(0, 0, 0, 0.25), y = 2.0, blur = 4.0)]

    parent["accent"] = accent
    parent["space"] = 6.0
    parent["minimum.size"] = minSize
    parent["padding"] = padding
    parent["shadow"] = shadows
    child["nested.accent"] = styleToken("accent")

    var value: StyleValue
    check child.resolveToken("nested.accent", value)
    check value.kind == svColor
    check value.color == accent

    let appearance = Appearance(theme: initThemeBuilder(child).finish())
    check appearance.colorToken("nested.accent", color(0, 0, 0, 1)) == accent
    check appearance.lengthToken("space", 0.0) == 6.0
    check appearance.sizeToken("minimum.size", initSize(0, 0)) == minSize
    check appearance.insetsToken("padding", insets(0)) == padding
    check appearance.shadowsToken("shadow", @[]) == shadows
    check appearance.colorToken("missing", accent) == accent

  test "theme builder freezes independently owned snapshots":
    let
      firstAccent = color(0.18, 0.42, 0.76, 1.0)
      secondAccent = color(0.82, 0.24, 0.36, 1.0)
      fallback = color(0.0, 0.0, 0.0, 1.0)
      button = controlStyle(srButton)

    var builder = initThemeBuilder(initTheme())
    builder["snapshot.accent"] = firstAccent
    builder[srButton, StyleTextColor] = firstAccent
    let first = builder.finish()

    builder["snapshot.accent"] = secondAccent
    builder[srButton, StyleTextColor] = secondAccent
    let second = builder.finish()

    check first.generation != second.generation
    check first.colorToken("snapshot.accent", fallback) == firstAccent
    check second.colorToken("snapshot.accent", fallback) == secondAccent
    check first.resolveColor(button, StyleTextColor, fallback) == firstAccent
    check second.resolveColor(button, StyleTextColor, fallback) == secondAccent

  test "theme snapshot accessors cannot mutate frozen storage":
    let
      accent = color(0.16, 0.38, 0.72, 1.0)
      replacement = color(0.86, 0.26, 0.44, 1.0)
      fallback = color(0.0, 0.0, 0.0, 1.0)
      shadows = @[dropShadow(color(0.0, 0.0, 0.0, 0.4), blur = 5.0)]
      selector = initStyleSelector(srButton, classes = @["primary"])
      context = controlStyle(srButton, classes = @["primary"])

    var builder = initThemeBuilder(initTheme())
    builder["snapshot.accent"] = accent
    builder["snapshot.shadows"] = shadows
    builder[selector, StyleTextColor] = accent
    builder[selector, StyleBoxShadows] = shadows
    let snapshot = builder.finish()

    let tokenCopy = snapshot.tokens
    tokenCopy["snapshot.accent"] = replacement
    var tokenShadows: StyleValue
    check tokenCopy.resolveToken("snapshot.shadows", tokenShadows)
    tokenShadows.shadows[0].blur = 99.0

    let patchCopy = snapshot.stylePatch(selector)
    patchCopy[StyleTextColor] = replacement
    var patchShadows: StyleValue
    check patchCopy.getStyle(StyleBoxShadows, patchShadows)
    patchShadows.shadows[0].blur = 99.0

    var rulesCopy = snapshot.rules
    rulesCopy[^1].selector.classes[0][0] = 'x'

    check snapshot.colorToken("snapshot.accent", fallback) == accent
    check snapshot.shadowsToken("snapshot.shadows", @[]) == shadows
    check snapshot.resolveColor(context, StyleTextColor, fallback) == accent
    var frozenShadows: StyleValue
    check snapshot.stylePatch(selector).getStyle(StyleBoxShadows, frozenShadows)
    check frozenShadows.shadows == shadows

  test "unchanged snapshots retain their cache generation":
    let
      snapshot = initTheme()
      rebuilt = initThemeBuilder(snapshot).finish()
      firstAppearance = initAppearance(snapshot)
      secondAppearance = initAppearance(snapshot.clone())

    check rebuilt.generation == snapshot.generation
    check firstAppearance.sameAppearanceGeneration(secondAppearance)

  test "appearance tokens and style patches resolve into concrete styles":
    var appearance = initAppearance()
    let
      buttonFill = color(0.11, 0.22, 0.33, 1.0)
      focusRing = color(0.24, 0.42, 0.90, 0.75)
      fieldText = color(0.44, 0.55, 0.66, 1.0)
      buttonHighlight = color(0.95, 0.96, 0.97, 0.44)
      buttonShadow = color(0.04, 0.05, 0.06, 0.22)
      buttonMinimum = initSize(72.0, 32.0)
      buttonInsets = insets(2.0, 10.0)
      buttonShadows =
        @[
          dropShadow(color(0, 0, 0, 0.35), y = 2.0, blur = 5.0),
          insetShadow(color(1, 1, 1, 0.18), y = -1.0, blur = 1.0),
        ]

    var builder = initThemeBuilder(appearance.theme)
    builder["field.text.override"] = fieldText
    appearance.theme = builder.finish()
    appearance[srButton, StyleFill] = buttonFill
    appearance[srButton, StyleCornerRadius] = 9.0
    appearance[srButton, StyleFocusRingColor] = focusRing
    appearance[srButton, StyleTextInsets] = buttonInsets
    appearance[srButton, StyleTextHighlightColor] = buttonHighlight
    appearance[srButton, StyleTextShadowColor] = buttonShadow
    appearance[srButton, StyleMinimumSize] = buttonMinimum
    appearance[srButton, StyleBoxShadows] = buttonShadows
    appearance[srButton, StyleChrome] = styleKeyword(DefaultChromeName)
    appearance[srTextField, StyleTextColor] = styleToken("field.text.override")
    appearance[srTextField, StyleBorderWidth] = 4.0

    let
      buttonStyle = appearance.resolveButtonStyle(controlStyle(srButton))
      textFieldStyle = appearance.resolveTextFieldStyle(
        controlStyle(srTextField), color(0.1, 0.1, 0.1, 1.0)
      )

    check buttonStyle.box.fill == buttonFill
    check buttonStyle.box.cornerRadius == 9.0
    check buttonStyle.box.focusRingColor == focusRing
    check buttonStyle.box.shadows == buttonShadows
    check buttonStyle.text.insets == buttonInsets
    check buttonStyle.textHighlightColor == buttonHighlight
    check buttonStyle.textShadowColor == buttonShadow
    check buttonStyle.minSize == buttonMinimum
    check buttonStyle.chrome == DefaultChromeName
    check textFieldStyle.text.color == fieldText
    check textFieldStyle.box.borderWidth == 4.0
    let textPatch = appearance[srTextField, StyleTextColor]
    check textPatch.kind == svToken
    check textPatch.token == "field.text.override"

  test "appearance overrides do not mutate the base theme":
    let theme = initTheme()
    var
      firstAppearance = initAppearance(theme)
      secondAppearance = initAppearance(theme)

    let
      baseStyle = theme.resolveButtonStyle(controlStyle(srButton))
      overrideFill = color(0.67, 0.18, 0.22, 1.0)

    var builder = initThemeBuilder(firstAppearance.theme)
    builder["button.fill"] = overrideFill
    firstAppearance.theme = builder.finish()
    firstAppearance[srButton, StyleCornerRadius] = 11.0

    check firstAppearance.resolveButtonStyle(controlStyle(srButton)).box.fill ==
      overrideFill
    check firstAppearance.resolveButtonStyle(controlStyle(srButton)).box.cornerRadius ==
      11.0
    check secondAppearance.resolveButtonStyle(controlStyle(srButton)).box.fill ==
      baseStyle.box.fill
    check secondAppearance.resolveButtonStyle(controlStyle(srButton)).box.cornerRadius ==
      baseStyle.box.cornerRadius
    check theme.resolveButtonStyle(controlStyle(srButton)).box.fill == baseStyle.box.fill
    check theme.resolveButtonStyle(controlStyle(srButton)).box.cornerRadius ==
      baseStyle.box.cornerRadius

  test "built-in themes support editing and actions after switching and resizing":
    let
      window = newWindow("Theme workflow", frame = rect(0, 0, 420, 320))
      form = newStackView(laVertical)
      field = newTextField()
      toggle = newCheckBox("Keep changes")
      button = newButton("Apply changes")
      label = newLabel("Theme preview")
      action = actionSelector("applyThemePreview")
    defer:
      window.close()
    form.distribution = svdNatural
    form.spacing = 8
    form.edgeInsets = insets(12)
    form.addArrangedSubview(label, field, toggle, button)
    window.setContentView(form)
    var
      submitted: string
      actionCount = 0
    let target = newActionTarget(
      action,
      proc(sender: DynamicAgent) =
        submitted = field.text
        inc actionCount
      ,
    )
    button.target = target
    button.action = action

    for index, name in [
      "aqua", "banner", "darkbsd", "macos", "macos-dark", "nebula", "peachy",
      "synthwave83",
    ]:
      checkpoint("theme: " & name)
      window.setAppearance(initAppearance(initThemeByName(name)))
      window.frame = rect(0, 0, (420 + index * 20).float32, 320)
      field.text = ""
      form.layoutSubtreeIfNeeded()
      checkpoint("form: " & $form.frame() & " field: " & $field.frame())
      require window.clickView(field)
      let entered = "Sample " & $index
      require window.dispatchTextInput(entered)
      let previousState = toggle.state
      require window.clickView(toggle)
      check toggle.state != previousState
      require window.clickView(button)
      check submitted == entered
      check actionCount == index + 1

      let list = buildRenders(form)[DefaultDrawLevel]
      for text in [label.text, entered, toggle.title, button.title]:
        check text in list.renderedText()
      for control in [View(field), View(toggle), View(button)]:
        check control.frame().size.width > 0
        check control.frame().size.height >= control.intrinsicContentSize().height
        check control.frame().maxY <= form.bounds().maxY

  test "font overrides relayout existing controls and preserve input":
    let
      window = newWindow("Resizable theme", frame = rect(0, 0, 420, 320))
      form = newStackView(laVertical)
      field = newTextField()
      button = newButton("Apply changes")
    defer:
      window.close()
    form.distribution = svdNatural
    form.spacing = 10
    form.addArrangedSubview(field, button)
    window.setContentView(form)
    var previousTextWidth = 0.0'f32
    for fontSize in [12.0'f32, 36.0'f32]:
      var appearance = initAppearance()
      appearance[srButton, StyleFontSize] = fontSize
      appearance[srTextField, StyleFontSize] = fontSize
      window.setAppearance(appearance)
      form.layoutSubtreeIfNeeded()
      let natural = button.intrinsicContentSize()
      check natural.width > previousTextWidth
      check button.frame().size.height >= natural.height
      previousTextWidth = natural.width
      field.text = ""
      require window.clickView(field)
      require window.dispatchTextInput("Readable")
      require window.clickView(button)
      check field.text == "Readable"
      check "Readable" in buildRenders(form)[DefaultDrawLevel].renderedText()

  test "runtime theme aliases resolve to their canonical appearance":
    for names in [
      ["macos", "mac", "modern-macos"],
      ["macos-dark", "dark-macos", "modern-macos-dark"],
      ["darkbsd", "dark-bsd", "ruby-bsd"],
    ]:
      let canonical = initThemeByName(names[0])
      for name in names:
        checkpoint("theme alias: " & name)
        let theme = initThemeByName(name)
        check theme.resolveButtonStyle(controlStyle(srButton)) ==
          canonical.resolveButtonStyle(controlStyle(srButton))
        check theme.resolveTextFieldStyle(controlStyle(srTextField)) ==
          canonical.resolveTextFieldStyle(controlStyle(srTextField))
