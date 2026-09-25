## Lazy filesystem listings and a reusable table-backed file browser.

import std/[algorithm, options, os, strutils, tables]

import sigils/core

import ../controls/buttons
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../text/textfields
import ../view/views
from ../view/viewgeometry import setFrameFromLayout
import ./stackviews
import ./tableviews

export tableviews

const
  FileBrowserBackOperation* = "file-browser.back"
  FileBrowserForwardOperation* = "file-browser.forward"
  FileBrowserUpOperation* = "file-browser.up"
  FileBrowserHomeOperation* = "file-browser.home"
  FileBrowserRefreshOperation* = "file-browser.refresh"
  DefaultFileBrowserEntryLimit* = 1_000

type
  FileBrowserEntryKind* = enum
    fbekFile
    fbekDirectory
    fbekSymbolicLink

  FileBrowserEntry* = object
    path*: string
    name*: string
    kind*: FileBrowserEntryKind

  FileBrowserDirectoryListing = object
    entries: seq[FileBrowserEntry]
    truncated: bool

  FileSystemBrowserModel* = object
    xListings: Table[string, seq[FileBrowserEntry]]
    xListingTruncation: Table[string, bool]
    xEntryLimit: int

  FileBrowserOperationSelection* = enum
    fbosAny
    fbosFiles
    fbosDirectories

  FileBrowserOperation* = object
    identifier*: string
    title*: string
    toolTip*: string
    selection*: FileBrowserOperationSelection
    requiresSelection*: bool

  FileBrowserTableView = ref object of TableView
    xActivatesRows: bool

  FileBrowser* = ref object of View
    xFileSystem: FileSystemBrowserModel
    xDirectoryPath: string
    xHistory: seq[string]
    xHistoryIndex: int
    xLayout: StackView
    xToolbar: StackView
    xLocationLabel: Label
    xLocationField: TextField
    xStatusLabel: Label
    xPlaces: StackView
    xTableView: TableView
    xOperationBindings: seq[FileBrowserOperationBinding]

  FileBrowserOperationHandler* =
    proc(browser: FileBrowser, entries: seq[FileBrowserEntry]) {.closure.}

  FileBrowserOperationBinding = object
    operation: FileBrowserOperation
    button: Button

func initFileBrowserOperation*(
    identifier, title: string,
    selection = fbosAny,
    requiresSelection = true,
    toolTip = "",
): FileBrowserOperation =
  FileBrowserOperation(
    identifier: identifier,
    title: title,
    toolTip: toolTip,
    selection: selection,
    requiresSelection: requiresSelection,
  )

func fileBrowserDisplayName*(path: string): string =
  result = path.extractFilename()
  if result.len == 0:
    result = path

proc isBrowsableDirectory*(path: string): bool =
  dirExists(path) and not symlinkExists(path)

func isDirectory*(entry: FileBrowserEntry): bool =
  entry.kind == fbekDirectory

func isFile*(entry: FileBrowserEntry): bool =
  entry.kind == fbekFile

func compareFileBrowserEntries(left, right: FileBrowserEntry): int =
  if left.isDirectory() != right.isDirectory():
    return if left.isDirectory(): -1 else: 1
  cmpIgnoreCase(left.name, right.name)

proc loadDirectoryEntries(
    directoryPath: string, maxEntries: int
): FileBrowserDirectoryListing =
  if not directoryPath.isBrowsableDirectory():
    return
  let entryLimit = max(maxEntries, 1)
  try:
    for component, path in walkDir(directoryPath, relative = false):
      if result.entries.len >= entryLimit:
        result.truncated = true
        break
      let kind =
        case component
        of pcFile: fbekFile
        of pcDir: fbekDirectory
        of pcLinkToFile, pcLinkToDir: fbekSymbolicLink
      result.entries.add FileBrowserEntry(
        path: path, name: path.fileBrowserDisplayName(), kind: kind
      )
    result.entries.sort(compareFileBrowserEntries)
  except OSError:
    discard

