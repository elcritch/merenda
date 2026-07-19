## Tekton, Merenda's resource-document builder application.

import std/os

import merenda/nimkit
import merenda/tekton/editor

const
  TektonNamespace* = "merenda.tekton"
  TektonRootResourceId* = ResourceId("tekton.root")

proc tektonStarterBundle*(): ResourceBundle =
  ## Builds the editable starter document used for new Tekton documents.
  result = initResourceBundle(TektonNamespace)
  let
    heading = initViewNodeResource(
      resourceId("tekton.heading"),
      kind = "label",
      properties = [
        resourceProperty("stringValue", resourceValue("Build a NimKit interface")),
        resourceProperty("alignment", resourceValue("taCenter")),
      ],
    )
    instructions = initViewNodeResource(
      resourceId("tekton.instructions"),
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
      resourceId("tekton.name"),
      kind = "textField",
      properties = [
        resourceProperty("stringValue", resourceValue("Editable text")),
        resourceProperty("editable", resourceValue(true)),
      ],
    )
    enabled = initViewNodeResource(
      resourceId("tekton.enabled"),
      kind = "checkBox",
      properties = [
        resourceProperty("title", resourceValue("Enable live resource editing")),
        resourceProperty("state", resourceValue("bsOn")),
      ],
    )
    mode = initViewNodeResource(
      resourceId("tekton.mode"),
      kind = "switchButton",
      properties = [resourceProperty("on", resourceValue(true))],
    )
    progress = initViewNodeResource(
      resourceId("tekton.progress"),
      kind = "progressIndicator",
      properties = [resourceProperty("value", resourceValue(0.68'f32))],
    )
    root = initViewNodeResource(
      TektonRootResourceId,
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

proc newTektonDocument*(fileUrl = ""): ResourceEditorDocument =
  ## Creates a starter document or loads an existing canonical CBOR resource file.
  result = newResourceEditorDocument(tektonStarterBundle(), fileUrl = fileUrl)
  if fileUrl.len > 0 and fileExists(fileUrl):
    discard result.readFromFileUrl(fileUrl)
  elif fileUrl.len == 0:
    result.displayName = "Tekton — Untitled Resources"
  discard result.resources().selectResource(TektonRootResourceId)

proc runTekton*(fileUrl = "") =
  let
    app = sharedApplication()
    document = newTektonDocument(fileUrl)
  discard document.showWindows(app)
  app.run()

when isMainModule:
  let arguments = commandLineParams()
  runTekton(
    if arguments.len > 0:
      arguments[0]
    else:
      ""
  )
