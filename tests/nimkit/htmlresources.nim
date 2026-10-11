## GUI markup behavior shared by the NimKit test runner.
import std/[options, os, strutils, tempfiles, unittest]

import merenda/nimkit
import ../../examples/html_ui_demo

proc hasCode(loaded: ResourceLoadResult, code: string): bool =
  for diagnostic in loaded.diagnostics:
    if diagnostic.code == code:
      return true

suite "NimKit GUI markup resources":
  test "HTML5 void tags, entities, casing, and boolean attributes create native siblings":
    let loaded = parseGuiResourceBundle(
      """
      <!doctype nimkit>
      <NK-MAIN>
        <NK-WINDOW id=window title="GUI interface" data-frame="120 140 400 300">
        <NK-STACK-VIEW ID=root
              data-padding="12 24" data-spacing=8>
          <nk-label data-label-style=title id=heading>Hello &amp; welcome</nk-label>
          <input ID=name value="Ada &amp; Grace" placeholder="Your name" readonly>
          <input id=enabled type=checkbox checked disabled=false>
          <nk-label id=message>First<br>second<br/>third</nk-label>
          <button id=save class="primary wide">Save <strong>changes</strong></button>
        </NK-STACK-VIEW>
        </NK-WINDOW>
      </NK-MAIN>
    """
    )
    check loaded.loaded
    check loaded.diagnostics.len == 0
    check loaded.bundle.views.len == 1
    check loaded.bundle.views[0].children.len == 5
    check loaded.bundle.windows[0].title.fallback == "GUI interface"
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    let
      root = StackView(built.instance.view(resourceId("root")))
      name = TextField(built.instance.view(resourceId("name")))
      checkbox = Button(built.instance.view(resourceId("enabled")))
      save = Button(built.instance.view(resourceId("save")))
      window = built.instance.window(resourceId("window"))
    check root.orientation == laVertical
    check root.spacing == 8
    check root.edgeInsets == insets(12, 24, 12, 24)
    check name.stringValue == "Ada & Grace"
    check name.placeholder == "Your name"
    check not name.editable
    check checkbox.state == bsOn
    check not checkbox.enabled
    check save.title == "Save changes"
    check save.styleId == "save"
    check save.styleClasses == @["primary", "wide"]
    check TextField(built.instance.view(resourceId("message"))).stringValue ==
      "First\nsecond\nthird"
    check Label(built.instance.view(resourceId("heading"))).labelStyle == lsTitle
    check window.contentView == root
    check window.frame == rect(120, 140, 400, 300)

  test "normal select subelements preserve display text, values, and selection":
    let loaded = parseGuiResourceBundle(
      """
      <select id=language>
        <option value=nim>Nim</option>
        <option value=other selected>Another language</option>
      </select>
    """
    )
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    let combo = ComboBox(built.instance.view(resourceId("language")))
    check not combo.editable
    check combo.numberOfItems == 2
    check combo.itemAtIndex(1) == "Another language"
    check combo.itemObjectValueAtIndex(1) == toObj("other")
    check combo.selectedIndex == 1

  test "a GUI document defines independent windows with separate content roots":
    let loaded = parseGuiResourceBundle(
      """<nk-main>
  <nk-window id=primary title="Preferences" data-frame="10 20 480 320">
    <nk-stack-view id=primary-content data-spacing=8>
      <nk-label id=title data-label-style=title>Preferences</nk-label>
      <nk-stack-view data-axis=horizontal id=actions><button id=save>Save</button></nk-stack-view>
    </nk-stack-view>
  </nk-window>
  <nk-window id=secondary title="Inspector" data-frame="520 20 300 320">
    <nk-view id=secondary-content><nk-label id=details>Details</nk-label></nk-view>
  </nk-window>
</nk-main>"""
    )
    require loaded.loaded
    check loaded.bundle.windows.len == 2
    check loaded.bundle.views.len == 2
    let built = loaded.bundle.instantiateResources()
    require built.instantiated
    let
      primary = built.instance.window(resourceId("primary"))
      secondary = built.instance.window(resourceId("secondary"))
      first = built.instance.view(resourceId("primary-content"))
      second = built.instance.view(resourceId("secondary-content"))
    defer:
      primary.close()
      secondary.close()
    check primary.contentView == first
    check secondary.contentView == second
    check first != second
    check first.superview.isNil
    check second.superview.isNil
    check primary.frame == rect(10, 20, 480, 320)
    check secondary.frame == rect(520, 20, 300, 320)
    check StackView(built.instance.view(resourceId("actions"))).orientation ==
      laHorizontal
    check built.instance.view(resourceId("title")).subviews.len == 0
    check built.instance.view(resourceId("details")).superview == second
    check loaded.bundle.encodeResourceBundle().decodeResourceBundle().loaded

  test "native widgets own their text and only containers create child views":
    let loaded = parseGuiResourceBundle(
      """<nk-stack-view id=root>
  <nk-label id=caption>Hello <strong>native</strong> widgets</nk-label>
  <nk-text-field id=field value="Ada"/>
  <nk-text-view id=editor>Line one
  Line two</nk-text-view>
  <nk-check-box id=updates checked>Send updates</nk-check-box>
  <nk-combo-box id=language><option value=nim>Nim</option></nk-combo-box>
  <section id=group><nk-label>Grouped</nk-label></section>
</nk-stack-view>"""
    )
    require loaded.loaded
    let built = loaded.bundle.instantiateResources()
    require built.instantiated
    check TextField(built.instance.view(resourceId("caption"))).stringValue ==
      "Hello native widgets"
    check TextField(built.instance.view(resourceId("field"))).stringValue == "Ada"
    check TextView(built.instance.view(resourceId("editor"))).stringValue ==
      "Line one\n  Line two"
    check Button(built.instance.view(resourceId("updates"))).title == "Send updates"
    check Button(built.instance.view(resourceId("updates"))).state == bsOn
    check ComboBox(built.instance.view(resourceId("language"))).itemObjectValueAtIndex(
      0
    ) == toObj("nim")
    for id in ["caption", "field", "editor", "updates", "language"]:
      check built.instance.view(resourceId(id)).subviews.len == 0
    check StackView(built.instance.view(resourceId("group"))).orientation == laVertical

  test "browser scaffolding and ambiguous GUI ownership produce diagnostics":
    for tag in [
      "html", "head", "body", "form", "p", "h1", "div", "header", "footer", "window",
      "column", "row", "view", "label", "text-field", "combo-box", "nk-column", "nk-row",
    ]:
      let loaded = parseGuiResourceBundle("<" & tag & ">Text</" & tag & ">")
      check not loaded.loaded
      check loaded.hasCode("gui.element.unsupported")
    for source in [
      "<nk-main><nk-main><nk-view/></nk-main></nk-main>",
      "<nk-view><nk-main><nk-view/></nk-main></nk-view>",
    ]:
      check parseGuiResourceBundle(source).hasCode("gui.document.nested")
    for source in [
      "<nk-window id=outer><nk-window id=inner><nk-view/></nk-window></nk-window>",
      "<nk-view><nk-window id=nested><nk-view/></nk-window></nk-view>",
    ]:
      check parseGuiResourceBundle(source).hasCode("gui.window.nested")
    for source in [
      "<nk-window id=empty/>", "<nk-window id=many><nk-view/><nk-view/></nk-window>"
    ]:
      check parseGuiResourceBundle(source).hasCode("gui.window.content")
    check parseGuiResourceBundle("<nk-window><nk-view/></nk-window>").hasCode(
      "gui.window.idMissing"
    )
    check not parseGuiResourceBundle(
      "<nk-label><nk-check-box>Ambiguous</nk-check-box></nk-label>"
    ).loaded

  test "the optional NimKit doctype identifies GUI markup without a DTD":
    for marker in ["", "<!doctype nimkit>", "<!DOCTYPE NIMKIT>"]:
      check parseGuiResourceBundle(marker & "<nk-main><nk-view/></nk-main>").loaded
    for marker in [
      "<!doctype html>", "<!doctype nimkit SYSTEM 'schema.dtd'>",
      "<!doctype nimkit [<!ENTITY name 'value'>]>",
    ]:
      check parseGuiResourceBundle(marker & "<nk-view/>").hasCode(
        "gui.doctype.unsupported"
      )
    check parseGuiResourceBundle("<nk-view/><!doctype nimkit>").hasCode(
      "gui.doctype.unsupported"
    )

  test "custom native element names reject ambiguous normalized kind names":
    var registry = initNimKitResourceRegistry()
    for name in ["some-appWidget", "someApp-widget"]:
      registry.registerViewKind(
        name,
        proc(frame: Rect): View =
          newView(frame),
      )
    check parseGuiResourceBundle("<some-app-widget/>", registry).hasCode(
      "gui.kind.ambiguous"
    )

  test "application tags preserve their prefix and inherit native content policies":
    var registry = initNimKitResourceRegistry()
    registry.registerViewKind(
      "some-app-widget",
      proc(frame: Rect): View =
        newView(frame),
    )
    registry.registerViewKind(
      "some-app-picker",
      proc(frame: Rect): View =
        newComboBox(frame = frame),
      baseKind = "comboBox",
    )
    registry.registerViewKind(
      "some-app-editor",
      proc(frame: Rect): View =
        newTextView(frame = frame),
      baseKind = "textView",
    )
    let loaded = parseGuiResourceBundle(
      """<some-app-widget id=root>
  <some-app-picker id=picker data-item-values="nim c" data-items="Nim C"
                   data-selected-index="1"/>
  <some-app-editor id=editor disabled>one &lt;b&gt;two&lt;/b&gt;</some-app-editor>
</some-app-widget>""",
      registry,
    )
    require loaded.loaded
    check loaded.bundle.views[0].kind == "some-app-widget"
    let built = loaded.bundle.instantiateResources(registry)
    require built.instantiated
    let picker = ComboBox(built.instance.view(resourceId("picker")))
    check picker.itemObjectValueAtIndex(1) == toObj("c")
    check picker.selectedIndex == 1
    let editor = TextView(built.instance.view(resourceId("editor")))
    check editor.stringValue == "one <b>two</b>"
    check not editor.editable
    check not editor.selectable
    check not parseGuiResourceBundle("<app-widget/>", registry).loaded
    check parseGuiResourceBundle("<nk-stack-view data-kind=button/>").hasCode(
      "gui.kind.override"
    )

  test "native multiline controls reject child elements and preserve escaped markup":
    for source in [
      "<nk-text-view>one <b>two</b></nk-text-view>",
      "<nk-text-view><button>Hidden control</button></nk-text-view>",
    ]:
      let loaded = parseGuiResourceBundle(source)
      check not loaded.loaded
      check loaded.hasCode("gui.element.unsupportedChild")
    let loaded = parseGuiResourceBundle(
      "<nk-text-view id=editor>one &lt;b&gt;two&lt;/b&gt;\nthree</nk-text-view>"
    )
    require loaded.loaded
    let built = loaded.bundle.instantiateResources()
    require built.instantiated
    check TextView(built.instance.view(resourceId("editor"))).stringValue ==
      "one <b>two</b>\nthree"

  test "native boxes and groups own one content root and measure its stack":
    var registry = initNimKitResourceRegistry()
    registry.registerViewKind(
      "some-app-group",
      proc(frame: Rect): View =
        newGroupBox(frame = frame),
      baseKind = "group",
    )
    for tag in ["nk-box", "nk-group", "some-app-group"]:
      let loaded = parseGuiResourceBundle(
        "<" & tag & " id=group data-title=Account><nk-stack-view id=content " &
          "data-spacing=8 data-distribution=natural><button>Save</button>" &
          "<button>Reset</button></nk-stack-view></" & tag & ">",
        registry,
      )
      require loaded.loaded
      let built = loaded.bundle.instantiateResources(registry)
      require built.instantiated
      let
        group = Box(built.instance.view(resourceId("group")))
        content = StackView(built.instance.view(resourceId("content")))
      check group.contentView == content
      check content.superview == group
      check group.title == "Account"
      check group.accessibilityRole == arGroup
      check group.accessibilityLabel == "Account"
      check content.arrangedSubviews.len == 2
      check group.intrinsicContentSize.height > content.intrinsicContentSize.height
      check loaded.bundle.encodeResourceBundle().decodeResourceBundle().loaded
      let invalid = parseGuiResourceBundle(
        "<" & tag & "><button>One</button><button>Two</button></" & tag & ">", registry
      )
      check not invalid.loaded
      check invalid.hasCode("resource.view.tooManyChildren")

  test "void normalization preserves quoted delimiters, comments, and unquoted slashes":
    let loaded = parseGuiResourceBundle(
      "<section id=root>\r\n<!-- <input> -->\r\n" & "<input id=path value=src/>\r\n" &
        "<input id=compare placeholder='a > b / c'>\r\n" &
        "<button id=done>Done</button></section>"
    )
    check loaded.loaded
    check loaded.diagnostics.len == 0
    check loaded.bundle.views[0].children.len == 3
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    check TextField(built.instance.view(resourceId("path"))).stringValue == "src/"
    check TextField(built.instance.view(resourceId("compare"))).placeholder ==
      "a > b / c"

  test "native combo attributes apply items before values and selection":
    let loaded = parseGuiResourceBundle(
      """<nk-view data-kind=comboBox id=language data-item-values="nim c"
              data-selected-index=1 data-items="Nim C"></nk-view>"""
    )
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    let combo = ComboBox(built.instance.view(resourceId("language")))
    check combo.numberOfItems == 2
    check combo.itemAtIndex(1) == "C"
    check combo.itemObjectValueAtIndex(1) == toObj("c")
    check combo.selectedIndex == 1

  test "textarea preserves literal markup and only reserves actual widget IDs":
    var limits = initResourceLoadLimits()
    limits.maximumNodes = 3
    limits.maximumTreeDepth = 2
    let loaded = parseGuiResourceBundle(
      """<section id=root><textarea id=notes>one <b>two</b> <input id=after>
<!-- literal comment --> &lt;three&gt; &amp; &copy; </TeXtArEa>
<button id=after>After</button></section>""",
      limits,
    )
    check loaded.loaded
    check loaded.diagnostics.len == 0
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    check TextView(built.instance.view(resourceId("notes"))).stringValue ==
      "one <b>two</b> <input id=after>\n" & "<!-- literal comment --> <three> & \u00a9 "
    check Button(built.instance.view(resourceId("after"))).title == "After"

  test "long literal ampersand runs preserve following named entities":
    let value = repeat('&', 100_000) & "&copy;"
    let loaded = parseGuiResourceBundle("<input id=field value='" & value & "'>")
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    check TextField(built.instance.view(resourceId("field"))).stringValue ==
      repeat('&', 100_000) & "\u00a9"

  test "textarea distinguishes unquoted value slashes from closing markers":
    let loaded = parseGuiResourceBundle(
      """<section><textarea id=notes/>one <b>two</b></textarea>
<textarea id="empty"/><button id=after>After</button></section>"""
    )
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    check TextView(built.instance.view(resourceId("notes/"))).stringValue ==
      "one <b>two</b>"
    check TextView(built.instance.view(resourceId("empty"))).stringValue == ""
    check Button(built.instance.view(resourceId("after"))).title == "After"

  test "HTML classes preserve native heading styles and data properties take precedence":
    let loaded = parseGuiResourceBundle(
      """
      <section>
        <nk-label data-label-style=title data-alignment=left id=heading class=accent>Heading</nk-label>
        <input id=field disabled data-enabled=true>
      </section>
    """
    )
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    let heading = Label(built.instance.view(resourceId("heading")))
    check LabelStyleClass in heading.styleClasses
    check LabelTitleStyleClass in heading.styleClasses
    check "accent" in heading.styleClasses
    check heading.alignment == taLeft
    check TextField(built.instance.view(resourceId("field"))).enabled

  test "range, number, progress, and textarea retain native state":
    let loaded = parseGuiResourceBundle(
      """
      <section id=root>
        <input id=volume type=range min=0 max=10 step=0.5 value=3>
        <input id=count type=number min=1 max=20 step=2 value=5>
        <progress id=progress max=100 value=25></progress>
        <progress id=busy></progress>
        <textarea id=notes readonly>First line
  Second line</textarea>
      </section>
    """
    )
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    let
      slider = Slider(built.instance.view(resourceId("volume")))
      stepper = Stepper(built.instance.view(resourceId("count")))
      progress = ProgressIndicator(built.instance.view(resourceId("progress")))
      notes = TextView(built.instance.view(resourceId("notes")))
    check slider.maxValue == 10
    check slider.stepValue == 0.5
    check slider.value == 3
    check stepper.increment == 2
    check stepper.value == 5
    check progress.maxValue == 100
    check progress.value == 25
    check not progress.indeterminate
    check ProgressIndicator(built.instance.view(resourceId("busy"))).indeterminate
    check notes.stringValue == "First line\n  Second line"
    check not notes.editable

  test "attribute text preserves whitespace and HTML entities, including in IDs":
    let loaded = parseGuiResourceBundle(
      """
      <section>
        <input id="gui&#46;view&#46;1" value="  a / b&nbsp;&copy;  ">
        <textarea id=disabled disabled>Read only</textarea>
      </section>
    """
    )
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    check TextField(built.instance.view(resourceId("gui.view.1"))).stringValue ==
      "  a / b\u00a0\u00a9  "
    let text = TextView(built.instance.view(resourceId("disabled")))
    check not text.editable
    check not text.selectable

  test "native properties use kebab case and actions can be connected in Nim":
    let loaded = parseGuiResourceBundle(
      """
      <nk-stack-view id=toolbar data-axis=horizontal data-alignment=center
           data-frame="0 0 320 60" data-background-color="#123456">
        <button id=run data-action=runTask data-enabled=false>Run</button>
      </nk-stack-view>
    """
    )
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    let
      toolbar = StackView(built.instance.view(resourceId("toolbar")))
      button = Button(built.instance.view(resourceId("run")))
    check toolbar.orientation == laHorizontal
    check toolbar.stackAlignment == svaCenter
    check toolbar.backgroundColor == parseHtmlColor("#123456")
    check button.action.name == "runTask"
    check not button.enabled
    var clicked: bool
    button.target = newActionTarget(
      button.action,
      proc(sender: DynamicAgent) =
        clicked = Button(sender).identifier == "run",
    )
    check button.sendAction()
    check clicked

  test "fragments and custom registered kinds reuse the resource schema":
    var registry = initNimKitResourceRegistry()
    registry.registerViewKind(
      "panel",
      proc(frame: Rect): View =
        newView(frame),
    )
    let loaded = parseGuiResourceBundle(
      """
      <nk-view data-kind=panel id=panel data-alpha=0.5>
        <span id=caption>Native panel</span>
      </nk-view>
      <button id=other>Other root</button>
    """,
      registry,
    )
    check loaded.loaded
    check loaded.bundle.views.len == 2
    let built = loaded.bundle.instantiateResources(registry)
    check built.instantiated
    check built.instance.view(resourceId("panel")).alphaValue == 0.5
    check built.instance.view(resourceId("caption")).superview ==
      built.instance.view(resourceId("panel"))

  test "mixed inline text produces one label and generated IDs avoid explicit IDs":
    let loaded = parseGuiResourceBundle(
      """
      <section>Hello <strong>native</strong> world!
        <button id="gui.view.1">Continue</button>
      </section>
    """
    )
    check loaded.loaded
    check loaded.bundle.views[0].id != resourceId("gui.view.1")
    check loaded.bundle.views[0].children.len == 2
    check loaded.bundle.views[0].children[0].properties[0].value.stringValue ==
      "Hello native world!"
    check loaded.bundle.encodeResourceBundle().decodeResourceBundle().loaded

  test "bad properties and unsupported GUI features produce diagnostics":
    for source in [
      "<section data-background-color=''></section>", "",
      "<html><head><title>Only metadata</title></head></html>",
      "<button onmouseover='run()'>Run</button>", "<input type=password>",
      "<button data-unknown=true>Broken</button>",
      "<section data-spacing=nan></section>", "<section data-axis=diagonal></section>",
      "<select multiple><option>One</option></select>",
      "<button onclick='run()'>Run</button>", "<section style='color:red'></section>",
      "<canvas></canvas>", "<nk-view data-kind=missing></nk-view>",
    ]:
      check not parseGuiResourceBundle(source).loaded
    let duplicate =
      parseGuiResourceBundle("<section id=x><button id=x>Duplicate</button></section>")
    check duplicate.hasCode("resource.identifier.duplicate")
    check not duplicate.loaded
    let malformed = parseGuiResourceBundle("<button data-frame='1 2 3'>Broken</button>")
    check malformed.hasCode("gui.attribute.invalid")

  test "HTML limits stop deep and oversized input before DOM construction":
    var limits = initResourceLoadLimits()
    limits.maximumTreeDepth = 2
    check parseGuiResourceBundle(
      "<section><section><section></section></section></section>", limits
    )
    .hasCode("gui.tree.tooDeep")
    check parseGuiResourceBundle(
      "<section><section/><button>Safe</button></section>", limits
    ).loaded
    limits.maximumNodes = 1
    check parseGuiResourceBundle("<section><input></section>", limits).hasCode(
      "gui.nodes.tooMany"
    )
    limits.maximumDataBytes = 4
    check parseGuiResourceBundle("<section></section>", limits).hasCode(
      "gui.data.tooLarge"
    )

  test "file loading preserves relative image resources without loading assets":
    let directory = createTempDir("nimkit-html-", "")
    defer:
      removeDir(directory)
    let path = directory / "interface.html"
    writeFile(path, "<section><img id=icon src='images/icon.png' alt=Icon></section>")
    let loaded = loadGuiResourceBundle(path)
    check loaded.loaded
    check loaded.bundle.images.len == 1
    check loaded.bundle.images[0].path == "images/icon.png"
    let image = loaded.bundle.findView(resourceId("icon")).get()
    check image.kind == "imageView"
    check image.properties[0].value.referenceValue.kind == rrImage
    removeFile(path)

  test "the shipped HTML example keeps controls compact when resized":
    let path =
      currentSourcePath().parentDir.parentDir.parentDir / "examples/html_ui_demo.html"
    let loaded = loadGuiResourceBundle(path)
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    let
      window = built.instance.window(resourceId("window"))
      root = window.contentView
      about = built.instance.window(resourceId("about"))
      button = Button(built.instance.view(resourceId("preview")))
      reset = Button(built.instance.view(resourceId("reset")))
      name = TextField(built.instance.view(resourceId("name")))
      language = ComboBox(built.instance.view(resourceId("language")))
      updates = Button(built.instance.view(resourceId("updates")))
      status = TextField(built.instance.view(resourceId("status")))
      stylesheet =
        loadCssTheme(path.changeFileExt("css"), initThemeByName("macos-dark"))
    check stylesheet.diagnostics.len == 0
    newApplication("GUI resource layout test").configureHtmlUiDemo(
      built.instance, stylesheet.theme
    )
    root.layoutSubtreeIfNeeded()
    about.contentView.layoutSubtreeIfNeeded()
    defer:
      window.close()
      about.close()
    let aboutGroup = Box(built.instance.view(resourceId("about-group")))
    check aboutGroup.contentView == built.instance.view(resourceId("about-details"))
    check aboutGroup.frame.maxY <= about.contentView.bounds.h

    check button.action.name == "previewProfile"
    check reset.action.name == "resetProfile"
    check updates.title == "Send me product updates"
    check name.stringValue == "Ada"
    check language.itemAtIndex(language.selectedIndex) == "Nim"
    check root.cssLayoutDiagnostics.len == 0
    let
      buttonHeight = button.frame.h
      languageHeight = language.frame.h
      checkboxHeight = updates.frame.h

    for size in [initSize(560, 640), initSize(720, 740), initSize(440, 640)]:
      root.frame = rect(0, 0, size.width, size.height)
      root.layoutSubtreeIfNeeded()
      check button.frame.w > 0
      check button.frame.h > 0
      check button.frame.h <= 44
      check abs(button.frame.h - buttonHeight) < 0.01
      check abs(language.frame.h - languageHeight) < 0.01
      check abs(updates.frame.h - checkboxHeight) < 0.01
      check language.frame.h <= 44
      check updates.frame.h <= 32
      check abs(name.frame.w - language.frame.w) < 0.01
      check button.frame.maxX <= button.superview.bounds.w
      check status.superview.frame.maxY <= root.bounds.h
      check root.layoutFeedbackCycles == 0

  test "HTML demo switches CSS themes immediately and reset restores custom styles":
    let path =
      currentSourcePath().parentDir.parentDir.parentDir / "examples/html_ui_demo.html"
    let loaded = loadGuiResourceBundle(path)
    require loaded.loaded
    let built = loaded.bundle.instantiateResources()
    require built.instantiated
    let
      window = built.instance.window(resourceId("window"))
      root = window.contentView
      about = built.instance.window(resourceId("about"))
      picker = ComboBox(built.instance.view(resourceId("theme")))
      name = TextField(built.instance.view(resourceId("name")))
      language = ComboBox(built.instance.view(resourceId("language")))
      updates = Button(built.instance.view(resourceId("updates")))
      preview = Button(built.instance.view(resourceId("preview")))
      reset = Button(built.instance.view(resourceId("reset")))
      status = TextField(built.instance.view(resourceId("status")))
      progress = ProgressIndicator(built.instance.view(resourceId("progress")))
      stylesheet =
        loadCssTheme(path.changeFileExt("css"), initThemeByName("macos-dark"))
      context = controlStyle(srButton, id = "preview", classes = @["primary"])
      themeNames = [
        "custom", "aqua", "banner", "darkbsd", "macos", "macos-dark", "nebula",
        "peachy", "synthwave83",
      ]
    defer:
      window.close()
      about.close()
    require stylesheet.diagnostics.len == 0
    newApplication("GUI resource theme test").configureHtmlUiDemo(
      built.instance, stylesheet.theme
    )
    check picker.action.name == "changeTheme"
    require picker.numberOfItems == themeNames.len
    name.stringValue = "Grace"
    language.selectedIndex = 1
    updates.state = bsOff

    for index, themeName in themeNames:
      checkpoint("theme: " & themeName)
      check picker.itemObjectValueAtIndex(index) == toObj(themeName)
      picker.selectedIndex = index
      require picker.sendAction()
      let expected =
        if themeName == "custom":
          stylesheet.theme
        else:
          initThemeByName(themeName)
      check root.effectiveAppearance.theme.resolveButtonStyle(context) ==
        expected.resolveButtonStyle(context)
      check about.contentView.effectiveAppearance.theme.resolveButtonStyle(context) ==
        expected.resolveButtonStyle(context)
      check root.cssLayoutDiagnostics.len == 0
      check root.layoutFeedbackCycles == 0
      check name.stringValue == "Grace"
      check language.selectedIndex == 1
      check updates.state == bsOff

    require preview.sendAction()
    check status.stringValue == "Grace · C · Updates off"
    check progress.value == 100
    require reset.sendAction()
    check picker.selectedIndex == 0
    check name.stringValue == "Ada"
    check language.selectedIndex == 0
    check updates.state == bsOn
    check progress.value == 0
    check status.stringValue == "Your preview will appear here."
    check root.effectiveAppearance.theme.resolveButtonStyle(context) ==
      stylesheet.theme.resolveButtonStyle(context)

  test "the About window can reopen after the application prunes closed windows":
    let
      path =
        currentSourcePath().parentDir.parentDir.parentDir / "examples/html_ui_demo.html"
      loaded = loadGuiResourceBundle(path)
    require loaded.loaded
    let built = loaded.bundle.instantiateResources()
    require built.instantiated
    let
      app = newApplication("GUI resource window test")
      about = built.instance.window(resourceId("about"))
      show = Button(built.instance.view(resourceId("show-about")))
      close = Button(built.instance.view(resourceId("close-about")))
    app.automaticallyStartsLocalSigilThread = false
    app.configureHtmlUiDemo(built.instance, initThemeByName("macos-dark"))
    defer:
      about.close()
      built.instance.window(resourceId("window")).close()
    for _ in 0 ..< 2:
      require show.sendAction()
      check about.isVisible
      check about in app.windows
      require close.sendAction()
      check about.isClosed
      discard app.runForFrames(1)
      check about notin app.windows
