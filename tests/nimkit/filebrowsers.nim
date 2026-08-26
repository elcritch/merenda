import std/[os, tempfiles, unittest]

import figdraw
import sigils/core

import merenda/nimkit

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

    check browser.tableView().columnCount() == 2
    check browser.tableView().rowCount() == 3
    check browser.entries()[0].path == folder
    check browser.operationButtons().len == 7
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
