import
  std/[monotimes, options, os, osproc, strutils, tempfiles, times, unicode, unittest]

import figdraw
import sigils/threads

import merenda/nimkit
import merenda/nimkit/text/monotextviews as monoTextViews
import merenda/kosmo/kosmo

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add rune

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
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText and node.renderedText().startsWith(prefix):
      return node.screenBox

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
      wideColumnWidth = tree.outlineColumn().width()
      wideScrollerMinX =
        scrollView.frame().origin.x + scrollView.verticalScrollerRect().origin.x

    check not scrollView.verticalScrollerRect().isEmpty
    check scrollView.horizontalScrollerRect().isEmpty
    check abs(wideColumnWidth - scrollView.viewportSize().width) < 0.01'f32
    check abs(wideTextFrame.x + wideTextFrame.w - wideScrollerMinX) < 0.01'f32

    tree.frame = rect(0, 0, 190, 120)
    let
      narrowTitle = tree.renderedTextStartingWith("a_very")
      narrowTextFrame = tree.renderedTextFrameStartingWith("a_very")
      narrowScrollerMinX =
        scrollView.frame().origin.x + scrollView.verticalScrollerRect().origin.x

    check scrollView.horizontalScrollerRect().isEmpty
    check tree.outlineColumn().width() < wideColumnWidth
    check abs(tree.outlineColumn().width() - scrollView.viewportSize().width) < 0.01'f32
    check abs(narrowTextFrame.x + narrowTextFrame.w - narrowScrollerMinX) < 0.01'f32
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
    check tree.rowCount() == 3
    check tree.itemAtRow(1).identifier == folder
    check tree.outlineItemWithIdentifier(rootFile).leaf

    tree.expandItem(folder)
    check tree.rowCount() == 4
    check tree.outlineItemWithIdentifier(nestedFile).leaf

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
      modifiedColor = color(0.82, 0.62, 0.20, 1.0)
      addedColor = color(0.32, 0.72, 0.40, 1.0)
      ignoredColor = color(0.50, 0.52, 0.56, 0.72)
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
    check modifiedDecoration.color == some(modifiedColor)
    check untrackedDecoration.badge == "U"
    check untrackedDecoration.color == some(addedColor)
    check gitItem.decoration.color == some(ignoredColor)
    check gitItem.tooltip.endsWith("Ignored")
    check githubItem.decoration.color == some(ignoredColor)
    check githubItem.tooltip.endsWith("Ignored")
    check githubFileItem.decoration.color == some(ignoredColor)
    check githubFileItem.tooltip.endsWith("Ignored")
    check ignoredItem.decoration.badge.len == 0
    check ignoredItem.decoration.color == some(ignoredColor)
    check ignoredItem.tooltip.endsWith("Ignored")
    check ignoredNestedItem.decoration.color == some(ignoredColor)
    check ignoredNestedItem.tooltip.endsWith("Ignored")
    check folderItem.decoration.badge.len == 0
    check folderItem.decoration.color == some(modifiedColor)
    check folderItem.tooltip.endsWith("Contains modified files")

  test "file tree receives Git status from its Sigils worker":
    let root = createTempDir("merenda-kosmo-tree-git-worker-", "")
    discard execProcess(
      "git",
      workingDir = root,
      args = ["init", "-q"],
      options = {poUsePath, poStdErrToStdOut},
    )
    let untrackedFile = root / "worker-result.txt"
    writeFile(untrackedFile, "worker result\n")
    let
      tree = newKosmoFileTree(root)
      service = tree.startGitStatusMonitoring(refreshInterval = initDuration())
    defer:
      tree.stopGitStatusMonitoring()
      removeDir(root)

    check tree.waitForGitStatus(timeoutMilliseconds = 10_000)
    check service.lastSnapshot().workerThreadId != getThreadId()
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

  test "opening files and folders updates the file-tree root":
    let
      root = createTempDir("merenda-kosmo-open-path-", "")
      folder = root / "folder"
      filePath = root / "document.txt"
    createDir(folder)
    writeFile(filePath, "document body")
    defer:
      removeFile(filePath)
      removeDir(folder)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Open Path Test"))
    check frontend.openPath(filePath)
    check frontend.fileTree.rootPath == absolutePath(root)

    check frontend.openPath(folder)
    check frontend.fileTree.rootPath == absolutePath(folder)
    frontend.close()

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
