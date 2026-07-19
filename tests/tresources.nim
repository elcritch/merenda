import std/[os, unittest]

import merenda/nimkit
import merenda/nimkit/resources

proc diagnosticWithCode(diagnostics: ResourceDiagnostics, code: string): bool =
  for diagnostic in diagnostics:
    if diagnostic.code == code:
      return true

proc sampleBundle(): ResourceBundle =
  result = initResourceBundle("tests.resources")
  result.localizations =
    @[
      LocalizedCatalogResource(
        locale: "en",
        strings:
          @[
            LocalizedStringResource(key: "window.title", value: "Resource Window"),
            LocalizedStringResource(key: "button.run", value: "Run Resource"),
          ],
      )
    ]
  result.images =
    @[
      ImageAssetResource(
        id: resourceId("shadow"),
        sourceKind: risFile,
        path: "data/shadow-button.png",
        cachePolicy: ricDefault,
      )
    ]
  result.commands =
    @[
      CommandResource(
        id: resourceId("run"), selector: "performClick", targetKind: rctResponderChain
      )
    ]
  result.keyBindings =
    @[
      KeyBindingTableResource(
        id: resourceId("window.keys"),
        bindings:
          @[
            KeyBindingResource(
              stroke: KeyStrokeResource(text: "r", modifiers: {rsmShortcut}),
              commandId: resourceId("run"),
            )
          ],
      )
    ]
  result.themes =
    @[
      ThemeFragmentResource(
        id: resourceId("test.theme"),
        tokens:
          @[
            ThemeTokenResource(
              name: "resource.accent",
              value: ResourceStyleValue(kind: rsvColor, color: color(0.2, 0.4, 0.8)),
            ),
            ThemeTokenResource(
              name: "resource.minimumSize",
              value: ResourceStyleValue(kind: rsvSize, size: initSize(120, 32)),
            ),
          ],
        rules:
          @[
            ThemeRuleResource(
              selector: ThemeSelectorResource(role: "srButton"),
              styles:
                @[
                  ThemeStyleResource(
                    name: "background.color",
                    value: ResourceStyleValue(kind: rsvToken, text: "resource.accent"),
                  )
                ],
            )
          ],
      )
    ]

  let
    runButton = initViewNodeResource(
      resourceId("run.button"),
      kind = "button",
      properties = [
        resourceProperty("frame", resourceValue(rect(16, 48, 140, 32))),
        resourceProperty(
          "title",
          resourceValue(resourceReference(rrLocalizedString, resourceId("button.run"))),
        ),
      ],
    )
    icon = initViewNodeResource(
      resourceId("run.icon"),
      kind = "imageView",
      properties = [
        resourceProperty(
          "image", resourceValue(resourceReference(rrImage, resourceId("shadow")))
        )
      ],
    )
    root = initViewNodeResource(
      resourceId("root"),
      kind = "stackView",
      properties = [
        resourceProperty("orientation", resourceValue("laVertical")),
        resourceProperty("spacing", resourceValue(8.0'f32)),
        resourceProperty("edgeInsets", resourceValue(insets(4, 8, 12, 16))),
      ],
      children = [runButton, icon],
    )
  result.views = @[root]
  result.controllers =
    @[initControllerNodeResource(resourceId("root.controller"), resourceId("root"))]
  result.windows =
    @[
      WindowResource(
        id: resourceId("main.window"),
        kind: rwWindow,
        title: localizedResourceText("window.title", "Window"),
        frame: rect(80, 80, 420, 260),
        controllerId: resourceId("root.controller"),
        initialFirstResponderId: resourceId("run.button"),
        keyBindingTableId: resourceId("window.keys"),
        themeId: resourceId("test.theme"),
      )
    ]
  result.menus =
    @[
      MenuResource(
        id: resourceId("main.menu"),
        title: resourceText("Main"),
        items:
          @[
            MenuItemResource(
              id: resourceId("run.item"),
              title: localizedResourceText("button.run", "Run"),
              commandId: resourceId("run"),
              enabled: rfOn,
              validates: rfOn,
            )
          ],
      )
    ]

suite "NimKit resources":
  test "canonical CBOR round trips stable resource records":
    let
      bundle = sampleBundle()
      first = bundle.encodeResourceBundle()
      second = bundle.encodeResourceBundle()
      decoded = decodeResourceBundle(first)

    check first == second
    check decoded.loaded
    check decoded.bundle.format == ResourceFormatName
    check decoded.bundle.namespace == "tests.resources"
    check decoded.bundle.views[0].children[0].id == resourceId("run.button")
    check decoded.bundle.views[0].properties[2].value.insetsValue == insets(
      4, 8, 12, 16
    )
    check decoded.bundle.windows[0].frame == rect(80, 80, 420, 260)
    check decoded.bundle.keyBindings[0].bindings[0].stroke.modifiers == {rsmShortcut}
    check decoded.bundle.themes[0].tokens[0].value.kind == rsvColor
    check decoded.bundle.themes[0].tokens[0].value.color == color(0.2, 0.4, 0.8)
    check decoded.bundle.themes[0].tokens[1].value.size == initSize(120, 32)

  test "decode reports malformed and incompatible resources":
    let malformed = decodeResourceBundle("not cbor")
    check malformed.diagnostics.diagnosticWithCode("resource.cbor.invalid")

    let trailing = decodeResourceBundle(sampleBundle().encodeResourceBundle() & "x")
    check trailing.diagnostics.diagnosticWithCode("resource.cbor.trailingData")

    var bundle = sampleBundle()
    bundle.version.major = CurrentResourceVersion.major + 1
    let incompatible = decodeResourceBundle(bundle.encodeResourceBundle())
    check incompatible.diagnostics.diagnosticWithCode("resource.version.incompatible")

  test "validation reports identifiers references selectors and assets":
    var bundle = sampleBundle()
    bundle.views[0].children[1].id = resourceId("run.button")
    bundle.commands[0].selector = "missingSelector"
    bundle.images[0].path = "data/does-not-exist.png"
    bundle.windows[0].themeId = resourceId("missing.theme")

    let diagnostics = bundle.validateResources(
      initNimKitResourceRegistry(), initResourceValidationOptions(getCurrentDir())
    )
    check diagnostics.hasErrors
    check diagnostics.diagnosticWithCode("resource.identifier.duplicate")
    check diagnostics.diagnosticWithCode("resource.command.selectorMismatch")
    check diagnostics.diagnosticWithCode("resource.image.unavailable")
    check diagnostics.diagnosticWithCode("resource.reference.unavailable")

  test "validation reports localization and theme parent cycles":
    var bundle = sampleBundle()
    bundle.localizations =
      @[
        LocalizedCatalogResource(locale: "a", fallbackLocale: "b"),
        LocalizedCatalogResource(locale: "b", fallbackLocale: "a"),
      ]
    bundle.themes =
      @[
        ThemeFragmentResource(id: resourceId("a"), parentId: resourceId("b")),
        ThemeFragmentResource(id: resourceId("b"), parentId: resourceId("a")),
      ]
    bundle.windows[0].themeId = resourceId("a")

    let diagnostics = bundle.validateResources(initNimKitResourceRegistry())
    check diagnostics.diagnosticWithCode("resource.localization.fallbackCycle")
    check diagnostics.diagnosticWithCode("resource.theme.parentCycle")

  test "validated resources instantiate and bridge to NimKit identities":
    let
      bundle = sampleBundle()
      context =
        initResourceInstantiationContext(locale = "en", assetBasePath = getCurrentDir())
      construction = bundle.instantiateResources(context)

    check construction.instantiated
    let
      root = StackView(construction.instance.view(resourceId("root")))
      button = Button(construction.instance.view(resourceId("run.button")))
      imageView = ImageView(construction.instance.view(resourceId("run.icon")))
      window = construction.instance.window(resourceId("main.window"))
      menu = construction.instance.menu(resourceId("main.menu"))

    check root.subviews.len == 2
    check root.edgeInsets == insets(4, 8, 12, 16)
    check button.title == "Run Resource"
    check imageView.image().isNil == false
    check window.title == "Resource Window"
    check window.contentView == View(root)
    check window.initialFirstResponder == View(button)
    check window.keyBindings.bindings.len == 1
    check construction.instance.findWindowController(resourceId("main.window")).isNil ==
      false
    check menu.len == 1
    check menu[0].title == "Run Resource"
    check menu[0].action().name == "performClick"

    var theme: Theme
    check construction.instance.findTheme(resourceId("test.theme"), theme)
    var accent: StyleValue
    check theme.tokens.resolveToken("resource.accent", accent)
    check accent.kind == svColor

  test "construction diagnoses selectors unsupported by explicit targets":
    var bundle = sampleBundle()
    bundle.commands[0].targetKind = rctExplicit
    bundle.commands[0].targetId = resourceId("root")
    bundle.keyBindings.setLen(0)
    bundle.windows[0].keyBindingTableId = resourceId("")

    let construction = bundle.instantiateResources(
      initResourceInstantiationContext(assetBasePath = getCurrentDir())
    )
    check construction.instantiated == false
    check construction.diagnostics.diagnosticWithCode(
      "resource.command.selectorMismatch"
    )

  test "required instance lookup reports missing identifiers":
    let construction = sampleBundle().instantiateResources(
        initResourceInstantiationContext(assetBasePath = getCurrentDir())
      )
    expect ResourceLookupError:
      discard construction.instance.view(resourceId("missing"))
