## Find-in-files sidebar UI backed by NimKit's worker-based file search.

import std/[options, os, strutils, tables]

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ./filetree

const
  DefaultKosmoSearchResultsPerFile* = 30
  SearchFieldAction = "kosmo.performFileSearch"
  CancelSearchAction = "kosmo.cancelFileSearch"
  SearchFileIdentifierPrefix = "kosmo.search-file."
  SearchResultIdentifierPrefix = "kosmo.search-result."
  SearchLoadMoreIdentifierPrefix = "kosmo.search-load-more."

type
  SearchResultOpenHandler* = proc(
    match: nimkit.FileSearchMatch, disposition: FileTreeOpenDisposition
  ) {.closure.}

  SearchResultGroup = object
    path: string
    matchIndexes: seq[int]
    visibleCount: int

  KosmoSearchResults* = ref object of nimkit.OutlineView
    xMatches: seq[nimkit.FileSearchMatch]
    xGroups: seq[SearchResultGroup]
    xMatchGroupIndexes: seq[int]
    xOnOpenResult: SearchResultOpenHandler
    xOpenDisposition: FileTreeOpenDisposition
    xRootPath: string
    xResultsPerFile: int

  KosmoFileSearchPanel* = ref object of nimkit.View
    queryField*: nimkit.TextField
    resultsView*: KosmoSearchResults
    statusLabel*: nimkit.Label
    progressIndicator*: nimkit.ProgressIndicator
    cancelButton*: nimkit.Button
    xRootPath: string
    xService: nimkit.FileSearchService
    xActiveSearch: nimkit.FileSearchHandle

func indexedIdentifier(prefix: string, index: int): string =
  prefix & $index

func identifierIndex(identifier, prefix: string): int =
  if not identifier.startsWith(prefix):
    return -1
  try:
    parseInt(identifier[prefix.len .. ^1])
  except ValueError:
    -1

func fileIdentifier(index: int): string =
  indexedIdentifier(SearchFileIdentifierPrefix, index)

func resultIdentifier(index: int): string =
  indexedIdentifier(SearchResultIdentifierPrefix, index)

func loadMoreIdentifier(index: int): string =
  indexedIdentifier(SearchLoadMoreIdentifierPrefix, index)

proc searchFileTitle(path, rootPath: string): string =
  if rootPath.len > 0:
    relativePath(path, rootPath)
  else:
    path

proc searchResultTitle(match: nimkit.FileSearchMatch): string =
  let lineText = match.lineText.strip()
  result = $match.line & ":" & $match.column
  if lineText.len > 0:
    result.add "  " & lineText

func loadMoreTitle(group: SearchResultGroup, resultsPerFile: int): string =
  let
    remaining = group.matchIndexes.len - group.visibleCount
    nextCount = min(remaining, resultsPerFile)
  "Load " & $nextCount & " more results (" & $remaining & " remaining)"

