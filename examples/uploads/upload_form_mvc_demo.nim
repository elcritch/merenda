## Traditional MVC version of the multi-file upload form.
## Run `nim c -r examples/uploads/upload_form_mvc_demo.nim`.
##
## UploadModel owns the files and enforces rules that span fields or files.
## UploadView holds ordinary NimKit widgets. UploadController handles their
## actions, changes the model, then updates the affected rows and editor fields.
## A selection change builds a fresh editor. Typing leaves the editor in place.
## The parent listens for file changes and upload requests. It sends tag queries
## to a worker and hands its results back to the form.
import std/[os, sequtils, strutils]
import sigils/[core, threadProxies, threads]
import merenda/nimkit
import ./[uploadfiles, uploadviews]

type
  UploadModel = object
    files: seq[UploadFile]
    lastId: int

  UploadController* = ref object of ViewController
    model: UploadModel
    ui: UploadView
    selected: int ## Index into the model and the matching row, or -1.
    touched: set[FileField]
    submitted: bool

  UploadPageController* = ref object of ViewController
    form*: UploadController
    events: Label
    uploads: seq[seq[UploadFile]]
    recentEvents: seq[string]
    backend: AgentProxy[TagBackend]

proc addPaths(model: var UploadModel, paths: openArray[string]) =
  for path in paths:
    inc model.lastId
    model.files.add UploadFile(id: model.lastId, path: path, name: path.extractFilename)

proc setCategory(file: var UploadFile, category: string) =
  if file.category != category:
    file.category = category
    file.subcategory = ""

proc setSpecial(model: var UploadModel, index: int, special: bool) =
  for i, file in model.files.mpairs:
    file.special = special and i == index

proc filesChanged*(c: UploadController, files: seq[UploadFile]) {.signal.}
proc tagSearchStarted*(c: UploadController, query: string) {.signal.}
proc uploadRequested*(c: UploadController, files: seq[UploadFile]) {.signal.}

proc showSuggestions*(c: UploadController, query: string, tags: seq[string]) =
  let picker = c.ui.editor.tags
  if not picker.isNil and query == picker.query.strip.toLowerAscii:
    picker.setAvailableTags(tags.mapIt(tagItem(it)))

proc queryEdited(c: UploadController, sender: DynamicAgent) {.slot.} =
  let picker = c.ui.editor.tags
  if sender == DynamicAgent(picker):
    emit c.tagSearchStarted(picker.query.strip.toLowerAscii)

proc tagsEdited(c: UploadController, sender: DynamicAgent) {.slot.} =
  let picker = c.ui.editor.tags
  if sender == DynamicAgent(picker):
    c.model.files[c.selected].tags = picker.selectedIdentifiers

proc showRow(c: UploadController, index: int) =
  let file = c.model.files[index]
  let row = c.ui.rows[index]
  row.select.title = file.displayName
  row.select.state = if index == c.selected: bsOn else: bsOff
  row.detail.stringValue = file.detailLine

proc showIssues(c: UploadController) =
  let file = c.model.files[c.selected]
  for field in FileField:
    c.ui.editor.issues[field].stringValue =
      if c.submitted or field in c.touched:
        file.issueFor(field)
      else:
        ""

proc textEdited(c: UploadController, sender: DynamicAgent) {.slot.} =
  let editor = c.ui.editor
  if sender == DynamicAgent(editor.name):
    c.model.files[c.selected].name = editor.name.stringValue
    c.touched.incl ffName
  elif sender == DynamicAgent(editor.altText):
    c.model.files[c.selected].altText = editor.altText.stringValue
    c.touched.incl ffAltText
  else:
    return
  c.showRow(c.selected)
  c.showIssues()

proc specialEdited(c: UploadController, sender: DynamicAgent) {.slot.} =
  if sender == DynamicAgent(c.ui.editor.special):
    c.model.setSpecial(c.selected, c.ui.editor.special.state == bsOn)
    for i in 0 ..< c.ui.rows.len:
      c.showRow(i)

