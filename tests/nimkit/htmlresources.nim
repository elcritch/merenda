## HTML GUI behavior shared by the NimKit test runner.
import std/[options, os, tempfiles, unittest]

import merenda/nimkit

proc hasCode(loaded: ResourceLoadResult, code: string): bool =
  for diagnostic in loaded.diagnostics:
    if diagnostic.code == code:
      return true

suite "NimKit HTML resources":
  test "HTML5 void tags, entities, casing, and boolean attributes create native siblings":
    let loaded = parseHtmlResourceBundle(
      """
      <!doctype html>
      <HTML lang=en>
        <HEAD><meta charset=utf-8><title>HTML interface</title></HEAD>
        <BODY ID=root data-window=window data-window-frame="120 140 400 300"
              data-padding="12 24" data-spacing=8>
          <h1 id=heading>Hello &amp; welcome</h1>
          <input ID=name value="Ada &amp; Grace" placeholder="Your name" readonly>
          <input id=enabled type=checkbox checked disabled=false>
          <p id=message>First<br>second<br/>third</p>
          <button id=save class="primary wide">Save <strong>changes</strong></button>
        </BODY>
      </HTML>
    """
    )
    check loaded.loaded
    check loaded.diagnostics.len == 0
    check loaded.bundle.views.len == 1
    check loaded.bundle.views[0].children.len == 5
    check loaded.bundle.windows[0].title.fallback == "HTML interface"
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
    let loaded = parseHtmlResourceBundle(
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

  test "void normalization preserves quoted delimiters, comments, and unquoted slashes":
    let loaded = parseHtmlResourceBundle(
      "<main id=root>\r\n<!-- <input> -->\r\n" & "<input id=path value=src/>\r\n" &
        "<input id=compare placeholder='a > b / c'>\r\n" &
        "<button id=done>Done</button></main>"
    )
    check loaded.loaded
    check loaded.diagnostics.len == 0
    check loaded.bundle.views[0].children.len == 3
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    check TextField(built.instance.view(resourceId("path"))).stringValue == "src/"
    check TextField(built.instance.view(resourceId("compare"))).placeholder ==
      "a > b / c"

  test "HTML classes preserve native heading styles and data properties take precedence":
    let loaded = parseHtmlResourceBundle(
      """
      <main>
        <h1 id=heading class=accent>Heading</h1>
        <input id=field disabled data-enabled=true>
      </main>
    """
    )
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    let heading = Label(built.instance.view(resourceId("heading")))
    check LabelStyleClass in heading.styleClasses
    check LabelTitleStyleClass in heading.styleClasses
    check "accent" in heading.styleClasses
    check TextField(built.instance.view(resourceId("field"))).enabled

  test "range, number, progress, and textarea retain native state":
    let loaded = parseHtmlResourceBundle(
      """
      <main id=root>
        <input id=volume type=range min=0 max=10 step=0.5 value=3>
        <input id=count type=number min=1 max=20 step=2 value=5>
        <progress id=progress max=100 value=25></progress>
        <progress id=busy></progress>
        <textarea id=notes readonly>First line
  Second line</textarea>
      </main>
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
    let loaded = parseHtmlResourceBundle(
      """
      <main>
        <input id="html&#46;view&#46;1" value="  a / b&nbsp;&copy;  ">
        <textarea id=disabled disabled>Read only</textarea>
      </main>
    """
    )
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    check TextField(built.instance.view(resourceId("html.view.1"))).stringValue ==
      "  a / b\u00a0\u00a9  "
    let text = TextView(built.instance.view(resourceId("disabled")))
    check not text.editable
    check not text.selectable

  test "native properties use kebab case and actions can be connected in Nim":
    let loaded = parseHtmlResourceBundle(
      """
      <nav id=toolbar data-axis=horizontal data-alignment=center
           data-frame="0 0 320 60" data-background-color="#123456">
        <button id=run data-action=runTask data-enabled=false>Run</button>
      </nav>
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
    let loaded = parseHtmlResourceBundle(
      """
      <section data-kind=panel id=panel data-alpha=0.5>
        <span id=caption>Native panel</span>
      </section>
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
    let loaded = parseHtmlResourceBundle(
      """
      <div>Hello <strong>native</strong> world!
        <button id="html.view.1">Continue</button>
      </div>
    """
    )
    check loaded.loaded
    check loaded.bundle.views[0].id != resourceId("html.view.1")
    check loaded.bundle.views[0].children.len == 2
    check loaded.bundle.views[0].children[0].properties[0].value.stringValue ==
      "Hello native world!"
    check loaded.bundle.encodeResourceBundle().decodeResourceBundle().loaded

  test "bad properties and unsupported GUI features produce diagnostics":
    for source in [
      "<div data-background-color=''></div>", "",
      "<html><head><title>Only metadata</title></head></html>",
      "<button onmouseover='run()'>Run</button>", "<input type=password>",
      "<button data-unknown=true>Broken</button>", "<div data-spacing=nan></div>",
      "<div data-axis=diagonal></div>",
      "<select multiple><option>One</option></select>",
      "<button onclick='run()'>Run</button>", "<div style='color:red'></div>",
      "<canvas></canvas>", "<div data-kind=missing></div>",
    ]:
      check not parseHtmlResourceBundle(source).loaded
    let duplicate =
      parseHtmlResourceBundle("<main id=x><button id=x>Duplicate</button></main>")
    check duplicate.hasCode("resource.identifier.duplicate")
    check not duplicate.loaded
    let malformed =
      parseHtmlResourceBundle("<button data-frame='1 2 3'>Broken</button>")
    check malformed.hasCode("html.attribute.invalid")

  test "HTML limits stop deep and oversized input before DOM construction":
    var limits = initResourceLoadLimits()
    limits.maximumTreeDepth = 2
    check parseHtmlResourceBundle("<div><div><div></div></div></div>", limits).hasCode(
      "html.tree.tooDeep"
    )
    check parseHtmlResourceBundle("<div><div/><button>Safe</button></div>", limits).loaded
    limits.maximumNodes = 1
    check parseHtmlResourceBundle("<div><input></div>", limits).hasCode(
      "html.nodes.tooMany"
    )
    limits.maximumDataBytes = 4
    check parseHtmlResourceBundle("<div></div>", limits).hasCode("html.data.tooLarge")

  test "file loading preserves relative image resources without loading assets":
    let directory = createTempDir("nimkit-html-", "")
    defer:
      removeDir(directory)
    let path = directory / "interface.html"
    writeFile(path, "<main><img id=icon src='images/icon.png' alt=Icon></main>")
    let loaded = loadHtmlResourceBundle(path)
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
    let loaded = loadHtmlResourceBundle(path)
    check loaded.loaded
    let built = loaded.bundle.instantiateResources()
    check built.instantiated
    let
      window = built.instance.window(resourceId("window"))
      root = window.contentView
      button = Button(built.instance.view(resourceId("preview")))
      reset = Button(built.instance.view(resourceId("reset")))
      name = TextField(built.instance.view(resourceId("name")))
      language = ComboBox(built.instance.view(resourceId("language")))
      updates = Button(built.instance.view(resourceId("updates")))
      status = TextField(built.instance.view(resourceId("status")))
      stylesheet =
        loadCssTheme(path.changeFileExt("css"), initThemeByName("macos-dark"))
    check stylesheet.diagnostics.len == 0
    root.appearance = initAppearance(stylesheet.theme)
    root.layoutSubtreeIfNeeded()

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

    for size in [initSize(560, 540), initSize(720, 640), initSize(440, 540)]:
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
