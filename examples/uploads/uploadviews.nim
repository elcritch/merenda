## Native widget construction shared by the two MVC upload demos.
import merenda/nimkit
import ./uploadfiles

type
  FileRow* = tuple[select, remove: Button, detail: Label]

  FileEditor* = object
    name*, altText*: TextField
    categories*, subcategories*: StackView
    special*: Button
    tags*: TagController
    issues*: array[FileField, Label]

  UploadView* = ref object of StackView
    addButton*, cancelButton*, saveButton*: Button
    list*, form*: StackView
    count*, status*: Label
    rows*: seq[FileRow]
    editor*: FileEditor

proc stack*(orientation = laVertical, spacing = 8): StackView =
  result = newStackView(orientation)
  result.distribution = svdNatural
  result.spacing = spacing.float32

proc clear*(stack: StackView) =
  for child in stack.arrangedSubviews:
    child.removeFromSuperview()

proc addFileRow*(list: StackView, id: int): FileRow =
  result = (newRadioButton(), newButton("×"), newStatusLabel())
  result.select.identifier = "file-" & $id
  result.remove.identifier = "remove-" & $id
  result.remove.focusable = false
  let titles = stack(spacing = 2)
  titles.addArrangedSubview(result.select, result.detail)
  let line = stack(laHorizontal)
  line.alignment = svaCenter
  line.addArrangedSubview((titles, svspFillAvailableWidth), result.remove)
  list.addArrangedSubview(line)

proc addFileEditor*(
    container: StackView, file: UploadFile, tags: TagController
): FileEditor =
  result = FileEditor(
    name: newTextField(file.name),
    altText: newTextField(file.altText),
    categories: stack(laHorizontal, 12),
    subcategories: stack(laHorizontal, 12),
    special: newCheckBox("Special file (only one per upload)"),
    tags: tags,
  )
  result.name.identifier = "name"
  result.altText.identifier = "alt-text"
  result.altText.placeholder = "Describe the image"
  result.special.identifier = "special"
  result.special.state = if file.special: bsOn else: bsOff
  for field in FileField:
    result.issues[field] = newLabel()
    result.issues[field].identifier = "issue-" & $field
    result.issues[field].textColor = color(0.85, 0.2, 0.2, 1)
  let picker = newTagPicker(result.tags, tlpInline, "Search tags…")
  picker.identifier = "tags"
  container.addArrangedSubview(
    newStatusLabel(file.path),
    newLabel("File name"),
    result.name,
    result.issues[ffName],
    newLabel("Alt text"),
    result.altText,
    result.issues[ffAltText],
    newLabel("Category"),
    result.categories,
    result.issues[ffCategory],
    newLabel("Subcategory"),
    result.subcategories,
    result.issues[ffSubcategory],
    newLabel("Tags"),
    picker,
    result.special,
  )

proc newUploadView*(): UploadView =
  result = UploadView(
    addButton: newButton("Upload more documents…"),
    cancelButton: newButton("Cancel"),
    saveButton: newButton("Save"),
    list: stack(spacing = 2),
    form: stack(spacing = 6),
    count: newStatusLabel(),
    status: newStatusLabel("Select a file to edit its upload details."),
  )
  initStackViewFields(result, laVertical)
  result.addButton.identifier = "add-files"
  result.cancelButton.identifier = "cancel"
  result.saveButton.identifier = "save"
  result.status.identifier = "status"
  let sidebar = stack()
  sidebar.addArrangedSubview(result.count, result.list, result.addButton)
  let actions = stack(laHorizontal)
  actions.addArrangedSubview(result.cancelButton, result.saveButton)
  let panel = stack(spacing = 12)
  panel.addArrangedSubview(result.form, actions)
  for column in [sidebar, panel]:
    column.edgeInsets = insets(8)
    column.backgroundColor = color(0.5, 0.5, 0.5, 0.08)
  let columns = stack(laHorizontal, 16)
  columns.addArrangedSubview(sidebar, (panel, svspFillAvailableWidth))
  result.distribution = svdNatural
  result.spacing = 12
  result.edgeInsets = insets(16)
  result.addArrangedSubview(newHeadingLabel("Upload files"), columns, result.status)
