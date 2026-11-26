## A multi-file upload form built with DirectView and Sigils.
## Run `nim ic -r examples/upload_form_demo.nim`.
##
## The user picks several files, selects one in the list on the left, and edits
## its name, alt text, category, subcategory, tags and "special" flag on the right.
## Save uploads every file with its own values.
##
## One `CollectionSigil` owns every file's values, and one `Sigil[int]` owns the
## selection. The list and the form both read from that state, and their edits
## go back through `UploadStore` commands. Nothing copies the selected file into
## a separate form model, so no copy needs to be synced back, and an edit cannot
## loop back into the form.
##
## Each of the challenge's rules maps to one mechanism:
##
## 1. Selecting a file rebuilds the form under that file's key. The new fields
##    read their text from the file, and the selection-change slot clears the
##    touched fields, submit errors and tag search state.
## 2. Field edits update the selected file through the store. Bindings skip echoes
##    of their own writes, and Sigils skip publishing values that are unchanged.
## 3. `setCategory` clears the subcategory in the same publication.
## 4. `setSpecial` publishes one snapshot that clears the flag on every other file.
## 5. Typing a tag query emits `tagSearchStarted`. The parent searches on a worker
##    thread and passes results back with `showSuggestions`. Results for an older
##    query are dropped.
## 6. Adding or removing files emits `filesChanged` for the parent to observe.
import std/[os, sequtils, strutils]
import sigils/[core, reactive, threadProxies, threads]
import merenda/nimkit
import merenda/nimkit/directviews
import merenda/nimkit/foundation/backgroundworkers

type
  FileField* = enum
    ffName
    ffAltText
    ffCategory
    ffSubcategory

  UploadFile* = object
    id*: int
    path*: string
    name*, altText*: string
    category*, subcategory*: string
    tags*: seq[string]
    special*: bool

  CategoryChoice* = tuple[category, subcategory: string]
  ListState* = tuple[ids: seq[int], selected: int]

  UploadStore* = ref object of Responder
    ## Owns the files and the selection. The list and the form only read this
    ## state; changes go through the store's commands.
    files*: CollectionSigil[int, UploadFile]
    selected*: Sigil[int]
    listState*: Sigil[ListState]
    nextId: int

  FileForm* = ref object of Responder
    ## UI state for editing the selected file. Each file's values stay in the
    ## store. Everything here resets when the selection changes.
    store*: UploadStore
    touched*: Sigil[set[FileField]]
    submitted*: Sigil[bool]
    tagQuery*: Sigil[string]
    suggestions*: Sigil[seq[string]]
    choice*: Sigil[CategoryChoice]
    tags*: Sigil[seq[string]]
    tagController*: TagController
    issues*: array[FileField, Sigil[string]]

  TagBackend = ref object of AgentActor

  FileRow* = ref object of StackView ## A list row that selects its file when clicked.
    store: BackRef[UploadStore]
    fileId: int

  UploadPage* = ref object of Responder
    ## The parent component. It reacts to the upload form's events.
    store*: UploadStore
    form*: FileForm
    status*: Sigil[string]
    events*: Sigil[seq[string]]
    uploads*: seq[seq[UploadFile]]
    backend: AgentProxy[TagBackend]

const
  Categories* = [
    (name: "Photos", subcategories: @["Landscape", "Portrait", "Product"]),
    (name: "Documents", subcategories: @["Invoice", "Contract", "Report"]),
    (name: "Media", subcategories: @["Audio", "Video", "Slides"]),
  ]
  TagCatalog = [
    "brand", "campaign", "contract", "draft", "final", "internal", "interview",
    "invoice", "landscape", "launch", "legal", "nature", "night", "nim", "portrait",
    "press", "product", "public", "quarterly", "release", "review", "summer", "sunset",
    "team", "travel",
  ]
  SearchLatencyMs = 150
  SamplePaths* = [
    "~/Pictures/sunset-over-lake.jpg", "~/Documents/contract-2026.pdf",
    "~/Pictures/team-offsite.png", "~/Music/podcast-intro.mp3",
    "~/Documents/q3-report.pdf",
  ]
  ImageExtensions = [".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"]
  ErrorColor = color(0.85, 0.2, 0.2, 1)
  SelectedColor = color(0.3, 0.55, 1.0, 0.22)
  ClearColor = color(0, 0, 0, 0)
  PanelColor = color(0.5, 0.5, 0.5, 0.08)

