import std/[options, os, osproc, strutils, tempfiles, times, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

suite "Kosmo workspace roots":
  test "browser opens stay in their window after a detached pane closes":
    let
      root = createTempDir("kosmo-closed-pane-", "")
      path = root / "file.txt"
      app = newApplication("Kosmo Closed Pane")
      frontend = newKosmoApplication(app, root, monitorsGitStatus = false)
    writeFile(path, "contents")
    defer:
      frontend.close()
      removeDir(root)
    app.addWindow(frontend.window)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    app.activateWindow(frontend.window)
    require frontend.window.makeFirstResponder(frontend.editorView)
    require frontend.newEditorTab()
    frontend.contentView.layoutSubtreeIfNeeded()
    let
      tabs = frontend.documentTabs
      bounds = tabs.documentTabRect(0)
      start = tabs.pointToWindow(initPoint(bounds.minX + 30, bounds.minY + 12))
      drop = initPoint(
        frontend.window.frame().size.width + 180,
        frontend.window.frame().size.height + 180,
      )
    require frontend.window.mouseDownAt(start)
    require frontend.window.mouseDraggedAt(drop)
    require frontend.window.mouseUpAt(drop)
    require frontend.detachedEditorWindows().len == 1
    let detached = frontend.detachedEditorWindows()[0]
    app.activateWindow(detached)
    detached.close()
    require frontend.showFileExplorer()
    frontend.fileTree.onOpenFile()(path, fodPermanent)
    let models = frontend.documentTabs.documentTabModels()
    var fileInMainWindow = false
    for model in models:
      if model.title == "file.txt":
        fileInMainWindow = true
    check fileInMainWindow

  test "opening a file from a terminal restores the shortcut responder chain":
    let
      root = createTempDir("kosmo-open-focus-", "")
      path = root / "file.txt"
      app = newApplication("Kosmo Open Focus")
      frontend = newKosmoApplication(app, root, monitorsGitStatus = false)
      terminal = newKosmoTerminalView()
    writeFile(path, "file contents")
    defer:
      frontend.close()
      removeDir(root)
    app.addWindow(frontend.window)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    app.activateWindow(frontend.window)
    require frontend.openDocument(
      newKosmoPaneDocument("terminal", "Terminal", terminal)
    )
    require frontend.openPath(path)
    let editorFocused =
      frontend.window.firstResponder() == Responder(frontend.editorView)
    check editorFocused
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: key1, keyCode: key1.ord, modifiers: shortcutModifiers())
    )

  test "quick open and find in files include every added folder":
    let
      workspace = createTempDir("kosmo-multi-root-", "")
      roots = @[workspace / "first", workspace / "second", workspace / "third"]
    for root in roots:
      createDir(root)
      writeFile(root / "shared.txt", "needle " & root.extractFilename())
    let
      app = newApplication("Kosmo Multiple Roots")
      frontend = newKosmoApplication(app, roots[0], monitorsGitStatus = false)
    defer:
      frontend.close()
      removeDir(workspace)
    app.addWindow(frontend.window)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    app.activateWindow(frontend.window)
    require frontend.window.makeFirstResponder(frontend.editorView)
    for root in roots[1 .. ^1]:
      let panel = newOpenPanel()
      let modal = app.beginModalSession(panel.window)
      app.endModalSession(modal)
      panel.window.close()
      require frontend.openPath(root)
    check frontend.fileTree.rootPaths == roots
    require frontend.showQuickOpen()
    check frontend.quickOpenPanel.projectFiles().len == 3
    frontend.quickOpenPanel.dismiss()
    require frontend.showFindInFiles()
    frontend.searchPanel.queryField.text = "needle"
    require frontend.searchPanel.performSearch()
    require frontend.searchPanel.waitForSearch()
    check frontend.searchPanel.resultsView.matches.len == 3
    for root in roots:
      require frontend.showFileExplorer()
      frontend.contentView.layoutSubtreeIfNeeded()
      let
        tree = frontend.fileTree
        row = tree.rowForItem(root / "shared.txt")
      require row >= 0
      let
        bounds = tree.rowItemRect(row)
        point = tree.pointToWindow(initPoint(bounds.minX + 90, bounds.minY + 12))
      require frontend.window.mouseDownAt(point, clickCount = 2)
      require frontend.window.mouseUpAt(point, clickCount = 2)
      let tabs = frontend.editorView.editor.tabs()
      var found = false
      for tab in tabs:
        if tab.filePath == some(root / "shared.txt"):
          found = true
      check found
      when defined(posix):
        require frontend.window.dispatchKeyDown(
          KeyEvent(
            key: keyT,
            keyCode: keyT.ord,
            modifiers: shortcutModifiers() + {nimkit.kmShift},
          )
        )
        check frontend.editorPane.contentView of KosmoTerminalView

  test "quick open keeps duplicate names distinct and deduplicates overlapping roots":
    let
      workspace = createTempDir("kosmo-root-collisions-", "")
      first = workspace / "one" / "project"
      second = workspace / "two" / "project"
    createDir(first / "nested")
    createDir(second)
    writeFile(first / "same.txt", "first")
    writeFile(first / "nested" / "child.txt", "child")
    writeFile(second / "same.txt", "second")
    let
      app = newApplication("Kosmo Root Collisions")
      frontend = newKosmoApplication(app, first, monitorsGitStatus = false)
    defer:
      frontend.close()
      removeDir(workspace)
    app.addWindow(frontend.window)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    app.activateWindow(frontend.window)
    require frontend.openPath(second)
    require frontend.openPath(first / "nested")
    require frontend.showQuickOpen()
    check frontend.quickOpenPanel.projectFiles().len == 3
    require frontend.window.dispatchTextInput(second / "same.txt")
    require frontend.quickOpenPanel.filteredFiles().len == 1
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    check not frontend.quickOpenPanel.isOpen()
    var openedSecond = false
    for tab in frontend.editorView.editor.tabs():
      if tab.active and tab.filePath == some(second / "same.txt"):
        openedSecond = true
    check openedSecond

  test "Git monitoring includes newly added roots and retains each root's decorations":
    let
      workspace = createTempDir("kosmo-roots-git-", "")
      first = workspace / "first"
      second = workspace / "second"
      plain = workspace / "plain"
      originalDirectory = getCurrentDir()
    for root in [first, second, plain]:
      createDir(root)
      writeFile(root / "changed.txt", "untracked")
    for root in [first, second]:
      let initialization = execCmdEx("git -C " & quoteShell(root) & " init -q")
      require initialization.exitCode == 0
    let tree = newKosmoFileTree(first)
    discard tree.startGitStatusMonitoring(refreshInterval = initDuration())
    defer:
      tree.stopGitStatusMonitoring()
      removeDir(workspace)
    require tree.waitForGitStatus()
    require tree.addRootPath(second)
    require tree.addRootPath(plain)
    require tree.waitForGitStatus()
    check getCurrentDir() == originalDirectory
    for root in [first, second]:
      check tree.outlineItemWithIdentifier(root / "changed.txt").decoration.badge == "U"
    check tree.outlineItemWithIdentifier(plain / "changed.txt").decoration.badge == ""

    removeFile(second / "changed.txt")
    require tree.refreshGitStatus()
    require tree.waitForGitStatus()
    check tree.outlineItemWithIdentifier(first / "changed.txt").decoration.badge == "U"
    check tree.outlineItemWithIdentifier(second / "changed.txt").decoration.badge == ""
    tree.rootPath = plain
    require tree.waitForGitStatus()
    tree.applyGitStatus(
      GitStatusSnapshot(
        rootPath: first,
        isRepository: true,
        entries: @[GitStatusEntry(path: plain / "changed.txt", state: gfsModified)],
      )
    )
    check tree.outlineItemWithIdentifier(plain / "changed.txt").decoration.badge == ""
