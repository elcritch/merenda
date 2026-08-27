## Find-in-files sidebar UI backed by NimKit's worker-based file search.

import std/[options, os, strutils]

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ./filetree

const
  SearchFieldAction = "kosmo.performFileSearch"
  SearchResultIdentifierPrefix = "kosmo.search-result."

type
  KosmoSearchResults* = ref object of nimkit.OutlineView
    xMatches: seq[nimkit.FileSearchMatch]
    xOnOpenFile: FileTreeOpenHandler
    xOpenDisposition: FileTreeOpenDisposition
    xRootPath: string

  KosmoFileSearchPanel* = ref object of nimkit.View
    queryField*: nimkit.TextField
    resultsView*: KosmoSearchResults
    statusLabel*: nimkit.Label
    xRootPath: string
    xService: nimkit.FileSearchService
    xActiveSearch: nimkit.FileSearchHandle

func resultIdentifier(index: int): string =
  SearchResultIdentifierPrefix & $index

func resultIndex(identifier: string): int =
  if not identifier.startsWith(SearchResultIdentifierPrefix):
    return -1
  try:
    parseInt(identifier[SearchResultIdentifierPrefix.len .. ^1])
  except ValueError:
    -1

proc searchResultTitle(match: nimkit.FileSearchMatch, rootPath: string): string =
  let
    path =
      if rootPath.len > 0:
        relativePath(match.path, rootPath)
      else:
        match.path
    lineText = match.lineText.strip()
  result = path & ":" & $match.line & ":" & $match.column
  if lineText.len > 0:
    result.add "  " & lineText

protocol KosmoSearchResultsDataSource of nimkit.OutlineViewDataSource:
  method numberOfChildren(
      results: KosmoSearchResults,
      outlineView: nimkit.OutlineView,
      parentIdentifier: string,
  ): int =
    discard outlineView
    if parentIdentifier.len == 0: results.xMatches.len else: 0

  method childIdentifier(
      results: KosmoSearchResults,
      outlineView: nimkit.OutlineView,
      parentIdentifier: string,
      index: int,
  ): string =
    discard results
    discard outlineView
    if parentIdentifier.len == 0 and index >= 0:
      resultIdentifier(index)
    else:
      ""

  method outlineItem(
      results: KosmoSearchResults, outlineView: nimkit.OutlineView, identifier: string
  ): nimkit.OutlineItem =
    discard outlineView
    let index = identifier.resultIndex()
    if index notin 0 ..< results.xMatches.len:
      return
    let match = results.xMatches[index]
    nimkit.initOutlineItem(
      identifier,
      match.searchResultTitle(results.xRootPath),
      leaf = true,
      tooltip = match.path,
    )

protocol KosmoSearchResultsTableDelegate of nimkit.TableViewDelegate:
  method shouldEditCell(
      results: KosmoSearchResults,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): bool =
    discard results
    discard tableView
    discard row
    discard column
    false

protocol KosmoSearchResultsEvents of nimkit.ResponderEventProtocol:
  method mouseUp(results: KosmoSearchResults, event: nimkit.MouseEvent): bool =
    results.xOpenDisposition = if event.clickCount >= 2: fodPermanent else: fodTemporary
    defer:
      results.xOpenDisposition = fodPermanent
    let next = results.performNext(nimkit.mouseUp, event)
    if next.isSome:
      next.get()
    else:
      false

proc searchResultWasActivated(
    results: KosmoSearchResults, sender: nimkit.DynamicAgent
) {.slot.} =
  if sender != nimkit.DynamicAgent(results) or results.xOnOpenFile.isNil:
    return
  let index = results.selectedItemIdentifier().resultIndex()
  if index in 0 ..< results.xMatches.len:
    results.xOnOpenFile(results.xMatches[index].path, results.xOpenDisposition)

proc matches*(results: KosmoSearchResults): lent seq[nimkit.FileSearchMatch] =
  results.xMatches