proc showChoices(c: UploadController)

proc choiceEdited(c: UploadController, sender: DynamicAgent) {.slot.} =
  let button = Button(sender)
  let editor = c.ui.editor
  if button.superview == editor.categories:
    let previous = c.model.files[c.selected].subcategory
    c.model.files[c.selected].setCategory(button.title)
    c.touched.incl ffCategory
    if previous != c.model.files[c.selected].subcategory:
      c.touched.incl ffSubcategory
  elif button.superview == editor.subcategories:
    c.model.files[c.selected].subcategory = button.title
    c.touched.incl ffSubcategory
  else:
    return
  c.showChoices()
  c.showRow(c.selected)
  c.showIssues()

proc addChoice(c: UploadController, row: StackView, prefix, name, current: string) =
  let button = newRadioButton(name)
  button.identifier = prefix & name
  button.state = if name == current: bsOn else: bsOff
  connect(button, actionDidSend, c, choiceEdited)
  row.addArrangedSubview(button)

proc showChoices(c: UploadController) =
  let editor = c.ui.editor
  let file = c.model.files[c.selected]
  editor.categories.clear()
  editor.subcategories.clear()
  for category in Categories:
    c.addChoice(editor.categories, "category-", category.name, file.category)
  for name in subcategoriesFor(file.category):
    c.addChoice(editor.subcategories, "subcategory-", name, file.subcategory)
  if file.category.len == 0:
    editor.subcategories.addArrangedSubview(newLabel("Choose a category first."))

proc showEditor(c: UploadController) =
  c.ui.form.clear()
  c.touched = {}
  c.submitted = false
  c.ui.editor = FileEditor()
  if c.selected < 0:
    c.ui.form.addArrangedSubview(newLabel("Select or add a file to edit its details."))
    return
  let file = c.model.files[c.selected]
  let editor = c.ui.form.addFileEditor(
    file, newTagController(selected = file.tags.mapIt(tagItem(it)))
  )
  c.ui.editor = editor
  c.showChoices()
  connect(editor.name, textDidChange, c, textEdited)
  connect(editor.altText, textDidChange, c, textEdited)
  connect(editor.special, actionDidSend, c, specialEdited)
  connect(editor.tags, tagQueryDidChange, c, queryEdited)
  connect(editor.tags, tagSelectionDidChange, c, tagsEdited)
  emit c.tagSearchStarted("")

proc selectFile(c: UploadController, index: int) =
  let previous = c.selected
  if previous != index:
    c.selected = index
    c.showEditor()
    if previous >= 0:
      c.showRow(previous)
  c.showRow(index)

proc showList(c: UploadController)

proc selectRow(c: UploadController, sender: DynamicAgent) {.slot.} =
  let index = c.ui.rows.findIt(DynamicAgent(it.select) == sender)
  if index >= 0:
    c.selectFile(index)

proc removeRow(c: UploadController, sender: DynamicAgent) {.slot.} =
  let index = c.ui.rows.findIt(DynamicAgent(it.remove) == sender)
  if index >= 0:
    c.model.files.delete(index)
    if index == c.selected:
      c.selected = min(index, c.model.files.high)
      c.showEditor()
    elif index < c.selected:
      dec c.selected
    c.showList()
    emit c.filesChanged(c.model.files)

proc showList(c: UploadController) =
  c.ui.list.clear()
  c.ui.rows.setLen(0)
  let count = c.model.files.len
  c.ui.count.stringValue =
    (if count == 1: "1 file" else: $count & " files") & " to upload"
  if count == 0:
    c.ui.list.addArrangedSubview(newLabel("No files. Add some to upload."))
  for index, file in c.model.files:
    let row = c.ui.list.addFileRow(file.id)
    connect(row.select, actionDidSend, c, selectRow)
    connect(row.remove, actionDidSend, c, removeRow)
    c.ui.rows.add row
    c.showRow(index)