func initFileSystemBrowserModel*(
    entryLimit: Positive = DefaultFileBrowserEntryLimit
): FileSystemBrowserModel =
  FileSystemBrowserModel(
    xListings: initTable[string, seq[FileBrowserEntry]](),
    xListingTruncation: initTable[string, bool](),
    xEntryLimit: entryLimit.int,
  )

func entryLimit*(model: FileSystemBrowserModel): int =
  if model.xEntryLimit > 0: model.xEntryLimit else: DefaultFileBrowserEntryLimit

proc entries*(
    model: var FileSystemBrowserModel, directoryPath: string
): lent seq[FileBrowserEntry] =
  ## Return a cached listing, loading this directory on first access.
  if not model.xListings.hasKey(directoryPath):
    let listing = directoryPath.loadDirectoryEntries(model.entryLimit())
    model.xListings[directoryPath] = listing.entries
    model.xListingTruncation[directoryPath] = listing.truncated
  model.xListings[directoryPath]

proc isDirectoryLoaded*(model: FileSystemBrowserModel, directoryPath: string): bool =
  model.xListings.hasKey(directoryPath)

proc isDirectoryTruncated*(model: FileSystemBrowserModel, directoryPath: string): bool =
  if model.xListingTruncation.hasKey(directoryPath):
    result = model.xListingTruncation[directoryPath]

proc cachedDirectoryCount*(model: FileSystemBrowserModel): int =
  model.xListings.len

proc invalidate*(model: var FileSystemBrowserModel, directoryPath = "") =
  ## Drop one cached listing, or every listing when no path is supplied.
  if directoryPath.len == 0:
    model.xListings.clear()
    model.xListingTruncation.clear()
  else:
    model.xListings.del(directoryPath)
    model.xListingTruncation.del(directoryPath)

proc `entryLimit=`*(model: var FileSystemBrowserModel, value: Positive) =
  if model.xEntryLimit == value.int:
    return
  model.xEntryLimit = value.int
  model.invalidate()

protocol FileBrowserEvents:
  proc fileBrowserDirectoryDidChange*(
    browser: FileBrowser, sender: DynamicAgent
  ) {.signal.}

  proc fileBrowserSelectionDidChange*(
    browser: FileBrowser, sender: DynamicAgent
  ) {.signal.}

  proc fileBrowserEntryWasActivated*(
    browser: FileBrowser, sender: DynamicAgent, entry: FileBrowserEntry
  ) {.signal.}

proc entries*(browser: FileBrowser): seq[FileBrowserEntry] =
  browser.xFileSystem.entries(browser.xDirectoryPath)

proc entryLimit*(browser: FileBrowser): int =
  browser.xFileSystem.entryLimit()

proc isDirectoryListingTruncated*(browser: FileBrowser): bool =
  browser.xFileSystem.isDirectoryTruncated(browser.xDirectoryPath)

proc entryAt*(browser: FileBrowser, index: int): FileBrowserEntry =
  let entries = browser.entries()
  if index in 0 ..< entries.len:
    result = entries[index]

proc selectedEntries*(browser: FileBrowser): seq[FileBrowserEntry] =
  let entries = browser.entries()
  for index in browser.xTableView.selectedIndexes():
    if index in 0 ..< entries.len:
      result.add entries[index]

proc selectedPaths*(browser: FileBrowser): seq[string] =
  for entry in browser.selectedEntries():
    result.add entry.path

proc operationAcceptsSelection(
    operation: FileBrowserOperation, entries: openArray[FileBrowserEntry]
): bool =
  if not operation.requiresSelection:
    return true
  if entries.len == 0:
    return false
  for entry in entries:
    case operation.selection
    of fbosAny:
      discard
    of fbosFiles:
      if not entry.isFile():
        return false
    of fbosDirectories:
      if not entry.isDirectory():
        return false
  true

proc canNavigateUp(browser: FileBrowser): bool =
  if browser.xDirectoryPath.len == 0:
    return false
  let parent = browser.xDirectoryPath.parentDir()
  parent.len > 0 and parent != browser.xDirectoryPath

