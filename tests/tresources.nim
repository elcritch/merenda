import std/[options, os, strutils, unittest]

import merenda/nimkit
import merenda/nimkit/resources

type
  ResourceTestMode = enum
    rtmCompact
    rtmExpanded

  ResourceTestView = ref object of View
    xResourceCount: int
    xResourceMode: ResourceTestMode

protocol ResourceTestViewProtocol {.selectorScope: protocol, setterStyle: nim.} from
  ResourceTestView:
  property resourceCount -> int {.field: xResourceCount.}
  property resourceMode -> ResourceTestMode {.field: xResourceMode.}

proc newResourceTestView(frame = AutoRect): ResourceTestView =
  result = ResourceTestView()
  initViewFields(result, frame)
  discard result.withProto()

proc diagnosticWithCode(diagnostics: ResourceDiagnostics, code: string): bool =
  for diagnostic in diagnostics:
    if diagnostic.code == code:
      return true

proc sampleBundle(): ResourceBundle =
  result = initResourceBundle("tests.resources")
  result.localizations =
    @[
      LocalizedCatalogResource(
        id: resourceId("localization.en"),
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
  result.layoutGuides =
    @[
      initResourceLayoutGuide(
        resourceId("root.content"), resourceId("root"), insets(4, 8, 12, 16)
      )
    ]
  result.layoutConstraints =
    @[
      initResourceLayoutConstraint(
        resourceId("run.width"),
        resourceId("root"),
        resourceLayoutItem(resourceId("run.button")),
        rlaWidth,
        constant = 140.0'f32,
      ),
      initResourceLayoutConstraint(
        resourceId("icon.leading"),
        resourceId("root"),
        resourceLayoutItem(resourceId("run.icon")),
        rlaLeading,
        resourceLayoutItem(resourceId("root.content"), rliGuide),
        rlaLeading,
        constant = 4.0'f32,
        active = false,
      ),
    ]
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

proc editorBundle(): ResourceBundle =
  result = initResourceBundle("tests.resource-editor")
  result.views =
    @[
      initViewNodeResource(
        resourceId("editor.root"),
        kind = "stackView",
        properties = [resourceProperty("spacing", resourceValue(8.0'f32))],
        children = [
          initViewNodeResource(
            resourceId("editor.button"),
            kind = "button",
            properties = [resourceProperty("title", resourceValue("Original"))],
          )
        ],
      )
    ]

suite "NimKit resources":
  test "registry exposes deterministic kind and inherited property descriptors":
    let registry = initNimKitResourceRegistry()
    var kindNames: seq[string]
    for descriptor in registry.viewKinds:
      kindNames.add descriptor.kind

    check kindNames ==
      @[
        "box", "button", "checkBox", "control", "imageView", "label",
        "progressIndicator", "radioButton", "splitView", "stackView", "switchButton",
        "textField", "view",
      ]
    check registry.viewKindDescriptor("button").baseKind == "control"
    check registry.findViewKindDescriptor("missing").isNone
    expect ResourceRegistryLookupError:
      discard registry.viewKindDescriptor("missing")

    let
      frame = registry.viewPropertyDescriptor("button", "frame")
      title = registry.viewPropertyDescriptor("button", "title")
      background = registry.viewPropertyDescriptor("button", "background")
    check frame.declaredKind == "view"
    check frame.inherited
    check frame.nimTypeName == "Rect"
    check frame.acceptedKinds == {rvRect}
    check frame.getterSelectorName.endsWith("frame")
    check frame.setterSelectorName.endsWith("frame=")
    check frame.editable
    check title.declaredKind == "button"
    check not title.inherited
    check title.nimTypeName == "string"
    check background.aliasOf == "backgroundColor"
    check background.acceptedKinds == {rvColor}

    var
      propertyNames: seq[string]
      previousName: string
    for descriptor in registry.viewProperties("button"):
      propertyNames.add descriptor.name
      check previousName.len == 0 or previousName < descriptor.name
      previousName = descriptor.name
    check "frame" in propertyNames
    check "title" in propertyNames
    check "background" in propertyNames
    check registry.findViewPropertyDescriptor("button", "missing").isNone
    expect ResourceRegistryLookupError:
      discard registry.viewPropertyDescriptor("button", "missing")

  test "Sigils protocol properties are discovered and bound automatically":
    var registry = initNimKitResourceRegistry()

    check registry.acceptsViewProperty("view", "frame", rvRect)
    check registry.acceptsViewProperty("view", "tag", rvInt)
    check registry.acceptsViewProperty("view", "backgroundColor", rvColor)
    check registry.acceptsViewProperty("view", "background", rvColor)
    check registry.acceptsViewProperty("view", "alpha", rvFloat)
    check registry.acceptsViewProperty("control", "enabled", rvBool)
    check registry.acceptsViewProperty("button", "buttonType", rvString)
    check registry.acceptsViewProperty("textField", "textColor", rvColor)
    check registry.acceptsViewProperty("textField", "editable", rvBool)
    check registry.acceptsViewProperty("stackView", "distribution", rvString)
    check registry.acceptsViewProperty("imageView", "imageTint", rvColor)
    check registry.acceptsViewProperty("switchButton", "on", rvBool)
    check registry.acceptsViewProperty("progressIndicator", "value", rvFloat)
    check registry.acceptsViewProperty("box", "boxKind", rvString)
    check registry.acceptsViewProperty("splitView", "dividerThickness", rvFloat)
    check not registry.acceptsViewProperty("button", "state", rvBool)

    registry.registerViewKind(
      "resourceTestView",
      proc(frame: Rect): View =
        newResourceTestView(frame),
    )
    registerResourceEnumType[ResourceTestMode](registry, "ResourceTestMode")
    registry.registerViewProtocolProperties(
      "resourceTestView", ResourceTestViewProtocol
    )
    check registry.acceptsViewProperty("resourceTestView", "resourceMode", rvString)

    let view =
      ResourceTestView(registry.constructView("resourceTestView", rect(1, 2, 30, 40)))
    check registry.applyViewProperty(
      "resourceTestView",
      view,
      resourceProperty("resourceCount", resourceValue(42)),
      ResourcePropertyContext(),
    )
    check registry.applyViewProperty(
      "resourceTestView",
      view,
      resourceProperty("resourceMode", resourceValue("rtmExpanded")),
      ResourcePropertyContext(),
    )
    check view.resourceCount() == 42
    check view.resourceMode() == rtmExpanded

    let customProperty =
      registry.viewPropertyDescriptor("resourceTestView", "resourceCount")
    check customProperty.nimTypeName == "int"
    check customProperty.acceptedKinds == {rvInt}
    check customProperty.editable

  test "discovered properties preserve conversion and setter behavior":
    let
      registry = initNimKitResourceRegistry()
      context = ResourcePropertyContext(
        textFor: proc(key, fallback: string): string =
          if key == "localized.title": "Localized Title" else: fallback
      )
      view = newView()
      button = newButton()
      textField = newTextField()
      stackView = newStackView()
      switchButton = newSwitchButton()
      progress = newProgressIndicator()
      box = newBox()
      splitView = newSplitView()

    check registry.applyViewProperty(
      "view", view, resourceProperty("tag", resourceValue(19)), context
    )
    check registry.applyViewProperty(
      "view", view, resourceProperty("alpha", resourceValue(2.0'f32)), context
    )
    check registry.applyViewProperty(
      "button",
      button,
      resourceProperty(
        "title",
        resourceValue(
          resourceReference(rrLocalizedString, resourceId("localized.title"))
        ),
      ),
      context,
    )
    check registry.applyViewProperty(
      "button", button, resourceProperty("state", resourceValue("bsOn")), context
    )
    check registry.applyViewProperty(
      "textField",
      textField,
      resourceProperty("alignment", resourceValue("taRight")),
      context,
    )
    check registry.applyViewProperty(
      "textField",
      textField,
      resourceProperty("editable", resourceValue(false)),
      context,
    )
    check registry.applyViewProperty(
      "stackView",
      stackView,
      resourceProperty("spacing", resourceValue(-4.0'f32)),
      context,
    )
    check registry.applyViewProperty(
      "switchButton", switchButton, resourceProperty("on", resourceValue(true)), context
    )
    check registry.applyViewProperty(
      "progressIndicator",
      progress,
      resourceProperty("value", resourceValue(0.75'f32)),
      context,
    )
    check registry.applyViewProperty(
      "box", box, resourceProperty("title", resourceValue("Resource Group")), context
    )
    check registry.applyViewProperty(
      "splitView",
      splitView,
      resourceProperty("splitAxis", resourceValue("laVertical")),
      context,
    )

    check view.tag() == 19
    check view.alphaValue() == 1.0'f32
    check button.title() == "Localized Title"
    check button.state() == bsOn
    check textField.alignment() == taRight
    check not textField.editable()
    check stackView.spacing() == 0.0'f32
    check switchButton.on()
    check progress.value() == 0.75'f32
    check box.title() == "Resource Group"
    check splitView.splitAxis() == laVertical

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
    check decoded.bundle.layoutGuides[0].owningViewId == resourceId("root")
    check decoded.bundle.layoutConstraints[1].secondItem.kind == rliGuide
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
        LocalizedCatalogResource(
          id: resourceId("localization.a"), locale: "a", fallbackLocale: "b"
        ),
        LocalizedCatalogResource(
          id: resourceId("localization.b"), locale: "b", fallbackLocale: "a"
        ),
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

  test "layout validation reports endpoint anchor ownership and scalar errors":
    var bundle = sampleBundle()
    bundle.layoutConstraints.add initResourceLayoutConstraint(
      resourceId("invalid.layout"),
      resourceId("run.button"),
      resourceLayoutItem(resourceId("run.icon")),
      rlaLeft,
      resourceLayoutItem(resourceId("missing.guide"), rliGuide),
      rlaTop,
      multiplier = 0.0'f32,
      priority = 1200.0'f32,
    )

    let diagnostics = bundle.validateResources(initNimKitResourceRegistry())
    check diagnostics.diagnosticWithCode("resource.reference.unavailable")
    check diagnostics.diagnosticWithCode("resource.layout.anchorMismatch")
    check diagnostics.diagnosticWithCode("resource.layout.multiplierInvalid")
    check diagnostics.diagnosticWithCode("resource.layout.priorityInvalid")
    check diagnostics.diagnosticWithCode("resource.layout.ownerMismatch")

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
      widthConstraint = construction.instance.layoutConstraint(resourceId("run.width"))
      leadingConstraint =
        construction.instance.layoutConstraint(resourceId("icon.leading"))

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
    check widthConstraint.firstItem() == View(button)
    check widthConstraint.firstAttribute() == atWidth
    check widthConstraint.constant() == 140.0'f32
    check widthConstraint.active()
    check leadingConstraint.secondItem() == View(root)
    check leadingConstraint.constant() == 12.0'f32
    check not leadingConstraint.active()

    var guide: LayoutGuide
    check construction.instance.findLayoutGuide(resourceId("root.content"), guide)
    check guide.owningView() == View(root)
    check guide.insets() == insets(4, 8, 12, 16)

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
    expect ResourceLookupError:
      discard construction.instance.layoutConstraint(resourceId("missing"))

  test "resource documents provide read-only lookup paths and selection":
    let document = newResourceDocument(editorBundle())

    check document.revision == 0
    check document.hasLastValidRevision
    check document.lastValidRevision == 0
    check document.draftIsValid
    check document.contains(resourceId("editor.root"))
    check document.findView(resourceId("editor.button")).isSome
    check document.findView(resourceId("missing")).isNone
    check document.nodePath(resourceId("editor.button")) ==
      resourceNodePath(rnkView, resourceId("editor.button"))
    check document.diagnosticPath(
      resourceNodePath(rnkView, resourceId("editor.button"))
    ) == "views[0].children[0]"
    check document.findParentPath(
      resourceNodePath(rnkView, resourceId("editor.button"))
    ) == some(resourceNodePath(rnkView, resourceId("editor.root")))
    check document.viewProperty(resourceId("editor.button"), "title").value.stringValue ==
      "Original"

    var detached = document.view(resourceId("editor.button"))
    detached.kind = "textField"
    check document.view(resourceId("editor.button")).kind == "button"

    check document.selectResource(resourceId("editor.button"))
    check document.isSelected(resourceId("editor.button"))
    document.selectResources(
      [resourceId("editor.button"), resourceId("missing"), resourceId("editor.button")]
    )
    check document.selectedResourceIds == @[resourceId("editor.button")]

    var paths: seq[ResourceNodePath]
    for path in document:
      paths.add path
    check paths.len == 2

    let unchanged = document.setViewProperty(
      resourceId("editor.button"), resourceProperty("title", resourceValue("Original"))
    )
    check not unchanged.applied
    check unchanged.error == reeUnchanged
    check document.revision == 0
    check document.undoManager.undoCount == 0

    expect ResourceDocumentLookupError:
      discard document.view(resourceId("missing"))
    expect ResourceDocumentLookupError:
      discard document.nodePath(resourceId("missing"))

  test "resource document view edits validate revision and undo state":
    let
      document = newResourceDocument(editorBundle())
      labelId = resourceId("editor.label")
      rootId = resourceId("editor.root")
      label = initViewNodeResource(
        labelId,
        kind = "label",
        properties = [resourceProperty("stringValue", resourceValue("Status"))],
      )

    let inserted = document.insertView(label, rootId, 1)
    check inserted.applied
    check inserted.kind == rekInsert
    check inserted.error == reeNone
    check inserted.revision == 1
    check inserted.path == some(resourceNodePath(rnkView, labelId))
    check inserted.diagnosticPath == "views[0].children[1]"
    check document.view(labelId).kind == "label"
    check document.undoManager.undoCount == 1
    check document.lastValidRevision == 1

    let stablePath = document.nodePath(labelId)
    let moved =
      document.apply(initResourceViewMoveOperation(labelId, index = some(0.Natural)))
    check moved.applied
    check moved.kind == rekMove
    check document.nodePath(labelId) == stablePath
    check document.diagnosticPath(stablePath) == "views[0]"
    check document.findParentPath(stablePath).isNone

    var replacement = document.view(labelId)
    replacement.kind = "textField"
    replacement.properties =
      @[resourceProperty("stringValue", resourceValue("Editable"))]
    let replaced = document.replaceView(labelId, replacement)
    check replaced.applied
    check replaced.kind == rekReplace
    check document.view(labelId).kind == "textField"

    check document.selectResource(labelId)
    let removed = document.apply(initResourceViewRemoveOperation(labelId))
    check removed.applied
    check removed.kind == rekRemove
    check removed.path.isNone
    check removed.previousPath == some(stablePath)
    check not document.contains(labelId)
    check document.selectedResourceIds.len == 0

    check document.undoManager.performUndo()
    check document.contains(labelId)
    check document.view(labelId).kind == "textField"
    check document.revision == 5
    check document.undoManager.performRedo()
    check not document.contains(labelId)
    check document.revision == 6

  test "resource documents retain invalid drafts beside the last valid revision":
    let document = newResourceDocument(editorBundle())
    let validBundle = document.lastValidBundle
    let invalid = document.setViewProperty(
      resourceId("editor.root"),
      resourceProperty("missingProperty", resourceValue(true)),
    )

    check invalid.applied
    check invalid.diagnostics.hasErrors
    check not document.draftIsValid
    check document.revision == 1
    check document.lastValidRevision == 0
    check document.findViewProperty(resourceId("editor.root"), "missingProperty").isSome
    check validBundle.findView(resourceId("editor.root")).get().properties.len == 1
    check document.lastValidBundle
    .findView(resourceId("editor.root"))
    .get().properties.len == 1

    check document.undoManager.performUndo()
    check document.draftIsValid
    check document.revision == 2
    check document.lastValidRevision == 2
    check document.findViewProperty(resourceId("editor.root"), "missingProperty").isNone

    let duplicate = document.insertView(
      initViewNodeResource(resourceId("editor.button")), resourceId("editor.root")
    )
    check not duplicate.applied
    check duplicate.error == reeIdentifierDuplicate
    check document.revision == 2

    let cycle =
      document.moveView(resourceId("editor.root"), resourceId("editor.button"))
    check not cycle.applied
    check cycle.error == reeHierarchyCycle

  test "invalid initial resource documents report missing valid state":
    var bundle = editorBundle()
    bundle.views[0].kind = "missingKind"
    let document = newResourceDocument(bundle)

    check not document.draftIsValid
    check not document.hasLastValidRevision
    expect ResourceDocumentStateError:
      discard document.lastValidRevision
    expect ResourceDocumentStateError:
      discard document.lastValidBundle
