## A multi-file upload form built with DirectView and Sigils.
## Run `nim ic -r examples/uploads/upload_form_direct_demo.nim`.
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
import std/strutils
import sigils/reactive
import merenda/nimkit
import merenda/nimkit/directviews
import ./uploadstate

export uploadstate

type FileRow* = ref object of StackView ## A list row that selects its file when clicked.
  store: BackRef[UploadStore]
  fileId: int

const
  ErrorColor = color(0.85, 0.2, 0.2, 1)
  SelectedColor = color(0.3, 0.55, 1.0, 0.22)
  ClearColor = color(0, 0, 0, 0)
  PanelColor = color(0.5, 0.5, 0.5, 0.08)

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
      this.spacing = 2
      for id in state.ids:
        keyed(id):
          component(fileRow, id, id == state.selected, store)
      if state.ids.len == 0:
        Label(stringValue = "No files. Add some to upload.")

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

template bindFileText(field: TextField, form: FileForm, id: int, kind: FileTextField) =
  let key: FileTextContext = (id, kind)
  field.bindTextField(
    $kind, form.store.files.item(id), form, key, readFileText, editFileText
  )

proc fileFields(context: DirectNode, form: FileForm, id: int) =
  ## Rule 1: this component is keyed by file id, so selecting another file
  ## replaces these widgets and their edit state.
  let store = form.store
  context.viewBody:
    VStack:
      this.identifier = "form-" & $id
      this.distribution = svdNatural
      this.spacing = 6
      Label(identifier = "path", labelStyle = lsStatus):
        this.stringValue = store.files[id].path
      Label(stringValue = "File name")
      TextField(identifier = "name"):
        this.bindFileText(form, id, ffName)
      component(issueLabel, form, ffName)
      Label(stringValue = "Alt text")
      TextField(identifier = "alt-text", placeholder = "Describe the image"):
        this.bindFileText(form, id, ffAltText)
      component(issueLabel, form, ffAltText)
      Label(stringValue = "Category")
      component(bindBody, form.choice, form, drawChoices)
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
      if id in form.store.files:
        keyed(id):
          component(fileFields, form, id)
      else:
        Label(stringValue = "Select or add a file to edit its details.")

proc newUploadView*(page: UploadPage): DirectView =
  result = newDirectView()
  result.viewBody:
    VStack:
      this.distribution = svdNatural
      this.spacing = 12
      this.edgeInsets = insets(16)
      Label(stringValue = "Upload files", labelStyle = lsHeading)
      HStack:
        this.distribution = svdNatural
        this.spacing = 16
        VStack:
          this.identifier = "file-list"
          this.distribution = svdNatural
          this.edgeInsets = insets(8)
          this.backgroundColor = PanelColor
          Label(identifier = "file-count", labelStyle = lsStatus):
            this.bindValue("count", page.store.files.order) do(
              label: Label, ids: seq[int]
            ):
              label.stringValue =
                (if ids.len == 1: "1 file" else: $ids.len & " files") & " to upload"
          component(bindBody, page.store.listState, page.store, drawFileList)
          Button(
            "Upload more documents…", identifier = "add-files", focusable = false
          ):
            this.onAction(page) do(this: Button, receiver: UploadPage):
              receiver.chooseFiles()
        VStack:
          this.arrangedSizing = svspFillAvailableWidth
          this.distribution = svdNatural
          this.spacing = 12
          this.edgeInsets = insets(8)
          this.backgroundColor = PanelColor
          component(bindBody, page.form.store.selected, page.form, drawForm)
          HStack:
            this.distribution = svdNatural
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
