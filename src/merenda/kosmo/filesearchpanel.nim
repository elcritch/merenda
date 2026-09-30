## Find-in-files sidebar UI backed by NimKit's worker-based file search.

import std/[options, os, strutils, tables]
import ../nimkit/foundation/atomicfiles
import ../nimkit/foundation/textsearch

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ./filetree
import ./searchbuttons

const
  DefaultKosmoSearchResultsPerFile* = 30
  SearchFieldAction = "kosmo.performFileSearch"
  CancelSearchAction = "kosmo.cancelFileSearch"
  KosmoCancelSearchButtonStyleId* = "kosmo.cancel-search"
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
    xGroupIndexes: Table[string, int]
    xMatchGroupIndexes: seq[int]
    xOnOpenResult: SearchResultOpenHandler
    xOpenDisposition: FileTreeOpenDisposition
    xRootPath: string
    xResultsPerFile: int

  KosmoFileSearchPanel* = ref object of nimkit.View
    queryField*: nimkit.TextField
    replacementField*: nimkit.TextField
    xReplacementVisible: bool
    disclosureButton: nimkit.Button
    expressionButton: nimkit.Button
    replaceButton*, replaceAllButton*: nimkit.Button
    canReplaceFile*: proc(path: string): bool {.closure.}
    onFileReplaced*: proc(path: string) {.closure.}
    xPattern: string
    xCaseSensitive: bool
    xRegularExpression: bool
    xReplacementSummary: string
    resultsView*: KosmoSearchResults
    statusLabel*: nimkit.Label
    progressIndicator*: nimkit.ProgressIndicator
    cancelButton*: nimkit.Button
    xRootPath: string
    xSearchOptions: nimkit.FileSearchOptions
    xRootPaths: seq[string]
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

proc appendMatches(
  results: KosmoSearchResults, matches: openArray[nimkit.FileSearchMatch]
)

proc setMatches(
    results: KosmoSearchResults,
    rootPath: string,
    matches: openArray[nimkit.FileSearchMatch],
) =
  results.selectedItemIdentifier = ""
  results.xRootPath = rootPath
  results.xMatches.setLen(0)
  results.xGroups.setLen(0)
  results.xGroupIndexes.clear()
  results.xMatchGroupIndexes.setLen(0)
  results.expandedItemIdentifiers = []
  results.reloadOutlineData()
  results.appendMatches(matches)

proc appendMatches(
    results: KosmoSearchResults, matches: openArray[nimkit.FileSearchMatch]
) =
  if matches.len == 0:
    return
  let
    selectedIdentifiers = results.selectedItemIdentifiers()
    previousGroupCount = results.xGroups.len
  for match in matches:
    var groupIndex: int
    if results.xGroupIndexes.hasKey(match.path):
      groupIndex = results.xGroupIndexes[match.path]
    else:
      groupIndex = results.xGroups.len
      results.xGroupIndexes[match.path] = groupIndex
      results.xGroups.add SearchResultGroup(path: match.path)
    let matchIndex = results.xMatches.len
    results.xMatches.add match
    results.xGroups[groupIndex].matchIndexes.add matchIndex
    results.xMatchGroupIndexes.add groupIndex
    if results.xGroups[groupIndex].visibleCount < results.xResultsPerFile:
      results.xGroups[groupIndex].visibleCount =
        min(results.xResultsPerFile, results.xGroups[groupIndex].matchIndexes.len)
  if results.xGroups.len > previousGroupCount:
    var expanded = results.expandedItemIdentifiers()
    for groupIndex in previousGroupCount ..< results.xGroups.len:
      expanded.add fileIdentifier(groupIndex)
    results.expandedItemIdentifiers = expanded
  else:
    results.reloadOutlineData()
  results.selectedItemIdentifiers = selectedIdentifiers

