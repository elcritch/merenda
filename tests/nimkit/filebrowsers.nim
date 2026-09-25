import std/[os, strutils, tempfiles, unittest]

import figdraw
import sigils/core

import merenda/nimkit
import ./fixtures/widgetflows

type FileBrowserSignalSpy = ref object of Responder
  activatedPaths: seq[string]

proc newFileBrowserSignalSpy(): FileBrowserSignalSpy =
  result = FileBrowserSignalSpy()
  initResponder(result)

proc rememberFileBrowserActivation(
    spy: FileBrowserSignalSpy, sender: DynamicAgent, entry: FileBrowserEntry
) {.slot.} =
  discard sender
  spy.activatedPaths.add entry.path

proc rowForPath(browser: FileBrowser, path: string): int =
  for index, entry in browser.entries():
    if entry.path == path:
      return index
  -1

proc fileBrowserRowPoint(browser: FileBrowser, row: int): Point =
  let
    tableView = browser.tableView()
    rowRect = tableView.rowItemRect(row)
  tableView.pointToWindow(
    initPoint(
      rowRect.origin.x + rowRect.size.width * 0.5'f32,
      rowRect.origin.y + rowRect.size.height * 0.5'f32,
    )
  )

proc clickFileBrowserRow(
    window: Window, browser: FileBrowser, row: int, modifiers: set[KeyModifier] = {}
): bool =
  let point = browser.fileBrowserRowPoint(row)
  window.mouseDownAt(point, modifiers = modifiers) and
    window.mouseUpAt(point, modifiers = modifiers)

proc doubleClickFileBrowserRow(window: Window, browser: FileBrowser, row: int): bool =
  let point = browser.fileBrowserRowPoint(row)
  window.mouseDownAt(point, clickCount = 2) and window.mouseUpAt(point, clickCount = 2)

proc clickButton(window: Window, button: Button): bool =
  let bounds = button.bounds()
  window.clickAt(
    button.pointToWindow(
      initPoint(
        bounds.origin.x + bounds.size.width * 0.5'f32,
        bounds.origin.y + bounds.size.height * 0.5'f32,
      )
    )
  )