proc updateOperationButtons(browser: FileBrowser) =
  let selection = browser.selectedEntries()
  for binding in browser.xOperationBindings:
    binding.button.enabled =
      case binding.operation.identifier
      of FileBrowserBackOperation:
        browser.xHistoryIndex > 0
      of FileBrowserForwardOperation:
        browser.xHistoryIndex >= 0 and browser.xHistoryIndex < browser.xHistory.high
      of FileBrowserUpOperation:
        browser.canNavigateUp()
      else:
        binding.operation.operationAcceptsSelection(selection)

proc syncLocation(browser: FileBrowser) =
  browser.xLocationField.text = browser.xDirectoryPath
  browser.xLocationField.toolTip = browser.xDirectoryPath
  let count = browser.entries().len
  browser.xStatusLabel.text = $count & (if count == 1: " item" else: " items")
  if browser.isDirectoryListingTruncated():
    browser.xStatusLabel.text =
      "Folder listing limited: showing up to " & $browser.entryLimit() & " entries"
  browser.updateOperationButtons()

proc setDirectoryPath(browser: FileBrowser, path: string, recordHistory: bool): bool =
  if not path.isBrowsableDirectory():
    return false
  let next = absolutePath(path)
  if browser.xDirectoryPath == next:
    return true
  browser.xDirectoryPath = next
  if recordHistory:
    if browser.xHistoryIndex < browser.xHistory.high:
      browser.xHistory.setLen(browser.xHistoryIndex + 1)
    browser.xHistory.add next
    browser.xHistoryIndex = browser.xHistory.high
  browser.xTableView.selectedIndexes = @[]
  browser.xTableView.reloadData()
  browser.syncLocation()
  emit browser.fileBrowserDirectoryDidChange(DynamicAgent(browser))
  true

proc directoryPath*(browser: FileBrowser): string =
  browser.xDirectoryPath

proc `directoryPath=`*(browser: FileBrowser, path: string) =
  discard browser.setDirectoryPath(path, recordHistory = true)

proc navigateBack*(browser: FileBrowser): bool {.discardable.} =
  if browser.xHistoryIndex <= 0:
    return false
  dec browser.xHistoryIndex
  result = browser.setDirectoryPath(
    browser.xHistory[browser.xHistoryIndex], recordHistory = false
  )

proc navigateForward*(browser: FileBrowser): bool {.discardable.} =
  if browser.xHistoryIndex < 0 or browser.xHistoryIndex >= browser.xHistory.high:
    return false
  inc browser.xHistoryIndex
  result = browser.setDirectoryPath(
    browser.xHistory[browser.xHistoryIndex], recordHistory = false
  )

proc navigateUp*(browser: FileBrowser): bool {.discardable.} =
  if not browser.canNavigateUp():
    return false
  browser.setDirectoryPath(browser.xDirectoryPath.parentDir(), recordHistory = true)

proc navigateHome*(browser: FileBrowser): bool {.discardable.} =
  browser.setDirectoryPath(getHomeDir(), recordHistory = true)

proc navigateToLocation*(browser: FileBrowser): bool {.discardable.} =
  ## Open the location field's path, resolving relative paths from this folder.
  let entered = browser.xLocationField.text.strip()
  if entered.len > 0:
    let expanded = expandTilde(entered)
    let path = absolutePath(expanded, browser.xDirectoryPath)
    result = browser.setDirectoryPath(path, recordHistory = true)
    if result:
      browser.syncLocation()
  if not result:
    browser.xStatusLabel.text = "Folder not found: " & entered

proc selectPaths*(browser: FileBrowser, paths: openArray[string])

proc refresh*(browser: FileBrowser) =
  ## Invalidate the current lazy listing and reload the table.
  let selectedPaths = browser.selectedPaths()
  browser.xFileSystem.invalidate(browser.xDirectoryPath)
  browser.xTableView.reloadData()
  browser.selectPaths(selectedPaths)
  browser.syncLocation()

