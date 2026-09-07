## A lazy filesystem tree for Kosmo frontends.

import std/[algorithm, options, os, sets, strutils, tables, times, unicode]

import ../nimkit as nimkit except performKeyEquivalent
from ../nimkit/foundation/selectors import performKeyEquivalent
from ../nimkit/view/viewgeometry import setFrameFromLayout

type
  FileTreeDisplayMode* {.pure.} = enum
    AllFiles
    VisibleFiles
    SourceControlChanges

  FileTreeOpenDisposition* = enum
    fodPermanent
    fodTemporary

  FileTreeOpenHandler* =
    proc(path: string, disposition: FileTreeOpenDisposition) {.closure.}

  FileTreeSearchEntry = object
    path: string
    normalizedName: string
    hidden: bool

  KosmoFileTree* = ref object of nimkit.OutlineView
    xRootPath: string
    xRootPaths: seq[string]
    xFileSystem: nimkit.FileSystemBrowserModel
    xChildren: Table[string, seq[string]]
    xOnOpenFile: FileTreeOpenHandler
    xOpenDisposition: FileTreeOpenDisposition
    xGitStatusService: nimkit.GitStatusService
    xGitSnapshots: Table[string, nimkit.GitStatusSnapshot]
    xGitFileStates: Table[string, nimkit.GitFileState]
    xGitDescendantStates: Table[string, nimkit.GitFileState]
    xGitChildren: Table[string, seq[string]]
    xVisibleChildren: Table[string, seq[string]]
    xMatchingPaths: HashSet[string]
    xFilterText: string
    xDisplayMode: FileTreeDisplayMode
    xExpandedBeforeFilter: seq[string]
    xSearchEntries: seq[FileTreeSearchEntry]
    xSearchIndexValid: bool

  KosmoFileBrowserPanel* = ref object of nimkit.View
    fileTree*: KosmoFileTree
    filterField*: nimkit.TextField
    scopeButton*: nimkit.PopupMenuButton
    closeFilterButton*: nimkit.Button
    promptLabel: nimkit.Label

  KosmoFileFilterFieldEditor = ref object of nimkit.FieldEditor
    panel: WeakRef[KosmoFileBrowserPanel]

  KosmoFileFilterFieldCell = ref object of nimkit.TextFieldCell
    editor: KosmoFileFilterFieldEditor

  KosmoFileFilterPromptLabel = ref object of nimkit.Label

const
  GitModifiedColor = nimkit.color(0.82, 0.62, 0.20, 1.0)
  GitAddedColor = nimkit.color(0.32, 0.72, 0.40, 1.0)
  GitDeletedColor = nimkit.color(0.90, 0.32, 0.32, 1.0)
  GitRenamedColor = nimkit.color(0.32, 0.64, 0.88, 1.0)
  GitConflictedColor = nimkit.color(0.94, 0.30, 0.36, 1.0)
  GitIgnoredColor = nimkit.color(0.50, 0.52, 0.56, 0.72)
  FileTreeScopeAction = "kosmo.fileTreeScope"
  FileTreeCloseFilterAction = "kosmo.fileTreeCloseFilter"
  FileBrowserControlInset = 8.0'f32
  FileBrowserControlHeight = 26.0'f32
  FileBrowserControlRowHeight = 42.0'f32

func title*(mode: FileTreeDisplayMode): string =
  case mode
  of FileTreeDisplayMode.AllFiles: "All Files"
  of FileTreeDisplayMode.VisibleFiles: "Visible Files"
  of FileTreeDisplayMode.SourceControlChanges: "Changed Files"

proc expandableDirectory(path: string): bool =
  path.isBrowsableDirectory()

proc loadChildPaths(tree: KosmoFileTree, parentIdentifier: string) =
  if tree.xChildren.hasKey(parentIdentifier):
    return
  var children: seq[string]
  if parentIdentifier.len == 0:
    children.add tree.xRootPaths
  elif parentIdentifier.expandableDirectory():
    for entry in tree.xFileSystem.entries(parentIdentifier):
      children.add entry.path
  tree.xChildren[parentIdentifier] = children

proc rawChildPaths(tree: KosmoFileTree, parentIdentifier: string): lent seq[string] =
  tree.loadChildPaths(parentIdentifier)
  tree.xChildren[parentIdentifier]

proc hiddenPath(tree: KosmoFileTree, path: string): bool =
  var currentPath = path
  while currentPath.len > 0 and currentPath notin tree.xRootPaths:
    if currentPath.extractFilename().startsWith("."):
      return true
    let parentPath = currentPath.parentDir()
    if parentPath == currentPath:
      break
    currentPath = parentPath

