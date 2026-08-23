import std/[os, strutils, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

proc renderedText(buffer: RenderBuffer): string =
  for row in 0 ..< buffer.height:
    for column in 0 ..< buffer.width:
      result.add buffer.cell(column, row).symbol
    result.add '\n'

suite "Kosmo":
  test "renders initial text into a cell grid":
    let editor = newKosmoEditor(text = "hello")
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    check "hello" in buffer.renderedText
    editor.close()

  test "text input and physical keys use Moe's frontend API":
    let editor = newKosmoEditor()
    var buffer = newRenderBuffer(24, 8)

    check editor.handleKey("i")
    check editor.handleTextInput("λ")
    check editor.handleKey("Esc")
    editor.render(buffer)

    check "λ" in buffer.renderedText
    editor.close()

  test "scroll input reports a frontend-neutral outcome":
    let editor = newKosmoEditor(text = "one\ntwo\nthree")
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    let outcome = editor.handleScrollInput(initScrollInput(2, 2, 1))
    check outcome.requestedRows == 1
    check outcome.region.rows >= 0
    check outcome.region.columns >= 0
    editor.close()

  test "fractional wheel deltas accumulate into physical rows":
    var lines: seq[string]
    for index in 0 ..< 40:
      lines.add "line " & $index
    let
      editor = newKosmoEditor(text = lines.join("\n"))
      view = newKosmoEditorView(editor)
    view.frame = rect(0, 0, 240, 120)
    view.refresh()

    for _ in 0 ..< 3:
      check view.scrollBy(-0.25'f32, row = 2, column = 2).requestedRows == 0
    let outcome = view.scrollBy(-0.25'f32, row = 2, column = 2)
    check outcome.handled
    check outcome.requestedRows == 1
    check outcome.appliedRows == 1
    editor.close()

  test "opens a file through the Moe facade":
    let path = getTempDir() / "merenda-kosmo-open-file.txt"
    writeFile(path, "opened from disk")
    defer:
      if fileExists(path):
        removeFile(path)

    let editor = newKosmoEditor()
    let outcome = editor.openFile(path)
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    check outcome.loaded
    check "opened from disk" in buffer.renderedText
    editor.close()

  test "rejects binary files before rendering them as text":
    let path = getTempDir() / "merenda-kosmo-binary-file"
    writeFile(path, "\xCF\xFA\xED\xFE" & "\0".repeat(64))
    defer:
      if fileExists(path):
        removeFile(path)

    let
      editor = newKosmoEditor()
      outcome = editor.openFile(path)
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    check not outcome.loaded
    check "binary file" in outcome.message
    editor.close()

  test "frontend adds an Open command to the File menu":
    let app = newApplication("Kosmo Test")
    let frontend = newKosmoApplication(app)
    let fileMenu = app.mainMenu()[0].submenu()
    let openItem = fileMenu.menuItemWithIdentifier(KosmoOpenFileAction)

    check not openItem.isNil
    check openItem.title == "Open…"
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.contentView.menuBar().hidden() == app.usesNativeMainMenu()
    if app.usesNativeMainMenu():
      check frontend.contentView.contentView().frame().origin.y == 0.0'f32
    check frontend.splitView.panes() ==
      @[View(frontend.fileTree), View(frontend.editorView)]
    frontend.editorView.editor.close()

  test "settled editor refresh does not re-dirty its containing layout":
    let frontend = newKosmoApplication(newApplication("Kosmo Layout Test"))
    defer:
      frontend.close()

    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    frontend.contentView.layoutSubtreeIfNeeded()

    check not frontend.contentView.needsLayout()
    check not frontend.contentView.contentView().needsLayout()

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