proc addPaths*(c: UploadController, paths: openArray[string]) =
  if paths.len > 0:
    c.model.addPaths(paths)
    if c.selected < 0:
      c.selected = 0
      c.showEditor()
    c.showList()
    emit c.filesChanged(c.model.files)

proc chooseFiles(c: UploadController, sender: DynamicAgent) {.slot.} =
  let panel = newOpenPanel()
  panel.message = "Choose files to upload."
  panel.allowsMultipleSelection = true
  panel.directoryUrl = getHomeDir()
  if sharedApplication().runModal(panel) == PanelResponseOk:
    c.addPaths(panel.selectedUrls.mapIt(it.filePathFromUrl()))

proc save(c: UploadController, sender: DynamicAgent) {.slot.} =
  if c.model.files.len == 0:
    c.ui.status.stringValue = "Add files before uploading."
    return
  for i, file in c.model.files:
    if not file.isValid:
      c.selectFile(i)
      c.submitted = true
      c.showIssues()
      c.ui.status.stringValue = "Fix the highlighted fields before uploading."
      return
  emit c.uploadRequested(c.model.files)

proc cancel(c: UploadController, sender: DynamicAgent) {.slot.} =
  if c.model.files.len > 0:
    c.model.files.setLen(0)
    c.selected = -1
    c.showList()
    c.showEditor()
    emit c.filesChanged(c.model.files)
  c.ui.status.stringValue = "Upload cancelled."

proc newUploadController*(): UploadController =
  let c = UploadController(selected: -1, ui: newUploadView())
  c.initViewController(c.ui)
  connect(c.ui.addButton, actionDidSend, c, chooseFiles)
  connect(c.ui.cancelButton, actionDidSend, c, cancel)
  connect(c.ui.saveButton, actionDidSend, c, save)
  c.showList()
  c.showEditor()
  c

proc logEvent(page: UploadPageController, message: string) =
  page.recentEvents.add message
  if page.recentEvents.len > 4:
    page.recentEvents.delete(0)
  page.events.stringValue = "Events: " & page.recentEvents.join("  ·  ")

proc onFilesChanged(page: UploadPageController, files: seq[UploadFile]) {.slot.} =
  page.logEvent("filesChanged: " & $files.len & " file(s)")

proc onUploadRequested(page: UploadPageController, files: seq[UploadFile]) {.slot.} =
  page.uploads.add files
  page.logEvent("uploadRequested: " & $files.len & " file(s)")
  page.form.ui.status.stringValue = uploadSummary(files)

proc showTagResults(
    page: UploadPageController, query: string, tags: seq[string]
) {.slot.} =
  page.form.showSuggestions(query, tags)

proc onTagSearchStarted(page: UploadPageController, query: string) {.slot.} =
  page.logEvent("tagSearchStarted: \"" & query & "\"")
  if page.backend.isNil:
    page.backend = newTagBackend()
    connectThreaded(
      page.backend, tagsFound, page, UploadPageController.showTagResults()
    )
  emit page.backend.searchTags(query)

proc newUploadPageController*(
    paths: openArray[string] = SamplePaths
): UploadPageController =
  result = UploadPageController(form: newUploadController(), events: newStatusLabel())
  let root = stack()
  result.events.identifier = "events"
  root.addArrangedSubview(result.form.view, result.events)
  result.initViewController(root)
  result.addChildViewController(result.form)
  connect(result.form, filesChanged, result, onFilesChanged)
  connect(result.form, uploadRequested, result, onUploadRequested)
  connect(result.form, tagSearchStarted, result, onTagSearchStarted)
  result.form.addPaths(paths)

when isMainModule and not defined(merendaTests):
  let app = sharedApplication()
  let window =
    newWindowController(newWindow("Upload files (MVC)", frame = rect(80, 80, 980, 640)))
  window.viewController = newUploadPageController()
  window.showWindow(app)
  app.run()