proc isTreeDirectory(tree: KosmoFileTree, path: string): bool =
  path.expandableDirectory() or path in tree.xGitDescendantStates

proc compareTreePaths(tree: KosmoFileTree, left, right: string): int =
  let
    leftDirectory = tree.isTreeDirectory(left)
    rightDirectory = tree.isTreeDirectory(right)
  if leftDirectory != rightDirectory:
    return if leftDirectory: -1 else: 1
  cmpIgnoreCase(left.fileBrowserDisplayName(), right.fileBrowserDisplayName())

proc changedChildPaths(tree: KosmoFileTree, parentIdentifier: string): seq[string] =
  if parentIdentifier in tree.xGitChildren:
    result = tree.xGitChildren[parentIdentifier]

proc rebuildGitChildren(tree: KosmoFileTree) =
  tree.xGitChildren.clear()
  var seenChildren = initTable[string, HashSet[string]]()
  for path, state in tree.xGitFileStates:
    if state == nimkit.gfsIgnored:
      continue
    var childPath = path
    while childPath.len > 0:
      let parentPath = childPath.parentDir()
      if parentPath == childPath:
        break
      if childPath notin seenChildren.mgetOrPut(parentPath, initHashSet[string]()):
        seenChildren[parentPath].incl childPath
        tree.xGitChildren.mgetOrPut(parentPath, @[]).add childPath
      childPath = parentPath
  for parentPath, children in tree.xGitChildren.mpairs:
    discard parentPath
    children.sort(
      proc(left, right: string): int =
        tree.compareTreePaths(left, right)
    )

proc displayModeIncludes(tree: KosmoFileTree, path: string): bool =
  case tree.xDisplayMode
  of FileTreeDisplayMode.AllFiles:
    true
  of FileTreeDisplayMode.VisibleFiles:
    not tree.hiddenPath(path)
  of FileTreeDisplayMode.SourceControlChanges:
    (path in tree.xGitFileStates and tree.xGitFileStates[path] != nimkit.gfsIgnored) or
      path in tree.xGitDescendantStates

proc filteredChildPaths(
    tree: KosmoFileTree, parentIdentifier: string
): lent seq[string] =
  if parentIdentifier notin tree.xVisibleChildren:
    var candidates: seq[string]
    if parentIdentifier.len == 0:
      candidates.add tree.xRootPaths
    elif tree.xDisplayMode == FileTreeDisplayMode.SourceControlChanges:
      candidates = tree.changedChildPaths(parentIdentifier)
    else:
      candidates.add tree.rawChildPaths(parentIdentifier)
    var children: seq[string]
    for path in candidates:
      if tree.displayModeIncludes(path) and
          (tree.xFilterText.strip().len == 0 or path in tree.xMatchingPaths):
        children.add path
    tree.xVisibleChildren[parentIdentifier] = children
  tree.xVisibleChildren[parentIdentifier]

proc includePathAndAncestors(
    tree: KosmoFileTree, path: string, expanded: var seq[string]
) =
  for root in tree.xRootPaths:
    if not path.isRelativeTo(root):
      continue
    var currentPath = path
    while currentPath.len > 0:
      tree.xMatchingPaths.incl currentPath
      if currentPath == root:
        if currentPath notin expanded:
          expanded.add currentPath
        break
      currentPath = currentPath.parentDir()
      if currentPath.len > 0 and currentPath notin expanded:
        expanded.add currentPath

proc collectSearchEntries(
    tree: KosmoFileTree, parentIdentifier: string, seen: var HashSet[string]
) =
  for path in tree.rawChildPaths(parentIdentifier):
    if path.expandableDirectory():
      tree.collectSearchEntries(path, seen)
    elif path notin seen:
      seen.incl path
      tree.xSearchEntries.add FileTreeSearchEntry(
        path: path,
        normalizedName: path.fileBrowserDisplayName().toLower(),
        hidden: tree.hiddenPath(path),
      )

proc ensureSearchIndex(tree: KosmoFileTree) =
  if tree.xSearchIndexValid:
    return
  tree.xSearchEntries.setLen(0)
  var seen = initHashSet[string]()
  for root in tree.xRootPaths:
    tree.collectSearchEntries(root, seen)
  tree.xSearchIndexValid = true

proc invalidateSearchIndex(tree: KosmoFileTree) =
  tree.xSearchEntries.setLen(0)
  tree.xSearchIndexValid = false

