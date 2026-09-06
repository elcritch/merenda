import std/[os, strutils, tempfiles, unicode, unittest]

import figdraw

import merenda/nimkit
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

proc rendersFill(view: View, fillValue: Fill): bool =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkRectangle and node.fill == fillValue:
      return true

proc rendersTextWithColor(view: View, text: string, textColor: Color): bool =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText and node.renderedText() == text:
      for spanColor in node.textLayout.spanColors:
        if spanColor.kind == flColor and spanColor.color == textColor.rgba:
          return true

suite "Kosmo file tree interactions":
  test "display shortcuts are scoped to the focused file tree":
    let root = createTempDir("kosmo-browser-shortcuts-", "")
    createDir(root / "folder" / "nested")
    writeFile(root / "folder" / "nested" / "file.txt", "test")
    let
      tree = newKosmoFileTree(root)
      panel = newKosmoFileBrowserPanel(tree)
      window = newWindow("Browser shortcuts", rect(0, 0, 300, 400))
    defer:
      window.close()
      removeDir(root)
    window.setContentView(panel)
    panel.layoutSubtreeIfNeeded()
    require window.makeFirstResponder(tree)
    for (key, expected) in [
      (keyF, FileTreeDisplayMode.VisibleFiles),
      (keyH, FileTreeDisplayMode.AllFiles),
      (keyH, FileTreeDisplayMode.VisibleFiles),
      (keyG, FileTreeDisplayMode.SourceControlChanges),
      (keyH, FileTreeDisplayMode.AllFiles),
      (keyG, FileTreeDisplayMode.SourceControlChanges),
      (keyA, FileTreeDisplayMode.AllFiles),
    ]:
      check window.dispatchKeyDown(
        KeyEvent(key: key, keyCode: key.ord, modifiers: {kmShift})
      )
      check tree.displayMode == expected
      check panel.scopeButton.title == expected.title()
      check panel.scopeButton.menu()[expected.ord].state == bsOn
    let expandKey = KeyEvent(key: keyE, keyCode: keyE.ord, modifiers: {kmShift})
    check window.dispatchKeyDown(expandKey)
    check tree.isItemExpanded(root)
    check tree.isItemExpanded(root / "folder")
    check tree.isItemExpanded(root / "folder" / "nested")
    check tree.rowForItem(root / "folder" / "nested" / "file.txt") >= 0
    check window.dispatchKeyDown(expandKey)
    check tree.expandedItemIdentifiers().len == 0
    check window.dispatchKeyDown(expandKey)
    check tree.isItemExpanded(root / "folder" / "nested")
    require panel.showFilter()
    for key in [keyH, keyG, keyF, keyA, keyE]:
      check not panel.performKeyEquivalent(
        KeyEvent(key: key, keyCode: key.ord, modifiers: {kmShift})
      )
      check tree.displayMode == FileTreeDisplayMode.AllFiles
      check tree.isItemExpanded(root / "folder" / "nested")
    panel.dismissFilter()
    let other = newTextField()
    panel.addSubview(other)
    require window.makeFirstResponder(other)
    check not panel.performKeyEquivalent(
      KeyEvent(key: keyG, keyCode: keyG.ord, modifiers: {kmShift})
    )
    check tree.displayMode == FileTreeDisplayMode.AllFiles

  test "Git status refresh redraws retained file rows":
    let
      root = createTempDir("merenda-kosmo-tree-git-redraw-", "")
      ignoredPath = root / "ignored.log"
      ignoredColor = color(0.50, 0.52, 0.56, 0.72)
    writeFile(ignoredPath, "ignored")
    let tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 120))
    defer:
      removeFile(ignoredPath)
      removeDir(root)

    discard buildRenders(tree)
    check not tree.rendersTextWithColor("ignored.log", ignoredColor)

    tree.applyGitStatus(
      GitStatusSnapshot(
        rootPath: absolutePath(root),
        isRepository: true,
        entries: @[GitStatusEntry(path: ignoredPath, state: gfsIgnored)],
      )
    )

    check tree.rendersTextWithColor("ignored.log", ignoredColor)

  test "hover input redraws the highlighted row":
    let
      root = createTempDir("merenda-kosmo-tree-hover-", "")
      filePath = root / "hover-target.txt"
    writeFile(filePath, "hover target")
    defer:
      removeFile(filePath)
      removeDir(root)

    let
      window = newWindow("Kosmo File Tree Hover", frame = rect(0, 0, 300, 120))
      tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 120))
      hoverFill = fill(color(0.91, 0.23, 0.67, 1.0))
    var appearance = initAppearance()
    appearance[srRowItem, {ssHovered}, StyleFill] = hoverFill
    tree.appearance = appearance
    window.setContentView(tree)
    discard buildRenders(tree)

    let
      row = tree.rowForItem(filePath)
      rowRect = tree.rowItemRect(row)
      point = tree.pointToWindow(
        initPoint(rowRect.origin.x + 40.0'f32, rowRect.origin.y + 12.0'f32)
      )
    check not tree.rendersFill(hoverFill)
    check window.mouseMovedAt(point)
    check tree.highlightedIndex() == row
    check tree.rendersFill(hoverFill)

  test "wheel input lazily renders newly visible rows":
    let root = createTempDir("merenda-kosmo-tree-scroll-", "")
    var paths: seq[string]
    for index in 0 ..< 12:
      let path = root / align($index, 2, '0') & "-row.txt"
      writeFile(path, "row " & $index)
      paths.add path
    defer:
      for path in paths:
        removeFile(path)
      removeDir(root)

    let
      window = newWindow("Kosmo File Tree Scroll", frame = rect(0, 0, 300, 74))
      tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 74))
    window.setContentView(tree)

    check tree.renderedTextStartingWith("00-row") == "00-row.txt"
    check window.scrollWheelAt(
      tree.pointToWindow(initPoint(40.0'f32, 40.0'f32)), deltaY = -3.0'f32
    )
    check tree.firstVisibleIndex() == 3
    check tree.renderedTextStartingWith("02-row") == "02-row.txt"
    check tree.renderedTextStartingWith("00-row").len == 0

  test "display scopes retain folders leading to visible and changed files":
    let
      root = createTempDir("merenda-kosmo-tree-scope-", "")
      folder = root / "source"
      hiddenFolder = root / ".cache"
      visibleFile = root / "README.md"
      hiddenFile = root / ".env"
      changedFile = folder / "changed.nim"
      hiddenNestedFile = hiddenFolder / "generated.txt"
      removedFolder = root / "removed"
      deletedFile = removedFolder / "old.nim"
      unicodeDeletedFile = removedFolder / "École.nim"
    createDir(folder)
    createDir(hiddenFolder)
    writeFile(visibleFile, "visible")
    writeFile(hiddenFile, "hidden")
    writeFile(changedFile, "changed")
    writeFile(hiddenNestedFile, "hidden nested")
    defer:
      removeFile(visibleFile)
      removeFile(hiddenFile)
      removeFile(changedFile)
      removeFile(hiddenNestedFile)
      removeDir(folder)
      removeDir(hiddenFolder)
      removeDir(root)

    let tree = newKosmoFileTree(root)
    check tree.displayMode == FileTreeDisplayMode.AllFiles
    check tree.rowForItem(hiddenFile) >= 0
    check tree.rowForItem(hiddenFolder) >= 0

    tree.displayMode = FileTreeDisplayMode.VisibleFiles
    check tree.rowForItem(visibleFile) >= 0
    check tree.rowForItem(hiddenFile) < 0
    check tree.rowForItem(hiddenFolder) < 0

    tree.applyGitStatus(
      GitStatusSnapshot(
        rootPath: absolutePath(root),
        isRepository: true,
        entries:
          @[
            GitStatusEntry(path: changedFile, state: gfsModified),
            GitStatusEntry(path: deletedFile, state: gfsDeleted),
            GitStatusEntry(path: unicodeDeletedFile, state: gfsDeleted),
          ],
      )
    )
    tree.displayMode = FileTreeDisplayMode.SourceControlChanges
    check tree.rowForItem(visibleFile) < 0
    check tree.rowForItem(folder) >= 0
    check tree.rowForItem(removedFolder) >= 0
    tree.expandItem(folder)
    tree.expandItem(removedFolder)
    check tree.rowForItem(changedFile) >= 0
    check tree.rowForItem(deletedFile) >= 0
    check tree.outlineItemWithIdentifier(deletedFile).decoration.badge == "D"
    tree.filterText = "éCOLE"
    check tree.rowForItem(removedFolder) >= 0
    check tree.rowForItem(unicodeDeletedFile) >= 0
    check tree.rowForItem(deletedFile) < 0
    tree.filterText = ""

  test "double clicking a deleted ancestor folder toggles it":
    let
      root = createTempDir("merenda-kosmo-tree-deleted-folder-", "")
      removedFolder = root / "removed"
      deletedFile = removedFolder / "old.nim"
      window = newWindow("Kosmo Deleted Folder", frame = rect(0, 0, 300, 120))
      tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 120))
    defer:
      window.close()
      removeDir(root)

    tree.applyGitStatus(
      GitStatusSnapshot(
        rootPath: absolutePath(root),
        isRepository: true,
        entries: @[GitStatusEntry(path: deletedFile, state: gfsDeleted)],
      )
    )
    tree.displayMode = FileTreeDisplayMode.SourceControlChanges
    window.setContentView(tree)
    let
      rowRect = tree.rowItemRect(tree.rowForItem(removedFolder))
      point = tree.pointToWindow(
        initPoint(
          rowRect.origin.x + rowRect.size.width * 0.5'f32,
          rowRect.origin.y + rowRect.size.height * 0.5'f32,
        )
      )
    check window.mouseDownAt(point, clickCount = 2)
    check window.mouseUpAt(point, clickCount = 2)
    check tree.isItemExpanded(removedFolder)
    check tree.rowForItem(deletedFile) >= 0

  test "changed-file filtering preserves every overlapping root hierarchy":
    let
      root = createTempDir("merenda-kosmo-tree-overlapping-roots-", "")
      nestedRoot = root / "source"
      changedFile = nestedRoot / "changed.nim"
    createDir(nestedRoot)
    writeFile(changedFile, "changed")
    defer:
      removeFile(changedFile)
      removeDir(nestedRoot)
      removeDir(root)

    let tree = newKosmoFileTree(root)
    check tree.addRootPath(nestedRoot)
    tree.applyGitStatus(
      GitStatusSnapshot(
        rootPath: absolutePath(root),
        isRepository: true,
        entries: @[GitStatusEntry(path: changedFile, state: gfsModified)],
      )
    )
    tree.displayMode = FileTreeDisplayMode.SourceControlChanges
    tree.filterText = "changed"

    var
      nestedUnderOuter = false
      fileUnderOuter = false
    for row in 0 ..< tree.rowCount():
      let identifier = tree.itemIdentifierForRow(row)
      if identifier == nestedRoot and tree.levelForRow(row) == 1:
        nestedUnderOuter = true
      elif identifier == changedFile and tree.levelForRow(row) == 2:
        fileUnderOuter = true
    check nestedUnderOuter
    check fileUnderOuter

  test "live file filtering is case insensitive and restores expansion state":
    let
      root = createTempDir("merenda-kosmo-tree-filter-", "")
      folder = root / "source"
      hiddenFolder = root / ".cache"
      matchingFile = folder / "NeedleView.nim"
      otherFile = root / "other.txt"
      hiddenMatch = hiddenFolder / "needle-secret.txt"
    createDir(folder)
    createDir(hiddenFolder)
    writeFile(matchingFile, "match")
    writeFile(otherFile, "other")
    writeFile(hiddenMatch, "hidden match")
    defer:
      removeFile(matchingFile)
      removeFile(otherFile)
      removeFile(hiddenMatch)
      removeDir(folder)
      removeDir(hiddenFolder)
      removeDir(root)

    let tree = newKosmoFileTree(root)
    check not tree.isItemExpanded(folder)
    tree.filterText = "needLE"
    check tree.filterText == "needLE"
    check tree.isItemExpanded(folder)
    check tree.rowForItem(matchingFile) >= 0
    check tree.rowForItem(otherFile) < 0

    tree.displayMode = FileTreeDisplayMode.VisibleFiles
    check tree.rowForItem(matchingFile) >= 0
    check tree.rowForItem(hiddenFolder) < 0
    check tree.rowForItem(hiddenMatch) < 0

    tree.filterText = ""
    check not tree.isItemExpanded(folder)
    check tree.rowForItem(otherFile) >= 0

  test "file browser controls occupy expected rows and Cmd-F filters the tree":
    let
      root = createTempDir("merenda-kosmo-browser-controls-", "")
      matchingFile = root / "needle.txt"
      otherFile = root / "other.txt"
    writeFile(matchingFile, "match")
    writeFile(otherFile, "other")
    let
      tree = newKosmoFileTree(root)
      panel = newKosmoFileBrowserPanel(tree)
      window = newWindow("Kosmo File Browser Controls", rect(0, 0, 280, 320))
    defer:
      window.close()
      removeFile(matchingFile)
      removeFile(otherFile)
      removeDir(root)
    window.setContentView(panel)
    panel.layoutSubtreeIfNeeded()

    check panel.scopeButton.title == "All Files"
    check panel.scopeButton.menu().items().len == 3
    check panel.scopeButton.menu()[0].title == "All Files"
    check panel.scopeButton.menu()[1].title == "Visible Files"
    check panel.scopeButton.menu()[2].title == "Changed Files"
    check panel.scopeButton.menu()[0].state == bsOn
    check panel.scopeButton.frame().minY >= panel.fileTree.frame().maxY
    check panel.filterField.hidden

    require window.makeFirstResponder(tree)
    check window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: shortcutModifiers())
    )
    check not panel.filterField.hidden
    check window.fieldEditorClient() == panel.filterField
    check panel.filterField.frame().maxY <= panel.fileTree.frame().minY
    require window.makeFirstResponder(tree)
    let filterBounds = panel.filterField.bounds()
    let filterPoint = panel.filterField.pointToWindow(
      initPoint(
        filterBounds.origin.x + filterBounds.size.width * 0.5'f32,
        filterBounds.origin.y + filterBounds.size.height * 0.5'f32,
      )
    )
    check window.mouseDownAt(filterPoint)
    discard window.mouseUpAt(filterPoint)
    check window.fieldEditorClient() == panel.filterField
    check window.dispatchTextInput("needle")
    check tree.filterText == "needle"
    check tree.rowForItem(matchingFile) >= 0
    check tree.rowForItem(otherFile) < 0

    check window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
    check panel.filterField.hidden
    check tree.filterText.len == 0
    check window.firstResponder() == tree

    panel.scopeButton.popupPresentation = ppInline
    let scopeBounds = panel.scopeButton.bounds()
    check window.clickAt(
      panel.scopeButton.pointToWindow(
        initPoint(
          scopeBounds.origin.x + scopeBounds.size.width * 0.5'f32,
          scopeBounds.origin.y + scopeBounds.size.height * 0.5'f32,
        )
      )
    )
    check panel.scopeButton.popupOpen()
    require panel.subviews()[^1] of PopupListView
    let
      popup = PopupListView(panel.subviews()[^1])
      itemBounds = popup.popupListItemRect(popup.bounds(), 2)
    check window.clickAt(
      popup.pointToWindow(
        initPoint(
          itemBounds.origin.x + itemBounds.size.width * 0.5'f32,
          itemBounds.origin.y + itemBounds.size.height * 0.5'f32,
        )
      )
    )
    check tree.displayMode == FileTreeDisplayMode.SourceControlChanges
    check panel.scopeButton.title == "Changed Files"
    check panel.scopeButton.toolTip == "Changed Files"
    check panel.scopeButton.accessibilityValue() == "Changed Files"
    check panel.scopeButton.menu()[2].state == bsOn

    for mode in [
      FileTreeDisplayMode.AllFiles, FileTreeDisplayMode.VisibleFiles,
      FileTreeDisplayMode.SourceControlChanges, FileTreeDisplayMode.AllFiles,
    ]:
      panel.scopeButton.openPopup()
      require panel.subviews()[^1] of PopupListView
      let
        scopePopup = PopupListView(panel.subviews()[^1])
        choiceBounds = scopePopup.popupListItemRect(scopePopup.bounds(), mode.ord)
      check window.clickAt(
        scopePopup.pointToWindow(
          initPoint(
            choiceBounds.origin.x + choiceBounds.size.width * 0.5'f32,
            choiceBounds.origin.y + choiceBounds.size.height * 0.5'f32,
          )
        )
      )
      check tree.displayMode == mode
      check panel.scopeButton.title == mode.title()
      for index, item in panel.scopeButton.menu().items():
        check item.state == (if index == mode.ord: bsOn else: bsOff)
      if mode != FileTreeDisplayMode.SourceControlChanges:
        check tree.rowForItem(otherFile) >= 0
