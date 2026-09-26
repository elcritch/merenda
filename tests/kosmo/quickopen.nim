import std/[options, os, osproc, tempfiles, unicode, unittest]

import figdraw

import merenda/nimkit
import merenda/kosmo/kosmo
import merenda/kosmo/workspacefiles
import fixtures/ui

proc renderedText(node: Fig): string =
  for glyphIndex in 0 ..< node.textLayout.glyphCount():
    result.add node.textLayout.displayRune(glyphIndex)

suite "Kosmo quick open":
  test "quick open uses the platform primary P shortcut":
    let frontend = newKosmoApplication(newApplication("Kosmo Quick Open Shortcut Test"))
    defer:
      frontend.close()

    let quickOpenItem = frontend.application.mainMenu()[1]
      .submenu()
      .menuItemWithIdentifier(KosmoQuickOpenAction)
    require not quickOpenItem.isNil
    check quickOpenItem.keyEquivalent().key == keyP
    check quickOpenItem.modifierMask() == shortcutModifiers()

  test "project files use fuzzy ranking and exclude Git ignored paths":
    let
      root = createTempDir("merenda-kosmo-quick-open-files-", "")
      sourceDirectory = root / "src"
      testDirectory = root / "tests"
      ignoredDirectory = root / "build"
    createDir(sourceDirectory)
    createDir(testDirectory)
    createDir(ignoredDirectory)
    writeFile(root / ".gitignore", "build/\n")
    writeFile(sourceDirectory / "main.nim", "echo \"main\"\n")
    writeFile(testDirectory / "main_spec.nim", "discard\n")
    writeFile(ignoredDirectory / "main-generated.nim", "discard\n")
    discard execProcess(
      "git",
      workingDir = root,
      args = ["init", "-q"],
      options = {poUsePath, poStdErrToStdOut},
    )
    require dirExists(root / ".git")
    writeFile(root / ".git" / "info" / "exclude", "*.private\n")
    writeFile(root / "credentials.private", "ignored\n")
    defer:
      removeDir(root)

    let files = projectFiles(root)
    check "src/main.nim" in files
    check "tests/main_spec.nim" in files
    check "build/main-generated.nim" notin files
    check "credentials.private" notin files
    check fuzzyFilterFiles(files, "smn")[0] == "src/main.nim"

  test "project files fall back to the filesystem when Git listing fails":
    let root = createTempDir("merenda-kosmo-quick-open-fallback-", "")
    writeFile(root / ".gitignore", "*.private\n")
    writeFile(root / "notes.private", "included by fallback\n")
    writeFile(root / "README.md", "# Fallback\n")
    defer:
      removeDir(root)

    check projectFiles(root) == @[".gitignore", "README.md", "notes.private"]

  test "standalone quick open retains its root for no-argument reloads":
    let root = createTempDir("merenda-kosmo-quick-open-root-", "")
    writeFile(root / "retained.nim", "discard\n")
    let panel = newKosmoQuickOpenPanel(root)
    defer:
      panel.workspaceFiles.close()
      removeDir(root)

    check panel.rootPath() == root
    panel.reloadProjectFiles()
    check panel.rootPath() == root
    check panel.projectFiles() == @["retained.nim"]

  test "popup shows its prompt and file choices within the window":
    let
      root = createTempDir("merenda-kosmo-quick-open-layout-", "")
      frontend = newKosmoApplication(newApplication("Kosmo Quick Open Layout Test"))
    for name in ["alpha.nim", "beta.nim", "gamma.nim"]:
      writeFile(root / name, "discard\n")
    defer:
      frontend.close()
      removeDir(root)

    frontend.window.setContentView(frontend.contentView)
    frontend.quickOpenPanel.reloadProjectFiles(root)
    frontend.quickOpenPanel.hidden = false
    for width in [640.0'f32, 1000.0'f32]:
      frontend.contentView.frame = rect(0, 0, width, 700)
      frontend.contentView.layoutSubtreeIfNeeded()
      frontend.quickOpenPanel.checkVisibleIn(frontend.contentView)
      frontend.quickOpenPanel.queryField.checkVisibleIn(frontend.quickOpenPanel)
      let renders = buildRenders(frontend.contentView)
      var texts: seq[string]
      for level, render in renders:
        for node in render.nodes:
          if node.kind == nkText:
            texts.add node.renderedText()
      for expected in ["Open File", "alpha.nim", "beta.nim", "gamma.nim"]:
        check expected in texts

  test "quick open spinner draws on the popup layer":
    let files = newWorkspaceFiles()
    defer:
      files.close()
    let panel = newKosmoQuickOpenPanel(files = files)
    let indicator = panel.progressIndicator
    # Render independently of the popup's slide-in animation and file worker.
    indicator.removeFromSuperview()
    indicator.frame = rect(0, 0, 20, 20)
    indicator.startAnimation()
    defer:
      indicator.stopAnimation()
    let renders = buildRenders(indicator)
    var visibleIndicator = false
    for node in renders[PopupDrawLevel].nodes:
      if node.kind == nkDrawable and node.drawOps.len > 0:
        visibleIndicator = true
    check visibleIndicator

  test "platform primary P filters, selects, opens, and dismisses the file popup":
    let
      root = createTempDir("merenda-kosmo-quick-open-input-", "")
      sourceDirectory = root / "src"
      testDirectory = root / "tests"
      ignoredDirectory = root / "build"
      sourcePath = sourceDirectory / "main.nim"
      testPath = testDirectory / "main_spec.nim"
    createDir(sourceDirectory)
    createDir(testDirectory)
    createDir(ignoredDirectory)
    writeFile(root / ".gitignore", "build/\n")
    writeFile(sourcePath, "echo \"main\"\n")
    writeFile(testPath, "discard\n")
    writeFile(ignoredDirectory / "main-generated.nim", "discard\n")
    discard execProcess(
      "git",
      workingDir = root,
      args = ["init", "-q"],
      options = {poUsePath, poStdErrToStdOut},
    )
    require dirExists(root / ".git")
    let frontend = newKosmoApplication(newApplication("Kosmo Quick Open Input Test"))
    defer:
      frontend.close()
      removeDir(root)

    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    frontend.fileTree.rootPath = root
    check frontend.window.makeFirstResponder(frontend.editorView)

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyP, keyCode: keyP.ord, modifiers: shortcutModifiers())
    )
    check frontend.quickOpenPanel.isOpen()
    check frontend.window.fieldEditorClient() == frontend.quickOpenPanel.queryField
    let loading = frontend.quickOpenPanel.isLoading()
    check frontend.quickOpenPanel.progressIndicator.animating() == loading
    require frontend.quickOpenPanel.waitForProjectFiles()
    check not frontend.quickOpenPanel.progressIndicator.animating()
    check "build/main-generated.nim" notin frontend.quickOpenPanel.projectFiles()

    check frontend.window.dispatchTextInput("mainx")
    check frontend.quickOpenPanel.filteredFiles().len == 0
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord)
    )
    check frontend.quickOpenPanel.queryField.text() == "main"
    check frontend.quickOpenPanel.filteredFiles() ==
      @["src/main.nim", "tests/main_spec.nim"]
    check frontend.quickOpenPanel.highlightedFile() == "src/main.nim"

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord)
    )
    check frontend.quickOpenPanel.highlightedFile() == "tests/main_spec.nim"
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyP, keyCode: keyP.ord, modifiers: shortcutModifiers())
    )
    check frontend.quickOpenPanel.highlightedFile() == "tests/main_spec.nim"
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord, text: "\n")
    )
    check not frontend.quickOpenPanel.isOpen()
    check frontend.editorView.editor.tabs()[^1].filePath.get() == testPath

    check frontend.window.makeFirstResponder(frontend.editorView)
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyP, keyCode: keyP.ord, modifiers: shortcutModifiers())
    )
    check frontend.quickOpenPanel.isOpen()
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    check not frontend.quickOpenPanel.isOpen()
    check frontend.window.firstResponder() == frontend.editorView