proc rebuildMatchingPaths(tree: KosmoFileTree): seq[string] =
  tree.xMatchingPaths.clear()
  let needle = tree.xFilterText.strip().toLower()
  if needle.len == 0:
    return
  if tree.xDisplayMode == FileTreeDisplayMode.SourceControlChanges:
    for path, state in tree.xGitFileStates:
      if state != nimkit.gfsIgnored and
          path.fileBrowserDisplayName().toLower().contains(needle):
        tree.includePathAndAncestors(path, result)
  else:
    tree.ensureSearchIndex()
    for entry in tree.xSearchEntries:
      if (tree.xDisplayMode != FileTreeDisplayMode.VisibleFiles or not entry.hidden) and
          entry.normalizedName.contains(needle):
        tree.includePathAndAncestors(entry.path, result)

proc reloadFilteredTree(tree: KosmoFileTree, updateSearchExpansion = true) =
  tree.xVisibleChildren.clear()
  if tree.xFilterText.strip().len > 0:
    let expanded = tree.rebuildMatchingPaths()
    if updateSearchExpansion:
      tree.expandedItemIdentifiers = expanded
  tree.reloadOutlineData()

func gitStatePriority(state: nimkit.GitFileState): int =
  case state
  of nimkit.gfsConflicted: 6
  of nimkit.gfsDeleted: 5
  of nimkit.gfsModified: 4
  of nimkit.gfsRenamed: 3
  of nimkit.gfsAdded: 2
  of nimkit.gfsUntracked: 1
  of nimkit.gfsIgnored: 0

func gitStateTitle(state: nimkit.GitFileState): string =
  case state
  of nimkit.gfsModified: "Modified"
  of nimkit.gfsAdded: "Added"
  of nimkit.gfsDeleted: "Deleted"
  of nimkit.gfsRenamed: "Renamed"
  of nimkit.gfsUntracked: "Untracked"
  of nimkit.gfsConflicted: "Merge conflict"
  of nimkit.gfsIgnored: "Ignored"

func gitStateBadge(state: nimkit.GitFileState): string =
  case state
  of nimkit.gfsModified: "M"
  of nimkit.gfsAdded: "A"
  of nimkit.gfsDeleted: "D"
  of nimkit.gfsRenamed: "R"
  of nimkit.gfsUntracked: "U"
  of nimkit.gfsConflicted: "!"
  of nimkit.gfsIgnored: ""

func gitStateColor(state: nimkit.GitFileState): nimkit.Color =
  case state
  of nimkit.gfsModified: GitModifiedColor
  of nimkit.gfsAdded, nimkit.gfsUntracked: GitAddedColor
  of nimkit.gfsDeleted: GitDeletedColor
  of nimkit.gfsRenamed: GitRenamedColor
  of nimkit.gfsConflicted: GitConflictedColor
  of nimkit.gfsIgnored: GitIgnoredColor

proc includeGitState(
    states: var Table[string, nimkit.GitFileState],
    path: string,
    state: nimkit.GitFileState,
) =
  if path notin states or state.gitStatePriority() > states[path].gitStatePriority():
    states[path] = state

proc isWithinHiddenDirectory(tree: KosmoFileTree, path: string): bool =
  var currentPath = path
  while currentPath.len > 0 and currentPath notin tree.xRootPaths:
    if currentPath.extractFilename().startsWith(".") and dirExists(currentPath):
      return true
    let parentPath = currentPath.parentDir()
    if parentPath == currentPath:
      break
    currentPath = parentPath

proc gitDecoration(tree: KosmoFileTree, path: string): nimkit.OutlineItemDecoration =
  if path in tree.xGitFileStates:
    let state = tree.xGitFileStates[path]
    return nimkit.initOutlineItemDecoration(
      badge = state.gitStateBadge(),
      color = some(state.gitStateColor()),
      tooltip = state.gitStateTitle(),
      badgePlacement = nimkit.oibpLeading,
    )
  var parentPath = path.parentDir()
  while parentPath.len > 0:
    if parentPath in tree.xGitFileStates and
        tree.xGitFileStates[parentPath] == nimkit.gfsIgnored:
      return nimkit.initOutlineItemDecoration(
        color = some(GitIgnoredColor), tooltip = nimkit.gfsIgnored.gitStateTitle()
      )
    if parentPath in tree.xRootPaths:
      break
    let nextParent = parentPath.parentDir()
    if nextParent == parentPath:
      break
    parentPath = nextParent
  if tree.isWithinHiddenDirectory(path):
    return nimkit.initOutlineItemDecoration(
      color = some(GitIgnoredColor), tooltip = nimkit.gfsIgnored.gitStateTitle()
    )
  if path in tree.xGitDescendantStates:
    let state = tree.xGitDescendantStates[path]
    return nimkit.initOutlineItemDecoration(
      color = some(state.gitStateColor()),
      tooltip = "Contains " & state.gitStateTitle().toLowerAscii() & " files",
    )

