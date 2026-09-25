import std/[options, os, unittest]

import merenda/nimkit
import merenda/tekton

proc layoutBundle(): ResourceBundle =
  result = initResourceBundle("tests.tekton.layout-authoring")
  result.views =
    @[
      initViewNodeResource(
        resourceId("canvas"),
        properties = [resourceProperty("frame", resourceValue(rect(20, 20, 400, 300)))],
        children = [
          initViewNodeResource(
            resourceId("child"),
            "button",
            [
              resourceProperty("frame", resourceValue(rect(20, 20, 180, 44))),
              resourceProperty("title", resourceValue("Build")),
            ],
          )
        ],
      )
    ]

proc rowIndex(editor: ResourceEditor, name: string): int =
  for index, row in editor.propertyRows():
    if row.descriptor.name == name:
      return index
  -1

suite "Tekton layout authoring":
  test "typed record operations validate identity and support grouped undo":
    let
      document = newResourceDocument(layoutBundle())
      owner = resourceId("canvas")
      first = initResourceLayoutGuide(resourceId("guide.1"), owner, insets(8.0))
      second = initResourceLayoutGuide(resourceId("guide.2"), owner, insets(16.0))
      manager = document.undoManager()
    manager.beginUndoGrouping()
    check document.insertResource(first).applied
    check document.insertResource(second).applied
    check manager.endUndoGrouping()
    check document.draftIsValid()
    check document.insertResource(first).error == reeIdentifierDuplicate
    check document.insertResource(initResourceLayoutGuide(resourceId("canvas"), owner)).error ==
      reeIdentifierDuplicate
    check document.insertResource(initResourceLayoutGuide(ResourceId(""), owner)).error ==
      reeIdentifierMissing
    check document.insertResource(
      initResourceLayoutGuide(resourceId("outside"), owner), some(9.Natural)
    ).error == reeIndexOutOfBounds
    check document.replaceResource(first.id, second).error == reeIdentifierMismatch
    check document.moveResource(second.id, 2).error == reeIndexOutOfBounds
    check manager.performUndo()
    check document.bundle().layoutGuides.len == 0
    check manager.performRedo()
    check document.bundle().layoutGuides.len == 2
    check document.moveResource(second.id, 0).applied
    check document.bundle().layoutGuides[0].id == second.id
    check manager.performUndo()
    check document.bundle().layoutGuides[0].id == first.id
    check document.removeResource(first.id).applied
    check not document.contains(first.id)
    check manager.performUndo()
    check document.layoutGuide(first.id) == first

  test "guides and constraints can be created edited saved and reloaded":
    let file = getTempDir() / ("tekton-layout-" & $getCurrentProcessId() & ".cbor")
    defer:
      if fileExists(file):
        removeFile(file)
    let
      document = newResourceEditorDocument(layoutBundle(), fileUrl = file)
      editor = newResourceEditor(document)
      window = editor.newResourceEditorWindow()
      childId = resourceId("child")
      child = editor.previewInstance().view(childId)
    check editor.selectResource(resourceId("canvas"))
    let guideEdit = editor.insertResourceKind(rnkLayoutGuide)
    check guideEdit.applied
    check editor.hasPreviewSelection()
    check editor.commitSelectedPropertyText("insets", "12, 14, 16, 18").edit.applied
    check document.resources().layoutGuide(guideEdit.resourceId).insets ==
      insets(12, 14, 16, 18)
    check editor.selectResource(childId)
    let constraintEdit = editor.insertResourceKind(rnkLayoutConstraint)
    check constraintEdit.applied
    check editor.hasPreviewSelection()
    check editor.commitSelectedPropertyText("constant", "220").edit.applied
    check editor.commitSelectedPropertyText("priority", "750").edit.applied
    check editor.commitSelectedPropertyText("active", "false").edit.applied
    check not editor
    .previewInstance()
    .layoutConstraint(constraintEdit.resourceId)
    .active()
    check editor.previewInstance().view(childId) == child
    check document.undoManagerFor().performUndo()
    check editor.previewInstance().layoutConstraint(constraintEdit.resourceId).active()
    check editor.commitSelectedPropertyText("priority", "2000").edit.applied
    check not document.resources().draftIsValid()
    let validRevision = editor.previewRevision()
    check editor.commitSelectedPropertyText("priority", "900").edit.applied
    check document.resources().draftIsValid()
    check editor.previewRevision() > validRevision
    discard window.buildRenders()
    check editor.saveEditorDocument()
    let loaded = newTektonDocument(file)
    check loaded.resources().draftIsValid()
    check loaded.resources().layoutGuide(guideEdit.resourceId).insets ==
      insets(12, 14, 16, 18)
    check loaded.resources().layoutConstraint(constraintEdit.resourceId).constant == 220
    check loaded.resources().layoutConstraint(constraintEdit.resourceId).priority == 900
    check editor.removeSelectedView().applied
    check not document.resources().contains(constraintEdit.resourceId)
    check document.undoManagerFor().performUndo()
    check document.resources().contains(constraintEdit.resourceId)

  test "invalid numeric text remains in the field editor and does not change the draft":
    let
      document = newResourceEditorDocument(layoutBundle())
      editor = newResourceEditor(document)
      window = editor.newResourceEditorWindow()
    check editor.selectResource(resourceId("child"))
    let inserted = editor.insertResourceKind(rnkLayoutConstraint)
    let original = document.resources().layoutConstraint(inserted.resourceId)
    discard window.buildRenders()
    let
      table = editor.propertyInspector()
      row = editor.rowIndex("constant")
      column = table.columnWithIdentifier("value")
    check table.beginEditingCell(row, column)
    check not table.commitEditingCell("not a number")
    check table.editingState().active
    check table.editingValidationError().len > 0
    check document.resources().layoutConstraint(inserted.resourceId) == original
    check table.commitEditingCell("240")
    check document.resources().layoutConstraint(inserted.resourceId).constant == 240

  test "pinning a child creates four constraints as one undoable action":
    var bundle = layoutBundle()
    bundle.views[0].children[0].kind = "view"
    bundle.views[0].children[0].properties.setLen(1)
    let
      document = newResourceEditorDocument(bundle)
      editor = newResourceEditor(document)
      window = editor.newResourceEditorWindow()
      childId = resourceId("child")
      child = editor.previewInstance().view(childId)
    check editor.selectResource(childId)
    check editor.pinSelectedView().applied
    check document.resources().draftIsValid()
    check document.resources().bundle().layoutConstraints.len == 4
    check document.undoManagerFor().undoActionName() == "Pin to Parent"
    discard window.buildRenders()
    check child.frame() == rect(16, 16, 368, 268)
    check not editor.nudgeSelectedView(initPoint(10, 0)).applied
    check not editor.resizeSelectedView(initSize(10, 0)).applied
    check document.undoManagerFor().performUndo()
    check document.resources().bundle().layoutConstraints.len == 0
    check document
    .resources()
    .findViewProperty(childId, "translatesAutoresizingMaskIntoConstraints").isNone
    check editor.previewInstance().view(childId) == child
    check document.undoManagerFor().performRedo()
    check document.resources().bundle().layoutConstraints.len == 4
    check editor.removeSelectedView().applied
    check document.resources().draftIsValid()
    check document.resources().bundle().layoutConstraints.len == 0
    check document.undoManagerFor().performUndo()
    check document.resources().contains(childId)
    check document.resources().bundle().layoutConstraints.len == 4

  test "window and command inspectors round trip editable fields":
    let
      document = newResourceEditorDocument(layoutBundle())
      editor = newResourceEditor(document)
    check editor.selectResource(resourceId("canvas"))
    let window = editor.insertResourceKind(rnkWindow)
    check window.applied
    check editor.commitSelectedPropertyText("title", "My app").edit.applied
    check editor.commitSelectedPropertyText("frame", "60, 80, 720, 480").edit.applied
    check document.resources().window(window.resourceId).title.fallback == "My app"
    let command = editor.insertResourceKind(rnkCommand)
    check command.applied
    check editor.commitSelectedPropertyText("selector", "saveDocument").edit.applied
    check document.resources().command(command.resourceId).selector == "saveDocument"
    check document.resources().draftIsValid()

  test "conflicting authored constraints appear in diagnostics after layout":
    var bundle = layoutBundle()
    for index, width in [100.0'f32, 200.0'f32]:
      bundle.layoutConstraints.add initResourceLayoutConstraint(
        resourceId("width." & $index),
        resourceId("canvas"),
        resourceLayoutItem(resourceId("child")),
        rlaWidth,
        constant = width,
      )
    let
      document = newResourceEditorDocument(bundle)
      editor = newResourceEditor(document)
      window = editor.newResourceEditorWindow()
    discard window.buildRenders()
    var reported = false
    for diagnostic in editor.diagnosticRows():
      if diagnostic.code == "resource.layout.unsatisfied":
        reported = true
        check diagnostic.resourceId in [resourceId("width.0"), resourceId("width.1")]
    check reported