proc filesChanged*(store: UploadStore, files: seq[UploadFile]) {.signal.}
proc uploadRequested*(store: UploadStore, files: seq[UploadFile]) {.signal.}
proc tagSearchStarted*(form: FileForm, query: string) {.signal.}

# Pure rules: derived from file values and never stored.

proc fileId*(file: UploadFile): int =
  file.id

proc subcategoriesFor*(category: string): seq[string] =
  for entry in Categories:
    if entry.name == category:
      return entry.subcategories

proc isImage*(file: UploadFile): bool =
  file.path.splitFile.ext.toLowerAscii in ImageExtensions

proc issueFor*(file: UploadFile, field: FileField): string =
  case field
  of ffName:
    if file.name.strip.len == 0:
      result = "A file name is required."
  of ffAltText:
    if file.isImage and file.altText.strip.len == 0:
      result = "Images need alt text."
  of ffCategory:
    if file.category.len == 0:
      result = "Choose a category."
  of ffSubcategory:
    if file.category.len > 0 and file.subcategory.len == 0:
      result = "Choose a subcategory."

proc isValid*(file: UploadFile): bool =
  result = true
  for field in FileField:
    if file.issueFor(field).len > 0:
      return false

proc displayName(file: UploadFile): string =
  if file.name.strip.len > 0: file.name else: "Untitled file"

proc detailLine(file: UploadFile): string =
  ## A one-line summary under the file name in the list.
  var parts = @[file.path.splitFile.ext.strip(chars = {'.'}).toUpperAscii]
  if file.category.len > 0:
    parts.add file.category &
      (if file.subcategory.len > 0: " › " & file.subcategory
      else: "")
  if file.special:
    parts.add "Special"
  if not file.isValid:
    parts.add "Needs details"
  parts.join("  ·  ")

# The store: the single owner of the file values.

proc newUploadStore*(): UploadStore =
  let files = newCollectionSigil(newSeq[UploadFile](), fileId)
  let selected = newSigil(0)
  result = UploadStore(files: files, selected: selected, nextId: 1)
  # Only order and selection change the list's structure. Rows observe their own
  # file, so typing a name does not rebuild the list.
  result.listState = computedNow[ListState]:
    (ids: files.order{}, selected: selected{})
  initResponder(result)

template modifyFile(store: UploadStore, id: int, file, body: untyped) =
  ## Publish one changed file. An unchanged value does not notify anyone.
  if id in store.files:
    var file = store.files[id]
    body
    if file != store.files[id]:
      store.files[id] = file

proc selectFile*(store: UploadStore, id: int) =
  if id == 0 or id in store.files:
    store.selected <- id

proc addPaths*(store: UploadStore, paths: openArray[string]) =
  var next = store.files{}
  let first = store.nextId
  for path in paths:
    next.add UploadFile(id: store.nextId, path: path, name: path.extractFilename)
    inc store.nextId
  if paths.len > 0:
    store.files <- next
    if store.selected{} == 0:
      store.selectFile(first)
    emit store.filesChanged(next)

proc removeFile*(store: UploadStore, id: int) =
  var next = store.files{}
  for index, file in next:
    if file.id == id:
      next.delete(index)
      store.files <- next
      if store.selected{} == id:
        # Select the file that moved into the removed row, or the new last row.
        store.selectFile(
          if next.len == 0:
            0
          else:
            next[min(index, next.high)].id
        )
      emit store.filesChanged(next)
      return