protocol KosmoFileTreeDataSource of nimkit.OutlineViewDataSource:
  method numberOfChildren(
      tree: KosmoFileTree, outlineView: nimkit.OutlineView, parentIdentifier: string
  ): int =
    discard outlineView
    tree.filteredChildPaths(parentIdentifier).len

  method childIdentifier(
      tree: KosmoFileTree,
      outlineView: nimkit.OutlineView,
      parentIdentifier: string,
      index: int,
  ): string =
    discard outlineView
    let children = tree.filteredChildPaths(parentIdentifier)
    if index in 0 ..< children.len:
      children[index]
    else:
      ""

  method outlineItem(
      tree: KosmoFileTree, outlineView: nimkit.OutlineView, identifier: string
  ): nimkit.OutlineItem =
    discard outlineView
    if identifier.len == 0:
      return
    let
      expandable = tree.isTreeDirectory(identifier)
      decoration = tree.gitDecoration(identifier)
    nimkit.initOutlineItem(
      identifier,
      identifier.fileBrowserDisplayName(),
      parentIdentifier =
        if identifier in tree.xRootPaths:
          ""
        else:
          identifier.parentDir(),
      expandable = expandable,
      leaf = not expandable,
      tooltip =
        if decoration.tooltip.len > 0:
          identifier & "\n" & decoration.tooltip
        else:
          identifier,
      decoration = decoration,
    )

protocol KosmoFileTreeTableDelegate of nimkit.TableViewDelegate:
  method shouldEditCell(
      tree: KosmoFileTree,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): bool =
    false

protocol KosmoFileTreeEvents of nimkit.ResponderEventProtocol:
  method mouseUp(tree: KosmoFileTree, event: nimkit.MouseEvent): bool =
    tree.xOpenDisposition = if event.clickCount >= 2: fodPermanent else: fodTemporary
    defer:
      tree.xOpenDisposition = fodPermanent
    let next = tree.performNext(mouseUp, event)
    if next.isSome: next.get else: false

proc fileTreeRowWasActivated(
    tree: KosmoFileTree, sender: nimkit.DynamicAgent
) {.slot.} =
  if sender != nimkit.DynamicAgent(tree):
    return
  let path = tree.selectedItemIdentifier()
  if tree.isTreeDirectory(path):
    if tree.xOpenDisposition == fodPermanent:
      tree.toggleItem(path)
  elif fileExists(path) and not tree.xOnOpenFile.isNil:
    tree.xOnOpenFile(path, tree.xOpenDisposition)

proc rootPath*(tree: KosmoFileTree): string =
  ## Return the first project root, used as the default working directory.
  tree.xRootPath

proc rootPaths*(tree: KosmoFileTree): lent seq[string] =
  ## Return the file browser's ordered top-level folders.
  tree.xRootPaths

func displayMode*(tree: KosmoFileTree): FileTreeDisplayMode =
  tree.xDisplayMode

proc `displayMode=`*(tree: KosmoFileTree, mode: FileTreeDisplayMode) =
  ## Choose whether the tree shows every file, non-hidden files, or Git changes.
  if tree.isNil or tree.xDisplayMode == mode:
    return
  tree.xDisplayMode = mode
  tree.reloadFilteredTree()

proc filterText*(tree: KosmoFileTree): string =
  tree.xFilterText

proc `filterText=`*(tree: KosmoFileTree, text: string) =
  ## Filter file names case-insensitively while retaining their ancestor folders.
  if tree.isNil or tree.xFilterText == text:
    return
  let wasFiltering = tree.xFilterText.strip().len > 0
  tree.xFilterText = text
  let isFiltering = tree.xFilterText.strip().len > 0
  if not wasFiltering and isFiltering:
    tree.xExpandedBeforeFilter = tree.expandedItemIdentifiers()
  elif wasFiltering and not isFiltering:
    tree.xMatchingPaths.clear()
    tree.xVisibleChildren.clear()
    tree.expandedItemIdentifiers = tree.xExpandedBeforeFilter
    tree.reloadOutlineData()
    return
  tree.reloadFilteredTree()