suite "File browsers":
  test "filesystem listings load lazily and refresh explicitly":
    let
      root = createTempDir("merenda-file-browser-cache-", "")
      original = root / "original.txt"
      added = root / "added.txt"
    writeFile(original, "original")
    defer:
      removeFile(original)
      if fileExists(added):
        removeFile(added)
      removeDir(root)

    var model = initFileSystemBrowserModel()
    check not model.isDirectoryLoaded(root)
    check model.cachedDirectoryCount() == 0
    check model.entries(root).len == 1
    check model.isDirectoryLoaded(root)
    check model.cachedDirectoryCount() == 1

    writeFile(added, "added")
    check model.entries(root).len == 1
    model.invalidate(root)
    check model.entries(root).len == 2

  test "filesystem listings cap entries and report truncation":
    let root = createTempDir("merenda-file-browser-limit-", "")
    var paths: seq[string]
    for index in 0 ..< 5:
      let path = root / ("entry-" & $index & ".txt")
      writeFile(path, "entry")
      paths.add path
    defer:
      for path in paths:
        removeFile(path)
      removeDir(root)

    var model = initFileSystemBrowserModel(entryLimit = 3)
    check model.entryLimit() == 3
    check model.entries(root).len == 3
    check model.isDirectoryTruncated(root)

    let browser = newFileBrowser(root, entryLimit = 3)
    check browser.entries().len == 3
    check browser.isDirectoryListingTruncated()
    check "showing up to 3 entries" in browser.statusLabel().text
    check browser.locationField().text == absolutePath(root)

    browser.entryLimit = 5
    check browser.entries().len == 5
    check not browser.isDirectoryListingTruncated()

  test "refresh updates the directory truncation notice":
    let root = createTempDir("merenda-file-browser-refresh-limit-", "")
    var paths: seq[string]
    for index in 0 ..< 3:
      let path = root / ("entry-" & $index & ".txt")
      writeFile(path, "entry")
      paths.add path
    let overflow = root / "overflow.txt"
    defer:
      for path in paths:
        if fileExists(path):
          removeFile(path)
      if fileExists(overflow):
        removeFile(overflow)
      removeDir(root)

    let browser = newFileBrowser(root, entryLimit = 3)
    check not browser.isDirectoryListingTruncated()
    check "showing up to" notin browser.statusLabel().text

    writeFile(overflow, "overflow")
    browser.refresh()
    check browser.isDirectoryListingTruncated()
    check "showing up to 3 entries" in browser.statusLabel().text

    removeFile(overflow)
    browser.refresh()
    check not browser.isDirectoryListingTruncated()
    check "showing up to" notin browser.statusLabel().text

  test "browser table and name column grow and shrink with the viewport":
    let root = createTempDir("merenda-browser-resize-", "")
    defer:
      removeDir(root)
    let browser = newFileBrowser(root, frame = rect(0, 0, 640, 420))
    browser.layoutSubtreeIfNeeded()
    let
      table = browser.tableView()
      originalSize = table.frame().size
      nameWidth = table.columnWithIdentifier("name").width()
      placesWidth = browser.placesView().frame().size.width
      toolbarHeight = browser.toolbar().frame().size.height
      locationHeight = browser.locationField().frame().size.height
    check originalSize.height > 200
    for size in [initSize(940, 620), initSize(640, 420)]:
      browser.frame = rect(0, 0, size.width, size.height)
      browser.layoutSubtreeIfNeeded()
      check abs(table.frame().size.width - originalSize.width - (size.width - 640)) < 1
      check abs(table.frame().size.height - originalSize.height - (size.height - 420)) <
        1
      check abs(
        table.columnWithIdentifier("name").width() - nameWidth - (size.width - 640)
      ) < 1
      check browser.placesView().frame().size.width == placesWidth
      check browser.toolbar().frame().size.height == toolbarHeight
      check browser.locationField().frame().size.height == locationHeight

  test "editable location navigates relative paths and keeps invalid paths out of history":
    let
      root = createTempDir("merenda-browser-location-", "")
      folder = root / "folder"
    createDir(folder)
    defer:
      removeDir(folder)
      removeDir(root)
    let
      browser = newFileBrowser(root)
      window = newWindow("Location workflow", frame = rect(0, 0, 760, 540))
    defer:
      window.close()
    window.setContentView(browser)
    require window.replaceText(browser.locationField(), "folder")
    require window.pressKey(keyEnter)
    check browser.directoryPath() == absolutePath(folder)
    check browser.locationField().text == absolutePath(folder)
    require window.replaceText(browser.locationField(), "missing")
    require window.pressKey(keyEnter)
    check browser.directoryPath() == absolutePath(folder)
    check "Folder not found" in browser.statusLabel().text
    require window.clickView(browser.operationButton(FileBrowserBackOperation))
    check browser.directoryPath() == absolutePath(root)
    require window.clickView(browser.operationButton(FileBrowserForwardOperation))
    check browser.directoryPath() == absolutePath(folder)
    for place in browser.placesView().arrangedSubviews():
      if place of Button:
        require window.clickView(place)
        check browser.directoryPath() == absolutePath(place.toolTip)

  test "open and save panels give window growth to the browser and anchor their footers":
    let root = createTempDir("merenda-panel-resize-", "")
    defer:
      removeDir(root)
    let
      openPanel = newOpenPanel()
      savePanel = newSavePanel()
    defer:
      openPanel.window.close()
      savePanel.window.close()
    openPanel.directoryUrl = root
    savePanel.directoryUrl = root
    savePanel.nameFieldStringValue = "new.txt"
    discard openPanel.contentView()
    discard savePanel.contentView()
    for panel in [
      (openPanel.window, openPanel.fileBrowser(), openPanel.buttonViews),
      (savePanel.window, savePanel.fileBrowser(), savePanel.buttonViews),
    ]:
      let (window, browser, buttons) = panel
      window.contentView.layoutSubtreeIfNeeded()
      let
        originalWindow = window.frame()
        originalSize = browser.tableView().frame().size
        buttonSize = buttons[0].frame().size
        buttonOrigin = buttons[0].pointToWindow(initPoint(0, 0))
      check originalSize.height > 200
      check buttonSize.width >= buttons[0].intrinsicContentSize().width
      check buttonSize.width < originalWindow.size.width / 2
      check buttons[1].frame().maxX <= buttons[0].frame().origin.x
      window.frame = rect(
        100, 100, originalWindow.size.width + 200, originalWindow.size.height + 160
      )
      window.contentView.layoutSubtreeIfNeeded()
      check abs(browser.tableView().frame().size.width - originalSize.width - 200) < 1
      check abs(browser.tableView().frame().size.height - originalSize.height - 160) < 1
      check buttons[0].frame().size == buttonSize
      let nextOrigin = buttons[0].pointToWindow(initPoint(0, 0))
      check abs(nextOrigin.x - buttonOrigin.x - 200) < 1
      check abs(nextOrigin.y - buttonOrigin.y - 160) < 1
      window.frame = originalWindow
      window.contentView.layoutSubtreeIfNeeded()
      check browser.tableView().frame().size == originalSize

  test "save browser changes destination and selects names without losing a typed filename":
    let
      root = createTempDir("merenda-save-browser-", "")
      folder = root / "folder"
      existing = root / "existing.txt"
    createDir(folder)
    writeFile(existing, "existing")
    defer:
      removeFile(existing)
      removeDir(folder)
      removeDir(root)
    let panel = newSavePanel()
    defer:
      panel.window.close()
    panel.directoryUrl = root
    panel.nameFieldStringValue = "draft"
    panel.allowedFileTypes = @["txt"]
    var responses: seq[int]
    panel.prepareForModal(
      proc(response: int) =
        responses.add response
    )
    discard panel.contentView()
    let browser = panel.fileBrowser()
    discard panel.window.buildRenders()
    require panel.window.clickFileBrowserRow(browser, browser.rowForPath(existing))
    check TextField(panel.nameField).text == "existing.txt"
    check panel.selectedUrl() == existing
    require panel.window.replaceText(TextField(panel.nameField), "new draft")
    require panel.window.doubleClickFileBrowserRow(browser, browser.rowForPath(folder))
    check panel.directoryUrl == absolutePath(folder)
    check TextField(panel.nameField).text == "new draft"
    check panel.selectedUrl() == folder / "new draft.txt"
    require panel.window.clickView(browser.operationButton(FileBrowserBackOperation))
    check panel.selectedUrl() == root / "new draft.txt"
    check responses.len == 0
    require panel.window.replaceText(TextField(panel.nameField), "bad.png")
    check not panel.validateSelection()
    check not Button(panel.buttonViews[0]).enabled
    check responses.len == 0
    require panel.window.replaceText(TextField(panel.nameField), "new draft")
    require panel.window.clickView(panel.buttonViews[0])
    check responses == @[PanelResponseOk]
    check panel.selectedUrl() == root / "new draft.txt"

  test "directory-only open panels can accept the current folder after navigation":
    let
      root = createTempDir("merenda-choose-folder-", "")
      folder = root / "folder"
    createDir(folder)
    defer:
      removeDir(folder)
      removeDir(root)
    let panel = newOpenPanel()
    defer:
      panel.window.close()
    panel.directoryUrl = root
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    discard panel.contentView()
    check panel.selectedUrl() == absolutePath(root)
    check panel.validateSelection()
    panel.fileBrowser().directoryPath = folder
    check panel.selectedUrl() == absolutePath(folder)
    check panel.validateSelection()

  test "pointer keyboard and toolbar interactions drive the file browser":
    let
      root = createTempDir("merenda-file-browser-input-", "")
      folder = root / "folder"
      nestedFile = folder / "nested.txt"
      firstFile = root / "alpha.txt"
      secondFile = root / "beta.md"
      addedFile = root / "later.txt"
    createDir(folder)
    writeFile(nestedFile, "nested")
    writeFile(firstFile, "alpha")
    writeFile(secondFile, "beta")
    defer:
      removeFile(nestedFile)
      removeFile(firstFile)
      removeFile(secondFile)
      if fileExists(addedFile):
        removeFile(addedFile)
      removeDir(folder)
      removeDir(root)

    let
      window = newWindow("File Browser Input", frame = rect(0, 0, 640, 420))
      browser = newFileBrowser(root, frame = rect(0, 0, 640, 420))
      spy = newFileBrowserSignalSpy()
      fileOperation = initFileBrowserOperation(
        "test.file-operation", "File Action", selection = fbosFiles
      )
      folderOperation = initFileBrowserOperation(
        "test.folder-operation", "Folder Action", selection = fbosDirectories
      )
    var
      fileOperationPaths: seq[string]
      folderOperationPaths: seq[string]
    let
      fileButton = browser.addOperationButton(fileOperation) do(
        browser: FileBrowser, entries: seq[FileBrowserEntry]
      ):
        discard browser
        for entry in entries:
          fileOperationPaths.add entry.path
      folderButton = browser.addOperationButton(folderOperation) do(
        browser: FileBrowser, entries: seq[FileBrowserEntry]
      ):
        discard browser
        for entry in entries:
          folderOperationPaths.add entry.path

    browser.connect(fileBrowserEntryWasActivated, spy, rememberFileBrowserActivation)
    window.setContentView(browser)
    discard buildRenders(browser)

    check not browser.tableView().columnWithIdentifier("name").isNil
    check browser.tableView().rowCount() == 3
    check browser.entries()[0].path == folder
    check not fileButton.enabled
    check not folderButton.enabled

    let firstFileRow = browser.rowForPath(firstFile)
    check window.clickFileBrowserRow(browser, firstFileRow)
    check browser.selectedPaths() == @[firstFile]
    check fileButton.enabled
    check not folderButton.enabled
    check window.clickButton(fileButton)
    check fileOperationPaths == @[firstFile]

    browser.allowsMultipleSelection = true
    let secondFileRow = browser.rowForPath(secondFile)
    check window.clickFileBrowserRow(browser, secondFileRow, {kmCommand})
    check browser.selectedPaths() == @[firstFile, secondFile]
    check fileButton.enabled
    check window.clickButton(fileButton)
    check fileOperationPaths == @[firstFile, firstFile, secondFile]

    browser.allowsMultipleSelection = false
    let folderRow = browser.rowForPath(folder)
    check window.clickFileBrowserRow(browser, folderRow)
    check browser.selectedPaths() == @[folder]
    check not fileButton.enabled
    check folderButton.enabled
    check window.clickButton(folderButton)
    check folderOperationPaths == @[folder]

    check window.doubleClickFileBrowserRow(browser, folderRow)
    check browser.directoryPath() == absolutePath(folder)
    check spy.activatedPaths[^1] == folder
    discard buildRenders(browser)

    let nestedRow = browser.rowForPath(nestedFile)
    check window.clickFileBrowserRow(browser, nestedRow)
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check spy.activatedPaths[^1] == nestedFile

    let backButton = browser.operationButton(FileBrowserBackOperation)
    check backButton.enabled
    check window.clickButton(backButton)
    check browser.directoryPath() == absolutePath(root)
    check browser.operationButton(FileBrowserForwardOperation).enabled
    check window.clickButton(browser.operationButton(FileBrowserForwardOperation))
    check browser.directoryPath() == absolutePath(folder)
    check window.clickButton(browser.operationButton(FileBrowserUpOperation))
    check browser.directoryPath() == absolutePath(root)

    writeFile(addedFile, "later")
    check browser.rowForPath(addedFile) == -1
    check window.clickButton(browser.operationButton(FileBrowserRefreshOperation))
    check browser.rowForPath(addedFile) >= 0

    check window.clickButton(browser.operationButton(FileBrowserHomeOperation))
    check browser.directoryPath() == absolutePath(getHomeDir())
    check window.clickButton(browser.operationButton(FileBrowserBackOperation))
    check browser.directoryPath() == absolutePath(root)

  test "open panel accepts files and folders through browser input":
    let
      root = createTempDir("merenda-open-panel-browser-", "")
      folder = root / "folder"
      textFile = root / "document.txt"
      imageFile = root / "image.png"
    createDir(folder)
    writeFile(textFile, "text")
    writeFile(imageFile, "image")
    defer:
      removeFile(textFile)
      removeFile(imageFile)
      removeDir(folder)
      removeDir(root)

    let panel = newOpenPanel()
    panel.directoryUrl = root
    panel.allowedFileTypes = @["txt"]
    panel.canChooseDirectories = true
    var response = -1
    panel.prepareForModal(
      proc(value: int) =
        response = value
    )
    let
      browser = panel.fileBrowser()
      content = panel.contentView()
    discard buildRenders(content)

    check not browser.isNil
    check browser.directoryPath() == absolutePath(root)

    check panel.window.clickFileBrowserRow(browser, browser.rowForPath(imageFile))
    check panel.selectedUrl() == imageFile
    check not Button(panel.buttonViews[0]).enabled

    check panel.window.clickFileBrowserRow(browser, browser.rowForPath(textFile))
    check panel.selectedUrl() == textFile
    check Button(panel.buttonViews[0]).enabled
    check panel.window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check response == PanelResponseOk
    check panel.modalResponse() == PanelResponseOk

    response = -1
    check panel.window.clickFileBrowserRow(browser, browser.rowForPath(folder))
    check panel.selectedUrl() == folder
    check panel.window.clickButton(Button(panel.buttonViews[0]))
    check response == PanelResponseOk
    check panel.selectedUrl() == folder
