import std/[options, os, strutils, unittest]

import sigils/[core, selectors]

import merenda/nimkit
import merenda/nimkit/resources
import merenda/tekton

proc previewBundle(): ResourceBundle =
  result = initResourceBundle("tests.resource-preview")
  result.views =
    @[
      initViewNodeResource(
        resourceId("root"),
        properties = [resourceProperty("frame", resourceValue(rect(0, 0, 320, 180)))],
        children = [
          initViewNodeResource(
            resourceId("left"),
            properties =
              [resourceProperty("frame", resourceValue(rect(0, 0, 150, 180)))],
            children = [
              initViewNodeResource(
                resourceId("action"),
                kind = "button",
                properties = [
                  resourceProperty("frame", resourceValue(rect(10, 12, 100, 32))),
                  resourceProperty("title", resourceValue("Original")),
                ],
              )
            ],
          ),
          initViewNodeResource(
            resourceId("right"),
            properties =
              [resourceProperty("frame", resourceValue(rect(160, 0, 150, 180)))],
          ),
        ],
      )
    ]
  result.layoutGuides =
    @[
      initResourceLayoutGuide(
        resourceId("root.content"), resourceId("root"), insets(8.0)
      )
    ]
  result.layoutConstraints =
    @[
      initResourceLayoutConstraint(
        resourceId("action.width"),
        resourceId("root"),
        resourceLayoutItem(resourceId("action")),
        rlaWidth,
        constant = 100.0'f32,
      )
    ]
  result.controllers =
    @[
      initControllerNodeResource(
        resourceId("root.controller"),
        resourceId("root"),
        children = [
          initControllerNodeResource(
            resourceId("action.controller"), resourceId("action")
          )
        ],
      )
    ]
  result.commands =
    @[
      CommandResource(
        id: resourceId("activate"),
        selector: "performClick",
        targetKind: rctExplicit,
        targetId: resourceId("action"),
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
              id: resourceId("activate.item"),
              title: resourceText("Activate"),
              commandId: resourceId("activate"),
            )
          ],
      )
    ]

proc movedBundle(): ResourceBundle =
  result = previewBundle()
  var button = result.views[0].children[0].children[0]
  button.properties[1] = resourceProperty("title", resourceValue("Moved"))
  result.views[0].children[0].children.setLen(0)
  result.views[0].children[1].children.add button

proc hasDiagnostic(diagnostics: ResourceDiagnostics, code: string): bool =
  for diagnostic in diagnostics:
    if diagnostic.code == code:
      return true