proc reloadRoots(tree: KosmoFileTree, expanded: seq[string]) =
  tree.xFileSystem.invalidate()
  tree.xChildren.clear()
  tree.invalidateSearchIndex()
  tree.xVisibleChildren.clear()
  tree.xExpandedBeforeFilter = expanded
  if tree.xFilterText.strip().len > 0:
    tree.xMatchingPaths.clear()
    tree.expandedItemIdentifiers = tree.rebuildMatchingPaths()
  else:
    tree.expandedItemIdentifiers = expanded
  tree.selectedItemIdentifier = ""
  tree.reloadOutlineData()

proc `rootPath=`*(tree: KosmoFileTree, path: string) =
  let next =
    if path.len > 0 and dirExists(path):
      normalizedPath(absolutePath(path))
    else:
      ""
  let nextRoots =
    if next.len > 0:
      @[next]
    else:
      @[]
  if tree.xRootPath == next and tree.xRootPaths == nextRoots:
    return
  tree.xRootPath = next
  tree.xRootPaths = nextRoots
  tree.xGitFileStates.clear()
  tree.xGitDescendantStates.clear()
  tree.xGitChildren.clear()
  tree.xGitSnapshots.clear()
  if not tree.xGitStatusService.isNil:
    tree.xGitStatusService.rootPaths = nextRoots
  let expanded =
    if next.len > 0:
      @[next]
    else:
      @[]
  tree.reloadRoots(expanded)

proc addRootPath*(tree: KosmoFileTree, path: string): bool {.discardable.} =
  ## Append a directory to the browser's ordered top-level folders.
  if tree.isNil or path.len == 0 or not dirExists(path):
    return
  let next = normalizedPath(absolutePath(path))
  if next in tree.xRootPaths:
    return
  if tree.xRootPath.len == 0:
    tree.xRootPath = next
    tree.xGitFileStates.clear()
    tree.xGitDescendantStates.clear()
    tree.xGitChildren.clear()
  tree.xRootPaths.add next
  if not tree.xGitStatusService.isNil:
    tree.xGitStatusService.rootPaths = tree.xRootPaths
  var expanded = tree.expandedItemIdentifiers()
  expanded.add next
  tree.reloadRoots(expanded)
  result = true

proc refresh*(tree: KosmoFileTree) =
  ## Discard cached directory listings and reload the visible hierarchy.
  tree.xFileSystem.invalidate()
  tree.xChildren.clear()
  tree.invalidateSearchIndex()
  tree.reloadFilteredTree()

proc applyGitStatus*(tree: KosmoFileTree, snapshot: nimkit.GitStatusSnapshot) =
  ## Replace one root's decorations while retaining snapshots for the other roots.
  if tree.isNil or snapshot.rootPath notin tree.xRootPaths:
    return
  tree.xGitSnapshots[snapshot.rootPath] = snapshot
  var
    fileStates = initTable[string, nimkit.GitFileState]()
    descendantStates = initTable[string, nimkit.GitFileState]()
  for root, rootSnapshot in tree.xGitSnapshots:
    if rootSnapshot.isRepository:
      for entry in rootSnapshot.entries:
        fileStates.includeGitState(entry.path, entry.state)
        if entry.state != nimkit.gfsIgnored:
          var parentPath = entry.path.parentDir()
          while parentPath.len > 0:
            descendantStates.includeGitState(parentPath, entry.state)
            if parentPath == root:
              break
            let nextParent = parentPath.parentDir()
            if nextParent == parentPath:
              break
            parentPath = nextParent
  if tree.xGitFileStates == fileStates and tree.xGitDescendantStates == descendantStates:
    return
  tree.xGitFileStates = fileStates
  tree.xGitDescendantStates = descendantStates
  tree.rebuildGitChildren()
  tree.reloadFilteredTree()

proc applyRefreshedGitStatus(
    tree: KosmoFileTree, snapshot: nimkit.GitStatusSnapshot
) {.slot.} =
  tree.applyGitStatus(snapshot)

proc startGitStatusMonitoring*(
    tree: KosmoFileTree,
    refreshInterval: Duration = nimkit.DefaultGitStatusRefreshInterval,
): nimkit.GitStatusService =
  ## Start periodic asynchronous Git decorations for this tree.
  if tree.isNil:
    return
  if not tree.xGitStatusService.isNil:
    tree.xGitStatusService.close()
  result = nimkit.newGitStatusService(refreshInterval = refreshInterval)
  result.connect(nimkit.gitStatusDidRefresh, tree, applyRefreshedGitStatus)
  tree.xGitStatusService = result
  result.rootPaths = tree.xRootPaths

