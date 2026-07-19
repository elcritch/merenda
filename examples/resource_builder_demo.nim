import std/os

import merenda/nimkit

proc demoResourceBundle(): ResourceBundle =
  result = initResourceBundle("examples.resource-builder")
  let
    heading = initViewNodeResource(
      resourceId("demo.heading"),
      kind = "label",
      properties = [
        resourceProperty("stringValue", resourceValue("Interactive resource preview")),
        resourceProperty("alignment", resourceValue("taCenter")),
      ],
    )
    nameField = initViewNodeResource(
      resourceId("demo.name"),
      kind = "textField",
      properties = [
        resourceProperty("stringValue", resourceValue("Edit me in the inspector")),
        resourceProperty("editable", resourceValue(true)),
      ],
    )
    enabled = initViewNodeResource(
      resourceId("demo.enabled"),
      kind = "checkBox",
      properties = [
        resourceProperty("title", resourceValue("Live resource editing")),
        resourceProperty("state", resourceValue("bsOn")),
      ],
    )
    action = initViewNodeResource(
      resourceId("demo.action"),
      kind = "button",
      properties = [resourceProperty("title", resourceValue("Build Preview"))],
    )
    root = initViewNodeResource(
      resourceId("demo.root"),
      kind = "stackView",
      properties = [
        resourceProperty("frame", resourceValue(rect(28, 28, 430, 260))),
        resourceProperty("orientation", resourceValue("laVertical")),
        resourceProperty("spacing", resourceValue(12.0'f32)),
        resourceProperty("edgeInsets", resourceValue(insets(24.0))),
        resourceProperty("backgroundColor", resourceValue(color(0.94, 0.97, 1.0, 1.0))),
      ],
      children = [heading, nameField, enabled, action],
    )
  result.views = @[root]

when isMainModule:
  let
    app = sharedApplication()
    savePath = getTempDir() / "nimkit-resource-builder-demo.cbor"
    document = newResourceEditorDocument(demoResourceBundle(), fileUrl = savePath)
  document.displayName = "NimKit Resource Builder Demo"
  discard document.resources().selectResource(resourceId("demo.action"))
  discard document.showWindows(app)
  app.run()
