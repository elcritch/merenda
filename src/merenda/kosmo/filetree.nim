## A lazy filesystem tree for Kosmo frontends.

import std/[algorithm, options, os, strutils, tables]

import ../nimkit as nimkit

type
  FileTreeOpenDisposition* = enum
    fodPermanent
    fodTemporary

  FileTreeOpenHandler* =
    proc(path: string, disposition: FileTreeOpenDisposition) {.closure.}

  KosmoFileTree* = ref object of nimkit.OutlineView
    xRootPath: string
    xChildren: Table[string, seq[string]]
    xOnOpenFile: FileTreeOpenHandler
    xOpenDisposition: FileTreeOpenDisposition

func pathTitle(path: string): string =
  result = path.extractFilename()
  if result.len == 0:
    result = path

proc expandableDirectory(path: string): bool =
  dirExists(path) and not symlinkExists(path)

proc compareTreePaths(left, right: string): int =
  let
    leftDirectory = left.expandableDirectory()
    rightDirectory = right.expandableDirectory()
  if leftDirectory != rightDirectory:
    return if leftDirectory: -1 else: 1
  cmpIgnoreCase(left.pathTitle(), right.pathTitle())

proc loadChildPaths(tree: KosmoFileTree, parentIdentifier: string) =
  if tree.xChildren.hasKey(parentIdentifier):
    return
  var children: seq[string]
  if parentIdentifier.len == 0:
    if tree.xRootPath.len > 0:
      children.add tree.xRootPath
  elif parentIdentifier.expandableDirectory():
    try:
      for kind, path in walkDir(parentIdentifier, relative = false):
        if kind in {pcFile, pcDir, pcLinkToFile, pcLinkToDir}:
          children.add path
      children.sort(compareTreePaths)
    except OSError:
      discard
  tree.xChildren[parentIdentifier] = children

proc childPaths(tree: KosmoFileTree, parentIdentifier: string): lent seq[string] =
  tree.loadChildPaths(parentIdentifier)
  tree.xChildren[parentIdentifier]

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
    let expandable = identifier.expandableDirectory()
    nimkit.initOutlineItem(
      identifier,
      identifier.pathTitle(),
      parentIdentifier =
        if identifier == tree.xRootPath:
          ""
        else:
          identifier.parentDir(),
      expandable = expandable,
      leaf = not expandable,
      tooltip = identifier,
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
  tree.xRootPath

proc `rootPath=`*(tree: KosmoFileTree, path: string) =
  let next =
    if path.len > 0 and dirExists(path):
      absolutePath(path)
    else:
      ""
  if tree.xRootPath == next:
    return
  tree.xRootPath = next
  tree.xChildren.clear()
  let expanded =
    if next.len > 0:
      @[next]
    else:
      @[]
  tree.expandedItemIdentifiers = expanded
  tree.selectedItemIdentifier = ""
  tree.reloadOutlineData()

proc refresh*(tree: KosmoFileTree) =
  ## Discard cached directory listings and reload the visible hierarchy.
  tree.xChildren.clear()
  tree.reloadOutlineData()

proc onOpenFile*(tree: KosmoFileTree): FileTreeOpenHandler =
  tree.xOnOpenFile

proc `onOpenFile=`*(tree: KosmoFileTree, handler: FileTreeOpenHandler) =
  tree.xOnOpenFile = handler

proc newKosmoFileTree*(
    rootPath = "", frame: nimkit.Rect = nimkit.AutoRect
): KosmoFileTree =
  result = KosmoFileTree()
  result.initOutlineViewFields(frame)
  discard result.withProtocol(KosmoFileTreeDataSource)
  discard result.withProtocol(KosmoFileTreeTableDelegate)
  discard nimkit.DynamicAgent(result).pushMethods(KosmoFileTreeEvents.init())
  result.outlineDataSource = result
  result.outlineColumn().title = "Files"
  result.outlineColumn().width = 260.0'f32
  result.showsHeader = false
  result.rowHeight = 24.0'f32
  result.selectionMode = nimkit.tsmSingle
  result.usesAlternatingRowBackgrounds = false
  result.showsRowSeparators = false
  result.connect(nimkit.rowWasActivated, result, fileTreeRowWasActivated)
  result.rootPath = rootPath