proc refreshGitStatus*(tree: KosmoFileTree): bool {.discardable.} =
  ## Request an immediate status refresh in addition to the periodic schedule.
  not tree.isNil and not tree.xGitStatusService.isNil and
    tree.xGitStatusService.refresh()

proc waitForGitStatus*(
    tree: KosmoFileTree, timeoutMilliseconds: Natural = 5_000
): bool {.discardable.} =
  not tree.isNil and not tree.xGitStatusService.isNil and
    tree.xGitStatusService.waitForIdle(timeoutMilliseconds)

proc stopGitStatusMonitoring*(tree: KosmoFileTree) =
  ## Stop and join the Git status worker owned by this tree.
  if tree.isNil or tree.xGitStatusService.isNil:
    return
  tree.xGitStatusService.disconnect(
    nimkit.gitStatusDidRefresh, tree, applyRefreshedGitStatus
  )
  tree.xGitStatusService.close()
  tree.xGitStatusService = nil

proc onOpenFile*(tree: KosmoFileTree): FileTreeOpenHandler =
  tree.xOnOpenFile

proc `onOpenFile=`*(tree: KosmoFileTree, handler: FileTreeOpenHandler) =
  tree.xOnOpenFile = handler

proc syncScopeControl(panel: KosmoFileBrowserPanel) =
  let mode = panel.fileTree.displayMode()
  panel.scopeButton.title = mode.title()
  panel.scopeButton.toolTip = mode.title()
  for index, item in panel.scopeButton.menu().items():
    item.state = if index == mode.ord: nimkit.bsOn else: nimkit.bsOff

proc selectScope(panel: KosmoFileBrowserPanel, mode: FileTreeDisplayMode) =
  panel.fileTree.displayMode = mode
  panel.syncScopeControl()

proc toggleTreeExpansion(tree: KosmoFileTree) =
  var
    pending = @[""]
    directories: seq[string]
    seen = initHashSet[string]()
    hasCollapsedDirectory = false
  while pending.len > 0:
    let parent = pending.pop()
    for path in tree.filteredChildPaths(parent):
      if path notin seen and tree.isTreeDirectory(path):
        seen.incl path
        directories.add path
        pending.add path
        if not tree.isItemExpanded(path):
          hasCollapsedDirectory = true
  tree.expandedItemIdentifiers =
    if hasCollapsedDirectory:
      directories
    else:
      @[]

proc newScopeMenuItem(
    panel: WeakRef[KosmoFileBrowserPanel], mode: FileTreeDisplayMode
): nimkit.MenuItem =
  # A separate call gives each callback its own captured mode.
  let action = nimkit.actionSelector(FileTreeScopeAction)
  result = nimkit.newMenuItem(mode.title(), action)
  result.target = nimkit.newActionTarget(action) do(sender: nimkit.DynamicAgent):
    discard sender
    if not panel.isNil:
      panel[].selectScope(mode)
  result.validates = false

proc filterTextDidChange(
    panel: KosmoFileBrowserPanel, sender: nimkit.DynamicAgent
) {.slot.} =
  discard sender
  panel.promptLabel.hidden = panel.filterField.text().len > 0
  panel.fileTree.filterText = panel.filterField.text()

proc showFilter*(panel: KosmoFileBrowserPanel): bool {.discardable.} =
  ## Reveal and focus the live file-name filter.
  if panel.isNil or not (panel.window() of nimkit.Window):
    return
  if panel.filterField.hidden():
    panel.filterField.hidden = false
    panel.promptLabel.hidden = panel.filterField.text().len > 0
    panel.closeFilterButton.hidden = false
    panel.setNeedsLayout()
    panel.layoutSubtreeIfNeeded()
  else:
    panel.filterField.selectedRange =
      nimkit.initTextRange(0, panel.filterField.text().runeLen)
  nimkit.Window(panel.window()).makeFirstResponder(panel.filterField)

proc dismissFilter*(panel: KosmoFileBrowserPanel) =
  ## Clear and hide the live filter, returning keyboard focus to the tree.
  if panel.isNil:
    return
  panel.filterField.text = ""
  panel.fileTree.filterText = ""
  panel.promptLabel.hidden = true
  panel.filterField.hidden = true
  panel.closeFilterButton.hidden = true
  panel.setNeedsLayout()
  let owner = panel.window()
  if owner of nimkit.Window:
    discard nimkit.Window(owner).makeFirstResponder(panel.fileTree)

