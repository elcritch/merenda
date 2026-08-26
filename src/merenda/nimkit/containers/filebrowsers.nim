## Lazy filesystem listings and a reusable table-backed file browser.

import std/[algorithm, options, os, strutils, tables]

import sigils/core

import ../controls/buttons
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../text/textfields
import ../view/views
import ./stackviews
import ./tableviews

export tableviews

const
  FileBrowserBackOperation* = "file-browser.back"
  FileBrowserForwardOperation* = "file-browser.forward"
  FileBrowserUpOperation* = "file-browser.up"
  FileBrowserHomeOperation* = "file-browser.home"
  FileBrowserRefreshOperation* = "file-browser.refresh"

type
  FileBrowserEntryKind* = enum
    fbekFile
    fbekDirectory
    fbekSymbolicLink

  FileBrowserEntry* = object
    path*: string
    name*: string
    kind*: FileBrowserEntryKind

  FileSystemBrowserModel* = object
    xListings: Table[string, seq[FileBrowserEntry]]

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

proc loadDirectoryEntries(directoryPath: string): seq[FileBrowserEntry] =
  if not directoryPath.isBrowsableDirectory():
    return
  try:
    for component, path in walkDir(directoryPath, relative = false):
      let kind =
        case component
        of pcFile: fbekFile
        of pcDir: fbekDirectory
        of pcLinkToFile, pcLinkToDir: fbekSymbolicLink
      result.add FileBrowserEntry(
        path: path, name: path.fileBrowserDisplayName(), kind: kind
      )
    result.sort(compareFileBrowserEntries)
  except OSError:
    discard

func initFileSystemBrowserModel*(): FileSystemBrowserModel =
  FileSystemBrowserModel(xListings: initTable[string, seq[FileBrowserEntry]]())

proc entries*(
    model: var FileSystemBrowserModel, directoryPath: string
): lent seq[FileBrowserEntry] =
  ## Return a cached listing, loading this directory on first access.
  if not model.xListings.hasKey(directoryPath):
    model.xListings[directoryPath] = directoryPath.loadDirectoryEntries()
  model.xListings[directoryPath]

proc isDirectoryLoaded*(model: FileSystemBrowserModel, directoryPath: string): bool =
  model.xListings.hasKey(directoryPath)

proc cachedDirectoryCount*(model: FileSystemBrowserModel): int =
  model.xListings.len

proc invalidate*(model: var FileSystemBrowserModel, directoryPath = "") =
  ## Drop one cached listing, or every listing when no path is supplied.
  if directoryPath.len == 0:
    model.xListings.clear()
  else:
    model.xListings.del(directoryPath)

protocol FileBrowserEvents:
  proc fileBrowserSelectionDidChange*(
    browser: FileBrowser, sender: DynamicAgent
  ) {.signal.}

  proc fileBrowserEntryWasActivated*(
    browser: FileBrowser, sender: DynamicAgent, entry: FileBrowserEntry
  ) {.signal.}

proc entries*(browser: FileBrowser): seq[FileBrowserEntry] =
  browser.xFileSystem.entries(browser.xDirectoryPath)

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
  browser.xLocationLabel.text = browser.xDirectoryPath
  browser.xLocationLabel.toolTip = browser.xDirectoryPath
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

proc selectPaths*(browser: FileBrowser, paths: openArray[string])

proc refresh*(browser: FileBrowser) =
  ## Invalidate the current lazy listing and reload the table.
  let selectedPaths = browser.selectedPaths()
  browser.xFileSystem.invalidate(browser.xDirectoryPath)
  browser.xTableView.reloadData()
  browser.selectPaths(selectedPaths)
  browser.updateOperationButtons()

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

proc initFileBrowserFields*(
    browser: FileBrowser, directoryPath = "", frame: Rect = AutoRect
) =
  initViewFields(browser, frame)
  browser.xFileSystem = initFileSystemBrowserModel()
  browser.xHistoryIndex = -1
  browser.xLayout = newStackView(laVertical)
  browser.xLayout.spacing = 8.0'f32
  browser.xToolbar = newStackView(laHorizontal)
  browser.xToolbar.spacing = 6.0'f32
  browser.xToolbar.distribution = svdNatural
  browser.xToolbar.setHuggingPriority(LayoutPriorityRequired, laVertical)
  browser.xToolbar.setCompressionPriority(LayoutPriorityRequired, laVertical)
  browser.xLocationLabel = newStatusLabel()
  browser.xLocationLabel.setHuggingPriority(LayoutPriorityRequired, laVertical)
  browser.xLocationLabel.setCompressionPriority(LayoutPriorityRequired, laVertical)
  let tableView = FileBrowserTableView()
  tableView.initTableViewFields()
  discard DynamicAgent(tableView).pushMethods(FileBrowserTableInput.init())
  browser.xTableView = tableView
  browser.xTableView.addColumn(newTableColumn("name", "Name", width = 300.0'f32))
  browser.xTableView.addColumn(newTableColumn("kind", "Kind", width = 120.0'f32))
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
  browser.xLayout.addArrangedSubview(View(browser.xLocationLabel))
  browser.xLayout.addArrangedSubview(View(browser.xTableView))
  browser.addSubview(browser.xLayout)
  discard browser.xLayout.pinEdges(toGuide = browser.contentLayoutGuide())
  browser.installDefaultOperations()
  let initialDirectory =
    if directoryPath.isBrowsableDirectory():
      directoryPath
    else:
      getCurrentDir()
  discard browser.setDirectoryPath(initialDirectory, recordHistory = true)
  browser.applyInitialFrame(frame)

proc newFileBrowser*(directoryPath = "", frame: Rect = AutoRect): FileBrowser =
  result = FileBrowser()
  result.initFileBrowserFields(directoryPath, frame)