proc clearFiles*(store: UploadStore) =
  if store.files.len > 0:
    store.files <- newSeq[UploadFile]()
    store.selectFile(0)
    emit store.filesChanged(newSeq[UploadFile]())

proc setName*(store: UploadStore, id: int, name: string) =
  store.modifyFile(id, file):
    file.name = name

proc setAltText*(store: UploadStore, id: int, altText: string) =
  store.modifyFile(id, file):
    file.altText = altText

proc setCategory*(store: UploadStore, id: int, category: string) =
  ## Rule 3: the subcategory depends on the category, so a new category clears it.
  store.modifyFile(id, file):
    if file.category != category:
      file.category = category
      file.subcategory = ""

proc setSubcategory*(store: UploadStore, id: int, subcategory: string) =
  store.modifyFile(id, file):
    if subcategory in subcategoriesFor(file.category):
      file.subcategory = subcategory

proc addTag*(store: UploadStore, id: int, tag: string) =
  let tag = tag.strip.toLowerAscii
  store.modifyFile(id, file):
    if tag.len > 0 and tag notin file.tags:
      file.tags.add tag

proc setTags*(store: UploadStore, id: int, tags: seq[string]) =
  store.modifyFile(id, file):
    file.tags = tags

proc removeTag*(store: UploadStore, id: int, tag: string) =
  store.modifyFile(id, file):
    let index = file.tags.find(tag)
    if index >= 0:
      file.tags.delete(index)

proc setSpecial*(store: UploadStore, id: int, special: bool) =
  ## Rule 4: at most one special file. Checking one file unchecks the others in
  ## the same snapshot, so observers never see two special files.
  if id in store.files:
    var next = store.files{}
    for file in next.mitems:
      file.special = special and file.id == id
    if next != store.files{}:
      store.files <- next

# The form: per-selection UI state and values derived from the selected file.

proc visibleIssue(
    files: CollectionSigil[int, UploadFile],
    selected: Sigil[int],
    touched: Sigil[set[FileField]],
    submitted: Sigil[bool],
    field: FileField,
): Sigil[string] =
  ## Show a field's error after the user touches the field or attempts to save.
  computedNow[string]:
    let file = files.item(selected{}){}
    let shown = submitted{} or field in touched{}
    if file.isSome and shown:
      file.get.issueFor(field)
    else:
      ""

proc resetSession*(form: FileForm) =
  form.touched <- {}
  form.submitted <- false
  form.tagQuery <- ""

proc selectionChanged(form: FileForm, attrs: set[SigilAttributes]) {.slot.} =
  ## Rule 1: a different file starts a clean form session.
  form.resetSession()

proc browseTags*(form: FileForm) =
  ## Ask the parent for every tag, which the dropdown lists before any typing.
  emit form.tagSearchStarted("")

proc queryChanged(form: FileForm, attrs: set[SigilAttributes]) {.slot.} =
  ## Rule 5: ask the parent to search. Results arrive through showSuggestions;
  ## until then the dropdown keeps filtering the previous results as you type.
  let query = form.tagQuery{}.strip.toLowerAscii
  if form.tagController.query != form.tagQuery{}:
    form.tagController.query = form.tagQuery{}
  emit form.tagSearchStarted(query)

proc showFileTags(form: FileForm, attrs: set[SigilAttributes]) {.slot.} =
  ## Load the selected file's tags into the picker. This is not a user edit, so
  ## it cannot write back into the store.
  let tags = form.tags{}
  if form.tagController.selectedIdentifiers != tags:
    form.tagController.setSelectedTags(tags.mapIt(tagItem(it)))

proc showSuggestedTags(form: FileForm, attrs: set[SigilAttributes]) {.slot.} =
  form.tagController.setAvailableTags(form.suggestions{}.mapIt(tagItem(it)))

proc tagsEdited(form: FileForm, sender: DynamicAgent) {.slot.} =
  ## Rule 2: a user edit in the picker updates the selected file.
  form.store.setTags(form.store.selected{}, form.tagController.selectedIdentifiers)

