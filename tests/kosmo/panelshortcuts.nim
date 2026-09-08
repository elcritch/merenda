## Synthetic user-input coverage for Kosmo's numbered panel shortcuts.
import std/[options, os, strutils, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo
import merenda/kosmo/workspacefiles

proc commandNumberEvent(number: range[1 .. 8]): KeyEvent =
  let key = Key(key1.ord + number - 1)
  KeyEvent(key: key, keyCode: key.ord, modifiers: shortcutModifiers())

proc presentSyntheticWindow(app: Application, frontend: KosmoApplication) =
  app.addWindow(frontend.window)
  frontend.window.setContentView(frontend.contentView)
  frontend.contentView.layoutSubtreeIfNeeded()
  doAssert frontend.window.makeFirstResponder(frontend.editorView)
  app.activateWindow(frontend.window)

proc firstResponderIs(window: Window, expected: Responder): bool =
  window.firstResponder == expected

proc keyWindowIs(app: Application, expected: Window): bool =
  app.keyWindow() == expected

proc controlKeyEvent(key: Key): KeyEvent =
  KeyEvent(key: key, keyCode: key.ord, modifiers: {kmControl})

proc primaryShiftKeyEvent(key: Key): KeyEvent =
  KeyEvent(
    key: key, keyCode: key.ord, modifiers: shortcutModifiers() + {nimkit.kmShift}
  )

suite "Kosmo synthetic panel shortcuts":
  test "saving a new editor tab writes through a Save As panel":
    let
      root = createTempDir("merenda-kosmo-save-untitled-", "")
      path = root / "saved.txt"
      frontend = newKosmoApplication(
        newApplication("Kosmo Save Untitled Test"),
        filePath = root,
        monitorsGitStatus = false,
      )
      panel = newSavePanel()
    defer:
      panel.window.close()
      frontend.close()
      if fileExists(path):
        removeFile(path)
      removeDir(root)

    require frontend.newEditorTab()
    require frontend.editorView.editor.handleKey("i")
    require frontend.editorView.editor.handleTextInput("saved from a new tab")
    require frontend.editorView.editor.handleKey("Esc")
    panel.nameFieldStringValue = "saved.txt"

    check frontend.saveActiveTabForTesting(panel)
    check panel.window.title == "Save As"
    check panel.prompt == "Save"
    check panel.directoryUrl == absolutePath(root)
    check fileExists(path)
    check readFile(path).strip() == "saved from a new tab"
    let savedTab = frontend.editorView.editor.tabs()[^1]
    check savedTab.filePath.isSome
    check savedTab.filePath.get == absolutePath(path)
    check not savedTab.modified

  test "pane navigation focuses a displayed terminal instead of its detached editor":
    let
      app = newApplication("Kosmo Terminal Pane Focus Test")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
      terminal = newKosmoTerminalView()
    defer:
      frontend.close()
    app.presentSyntheticWindow(frontend)
    require frontend.window.sendAction(actionSelector(KosmoSplitVerticalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.openDocument(
      newKosmoPaneDocument("test-terminal", "Terminal", terminal)
    )
    let groups = frontend.editorGroups()
    require groups.len == 2
    require frontend.window.dispatchKeyDown(commandNumberEvent(2))
    require frontend.window.firstResponderIs(groups[0].editorView)

    for direction in [keyL, keyW]:
      require frontend.window.dispatchKeyDown(controlKeyEvent(keyW))
      require frontend.window.dispatchKeyDown(controlKeyEvent(direction))
      check frontend.window.firstResponderIs(terminal)
      check groups[1].pane.contentView == View(terminal)
      check terminal.window() == Responder(frontend.window)
      require frontend.window.dispatchKeyDown(commandNumberEvent(2))

  test "numbered shortcuts repeatedly return from the sidebar to terminal content":
    let
      app = newApplication("Kosmo Terminal Number Focus Test")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
      terminal = newKosmoTerminalView()
    defer:
      frontend.close()
    app.presentSyntheticWindow(frontend)
    require frontend.openDocument(
      newKosmoPaneDocument("test-terminal", "Terminal", terminal)
    )
    for iteration in 0 ..< 5:
      require app.performMenuKeyEquivalent(commandNumberEvent(1))
      check frontend.window.firstResponderIs(frontend.fileTree)
      require app.performMenuKeyEquivalent(commandNumberEvent(2))
      check frontend.window.firstResponderIs(terminal)
      check frontend.editorPane.contentView == View(terminal)

  test "leaving an editor cancels its pending pane prefix":
    let
      app = newApplication("Kosmo Pane Prefix Focus Test")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
      otherWindow = newWindow("Other window")
    defer:
      otherWindow.close()
      frontend.close()
    app.presentSyntheticWindow(frontend)
    require frontend.window.dispatchKeyDown(controlKeyEvent(keyW))
    require frontend.showFileExplorer()
    require frontend.window.dispatchKeyDown(commandNumberEvent(2))
    check not frontend.editorView.performKeyEquivalentInChain(
      KeyEvent(key: keyH, keyCode: keyH.ord)
    )

    require frontend.window.dispatchKeyDown(controlKeyEvent(keyW))
    app.activateWindow(otherWindow)
    app.activateWindow(frontend.window)
    check not frontend.editorView.performKeyEquivalentInChain(
      KeyEvent(key: keyH, keyCode: keyH.ord)
    )

  test "sidebar commands from a detached pane activate the browser window":
    let
      app = newApplication("Kosmo Detached Sidebar Focus Test")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
    defer:
      frontend.close()
    app.presentSyntheticWindow(frontend)
    require frontend.newEditorTab()
    frontend.contentView.layoutSubtreeIfNeeded()
    let
      tabs = frontend.documentTabs
      tabRect = tabs.documentTabRect(0)
      start = tabs.pointToWindow(
        initPoint(
          tabRect.minX + tabRect.size.width * 0.5'f32,
          tabRect.minY + tabRect.size.height * 0.5'f32,
        )
      )
      drop = initPoint(
        frontend.window.frame().size.width + 180.0'f32,
        frontend.window.frame().size.height + 180.0'f32,
      )
    require frontend.window.mouseDownAt(start)
    require frontend.window.mouseDraggedAt(drop)
    require frontend.window.mouseUpAt(drop)
    require frontend.detachedEditorWindows().len == 1
    let detached = frontend.detachedEditorWindows()[0]
    detached.contentView().layoutSubtreeIfNeeded()

    app.activateWindow(detached)
    require detached.sendAction(actionSelector(KosmoShowFileExplorerAction))
    check app.keyWindowIs(frontend.window)
    check frontend.window.firstResponderIs(frontend.fileTree)

    app.activateWindow(detached)
    require detached.sendAction(actionSelector(KosmoFindInFilesAction))
    check app.keyWindowIs(frontend.window)
    let searchFocused =
      frontend.window.fieldEditorClient() == frontend.searchPanel.queryField
    check searchFocused

  test "primary-shift-L reveals the active file only when it is in the browser":
    let
      root = createTempDir("merenda-kosmo-reveal-root-", "")
      outsideRoot = createTempDir("merenda-kosmo-reveal-outside-", "")
      firstFolder = root / "first"
      secondFolder = firstFolder / "second"
      activePath = secondFolder / "active.nim"
      outsidePath = outsideRoot / "outside.nim"
      app = newApplication("Kosmo Reveal Active File Test")
      frontend = newKosmoApplication(app, root, monitorsGitStatus = false)
    createDir(firstFolder)
    createDir(secondFolder)
    writeFile(activePath, "discard\n")
    writeFile(outsidePath, "discard\n")
    defer:
      frontend.close()
      removeDir(root)
      removeDir(outsideRoot)
    app.presentSyntheticWindow(frontend)
    require frontend.fileTree.workspaceFiles.waitForFiles()
    require frontend.openPath(activePath)
    require frontend.showFindInFiles()

    require app.performMenuKeyEquivalent(primaryShiftKeyEvent(keyL))
    check frontend.sidebarTabs.selectedIndex == 0
    check frontend.fileTree.selectedItemIdentifier == absolutePath(activePath)
    check frontend.fileTree.isItemExpanded(absolutePath(root))
    check frontend.fileTree.isItemExpanded(absolutePath(firstFolder))
    check frontend.fileTree.isItemExpanded(absolutePath(secondFolder))
    check frontend.window.firstResponderIs(frontend.fileTree)

    require frontend.openPath(outsidePath)
    require frontend.showFindInFiles()
    require app.performMenuKeyEquivalent(primaryShiftKeyEvent(keyL))
    check frontend.sidebarTabs.selectedIndex == 1
    check frontend.fileTree.selectedItemIdentifier == absolutePath(activePath)

  test "relative Moe saves use the active project's directory":
    let
      workspace = createTempDir("merenda-kosmo-project-save-", "")
      firstRoot = workspace / "first"
      secondRoot = workspace / "second"
      outsideRoot = workspace / "outside"
      savedName = "from-first-window.txt"
      savedPath = firstRoot / savedName
      outsidePath = outsideRoot / savedName
      initialDirectory = getCurrentDir()
    createDir(firstRoot)
    createDir(secondRoot)
    createDir(outsideRoot)
    defer:
      setCurrentDir(initialDirectory)
      if fileExists(savedPath):
        removeFile(savedPath)
      if fileExists(outsidePath):
        removeFile(outsidePath)
      removeDir(firstRoot)
      removeDir(secondRoot)
      removeDir(outsideRoot)
      removeDir(workspace)

    setCurrentDir(outsideRoot)
    let
      app = newApplication("Kosmo Project Save Test")
      manager = newKosmoWindowManager(app)
      first = manager.openProject(firstRoot)
      second = manager.openProject(secondRoot)
    defer:
      manager.close()
    require not first.isNil
    require not second.isNil
    check first.editorView.editor.workingDirectory() == absolutePath(firstRoot)
    check second.editorView.editor.workingDirectory() == absolutePath(secondRoot)

    check first.editorView.editor.handleKey(":")
    check first.editorView.editor.handleTextInput("w " & savedName)
    check first.editorView.editor.handleKey("Enter")

    check fileExists(savedPath)
    check not fileExists(outsidePath)
    check sameFile(getCurrentDir(), outsideRoot)

  test "native primary-1 focuses the file browser in the focused project window":
    let
      firstRoot = createTempDir("merenda-kosmo-panel-first-", "")
      secondRoot = createTempDir("merenda-kosmo-panel-second-", "")
      app = newApplication("Kosmo Panel Focus Test")
      manager = newKosmoWindowManager(app)
      first = newKosmoApplication(manager, firstRoot, monitorsGitStatus = false)
      second = newKosmoApplication(manager, secondRoot, monitorsGitStatus = false)
    defer:
      manager.close()
      removeDir(firstRoot)
      removeDir(secondRoot)
    require not first.isNil
    require not second.isNil
    check not first.fileTree.refreshGitStatus()
    check not second.fileTree.refreshGitStatus()
    app.presentSyntheticWindow(first)
    app.presentSyntheticWindow(second)
    check first.window.firstResponderIs(first.editorView)
    check second.window.firstResponderIs(second.editorView)

    first.window.dispatchHostFocusChanged(true)
    check app.performMenuKeyEquivalent(commandNumberEvent(1))

    check first.window.firstResponderIs(first.fileTree)
    check second.window.firstResponderIs(second.editorView)

  test "native primary-2 focuses the first editor in the focused project window":
    let
      firstRoot = createTempDir("merenda-kosmo-editor-first-", "")
      secondRoot = createTempDir("merenda-kosmo-editor-second-", "")
      app = newApplication("Kosmo Editor Focus Test")
      manager = newKosmoWindowManager(app)
      first = newKosmoApplication(manager, firstRoot, monitorsGitStatus = false)
      second = newKosmoApplication(manager, secondRoot, monitorsGitStatus = false)
    defer:
      manager.close()
      removeDir(firstRoot)
      removeDir(secondRoot)
    require not first.isNil
    require not second.isNil
    app.presentSyntheticWindow(first)
    app.presentSyntheticWindow(second)
    check first.showFileExplorer()
    check first.window.firstResponderIs(first.fileTree)

    first.window.dispatchHostFocusChanged(true)
    check app.performMenuKeyEquivalent(commandNumberEvent(2))

    check first.window.firstResponderIs(first.editorView)
    check second.window.firstResponderIs(second.editorView)
