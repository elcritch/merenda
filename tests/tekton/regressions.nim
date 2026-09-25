import std/[options, os, unittest]

import merenda/nimkit
import merenda/tekton

proc regressionBundle(title = "Original"): ResourceBundle =
  result = initResourceBundle("tests.tekton.regressions")
  result.views =
    @[
      initViewNodeResource(
        resourceId("canvas"),
        properties = [resourceProperty("frame", resourceValue(rect(0, 0, 400, 300)))],
        children = [
          initViewNodeResource(
            resourceId("button"),
            "checkBox",
            [
              resourceProperty("frame", resourceValue(rect(20, 20, 180, 44))),
              resourceProperty("title", resourceValue(title)),
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

suite "Tekton responsiveness and editing regressions":
  test "property edits construct only the changed view and preserve layout identities":
    var
      constructed = 0
      registry = initNimKitResourceRegistry()
      bundle = initResourceBundle("tests.tekton.large-preview")
    registry.registerViewKind(
      "button",
      proc(frame: Rect): View =
        inc constructed
        newButton(frame = frame),
      baseKind = "control",
    )
    for index in 0 ..< 100:
      bundle.views.add initViewNodeResource(
        resourceId("button." & $index),
        "button",
        [resourceProperty("title", resourceValue("Button " & $index))],
      )
    bundle.layoutConstraints.add initResourceLayoutConstraint(
      resourceId("width"),
      resourceId("button.0"),
      resourceLayoutItem(resourceId("button.0")),
      rlaWidth,
      constant = 100,
    )
    let
      preview = newResourcePreview(registry)
      host = newView()
    check preview.update(bundle, 0, host).applied
    let
      original = preview.view(resourceId("button.0"))
      constraint = preview.layoutConstraint(resourceId("width"))
    constructed = 0
    bundle.views[0].properties[0].value = resourceValue("Edited")
    check preview.update(bundle, 1, host).applied
    check constructed == 1
    check preview.view(resourceId("button.0")) == original
    check preview.layoutConstraint(resourceId("width")) == constraint
    check constraint.active()
    check Button(original).title() == "Edited"
    check original.constraints().len == 1
    constructed = 0
    bundle.layoutConstraints[0].constant = 120
    check preview.update(bundle, 2, host).applied
    check constructed == 0
    check preview.view(resourceId("button.0")) == original
    check original.constraints().len == 1
    check preview.layoutConstraint(resourceId("width")).constant() == 120

  test "loading another revision zero document replaces the preview":
    let path = getTempDir() / ("tekton-reload-" & $getCurrentProcessId() & ".cbor")
    defer:
      if fileExists(path):
        removeFile(path)
    let
      document = newResourceEditorDocument(regressionBundle())
      editor = newResourceEditor(document)
    writeFile(path, regressionBundle("Reloaded").encodeResourceBundle())
    check document.readFromFileUrl(path)
    check document.resources().revision() == 0
    check Button(editor.previewInstance().view(resourceId("button"))).title() ==
      "Reloaded"

  test "inspector shows runtime defaults without authoring them":
    let
      document = newResourceEditorDocument(regressionBundle())
      editor = newResourceEditor(document)
    check editor.selectResource(resourceId("button"))
    let index = editor.rowIndex("enabled")
    check index >= 0
    check editor.propertyRows()[index].text == "true"
    check editor.propertyRows()[index].value.get().boolValue
    check document.resources().findViewProperty(resourceId("button"), "enabled").isNone
    check not document.isDocumentEdited()

  test "hover and repeated synchronization preserve an active inspector edit":
    let
      document = newResourceEditorDocument(regressionBundle())
      editor = newResourceEditor(document)
      window = editor.newResourceEditorWindow()
    discard window.buildRenders()
    check editor.selectResource(resourceId("button"))
    let
      table = editor.propertyInspector()
      column = table.columnWithIdentifier("value")
      row = editor.rowIndex("title")
    check table.beginEditingCell(row, column)
    editor.clearPreviewHover()
    editor.synchronize()
    check table.editingState().active
    check table.commitEditingCell("Still editing")
    check Button(editor.previewInstance().view(resourceId("button"))).title() ==
      "Still editing"

  test "unchanged synchronization and selection do not rebuild inspector rows":
    var reads = 0
    var registry = initNimKitResourceRegistry()
    registry.registerViewProperty(
      "button",
      "probe",
      {rvBool},
      setter = proc(
          view: View, value: ResourceValue, context: ResourcePropertyContext
      ): bool =
        true,
      getter = proc(
          view: View, context: ResourcePropertyContext
      ): ResourcePropertyReadResult =
        inc reads
        ResourcePropertyReadResult(read: true, value: resourceValue(true)),
    )
    let document = newResourceEditorDocument(regressionBundle(), registry = registry)
    let editor = newResourceEditor(document)
    check editor.selectResource(resourceId("button"))
    check reads > 0
    reads = 0
    editor.clearPreviewHover()
    editor.synchronize()
    check editor.selectResource(resourceId("button"))
    check reads == 0

  test "design selection does not toggle preview controls":
    let
      document = newResourceEditorDocument(regressionBundle())
      editor = newResourceEditor(document)
      window = editor.newResourceEditorWindow()
      button = Button(editor.previewInstance().view(resourceId("button")))
    discard window.buildRenders()
    let point = button.pointToWindow(initPoint(40, 20))
    check button.state() == bsOff
    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check document.resources().selectedResourceIds() == @[resourceId("button")]
    check button.state() == bsOff

  test "nonfinite numbers stay invalid editable input":
    for text in ["nan", "inf", "-inf", "1e100"]:
      check not parseResourceValue(text, {rvFloat}).parsed
      check not parseResourceValue("0, 0, " & text & ", 30", {rvRect}).parsed

  test "decimal input falls back from integer to float without accepting a partial parse":
    let parsed = parseResourceValue("0.75", {rvInt, rvFloat})
    check parsed.parsed
    check parsed.value == resourceValue(0.75'f32)
    check not parseResourceValue("invalid", {rvInt}).parsed

  test "interaction mode enables control behavior explicitly":
    let
      document = newResourceEditorDocument(regressionBundle())
      editor = newResourceEditor(document)
      window = editor.newResourceEditorWindow()
      button = Button(editor.previewInstance().view(resourceId("button")))
    discard window.buildRenders()
    editor.interactivePreview = true
    let point = button.pointToWindow(initPoint(40, 20))
    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check button.state() == bsOn
    check not document.isDocumentEdited()

  test "sliders and steppers are editable through the registry and palette":
    let
      document = newResourceEditorDocument(regressionBundle())
      editor = newResourceEditor(document)
    check editor.selectResource(resourceId("canvas"))
    let slider = editor.insertViewKind("slider")
    check slider.applied
    check editor.commitSelectedPropertyText("value", "0.75").edit.applied
    require document.resources().draftIsValid()
    check Slider(editor.previewInstance().view(slider.resourceId)).value() == 0.75
    let stepper = editor.insertViewKind("stepper")
    check stepper.applied
    check editor.commitSelectedPropertyText("increment", "5").edit.applied
    check editor.commitSelectedPropertyText("value", "25").edit.applied
    require document.resources().draftIsValid()
    check Stepper(editor.previewInstance().view(stepper.resourceId)).value() == 25
    check Stepper(editor.previewInstance().view(stepper.resourceId)).increment() == 5

  test "failed setters that mutate first are rolled back":
    var
      registry = initNimKitResourceRegistry()
      live: View
      bundle = regressionBundle()
    registry.registerViewProperty(
      "checkBox",
      "probe",
      {rvString},
      setter = proc(
          view: View, value: ResourceValue, context: ResourcePropertyContext
      ): bool =
        view.identifier = value.stringValue
        if view == live and value.stringValue == "Fail after mutation":
          raise newException(ValueError, "intentional failure after setting identifier")
        true,
      getter = proc(
          view: View, context: ResourcePropertyContext
      ): ResourcePropertyReadResult =
        ResourcePropertyReadResult(read: true, value: resourceValue(view.identifier())),
    )
    bundle.views[0].children[0].properties.add resourceProperty(
      "probe", resourceValue("Original")
    )
    let
      preview = newResourcePreview(registry)
      host = newView()
    check preview.update(bundle, 0, host).applied
    live = preview.view(resourceId("button"))
    bundle.views[0].children[0].properties[^1].value =
      resourceValue("Fail after mutation")
    let update = preview.update(bundle, 1, host)
    check not update.applied
    check preview.revision() == 0
    check live.identifier() == "Original"

  test "property removal restores defaults without resetting unrelated live state":
    var bundle = regressionBundle()
    bundle.views[0].children[0].properties.add resourceProperty(
      "enabled", resourceValue(false)
    )
    let
      preview = newResourcePreview()
      host = newView()
    check preview.update(bundle, 0, host).applied
    let button = Button(preview.view(resourceId("button")))
    button.state = bsOn
    bundle.views[0].children[0].properties.setLen(2)
    check preview.update(bundle, 1, host).applied
    check button.enabled()
    check button.state() == bsOn