proc tagQueryEdited(form: FileForm, sender: DynamicAgent) {.slot.} =
  form.tagQuery <- form.tagController.query

proc newFileForm*(store: UploadStore): FileForm =
  let
    files = store.files
    selected = store.selected
    touched = newSigil[set[FileField]]({})
    submitted = newSigil(false)
  result = FileForm(
    store: store,
    touched: touched,
    submitted: submitted,
    tagQuery: newSigil(""),
    suggestions: newSigil(newSeq[string]()),
  )
  # Derived Sigils publish only when their value changes. Editing the name
  # recomputes `choice` and `tags`, but they publish nothing because their
  # values are unchanged, so the category buttons and tag chips are not rebuilt.
  result.choice = computedNow[CategoryChoice]:
    let file = files.item(selected{}){}
    if file.isSome:
      (category: file.get.category, subcategory: file.get.subcategory)
    else:
      (category: "", subcategory: "")
  result.tags = computedNow[seq[string]]:
    let file = files.item(selected{}){}
    if file.isSome:
      file.get.tags
    else:
      newSeq[string]()
  result.tagController = newTagController(selected = result.tags{}.mapIt(tagItem(it)))
  for field in FileField:
    result.issues[field] = visibleIssue(files, selected, touched, submitted, field)
  initResponder(result)
  connect(store.selected, change, result, selectionChanged)
  connect(result.tagQuery, change, result, queryChanged)
  connect(result.tags, change, result, showFileTags)
  connect(result.suggestions, change, result, showSuggestedTags)
  connect(result.tagController, tagSelectionDidChange, result, tagsEdited)
  connect(result.tagController, tagQueryDidChange, result, tagQueryEdited)

proc touch*(form: FileForm, field: FileField) =
  if field notin form.touched{}:
    form.touched <- form.touched{} + {field}

proc nameFor(form: FileForm, id: int): string =
  if id in form.store.files:
    result = form.store.files[id].name

proc editName(form: FileForm, id: int, text: string) =
  form.touch(ffName)
  form.store.setName(id, text)

proc altTextFor(form: FileForm, id: int): string =
  if id in form.store.files:
    result = form.store.files[id].altText

proc editAltText(form: FileForm, id: int, text: string) =
  form.touch(ffAltText)
  form.store.setAltText(id, text)

proc chooseCategory*(form: FileForm, category: string) =
  let id = form.store.selected{}
  if id notin form.store.files:
    return
  let hadSubcategory = form.store.files[id].subcategory.len > 0
  form.touch(ffCategory)
  form.store.setCategory(id, category)
  # Show the cleared subcategory as needing attention.
  if hadSubcategory and form.store.files[id].subcategory.len == 0:
    form.touch(ffSubcategory)

proc chooseSubcategory*(form: FileForm, subcategory: string) =
  form.touch(ffSubcategory)
  form.store.setSubcategory(form.store.selected{}, subcategory)

proc addTag*(form: FileForm, tag: string) =
  form.store.addTag(form.store.selected{}, tag)
  form.tagQuery <- ""

proc setTags*(form: FileForm, tags: seq[string]) =
  form.store.setTags(form.store.selected{}, tags)

proc removeTag*(form: FileForm, tag: string) =
  form.store.removeTag(form.store.selected{}, tag)

proc showSuggestions*(form: FileForm, query: string, tags: seq[string]) =
  ## Rule 5: show search results. Results for an older query are dropped, which
  ## also covers a selection change, because that clears the query.
  if query == form.tagQuery{}.strip.toLowerAscii:
    form.suggestions <- tags

proc submit*(form: FileForm): bool =
  ## Upload every file, or select the first invalid one and show its errors.
  let files = form.store.files{}
  if files.len == 0:
    return
  for file in files:
    if not file.isValid:
      form.store.selectFile(file.id)
      form.submitted <- true
      return
  emit form.store.uploadRequested(files)
  result = true

# The parent: listens to the form's events and runs the tag search backend.

