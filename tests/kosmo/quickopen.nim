import std/[options, os, osproc, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

suite "Kosmo quick open":
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
    defer:
      removeDir(root)

    let files = projectFiles(root)
    check "src/main.nim" in files
    check "tests/main_spec.nim" in files
    check "build/main-generated.nim" notin files
    check fuzzyFilterFiles(files, "smn")[0] == "src/main.nim"

  test "Command-T filters, selects, opens, and dismisses the file popup":
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
      KeyEvent(key: keyT, keyCode: keyT.ord, modifiers: {kmCommand})
    )
    check frontend.quickOpenPanel.isOpen()
    check frontend.window.fieldEditorClient() == frontend.quickOpenPanel.queryField
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
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord, text: "\n")
    )
    check not frontend.quickOpenPanel.isOpen()
    check frontend.editorView.editor.tabs()[^1].filePath.get() == testPath

    check frontend.window.makeFirstResponder(frontend.editorView)
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyT, keyCode: keyT.ord, modifiers: {kmCommand})
    )
    check frontend.quickOpenPanel.isOpen()
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    check not frontend.quickOpenPanel.isOpen()
    check frontend.window.firstResponder() == frontend.editorView
