import std/[unittest, unicode]

import figdraw
import sigils/core

import merenda/nimkit

type
  ResizeTableDataSource = ref object of Responder
    rows: int

  ResizeTableDelegate = ref object of Responder
    hostedColumn: string

protocol ResizeTableDataSourceMethods of TableViewDataSource:
  method numberOfRows(source: ResizeTableDataSource, tableView: TableView): int =
    source.rows

  method textForCell(
      source: ResizeTableDataSource, tableView: TableView, row: int, column: TableColumn
  ): string =
    column.identifier & ":" & $row

protocol ResizeTableDelegateMethods of TableViewDelegate:
  method viewForCell(
      delegate: ResizeTableDelegate, tableView: TableView, row: int, column: TableColumn
  ): View =
    if column.identifier == delegate.hostedColumn:
      return newLabel(column.identifier & ":" & $row)
    nil

proc newResizeTableDataSource(rows: int): ResizeTableDataSource =
  result = ResizeTableDataSource(rows: rows)
  initResponder(result)
  discard result.withProtocol(ResizeTableDataSourceMethods)

proc newResizeTableDelegate(hostedColumn: string): ResizeTableDelegate =
  result = ResizeTableDelegate(hostedColumn: hostedColumn)
  initResponder(result)
  discard result.withProtocol(ResizeTableDelegateMethods)

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add rune

proc renderedTextOriginX(window: Window, text: string): float32 =
  let renders = window.buildRenders()
  if DefaultDrawLevel notin renders:
    return -1.0'f32
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText and node.renderedText() == text:
      return node.screenBox.x.float32
  -1.0'f32

proc hostedTextOriginX(tableView: TableView, text: string): float32 =
  for rowView in tableView.contentView().subviews():
    for cellView in rowView.subviews():
      if cellView of TextField and TextField(cellView).text == text:
        return cellView.frame().origin.x
  -1.0'f32

proc tableHeaderBorderPoint(tableView: TableView, column: TableColumn): Point =
  let header = tableView.tableHeaderColumnRect(column)
  tableView.pointToWindow(
    initPoint(header.maxX - 1.0'f32, header.origin.y + header.size.height * 0.5'f32)
  )

suite "NimKit TableView column resizing":
  test "column resize redraws text cells during a synthetic drag":
    let
      window = newWindow("Table column resize", frame = rect(0, 0, 460, 180))
      root = newView(frame = rect(0, 0, 460, 180))
      tableView = newTableView(frame = rect(12, 12, 430, 150))
      source = newResizeTableDataSource(3)
      delegate = newResizeTableDelegate("state")
      project = newTableColumn("project", "Project", width = 100.0)
      state = newTableColumn("state", "State", width = 100.0)
      owner = newTableColumn("owner", "Owner", width = 100.0)

    defer:
      window.close()
    tableView.addColumn(project)
    tableView.addColumn(state)
    tableView.addColumn(owner)
    tableView.rowHeight = 28.0
    tableView.dataSource = source
    tableView.delegate = delegate
    root.addSubview(tableView)
    window.setContentView(root)
    discard window.buildRenders()

    let
      initialOwnerTextX = window.renderedTextOriginX("owner:0")
      initialStateX = tableView.hostedTextOriginX("state:0")
      start = tableView.tableHeaderBorderPoint(project)
      stop = initPoint(start.x + 32.0'f32, start.y)

    check initialOwnerTextX >= 0.0'f32
    check initialStateX >= 0.0'f32
    check window.mouseDownAt(start)
    check window.mouseDraggedAt(stop)
    check abs(project.width - 132.0'f32) < 0.1'f32
    check abs(window.renderedTextOriginX("owner:0") - initialOwnerTextX - 32.0'f32) <
      0.1'f32
    check abs(tableView.hostedTextOriginX("state:0") - initialStateX - 32.0'f32) <
      0.1'f32
    check window.mouseUpAt(stop)

  test "fill-sized column resize keeps the dragged border under the cursor":
    let
      window = newWindow("Fill table column resize", frame = rect(0, 0, 520, 180))
      root = newView(frame = rect(0, 0, 520, 180))
      tableView = newTableView(frame = rect(12, 12, 480, 150))
      source = newResizeTableDataSource(3)
      first =
        newTableColumn("first", "First", width = 160.0, sizingPolicy = tcspFlexible)
      second =
        newTableColumn("second", "Second", width = 220.0, sizingPolicy = tcspFlexible)
      third = newTableColumn("third", "Third", width = 100.0, sizingPolicy = tcspFixed)

    defer:
      window.close()
    tableView.columnSizing = tvcsFill
    tableView.addColumn(first)
    tableView.addColumn(second)
    tableView.addColumn(third)
    tableView.rowHeight = 28.0
    tableView.dataSource = source
    root.addSubview(tableView)
    window.setContentView(root)
    discard window.buildRenders()

    let
      initialHeader = tableView.tableHeaderColumnRect(second)
      start = tableView.tableHeaderBorderPoint(second)
      stop = initPoint(start.x + 40.0'f32, start.y)

    check window.mouseDownAt(start)
    check window.mouseDraggedAt(stop)
    discard window.buildRenders()
    let finalHeader = tableView.tableHeaderColumnRect(second)
    check abs(finalHeader.origin.x - initialHeader.origin.x) < 0.1'f32
    check abs(finalHeader.maxX - initialHeader.maxX - 40.0'f32) < 0.1'f32
    check window.mouseUpAt(stop)
    discard window.buildRenders()
    let settledHeader = tableView.tableHeaderColumnRect(second)
    check abs(settledHeader.origin.x - initialHeader.origin.x) < 0.1'f32
    check abs(settledHeader.maxX - initialHeader.maxX - 40.0'f32) < 0.1'f32