proc matchIdentifier*(results: KosmoSearchResults, index: Natural): string =
  ## Return the outline identifier for a displayed result.
  if index < results.xMatches.len:
    result = resultIdentifier(index)

proc `onOpenFile=`*(results: KosmoSearchResults, handler: FileTreeOpenHandler) =
  results.xOnOpenFile = handler

proc setMatches(
    results: KosmoSearchResults,
    rootPath: string,
    matches: openArray[nimkit.FileSearchMatch],
) =
  results.xRootPath = rootPath
  results.xMatches = @matches
  results.selectedItemIdentifier = ""
  results.reloadOutlineData()

proc newKosmoSearchResults(): KosmoSearchResults =
  result = KosmoSearchResults(xOpenDisposition: fodPermanent)
  result.initOutlineViewFields()
  discard result.withProtocol(KosmoSearchResultsDataSource)
  discard result.withProtocol(KosmoSearchResultsTableDelegate)
  discard nimkit.DynamicAgent(result).pushMethods(KosmoSearchResultsEvents.init())
  result.outlineDataSource = result
  result.outlineColumn().title = "Matches"
  result.outlineColumn().width = 320.0'f32
  result.showsHeader = false
  result.rowHeight = 24.0'f32
  result.selectionMode = nimkit.tsmSingle
  result.usesAlternatingRowBackgrounds = false
  result.showsRowSeparators = false
  result.connect(nimkit.rowWasActivated, result, searchResultWasActivated)

proc finishFileSearch(
    panel: KosmoFileSearchPanel, handle: nimkit.FileSearchHandle
) {.slot.} =
  if handle.isNil or handle != panel.xActiveSearch:
    return
  let searchResult = handle.result()
  panel.resultsView.setMatches(panel.xRootPath, searchResult.matches)
  panel.statusLabel.text =
    case searchResult.reason
    of nimkit.fsfrCancelled:
      "Search cancelled"
    of nimkit.fsfrResultLimitReached:
      $searchResult.matches.len & " results (limit reached)"
    of nimkit.fsfrFileLimitReached:
      $searchResult.matches.len & " results (file limit reached)"
    of nimkit.fsfrCompleted:
      if searchResult.matches.len == 1:
        "1 result"
      else:
        $searchResult.matches.len & " results"

proc ensureSearchService(panel: KosmoFileSearchPanel) =
  if panel.xService.isNil:
    panel.xService = nimkit.newFileSearchService()
    panel.xService.connect(nimkit.fileSearchDidFinish, panel, finishFileSearch)

proc performSearch*(panel: KosmoFileSearchPanel): bool {.discardable.} =
  ## Start a new asynchronous search for the current query field text.
  if panel.isNil:
    return
  let pattern = panel.queryField.text()
  if pattern.len == 0 or panel.xRootPath.len == 0:
    panel.resultsView.setMatches(panel.xRootPath, [])
    panel.statusLabel.text =
      if pattern.len == 0: "Enter a regular expression" else: "No folder is open"
    return
  if not panel.xActiveSearch.isNil and not panel.xActiveSearch.isFinished():
    panel.xActiveSearch.cancel()
  panel.resultsView.setMatches(panel.xRootPath, [])
  panel.statusLabel.text = "Searching…"
  try:
    panel.ensureSearchService()
    panel.xActiveSearch = panel.xService.search(
      nimkit.initFileSearchQuery(
        panel.xRootPath, pattern, nimkit.initFileSearchOptions(caseSensitive = false)
      )
    )
    result = true
  except CatchableError as error:
    panel.xActiveSearch = nil
    panel.statusLabel.text = error.msg

proc submitFileSearch(panel: KosmoFileSearchPanel, sender: nimkit.DynamicAgent) =
  discard sender
  discard panel.performSearch()
  let owner = panel.window()
  if owner of nimkit.Window:
    discard nimkit.Window(owner).makeFirstResponder(panel.queryField)

protocol KosmoFileSearchPanelLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(panel: KosmoFileSearchPanel) =
    let
      bounds = panel.bounds()
      horizontalPadding = min(8.0'f32, bounds.size.width * 0.5'f32)
      contentWidth = max(bounds.size.width - horizontalPadding * 2.0'f32, 0.0'f32)
    panel.queryField.setFrameFromLayout(
      nimkit.rect(horizontalPadding, 8.0'f32, contentWidth, 26.0'f32)
    )
    panel.statusLabel.setFrameFromLayout(
      nimkit.rect(horizontalPadding, 38.0'f32, contentWidth, 18.0'f32)
    )
    panel.resultsView.setFrameFromLayout(
      nimkit.rect(
        0.0'f32,
        60.0'f32,
        bounds.size.width,
        max(bounds.size.height - 60.0'f32, 0.0'f32),
      )
    )

proc rootPath*(panel: KosmoFileSearchPanel): string =
  panel.xRootPath

proc `rootPath=`*(panel: KosmoFileSearchPanel, rootPath: string) =
  let next =
    if rootPath.len > 0 and dirExists(rootPath):
      absolutePath(rootPath)
    else:
      ""
  if panel.xRootPath == next:
    return
  if not panel.xActiveSearch.isNil and not panel.xActiveSearch.isFinished():
    panel.xActiveSearch.cancel()
  panel.xActiveSearch = nil
  panel.xRootPath = next
  panel.resultsView.setMatches(next, [])
  panel.statusLabel.text = "Enter a regular expression"

proc activeSearch*(panel: KosmoFileSearchPanel): nimkit.FileSearchHandle =
  panel.xActiveSearch

proc waitForSearch*(
    panel: KosmoFileSearchPanel, timeoutMilliseconds: Natural = 5_000
): bool {.discardable.} =
  ## Wait for the current search while delivering its main-thread completion.
  not panel.isNil and not panel.xActiveSearch.isNil and
    panel.xService.waitFor(panel.xActiveSearch, timeoutMilliseconds)

proc focusQuery*(panel: KosmoFileSearchPanel): bool {.discardable.} =
  ## Focus and select the find query field in its window.
  if panel.isNil or not (panel.window() of nimkit.Window):
    return
  result = nimkit.Window(panel.window()).makeFirstResponder(panel.queryField)

proc `onOpenFile=`*(panel: KosmoFileSearchPanel, handler: FileTreeOpenHandler) =
  panel.resultsView.onOpenFile = handler

proc close*(panel: KosmoFileSearchPanel) =
  ## Stop the search workers owned by this panel.
  if panel.isNil or panel.xService.isNil:
    return
  panel.xService.disconnect(nimkit.fileSearchDidFinish, panel, finishFileSearch)
  panel.xService.close()
  panel.xService = nil
  panel.xActiveSearch = nil

proc newKosmoFileSearchPanel*(rootPath = ""): KosmoFileSearchPanel =
  let
    queryField = nimkit.newTextField("")
    resultsView = newKosmoSearchResults()
    statusLabel = nimkit.newStatusLabel("Enter a regular expression")
    action = nimkit.actionSelector(SearchFieldAction)
  result = KosmoFileSearchPanel(
    queryField: queryField, resultsView: resultsView, statusLabel: statusLabel
  )
  result.initViewFields()
  result.addSubview(queryField)
  result.addSubview(statusLabel)
  result.addSubview(resultsView)
  discard result.withProtocol(KosmoFileSearchPanelLayout)
  let panel = result.unsafeWeakRef()
  queryField.target = nimkit.newActionTarget(
    action,
    proc(sender: nimkit.DynamicAgent) =
      if not panel.isNil:
        panel[].submitFileSearch(sender)
    ,
  )
  queryField.action = action
  result.rootPath = rootPath