proc closeFileFilter(panel: KosmoFileBrowserPanel, sender: nimkit.DynamicAgent) =
  discard sender
  panel.dismissFilter()

protocol KosmoFileFilterFieldCellEditing of nimkit.CellEditingProtocol:
  method fieldEditorForView(
      cell: KosmoFileFilterFieldCell, controlView: nimkit.View
  ): nimkit.FieldEditor =
    discard controlView
    cell.editor

protocol KosmoFileFilterPromptHitTesting of nimkit.ViewProtocol:
  method pointInside(label: KosmoFileFilterPromptLabel, point: nimkit.Point): bool =
    discard label
    discard point
    false

protocol KosmoFileFilterEditorCancellation of nimkit.MenuCommandProtocol:
  method cancelOperation(editor: KosmoFileFilterFieldEditor, args: nimkit.ActionArgs) =
    discard args
    if not editor.panel.isNil:
      editor.panel[].dismissFilter()

protocol KosmoFileFilterEditorKeyEquivalents of nimkit.ResponderCommandDispatchProtocol:
  method performKeyEquivalent(
      editor: KosmoFileFilterFieldEditor, event: nimkit.KeyEvent
  ): bool =
    if event.key == nimkit.keyF and event.modifiers == nimkit.shortcutModifiers() and
        not editor.panel.isNil:
      return editor.panel[].showFilter()

protocol KosmoFileBrowserPanelCommands of nimkit.ResponderCommandDispatchProtocol:
  method performKeyEquivalent(
      panel: KosmoFileBrowserPanel, event: nimkit.KeyEvent
  ): bool =
    if event.key == nimkit.keyF and event.modifiers == nimkit.shortcutModifiers():
      return panel.showFilter()
    if event.modifiers == {nimkit.kmShift} and panel.window() of nimkit.Window and
        nimkit.Window(panel.window()).firstResponder == panel.fileTree:
      case event.key
      of nimkit.keyE:
        panel.fileTree.toggleTreeExpansion()
      of nimkit.keyH:
        panel.selectScope(
          if panel.fileTree.displayMode() == FileTreeDisplayMode.AllFiles:
            FileTreeDisplayMode.VisibleFiles
          else:
            FileTreeDisplayMode.AllFiles
        )
      of nimkit.keyG:
        panel.selectScope(FileTreeDisplayMode.SourceControlChanges)
      of nimkit.keyF:
        panel.selectScope(FileTreeDisplayMode.VisibleFiles)
      of nimkit.keyA:
        panel.selectScope(FileTreeDisplayMode.AllFiles)
      else:
        return
      return true

protocol KosmoFileBrowserPanelMenuCommands of nimkit.MenuCommandProtocol:
  method cancelOperation(panel: KosmoFileBrowserPanel, args: nimkit.ActionArgs) =
    discard args
    if not panel.filterField.hidden():
      panel.dismissFilter()

protocol KosmoFileBrowserPanelLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(panel: KosmoFileBrowserPanel) =
    let
      bounds = panel.bounds()
      searchHeight =
        if panel.filterField.hidden:
          0.0'f32
        else:
          min(FileBrowserControlRowHeight, bounds.size.height)
      scopeHeight = min(
        FileBrowserControlRowHeight, max(bounds.size.height - searchHeight, 0.0'f32)
      )
      treeHeight = max(bounds.size.height - searchHeight - scopeHeight, 0.0'f32)
      contentWidth = max(bounds.size.width - FileBrowserControlInset * 2.0'f32, 0.0'f32)
      closeWidth = min(FileBrowserControlHeight, contentWidth)
      filterWidth = max(contentWidth - closeWidth - 6.0'f32, 0.0'f32)
    panel.fileTree.setFrameFromLayout(
      nimkit.rect(0.0'f32, searchHeight, bounds.size.width, treeHeight)
    )
    panel.filterField.setFrameFromLayout(
      nimkit.rect(
        FileBrowserControlInset,
        FileBrowserControlInset,
        filterWidth,
        min(FileBrowserControlHeight, searchHeight),
      )
    )
    panel.promptLabel.setFrameFromLayout(
      nimkit.rect(
        FileBrowserControlInset + 10.0'f32,
        FileBrowserControlInset,
        max(filterWidth - 20.0'f32, 0.0'f32),
        min(FileBrowserControlHeight, searchHeight),
      )
    )
    panel.closeFilterButton.setFrameFromLayout(
      nimkit.rect(
        FileBrowserControlInset + filterWidth + 6.0'f32,
        FileBrowserControlInset,
        closeWidth,
        min(FileBrowserControlHeight, searchHeight),
      )
    )
    panel.scopeButton.setFrameFromLayout(
      nimkit.rect(
        FileBrowserControlInset,
        searchHeight + treeHeight + FileBrowserControlInset,
        contentWidth,
        min(FileBrowserControlHeight, scopeHeight),
      )
    )

proc newKosmoFileTree*(
    rootPath = "", frame: nimkit.Rect = nimkit.AutoRect
): KosmoFileTree =
  result = KosmoFileTree()
  result.initOutlineViewFields(frame)
  result.xFileSystem = nimkit.initFileSystemBrowserModel()
  result.xGitFileStates = initTable[string, nimkit.GitFileState]()
  result.xGitDescendantStates = initTable[string, nimkit.GitFileState]()
  result.xGitChildren = initTable[string, seq[string]]()
  result.xVisibleChildren = initTable[string, seq[string]]()
  result.xMatchingPaths = initHashSet[string]()
  discard result.withProtocol(KosmoFileTreeDataSource)
  discard result.withProtocol(KosmoFileTreeTableDelegate)
  discard nimkit.DynamicAgent(result).pushMethods(KosmoFileTreeEvents.init())
  result.outlineDataSource = result
  result.outlineColumn().title = "Files"
  result.outlineColumn().width = 260.0'f32
  result.outlineColumn().sizingPolicy = nimkit.tcspFlexible
  result.columnSizing = nimkit.tvcsFill
  result.showsHeader = false
  result.rowHeight = 24.0'f32
  result.selectionMode = nimkit.tsmSingle
  result.usesAlternatingRowBackgrounds = false
  result.showsRowSeparators = false
  result.connect(nimkit.rowWasActivated, result, fileTreeRowWasActivated)
  result.rootPath = rootPath

proc newKosmoFileBrowserPanel*(tree: KosmoFileTree): KosmoFileBrowserPanel =
  ## Wrap a file tree with live filtering and a persistent display-scope popup.
  let
    filterField = nimkit.newTextField()
    scopeMenu = nimkit.newMenu("Files Shown")
    scopeButton =
      nimkit.newPopupMenuButton(FileTreeDisplayMode.AllFiles.title(), scopeMenu)
    closeFilterButton = nimkit.newButton("×")
    promptLabel = KosmoFileFilterPromptLabel()
  promptLabel.initLabelFields("Filter Files")
  discard promptLabel.withProtocol(KosmoFileFilterPromptHitTesting)
  result = KosmoFileBrowserPanel(
    fileTree: tree,
    filterField: filterField,
    scopeButton: scopeButton,
    closeFilterButton: closeFilterButton,
    promptLabel: promptLabel,
  )
  result.initViewFields()
  result.clipsToBounds = true

  let
    panel = result.unsafeWeakRef()
    editor = KosmoFileFilterFieldEditor(panel: panel)
  editor.initFieldEditorFields()
  discard editor.withProtocol(KosmoFileFilterEditorCancellation)
  discard editor.withProtocol(KosmoFileFilterEditorKeyEquivalents)
  let cell = KosmoFileFilterFieldCell(editor: editor)
  cell.initTextFieldCellFields()
  discard cell.withProtocol(KosmoFileFilterFieldCellEditing)
  filterField.setCell(cell)

  result.addSubview(tree)
  result.addSubview(filterField)
  result.addSubview(promptLabel)
  result.addSubview(closeFilterButton)
  result.addSubview(scopeButton)
  discard result.withProtocol(KosmoFileBrowserPanelCommands)
  discard result.withProtocol(KosmoFileBrowserPanelMenuCommands)
  discard result.withProtocol(KosmoFileBrowserPanelLayout)

  let closeAction = nimkit.actionSelector(FileTreeCloseFilterAction)
  for mode in FileTreeDisplayMode:
    discard scopeMenu.addItem(newScopeMenuItem(panel, mode))
  closeFilterButton.target = nimkit.newActionTarget(closeAction) do(
    sender: nimkit.DynamicAgent
  ):
    if not panel.isNil:
      panel[].closeFileFilter(sender)
  closeFilterButton.action = closeAction
  closeFilterButton.accessibilityLabel = "Close file filter"
  closeFilterButton.toolTip = "Close file filter"
  filterField.accessibilityLabel = "Filter files"
  scopeButton.accessibilityLabel = "Files shown"
  filterField.hidden = true
  promptLabel.hidden = true
  closeFilterButton.hidden = true
  filterField.connect(nimkit.textDidChange, result, filterTextDidChange)
  result.syncScopeControl()
