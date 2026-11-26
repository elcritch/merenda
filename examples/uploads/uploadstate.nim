## Observable model and editor session used by both reactive upload demos.
import std/[os, sequtils, strutils]
import sigils/[core, reactive, threadProxies, threads]
import merenda/nimkit
import ./uploadfiles

export uploadfiles

type
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

  UploadPage* = ref object of Responder
    ## The parent component. It reacts to the upload form's events.
    store*: UploadStore
    form*: FileForm
    status*: Sigil[string]
    events*: Sigil[seq[string]]
    uploads*: seq[seq[UploadFile]]
    backend: AgentProxy[TagBackend]

proc filesChanged*(store: UploadStore, files: seq[UploadFile]) {.signal.}
proc uploadRequested*(store: UploadStore, files: seq[UploadFile]) {.signal.}
proc tagSearchStarted*(form: FileForm, query: string) {.signal.}

# Pure rules: derived from file values and never stored.

proc fileId*(file: UploadFile): int =
  file.id

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
  let index = next.findIt(it.id == id)
  if index >= 0:
    next.delete(index)
    store.files <- next
    if store.selected{} == id:
      # Select the file that moved into the removed row, or the new last row.
      let id = (if next.len == 0: 0 else: next[min(index, next.high)].id)
      store.selectFile(id)
    emit store.filesChanged(next)

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
    let file = files.item(selected{}){}.get(UploadFile())
    (category: file.category, subcategory: file.subcategory)
  result.tags = computedNow[seq[string]]:
    files.item(selected{}){}.get(UploadFile()).tags
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
  form.touched <- form.touched{} + {field}

type FileTextField* = range[ffName .. ffAltText]
type FileTextContext* = tuple[id: int, field: FileTextField]

proc readFileText*(form: FileForm, key: FileTextContext): string =
  if key.id in form.store.files:
    let file = form.store.files[key.id]
    case key.field
    of ffName:
      result = file.name
    of ffAltText:
      result = file.altText

proc editFileText*(form: FileForm, key: FileTextContext, text: string) =
  if form.store.selected{} == key.id:
    form.touch(key.field)
    case key.field
    of ffName:
      form.store.setName(key.id, text)
    of ffAltText:
      form.store.setAltText(key.id, text)

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
    page.backend = newTagBackend()
    connectThreaded(page.backend, tagsFound, page, UploadPage.showTagResults())
  emit page.backend.searchTags(query)

proc onUploadRequested(page: UploadPage, files: seq[UploadFile]) {.slot.} =
  page.uploads.add files
  page.logEvent("uploadRequested: " & $files.len & " file(s)")
  page.status <- uploadSummary(files)

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
    page.store.addPaths(panel.selectedUrls.mapIt(it.filePathFromUrl()))
