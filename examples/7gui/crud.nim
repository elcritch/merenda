import std/strutils

import merenda/nimkit

import sigils/[core, selectors]

type
  Person = object
    id: int
    name: string
    surname: string

  CrudController = ref object of Responder
    people: seq[Person]
    nextId: int
    table: TableView
    prefixField: TextField
    nameField: TextField
    surnameField: TextField
    createButton: Button
    updateButton: Button
    deleteButton: Button
    status: Label

func displayName(person: Person): string =
  person.surname & ", " & person.name

proc filteredIndexes(controller: CrudController): seq[int] =
  let prefix = controller.prefixField.stringValue.strip().toLowerAscii()
  for index, person in controller.people:
    if prefix.len == 0 or person.surname.toLowerAscii().startsWith(prefix):
      result.add index

proc sourceIndexForRow(controller: CrudController, row: int): int =
  let indexes = controller.filteredIndexes()
  if row in 0 ..< indexes.len:
    indexes[row]
  else:
    -1

proc selectedSourceIndex(controller: CrudController): int =
  controller.sourceIndexForRow(controller.table.selectedIndex)

proc updateCrudButtons(controller: CrudController) =
  let hasSelection = controller.selectedSourceIndex() >= 0
  controller.updateButton.enabled = hasSelection
  controller.deleteButton.enabled = hasSelection

proc updateCrudStatus(controller: CrudController) =
  let
    visible = controller.filteredIndexes().len
    total = controller.people.len
  controller.status.text = $visible & " of " & $total & " records shown"

proc reloadCrudTable(controller: CrudController) =
  controller.table.reloadData()
  controller.updateCrudButtons()
  controller.updateCrudStatus()

proc fillSelection(controller: CrudController) =
  let index = controller.selectedSourceIndex()
  if index notin 0 ..< controller.people.len:
    controller.updateCrudButtons()
    return
  controller.nameField.text = controller.people[index].name
  controller.surnameField.text = controller.people[index].surname
  controller.updateCrudButtons()

protocol CrudDataSource of TableViewDataSource:
  method numberOfRows(controller: CrudController, tableView: TableView): int =
    discard tableView
    controller.filteredIndexes().len

  method textForCell(
      controller: CrudController, tableView: TableView, row: int, column: TableColumn
  ): string =
    discard tableView
    discard column
    let index = controller.sourceIndexForRow(row)
    if index in 0 ..< controller.people.len:
      controller.people[index].displayName()
    else:
      ""

  method identifierForRow(
      controller: CrudController, tableView: TableView, row: int
  ): string =
    discard tableView
    let index = controller.sourceIndexForRow(row)
    if index in 0 ..< controller.people.len:
      $controller.people[index].id
    else:
      ""

  method rowForIdentifier(
      controller: CrudController, tableView: TableView, identifier: string
  ): int =
    discard tableView
    for row, index in controller.filteredIndexes():
      if index in 0 ..< controller.people.len and
          $controller.people[index].id == identifier:
        return row
    -1

protocol CrudDelegate of TableViewDelegate:
  method tableRowHeight(
      controller: CrudController, tableView: TableView, row: int
  ): float32 =
    discard controller
    discard tableView
    discard row
    28.0

proc newCrudController(
    table: TableView,
    prefixField, nameField, surnameField: TextField,
    createButton, updateButton, deleteButton: Button,
    status: Label,
): CrudController =
  result = CrudController(
    people:
      @[
        Person(id: 1, name: "Hans", surname: "Emil"),
        Person(id: 2, name: "Max", surname: "Mustermann"),
        Person(id: 3, name: "Roman", surname: "Tisch"),
      ],
    nextId: 4,
    table: table,
    prefixField: prefixField,
    nameField: nameField,
    surnameField: surnameField,
    createButton: createButton,
    updateButton: updateButton,
    deleteButton: deleteButton,
    status: status,
  )
  initResponder(result)
  discard result.withProtocol(CrudDataSource)
  discard result.withProtocol(CrudDelegate)

proc prefixChanged(controller: CrudController, sender: DynamicAgent) {.slot.} =
  if sender == DynamicAgent(controller.prefixField):
    controller.table.selectedIndex = -1
    controller.reloadCrudTable()

proc selectionChanged(controller: CrudController, sender: DynamicAgent) {.slot.} =
  if sender == DynamicAgent(controller.table):
    controller.fillSelection()

proc createPerson(controller: CrudController, sender: DynamicAgent) =
  discard sender
  let
    name = controller.nameField.stringValue.strip()
    surname = controller.surnameField.stringValue.strip()
  if name.len == 0 and surname.len == 0:
    return
  controller.people.add Person(id: controller.nextId, name: name, surname: surname)
  inc controller.nextId
  controller.reloadCrudTable()

