import std/[options, os, osproc, tempfiles, unicode, unittest]

import figdraw

import merenda/nimkit
import merenda/kosmo/kosmo

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add rune

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
    defer:
      removeDir(root)

    let files = projectFiles(root)
    check "src/main.nim" in files
    check "tests/main_spec.nim" in files
    check "build/main-generated.nim" notin files
    check fuzzyFilterFiles(files, "smn")[0] == "src/main.nim"

  test "popup blurs translucent panel input and result row surfaces":
    let
      root = createTempDir("merenda-kosmo-quick-open-blur-", "")
      frontend = newKosmoApplication(newApplication("Kosmo Quick Open Blur Test"))
    writeFile(root / "alpha.nim", "discard\n")
    writeFile(root / "beta.nim", "discard\n")
    writeFile(root / "gamma.nim", "discard\n")
    defer:
      frontend.close()
      removeDir(root)

    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    frontend.quickOpenPanel.reloadProjectFiles(root)
    frontend.quickOpenPanel.hidden = false
    let renders = buildRenders(frontend.contentView)

    var
      defaultBlurs: seq[Fig]
      popupBlurs: seq[Fig]
    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkBackdropBlur:
        defaultBlurs.add node
    for node in renders[PopupDrawLevel].nodes:
      if node.kind == nkBackdropBlur:
        popupBlurs.add node

    require defaultBlurs.len == 2
    require popupBlurs.len == 1
    let
      outerBlur = defaultBlurs[0]
      queryBlur = defaultBlurs[1]
      resultsBlur = popupBlurs[0]
      outerTintAlpha = outerBlur.fill.centerColorRgba().a
      queryTintAlpha = queryBlur.fill.centerColorRgba().a
      resultsTintAlpha = resultsBlur.fill.centerColorRgba().a

    check frontend.quickOpenPanel.boxTitle() == "Open File"
    var titleNode = none(Fig)
    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkText and node.renderedText() == "Open File":
        titleNode = some(node)
    require titleNode.isSome
    require titleNode.get().textLayout.spanColors.len > 0
    require titleNode.get().textLayout.selectionRects.len > 0
    var
      titleMinX = float32.high
      titleMaxX = -float32.high
    for rect in titleNode.get().textLayout.selectionRects:
      titleMinX = min(titleMinX, rect.x)
      titleMaxX = max(titleMaxX, rect.x + rect.w)
    let
      titleColor = titleNode.get().textLayout.spanColors[0].centerColorRgba()
      titleContentCenterX = (titleMinX + titleMaxX) / 2.0'f32
      titleBoundsCenterX = titleNode.get().screenBox.w / 2.0'f32
    check titleNode.get().screenBox.y < queryBlur.screenBox.y
    check abs(titleContentCenterX - titleBoundsCenterX) <= 1.0'f32
    check titleColor.a == high(uint8)
    check titleColor.r.int + titleColor.g.int + titleColor.b.int > 384

    check outerBlur.backdropBlur.blur > 0.0'f32
    check queryBlur.backdropBlur.blur > 0.0'f32
    check resultsBlur.backdropBlur.blur > 0.0'f32
    check outerTintAlpha < queryTintAlpha
    check queryTintAlpha == resultsTintAlpha
    check outerBlur.screenBox.w > queryBlur.screenBox.w
    check outerBlur.screenBox.h > resultsBlur.screenBox.h

    var
      queryCoverAlpha = 0'u8
      resultsCoverAlpha = 0'u8
    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.screenBox == queryBlur.screenBox:
        queryCoverAlpha = max(queryCoverAlpha, node.fill.centerColorRgba().a)
    for node in renders[PopupDrawLevel].nodes:
      if node.kind == nkRectangle and node.screenBox == resultsBlur.screenBox:
        resultsCoverAlpha = max(resultsCoverAlpha, node.fill.centerColorRgba().a)
    check queryCoverAlpha < queryTintAlpha
    check resultsCoverAlpha < resultsTintAlpha

    var
      minimumRowAlpha = high(uint8)
      maximumRowAlpha = 0'u8
      rowCount = 0
    for node in renders[PopupDrawLevel].nodes:
      if node.kind == nkRectangle and
          node.screenBox.w > resultsBlur.screenBox.w * 0.9'f32 and
          node.screenBox.h < resultsBlur.screenBox.h:
        let alpha = node.fill.centerColorRgba().a
        minimumRowAlpha = min(minimumRowAlpha, alpha)
        maximumRowAlpha = max(maximumRowAlpha, alpha)
        inc rowCount
    require rowCount > 1
    check minimumRowAlpha > 0'u8
    check minimumRowAlpha < maximumRowAlpha
    check maximumRowAlpha < high(uint8)

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
    let initialAnimationCount = frontend.window.animationScheduler().animationCount()

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyP, keyCode: keyP.ord, modifiers: shortcutModifiers())
    )
    check frontend.quickOpenPanel.isOpen()
    check frontend.window.fieldEditorClient() == frontend.quickOpenPanel.queryField
    check "build/main-generated.nim" notin frontend.quickOpenPanel.projectFiles()
    let startFrame = frontend.quickOpenPanel.frame()
    check startFrame.origin.y + startFrame.size.height <=
      frontend.contentView.bounds().origin.y
    check frontend.quickOpenPanel.presentationOffset() < 0.0'f32
    check frontend.window.animationScheduler().animationCount() > initialAnimationCount

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
      KeyEvent(key: keyP, keyCode: keyP.ord, modifiers: shortcutModifiers())
    )
    check frontend.quickOpenPanel.isOpen()
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    check not frontend.quickOpenPanel.isOpen()
    check frontend.window.firstResponder() == frontend.editorView
