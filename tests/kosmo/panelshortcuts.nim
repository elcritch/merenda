## Synthetic user-input coverage for Kosmo's numbered panel shortcuts.
import std/[os, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

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

suite "Kosmo synthetic panel shortcuts":
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