suite "Tekton identity-preserving resource previews":
  test "reconciliation preserves compatible view and controller identities":
    let
      registry = initNimKitResourceRegistry()
      preview = newResourcePreview(registry)
      host = newView(frame = rect(0, 0, 400, 240))
      initial = preview.update(previewBundle(), 0, host)
      button = preview.view(resourceId("action"))
      controller = preview.controller(resourceId("action.controller"))
      initialConstraint = preview.layoutConstraint(resourceId("action.width"))

    check initial.applied
    check preview.revision() == 0
    check button.superview() == preview.view(resourceId("left"))
    check host.subviews() == @[preview.view(resourceId("root"))]
    check initialConstraint.firstItem() == button
    check initialConstraint.active()

    let reconciled = preview.update(movedBundle(), 1, host)

    check reconciled.applied
    check preview.revision() == 1
    check preview.view(resourceId("action")) == button
    check preview.controller(resourceId("action.controller")) == controller
    check button.superview() == preview.view(resourceId("right"))
    check Button(button).title() == "Moved"
    check controller.view() == button
    check preview.menu(resourceId("main.menu")).itemModels()[0].target ==
      DynamicAgent(button)
    let reconciledConstraint = preview.layoutConstraint(resourceId("action.width"))
    check reconciledConstraint != initialConstraint
    check not initialConstraint.active()
    check reconciledConstraint.firstItem() == button
    check reconciledConstraint.active()

    var foundMove = false
    for change in reconciled.changes:
      if change.resourceId == resourceId("action"):
        check rpckReused in change.kinds
        check rpckMoved in change.kinds
        check rpckUpdated in change.kinds
        foundMove = true
    check foundMove

  test "getter conversion hit mapping and geometry stay resource-addressed":
    let
      preview = newResourcePreview()
      host = newView(frame = rect(0, 0, 400, 240))
    check preview.update(previewBundle(), 0, host).applied

    let
      button = preview.view(resourceId("action"))
      implementationView = newView(frame = rect(2, 2, 12, 12))
    button.addSubview(implementationView)

    let title = preview.readViewProperty(resourceId("action"), "title")
    check title.read
    check title.value == resourceValue("Original")
    check preview.resourceIdForView(implementationView) == some(resourceId("action"))

    let geometry = preview.geometry(resourceId("action"), host)
    check geometry.found
    check geometry.view == button
    check geometry.bounds == button.bounds()

    let point = button.pointToView(initPoint(4, 4), host)
    let hit = preview.hitTest(host, point)
    check hit.found
    check hit.resourceId == resourceId("action")
    check hit.resourceView == button
    check hit.geometry.frameInReferenceView == geometry.frameInReferenceView

  test "kind changes replace identities and prune stale mappings":
    let
      preview = newResourcePreview()
      host = newView(frame = rect(0, 0, 400, 240))
    check preview.update(previewBundle(), 0, host).applied
    let
      oldButton = preview.view(resourceId("action"))
      oldLeft = preview.view(resourceId("left"))

    var changed = movedBundle()
    changed.commands.setLen(0)
    changed.menus.setLen(0)
    changed.views[0].children.delete(0)
    changed.views[0].children[0].children[0] = initViewNodeResource(
      resourceId("action"),
      kind = "label",
      properties = [
        resourceProperty("frame", resourceValue(rect(12, 14, 120, 28))),
        resourceProperty("stringValue", resourceValue("Replacement")),
      ],
    )
    changed.views[0].children[0].children.add initViewNodeResource(
      resourceId("inserted"), kind = "button"
    )

    let update = preview.update(changed, 1, host)
    check update.applied
    check preview.view(resourceId("action")) != oldButton
    check Label(preview.view(resourceId("action"))).stringValue() == "Replacement"
    check preview.findView(resourceId("left")).isNil
    check oldLeft.superview().isNil
    check not preview.findView(resourceId("inserted")).isNil
    check preview.resourceIdForView(oldButton).isNone

  test "failed property application leaves revision graph and mappings untouched":
    let
      preview = newResourcePreview()
      host = newView(frame = rect(0, 0, 400, 240))
    check preview.update(previewBundle(), 0, host).applied
    let
      button = preview.view(resourceId("action"))
      root = preview.view(resourceId("root"))
      failingSetter = selector[string, tuple[]]("ButtonProtocol.title=")
      fail: DynamicMethod = proc(self: DynamicAgent, invocation: var Invocation) =
        discard self
        discard invocation
        raise newException(ValueError, "intentional preview setter failure")
    discard DynamicAgent(button).replaceMethod(failingSetter, fail)

    var changed = movedBundle()
    changed.views[0].children.add initViewNodeResource(
      resourceId("uncommitted"), kind = "label"
    )
    let failed = preview.update(changed, 1, host)

    check not failed.applied
    check failed.diagnostics.hasDiagnostic("resource.preview.propertyApplyFailed")
    check preview.revision() == 0
    check preview.view(resourceId("action")) == button
    check Button(button).title() == "Original"
    check button.superview() == preview.view(resourceId("left"))
    check host.subviews() == @[root]
    check preview.findView(resourceId("uncommitted")).isNil

  test "option title edits preserve combo values and selection through replacement":
    for tag in ["nk-combo-box", "some-app-picker"]:
      var registry = initNimKitResourceRegistry()
      registry.registerViewKind(
        "some-app-picker",
        proc(frame: Rect): View =
          newComboBox(frame = frame),
        baseKind = "comboBox",
      )
      let
        preview = newResourcePreview(registry)
        initial = parseGuiResourceBundle(
          "<nk-stack-view id=root><" & tag & " id=picker>" &
            "<option value=nim>Nim</option><option value=c selected>C</option>" & "</" &
            tag & "></nk-stack-view>",
          registry,
        )
      require initial.loaded
      require preview.update(initial.bundle, 0).applied
      let
        oldPicker = preview.view(resourceId("picker"))
        root = preview.view(resourceId("root"))
        changed = parseGuiResourceBundle(
          "<nk-stack-view id=root><" & tag & " id=picker>" &
            "<option value=nim>Nim language</option><option value=c selected>C language</option>" &
            "</" & tag & "></nk-stack-view>",
          registry,
        )
      require changed.loaded
      let update = preview.update(changed.bundle, 1)
      require update.applied
      check not update.diagnostics.hasErrors
      let picker = ComboBox(preview.view(resourceId("picker")))
      check picker != oldPicker
      check preview.view(resourceId("root")) == root
      check picker.superview == root
      check oldPicker.superview.isNil
      check picker.itemAtIndex(1) == "C language"
      check picker.itemObjectValueAtIndex(0) == toObj("nim")
      check picker.itemObjectValueAtIndex(1) == toObj("c")
      check picker.selectedIndex == 1

  test "changing option counts commits a complete combo without partial updates":
    let
      preview = newResourcePreview()
      initial = parseGuiResourceBundle(
        "<select id=picker><option value=nim>Nim</option></select>"
      )
    require initial.loaded
    require preview.update(initial.bundle, 0).applied
    let
      original = preview.view(resourceId("picker"))
      changed = parseGuiResourceBundle(
        "<select id=picker><option value=nim>Nim</option>" &
          "<option value=c>C</option><option value=other selected>Other</option></select>"
      )
    require changed.loaded
    let update = preview.update(changed.bundle, 1)
    require update.applied
    check not update.diagnostics.hasErrors
    let picker = ComboBox(preview.view(resourceId("picker")))
    check picker != original
    check picker.numberOfItems == 3
    check picker.itemObjectValueAtIndex(2) == toObj("other")
    check picker.selectedIndex == 2
    check preview.revision == 1

  test "label style edits preserve explicit alignment and CSS classes":
    let
      preview = newResourcePreview()
      source =
        """<nk-label id=heading data-label-style=title data-alignment=right
                          class=accent>Heading</nk-label>"""
      initial = parseGuiResourceBundle(source)
    require initial.loaded
    require preview.update(initial.bundle, 0).applied
    let original = preview.view(resourceId("heading"))
    let changed = parseGuiResourceBundle(source.replace("style=title", "style=heading"))
    require changed.loaded
    require preview.update(changed.bundle, 1).applied
    let heading = Label(preview.view(resourceId("heading")))
    check heading != original
    check heading.labelStyle == lsHeading
    check heading.alignment == taRight
    check LabelHeadingStyleClass in heading.styleClasses
    check "accent" in heading.styleClasses

  test "document appends apply label defaults before inherited explicit overrides":
    for kind in ["label", "some-app-caption"]:
      var registry = initNimKitResourceRegistry()
      registry.registerViewKind(
        "some-app-caption",
        proc(frame: Rect): View =
          newLabel(frame = frame),
        baseKind = "label",
      )
      registry.registerViewPropertyAlias("label", "textStyle", "labelStyle")
      var bundle = initResourceBundle()
      let id = resourceId("heading")
      bundle.views =
        @[
          initViewNodeResource(
            id,
            kind = kind,
            properties = [
              resourceProperty("alignment", resourceValue("taRight")),
              resourceProperty("styleClasses", resourceValue(@["accent"])),
              resourceProperty("stringValue", resourceValue("Heading")),
            ],
          )
        ]
      let
        document = newResourceDocument(bundle, registry)
        preview = newResourcePreview(registry)
      require preview.update(document.bundle, document.revision).applied
      let original = preview.view(id)
      require document.setViewProperty(
        id, resourceProperty("textStyle", resourceValue("lsTitle"))
      ).applied
      require preview.update(document.bundle, document.revision).applied
      let heading = Label(preview.view(id))
      check heading != original
      check heading.labelStyle == lsTitle
      check heading.alignment == taRight
      check heading.styleClasses == @["accent"]

      # The fast preflight path must also use the same setter order.
      require document.setViewProperty(
        id, resourceProperty("stringValue", resourceValue("Updated heading"))
      ).applied
      require document.setViewProperty(
        id, resourceProperty("alignment", resourceValue("taLeft"))
      ).applied
      require document.setViewProperty(
        id, resourceProperty("styleClasses", resourceValue(@["updated-accent"]))
      ).applied
      require preview.update(document.bundle, document.revision).applied
      check preview.view(id) == heading
      check heading.stringValue == "Updated heading"
      check heading.alignment == taLeft
      check heading.styleClasses == @["updated-accent"]

  test "document appends build combo items before values and selection":
    var bundle = initResourceBundle()
    let id = resourceId("picker")
    bundle.views =
      @[
        initViewNodeResource(
          id,
          kind = "comboBox",
          properties = [
            resourceProperty("items", resourceValue(@["Nim", "C"])),
            resourceProperty("itemValues", resourceValue(@["nim", "c"])),
            resourceProperty("selectedIndex", resourceValue(1)),
          ],
        )
      ]
    let
      document = newResourceDocument(bundle)
      preview = newResourcePreview()
    require preview.update(document.bundle, document.revision).applied
    let original = preview.view(id)
    require document.removeViewProperty(id, "items").applied
    require document.setViewProperty(
      id, resourceProperty("items", resourceValue(@["Nim language", "C language"]))
    ).applied
    require preview.update(document.bundle, document.revision).applied
    let picker = ComboBox(preview.view(id))
    check picker != original
    check picker.itemAtIndex(1) == "C language"
    check picker.itemObjectValueAtIndex(0) == toObj("nim")
    check picker.itemObjectValueAtIndex(1) == toObj("c")
    check picker.selectedIndex == 1

  test "group content identity and authored background survive structural reconciliation":
    let
      preview = newResourcePreview()
      source =
        """<nk-stack-view id=root>
  <nk-group id=group data-title=Account>
    <nk-stack-view id=content data-background-color="#123456" data-spacing=8>
      <button id=save>Save</button>
    </nk-stack-view>
  </nk-group>
</nk-stack-view>"""
      initial = parseGuiResourceBundle(source)
    require initial.loaded
    require preview.update(initial.bundle, 0).applied
    let
      group = Box(preview.view(resourceId("group")))
      content = preview.view(resourceId("content"))
      background = content.background
      changed = parseGuiResourceBundle(
        source.replace(
          "<button id=save>Save</button>",
          "<button id=save>Save</button><button id=reset>Reset</button>",
        )
      )
    require changed.loaded
    let update = preview.update(changed.bundle, 1)
    require update.applied
    check not update.diagnostics.hasErrors
    check preview.view(resourceId("group")) == group
    check preview.view(resourceId("content")) == content
    check group.contentView == content
    check content.superview == group
    check content.background == background
    check StackView(content).arrangedSubviews.len == 2

  test "changed image assets update reused image views through resource ids":
    var initialBundle = initResourceBundle("tests.resource-preview-assets")
    initialBundle.images =
      @[
        ImageAssetResource(
          id: resourceId("asset"),
          sourceKind: risFile,
          path: "shadow-button.png",
          cachePolicy: ricNever,
        )
      ]
    initialBundle.views =
      @[
        initViewNodeResource(
          resourceId("image"),
          kind = "imageView",
          properties = [
            resourceProperty(
              "image", resourceValue(resourceReference(rrImage, resourceId("asset")))
            )
          ],
        )
      ]

    let
      context =
        initResourceInstantiationContext(assetBasePath = getCurrentDir() / "data")
      options = initResourceValidationOptions(assetBasePath = getCurrentDir() / "data")
      preview = newResourcePreview(initNimKitResourceRegistry(), context, options)
      host = newView(frame = rect(0, 0, 200, 100))
    check preview.update(initialBundle, 0, host).applied
    let
      imageView = preview.view(resourceId("image"))
      firstImage = ImageView(imageView).image()

    var changedBundle = initialBundle
    changedBundle.images[0].path = "shadow-button-right.png"
    let changed = preview.update(changedBundle, 1, host)

    check changed.applied
    check preview.view(resourceId("image")) == imageView
    check cast[pointer](ImageView(imageView).image()) != cast[pointer](firstImage)
    check cast[pointer](preview.image(resourceId("asset"))) ==
      cast[pointer](ImageView(imageView).image())

    let installedImage = ImageView(imageView).image()
    var unavailableBundle = changedBundle
    unavailableBundle.images[0].path = "missing-preview-asset.png"
    let unavailable = preview.update(unavailableBundle, 2, host)
    check not unavailable.applied
    check preview.revision() == 1
    check preview.view(resourceId("image")) == imageView
    check cast[pointer](ImageView(imageView).image()) == cast[pointer](installedImage)
