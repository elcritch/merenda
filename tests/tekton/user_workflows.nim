import std/unittest

import merenda/nimkit
import merenda/tekton

proc blankCanvasBundle(): ResourceBundle =
  result = initResourceBundle("tests.tekton.user-workflows")
  result.views =
    @[
      initViewNodeResource(
        resourceId("canvas"),
        properties = [
          resourceProperty("frame", resourceValue(rect(20, 20, 640, 420))),
          resourceProperty(
            "backgroundColor", resourceValue(color(0.96, 0.97, 0.99, 1.0))
          ),
        ],
      )
    ]

suite "Tekton user workflows":
  test "a user can add edit duplicate position reorder and undo a view":
    let
      document = newResourceEditorDocument(blankCanvasBundle())
      editor = newResourceEditor(document)
      window = editor.newResourceEditorWindow()
      canvasId = resourceId("canvas")
      firstButtonId = resourceId("button.1")
      duplicateId = resourceId("button.2")

    check editor.selectResource(canvasId)
    check editor.paletteButton("button").sendAction()
    check document.resources().selectedResourceIds() == @[firstButtonId]

    let titleEdit = editor.commitSelectedPropertyText("title", "Create project")
    check titleEdit.edit.applied
    check Button(editor.previewInstance().view(firstButtonId)).title() ==
      "Create project"

    check window.dispatchKeyDown(
      KeyEvent(key: keyD, keyCode: keyD.ord, modifiers: shortcutModifiers())
    )
    check document.resources().selectedResourceIds() == @[duplicateId]
    check document.resources().viewProperty(duplicateId, "title").value.stringValue ==
      "Create project"
    check editor.hierarchyView().selectedItemIdentifier() == $duplicateId
    let duplicatePreview = editor.previewInstance().view(duplicateId)
    check not duplicatePreview.isNil

    check document.resources().viewProperty(firstButtonId, "frame").value.rectValue ==
      rect(18, 18, 180, 44)
    check document.resources().viewProperty(duplicateId, "frame").value.rectValue ==
      rect(30, 30, 180, 44)
    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmOption})
    )
    check window.dispatchKeyDown(
      KeyEvent(
        key: keyArrowDown, keyCode: keyArrowDown.ord, modifiers: {kmOption, kmShift}
      )
    )
    check document.resources().viewProperty(duplicateId, "frame").value.rectValue ==
      rect(31, 40, 180, 44)
    check editor.previewInstance().view(duplicateId) == duplicatePreview

    check editor.moveEarlierButton().sendAction()
    check document.resources().view(canvasId).children[0].id == duplicateId
    check document.resources().view(canvasId).children[1].id == firstButtonId
    check editor.previewInstance().view(duplicateId) == duplicatePreview

    check document.undoManagerFor().performUndo()
    check document.resources().view(canvasId).children[0].id == firstButtonId
    check document.resources().view(canvasId).children[1].id == duplicateId
    check document.resources().selectedResourceIds() == @[duplicateId]
    check editor.previewInstance().view(duplicateId) == duplicatePreview

    check document.undoManagerFor().performRedo()
    check document.resources().view(canvasId).children[0].id == duplicateId
    check document.resources().draftIsValid()

  test "deleting a view keeps the user at the nearest sibling":
    let
      document = newResourceEditorDocument(blankCanvasBundle())
      editor = newResourceEditor(document)
      window = editor.newResourceEditorWindow()
      canvasId = resourceId("canvas")
      buttonId = resourceId("button.1")
      labelId = resourceId("label.1")
      fieldId = resourceId("textField.1")

    check editor.selectResource(canvasId)
    check editor.paletteButton("button").sendAction()
    check editor.paletteButton("label").sendAction()
    check editor.paletteButton("textField").sendAction()
    check document.resources().view(canvasId).children.len == 3

    check editor.selectResource(labelId)
    check window.dispatchKeyDown(KeyEvent(key: keyDelete, keyCode: keyDelete.ord))
    check not document.resources().contains(labelId)
    check document.resources().selectedResourceIds() == @[fieldId]
    check editor.hierarchyView().selectedItemIdentifier() == $fieldId
    check editor.previewInstance().view(fieldId) != nil

    check document.undoManagerFor().performUndo()
    check document.resources().contains(labelId)
    check document.resources().selectedResourceIds() == @[fieldId]
    check document.resources().view(canvasId).children[0].id == buttonId
    check document.resources().view(canvasId).children[1].id == labelId
    check document.resources().view(canvasId).children[2].id == fieldId

    check editor.selectResource(fieldId)
    check window.dispatchKeyDown(KeyEvent(key: keyDelete, keyCode: keyDelete.ord))
    check document.resources().selectedResourceIds() == @[labelId]
