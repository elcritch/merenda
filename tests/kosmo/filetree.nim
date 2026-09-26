import std/[options, os, osproc, strutils, tempfiles, times, unicode, unittest]

import figdraw
import figdraw/debugtools

import merenda/nimkit
import merenda/nimkit/text/monotextviews as monoTextViews
import merenda/kosmo/kosmo

proc renderedText(node: Fig): string =
  for glyphIndex in 0 ..< node.textLayout.glyphCount():
    result.add node.textLayout.displayRune(glyphIndex)

proc renderedTextStartingWith(view: View, prefix: string): string =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText:
      let text = node.renderedText()
      if text.startsWith(prefix):
        return text

proc renderedTextFrameStartingWith(
    view: View, prefix: string
): typeof(default(Fig).screenBox) =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return
  for hit in renders[DefaultDrawLevel].collectDebugFigs():
    if hit.node.kind == nkText and hit.node.renderedText().startsWith(prefix):
      return hit.bounds

suite "Kosmo":
  test "file tree column follows its viewport and retruncates after resize":
    let
      root = createTempDir("merenda-kosmo-tree-resize-", "")
      longName = "a_very_long_filename_that_needs_live_truncation.nim"
      longPath = root / longName
    var paths = @[longPath]
    writeFile(longPath, "long")
    for index in 0 ..< 8:
      let path = root / ("short-" & $index & ".nim")
      writeFile(path, "short")
      paths.add path
    defer:
      for path in paths:
        removeFile(path)
      removeDir(root)

    let
      tree = newKosmoFileTree(root, frame = rect(0, 0, 340, 120))
      scrollView = tree.scrollView()
      wideTitle = tree.renderedTextStartingWith("a_very")
      wideTextFrame = tree.renderedTextFrameStartingWith("a_very")
      wideScrollerMinX =
        scrollView.frame().origin.x + scrollView.verticalScrollerRect().origin.x

    check not scrollView.verticalScrollerRect().isEmpty
    check scrollView.horizontalScrollerRect().isEmpty
    check wideTextFrame.x + wideTextFrame.w <= wideScrollerMinX + 1

    tree.frame = rect(0, 0, 190, 120)
    let
      narrowTitle = tree.renderedTextStartingWith("a_very")
      narrowTextFrame = tree.renderedTextFrameStartingWith("a_very")
      narrowScrollerMinX =
        scrollView.frame().origin.x + scrollView.verticalScrollerRect().origin.x

    check scrollView.horizontalScrollerRect().isEmpty
    check narrowTextFrame.x + narrowTextFrame.w <= narrowScrollerMinX + 1
    check narrowTitle != wideTitle
    check narrowTitle.endsWith("…")

  test "file tree lazily exposes folders before files":
    let
      root = createTempDir("merenda-kosmo-tree-", "")
      folder = root / "folder"
      nestedFile = folder / "nested.txt"
      rootFile = root / "root.txt"
    createDir(folder)
    writeFile(nestedFile, "nested")
    writeFile(rootFile, "root")
    defer:
      removeFile(nestedFile)
      removeFile(rootFile)
      removeDir(folder)
      removeDir(root)

    let tree = newKosmoFileTree(root)
    check tree.rootPath == absolutePath(root)
    require tree.rowForItem(folder) >= 0
    check tree.rowForItem(folder) < tree.rowForItem(rootFile)
    check tree.rowForItem(nestedFile) < 0
    check tree.outlineItemWithIdentifier(rootFile).leaf

    tree.expandItem(folder)
    check tree.rowForItem(nestedFile) > tree.rowForItem(folder)
    check tree.outlineItemWithIdentifier(nestedFile).leaf

  test "file tree appends ordered top-level folders":
    let
      workspace = createTempDir("merenda-kosmo-tree-roots-", "")
      firstRoot = workspace / "first"
      secondRoot = workspace / "second"
    createDir(firstRoot)
    createDir(secondRoot)
    defer:
      removeDir(secondRoot)
      removeDir(firstRoot)
      removeDir(workspace)

    let tree = newKosmoFileTree(firstRoot)
    check tree.rootPaths == @[absolutePath(firstRoot)]
    check tree.addRootPath(secondRoot)
    check tree.rootPaths == @[absolutePath(firstRoot), absolutePath(secondRoot)]
    check tree.outlineItemWithIdentifier(firstRoot).parentIdentifier.len == 0
    check tree.outlineItemWithIdentifier(secondRoot).parentIdentifier.len == 0
    check not tree.addRootPath(secondRoot)

    tree.rootPath = firstRoot
    check tree.rootPaths == @[absolutePath(firstRoot)]

  test "file tree exposes Git file badges and descendant folder colors":
    let
      root = createTempDir("merenda-kosmo-tree-git-", "")
      folder = root / "folder"
      nestedFile = folder / "nested.nim"
      gitDirectory = root / ".git"
      githubFolder = root / ".github"
      githubFile = githubFolder / "workflow.yml"
      ignoredFolder = root / "ignored-cache"
      ignoredNestedFile = ignoredFolder / "cached.bin"
      untrackedFile = root / "notes.txt"
      ignoredFile = root / "ignored.log"
      tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 140))
    createDir(folder)
    createDir(gitDirectory)
    createDir(githubFolder)
    createDir(ignoredFolder)
    writeFile(nestedFile, "let nested = true\n")
    writeFile(githubFile, "name: checks\n")
    writeFile(ignoredNestedFile, "cached\n")
    writeFile(untrackedFile, "notes\n")
    writeFile(ignoredFile, "ignored\n")
    defer:
      removeFile(nestedFile)
      removeFile(githubFile)
      removeFile(ignoredNestedFile)
      removeFile(untrackedFile)
      removeFile(ignoredFile)
      removeDir(folder)
      removeDir(gitDirectory)
      removeDir(githubFolder)
      removeDir(ignoredFolder)
      removeDir(root)

    tree.applyGitStatus(
      GitStatusSnapshot(
        rootPath: absolutePath(root),
        isRepository: true,
        entries:
          @[
            GitStatusEntry(path: nestedFile, state: gfsModified),
            GitStatusEntry(path: untrackedFile, state: gfsUntracked),
            GitStatusEntry(path: gitDirectory, state: gfsIgnored),
            GitStatusEntry(path: ignoredFile, state: gfsIgnored),
            GitStatusEntry(path: ignoredFolder, state: gfsIgnored),
          ],
      )
    )
    tree.displayMode = FileTreeDisplayMode.AllFiles
    tree.expandItem(folder)
    tree.expandItem(githubFolder)
    tree.expandItem(ignoredFolder)

    let
      modifiedDecoration = tree.outlineItemWithIdentifier(nestedFile).decoration
      untrackedDecoration = tree.outlineItemWithIdentifier(untrackedFile).decoration
      gitItem = tree.outlineItemWithIdentifier(gitDirectory)
      githubItem = tree.outlineItemWithIdentifier(githubFolder)
      githubFileItem = tree.outlineItemWithIdentifier(githubFile)
      ignoredItem = tree.outlineItemWithIdentifier(ignoredFile)
      ignoredNestedItem = tree.outlineItemWithIdentifier(ignoredNestedFile)
      folderItem = tree.outlineItemWithIdentifier(folder)
    check modifiedDecoration.badge == "M"
    require modifiedDecoration.color.isSome
    check modifiedDecoration.badgePlacement == oibpLeading
    check untrackedDecoration.badge == "U"
    require untrackedDecoration.color.isSome
    check untrackedDecoration.color != modifiedDecoration.color
    check untrackedDecoration.badgePlacement == oibpLeading
    let ignoredColor = ignoredItem.decoration.color
    require ignoredColor.isSome
    check ignoredColor != modifiedDecoration.color
    check gitItem.decoration.color == ignoredColor
    check gitItem.tooltip.endsWith("Ignored")
    check githubItem.decoration.color == ignoredColor
    check githubItem.tooltip.endsWith("Ignored")
    check githubFileItem.decoration.color == ignoredColor
    check githubFileItem.tooltip.endsWith("Ignored")
    check ignoredItem.decoration.badge.len == 0
    check ignoredItem.decoration.color == ignoredColor
    check ignoredItem.tooltip.endsWith("Ignored")
    check ignoredNestedItem.decoration.color == ignoredColor
    check ignoredNestedItem.tooltip.endsWith("Ignored")
    check folderItem.decoration.badge.len == 0
    check folderItem.decoration.color == modifiedDecoration.color
    check folderItem.tooltip.endsWith("Contains modified files")

  test "file tree displays Git status after a background refresh":
    let root = createTempDir("merenda-kosmo-tree-git-worker-", "")
    discard execProcess(
      "git",
      workingDir = root,
      args = ["init", "-q"],
      options = {poUsePath, poStdErrToStdOut},
    )
    let untrackedFile = root / "worker-result.txt"
    writeFile(untrackedFile, "worker result\n")
    let tree = newKosmoFileTree(root)
    discard tree.startGitStatusMonitoring(refreshInterval = initDuration())
    defer:
      tree.stopGitStatusMonitoring()
      removeDir(root)

    check tree.waitForGitStatus(timeoutMilliseconds = 10_000)
    check tree.outlineItemWithIdentifier(untrackedFile).decoration.badge == "U"

  test "file tree activates files without entering inline editing":
    let
      root = createTempDir("merenda-kosmo-tree-activation-", "")
      filePath = root / "document.txt"
    writeFile(filePath, "document body")
    let
      window = newWindow("Kosmo File Tree Activation", frame = rect(0, 0, 300, 120))
      tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 120))
    defer:
      removeFile(filePath)
      removeDir(root)

    var openRequests: seq[tuple[path: string, disposition: FileTreeOpenDisposition]]
    tree.onOpenFile = proc(path: string, disposition: FileTreeOpenDisposition) =
      openRequests.add (path, disposition)
    window.setContentView(tree)
    discard buildRenders(tree)

    let
      row = tree.rowForItem(filePath)
      rowRect = tree.rowItemRect(row)
      point = tree.pointToWindow(
        initPoint(
          rowRect.origin.x + rowRect.size.width * 0.5'f32,
          rowRect.origin.y + rowRect.size.height * 0.5'f32,
        )
      )
    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check not tree.editingState.active
    check openRequests == @[(filePath, fodTemporary)]

    check window.mouseDownAt(point, clickCount = 2)
    check window.mouseUpAt(point, clickCount = 2)
    check not tree.editingState.active
    check openRequests == @[(filePath, fodTemporary), (filePath, fodPermanent)]

    openRequests.setLen(0)
    check tree.keyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check not tree.editingState.active
    check openRequests == @[(filePath, fodPermanent)]

  test "double clicking a file tree folder toggles it":
    let
      root = createTempDir("merenda-kosmo-tree-folder-", "")
      folder = root / "folder"
      nestedFile = folder / "nested.txt"
    createDir(folder)
    writeFile(nestedFile, "nested")
    let
      window = newWindow("Kosmo Folder Activation", frame = rect(0, 0, 300, 120))
      tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 120))
    defer:
      removeFile(nestedFile)
      removeDir(folder)
      removeDir(root)

    window.setContentView(tree)
    discard buildRenders(tree)
    let
      rowRect = tree.rowItemRect(tree.rowForItem(folder))
      point = tree.pointToWindow(
        initPoint(
          rowRect.origin.x + rowRect.size.width * 0.5'f32,
          rowRect.origin.y + rowRect.size.height * 0.5'f32,
        )
      )

    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check not tree.isItemExpanded(folder)

    check window.mouseDownAt(point, clickCount = 2)
    check window.mouseUpAt(point, clickCount = 2)
    check tree.isItemExpanded(folder)
    check tree.rowForItem(nestedFile) >= 0

    check window.mouseDownAt(point, clickCount = 2)
    check window.mouseUpAt(point, clickCount = 2)
    check not tree.isItemExpanded(folder)
    check tree.rowForItem(nestedFile) < 0

  test "opening files preserves roots and opening folders appends them":
    let
      root = createTempDir("merenda-kosmo-open-path-", "")
      folder = root / "folder"
      secondFolder = root / "second-folder"
      filePath = root / "document.txt"
    createDir(folder)
    createDir(secondFolder)
    writeFile(filePath, "document body")
    defer:
      removeFile(filePath)
      removeDir(secondFolder)
      removeDir(folder)
      removeDir(root)

    let
      frontend = newKosmoApplication(newApplication("Kosmo Open Path Test"))
      initialRoot = frontend.fileTree.rootPath
      initialRootName = initialRoot.fileBrowserDisplayName()
    check frontend.window.title == "Kosmo (" & initialRootName & ")"
    check frontend.openPath(filePath)
    check frontend.fileTree.rootPaths == @[initialRoot]

    check frontend.openPath(folder)
    check frontend.fileTree.rootPaths == @[initialRoot, absolutePath(folder)]
    check frontend.window.title == "Kosmo (" & initialRootName & " + 1)"

    check frontend.openPath(secondFolder)
    check frontend.fileTree.rootPaths ==
      @[initialRoot, absolutePath(folder), absolutePath(secondFolder)]
    check frontend.window.title == "Kosmo (" & initialRootName & " + 2)"
    frontend.close()

  test "opening a project creates a new window with its own file browser":
    let
      folder = createTempDir("merenda-kosmo-project-window-", "")
      app = newApplication("Kosmo Project Window Test")
      manager = newKosmoWindowManager(app)
    defer:
      removeDir(folder)

    let frontend = manager.openProject(folder)
    require not frontend.isNil
    check frontend.hasFileBrowser()
    check frontend.fileTree.rootPaths == @[absolutePath(folder)]
    check frontend.window.title == "Kosmo (" & folder.fileBrowserDisplayName() & ")"
    check not frontend.sidebarPane.isHidden
    check not frontend.fileTree.bounds().isEmpty
    check manager.managedWindows() == @[frontend]
    check frontend.window in app.windows()

    frontend.window.close()
    check manager.managedWindows().len == 0

  test "opening a file without a window creates a browserless window":
    let
      folder = createTempDir("merenda-kosmo-file-window-", "")
      filePath = folder / "document.txt"
      app = newApplication("Kosmo File Window Test")
      manager = newKosmoWindowManager(app)
    writeFile(filePath, "document body")
    defer:
      removeFile(filePath)
      removeDir(folder)

    check manager.openPath(filePath)
    let windows = manager.managedWindows()
    require windows.len == 1
    let frontend = windows[0]
    check not frontend.hasFileBrowser()
    check frontend.fileTree.rootPaths.len == 0
    check frontend.window.title == "Kosmo"
    check frontend.editorView.editor.tabs()[0].filePath == some(filePath)
    check not frontend.showFileExplorer()
    check frontend.window in app.windows()

    frontend.window.close()
    check manager.managedWindows().len == 0

  test "open panel action buttons keep their natural height":
    let panel = newOpenPanel()
    let folder = createTempDir("merenda-kosmo-panel-folder-", "")
    defer:
      removeDir(folder)
    panel.canChooseDirectories = true
    panel.selectUrl(folder)
    let content = panel.contentView()
    content.layoutSubtreeIfNeeded()
    let button = Button(panel.buttonViews[0])

    check panel.validateSelection()
    check button.frame().size.height == button.sizeThatFits().height
    check button.frame().size.height < content.bounds().size.height / 2.0'f32