proc newKosmoSearchResults(): KosmoSearchResults =
  result = KosmoSearchResults(
    xGroupIndexes: initTable[string, int](),
    xOpenDisposition: fodPermanent,
    xResultsPerFile: DefaultKosmoSearchResultsPerFile,
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
  panel.replaceButton.enabled = not searching and panel.resultsView.matches.len > 0
  panel.replaceAllButton.enabled = panel.replaceButton.enabled
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
  if panel.resultsView.matches.len != searchResult.matches.len:
    panel.resultsView.setMatches(panel.xRootPath, searchResult.matches)
  panel.statusLabel.text =
    case searchResult.reason
    of nimkit.fsfrCancelled:
      "Search cancelled"
    of nimkit.fsfrResultLimitReached:
      $searchResult.matches.len & " results (limit reached)"
    of nimkit.fsfrFileLimitReached:
      $searchResult.matches.len & " results (file limit reached)"
    of nimkit.fsfrPatternError:
      "Search error: " & searchResult.errorMessage
    of nimkit.fsfrCompleted:
      if searchResult.matches.len == 1:
        "1 result"
      else:
        $searchResult.matches.len & " results"

  panel.updateSearchControls(false)
  if searchResult.reason == nimkit.fsfrPatternError:
    panel.replaceButton.enabled = false
    panel.replaceAllButton.enabled = false
  if panel.xReplacementSummary.len > 0:
    panel.statusLabel.text = panel.xReplacementSummary & "; " & panel.statusLabel.text
    panel.xReplacementSummary = ""

proc appendFileSearchMatches(
    panel: KosmoFileSearchPanel,
    handle: nimkit.FileSearchHandle,
    matches: seq[nimkit.FileSearchMatch],
) {.slot.} =
  if handle.isNil or handle != panel.xActiveSearch:
    return
  panel.resultsView.appendMatches(matches)
  if handle.cancelRequested():
    return
  let count = panel.resultsView.matches.len
  panel.statusLabel.text =
    if count == 1:
      "1 result…"
    else:
      $count & " results…"

proc ensureSearchService(panel: KosmoFileSearchPanel) =
  if panel.xService.isNil:
    panel.xService = nimkit.newFileSearchService()
    panel.xService.connect(
      nimkit.fileSearchDidFindMatches, panel, appendFileSearchMatches
    )
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
  if not panel.xActiveSearch.isNil and not panel.xActiveSearch.isFinished():
    panel.xActiveSearch.cancel()
  panel.xActiveSearch = nil
  panel.xPattern = pattern
  panel.xCaseSensitive = panel.xSearchOptions.caseSensitive
  panel.xRegularExpression = panel.xSearchOptions.regularExpression
  if pattern.len == 0 or panel.xRootPath.len == 0:
    panel.resultsView.setMatches(panel.xRootPath, [])
    panel.updateSearchControls(false)
    panel.statusLabel.text =
      if pattern.len == 0: "Enter search text" else: "No folder is open"
    return
  panel.resultsView.setMatches(panel.xRootPath, [])
  panel.statusLabel.text = "Searching…"
  panel.updateSearchControls(true)
  try:
    panel.ensureSearchService()
    panel.xActiveSearch = panel.xService.search(
      nimkit.initFileSearchQuery(panel.xRootPaths, pattern, panel.xSearchOptions)
    )
    result = true
  except CatchableError as error:
    panel.xActiveSearch = nil
    panel.updateSearchControls(false)
    panel.statusLabel.text = error.msg

proc replaceMatches*(panel: KosmoFileSearchPanel, all = false): int {.discardable.} =
  ## Replace displayed results, validating original lines, spans, and templates.
  if panel.isNil or panel.xActiveSearch.isNil or not panel.xActiveSearch.isFinished():
    return
  if panel.xActiveSearch.result().reason == nimkit.fsfrPatternError:
    return
  if panel.queryField.text() != panel.xPattern or
      panel.xSearchOptions.regularExpression != panel.xRegularExpression or
      panel.xSearchOptions.caseSensitive != panel.xCaseSensitive:
    panel.statusLabel.text = "Run the changed search before replacing"
    return
  var grouped = initOrderedTable[string, seq[nimkit.FileSearchMatch]]()
  let selected = panel.resultsView.selectedItemIdentifier().identifierIndex(
      SearchResultIdentifierPrefix
    )
  for index, match in panel.resultsView.matches:
    if all or index == selected:
      grouped.mgetOrPut(match.path, @[]).add match
  if grouped.len == 0:
    panel.statusLabel.text = "Select a match to replace"
    return
  var pattern: TextSearchPattern
  var replacement: TextSearchReplacement
  try:
    pattern = initTextSearchPattern(
      panel.xPattern, panel.xRegularExpression, panel.xCaseSensitive
    )
    replacement = pattern.initTextSearchReplacement(panel.replacementField.text())
  except TextSearchError as error:
    panel.statusLabel.text = "Replacement error: " & error.msg
    return
  var skipped = 0
  var firstError = ""
  for path, matches in grouped.mpairs:
    try:
      if not panel.canReplaceFile.isNil and not panel.canReplaceFile(path):
        raise newException(IOError, "Unsaved changes: " & path)
      if getFileSize(path) > panel.xSearchOptions.maxFileSizeBytes:
        raise newException(IOError, "File exceeds search size limit: " & path)
      let original = readFile(path)
      var updated = ""
      var last = 0
      var lineEnd = -1
      var replacements = initTable[tuple[offset, length: int], string]()
      for match in matches:
        let offset = int(match.byteOffset)
        if offset < 0 or offset > original.len or
            match.matchLength > original.len - offset:
          raise newException(IOError, "File changed: " & path)
        if offset > lineEnd:
          let lineStart =
            if offset == 0:
              0
            else:
              original.rfind('\n', 0, offset - 1) + 1
          let newline = original.find('\n', offset)
          lineEnd = if newline < 0: original.len else: newline
          if lineEnd > lineStart and original[lineEnd - 1] == '\r':
            dec lineEnd
          let line = original[lineStart ..< lineEnd]
          if line != match.lineText:
            raise newException(IOError, "File changed: " & path)
          # Every result on this line came from the same worker snapshot.
          # Validate its text and enumerate its spans only once.
          replacements.clear()
          for bounds in pattern.findMatches(line):
            replacements[(lineStart + bounds.first, max(bounds.last - bounds.first, 0))] =
              replacement.expand(bounds, line)
        if (offset, match.matchLength) notin replacements:
          raise newException(IOError, "File changed: " & path)
        updated.add original[last ..< max(last, offset)]
        updated.add replacements[(offset, match.matchLength)]
        last = max(last, offset + match.matchLength)
      updated.add original[last ..< original.len]
      if readFile(path) != original:
        raise newException(IOError, "File changed: " & path)
      atomicWriteFile(path, updated)
      result += matches.len
      if not panel.onFileReplaced.isNil:
        panel.onFileReplaced(path)
    except CatchableError as error:
      inc skipped
      if firstError.len == 0:
        firstError = error.msg
  panel.xReplacementSummary = "Replaced " & $result & " matches"
  if skipped > 0:
    panel.xReplacementSummary.add "; skipped " & $skipped & " files (" & firstError & ")"
  discard panel.performSearch()

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
      disclosureWidth = min(24.0'f32, contentWidth / 8)
      fieldX = horizontalPadding + disclosureWidth + 6
      replacementWidth = max(contentWidth - disclosureWidth - 6, 0)
      fieldWidth = max(replacementWidth - 34, 0)
      statusY = if panel.xReplacementVisible: 104.0'f32 else: 38.0'f32
      resultsY = statusY + 22
      cancelSize = min(20.0'f32, contentWidth)
      progressSize = min(18.0'f32, max(contentWidth - cancelSize - 4.0'f32, 0.0'f32))
      trailingWidth =
        if panel.cancelButton.hidden:
          0.0'f32
        else:
          progressSize + cancelSize + 6.0'f32
    panel.disclosureButton.setFrameFromLayout(
      nimkit.rect(horizontalPadding, 8, disclosureWidth, 26)
    )
    panel.queryField.setFrameFromLayout(
      nimkit.rect(fieldX, 8.0'f32, fieldWidth, 26.0'f32)
    )
    panel.expressionButton.setFrameFromLayout(
      nimkit.rect(fieldX + fieldWidth + 6, 8, 28, 26)
    )
    panel.replacementField.setFrameFromLayout(
      nimkit.rect(fieldX, 40, replacementWidth, 26)
    )
    let buttonWidth = max((replacementWidth - 6) / 2, 1)
    panel.replaceButton.setFrameFromLayout(nimkit.rect(fieldX, 72, buttonWidth, 26))
    panel.replaceAllButton.setFrameFromLayout(
      nimkit.rect(fieldX + buttonWidth + 6, 72, buttonWidth, 26)
    )
    panel.statusLabel.setFrameFromLayout(
      nimkit.rect(
        horizontalPadding, statusY, max(contentWidth - trailingWidth, 0.0'f32), 18.0'f32
      )
    )
    panel.progressIndicator.setFrameFromLayout(
      nimkit.rect(
        horizontalPadding +
          max(contentWidth - progressSize - cancelSize - 4.0'f32, 0.0'f32),
        statusY,
        progressSize,
        18.0'f32,
      )
    )
    panel.cancelButton.setFrameFromLayout(
      nimkit.rect(
        horizontalPadding + max(contentWidth - cancelSize, 0.0'f32),
        statusY - 1,
        cancelSize,
        20.0'f32,
      )
    )
    panel.resultsView.setFrameFromLayout(
      nimkit.rect(
        0.0'f32,
        resultsY,
        bounds.size.width,
        max(bounds.size.height - resultsY, 0.0'f32),
      )
    )

proc rootPath*(panel: KosmoFileSearchPanel): string =
  panel.xRootPath

proc rootPaths*(panel: KosmoFileSearchPanel): seq[string] =
  ## Return all folders included in subsequent searches.
  panel.xRootPaths

proc `rootPaths=`*(panel: KosmoFileSearchPanel, rootPaths: openArray[string]) =
  ## Replace the search roots and discard results from the previous workspace.
  var next: seq[string]
  for root in rootPaths:
    if root.len > 0 and dirExists(root):
      let path = normalizedPath(absolutePath(root))
      if path notin next:
        next.add path
  if panel.xRootPaths == next:
    return
  if not panel.xActiveSearch.isNil and not panel.xActiveSearch.isFinished():
    panel.xActiveSearch.cancel()
  panel.xActiveSearch = nil
  panel.updateSearchControls(false)
  panel.xRootPaths = next
  panel.xRootPath =
    if next.len > 0:
      next[0]
    else:
      ""
  panel.resultsView.setMatches(panel.xRootPath, [])
  panel.updateSearchControls(false)
  panel.statusLabel.text = "Enter search text"

proc `rootPath=`*(panel: KosmoFileSearchPanel, rootPath: string) =
  panel.rootPaths = [rootPath]

proc activeSearch*(panel: KosmoFileSearchPanel): nimkit.FileSearchHandle =
  panel.xActiveSearch

proc searchOptions*(panel: KosmoFileSearchPanel): nimkit.FileSearchOptions =
  ## Return the options applied to future searches from this panel.
  panel.xSearchOptions

proc `searchOptions=`*(panel: KosmoFileSearchPanel, options: nimkit.FileSearchOptions) =
  ## Configure future searches without interrupting the current search.
  panel.xSearchOptions = options
  panel.expressionButton.state =
    if options.regularExpression: nimkit.bsOn else: nimkit.bsOff
  panel.replacementField.accessibilityLabel =
    if options.regularExpression:
      "Replace with (capture template)"
    else:
      "Replace with (literal text)"
  panel.replacementField.toolTip =
    if options.regularExpression:
      "Reni replacement: $0, $1, ${name}, $$"
    else:
      "Literal replacement text"

func regularExpression*(panel: KosmoFileSearchPanel): bool =
  panel.xSearchOptions.regularExpression

proc `regularExpression=`*(panel: KosmoFileSearchPanel, enabled: bool) =
  ## Re-run the query when its interpretation changes; stale batches are ignored.
  var options = panel.xSearchOptions
  options.regularExpression = enabled
  panel.searchOptions = options
  if panel.queryField.text().len > 0:
    discard panel.performSearch()

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

func replacementVisible*(panel: KosmoFileSearchPanel): bool =
  panel.xReplacementVisible

proc `replacementVisible=`*(panel: KosmoFileSearchPanel, visible: bool) =
  ## Expand or collapse replacement while preserving the search and its results.
  let owner = panel.window()
  if not visible and owner of nimkit.Window:
    let window = nimkit.Window(owner)
    if window.fieldEditorClient() == panel.replacementField or
        window.firstResponder() == panel.replaceButton or
        window.firstResponder() == panel.replaceAllButton:
      discard panel.focusQuery()
  panel.xReplacementVisible = visible
  panel.replacementField.hidden = not visible
  panel.replaceButton.hidden = not visible
  panel.replaceAllButton.hidden = not visible
  panel.disclosureButton.showSearchDisclosure(visible)
  panel.disclosureButton.accessibilityLabel =
    if visible: "Hide replacement controls" else: "Show replacement controls"
  panel.disclosureButton.toolTip = panel.disclosureButton.accessibilityLabel()
  panel.setNeedsLayout()
  panel.layoutSubtreeIfNeeded()

proc `onOpenResult=`*(panel: KosmoFileSearchPanel, handler: SearchResultOpenHandler) =
  panel.resultsView.onOpenResult = handler

proc close*(panel: KosmoFileSearchPanel) =
  ## Stop the search workers owned by this panel.
  if panel.isNil or panel.xService.isNil:
    return
  panel.xService.disconnect(
    nimkit.fileSearchDidFindMatches, panel, appendFileSearchMatches
  )
  panel.xService.disconnect(nimkit.fileSearchDidFinish, panel, finishFileSearch)
  panel.xService.close()
  panel.xService = nil
  panel.xActiveSearch = nil
  panel.updateSearchControls(false)

proc newKosmoFileSearchPanel*(rootPath = ""): KosmoFileSearchPanel =
  let
    queryField = nimkit.newTextField("")
    resultsView = newKosmoSearchResults()
    statusLabel = nimkit.newStatusLabel("Enter search text")
    progressIndicator = nimkit.newProgressIndicator()
    cancelButton = newSearchButton("X", symbol = true)
    searchAction = nimkit.actionSelector(SearchFieldAction)
    cancelAction = nimkit.actionSelector(CancelSearchAction)
  result = KosmoFileSearchPanel(
    queryField: queryField,
    replacementField: nimkit.newTextField(),
    disclosureButton: newSearchButton("›", symbol = true),
    expressionButton: newSearchButton(".*", symbol = true),
    replaceButton: newSearchButton("Replace"),
    replaceAllButton: newSearchButton("Replace All"),
    resultsView: resultsView,
    statusLabel: statusLabel,
    progressIndicator: progressIndicator,
    cancelButton: cancelButton,
    xSearchOptions:
      nimkit.initFileSearchOptions(caseSensitive = false, regularExpression = false),
  )
  result.initViewFields()
  result.addSubview(queryField)
  result.addSubview(result.expressionButton)
  result.addSubview(result.replacementField)
  result.replacementField.placeholder = "Replace with"
  result.addSubview(result.replaceButton)
  result.addSubview(result.replaceAllButton)
  result.addSubview(result.disclosureButton)
  result.addSubview(statusLabel)
  result.addSubview(progressIndicator)
  result.addSubview(cancelButton)
  result.addSubview(resultsView)
  discard result.withProtocol(KosmoFileSearchPanelLayout)
  let panel = result.unsafeWeakRef()
  result.expressionButton.buttonType = nimkit.btToggle
  result.expressionButton.accessibilityLabel = "Use Reni regular expressions"
  result.expressionButton.toolTip = "Use Reni expressions and replacement captures"
  result.expressionButton.action = nimkit.actionSelector("kosmo.fileSearchExpressions")
  result.expressionButton.target = nimkit.newActionTarget(
    result.expressionButton.action
  ) do(sender: nimkit.DynamicAgent):
    if not panel.isNil:
      panel[].regularExpression = panel[].expressionButton.state == nimkit.bsOn
      discard panel[].focusQuery()
  result.disclosureButton.action = nimkit.actionSelector("kosmo.toggleFileReplacement")
  result.disclosureButton.target = nimkit.newActionTarget(
    result.disclosureButton.action
  ) do(sender: nimkit.DynamicAgent):
    if not panel.isNil:
      panel[].replacementVisible = not panel[].replacementVisible
      discard panel[].focusQuery()
  result.replacementField.accessibilityLabel = "Replace with (literal text)"
  result.replacementField.toolTip = "Replacement text (literal; empty deletes matches)"
  result.replaceButton.accessibilityLabel = "Replace selected match"
  result.replaceButton.toolTip = "Replace the selected match"
  result.replaceAllButton.toolTip = "Replace all displayed matches in files"
  result.replaceButton.action = nimkit.actionSelector("kosmo.replaceFileMatch")
  result.replaceButton.target = nimkit.newActionTarget(result.replaceButton.action) do(
    sender: nimkit.DynamicAgent
  ):
    if not panel.isNil:
      discard panel[].replaceMatches()
  result.replaceAllButton.action = nimkit.actionSelector("kosmo.replaceAllFileMatches")
  result.replaceAllButton.target = nimkit.newActionTarget(
    result.replaceAllButton.action
  ) do(sender: nimkit.DynamicAgent):
    if not panel.isNil:
      discard panel[].replaceMatches(all = true)
  progressIndicator.indeterminate = true
  progressIndicator.displayedWhenStopped = false
  progressIndicator.progressIndicatorStyle = nimkit.pisSpinning
  progressIndicator.accessibilityLabel = "Searching files"
  cancelButton.accessibilityLabel = "Cancel search"
  cancelButton.toolTip = "Cancel search"
  cancelButton.styleId = KosmoCancelSearchButtonStyleId
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
  result.replacementVisible = false
  result.rootPath = rootPath