proc updatePerson(controller: CrudController, sender: DynamicAgent) =
  discard sender
  let index = controller.selectedSourceIndex()
  if index notin 0 ..< controller.people.len:
    return
  controller.people[index].name = controller.nameField.stringValue.strip()
  controller.people[index].surname = controller.surnameField.stringValue.strip()
  controller.reloadCrudTable()

proc deletePerson(controller: CrudController, sender: DynamicAgent) =
  discard sender
  let index = controller.selectedSourceIndex()
  if index notin 0 ..< controller.people.len:
    return
  controller.people.delete(index)
  controller.table.selectedIndex = -1
  controller.reloadCrudTable()

let
  app = sharedApplication()
  window = newWindow("7GUIs CRUD", frame = rect(140, 140, 520, 420))
  root = newView()
  title = newTitleLabel("CRUD")
  prefixLabel = newFormLabel("Filter prefix")
  prefixField = newTextField("")
  table = newTableView()
  editForm = newFormView()
  nameField = newTextField("")
  surnameField = newTextField("")
  buttonRow = newStackView(laHorizontal)
  createButton = newButton("Create")
  updateButton = newButton("Update")
  deleteButton = newButton("Delete")
  status = newStatusLabel("")
  controller = newCrudController(
    table, prefixField, nameField, surnameField, createButton, updateButton,
    deleteButton, status,
  )
  createAction = actionSelector("sevenGuiCrudCreate")
  updateAction = actionSelector("sevenGuiCrudUpdate")
  deleteAction = actionSelector("sevenGuiCrudDelete")

table.addColumn(newTableColumn("person", "Name", width = 320.0))
table.dataSource = controller
table.delegate = controller
table.showsHeader = false
table.selectionMode = tsmSingle
table.usesAlternatingRowBackgrounds = true
table.visibleRows = 8

prefixField.connect(textDidChange, controller, prefixChanged)
table.connect(selectionDidChange, controller, selectionChanged)
createButton.target = newActionTarget(
  createAction,
  proc(sender: DynamicAgent) =
    controller.createPerson(sender),
)
createButton.action = createAction
updateButton.target = newActionTarget(
  updateAction,
  proc(sender: DynamicAgent) =
    controller.updatePerson(sender),
)
updateButton.action = updateAction
deleteButton.target = newActionTarget(
  deleteAction,
  proc(sender: DynamicAgent) =
    controller.deletePerson(sender),
)
deleteButton.action = deleteAction

editForm.edgeInsets = insets(0.0)
editForm.spacing[dcol] = 12.0
editForm.spacing[drow] = 10.0
editForm.minFieldWidth = 190.0
editForm.addRow(newFormLabel("Name"), nameField)
editForm.addRow(newFormLabel("Surname"), surnameField)

buttonRow.spacing = 8.0
buttonRow.alignment = svaFill
buttonRow.distribution = svdFillEqually
buttonRow.addArrangedSubview(createButton, updateButton, deleteButton)

root.addSubviews(
  autoNames(title, prefixLabel, prefixField, table, editForm, buttonRow, status)
)

activateConstraints:
  title[atTop] == root[atTop] + 24.0
  title[atLeft] == root[atLeft] + 28.0
  title[atRight] == root[atRight] - 28.0
  title[atHeight] == 30.0
  prefixLabel[atLeft] == title[atLeft]
  prefixLabel[atTop] == title[atBottom] + 14.0
  prefixLabel[atWidth] == 90.0
  prefixField[atLeft] == prefixLabel[atRight] + 10.0
  prefixField[atRight] == title[atRight]
  prefixField[atCenterY] == prefixLabel[atCenterY]
  table[atTop] == prefixField[atBottom] + 14.0
  table[atLeft] == title[atLeft]
  table[atRight] == title[atRight]
  table[atBottom] == editForm[atTop] - 14.0
  editForm[atLeft] == title[atLeft]
  editForm[atRight] == title[atRight]
  editForm[atHeight] == 76.0
  editForm[atBottom] == buttonRow[atTop] - 12.0
  buttonRow[atLeft] == title[atLeft]
  buttonRow[atRight] == title[atRight]
  buttonRow[atHeight] == 34.0
  buttonRow[atBottom] == status[atTop] - 12.0
  status[atLeft] == title[atLeft]
  status[atRight] == title[atRight]
  status[atHeight] == 28.0
  status[atBottom] == root[atBottom] - 24.0

controller.reloadCrudTable()
app.runWindow(window, root, prefixField)
