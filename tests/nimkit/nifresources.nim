## The optional NIF demo shares the HTML demo's native resource and style paths.
import std/[os, strutils, unittest]
import merenda/nimkit
import ../../examples/nif_ui_demo
import ../../examples/private/nifmarkup

const exampleDir = currentSourcePath().parentDir.parentDir.parentDir / "examples"

suite "NimKit NIF markup demo":
  test "NIF and HTML demo markup produce identical resource bundles":
    let original = loadGuiResourceBundle(exampleDir / "html_ui_demo.html")
    let converted =
      parseGuiResourceBundle(nifGuiMarkup(readFile(exampleDir / "nif_ui_demo.nif")))
    require original.loaded
    require converted.loaded
    check converted.diagnostics.len == 0
    check converted.bundle.encodeResourceBundle() ==
      original.bundle.encodeResourceBundle()

  test "NIF and CSS styles resolve identically across roles, ids, classes, and states":
    let base = initThemeByName("macos-dark")
    let original = loadCssTheme(exampleDir / "html_ui_demo.css", base)
    let converted =
      parseCssTheme(nifStylesheet(readFile(exampleDir / "nif_ui_demo.css.nif")), base)
    require original.diagnostics.len == 0
    require converted.diagnostics.len == 0
    for role in StyleRole:
      for states in [{}, {ssHovered}, {ssPressed}, {ssSelected}, {ssOpen}, {ssDisabled}]:
        for id in [
          "", "root", "about-content", "preferences", "name", "language", "theme"
        ]:
          for classes in [
            @[],
            @["primary"],
            @["label-title"],
            @["muted"],
            @["eyebrow"],
            @["field-label"],
          ]:
            let context = controlStyle(role, states, id = id, classes = classes)
            check converted.theme.resolveButtonStyle(context) ==
              original.theme.resolveButtonStyle(context)
            check converted.theme.resolveComboBoxStyle(context) ==
              original.theme.resolveComboBoxStyle(context)

  test "NIF demo wires preview, reset, and appearance changes for both windows":
    let loaded =
      parseGuiResourceBundle(nifGuiMarkup(readFile(exampleDir / "nif_ui_demo.nif")))
    require loaded.loaded
    let built = loaded.bundle.instantiateResources()
    require built.instantiated
    let
      app = newApplication("NIF demo test")
      window = built.instance.window(resourceId("window"))
      about = built.instance.window(resourceId("about"))
      name = TextField(built.instance.view(resourceId("name")))
      picker = ComboBox(built.instance.view(resourceId("theme")))
      language = ComboBox(built.instance.view(resourceId("language")))
      updates = Button(built.instance.view(resourceId("updates")))
      preview = Button(built.instance.view(resourceId("preview")))
      reset = Button(built.instance.view(resourceId("reset")))
      status = TextField(built.instance.view(resourceId("status")))
      progress = ProgressIndicator(built.instance.view(resourceId("progress")))
      stylesheet = parseCssTheme(
        nifStylesheet(readFile(exampleDir / "nif_ui_demo.css.nif")),
        initThemeByName("macos-dark"),
      )
      context = controlStyle(srButton, id = "preview", classes = @["primary"])
    defer:
      window.close()
      about.close()
    app.configureNifUiDemo(built.instance, stylesheet.theme)
    name.stringValue = "Grace"
    language.selectedIndex = 1
    updates.state = bsOff
    require preview.sendAction()
    check status.stringValue == "Grace · C · Updates off"
    check progress.value == 100
    picker.selectedIndex = 1
    require picker.sendAction()
    let aqua = initThemeByName("aqua")
    check window.contentView.effectiveAppearance.theme.resolveButtonStyle(context) ==
      aqua.resolveButtonStyle(context)
    check about.contentView.effectiveAppearance.theme.resolveButtonStyle(context) ==
      aqua.resolveButtonStyle(context)
    require reset.sendAction()
    check name.stringValue == "Ada"
    check language.selectedIndex == 0
    check picker.selectedIndex == 0
    check updates.state == bsOn
    check progress.value == 0
    check window.contentView.effectiveAppearance.theme.resolveButtonStyle(context) ==
      stylesheet.theme.resolveButtonStyle(context)

  test "NIF escapes preserve literal HTML, quotes, backslashes, and textarea newlines":
    let markup = nifGuiMarkup(
      """(.nif27)
      (nkStackView
        (input (attrs (kv "id" "name") (kv "value" "A & B <C> \^D\^ \|")))
        (textarea (attrs (kv "id" "text")) "Line one\0A  Line two"))"""
    )
    let loaded = parseGuiResourceBundle(markup)
    require loaded.loaded
    let built = loaded.bundle.instantiateResources()
    require built.instantiated
    check TextField(built.instance.view(resourceId("name"))).stringValue ==
      "A & B <C> \"D\" \\"
    check TextView(built.instance.view(resourceId("text"))).stringValue ==
      "Line one\n  Line two"
    check nifStylesheet("""(stylesheet (rule "button" (color "\23ff0000")))""").contains(
      "color: #ff0000;"
    )

  test "hexColor values retain short, long, and alpha CSS color forms":
    for digits in ["f00", "f00a", "829fff", "829fff80", "ABCDEF"]:
      let css = nifStylesheet(
        "(stylesheet (rule \"button\" (color (hexColor \"" & digits & "\"))))"
      )
      check css.contains("color: #" & digits & ";")
      check parseCssTheme(css).diagnostics.len == 0
    let gui = parseGuiResourceBundle(
      nifGuiMarkup(
        """(nkView (attrs
      (kv "data-background-color" (hexColor "829fff"))))"""
      )
    )
    check gui.loaded
    for digits in ["", "12", "12345", "1234567", "123456789", "ggg", "\\23fff"]:
      expect ValueError:
        discard nifStylesheet(
          "(stylesheet (rule \"button\" (color (hexColor \"" & digits & "\"))))"
        )
    for value in ["(hexColor)", "(hexColor \"fff\" \"fff\")", "(unknown \"fff\")"]:
      expect ValueError:
        discard nifStylesheet("(stylesheet (rule \"button\" (color " & value & ")))")

  test "property and token tags map to CSS names":
    let css = nifStylesheet(
      """(stylesheet
      (tokens (accent (hexColor "829fff")))
      (rule "button" (background (hexColor "829fff"))
        (fontSize "14px") (nimkitChrome "flat-transparent")))"""
    )
    check css.contains("--accent: #829fff;")
    check css.contains("background: #829fff;")
    check css.contains("font-size: 14px;")
    check css.contains("-nimkit-chrome: flat-transparent;")
    check parseCssTheme(css).diagnostics.len == 0

  test "native selectors preserve groups, conjunctions, spelling, and specificity":
    let css = nifStylesheet(
      """(stylesheet
      (tokens (accent (hexColor "829fff")))
      (rule (any (id name) (id language) (id theme))
        (background (var accent)) (borderWidth 2 px))
      (rule (match (state open) (class primary) (id language) (role comboBox))
        (borderWidth 3 px))
      (rule (match (role label) (class "label-title")) (fontSize 28 px))
      (rule (id "about-content") (padding 9 px 12 px))
      (rule (role comboBox) (borderWidth 5 px)))"""
    )
    check css.contains("#name, #language, #theme {")
    check css.contains("combo-box:open.primary#language {")
    check css.contains("label.label-title {")
    check css.contains("#about-content {")
    check css.contains("background: var(--accent);")
    let native = parseCssTheme(css)
    let original = parseCssTheme(
      """:root { --accent: #829fff; }
      #name, #language, #theme { background: var(--accent); border-width: 2px; }
      combo-box#language.primary:open { border-width: 3px; }
      label.label-title { font-size: 28px; }
      #about-content { padding: 9px 12px; }
      combo-box { border-width: 5px; }"""
    )
    require native.diagnostics.len == 0
    require original.diagnostics.len == 0
    for states in [{}, {ssOpen}]:
      for id in ["language", "other"]:
        for classes in [@[], @["primary"]]:
          let context = controlStyle(srComboBox, states, id = id, classes = classes)
          check native.theme.resolveComboBoxStyle(context) ==
            original.theme.resolveComboBoxStyle(context)

  test "native numbers, px units, keywords, and token names become typed style values":
    let css = nifStylesheet(
      """(stylesheet
      (tokens (focusColor (hexColor "829fff")))
      (rule (role button)
        (padding 9 px 12 px)
        (borderWidth 1u px)
        (borderRadius 2.5 px)
        (fontSize 1E1 px)
        (nimkitFocusRingInset -1.5 px)
        (nimkitWidthFactor 0.75)
        (nimkitChrome flatTransparent)
        (boxShadow none)
        (nimkitFocusRingColor (var focusColor))))"""
    )
    check css.contains("padding: 9px 12px;")
    check css.contains("border-width: 1px;")
    check css.contains("border-radius: 2.5px;")
    check css.contains("font-size: 10.0px;")
    check css.contains("-nimkit-focus-ring-inset: -1.5px;")
    check css.contains("-nimkit-width-factor: 0.75;")
    check css.contains("-nimkit-chrome: flat-transparent;")
    check css.contains("box-shadow: none;")
    check css.contains("-nimkit-focus-ring-color: var(--focus-color);")
    check parseCssTheme(css).diagnostics.len == 0

  test "native selectors and values reject ambiguous or malformed forms":
    for selector in [
      "(any)", "(match)", "(id)", "(id name language)", "(id 9)",
      "(id \"name, button\")", "(unknown name)", "(match (id name) (id language))",
      "(match (role button) (role label))",
      "(match (any (id name) (id language)) (state open))",
    ]:
      checkpoint(selector)
      expect ValueError:
        discard nifStylesheet("(stylesheet (rule " & selector & " (padding 0)))")
    for value in [
      "9px", ".5 px", "1. px", "+1 px", "1e1 px", "1E px", "1E+ px", "1E999 px",
      "0x181e29", "1_000", "-1u", "9223372036854775808", "18446744073709551616u",
      "9 em", "px 9", "9 px px", "9 px \"12px\"", "none default", "(var)",
      "(var accent extra)", "(var \"accent, color\")",
    ]:
      checkpoint(value)
      expect ValueError:
        discard
          nifStylesheet("(stylesheet (rule (role button) (padding " & value & ")))")

  test "canonical hex escapes and NIF27 shortcuts follow nifspec":
    check nifGuiMarkup("""(nkLabel "\28\29\5B\5D\7B\7D\7E\23\27\22\5C\3A\40")""") ==
      "<nk-label>()[]{}~#'&quot;\\:@</nk-label>"
    check nifGuiMarkup("""(nkLabel "\n\t\r\|\^")""") ==
      "<nk-label>\n\t\r\\&quot;</nk-label>"
    check nifGuiMarkup("""(nk\2Dlabel "Hello")""") == "<nk-label>Hello</nk-label>"

  test "malformed NIF is rejected before GUI or CSS parsing":
    for source in [
      "", "(.nif27)", ")", "(nkView", "(nkView))", "(nkView bare)",
      "(nkView \"unterminated)", "(nkView \"\\0\")", "(nkView \"\\ZZ\")",
      "(input \"unexpected\")", "(nkView (attrs (kv \"id\")))",
      "(nkView (attrs (kv \"id\" \"a\" \"b\")))",
      "(nkView (attrs (kv \"id\" \"a\") (kv \"ID\" \"b\")))",
      "(nkView (attrs (kv \"bad name\" \"x\")))", "(nkView (attrs) (attrs))",
      "(nkView \"\\af\")", "(nkView \"\\\\\")", "(nkView \"raw # control\")",
      "(nk-view)",
    ]:
      checkpoint(source)
      expect ValueError:
        discard nifGuiMarkup(source)
    expect ValueError:
      discard nifGuiMarkup(repeat("(nkView ", 257) & repeat(")", 257))
    for source in [
      "(rule \"button\")", "(stylesheet (button))", "(stylesheet (rule))",
      "(stylesheet (rule \"button\" (color)))", "(stylesheet)(stylesheet)",
    ]:
      checkpoint(source)
      expect ValueError:
        discard nifStylesheet(source)
