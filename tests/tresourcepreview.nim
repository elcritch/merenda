import std/[options, os, unittest]

import sigils/[core, selectors]

import merenda/nimkit
import merenda/nimkit/resources

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

suite "NimKit identity-preserving resource previews":
  test "reconciliation preserves compatible view and controller identities":
    let
      registry = initNimKitResourceRegistry()
      preview = newResourcePreview(registry)
      host = newView(frame = rect(0, 0, 400, 240))
      initial = preview.update(previewBundle(), 0, host)
      button = preview.view(resourceId("action"))
      controller = preview.controller(resourceId("action.controller"))

    check initial.applied
    check preview.revision() == 0
    check button.superview() == preview.view(resourceId("left"))
    check host.subviews() == @[preview.view(resourceId("root"))]

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