proc selectPaths*(browser: FileBrowser, paths: openArray[string]) =
  let entries = browser.entries()
  var indexes: seq[int]
  for path in paths:
    let candidate =
      if path.len > 0:
        absolutePath(path)
      else:
        ""
    for index, entry in entries:
      if entry.path == candidate:
        indexes.add index
        break
  browser.xTableView.selectedIndexes = indexes

proc selectPath*(browser: FileBrowser, path: string) =
  if path.len == 0:
    browser.selectPaths([])
  else:
    browser.selectPaths([path])

proc activateEntryAt*(browser: FileBrowser, index: int): bool {.discardable.} =
  let entries = browser.entries()
  if index notin 0 ..< entries.len:
    return false
  let entry = entries[index]
  if entry.isDirectory():
    discard browser.setDirectoryPath(entry.path, recordHistory = true)
  emit browser.fileBrowserEntryWasActivated(DynamicAgent(browser), entry)
  true

proc activateSelection*(browser: FileBrowser): bool {.discardable.} =
  browser.activateEntryAt(browser.xTableView.selectedIndex())

protocol FileBrowserTableDataSource of TableViewDataSource:
  method numberOfRows(browser: FileBrowser, tableView: TableView): int =
    discard tableView
    browser.entries().len

  method textForCell(
      browser: FileBrowser, tableView: TableView, row: int, column: TableColumn
  ): string =
    discard tableView
    let entry = browser.entryAt(row)
    case column.identifier
    of "kind":
      case entry.kind
      of fbekFile: "File"
      of fbekDirectory: "Folder"
      of fbekSymbolicLink: "Symbolic Link"
    else:
      entry.name

  method identifierForRow(
      browser: FileBrowser, tableView: TableView, row: int
  ): string =
    discard tableView
    browser.entryAt(row).path

protocol FileBrowserTableDelegate of TableViewDelegate:
  method shouldEditCell(
      browser: FileBrowser, tableView: TableView, row: int, column: TableColumn
  ): bool =
    false

  method didActivateRow(browser: FileBrowser, tableView: TableView, row: int) =
    if tableView of FileBrowserTableView and
        FileBrowserTableView(tableView).xActivatesRows:
      discard browser.activateEntryAt(row)

protocol FileBrowserTableInput of ResponderEventProtocol:
  method mouseUp(tableView: FileBrowserTableView, event: MouseEvent): bool =
    tableView.xActivatesRows = event.clickCount >= 2
    defer:
      tableView.xActivatesRows = false
    let next = tableView.performNext(mouseUp, event)
    if next.isSome:
      next.get()
    else:
      false

  method keyDown(tableView: FileBrowserTableView, event: KeyEvent): bool =
    tableView.xActivatesRows = event.key in {keyEnter, keySpace}
    defer:
      tableView.xActivatesRows = false
    let next = tableView.performNext(keyDown, event)
    if next.isSome:
      next.get()
    else:
      false

proc fileBrowserTableSelectionDidChange(
    browser: FileBrowser, sender: DynamicAgent
) {.slot.} =
  if sender != DynamicAgent(browser.xTableView):
    return
  browser.updateOperationButtons()
  emit browser.fileBrowserSelectionDidChange(DynamicAgent(browser))

proc addOperationButton*(
    browser: FileBrowser,
    operation: FileBrowserOperation,
    handler: FileBrowserOperationHandler,
): Button =
  ## Add a selection-aware operation to the browser toolbar.
  result = newButton(operation.title)
  result.toolTip = operation.toolTip
  let
    action = actionSelector(operation.identifier)
    browserRef = browser.unsafeWeakRef()
  result.target = newActionTarget(action) do(sender: DynamicAgent):
    discard sender
    if not browserRef.isNil and not handler.isNil:
      handler(browserRef[], browserRef[].selectedEntries())
  result.action = action
  browser.xToolbar.addArrangedSubview(View(result))
  browser.xOperationBindings.add FileBrowserOperationBinding(
    operation: operation, button: result
  )
  browser.updateOperationButtons()

proc operationButton*(browser: FileBrowser, identifier: string): Button =
  for binding in browser.xOperationBindings:
    if binding.operation.identifier == identifier:
      return binding.button

