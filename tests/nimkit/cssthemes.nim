import std/[os, strutils, tempfiles, unittest]
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
  test "property casing is normalized while custom properties stay case sensitive":
    let base = initThemeBuilder().finish()
    for property in [
      "-nimkit-column-width", "-nimkit-column-min-width", "-nimkit-column-max-width"
    ]:
      for spelling in [
        property, property.toUpperAscii(), property.replace("nimkit", "NimKit")
      ]:
        let parsed = parseCssTheme("table-view { " & spelling & ": 211px; }", base)
        checkpoint(spelling)
        check parsed.diagnostics.len == 1
        check parsed.theme.rules.len == 0
    let theme = cleanTheme(
      """
      :root { --Accent: red; --accent: blue; }
      button { BaCkGrOuNd: var(--Accent); CoLoR: var(--accent); BoRdEr-WiDtH: 3px; }
    """,
      base,
    )
    let style = theme.resolveButtonStyle(controlStyle(srButton))
    check style.box.fill == parseHtmlColor("red")
    check style.text.color == parseHtmlColor("blue")
    check style.box.borderWidth == 3

  test "CSS variables retain keyword meaning and units at their destination":
    let theme = cleanTheme(
      """
      :root { --chrome: aqua; --family: red; --slant: ObLiQuE; --offset: -2px; }
      button {
        -nimkit-chrome: var(--chrome);
        font-family: var(--family);
        font-style: var(--slant);
        -nimkit-focus-ring-inset: var(--offset);
      }
    """
    )
    let style = theme.resolveButtonStyle(controlStyle(srButton))
    check style.chrome == "aqua"
    check style.text.fontName == "red"
    check style.text.fontSlant == fsOblique
    check style.box.focusRingInset == -2
    check theme.lengthToken("--offset", 0) == -2
    check theme.styleValue("--chrome", styleKeyword("")).keyword == "aqua"
    check theme.colorToken("--family", color(0, 0, 0, 0)) == parseHtmlColor("red")
    for property in [
      "-nimkit-width-factor", "-nimkit-knob-size-factor", "-nimkit-knob-value-tint"
    ]:
      let literal =
        parseCssTheme("switch { " & property & ": 0.5; " & property & ": 2px; }")
      let variable = parseCssTheme(
        ":root { --factor: 2px; } switch { " & property & ": 0.5; " & property &
          ": var(--factor); }"
      )
      checkpoint(property)
      check literal.diagnostics.len == 1
      check variable.diagnostics.len == 1
      check literal.theme.resolveSwitchButtonStyle(controlStyle(srSwitch)) ==
        variable.theme.resolveSwitchButtonStyle(controlStyle(srSwitch))
    let percent = cleanTheme(":root { --width: 25%; } view { width: var(--width); }")
    let constraint =
      percent.resolveLayoutConstraints(controlStyle(srView), StyleLayoutWidth)[0]
    check constraint.multiplier == 0.25
    check constraint.target == sltParent

  test "CSS aliases preserve native typed resources and recompile after native edits":
    let face = initSystemTypeface(getCurrentDir() / "data/Ubuntu.ttf")
    let shade = color(0.12345, 0.25, 0.6789, 0.5)
    var builder = initThemeBuilder(initTheme())
    builder.setFontFace(frUI, face)
    builder["native.chrome"] = styleKeyword("aqua")
    builder["native.scale"] = 0.75
    builder["native.shade"] = shade
    let theme = cleanTheme(
      """
      :root {
        --face: var(--font-ui-face);
        --chrome: var(--native-chrome);
        --scale: var(--native-scale);
        --shade: var(--native-shade);
      }
      button { -nimkit-font-face: var(--face); -nimkit-chrome: var(--chrome); color: var(--shade); }
      switch { -nimkit-width-factor: var(--scale); }
    """,
      builder.finish(),
    )
    let style = theme.resolveButtonStyle(controlStyle(srButton))
    check style.text.fontFace == face
    check style.chrome == "aqua"
    check style.text.color == shade
    check theme.styleValue("--face", styleFontFace(SystemTypeface())).fontFace == face
    check theme.lengthToken("--scale", 0) == 0.75
    check theme.colorToken("--shade", color(0, 0, 0, 0)) == shade
    var changed = initThemeBuilder(theme)
    changed["native.shade"] = parseHtmlColor("orange")
    changed[srButton, StyleTextColor] = styleToken("--shade")
    check changed.finish().textColor() == parseHtmlColor("orange")
    check theme.textColor() == shade

  test "expanded selectors report each failed declaration once and recover atomically":
    let first = parseCssTheme(
      """
      button, .primary, * { padding: var(--gap); border-radius: var(--radius); }
    """
    )
    check first.diagnostics.len == 2
    check first.diagnostics[0].line == 1
    let fixed = cleanTheme(
      ":root { --gap: 1px 2px 3px 4px; --radius: 5px 6px 7px 8px; }", first.theme
    )
    let style = fixed.resolveButtonStyle(controlStyle(srButton, classes = @["primary"]))
    check style.text.insets == insets(1, 4, 3, 2)
    check style.box.cornerRadii ==
      CornerRadii(topLeft: 5, topRight: 6, bottomRight: 7, bottomLeft: 8)
    let again = parseCssTheme("button { padding: var(--another); }", first.theme)
    check again.diagnostics.len == 3

  test "application CSS overrides every bundled theme including specific state defaults":
    for name in [
      "aqua", "banner", "macos", "macos-dark", "darkbsd", "nebula", "peachy",
      "synthwave83",
    ]:
      checkpoint(name)
      let base = initThemeByName(name)
      let themed = cleanTheme("* { color: #123456; background: #654321; }", base)
      for states in [{}, {ssDisabled}, {ssSelected}, {ssHovered, ssAccent}]:
        let style = themed.resolveButtonStyle(controlStyle(srButton, states))
        check style.text.color == parseHtmlColor("#123456")
        check style.box.fill == parseHtmlColor("#654321")
      check themed.resolveFill(
        controlStyle(srView), fill(color(0, 0, 0, 0)), StyleBackgroundFill
      ) == fill(parseHtmlColor("#654321"))
      check base.resolveButtonStyle(controlStyle(srButton)).text.color !=
        parseHtmlColor("#123456")

  test "programmatic edits have the same precedence before and after CSS is loaded":
    var defaults = initThemeBuilder()
    defaults[initStyleSelector(srButton, id = "apply"), StyleTextColor] =
      parseHtmlColor("red")
    let base = defaults.finish()
    check cleanTheme("* { color: blue; }", base).textColor(
      controlStyle(srButton, id = "apply")
    ) == parseHtmlColor("blue")
    var edits = initThemeBuilder(base)
    edits[srButton, StyleTextColor] = parseHtmlColor("green")
    let changed = cleanTheme("* { color: blue !important; }", edits.finish())
    check changed.textColor(controlStyle(srButton, id = "apply")) ==
      parseHtmlColor("green")
    var appearance = initAppearance(changed)
    appearance[srButton, StyleTextColor] = parseHtmlColor("orange")
    check cleanTheme("button { color: red !important; }", appearance.theme).textColor() ==
      parseHtmlColor("orange")

  test "CSS and native selectors share class state specificity and direct role precedence":
    var defaults = initThemeBuilder()
    defaults[initStyleSelector(srButton, classes = @["primary"]), StyleTextColor] =
      parseHtmlColor("red")
    defaults[srButton, {ssHovered}, StyleTextColor] = parseHtmlColor("blue")
    let context = controlStyle(srButton, {ssHovered}, classes = @["primary"])
    check defaults.finish().textColor(context) ==
      cleanTheme(
        "button.primary { color: red; } button:hover { color: blue; }",
        base = initThemeBuilder().finish(),
      )
      .textColor(context)
    let roles =
      cleanTheme("menu-bar-item { border-radius: 4px; } tab { border-radius: 7px; }")
    check roles.resolveButtonStyle(controlStyle(srMenuBarItem)).box.cornerRadius == 4

  test "legacy token names and CSS custom properties refer to the same values":
    let original =
      cleanTheme(":root { --accent: red; } button { background: var(--accent); }")
    var defaults = initThemeBuilder(original, sroTheme)
    defaults["accent"] = parseHtmlColor("blue")
    check defaults.finish().resolveButtonStyle(controlStyle(srButton)).box.fill ==
      parseHtmlColor("red")
    var builder = initThemeBuilder(original)
    builder["accent"] = parseHtmlColor("orange")
    builder["button.fill"] = parseHtmlColor("lime")
    let changed = cleanTheme(":root { --accent: blue !important; }", builder.finish())
    check changed.colorToken("accent", color(0, 0, 0, 0)) == parseHtmlColor("orange")
    check changed.colorToken("--accent", color(0, 0, 0, 0)) == parseHtmlColor("orange")
    check changed.colorToken("--button-fill", color(0, 0, 0, 0)) ==
      parseHtmlColor("lime")
    check changed.resolveButtonStyle(controlStyle(srButton)).box.fill ==
      parseHtmlColor("orange")
    check original.resolveButtonStyle(controlStyle(srButton)).box.fill ==
      parseHtmlColor("red")

  test "composite variables project padding radii sizes and shadows and recompile on edits":
    let source =
      """
      :root {
        --gap: 2px 4px 6px 8px;
        --radius: 1px 2px 3px 4px;
        --minimum: 80px 30px;
        --uniform: 12px;
        --empty-shadow: none;
        --shade: rgba(0, 0, 0, 0.25);
        --kind: inset;
        --shadow: var(--kind) 0 1px 3px var(--shade);
      }
      button {
        padding: var(--gap);
        border-radius: var(--radius);
        -nimkit-minimum-size: var(--minimum);
        box-shadow: var(--shadow);
      }
    """
    let theme = cleanTheme(source)
    let style = theme.resolveButtonStyle(controlStyle(srButton))
    check style.text.insets == insets(2, 8, 6, 4)
    check style.box.cornerRadii ==
      CornerRadii(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4)
    check style.minSize == initSize(80, 30)
    require style.box.shadows.len == 1
    check style.box.shadows[0].kind == bskInset
    check style.box.shadows[0].color.a == 0.25
    check theme.insetsToken("--gap", insets(0)) == style.text.insets
    check theme.sizeToken("--minimum", initSize(0, 0)) == style.minSize
    check theme.sizeToken("--uniform", initSize(0, 0)) == initSize(12, 12)
    check theme.insetsToken("--uniform", insets(0)) == insets(12)
    check theme.shadowsToken("--empty-shadow", @[dropShadow(color(0, 0, 0, 1))]).len == 0
    check theme.shadowsToken("--shadow", @[]) == style.box.shadows
    var builder = initThemeBuilder(theme)
    builder["gap"] = insets(9)
    builder["shade"] = parseHtmlColor("red")
    builder[srButton, StyleBoxShadows] = styleToken("shadow")
    let edited = builder.finish().resolveButtonStyle(controlStyle(srButton))
    check edited.text.insets == insets(9)
    require edited.box.shadows.len == 1
    check edited.box.shadows[0].color == parseHtmlColor("red")
    check theme.resolveButtonStyle(controlStyle(srButton)) == style

  test "bounded linear gradients preserve renderer axes stops and variable colors":
    let theme = cleanTheme(
      """
      :root {
        --a: red; --b: lime; --c: blue;
        --surface: linear-gradient(to right, var(--a), var(--b) 40%, var(--c));
      }
      button { background: var(--surface); }
    """
    )
    let surface = theme.resolveButtonStyle(controlStyle(srButton)).box.fill
    check surface ==
      linear(
        parseHtmlColor("red"),
        parseHtmlColor("lime"),
        parseHtmlColor("blue"),
        fgaX,
        102'u8,
      )
    check cleanTheme("button { background: linear-gradient(to top, red, blue); }")
    .resolveButtonStyle(controlStyle(srButton)).box.fill ==
      linear(parseHtmlColor("blue"), parseHtmlColor("red"), fgaY)
    check cleanTheme("button { background: linear-gradient(45deg, red, blue); }")
    .resolveButtonStyle(controlStyle(srButton)).box.fill ==
      linear(parseHtmlColor("red"), parseHtmlColor("blue"), fgaDiagBLTR)
    for gradient in [
      "linear-gradient(12deg, red, blue)", "linear-gradient(red, blue, lime, black)",
      "linear-gradient(red 20%, blue)", "linear-gradient(red, blue 80%)",
      "linear-gradient(red, lime 101%, blue)",
    ]:
      let parsed =
        parseCssTheme("button { background: red; background: " & gradient & "; }")
      check parsed.diagnostics.len == 1
      check parsed.theme.resolveButtonStyle(controlStyle(srButton)).box.fill ==
        parseHtmlColor("red")

  test "composite variable failures preserve complete lower declarations and recover":
    let first = parseCssTheme(
      """
      button { padding: 3px; padding: 1px var(--missing); }
      :root { --loop: 1px var(--loop); }
      button { border-radius: 6px; border-radius: var(--loop); }
    """
    )
    check first.diagnostics.len == 2
    let style = first.theme.resolveButtonStyle(controlStyle(srButton))
    check style.text.insets == insets(3)
    check style.box.cornerRadii ==
      CornerRadii(topLeft: 6, topRight: 6, bottomLeft: 6, bottomRight: 6)
    let recovered =
      cleanTheme(":root { --missing: 5px; --loop: 2px 4px; }", first.theme)
    let resolved = recovered.resolveButtonStyle(controlStyle(srButton))
    check resolved.text.insets == insets(1, 5, 1, 5)
    check resolved.box.cornerRadii ==
      CornerRadii(topLeft: 2, topRight: 4, bottomLeft: 4, bottomRight: 2)
    var growing = ":root { --a0: 1px; "
    for i in 1 .. 15:
      growing.add "--a" & $i & ": var(--a" & $(i - 1) & ") var(--a" & $(i - 1) & "); "
    growing.add "} button { padding: 3px; padding: var(--a15); }"
    let bounded = parseCssTheme(growing)
    check bounded.diagnostics.len == 1
    check bounded.theme.resolveButtonStyle(controlStyle(srButton)).text.insets ==
      insets(3)
    var chain = ":root { --end: blue; --a15: linear-gradient(red, var(--end)); "
    for i in 0 .. 14:
      chain.add "--a" & $i & ": var(--a" & $(i + 1) & "); "
    chain.add "} button { background: red; background: var(--a0); }"
    let deep = parseCssTheme(chain)
    check deep.diagnostics.len == 1
    check deep.theme.resolveButtonStyle(controlStyle(srButton)).box.fill ==
      parseHtmlColor("red")

  test "programmatic uniform radii replace CSS corners with later longhand control":
    let base = cleanTheme("button { border-radius: 1px 2px 3px 4px; }")
    var appearance = initAppearance(base)
    appearance[srButton, StyleCornerRadius] = 9.0
    appearance[srButton, StyleCornerRadiusBottomRight] = 12.0
    check appearance.resolveButtonStyle(controlStyle(srButton)).box.cornerRadii ==
      CornerRadii(topLeft: 9, topRight: 9, bottomLeft: 9, bottomRight: 12)
    check base.resolveButtonStyle(controlStyle(srButton)).box.cornerRadii ==
      CornerRadii(topLeft: 1, topRight: 2, bottomLeft: 4, bottomRight: 3)

  test "programmatic state metrics invalidate layout and agree with rendered text":
    var builder = initThemeBuilder()
    builder[srButton, StyleChrome] = styleKeyword(FlatTransparentChromeName)
    builder[srButton, StyleFontSize] = 12.0
    builder[srButton, {ssHovered}, StyleFontSize] = 36.0
    let theme = builder.finish()
    check theme.metricsChange({ssHovered})
    let root = newView(frame = rect(0, 0, 400, 150))
    let button = newButton("Native metrics", frame = rect(0, 0, 300, 120))
    root.addSubview(button)
    root.appearance = initAppearance(theme)
    let size = button.intrinsicContentSize()
    let glyph = root.glyphHeight("Native metrics")
    root.needsLayout = false
    button.hovered = true
    check root.needsLayout
    check button.intrinsicContentSize().height > size.height
    check root.glyphHeight("Native metrics") > glyph
    button.hovered = false
    check button.intrinsicContentSize() == size

  test "bundled theme caching respects font environment changes and isolates edits":
    let existed = existsEnv(NimKitFontSizeEnv)
    let previous = getEnv(NimKitFontSizeEnv)
    defer:
      if existed:
        putEnv(NimKitFontSizeEnv, previous)
      else:
        delEnv(NimKitFontSizeEnv)
    let first = initAquaTheme()
    check initAquaTheme().generation == first.generation
    putEnv(NimKitFontSizeEnv, "19")
    if envOverrideAllowed(NimKitFontSizeEnv):
      let updated = initAquaTheme()
      check updated.resolveButtonStyle(controlStyle(srButton)).text.fontSize == 19
      check updated.generation != first.generation or
        first.resolveButtonStyle(controlStyle(srButton)).text.fontSize == 19
      var builder = initThemeBuilder(updated)
      builder[srButton, StyleFontSize] = 25.0
      check builder.finish().resolveButtonStyle(controlStyle(srButton)).text.fontSize ==
        25
      check initAquaTheme().resolveButtonStyle(controlStyle(srButton)).text.fontSize ==
        19
    else:
      check initAquaTheme().generation == first.generation
      check initAquaTheme().resolveButtonStyle(controlStyle(srButton)).text.fontSize ==
        first.resolveButtonStyle(controlStyle(srButton)).text.fontSize

  test "bundled inherited styles and asymmetric toolbar corners retain their appearance":
    for name in ["macos", "macos-dark", "darkbsd"]:
      let theme = initThemeByName(name)
      check theme.resolveButtonStyle(controlStyle(srMenuBarItem)).box.cornerRadius == 4
      check theme.resolveButtonStyle(controlStyle(srDocumentTab)).minSize ==
        initSize(96, 30)
    let toolbar = initThemeByName("synthwave83").resolveButtonStyle(
        controlStyle(srButton, classes = @[ToolbarButtonStyleClass])
      )
    check toolbar.box.cornerRadii ==
      CornerRadii(topLeft: 5, topRight: 0, bottomLeft: 0, bottomRight: 12)

  test "native plain view backgrounds use style identity without CSS":
    var builder = initThemeBuilder()
    builder[initStyleSelector(srView, classes = @["panel"]), StyleFill] =
      parseHtmlColor("red")
    let root = newView(frame = rect(0, 0, 100, 100))
    let child = newView(frame = rect(10, 10, 40, 40))
    child.styleClasses = @["panel"]
    root.addSubview(child)
    let list = buildRenders(root, initAppearance(builder.finish()))[DefaultDrawLevel]
    var found = false
    for node in list.nodes:
      if node.kind == nkRectangle and node.fill == fill(parseHtmlColor("red")):
        found = true
    check found

  test "plain child backgrounds preserve gradient stops and scale alpha":
    let root = newView(frame = rect(0, 0, 100, 100))
    let child = newView(frame = rect(10, 10, 40, 40))
    child.styleClasses = @["gradient"]
    child.alphaValue = 0.5
    root.addSubview(child)
    root.appearance = initAppearance(
      cleanTheme(
        ".gradient { background: linear-gradient(to right, red, lime 40%, blue); }"
      )
    )
    let list = buildRenders(root)[DefaultDrawLevel]
    var found = false
    for node in list.nodes:
      if node.kind == nkRectangle and node.fill.kind == flLinear3:
        found = true
        check node.fill.lin3.axis == fgaX
        check node.fill.lin3.midPos == 102
        check node.fill.lin3.start.r == 255
        check node.fill.lin3.mid.g == 255
        check node.fill.lin3.stop.b == 255
        check node.fill.lin3.start.a == 128
        check node.fill.lin3.mid.a == 128
        check node.fill.lin3.stop.a == 128
    check found

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
    let first = parseCssTheme(
      "button { color: red; color: var(--test-accent); padding: var(--gap); }"
    )
    check first.diagnostics.len == 2
    check first.theme.textColor() == parseHtmlColor("red")
    let valid = cleanTheme(":root { --test-accent: blue; --gap: 9px; }", first.theme)
    check valid.textColor() == parseHtmlColor("blue")
    check valid.resolveButtonStyle(controlStyle(srButton)).text.insets == insets(9)
    let wrongType = parseCssTheme(":root { --test-accent: 4px; --gap: red; }", valid)
    check wrongType.diagnostics.len == 2
    check wrongType.theme.textColor() == parseHtmlColor("red")
    check wrongType.theme.resolveButtonStyle(controlStyle(srButton)).text.insets ==
      initTheme().resolveButtonStyle(controlStyle(srButton)).text.insets
    let restored =
      cleanTheme(":root { --test-accent: lime; --gap: 2px; }", wrongType.theme)
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

  test "uniform radius clears earlier default and CSS per-corner values":
    var builder = initThemeBuilder(initTheme(), sroTheme)
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
