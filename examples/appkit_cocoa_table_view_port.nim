import std/[os, strutils]

import knutella/appkit
import knutella/objc

proc maxFramesFromEnv(defaultValue = -1): int =
  let raw = getEnv("KNUTELLA_EXAMPLE_FRAMES").strip()
  if raw.len == 0:
    return defaultValue
  try:
    parseInt(raw)
  except ValueError:
    defaultValue

proc objectDisplayString(value: NSObject): NSString =
  if value.isNil:
    return @ns""
  if value.isKindOfClass(NSString):
    return NSString(value)
  let raw = cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs.}](objc_msgSend)(
    value.value, getSelector("description")
  )
  if raw.isNil:
    return @ns""
  NSString(value: raw)

objcImpl:
  type FootballClub = object of NSObject
    xName {.set: setName, get: name.}: NSString
    xFoundationYear {.set: setFoundationYear, get: foundationYear.}: NSString

  method init*(self: var FootballClub): FootballClub =
    result =
      asTypeRaw[FootballClub](callSuperIdFrom(FootballClub, self, getSelector("init")))
    if result.isNil:
      return
    result.xName = @ns"FC Generic"
    result.xFoundationYear = @ns"2020"

objcImpl:
  type TableViewController = object of NSObject
    xFootballClubs: seq[FootballClub]
    xTableView: NSTableView
    xStatus: NSTextField

  method init*(self: var TableViewController): TableViewController =
    result = asTypeRaw[TableViewController](
      callSuperIdFrom(TableViewController, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.xFootballClubs = @[]
    result.xTableView = NSTableView(value: nil)
    result.xStatus = NSTextField(value: nil)

  method setTableView*(self: TableViewController, table: NSTableView) =
    self.xTableView =
      if table.isNil:
        NSTableView(value: nil)
      else:
        retain(table)

  method setStatusLabel*(self: TableViewController, label: NSTextField) =
    self.xStatus =
      if label.isNil:
        NSTextField(value: nil)
      else:
        retain(label)

  method fillTestData*(self: TableViewController) =
    var club1 = FootballClub.new()
    club1.setName(@ns"Manchester United")
    club1.setFoundationYear(@ns"1878")
    self.xFootballClubs.add(club1)

    var club2 = FootballClub.new()
    club2.setName(@ns"Liverpool")
    club2.setFoundationYear(@ns"1892")
    self.xFootballClubs.add(club2)

    var club3 = FootballClub.new()
    club3.setName(@ns"Real Madrid")
    club3.setFoundationYear(@ns"1902")
    self.xFootballClubs.add(club3)

    var club4 = FootballClub.new()
    club4.setName(@ns"Barcelona")
    club4.setFoundationYear(@ns"1899")
    self.xFootballClubs.add(club4)

  method numberOfRowsInTableView*(
      self: TableViewController, tableView: NSTableView
  ): int =
    self.xFootballClubs.len

  method tableView*(
      self: TableViewController,
      tableView: NSTableView,
      tableColumn {.kw("objectValueForTableColumn").}: NSTableColumn,
      row {.kw("row").}: int,
  ): NSObject =
    if row < 0 or row >= self.xFootballClubs.len or tableColumn.isNil:
      return NSObject(value: nil)
    let club = self.xFootballClubs[row]
    let identifier = tableColumn.identifier()
    if identifier == @ns"name":
      return NSObject(club.name())
    if identifier == @ns"foundationYear":
      return NSObject(club.foundationYear())
    NSObject(value: nil)

  method tableView*(
      self: TableViewController,
      tableView: NSTableView,
      value {.kw("setObjectValue").}: NSObject,
      tableColumn {.kw("forTableColumn").}: NSTableColumn,
      row {.kw("row").}: int,
  ) =
    if row < 0 or row >= self.xFootballClubs.len or tableColumn.isNil:
      return
    let club = self.xFootballClubs[row]
    let identifier = tableColumn.identifier()
    let text = objectDisplayString(value)
    if identifier == @ns"name":
      club.setName(text)
    elif identifier == @ns"foundationYear":
      club.setFoundationYear(text)

  method addClub*(self: TableViewController, sender: NSObject) =
    var club = FootballClub.new()
    let nextIndex = self.xFootballClubs.len + 1
    club.setName(@ns("FC Generic " & $nextIndex))
    club.setFoundationYear(@ns("20" & $(20 + (nextIndex mod 50))))
    self.xFootballClubs.add(club)
    if not self.xTableView.isNil:
      self.xTableView.selectRow(self.xFootballClubs.len - 1)
      self.xTableView.reloadData()
    if not self.xStatus.isNil:
      self.xStatus.setStringValue(
        @ns("Added club. Total rows: " & $self.xFootballClubs.len)
      )

  method removeClub*(self: TableViewController, sender: NSObject) =
    if self.xFootballClubs.len == 0:
      if not self.xStatus.isNil:
        self.xStatus.setStringValue(@ns"No rows to remove.")
      return
    var row = -1
    if not self.xTableView.isNil:
      row = self.xTableView.selectedRow()
    if row < 0 or row >= self.xFootballClubs.len:
      row = self.xFootballClubs.len - 1
    self.xFootballClubs.del(row)
    if not self.xTableView.isNil:
      if self.xFootballClubs.len > 0:
        self.xTableView.selectRow(min(row, self.xFootballClubs.len - 1))
      else:
        self.xTableView.deselectAll(NSObject(value: nil))
      self.xTableView.reloadData()
    if not self.xStatus.isNil:
      self.xStatus.setStringValue(
        @ns("Removed row " & $row & ". Total rows: " & $self.xFootballClubs.len)
      )

  method dealloc(self: TableViewController) {.used.} =
    self.xFootballClubs = @[]
    self.xTableView = NSTableView(value: nil)
    self.xStatus = NSTextField(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(TableViewController, self, getSelector("dealloc"))

when isMainModule and not defined(knutellaNoExampleMain):
  var app = NSApp()
  var window = newWindow(120, 120, 480, 360, "Cocoa Table View (KNutella Port)")
  var root = newView(0, 0, 480, 360)
  root.setBackgroundColor(nsColor(0.95, 0.95, 0.95, 1.0))

  var scrollView = NSScrollView.new()
  scrollView.setFrame(nsRect(20.0, 29.0, 372.0, 311.0))
  scrollView.setHasVerticalScroller(true)
  scrollView.setHasHorizontalScroller(false)
  scrollView.setAutohidesScrollers(true)

  var clubsTable = NSTableView.new()
  clubsTable.setFrame(nsRect(0.0, 0.0, 370.0, 310.0))
  clubsTable.setRowHeight(24.0)
  clubsTable.setIntercellSpacing(nsSize(3.0, 2.0))
  clubsTable.setUsesAlternatingRowBackgroundColors(true)

  var nameColumn = NSTableColumn.new(@ns"name")
  nameColumn.setWidth(253.5)
  nameColumn.headerCell().setTitle(@ns"Name")

  var foundationYearColumn = NSTableColumn.new(@ns"foundationYear")
  foundationYearColumn.setWidth(110.0)
  foundationYearColumn.headerCell().setTitle(@ns"Foundation year")

  clubsTable.addTableColumn(nameColumn)
  clubsTable.addTableColumn(foundationYearColumn)
  scrollView.setDocumentView(clubsTable.NSView)
  root.addSubview(scrollView)

  var status = newTextField(
    20.0, 8.0, 450.0, 18.0,
    "Select rows by clicking in the table. Use Add/Remove to edit.",
  )
  status.setDrawsBackground(false)
  status.setTextColor(nsColor(0.2, 0.2, 0.2, 1.0))
  root.addSubview(status)

  var controller = TableViewController.new()
  controller.setTableView(clubsTable)
  controller.setStatusLabel(status)
  controller.fillTestData()
  clubsTable.setDataSource(ID(value: controller.value))
  clubsTable.setDelegate(ID(value: controller.value))
  clubsTable.reloadData()
  clubsTable.selectRow(0)

  var addButton = newButton(411.0, 321.0, 59.0, 19.0, "Add")
  addButton.setOnClick(
    proc(sender: NSButton) =
      controller.addClub(sender.NSObject)
  )
  root.addSubview(addButton)

  var removeButton = newButton(411.0, 295.0, 59.0, 19.0, "Remove")
  removeButton.setOnClick(
    proc(sender: NSButton) =
      controller.removeClub(sender.NSObject)
  )
  root.addSubview(removeButton)

  window.setContentView(root)
  app.addWindow(window)
  window.makeKeyAndOrderFront(app)
  discard window.makeFirstResponder(clubsTable.NSResponder)

  echo "table rows: ", clubsTable.numberOfRows()
  echo "columns: ", clubsTable.numberOfColumns()
  echo "selected row: ", clubsTable.selectedRow()

  let frames = maxFramesFromEnv()
  try:
    if frames < 0:
      app.run()
    else:
      discard app.runForFrames(frames)
  except CatchableError as exc:
    echo "Unable to run table view example: ", exc.msg

  removeButton.value = nil
  addButton.value = nil
  controller.value = nil
  status.value = nil
  foundationYearColumn.value = nil
  nameColumn.value = nil
  clubsTable.value = nil
  scrollView.value = nil
  root.value = nil
  window.value = nil
  app.value = nil