proc operationButtons*(browser: FileBrowser): seq[Button] =
  for binding in browser.xOperationBindings:
    result.add binding.button

proc tableView*(browser: FileBrowser): TableView =
  browser.xTableView

proc toolbar*(browser: FileBrowser): StackView =
  browser.xToolbar

proc locationLabel*(browser: FileBrowser): Label =
  browser.xLocationLabel

proc locationField*(browser: FileBrowser): TextField =
  ## Editable folder path; press Return to navigate.
  browser.xLocationField

proc statusLabel*(browser: FileBrowser): Label =
  browser.xStatusLabel

proc placesView*(browser: FileBrowser): StackView =
  browser.xPlaces

proc `entryLimit=`*(browser: FileBrowser, value: Positive) =
  browser.xFileSystem.entryLimit = value
  browser.xTableView.reloadData()
  browser.syncLocation()

proc allowsMultipleSelection*(browser: FileBrowser): bool =
  browser.xTableView.selectionMode() in {tsmMultiple, tsmExtended}

proc `allowsMultipleSelection=`*(browser: FileBrowser, value: bool) =
  browser.xTableView.selectionMode = if value: tsmMultiple else: tsmSingle

proc installDefaultOperations(browser: FileBrowser) =
  discard browser.addOperationButton(
    initFileBrowserOperation(
      FileBrowserBackOperation,
      "Back",
      requiresSelection = false,
      toolTip = "Go to the previous folder",
    ),
    proc(browser: FileBrowser, entries: seq[FileBrowserEntry]) =
      discard entries
      discard browser.navigateBack(),
  )
  discard browser.addOperationButton(
    initFileBrowserOperation(
      FileBrowserForwardOperation,
      "Forward",
      requiresSelection = false,
      toolTip = "Go to the next folder",
    ),
    proc(browser: FileBrowser, entries: seq[FileBrowserEntry]) =
      discard entries
      discard browser.navigateForward(),
  )
  discard browser.addOperationButton(
    initFileBrowserOperation(
      FileBrowserUpOperation,
      "Up",
      requiresSelection = false,
      toolTip = "Go to the enclosing folder",
    ),
    proc(browser: FileBrowser, entries: seq[FileBrowserEntry]) =
      discard entries
      discard browser.navigateUp(),
  )
  discard browser.addOperationButton(
    initFileBrowserOperation(
      FileBrowserHomeOperation,
      "Home",
      requiresSelection = false,
      toolTip = "Go to the home folder",
    ),
    proc(browser: FileBrowser, entries: seq[FileBrowserEntry]) =
      discard entries
      discard browser.navigateHome(),
  )
  discard browser.addOperationButton(
    initFileBrowserOperation(
      FileBrowserRefreshOperation,
      "Refresh",
      requiresSelection = false,
      toolTip = "Reload this folder",
    ),
    proc(browser: FileBrowser, entries: seq[FileBrowserEntry]) =
      discard entries
      browser.refresh(),
  )

proc addPlace(browser: FileBrowser, title, path: string) =
  if not path.isBrowsableDirectory():
    return
  let
    button = newButton(title)
    action = actionSelector("file-browser.place." & title)
    browserRef = browser.unsafeWeakRef()
  button.toolTip = path
  button.action = action
  button.target = newActionTarget(action) do(sender: DynamicAgent):
    if not browserRef.isNil:
      browserRef[].directoryPath = path
  browser.xPlaces.addArrangedSubview(button)

protocol FileBrowserLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(browser: FileBrowser): IntrinsicSize =
    browser.xLayout.intrinsicContentSize()

  method layoutSubviews(browser: FileBrowser) =
    browser.xLayout.setFrameFromLayout(browser.bounds())

