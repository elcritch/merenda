import merenda/nimkit
import merenda/nimkit/resources

proc resourceBundle(): ResourceBundle =
  result = initResourceBundle("examples.resource-ui")
  let
    message = initViewNodeResource(
      resourceId("message"),
      kind = "label",
      properties =
        [resourceProperty("stringValue", resourceValue("Loaded from CBOR resources"))],
    )
    closeButton = initViewNodeResource(
      resourceId("close"),
      kind = "button",
      properties = [
        resourceProperty("title", resourceValue("Close")),
        resourceProperty("frame", resourceValue(rect(0, 0, 100, 32))),
      ],
    )
    root = initViewNodeResource(
      resourceId("root"),
      kind = "stackView",
      properties = [
        resourceProperty("orientation", resourceValue("laVertical")),
        resourceProperty("spacing", resourceValue(12.0'f32)),
        resourceProperty("edgeInsets", resourceValue(insets(24, 24, 24, 24))),
      ],
      children = [message, closeButton],
    )
  result.views = @[root]
  result.controllers =
    @[initControllerNodeResource(resourceId("controller"), resourceId("root"))]
  result.windows =
    @[
      WindowResource(
        id: resourceId("window"),
        title: resourceText("Resource UI"),
        frame: rect(160, 140, 420, 220),
        controllerId: resourceId("controller"),
        initialFirstResponderId: resourceId("close"),
      )
    ]

when isMainModule:
  let
    encoded = resourceBundle().encodeResourceBundle()
    loaded = decodeResourceBundle(encoded)
  if not loaded.loaded:
    for diagnostic in loaded.diagnostics:
      echo diagnostic.code, ": ", diagnostic.message
    quit 1

  let construction = loaded.bundle.instantiateResources()
  if not construction.instantiated:
    for diagnostic in construction.diagnostics:
      echo diagnostic.code, ": ", diagnostic.message
    quit 1

  let
    app = newApplication("Resource UI")
    window = construction.instance.window(resourceId("window"))
  app.runWindow(window, window.contentView)
