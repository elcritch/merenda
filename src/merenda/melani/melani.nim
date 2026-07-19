## Melani, Merenda's resource-document builder application.

import std/os

import merenda/nimkit

const
  MelaniNamespace* = "merenda.melani"
  MelaniRootResourceId* = ResourceId("melani.root")

proc melaniStarterBundle*(): ResourceBundle =
  ## Builds the editable starter document used for new Melani documents.
  result = initResourceBundle(MelaniNamespace)
  let
    heading = initViewNodeResource(
      resourceId("melani.heading"),
      kind = "label",
      properties = [
        resourceProperty("stringValue", resourceValue("Build a NimKit interface")),
        resourceProperty("alignment", resourceValue("taCenter")),
      ],
    )
    instructions = initViewNodeResource(
      resourceId("melani.instructions"),
      kind = "label",
      properties = [
        resourceProperty(
          "stringValue",
          resourceValue("Select a view, add widgets, and edit their properties."),
        ),
        resourceProperty("alignment", resourceValue("taCenter")),
      ],
    )
    nameField = initViewNodeResource(
      resourceId("melani.name"),
      kind = "textField",
      properties = [
        resourceProperty("stringValue", resourceValue("Editable text")),
        resourceProperty("editable", resourceValue(true)),
      ],
    )
    enabled = initViewNodeResource(
      resourceId("melani.enabled"),
      kind = "checkBox",
      properties = [
        resourceProperty("title", resourceValue("Enable live resource editing")),
        resourceProperty("state", resourceValue("bsOn")),
      ],
    )
    mode = initViewNodeResource(
      resourceId("melani.mode"),
      kind = "switchButton",
      properties = [resourceProperty("on", resourceValue(true))],
    )
    progress = initViewNodeResource(
      resourceId("melani.progress"),
      kind = "progressIndicator",
      properties = [resourceProperty("value", resourceValue(0.68'f32))],
    )
    root = initViewNodeResource(
      MelaniRootResourceId,
      kind = "stackView",
      properties = [
        resourceProperty("frame", resourceValue(rect(20, 20, 480, 330))),
        resourceProperty("orientation", resourceValue("laVertical")),
        resourceProperty("spacing", resourceValue(12.0'f32)),
        resourceProperty("edgeInsets", resourceValue(insets(24.0))),
        resourceProperty("backgroundColor", resourceValue(color(0.94, 0.97, 1.0, 1.0))),
      ],
      children = [heading, instructions, nameField, enabled, mode, progress],
    )
  result.views = @[root]

proc newMelaniDocument*(fileUrl = ""): ResourceEditorDocument =
  ## Creates a starter document or loads an existing canonical CBOR resource file.
  result = newResourceEditorDocument(melaniStarterBundle(), fileUrl = fileUrl)
  if fileUrl.len > 0 and fileExists(fileUrl):
    discard result.readFromFileUrl(fileUrl)
  elif fileUrl.len == 0:
    result.displayName = "Melani — Untitled Resources"
  discard result.resources().selectResource(MelaniRootResourceId)

proc runMelani*(fileUrl = "") =
  let
    app = sharedApplication()
    document = newMelaniDocument(fileUrl)
  discard document.showWindows(app)
  app.run()

when isMainModule:
  let arguments = commandLineParams()
  runMelani(
    if arguments.len > 0:
      arguments[0]
    else:
      ""
  )