proc searchTags(backend: AgentProxy[TagBackend], query: string) {.signal.}
proc tagsFound(backend: TagBackend, query: string, tags: seq[string]) {.signal.}

proc searchTags(backend: TagBackend, query: string) {.slot.} =
  ## Runs on a worker thread and simulates a backend round trip.
  sleep(SearchLatencyMs)
  var found: seq[string]
  for tag in TagCatalog:
    if tag.startsWith(query):
      found.add tag
  emit backend.tagsFound(query, found)

proc showTagResults(page: UploadPage, query: string, tags: seq[string]) {.slot.} =
  page.form.showSuggestions(query, tags)

proc logEvent(page: UploadPage, event: string) =
  var events = page.events{}
  events.add event
  if events.len > 4:
    events.delete(0)
  page.events <- events

proc onFilesChanged(page: UploadPage, files: seq[UploadFile]) {.slot.} =
  page.logEvent("filesChanged: " & $files.len & " file(s)")

proc onTagSearchStarted(page: UploadPage, query: string) {.slot.} =
  page.logEvent("tagSearchStarted: \"" & query & "\"")
  if page.backend.isNil:
    var backend = TagBackend()
    page.backend = backend.moveToThread(nimkitWorkerPool())
    connectThreaded(page.backend, searchTags, page.backend, searchTags)
    connectThreaded(page.backend, tagsFound, page, UploadPage.showTagResults())
  emit page.backend.searchTags(query)

proc onUploadRequested(page: UploadPage, files: seq[UploadFile]) {.slot.} =
  page.uploads.add files
  var lines: seq[string]
  for file in files:
    var line = file.name & " -> " & file.category & "/" & file.subcategory
    if file.tags.len > 0:
      line.add " #" & file.tags.join(" #")
    if file.special:
      line.add " (special)"
    lines.add line
  page.logEvent("uploadRequested: " & $files.len & " file(s)")
  page.status <- "Uploaded " & lines.join("; ")

proc newUploadPage*(paths: openArray[string] = SamplePaths): UploadPage =
  let store = newUploadStore()
  result = UploadPage(
    store: store,
    form: newFileForm(store),
    status: newSigil("Select a file to edit its upload details."),
    events: newSigil(newSeq[string]()),
  )
  initResponder(result)
  connect(store, filesChanged, result, onFilesChanged)
  connect(store, uploadRequested, result, onUploadRequested)
  connect(result.form, tagSearchStarted, result, onTagSearchStarted)
  result.form.browseTags()
  store.addPaths(paths)

proc save*(page: UploadPage) =
  if page.store.files.len == 0:
    page.status <- "Add files before uploading."
  elif not page.form.submit():
    page.status <- "Fix the highlighted fields before uploading."

proc cancel*(page: UploadPage) =
  page.store.clearFiles()
  page.status <- "Upload cancelled."

proc chooseFiles*(page: UploadPage) =
  let panel = newOpenPanel()
  panel.message = "Choose files to upload."
  panel.allowsMultipleSelection = true
  panel.directoryUrl = getHomeDir()
  if sharedApplication().runModal(panel) == PanelResponseOk:
    var paths: seq[string]
    for url in panel.selectedUrls:
      paths.add url.filePathFromUrl()
    page.store.addPaths(paths)

# Views. Rows and form fields bind to single files; bodies rebuild structure only.

protocol FileRowEvents of ResponderEventProtocol:
  method mouseDown(row: FileRow, event: MouseEvent): bool =
    let store = row.store{}
    if event.button == mbPrimary and not store.isNil:
      store.selectFile(row.fileId)
      result = true

proc newFileRow*(): FileRow =
  result = FileRow()
  initStackViewFields(result, laHorizontal)
  discard result.withProtocol(FileRowEvents)

proc showFile(row: FileRow, store: UploadStore, id: int) =
  row.store.target = store
  row.fileId = id

