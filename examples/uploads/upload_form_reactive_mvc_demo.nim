## Reactive MVC using ordinary NimKit widgets and scope-owned bindings.
## Run `nim c -r examples/uploads/upload_form_reactive_mvc_demo.nim`.
##
## The controller sends commands to the shared upload model. File order drives
## list membership, each row observes its own file, and selection mounts an
## editor whose bindings belong to that file. Edits keep the editor mounted.
import std/strutils
import sigils/[core, reactive]
import merenda/nimkit
import ./[uploadstate, uploadviews]

type ReactiveUploadController* = ref object of ViewController
  page*: UploadPage
  ui: UploadView
  bindings, rowBindings, editorBindings: BindingScope
  editorId: int

template command(button: Button, receiver: Responder, context, handler: untyped) =
  button.action = actionSelector("reactiveUploadCommand")
  button.target = newActionTarget(button.action, receiver, context, handler)

proc showName(button: Button, file: Opt[UploadFile]) =
  if file.isSome:
    button.title = file.get.displayName

proc showDetail(label: Label, file: Opt[UploadFile]) =
  if file.isSome:
    label.stringValue = file.get.detailLine

proc selected(store: UploadStore, id: int): bool =
  store.selected{} == id

proc showSelected(button: Button, selected: bool) =
  button.state = if selected: bsOn else: bsOff

proc showRows(controller: ReactiveUploadController, ids: seq[int]) =
  controller.rowBindings.dispose()
  let scope = newBindingScope()
  controller.rowBindings = scope
  let store = controller.page.store
  let list = controller.ui.list
  list.clear()
  let count = ids.len
  controller.ui.count.stringValue =
    (if count == 1: "1 file" else: $count & " files") & " to upload"
  if count == 0:
    list.addArrangedSubview(newLabel("No files. Add some to upload."))
  for id in ids:
    let row = list.addFileRow(id)
    let item = store.files.item(id)
    scope.bindValue("name-" & $id, item, row.select, showName)
    scope.bindValue("detail-" & $id, item, row.detail, showDetail)
    scope.bindSigilValue(
      "selected-" & $id, store.selected, store, id, selected, row.select, showSelected
    )
    row.select.command(store, id) do(store: UploadStore, id: int, sender: DynamicAgent):
      store.selectFile(id)
    row.remove.command(store, id) do(store: UploadStore, id: int, sender: DynamicAgent):
      store.removeFile(id)

proc showChoices(controller: ReactiveUploadController, choice: CategoryChoice) =
  let editor = controller.ui.editor
  let form = controller.page.form
  let id = controller.editorId
  editor.categories.clear()
  editor.subcategories.clear()
  for category in Categories:
    let button = newRadioButton(category.name)
    button.identifier = "category-" & category.name
    button.showSelected(category.name == choice.category)
    button.command(form, id) do(form: FileForm, id: int, sender: DynamicAgent):
      if form.store.selected{} == id:
        form.chooseCategory(Button(sender).title)
    editor.categories.addArrangedSubview(button)
  for name in subcategoriesFor(choice.category):
    let button = newRadioButton(name)
    button.identifier = "subcategory-" & name
    button.showSelected(name == choice.subcategory)
    button.command(form, id) do(form: FileForm, id: int, sender: DynamicAgent):
      if form.store.selected{} == id:
        form.chooseSubcategory(Button(sender).title)
    editor.subcategories.addArrangedSubview(button)
  if choice.category.len == 0:
    editor.subcategories.addArrangedSubview(newLabel("Choose a category first."))

proc showText(label: Label, value: string) =
  label.stringValue = value

proc showSpecial(box: Button, file: Opt[UploadFile]) =
  box.showSelected(file.isSome and file.get.special)

proc showEditor(controller: ReactiveUploadController, id: int) =
  controller.editorBindings.dispose()
  controller.ui.form.clear()
  controller.ui.editor = FileEditor()
  controller.editorId = id
  let form = controller.page.form
  let store = form.store
  if id notin store.files:
    controller.ui.form.addArrangedSubview(
      newLabel("Select or add a file to edit its details.")
    )
    return

  let editor = controller.ui.form.addFileEditor(store.files[id], form.tagController)
  controller.ui.editor = editor
  let scope = newBindingScope()
  controller.editorBindings = scope
  let item = store.files.item(id)
  for (field, widget) in [(ffName, editor.name), (ffAltText, editor.altText)]:
    let key: FileTextContext = (id, FileTextField(field))
    scope.bindTextField($field, item, form, key, readFileText, widget, editFileText)
  for field in FileField:
    scope.bindValue(
      "issue-" & $field, form.issues[field], editor.issues[field], showText
    )
  scope.bindValue("special", item, editor.special, showSpecial)
  scope.bindValue("choices", form.choice, controller, showChoices)
  editor.special.command(store, id) do(
    store: UploadStore, id: int, sender: DynamicAgent
  ):
    if store.selected{} == id:
      store.setSpecial(id, Button(sender).state == bsOn)

proc addFiles(controller: ReactiveUploadController, sender: DynamicAgent) {.slot.} =
  controller.page.chooseFiles()

proc save(controller: ReactiveUploadController, sender: DynamicAgent) {.slot.} =
  controller.page.save()

proc cancel(controller: ReactiveUploadController, sender: DynamicAgent) {.slot.} =
  controller.page.cancel()

proc showEvents(label: Label, events: seq[string]) =
  label.stringValue = "Events: " & events.join("  ·  ")

proc disposeBindings(controller: ReactiveUploadController) {.slot.} =
  controller.bindings.dispose()
  controller.rowBindings.dispose()
  controller.editorBindings.dispose()

proc newReactiveUploadController*(
    paths: openArray[string] = SamplePaths
): ReactiveUploadController =
  let controller = ReactiveUploadController(
    page: newUploadPage(paths), ui: newUploadView(), bindings: newBindingScope()
  )
  let ui = controller.ui
  let events = newStatusLabel()
  events.identifier = "events"
  ui.addArrangedSubview(events)
  controller.initViewController(ui)
  connect(controller, willTeardown, controller, disposeBindings)
  connect(ui.addButton, actionDidSend, controller, addFiles)
  connect(ui.saveButton, actionDidSend, controller, save)
  connect(ui.cancelButton, actionDidSend, controller, cancel)
  let page = controller.page
  controller.bindings.bindValue("order", page.store.files.order, controller, showRows)
  controller.bindings.bindValue(
    "selection", page.store.selected, controller, showEditor
  )
  controller.bindings.bindValue("status", page.status, ui.status, showText)
  controller.bindings.bindValue("events", page.events, events, showEvents)
  controller

when isMainModule and not defined(merendaTests):
  let app = sharedApplication()
  let window = newWindowController(
    newWindow("Upload files (Reactive MVC)", frame = rect(80, 80, 980, 640))
  )
  window.viewController = newReactiveUploadController()
  window.showWindow(app)
  app.run()