proc initFileBrowserFields*(
    browser: FileBrowser,
    directoryPath = "",
    frame: Rect = AutoRect,
    entryLimit: Positive = DefaultFileBrowserEntryLimit,
) =
  initViewFields(browser, frame)
  browser.xFileSystem = initFileSystemBrowserModel(entryLimit)
  browser.xHistoryIndex = -1
  browser.xLayout = newStackView(laVertical)
  browser.xLayout.spacing = 8.0'f32
  browser.xToolbar = newStackView(laHorizontal)
  browser.xToolbar.spacing = 6.0'f32
  browser.xToolbar.distribution = svdNatural
  browser.xToolbar.setHuggingPriority(LayoutPriorityRequired, laVertical)
  browser.xToolbar.setCompressionPriority(LayoutPriorityRequired, laVertical)
  browser.xLocationLabel = newFormLabel("Location:")
  browser.xLocationField = newTextField()
  browser.xStatusLabel = newStatusLabel()
  browser.xStatusLabel.setHuggingPriority(LayoutPriorityRequired, laVertical)
  browser.xStatusLabel.setCompressionPriority(LayoutPriorityRequired, laVertical)
  let
    browserRef = browser.unsafeWeakRef()
    locationAction = actionSelector("file-browser.location")
    locationRow = newStackView(laHorizontal)
  browser.xLocationField.action = locationAction
  browser.xLocationField.target = newActionTarget(locationAction) do(
    sender: DynamicAgent
  ):
    if not browserRef.isNil:
      discard browserRef[].navigateToLocation()
  locationRow.addArrangedSubview(browser.xLocationLabel)
  locationRow.addArrangedSubview(browser.xLocationField, svspFillAvailableWidth)
  browser.xPlaces = newStackView(laVertical)
  browser.xPlaces.distribution = svdNatural
  browser.xPlaces.addArrangedSubview(newHeadingLabel("Places"))
  for place in [
    ("Home", getHomeDir()),
    ("Documents", getHomeDir() / "Documents"),
    ("Downloads", getHomeDir() / "Downloads"),
    ("File System", absolutePath($DirSep)),
  ]:
    browser.addPlace(place[0], place[1])
  let tableView = FileBrowserTableView()
  tableView.initTableViewFields()
  discard DynamicAgent(tableView).pushMethods(FileBrowserTableInput.init())
  browser.xTableView = tableView
  browser.xTableView.addColumn(
    newTableColumn("name", "Name", width = 300.0'f32, sizingPolicy = tcspFlexible)
  )
  browser.xTableView.addColumn(newTableColumn("kind", "Type", width = 120.0'f32))
  browser.xTableView.columnSizing = tvcsFill
  discard browser.withProtocol(FileBrowserTableDataSource)
  discard browser.withProtocol(FileBrowserTableDelegate)
  browser.xTableView.dataSource = browser
  browser.xTableView.delegate = browser
  browser.xTableView.selectionMode = tsmSingle
  browser.xTableView.visibleRows = 8
  browser.xTableView.usesAlternatingRowBackgrounds = true
  browser.xTableView.connect(
    selectionDidChange, browser, fileBrowserTableSelectionDidChange
  )
  browser.xLayout.addArrangedSubview(View(browser.xToolbar))
  browser.xLayout.addArrangedSubview(locationRow)
  let body = newStackView(laHorizontal)
  body.addArrangedSubview(browser.xPlaces)
  body.addArrangedSubview(browser.xTableView, svspFillAvailableSpace)
  browser.xLayout.addArrangedSubview(body, svspFillAvailableSpace)
  browser.xLayout.addArrangedSubview(browser.xStatusLabel)
  browser.addSubview(browser.xLayout)
  discard browser.withProtocol(FileBrowserLayout)
  browser.installDefaultOperations()
  let initialDirectory =
    if directoryPath.isBrowsableDirectory():
      directoryPath
    else:
      getCurrentDir()
  discard browser.setDirectoryPath(initialDirectory, recordHistory = true)
  browser.applyInitialFrame(frame)

proc newFileBrowser*(
    directoryPath = "",
    frame: Rect = AutoRect,
    entryLimit: Positive = DefaultFileBrowserEntryLimit,
): FileBrowser =
  result = FileBrowser()
  result.initFileBrowserFields(directoryPath, frame, entryLimit)