proc fileRow(context: DirectNode, id: int, selected: bool, store: UploadStore) =
  context.viewBody:
    FileRow:
      this.identifier = "file-" & $id
      this.showFile(store, id)
      this.distribution = svdNatural
      this.alignment = svaCenter
      this.spacing = 8
      this.edgeInsets = insets(6, 10)
      this.backgroundColor = if selected: SelectedColor else: ClearColor
      VStack:
        this.arrangedSizing = svspFillAvailableWidth
        this.distribution = svdNatural
        this.alignment = svaLeading
        this.spacing = 2
        Label(identifier = "name-" & $id):
          this.bindValue("name", store.files.item(id)) do(
            label: Label, file: Opt[UploadFile]
          ):
            if file.isSome:
              label.stringValue = file.get.displayName
        Label(identifier = "detail-" & $id, labelStyle = lsStatus):
          this.bindValue("detail", store.files.item(id)) do(
            label: Label, file: Opt[UploadFile]
          ):
            if file.isSome:
              label.stringValue = file.get.detailLine
      Button("×", identifier = "remove-" & $id, focusable = false):
        this.styleClasses = @["toolbar-button"]
        this.onAction(store, id) do(this: Button, receiver: UploadStore, id: int):
          receiver.removeFile(id)

proc drawFileList(context: DirectNode, store: UploadStore, state: ListState) =
  context.viewBody:
    VStack:
      this.identifier = "files"
      this.distribution = svdNatural
      this.alignment = svaFill
      this.spacing = 2
      for id in state.ids:
        keyed(id):
          component(fileRow, id, id == state.selected, store)
      if state.ids.len == 0:
        Label(stringValue = "No files. Add some to upload.")

proc fileList(context: DirectNode, store: UploadStore) =
  context.bindBody(store.listState, store, drawFileList)

proc issueLabel(context: DirectNode, form: FileForm, field: FileField) =
  context.viewBody:
    Label:
      this.identifier = "issue-" & $field
      this.textColor = ErrorColor
      this.bindValue("issue", form.issues[field]) do(label: Label, value: string):
        label.stringValue = value

proc drawChoices(context: DirectNode, form: FileForm, choice: CategoryChoice) =
  context.viewBody:
    VStack:
      this.distribution = svdNatural
      this.alignment = svaFill
      this.spacing = 6
      HStack:
        this.identifier = "categories"
        this.distribution = svdNatural
        this.spacing = 12
        for entry in Categories:
          keyed(entry.name):
            RadioButton(title = entry.name, identifier = "category-" & entry.name):
              this.state = if entry.name == choice.category: bsOn else: bsOff
              this.onAction(form, entry.name) do(
                this: Button, receiver: FileForm, category: string
              ):
                this.state = bsOn
                receiver.chooseCategory(category)
      component(issueLabel, form, ffCategory)
      Label(stringValue = "Subcategory")
      HStack:
        this.identifier = "subcategories"
        this.distribution = svdNatural
        this.spacing = 12
        if choice.category.len == 0:
          Label(stringValue = "Choose a category first.")
        for name in subcategoriesFor(choice.category):
          keyed(choice.category & "/" & name):
            RadioButton(title = name, identifier = "subcategory-" & name):
              this.state = if name == choice.subcategory: bsOn else: bsOff
              this.onAction(form, name) do(
                this: Button, receiver: FileForm, subcategory: string
              ):
                this.state = bsOn
                receiver.chooseSubcategory(subcategory)
      component(issueLabel, form, ffSubcategory)

proc categoryChoices(context: DirectNode, form: FileForm) =
  context.bindBody(form.choice, form, drawChoices)

