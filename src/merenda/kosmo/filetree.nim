## A lazy filesystem tree for Kosmo frontends.

import std/[algorithm, os, strutils, tables]

import ../nimkit as nimkit

type
  FileTreeOpenHandler* = proc(path: string) {.closure.}

  KosmoFileTree* = ref object of nimkit.OutlineView
    xRootPath: string
    xChildren: Table[string, seq[string]]
    xOnOpenFile: FileTreeOpenHandler

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

proc childPaths(tree: KosmoFileTree, parentIdentifier: string): seq[string] =
  if parentIdentifier.len == 0:
    if tree.xRootPath.len > 0:
      return @[tree.xRootPath]
    return
  if not parentIdentifier.expandableDirectory():
    return
  if tree.xChildren.hasKey(parentIdentifier):
    return tree.xChildren[parentIdentifier]

  try:
    for kind, path in walkDir(parentIdentifier, relative = false):
      if kind in {pcFile, pcDir, pcLinkToFile, pcLinkToDir}:
        result.add path
    result.sort(compareTreePaths)
  except OSError:
    discard
  tree.xChildren[parentIdentifier] = result

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

proc fileTreeSelectionDidChange(
    tree: KosmoFileTree, sender: nimkit.DynamicAgent
) {.slot.} =
  if sender != nimkit.DynamicAgent(tree) or tree.xOnOpenFile.isNil:
    return
  let path = tree.selectedItemIdentifier()
  if fileExists(path):
    tree.xOnOpenFile(path)

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
  nimkit.TableView(tree).reloadData()

proc refresh*(tree: KosmoFileTree) =
  ## Discard cached directory listings and reload the visible hierarchy.
  tree.xChildren.clear()
  nimkit.TableView(tree).reloadData()

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
  result.outlineDataSource = result
  result.outlineColumn().title = "Files"
  result.outlineColumn().width = 260.0'f32
  result.showsHeader = false
  result.rowHeight = 24.0'f32
  result.selectionMode = nimkit.tsmSingle
  result.usesAlternatingRowBackgrounds = false
  result.showsRowSeparators = false
  result.connect(nimkit.selectionDidChange, result, fileTreeSelectionDidChange)
  result.rootPath = rootPath
