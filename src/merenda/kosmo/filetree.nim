## A lazy filesystem tree for Kosmo frontends.

import std/[options, os, strutils, tables, times]

import ../nimkit as nimkit

type
  FileTreeOpenDisposition* = enum
    fodPermanent
    fodTemporary

  FileTreeOpenHandler* =
    proc(path: string, disposition: FileTreeOpenDisposition) {.closure.}

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

const
  GitModifiedColor = nimkit.color(0.82, 0.62, 0.20, 1.0)
  GitAddedColor = nimkit.color(0.32, 0.72, 0.40, 1.0)
  GitDeletedColor = nimkit.color(0.90, 0.32, 0.32, 1.0)
  GitRenamedColor = nimkit.color(0.32, 0.64, 0.88, 1.0)
  GitConflictedColor = nimkit.color(0.94, 0.30, 0.36, 1.0)
  GitIgnoredColor = nimkit.color(0.50, 0.52, 0.56, 0.72)

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

proc childPaths(tree: KosmoFileTree, parentIdentifier: string): lent seq[string] =
  tree.loadChildPaths(parentIdentifier)
  tree.xChildren[parentIdentifier]

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
    tree.childPaths(parentIdentifier).len

  method childIdentifier(
      tree: KosmoFileTree,
      outlineView: nimkit.OutlineView,
      parentIdentifier: string,
      index: int,
  ): string =
    discard outlineView
    let children = tree.childPaths(parentIdentifier)
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
      expandable = identifier.expandableDirectory()
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
  if path.expandableDirectory():
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

proc reloadRoots(tree: KosmoFileTree, expanded: seq[string]) =
  tree.xFileSystem.invalidate()
  tree.xChildren.clear()
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
  tree.reloadOutlineData()

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
  tree.reloadOutlineData()

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

proc newKosmoFileTree*(
    rootPath = "", frame: nimkit.Rect = nimkit.AutoRect
): KosmoFileTree =
  result = KosmoFileTree()
  result.initOutlineViewFields(frame)
  result.xFileSystem = nimkit.initFileSystemBrowserModel()
  result.xGitFileStates = initTable[string, nimkit.GitFileState]()
  result.xGitDescendantStates = initTable[string, nimkit.GitFileState]()
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