proc fileFields(context: DirectNode, form: FileForm, id: int) =
  ## Rule 1: this component is keyed by file id, so selecting another file
  ## replaces these widgets and their edit state.
  let store = form.store
  context.viewBody:
    VStack:
      this.identifier = "form-" & $id
      this.distribution = svdNatural
      this.alignment = svaFill
      this.spacing = 6
      Label(identifier = "path", labelStyle = lsStatus):
        this.stringValue = store.files[id].path
      Label(stringValue = "File name")
      TextField(identifier = "name"):
        this.bindTextField("name", store.files.item(id), form, id, nameFor, editName)
      component(issueLabel, form, ffName)
      Label(stringValue = "Alt text")
      TextField(identifier = "alt-text", placeholder = "Describe the image"):
        this.bindTextField(
          "altText", store.files.item(id), form, id, altTextFor, editAltText
        )
      component(issueLabel, form, ffAltText)
      Label(stringValue = "Category")
      component(categoryChoices, form)
      Label(stringValue = "Tags")
      TagPicker(form.tagController, tlpInline, "Search tags…"):
        this.identifier = "tags"
      CheckBox(identifier = "special", title = "Special file (only one per upload)"):
        this.bindValue("special", store.files.item(id)) do(
          box: Button, file: Opt[UploadFile]
        ):
          box.state = if file.isSome and file.get.special: bsOn else: bsOff
        this.onAction(store, id) do(this: Button, receiver: UploadStore, id: int):
          receiver.setSpecial(id, this.state == bsOn)

proc drawForm(context: DirectNode, form: FileForm, id: int) =
  context.viewBody:
    VStack:
      this.distribution = svdNatural
      this.alignment = svaFill
      if id in form.store.files:
        keyed(id):
          component(fileFields, form, id)
      else:
        Label(stringValue = "Select or add a file to edit its details.")

proc fileForm(context: DirectNode, form: FileForm) =
  context.bindBody(form.store.selected, form, drawForm)

proc newUploadView*(page: UploadPage): DirectView =
  result = newDirectView()
  result.viewBody:
    VStack:
      this.distribution = svdNatural
      this.alignment = svaFill
      this.spacing = 12
      this.edgeInsets = insets(16)
      Label(stringValue = "Upload files", labelStyle = lsHeading)
      HStack:
        this.distribution = svdNatural
        this.alignment = svaFill
        this.spacing = 16
        VStack:
          this.identifier = "file-list"
          this.distribution = svdNatural
          this.alignment = svaFill
          this.spacing = 8
          this.edgeInsets = insets(8)
          this.backgroundColor = PanelColor
          Label(identifier = "file-count", labelStyle = lsStatus):
            this.bindValue("count", page.store.files.order) do(
              label: Label, ids: seq[int]
            ):
              label.stringValue =
                (if ids.len == 1: "1 file" else: $ids.len & " files") & " to upload"
          component(fileList, page.store)
          Button(
            "Upload more documents…", identifier = "add-files", focusable = false
          ):
            this.onAction(page) do(this: Button, receiver: UploadPage):
              receiver.chooseFiles()
        VStack:
          this.arrangedSizing = svspFillAvailableWidth
          this.distribution = svdNatural
          this.alignment = svaFill
          this.spacing = 12
          this.edgeInsets = insets(8)
          this.backgroundColor = PanelColor
          component(fileForm, page.form)
          HStack:
            this.distribution = svdNatural
            this.spacing = 8
            Button("Cancel", identifier = "cancel", focusable = false):
              this.onAction(page) do(this: Button, receiver: UploadPage):
                receiver.cancel()
            Button("Save", identifier = "save", focusable = false):
              this.onAction(page) do(this: Button, receiver: UploadPage):
                receiver.save()
      Label(identifier = "status", labelStyle = lsStatus):
        this.bindValue("status", page.status) do(label: Label, value: string):
          label.stringValue = value
      Label(identifier = "events", labelStyle = lsStatus):
        this.bindValue("events", page.events) do(label: Label, value: seq[string]):
          label.stringValue = "Events: " & value.join("  ·  ")

proc runUploadFormDemo*() =
  let page = newUploadPage()
  sharedApplication().runWindow(
    newWindow("Upload files", frame = rect(80, 80, 980, 640)), page.newUploadView()
  )

when isMainModule and not defined(merendaTests):
  runUploadFormDemo()
