import std/[algorithm, options, os, unittest]

import merenda/nimkit
import merenda/tekton
import merenda/tekton/tkapp

proc propertyRowIndex(editor: ResourceEditor, name: string): int =
  for index, row in editor.propertyRows():
    if row.descriptor.name == name:
      return index
  -1

suite "Tekton resource builder application":
  test "starter documents expose a valid editable workspace":
    let document = newTektonDocument()
    check document.displayName() == "Tekton — Untitled Resources"
    check document.resources().draftIsValid()
    check document.resources().selectedResourceIds() == @[TektonRootResourceId]
    check document.resources().view(TektonRootResourceId).kind == "stackView"
    check document.resources().view(TektonRootResourceId).children.len == 6

  test "inspector uses choices checkboxes and popup colors":
    let
      document = newTektonDocument()
      editor = newResourceEditor(document)
      valueColumn = editor.propertyInspector().columnWithIdentifier("value")

    check editor.selectResource(resourceId("tekton.heading"))
    let alignmentRow = editor.propertyRowIndex("alignment")
    check alignmentRow >= 0
    check editor.propertyRows()[alignmentRow].propertyEditorKind() == rpekComboBox
    let alignmentEditor =
      ComboBox(editor.propertyInspector().tableCellView(alignmentRow, valueColumn))
    check not alignmentEditor.isNil
    let rightIndex = alignmentEditor.indexOfItem("taRight")
    check rightIndex >= 0
    alignmentEditor.activateItemAtIndex(rightIndex)
    check document
    .resources()
    .viewProperty(resourceId("tekton.heading"), "alignment").value.stringValue ==
      "taRight"

    check editor.selectResource(resourceId("tekton.name"))
    let editableRow = editor.propertyRowIndex("editable")
    check editableRow >= 0
    check editor.propertyRows()[editableRow].propertyEditorKind() == rpekCheckBox
    let editableEditor =
      Button(editor.propertyInspector().tableCellView(editableRow, valueColumn))
    check editableEditor.state() == bsOn
    editableEditor.state = bsOff
    check editableEditor.sendAction()
    check not document
    .resources()
    .viewProperty(resourceId("tekton.name"), "editable").value.boolValue

    check editor.selectResource(TektonRootResourceId)
    let colorRow = editor.propertyRowIndex("backgroundColor")
    check colorRow >= 0
    check editor.propertyRows()[colorRow].propertyEditorKind() == rpekColorWell
    let colorEditor =
      PopupColorWell(editor.propertyInspector().tableCellView(colorRow, valueColumn))
    let redIndex = colorEditor.choices().find(
        initPopupColorChoice("Red", color(0.88, 0.24, 0.26, 1.0))
      )
    check redIndex >= 0
    check colorEditor.activateColorAtIndex(redIndex)
    check document
    .resources()
    .viewProperty(TektonRootResourceId, "backgroundColor").value.colorValue ==
      color(0.88, 0.24, 0.26, 1.0)

  test "palette adds siblings for leaf selections and Delete removes them":
    let
      document = newTektonDocument()
      editor = newResourceEditor(document)
    check editor.selectResource(resourceId("tekton.heading"))
    let button = editor.paletteButton("button")
    check not button.isNil
    check button.sendAction()
    let insertedId = resourceId("button.1")
    check document.resources().contains(insertedId)
    let insertedPath = document.resources().nodePath(insertedId)
    check document.resources().findParentPath(insertedPath) ==
      some(resourceNodePath(rnkView, TektonRootResourceId))
    check document.resources().selectedResourceIds() == @[insertedId]

    let window = editor.newResourceEditorWindow()
    check window.dispatchKeyDown(KeyEvent(key: keyDelete))
    check not document.resources().contains(insertedId)
    check document.resources().selectedResourceIds() == @[resourceId("tekton.progress")]

  test "preview roots keep authored positions across layout and edits":
    let
      document = newTektonDocument()
      editor = newResourceEditor(document)
      initial = editor.previewGeometry(TektonRootResourceId).frameInReferenceView
      window = editor.newResourceEditorWindow()
    discard window.buildRenders()
    let laidOut = editor.previewGeometry(TektonRootResourceId).frameInReferenceView
    check initial.origin == initPoint(20, 20)
    check laidOut.origin == initial.origin

    let changed = editor.commitPropertyText(TektonRootResourceId, "spacing", "16")
    check changed.edit.applied
    check editor.previewGeometry(TektonRootResourceId).frameInReferenceView.origin ==
      initial.origin

  test "existing CBOR documents load into the Tekton document type":
    let path = getTempDir() / ("tekton-resource-" & $getCurrentProcessId() & ".cbor")
    defer:
      if fileExists(path):
        removeFile(path)
    var bundle = tektonStarterBundle()
    bundle.namespace = "tests.tekton.loaded"
    writeFile(path, bundle.encodeResourceBundle())

    let document = newTektonDocument(path)
    check document.resources().bundle().namespace == "tests.tekton.loaded"
    check document.resources().selectedResourceIds() == @[TektonRootResourceId]