protocol KosmoSearchResultsDataSource of nimkit.OutlineViewDataSource:
  method numberOfChildren(
      results: KosmoSearchResults,
      outlineView: nimkit.OutlineView,
      parentIdentifier: string,
  ): int =
    discard outlineView
    if parentIdentifier.len == 0:
      return results.xGroups.len
    let groupIndex = parentIdentifier.identifierIndex(SearchFileIdentifierPrefix)
    if groupIndex in 0 ..< results.xGroups.len:
      let group = results.xGroups[groupIndex]
      result = group.visibleCount
      if group.visibleCount < group.matchIndexes.len:
        inc result

  method childIdentifier(
      results: KosmoSearchResults,
      outlineView: nimkit.OutlineView,
      parentIdentifier: string,
      index: int,
  ): string =
    discard outlineView
    if parentIdentifier.len == 0:
      if index in 0 ..< results.xGroups.len:
        return fileIdentifier(index)
      return
    let groupIndex = parentIdentifier.identifierIndex(SearchFileIdentifierPrefix)
    if groupIndex notin 0 ..< results.xGroups.len:
      return
    let group = results.xGroups[groupIndex]
    if index in 0 ..< group.visibleCount:
      result = resultIdentifier(group.matchIndexes[index])
    elif index == group.visibleCount and group.visibleCount < group.matchIndexes.len:
      result = loadMoreIdentifier(groupIndex)

  method outlineItem(
      results: KosmoSearchResults, outlineView: nimkit.OutlineView, identifier: string
  ): nimkit.OutlineItem =
    discard outlineView
    let groupIndex = identifier.identifierIndex(SearchFileIdentifierPrefix)
    if groupIndex in 0 ..< results.xGroups.len:
      let group = results.xGroups[groupIndex]
      return nimkit.initOutlineItem(
        identifier,
        group.path.searchFileTitle(results.xRootPath),
        expandable = true,
        tooltip = group.path,
        decoration = nimkit.initOutlineItemDecoration(badge = $group.matchIndexes.len),
      )

    let matchIndex = identifier.identifierIndex(SearchResultIdentifierPrefix)
    if matchIndex in 0 ..< results.xMatches.len:
      let
        match = results.xMatches[matchIndex]
        parentIndex = results.xMatchGroupIndexes[matchIndex]
      return nimkit.initOutlineItem(
        identifier,
        match.searchResultTitle(),
        parentIdentifier = fileIdentifier(parentIndex),
        leaf = true,
        tooltip = match.path & ":" & $match.line & ":" & $match.column,
      )

    let loadMoreIndex = identifier.identifierIndex(SearchLoadMoreIdentifierPrefix)
    if loadMoreIndex in 0 ..< results.xGroups.len:
      let group = results.xGroups[loadMoreIndex]
      if group.visibleCount < group.matchIndexes.len:
        return nimkit.initOutlineItem(
          identifier,
          group.loadMoreTitle(results.xResultsPerFile),
          parentIdentifier = fileIdentifier(loadMoreIndex),
          leaf = true,
          tooltip = "Show more matches from " & group.path,
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
  if sender != nimkit.DynamicAgent(results):
    return
  let identifier = results.selectedItemIdentifier()
  let groupIndex = identifier.identifierIndex(SearchFileIdentifierPrefix)
  if groupIndex in 0 ..< results.xGroups.len:
    results.toggleItem(identifier)
    return
  let loadMoreIndex = identifier.identifierIndex(SearchLoadMoreIdentifierPrefix)
  if loadMoreIndex in 0 ..< results.xGroups.len:
    let group = results.xGroups[loadMoreIndex]
    results.xGroups[loadMoreIndex].visibleCount =
      min(group.visibleCount + results.xResultsPerFile, group.matchIndexes.len)
    results.reloadOutlineData()
    let nextIdentifier =
      if results.xGroups[loadMoreIndex].visibleCount < group.matchIndexes.len:
        loadMoreIdentifier(loadMoreIndex)
      else:
        resultIdentifier(group.matchIndexes[^1])
    results.selectedItemIdentifier = nextIdentifier
    return
  let index = identifier.identifierIndex(SearchResultIdentifierPrefix)
  if index in 0 ..< results.xMatches.len and not results.xOnOpenResult.isNil:
    results.xOnOpenResult(results.xMatches[index], results.xOpenDisposition)

proc matches*(results: KosmoSearchResults): lent seq[nimkit.FileSearchMatch] =
  results.xMatches

proc matchIdentifier*(results: KosmoSearchResults, index: Natural): string =
  ## Return the stable outline identifier for a search result.
  if index < results.xMatches.len:
    result = resultIdentifier(index)

proc `onOpenResult=`*(results: KosmoSearchResults, handler: SearchResultOpenHandler) =
  results.xOnOpenResult = handler

proc setMatches(
    results: KosmoSearchResults,
    rootPath: string,
    matches: openArray[nimkit.FileSearchMatch],
) =
  results.selectedItemIdentifier = ""
  results.xRootPath = rootPath
  results.xMatches = @matches
  results.xGroups.setLen(0)
  results.xMatchGroupIndexes = newSeq[int](matches.len)
  var groupIndexes = initTable[string, int]()
  for index, match in matches:
    var groupIndex: int
    if groupIndexes.hasKey(match.path):
      groupIndex = groupIndexes[match.path]
    else:
      groupIndex = results.xGroups.len
      groupIndexes[match.path] = groupIndex
      results.xGroups.add SearchResultGroup(path: match.path)
    results.xGroups[groupIndex].matchIndexes.add index
    results.xMatchGroupIndexes[index] = groupIndex
  var expanded = newSeqOfCap[string](results.xGroups.len)
  for index in 0 ..< results.xGroups.len:
    results.xGroups[index].visibleCount =
      min(results.xResultsPerFile, results.xGroups[index].matchIndexes.len)
    expanded.add fileIdentifier(index)
  results.expandedItemIdentifiers = expanded
  results.reloadOutlineData()

proc newKosmoSearchResults(): KosmoSearchResults =
  result = KosmoSearchResults(
    xOpenDisposition: fodPermanent, xResultsPerFile: DefaultKosmoSearchResultsPerFile
  )
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

proc updateSearchControls(panel: KosmoFileSearchPanel, searching: bool) =
  panel.progressIndicator.hidden = not searching
  panel.cancelButton.hidden = not searching
  panel.cancelButton.enabled = searching
  if searching:
    panel.progressIndicator.startAnimation()
  else:
    panel.progressIndicator.stopAnimation()

proc finishFileSearch(
    panel: KosmoFileSearchPanel, handle: nimkit.FileSearchHandle
) {.slot.} =
  if handle.isNil or handle != panel.xActiveSearch:
    return
  panel.updateSearchControls(false)
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

proc cancelSearch*(panel: KosmoFileSearchPanel): bool {.discardable.} =
  ## Request cancellation of the running search and keep showing its progress
  ## until the worker acknowledges the request.
  if panel.isNil or panel.xActiveSearch.isNil or panel.xActiveSearch.isFinished():
    return
  panel.xActiveSearch.cancel()
  panel.cancelButton.enabled = false
  panel.statusLabel.text = "Cancelling…"
  result = true

proc cancelFileSearch(panel: KosmoFileSearchPanel, sender: nimkit.DynamicAgent) =
  discard sender
  discard panel.cancelSearch()

proc performSearch*(panel: KosmoFileSearchPanel): bool {.discardable.} =
  ## Start a new asynchronous search for the current query field text.
  if panel.isNil:
    return
  let pattern = panel.queryField.text()
  if pattern.len == 0 or panel.xRootPath.len == 0:
    panel.updateSearchControls(false)
    panel.resultsView.setMatches(panel.xRootPath, [])
    panel.statusLabel.text =
      if pattern.len == 0: "Enter a regular expression" else: "No folder is open"
    return
  if not panel.xActiveSearch.isNil and not panel.xActiveSearch.isFinished():
    panel.xActiveSearch.cancel()
  panel.resultsView.setMatches(panel.xRootPath, [])
  panel.statusLabel.text = "Searching…"
  panel.updateSearchControls(true)
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
    panel.updateSearchControls(false)
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
      cancelSize = min(20.0'f32, contentWidth)
      progressSize = min(18.0'f32, max(contentWidth - cancelSize - 4.0'f32, 0.0'f32))
      trailingWidth =
        if panel.cancelButton.hidden:
          0.0'f32
        else:
          progressSize + cancelSize + 6.0'f32
    panel.queryField.setFrameFromLayout(
      nimkit.rect(horizontalPadding, 8.0'f32, contentWidth, 26.0'f32)
    )
    panel.statusLabel.setFrameFromLayout(
      nimkit.rect(
        horizontalPadding,
        38.0'f32,
        max(contentWidth - trailingWidth, 0.0'f32),
        18.0'f32,
      )
    )
    panel.progressIndicator.setFrameFromLayout(
      nimkit.rect(
        horizontalPadding +
          max(contentWidth - progressSize - cancelSize - 4.0'f32, 0.0'f32),
        38.0'f32,
        progressSize,
        18.0'f32,
      )
    )
    panel.cancelButton.setFrameFromLayout(
      nimkit.rect(
        horizontalPadding + max(contentWidth - cancelSize, 0.0'f32),
        37.0'f32,
        cancelSize,
        20.0'f32,
      )
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
  panel.updateSearchControls(false)
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

proc `onOpenResult=`*(panel: KosmoFileSearchPanel, handler: SearchResultOpenHandler) =
  panel.resultsView.onOpenResult = handler

proc close*(panel: KosmoFileSearchPanel) =
  ## Stop the search workers owned by this panel.
  if panel.isNil or panel.xService.isNil:
    return
  panel.xService.disconnect(nimkit.fileSearchDidFinish, panel, finishFileSearch)
  panel.xService.close()
  panel.xService = nil
  panel.xActiveSearch = nil
  panel.updateSearchControls(false)

proc newKosmoFileSearchPanel*(rootPath = ""): KosmoFileSearchPanel =
  let
    queryField = nimkit.newTextField("")
    resultsView = newKosmoSearchResults()
    statusLabel = nimkit.newStatusLabel("Enter a regular expression")
    progressIndicator = nimkit.newProgressIndicator()
    cancelButton = nimkit.newButton("×")
    searchAction = nimkit.actionSelector(SearchFieldAction)
    cancelAction = nimkit.actionSelector(CancelSearchAction)
  result = KosmoFileSearchPanel(
    queryField: queryField,
    resultsView: resultsView,
    statusLabel: statusLabel,
    progressIndicator: progressIndicator,
    cancelButton: cancelButton,
  )
  result.initViewFields()
  result.addSubview(queryField)
  result.addSubview(statusLabel)
  result.addSubview(progressIndicator)
  result.addSubview(cancelButton)
  result.addSubview(resultsView)
  discard result.withProtocol(KosmoFileSearchPanelLayout)
  let panel = result.unsafeWeakRef()
  progressIndicator.indeterminate = true
  progressIndicator.displayedWhenStopped = false
  progressIndicator.progressIndicatorStyle = nimkit.pisSpinning
  progressIndicator.accessibilityLabel = "Searching files"
  cancelButton.accessibilityLabel = "Cancel search"
  cancelButton.toolTip = "Cancel search"
  queryField.target = nimkit.newActionTarget(
    searchAction,
    proc(sender: nimkit.DynamicAgent) =
      if not panel.isNil:
        panel[].submitFileSearch(sender)
    ,
  )
  queryField.action = searchAction
  cancelButton.target = nimkit.newActionTarget(
    cancelAction,
    proc(sender: nimkit.DynamicAgent) =
      if not panel.isNil:
        panel[].cancelFileSearch(sender)
    ,
  )
  cancelButton.action = cancelAction
  result.updateSearchControls(false)
  result.rootPath = rootPath
