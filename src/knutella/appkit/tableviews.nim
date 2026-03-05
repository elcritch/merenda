import std/math

import ./runtime
import ./controls
import ./events
import ./textfields

const
  defaultHeaderHeight = 25.0'f32
  defaultRowHeight = 24.0'f32
  defaultColumnWidth = 160.0'f32

proc clampColumnWidth(width: float32): float32 {.inline.} =
  max(width, 40.0'f32)

proc clearSubviews(view: NSView) =
  if view.isNil:
    return
  let children = view.subviews()
  for child in children:
    child.removeFromSuperview()

proc adjustedDataCellFrame(frame: NSRect, spacing: NSSize): NSRect =
  result = frame
  result.origin.x += spacing.width - 1.0
  result.origin.y += spacing.height
  result.size.width -= spacing.width
  result.size.height -= spacing.height
  result.size.height -= 1.0
  if result.origin.x < 0.0:
    result.origin.x = 0.0
  if result.origin.y < 0.0:
    result.origin.y = 0.0
  if result.size.width < 0.0:
    result.size.width = 0.0
  if result.size.height < 0.0:
    result.size.height = 0.0

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

proc viewOriginInWindow(view: NSView): NSPoint =
  var current = retain(view)
  while not current.isNil:
    let frame = current.frame()
    let bounds = current.bounds()
    result.x += frame.origin.x - bounds.origin.x
    result.y += frame.origin.y - bounds.origin.y
    current = current.superview()

proc numberOfRowsFromDataSource(tableView: NSTableView): int
proc objectValueFromDataSource(
  tableView: NSTableView, column: NSTableColumn, row: int
): NSObject

proc setObjectValueOnDataSource(
  tableView: NSTableView, value: NSObject, column: NSTableColumn, row: int
)

proc rebuildHeader(tableView: NSTableView)
proc rebuildRows(tableView: NSTableView)

objcImpl:
  type TableRowsDataSource {.structural.} =
    concept self
        method numberOfRowsInTableView*(
          self: TableRowsDataSource, tableView: NSTableView
        ): int

objcImpl:
  type TableObjectValueDataSource {.structural.} =
    concept self
        method tableView*(
          self: TableObjectValueDataSource,
          tableView: NSTableView,
          tableColumn {.kw("objectValueForTableColumn").}: NSTableColumn,
          row {.kw("row").}: int,
        ): NSObject

objcImpl:
  type TableSetObjectValueDataSource {.structural.} =
    concept self
        method tableView*(
          self: TableSetObjectValueDataSource,
          tableView: NSTableView,
          value {.kw("setObjectValue").}: NSObject,
          tableColumn {.kw("forTableColumn").}: NSTableColumn,
          row {.kw("row").}: int,
        )

objcImpl:
  type NSTableHeaderCell* = object of NSCell
    xTitle {.set: setTitle, get: title.}: NSString

  method init*(self: var NSTableHeaderCell): NSTableHeaderCell =
    result = asTypeRaw[NSTableHeaderCell](
      callSuperIdFrom(NSTableHeaderCell, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.xTitle = @ns"Column"

  method stringValue*(self: NSTableHeaderCell): NSString =
    self.xTitle()

  method setStringValue*(self: NSTableHeaderCell, value: NSString) =
    self.xTitle = value

  method dealloc(self: NSTableHeaderCell) {.used.} =
    self.xTitle = NSString(value: nil)
    discard callSuperIdFrom(NSTableHeaderCell, self, getSelector("dealloc"))

objcImpl:
  type NSTableColumn* = object of NSObject
    xIdentifier {.get: identifier.}: NSString
    xWidth {.get: width.}: float32
    xHeaderCell {.set: setHeaderCell, get: headerCell.}: NSTableHeaderCell
    xDataCell {.set: setDataCell, get: dataCell.}: NSCell
    xSortDescriptorPrototype {.
      set: setSortDescriptorPrototype, get: sortDescriptorPrototype
    .}: NSObject

  method init*(self: var NSTableColumn): NSTableColumn =
    result = asTypeRaw[NSTableColumn](
      callSuperIdFrom(NSTableColumn, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.xIdentifier = @ns""
    result.xWidth = defaultColumnWidth
    result.xHeaderCell = NSTableHeaderCell.new()
    result.xDataCell = NSCell.new()
    result.xSortDescriptorPrototype = NSObject(value: nil)

  method initWithIdentifier*(
      self: var NSTableColumn, identifier: NSString
  ): NSTableColumn =
    result = self.init()
    if result.isNil:
      return
    result.xIdentifier = identifier
    let cell = result.xHeaderCell
    if not cell.isNil:
      cell.setTitle(identifier)

  method setIdentifier*(self: NSTableColumn, identifier: NSString) =
    self.xIdentifier = identifier
    let cell = self.headerCell()
    if not cell.isNil:
      cell.setTitle(identifier)

  method setWidth*(self: NSTableColumn, width: float32) =
    self.xWidth = clampColumnWidth(width)

  method dealloc(self: NSTableColumn) {.used.} =
    self.xIdentifier = NSString(value: nil)
    self.xHeaderCell = NSTableHeaderCell(value: nil)
    self.xDataCell = NSCell(value: nil)
    self.xSortDescriptorPrototype = NSObject(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSTableColumn, self, getSelector("dealloc"))

objcImpl:
  type NSTableHeaderView* = object of NSView
    xTableView {.get: tableView.}: NSTableView

  method init*(self: var NSTableHeaderView): NSTableHeaderView =
    result = asTypeRaw[NSTableHeaderView](
      callSuperIdFrom(NSTableHeaderView, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.xTableView = NSTableView(value: nil)
    result.setFrame(nsRect(0.0, 0.0, 1.0, defaultHeaderHeight))
    result.setBackgroundColor(nsColor(0.90, 0.90, 0.90, 1.0))

  method isFlipped*(self: NSTableHeaderView): bool =
    true

  method setTableView*(self: NSTableHeaderView, value: NSTableView) =
    self.xTableView =
      if value.isNil:
        NSTableView(value: nil)
      else:
        retain(value)

  method dealloc(self: NSTableHeaderView) {.used.} =
    self.xTableView = NSTableView(value: nil)
    discard callSuperIdFrom(NSTableHeaderView, self, getSelector("dealloc"))

objcImpl:
  type NSTableView* = object of NSControl
    xColumns: seq[NSTableColumn]
    xDataSource: ID
    xDelegate: ID
    xHeaderViewObj: NSTableHeaderView
    xCornerView: NSView
    xRowHeight {.set: setRowHeight, get: rowHeight.}: float32
    xIntercellSpacing {.set: setIntercellSpacing, get: intercellSpacing.}: NSSize
    xUsesAlternatingRows {.
      set: setUsesAlternatingRowBackgroundColors,
      get: usesAlternatingRowBackgroundColors
    .}: bool
    xSelectedRow {.get: selectedRow.}: int
    xBackgroundColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    xGridColor {.set: setGridColor, get: gridColor.}: NSColor

  method init*(self: var NSTableView): NSTableView =
    result =
      asTypeRaw[NSTableView](callSuperIdFrom(NSTableView, self, getSelector("init")))
    if result.isNil:
      return
    result.setFrame(nsRect(0.0, 0.0, 320.0, 180.0))
    result.xColumns = @[]
    result.xDataSource.value = nil
    result.xDelegate.value = nil
    result.xHeaderViewObj = NSTableHeaderView.new()
    result.xCornerView = NSView(value: nil)
    result.xRowHeight = defaultRowHeight
    result.xIntercellSpacing = nsSize(3.0, 1.0)
    result.xUsesAlternatingRows = true
    result.xSelectedRow = -1
    result.xBackgroundColor = nsColor(1.0, 1.0, 1.0, 1.0)
    result.xGridColor = nsColor(0.85, 0.85, 0.85, 1.0)
    if not result.xHeaderViewObj.isNil:
      result.xHeaderViewObj.setTableView(result)
      result.xHeaderViewObj.setFrame(
        nsRect(0.0, 0.0, max(result.frame().size.width, 1.0), defaultHeaderHeight)
      )

  method initWithFrame*(
      self: var NSTableView,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ): NSTableView =
    result = self.init()
    if result.isNil:
      return
    result.setFrame(nsRect(x.float32, y.float32, max(width, 1.0), max(height, 1.0)))

  method isFlipped*(self: NSTableView): bool =
    true

  method acceptsFirstResponder*(self: NSTableView): bool =
    true

  method dataSource*(self: NSTableView): ID =
    retainId(self.xDataSource)

  method setDataSource*(self: NSTableView, value: ID) =
    self.xDataSource.value = replacedOwnedId(self.xDataSource.value, value.value)

  method delegate*(self: NSTableView): ID =
    retainId(self.xDelegate)

  method setDelegate*(self: NSTableView, value: ID) =
    self.xDelegate.value = replacedOwnedId(self.xDelegate.value, value.value)

  method headerView*(self: NSTableView): NSTableHeaderView =
    if self.xHeaderViewObj.isNil:
      return NSTableHeaderView(value: nil)
    retain(self.xHeaderViewObj)

  method setHeaderView*(self: NSTableView, value: NSTableHeaderView) =
    self.xHeaderViewObj =
      if value.isNil:
        NSTableHeaderView(value: nil)
      else:
        retain(value)
    if not self.xHeaderViewObj.isNil:
      self.xHeaderViewObj.setTableView(self)
      rebuildHeader(self)

  method cornerView*(self: NSTableView): NSView =
    if self.xCornerView.isNil:
      return NSView(value: nil)
    retain(self.xCornerView)

  method setCornerView*(self: NSTableView, value: NSView) =
    self.xCornerView =
      if value.isNil:
        NSView(value: nil)
      else:
        retain(value)

  method tableColumns*(self: NSTableView): NSArray[NSTableColumn] =
    nsArray[NSTableColumn](self.xColumns)

  method numberOfColumns*(self: NSTableView): int =
    self.xColumns.len

  method columnAtIndex*(self: NSTableView, idx: int): NSTableColumn =
    if idx < 0 or idx >= self.xColumns.len:
      return NSTableColumn(value: nil)
    retain(self.xColumns[idx])

  method tableColumnWithIdentifier*(
      self: NSTableView, identifier: NSString
  ): NSTableColumn =
    if identifier.isNil:
      return NSTableColumn(value: nil)
    for column in self.xColumns:
      if column.isNil:
        continue
      if column.identifier() == identifier:
        return retain(column)
    NSTableColumn(value: nil)

  method addTableColumn*(self: NSTableView, tableColumn: NSTableColumn) =
    if tableColumn.isNil:
      return
    for existing in self.xColumns:
      if existing.value == tableColumn.value:
        return
    self.xColumns.add(retain(tableColumn))
    rebuildHeader(self)
    self.reloadData()

  method removeTableColumn*(self: NSTableView, tableColumn: NSTableColumn) =
    if tableColumn.isNil:
      return
    for i, existing in self.xColumns:
      if existing.value == tableColumn.value:
        self.xColumns.del(i)
        break
    rebuildHeader(self)
    self.reloadData()

  method numberOfRows*(self: NSTableView): int =
    numberOfRowsFromDataSource(self)

  method objectValueForTableColumn*(
      self: NSTableView, tableColumn: NSTableColumn, row {.kw("row").}: int
  ): NSObject =
    objectValueFromDataSource(self, tableColumn, row)

  method setObjectValue*(
      self: NSTableView,
      value: NSObject,
      tableColumn {.kw("forTableColumn").}: NSTableColumn,
      row {.kw("row").}: int,
  ) =
    setObjectValueOnDataSource(self, value, tableColumn, row)
    self.reloadData()

  method reloadData*(self: NSTableView) =
    rebuildHeader(self)
    rebuildRows(self)

  method noteNumberOfRowsChanged*(self: NSTableView) =
    self.reloadData()

  method clickedRow*(self: NSTableView): int =
    self.xSelectedRow()

  method selectRow*(self: NSTableView, row: int) =
    let rows = self.numberOfRows()
    if rows <= 0:
      self.xSelectedRow = -1
      self.reloadData()
      return
    self.xSelectedRow = clamp(row, 0, rows - 1)
    self.reloadData()

  method deselectAll*(self: NSTableView, sender: NSObject) =
    self.xSelectedRow = -1
    self.reloadData()

  method mouseDown*(self: NSTableView, event: NSEvent) =
    if event.isNil:
      return
    let rowStride = max(self.xRowHeight + self.xIntercellSpacing.height, 1.0)
    let location = event.locationInWindow()
    let origin = viewOriginInWindow(self.NSView)
    let localY = location.y - origin.y
    let row = floor(localY / rowStride).int
    let rows = self.numberOfRows()
    if row >= 0 and row < rows:
      self.xSelectedRow = row
    else:
      self.xSelectedRow = -1
    self.reloadData()

  method dealloc(self: NSTableView) {.used.} =
    clearSubviews(self)
    self.xColumns = @[]
    self.xDataSource.value = replacedOwnedId(self.xDataSource.value, nil)
    self.xDelegate.value = replacedOwnedId(self.xDelegate.value, nil)
    self.xHeaderViewObj = NSTableHeaderView(value: nil)
    self.xCornerView = NSView(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSTableView, self, getSelector("dealloc"))

proc numberOfRowsFromDataSource(tableView: NSTableView): int =
  let source = tableView.xDataSource
  if source.isNil:
    return 0
  let dataSource = source.asWrapper(TableRowsDataSource)
  if dataSource.isNil:
    return 0
  max(dataSource.numberOfRowsInTableView(tableView), 0)

proc objectValueFromDataSource(
    tableView: NSTableView, column: NSTableColumn, row: int
): NSObject =
  let source = tableView.xDataSource
  if source.isNil:
    return NSObject(value: nil)
  let dataSource = source.asWrapper(TableObjectValueDataSource)
  if dataSource.isNil:
    return NSObject(value: nil)
  dataSource.tableView(tableView, column, row)

proc setObjectValueOnDataSource(
    tableView: NSTableView, value: NSObject, column: NSTableColumn, row: int
) =
  let source = tableView.xDataSource
  if source.isNil:
    return
  let dataSource = source.asWrapper(TableSetObjectValueDataSource)
  if dataSource.isNil:
    return
  dataSource.tableView(tableView, value, column, row)

proc rebuildHeader(tableView: NSTableView) =
  let header = tableView.headerView()
  if header.isNil:
    return
  clearSubviews(header)
  var x = 0.0'f32
  for column in tableView.xColumns:
    if column.isNil:
      continue
    let width = clampColumnWidth(column.width())
    let headerCell = column.headerCell()
    let title =
      if not headerCell.isNil:
        headerCell.title()
      else:
        column.identifier()
    var label = NSTextField.new()
    label.setFrame(nsRect(x, 0.0, width, defaultHeaderHeight))
    label.setStringValue(title)
    label.setEditable(false)
    label.setSelectable(false)
    label.setBezeled(true)
    label.setBordered(true)
    label.setDrawsBackground(true)
    label.setTextColor(nsColor(0.15, 0.15, 0.15, 1.0))
    label.setBackgroundColor(nsColor(0.92, 0.92, 0.92, 1.0))
    header.addSubview(label)
    x += width
  header.setFrame(
    nsRect(0.0, 0.0, max(x, tableView.frame().size.width), defaultHeaderHeight)
  )
  header.setNeedsDisplay(true)

proc rebuildRows(tableView: NSTableView) =
  clearSubviews(tableView)
  if tableView.xColumns.len == 0:
    tableView.setNeedsDisplay(true)
    return

  let rows = tableView.numberOfRows()
  if rows <= 0:
    tableView.xSelectedRow = -1
    tableView.setNeedsDisplay(true)
    return

  if tableView.xSelectedRow() >= rows:
    tableView.xSelectedRow = rows - 1

  var y = 0.0'f32
  let rowStride = max(tableView.xRowHeight + tableView.xIntercellSpacing.height, 1.0)
  var widest = 0.0'f32
  for row in 0 ..< rows:
    var x = 0.0'f32
    for column in tableView.xColumns:
      if column.isNil:
        continue
      let width = clampColumnWidth(column.width())
      let value = tableView.objectValueForTableColumn(column, row)
      let text = objectDisplayString(value)
      var field = NSTextField.new()
      let spacing = tableView.xIntercellSpacing()
      let cellFrame = adjustedDataCellFrame(
        nsRect(x, y, width + spacing.width, tableView.xRowHeight + spacing.height),
        spacing,
      )
      field.setFrame(cellFrame)
      field.setStringValue(text)
      field.setEditable(false)
      field.setSelectable(false)
      field.setBezeled(false)
      field.setBordered(false)
      field.setDrawsBackground(true)
      if row == tableView.xSelectedRow():
        field.setTextColor(nsColor(1.0, 1.0, 1.0, 1.0))
        field.setBackgroundColor(nsColor(0.22, 0.49, 0.86, 1.0))
      elif tableView.xUsesAlternatingRows and (row mod 2 == 1):
        field.setTextColor(nsColor(0.12, 0.12, 0.12, 1.0))
        field.setBackgroundColor(nsColor(0.96, 0.96, 0.96, 1.0))
      else:
        field.setTextColor(nsColor(0.12, 0.12, 0.12, 1.0))
        field.setBackgroundColor(tableView.xBackgroundColor())
      tableView.addSubview(field)
      x += width + tableView.xIntercellSpacing.width
    widest = max(widest, x)
    y += rowStride

  tableView.setFrameSize(
    nsSize(
      max(tableView.frame().size.width, widest), max(tableView.frame().size.height, y)
    )
  )
  tableView.setNeedsDisplay(true)

proc new*(t: typedesc[NSTableHeaderCell]): NSTableHeaderCell =
  var allocated = NSTableHeaderCell.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSTableColumn]): NSTableColumn =
  var allocated = NSTableColumn.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSTableColumn], identifier: NSString): NSTableColumn =
  var allocated = NSTableColumn.alloc()
  result = allocated.initWithIdentifier(identifier)
  allocated.value = nil

proc new*(t: typedesc[NSTableHeaderView]): NSTableHeaderView =
  var allocated = NSTableHeaderView.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSTableView]): NSTableView =
  var allocated = NSTableView.alloc()
  result = initOwned(move(allocated))
