import std/[os, strutils, tables, tempfiles, unittest]
import figdraw except CornerRadii
import merenda/nimkit
import ./fixtures/[rendergeometry, widgetflows]

proc cleanTheme(source: string, base: Theme = initTheme()): Theme =
  let parsed = parseCssTheme(source, base)
  doAssert parsed.diagnostics.len == 0, $parsed.diagnostics
  parsed.theme

proc textColor(theme: Theme, context = controlStyle(srButton)): Color =
  theme.resolveColor(context, StyleTextColor, color(0, 0, 0, 0))

proc glyphHeight(view: View, text: string): float32 =
  let list = buildRenders(view)[DefaultDrawLevel]
  for node in list.nodes:
    if node.kind == nkText and node.textContent() == text:
      for index in 0 ..< node.textLayout.glyphCount():
        result = max(result, node.textLayout.glyphRect(index).h)

suite "NimKit CSS themes":
  test "compound selectors lists aliases and states use existing style contexts":
    let theme = cleanTheme(
      """
      /* role names are case insensitive; class/id names are not */
      Button#apply.primary.toolbar:hover:focus { color: #123456; }
      checkbox:checked, radio:selected { color: lime; }
      label { color: blue; }
      .primary { background-color: #f08040; }
    """
    )
    check theme.textColor(
      controlStyle(
        srButton,
        {ssHovered, ssFocused},
        id = "apply",
        classes = @["primary", "toolbar"],
      )
    ) == parseHtmlColor("#123456")
    check theme.textColor(controlStyle(srCheckBox, {ssSelected})) ==
      parseHtmlColor("lime")
    check theme.textColor(controlStyle(srRadioButton, {ssSelected})) ==
      parseHtmlColor("lime")
    check theme.textColor(controlStyle(srTextField, classes = @[LabelStyleClass])) ==
      parseHtmlColor("blue")
    check theme.resolveButtonStyle(controlStyle(srButton, classes = @["primary"])).box.fill ==
      parseHtmlColor("#f08040")
    check theme.textColor(
      controlStyle(
        srButton, {ssHovered}, id = "apply", classes = @["primary", "toolbar"]
      )
    ) != parseHtmlColor("#123456")

  test "CSS importance specificity and order apply to each declaration":
    let theme = cleanTheme(
      """
      #apply { color: red; }
      .primary { color: blue !important; background: black; }
      button:hover { background: orange; }
      button.primary { background: green; }
      button { border-width: 2px !important; color: white; }
      button { border-width: 9px; color: yellow; }
    """
    )
    let style = theme.resolveButtonStyle(
      controlStyle(srButton, {ssHovered}, id = "apply", classes = @["primary"])
    )
    check style.text.color == parseHtmlColor("blue")
    check style.box.fill == parseHtmlColor("green")
    check style.box.borderWidth == 2
    check theme.textColor() == parseHtmlColor("yellow")

  test "native base specificity does not defeat CSS and appends share one cascade":
    let base = initTheme()
    let first = cleanTheme("#apply { color: red; } * { border-width: 1px; }", base)
    let later =
      cleanTheme(".primary { color: blue; } button { border-width: 3px; }", first)
    check later.textColor(controlStyle(srButton, id = "apply", classes = @["primary"])) ==
      parseHtmlColor("red")
    check later.resolveButtonStyle(controlStyle(srButton, {ssDisabled})).box.borderWidth ==
      3
    check base.resolveButtonStyle(controlStyle(srButton)) !=
      later.resolveButtonStyle(controlStyle(srButton))
    let inherited = cleanTheme("button { color: red; } * { color: blue; }")
    check inherited.textColor(controlStyle(srStepper)) == parseHtmlColor("red")
    let laterUniversal = cleanTheme("* { color: yellow; }", inherited)
    check laterUniversal.textColor(controlStyle(srStepper)) == parseHtmlColor("red")

  test "explicit native writes override only changed keys and survive appended CSS":
    let styled = cleanTheme("button { background: red; color: blue; }")
    var builder = initThemeBuilder(styled)
    builder[srButton, StyleTextColor] = parseHtmlColor("green")
    let changed = builder.finish()
    let appended =
      cleanTheme("button { background: yellow; color: orange !important; }", changed)
    check changed.resolveButtonStyle(controlStyle(srButton)).box.fill ==
      parseHtmlColor("red")
    check changed.textColor() == parseHtmlColor("green")
    check appended.resolveButtonStyle(controlStyle(srButton)).box.fill ==
      parseHtmlColor("yellow")
    check appended.textColor() == parseHtmlColor("green")
    check styled.textColor() == parseHtmlColor("blue")
    check builder[srButton, StyleTextColor].color == parseHtmlColor("green")
    check changed[srButton, StyleTextColor].color == parseHtmlColor("green")
    var appearance = initAppearance(styled)
    appearance[srButton, StyleTextColor] = parseHtmlColor("yellow")
    check appearance[srButton, StyleTextColor].color == parseHtmlColor("yellow")
    var value: StyleValue
    check appearance.theme.stylePatch(initStyleSelector(srButton)).getStyle(
      StyleFill, value
    )
    check value.color == parseHtmlColor("red")

  test "root variables resolve forward references aliases and scalar shorthand values":
    let theme = cleanTheme(
      """
      button { color: var(--alias); padding: var(--gap); border-radius: var(--radius); }
      :root { --alias: var(--accent); --gap: 7px; --radius: 11px; --accent: #369; }
    """
    )
    let style = theme.resolveButtonStyle(controlStyle(srButton))
    check style.text.color == parseHtmlColor("#369")
    check style.text.insets == insets(7)
    check style.box.cornerRadii ==
      CornerRadii(topLeft: 11, topRight: 11, bottomLeft: 11, bottomRight: 11)

  test "important root variables survive snapshots and normal roots cannot replace them":
    let first = cleanTheme(
      ":root { --accent: red !important; --accent: blue; } button { color: var(--accent); }"
    )
    let snapshot = initThemeBuilder(first).finish()
    let later = cleanTheme(":root { --accent: green; }", snapshot)
    check first.textColor() == parseHtmlColor("red")
    check later.textColor() == parseHtmlColor("red")
    check cleanTheme(":root { --accent: yellow !important; }", later).textColor() ==
      parseHtmlColor("yellow")
    var native = initThemeBuilder(later)
    native["--accent"] = parseHtmlColor("orange")
    check cleanTheme(":root { --accent: black !important; }", native.finish()).textColor() ==
      parseHtmlColor("orange")

  test "diagnostics retain distinct declarations at the same appended source location":
    let first = parseCssTheme("button { color: var(--missing); }")
    let second = parseCssTheme("button { color: var(--other); }", first.theme)
    check first.diagnostics.len == 1
    check second.diagnostics.len == 2

  test "invalid variables retain lower declarations and recover after append":
    let first =
      parseCssTheme("button { color: red; color: var(--accent); padding: var(--gap); }")
    check first.diagnostics.len == 2
    check first.theme.textColor() == parseHtmlColor("red")
    let valid = cleanTheme(":root { --accent: blue; --gap: 9px; }", first.theme)
    check valid.textColor() == parseHtmlColor("blue")
    check valid.resolveButtonStyle(controlStyle(srButton)).text.insets == insets(9)
    let wrongType = parseCssTheme(":root { --accent: 4px; --gap: red; }", valid)
    check wrongType.diagnostics.len == 2
    check wrongType.theme.textColor() == parseHtmlColor("red")
    check wrongType.theme.resolveButtonStyle(controlStyle(srButton)).text.insets ==
      initTheme().resolveButtonStyle(controlStyle(srButton)).text.insets
    let restored = cleanTheme(":root { --accent: lime; --gap: 2px; }", wrongType.theme)
    check restored.textColor() == parseHtmlColor("lime")
    check restored.resolveButtonStyle(controlStyle(srButton)).text.insets == insets(2)
    let cycle = parseCssTheme(
      ":root { --a: var(--b); --b: var(--a); } button { color: red; color: var(--a); }"
    )
    check cycle.diagnostics.len == 1
    check cycle.theme.textColor() == parseHtmlColor("red")

  test "padding radius shadows alpha colors and extension values use toolkit metrics":
    let theme = cleanTheme(
      """
      button {
        padding: 1px 2px 3px 4px;
        border-radius: 5px 6px 7px 8px;
        box-shadow: 1px -2px 3px -4px rgba(10, 20, 30, 0.5), inset 0 1px 2px #fff8;
        background: rgb(100%, 0%, 50%);
        color: #1234;
        -nimkit-minimum-size: 90px 44px;
        -nimkit-focus-ring-inset: -2px;
        -nimkit-chrome: flat-transparent;
      }
    """
    )
    let style = theme.resolveButtonStyle(controlStyle(srButton))
    check style.text.insets == insets(1, 4, 3, 2)
    check style.box.cornerRadii ==
      CornerRadii(topLeft: 5, topRight: 6, bottomLeft: 8, bottomRight: 7)
    check style.box.shadows.len == 2
    check style.box.shadows[0].spread == -4
    check style.box.shadows[0].color.a == 0.5'f32
    check style.box.shadows[1].kind == bskInset
    check style.box.fill == color(1, 0, 0.5, 1)
    check abs(style.text.color.a - 4.0'f32 / 15) < 0.0001
    check style.minSize == initSize(90, 44)
    check style.box.focusRingInset == -2
    check style.chrome == FlatTransparentChromeName

  test "uniform radius clears earlier CSS and native per-corner values":
    var builder = initThemeBuilder(initTheme())
    builder[srButton, StyleCornerRadiusTopLeft] = 99.0
    builder[srButton, StyleCornerRadiusBottomRight] = 88.0
    let theme = cleanTheme(
      "button { border-radius: 1px 2px 3px 4px; border-radius: 12px; }",
      builder.finish(),
    )
    check theme.resolveButtonStyle(controlStyle(srButton)).box.cornerRadii ==
      CornerRadii(topLeft: 12, topRight: 12, bottomLeft: 12, bottomRight: 12)

  test "font families clear configured exact faces atomically with variable validation":
    var builder = initThemeBuilder(initTheme())
    builder.setFontFace(frUI, initSystemTypeface(getCurrentDir() / "data/Ubuntu.ttf"))
    let base = builder.finish()
    let theme =
      cleanTheme("button { font-family: \"D'Angelo\"; font-style: italic; }", base)
    let text = theme.resolveButtonStyle(controlStyle(srButton)).text
    check text.fontName == "D'Angelo"
    check text.fontFace.file.path == ""
    check text.italicFontFace.file.path == ""
    check text.boldFontFace.file.path == ""
    check text.boldItalicFontFace.file.path == ""
    let invalid = parseCssTheme("button { font-family: var(--missing); }", base)
    check invalid.diagnostics.len == 1
    check invalid.theme.resolveButtonStyle(controlStyle(srButton)).text.fontFace ==
      base.resolveButtonStyle(controlStyle(srButton)).text.fontFace

  test "unsupported selectors never broaden matching and later rules recover":
    for selector in [
      "button > label", "button label", "button + label", "button[enabled]",
      "button:unknown", "button:not(.other)", "button, :root", "button,",
    ]:
      let parsed = parseCssTheme(
        selector & " { color: red; --global: blue; } button { border-width: 3px; }"
      )
      check parsed.diagnostics.len > 0
      check parsed.theme.textColor() == initTheme().textColor()
      check parsed.theme.resolveButtonStyle(controlStyle(srButton)).box.borderWidth == 3
      check parsed.theme.colorToken("--global", color(0, 0, 0, 0)) == color(0, 0, 0, 0)
    let atRules = parseCssTheme(
      "@import \"unused.css\"; @media print { button { color: red; } } button { color: blue; }"
    )
    check atRules.diagnostics.len == 2
    check atRules.theme.textColor() == parseHtmlColor("blue")

  test "invalid values diagnose their source and preserve usable declarations":
    let parsed = parseCssTheme(
      "\nbutton {\n  color: red;\n  padding: -1px;\n  font-size: 1em;\n  border-width: 1e999px;\n  margin: 8px;\n  color: rgb(bad);\n}"
    )
    check parsed.diagnostics.len == 5
    check parsed.diagnostics[0].line == 4
    check parsed.diagnostics[0].column == 3
    check parsed.theme.textColor() == parseHtmlColor("red")

  test "invalid separators and empty names preserve lower valid declarations":
    let parsed = parseCssTheme(
      "button { color: red; color: rgb(,1,,2,3,); font-family: \"\"; -nimkit-chrome: \"\"; }"
    )
    check parsed.diagnostics.len == 3
    check parsed.theme.textColor() == parseHtmlColor("red")

  test "malformed tokenizer inputs terminate with diagnostics":
    for source in [
      "button[foo] { color: red; }", "button { color: red ! bogus; }",
      "button\\bad { color: red; }", "button\0 { color: red; }",
      "button { font-family: \"unclosed; }", "/* unclosed",
      "button { padding: calc(nested(2px)); }", "button {", "}", "{ color: red; }",
    ]:
      checkpoint(source.escape())
      check parseCssTheme(source).diagnostics.len > 0
    check cleanTheme("button { font-family: \"D'Angelo\"; }")
    .resolveButtonStyle(controlStyle(srButton)).text.fontName == "D'Angelo"

  test "empty CSS preserves generation and snapshots do not expose cascade storage":
    let base = initTheme()
    check parseCssTheme("/* empty */", base).theme.generation == base.generation
    let theme = cleanTheme(".primary { color: red !important; }")
    var rules = theme.rules
    for rule in rules.mitems:
      if rule.origin == sroCss:
        rule.important = false
        rule.patch[StyleTextColor] = parseHtmlColor("blue")
        rule.selector.classes[0] = "changed"
    check theme.textColor(controlStyle(srButton, classes = @["primary"])) ==
      parseHtmlColor("red")
    check initThemeBuilder(theme).finish().generation == theme.generation

  test "file loading keeps CSS diagnostics and reports filesystem errors":
    let (file, path) = createTempFile("nimkit-css-", ".css")
    defer:
      removeFile(path)
    file.write("button { color: #123456; }")
    file.close()
    let parsed = loadCssTheme(path)
    check parsed.diagnostics.len == 0
    check parsed.theme.textColor() == parseHtmlColor("#123456")
    expect IOError:
      discard loadCssTheme(path & ".missing")

  test "ordinary child backgrounds respect CSS identity alpha and appearance scope":
    let
      root = newView(frame = rect(0, 0, 200, 100))
      styled = newView(frame = rect(0, 0, 50, 50))
      plain = newView(frame = rect(60, 0, 50, 50))
    styled.styleClasses = @["panel"]
    styled.alphaValue = 0.5
    root.addSubview(styled)
    root.addSubview(plain)
    root.appearance = initAppearance(cleanTheme(".panel { background: red; }"))
    let list = buildRenders(root)[DefaultDrawLevel]
    var found = false
    for node in list.nodes:
      if node.kind == nkRectangle and node.fill == fill(color(1, 0, 0, 0.5)):
        found = true
    check found
    check plain.effectiveAppearance().theme.generation ==
      root.effectiveAppearance().theme.generation
    styled.appearance = initAppearance()
    check styled.effectiveAppearance().theme.generation !=
      root.effectiveAppearance().theme.generation

  test "rounded styled controls own their face without a square CSS shell":
    let theme = cleanTheme(
      ".primary { background: red; border-radius: 12px; -nimkit-chrome: flat-transparent; }"
    )
    for asRoot in [false, true]:
      let root = newView(frame = rect(0, 0, 200, 100))
      let button = newButton("Rounded", frame = rect(0, 0, 140, 60))
      button.addStyleClass("primary")
      root.addSubview(button)
      root.appearance = initAppearance(theme)
      button.appearance = initAppearance(theme)
      let list = buildRenders(
        if asRoot:
          View(button)
        else:
          root
      )[DefaultDrawLevel]
      var colored = 0
      for node in list.nodes:
        if node.kind == nkRectangle and node.fill == fill(parseHtmlColor("red")):
          inc colored
          for radius in node.corners:
            check radius > 0
      check colored == 1

  test "outward focus inset is a CSS state-dependent intrinsic metric":
    let root = newView(frame = rect(0, 0, 300, 100))
    let button = newButton("Focus inset", frame = rect(0, 0, 200, 70))
    root.addSubview(button)
    root.appearance = initAppearance(
      cleanTheme(
        "button { -nimkit-chrome: flat-transparent; } button:hover { -nimkit-focus-ring-inset: -20px; }"
      )
    )
    let original = button.intrinsicContentSize()
    root.needsLayout = false
    button.hovered = true
    check root.needsLayout
    check button.intrinsicContentSize().width > original.width

  test "hover active pressed focus and disabled metrics agree with drawing immediately":
    let
      root = newView(frame = rect(0, 0, 600, 200))
      button = newButton("Metrics", frame = rect(0, 0, 400, 120))
      theme = cleanTheme(
        """
        button { font-size: 12px; padding: 1px; -nimkit-chrome: flat-transparent; }
        button:hover { font-size: 28px; padding: 12px; }
        button:active { font-size: 32px; }
        button:pressed { font-size: 36px; }
        button:focus { padding: 20px; }
        button:disabled { padding: 30px; }
      """
      )
    root.addSubview(button)
    root.appearance = initAppearance(theme)
    let baseSize = button.intrinsicContentSize()
    let baseGlyph = root.glyphHeight("Metrics")
    root.needsLayout = false
    button.needsLayout = false
    button.hovered = true
    check root.needsLayout
    check button.intrinsicContentSize().height > baseSize.height
    check root.glyphHeight("Metrics") > baseGlyph
    button.hoverProgress = 0.5
    let hoveredSize = button.intrinsicContentSize()
    let hoveredGlyph = root.glyphHeight("Metrics")
    button.hovered = false
    check button.intrinsicContentSize() == baseSize
    check root.glyphHeight("Metrics") == baseGlyph
    button.active = true
    check button.intrinsicContentSize().height > hoveredSize.height - 24
    check root.glyphHeight("Metrics") > hoveredGlyph
    button.active = false
    button.highlighted = true
    check root.glyphHeight("Metrics") > hoveredGlyph
    button.highlighted = false
    root.needsLayout = false
    button.setFirstResponderFocusState(true, true)
    check root.needsLayout
    check button.intrinsicContentSize().height > baseSize.height
    button.setFirstResponderFocusState(false, false)
    root.needsLayout = false
    button.enabled = false
    check root.needsLayout
    check button.intrinsicContentSize().height > baseSize.height

  test "replacing CSS restores metrics while fields and button actions remain usable":
    let
      window = newWindow("CSS workflow", frame = rect(0, 0, 420, 260))
      form = newStackView(laVertical)
      field = newTextField()
      button = newButton("Apply")
      action = actionSelector("applyCssWorkflow")
    defer:
      window.close()
    var actions = 0
    let target = newActionTarget(
      action,
      proc(sender: DynamicAgent) =
        inc actions
      ,
    )
    button.target = target
    button.action = action
    form.addArrangedSubview(field, button)
    window.setContentView(form)
    let original = button.intrinsicContentSize()
    window.setAppearance(
      initAppearance(
        cleanTheme(
          "button { font-size: 30px; padding: 10px; } text-field { font-size: 20px; }"
        )
      )
    )
    form.layoutSubtreeIfNeeded()
    check button.intrinsicContentSize().width > original.width
    require window.clickView(field)
    require window.dispatchTextInput("Input survives")
    require window.clickView(button)
    check actions == 1
    window.setAppearance(initAppearance(parseCssTheme("").theme))
    form.layoutSubtreeIfNeeded()
    check button.intrinsicContentSize() == original
    check field.text == "Input survives"
    check "Input survives" in buildRenders(form)[DefaultDrawLevel].renderedText()
