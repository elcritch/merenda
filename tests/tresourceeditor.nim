import std/[options, os, unittest]

import merenda/nimkit

proc editorBundle(): ResourceBundle =
  result = initResourceBundle("tests.resource-editor-window")
  result.views =
    @[
      initViewNodeResource(
        resourceId("editor.root"),
        kind = "stackView",
        properties = [
          resourceProperty("frame", resourceValue(rect(16, 16, 360, 220))),
          resourceProperty("orientation", resourceValue("laVertical")),
          resourceProperty("spacing", resourceValue(8.0'f32)),
        ],
        children = [
          initViewNodeResource(
            resourceId("editor.button"),
            kind = "button",
            properties = [resourceProperty("title", resourceValue("Original"))],
          )
        ],
      )
    ]

proc propertyRow(
    editor: ResourceEditor, name: string
): Option[ResourceEditorPropertyRow] =
  for row in editor.propertyRows():
    if row.descriptor.name == name:
      return some(row)

suite "NimKit resource editor":
  test "generic resource values parse and retain invalid text":
    let
      parsedRect = parseResourceValue("1, 2, 30, 40", {rvRect})
      parsedBool = parseResourceValue("false", {rvBool})
      invalidBool = parseResourceValue("not a bool", {rvBool})

    check parsedRect.parsed
    check parsedRect.value.rectValue == rect(1, 2, 30, 40)
    check parsedBool.parsed
    check not parsedBool.value.boolValue
    check not invalidBool.parsed
    check invalidBool.value.kind == rvString
    check invalidBool.value.stringValue == "not a bool"

  test "editor exposes palette hierarchy inspector and stable valid preview":
    let
      document = newResourceEditorDocument(editorBundle())
      editor = newResourceEditor(document)
      buttonId = resourceId("editor.button")

    check editor.paletteKinds() == @ResourceEditorPaletteKinds
    check editor.hierarchyView().outlineItemIdentifiers().len == 2
    check editor.hasPreview()
    check editor.previewRevision() == 0
    check Button(editor.previewInstance().view(buttonId)).title() == "Original"

    let window = editor.newResourceEditorWindow()
    discard window.buildRenders()
    check window.contentView() == editor.rootView()
    check editor.previewSurface().frame().size.width > 0.0

    check editor.selectResource(buttonId)
    check editor.hasPreviewSelection()
    check editor.propertyRow("title").get().text == "Original"

    let invalid = editor.commitPropertyText(buttonId, "enabled", "not a bool")
    check invalid.edit.applied
    check not invalid.parsed
    check not document.resources().draftIsValid()
    check document.resources().revision() == 1
    check editor.previewRevision() == 0
    check editor.propertyRow("enabled").get().text == "not a bool"
    check editor.diagnosticRows().len > 0
    check editor.hasPreviewSelection()

    let valid = editor.commitPropertyText(buttonId, "enabled", "false")
    check valid.edit.applied
    check valid.parsed
    check document.resources().draftIsValid()
    check editor.previewRevision() == 2
    check not Button(editor.previewInstance().view(buttonId)).enabled()
    check document.resources().selectedResourceIds() == @[buttonId]
    check document.isDocumentEdited()

  test "palette insertion commits through the document and restores selection":
    let
      document = newResourceEditorDocument(editorBundle())
      editor = newResourceEditor(document)

    check editor.selectResource(resourceId("editor.root"))
    let inserted = editor.insertViewKind("label")
    check inserted.applied
    check inserted.resourceId == resourceId("label.1")
    check document.resources().view(resourceId("label.1")).kind == "label"
    check document.resources().selectedResourceIds() == @[resourceId("label.1")]
    check editor.previewInstance().findView(resourceId("label.1")).isNil == false
    check editor.hierarchyView().selectedItemIdentifier() == "label.1"

  test "CBOR document save and revert share undo clean state":
    let path =
      getTempDir() / ("nimkit-resource-editor-" & $getCurrentProcessId() & ".cbor")
    if fileExists(path):
      removeFile(path)
    defer:
      if fileExists(path):
        removeFile(path)

    let
      document = newResourceEditorDocument(editorBundle(), fileUrl = path)
      editor = newResourceEditor(document)
      buttonId = resourceId("editor.button")

    check document.undoManagerFor() == document.resources().undoManager()
    check document.undoManagerFor().isAtCleanState()
    check document.save()
    check fileExists(path)
    check decodeResourceBundle(readFile(path)).loaded
    check document.undoManagerFor().isAtCleanState()
    check not document.isDocumentEdited()

    discard editor.commitPropertyText(buttonId, "title", "Changed")
    check document.isDocumentEdited()
    check document.resources().viewProperty(buttonId, "title").value.stringValue ==
      "Changed"
    check document.revert()
    check document.resources().viewProperty(buttonId, "title").value.stringValue ==
      "Original"
    check Button(editor.previewInstance().view(buttonId)).title() == "Original"
    check document.undoManagerFor().isAtCleanState()
    check not document.isDocumentEdited()
