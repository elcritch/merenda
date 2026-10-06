import std/[options, os, strutils, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo
import merenda/kosmo/recovery

proc activeText(editor: KosmoEditor): string =
  for tab in editor.tabs():
    if tab.active:
      return editor.bufferText(tab.id).get("")

proc command(editor: KosmoEditor, text: string): bool =
  editor.handleTextInput(":" & text) and editor.handleKey("Enter")

proc command(
    frontend: KosmoApplication, text: string, view: KosmoEditorView = nil
): bool =
  let target = if view.isNil: frontend.editorView else: view
  frontend.window.makeFirstResponder(target) and
    frontend.window.dispatchTextInput(":" & text) and
    frontend.window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))

suite "Kosmo Moe frontend bridges":
  test "native history commits typing and resumes ordinary or forced Input":
    for forced in [false, true]:
      let editor = newKosmoEditor()
      defer:
        editor.close()
      editor.forceInputMode = forced
      if not forced:
        require editor.handleKey("i")
      require editor.handleTextInput("typed text")
      check editor.undo()
      check editor.activeText() == ""
      check editor.mode() == KosmoEditorMode.Insert
      check editor.redo()
      check editor.activeText() == "typed text"
      check editor.mode() == KosmoEditorMode.Insert
      require editor.handleTextInput(" more")
      check editor.undo()
      check editor.activeText() == "typed text"

  test "native clipboard callbacks keep explicit Vim registers and linewise puts":
    let editor = newKosmoEditor("first\nsecond")
    defer:
      editor.close()
    var clipboard, primary: string
    editor.configureClipboard(
      read = proc(selection: KosmoClipboardSelection): string =
        if selection == KosmoClipboardSelection.Clipboard: clipboard else: primary,
      write = proc(selection: KosmoClipboardSelection, text: string): bool =
        if selection == KosmoClipboardSelection.Clipboard:
          clipboard = text
        else:
          primary = text
        true,
    )
    require editor.handleTextInput("gg\"+yy")
    check clipboard == "first\n"
    require editor.handleTextInput("\"+p")
    check editor.activeText() == "first\nfirst\nsecond"
    clipboard = "external"
    require editor.handleTextInput("gg\"+p")
    check "external" in editor.activeText()
    clipboard = ""
    let previous = editor.activeText()
    require editor.handleTextInput("\"+p")
    check editor.activeText() == previous

  test "clipboard callbacks belong to each editor":
    let first = newKosmoEditor("one")
    let second = newKosmoEditor("two")
    defer:
      first.close()
      second.close()
    var firstClipboard, secondClipboard: string
    first.configureClipboard(
      proc(selection: KosmoClipboardSelection): string =
        firstClipboard,
      proc(selection: KosmoClipboardSelection, text: string): bool =
        firstClipboard = text
        true,
    )
    second.configureClipboard(
      proc(selection: KosmoClipboardSelection): string =
        secondClipboard,
      proc(selection: KosmoClipboardSelection, text: string): bool =
        secondClipboard = text
        true,
    )
    require first.handleTextInput("gg\"+yy")
    require second.handleTextInput("gg\"+yy")
    check firstClipboard == "one\n"
    check secondClipboard == "two\n"

  test "save and close affects the selected native tab despite other dirty buffers":
    let directory = createTempDir("kosmo-save-close-", "")
    defer:
      removeDir(directory)
    let path = directory / "saved.txt"
    writeFile(path, "original")
    let frontend =
      newKosmoApplication(newApplication("Kosmo Save Close"), monitorsGitStatus = false)
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let editor = frontend.editorView.editor
    require editor.handleKey("i")
    require editor.handleTextInput("other unsaved work")
    require editor.handleKey("Esc")
    require frontend.editorView.openFile(path)
    let selected = frontend.documentTabs.selectedDocumentTabIdentifier
    require editor.handleTextInput("A changed")
    require editor.handleKey("Esc")
    require frontend.command("wq")
    check frontend.documentTabs.selectedDocumentTabIdentifier != selected
    check readFile(path) == "original changed"
    check editor.activeText() == "other unsaved work"
    require editor.handleKey("i")
    require editor.handleTextInput("still running")
    check editor.undo()

  test "ZZ saves and closes a native tab without quitting the engine":
    let directory = createTempDir("kosmo-zz-", "")
    defer:
      removeDir(directory)
    let path = directory / "saved.txt"
    writeFile(path, "original")
    let frontend =
      newKosmoApplication(newApplication("Kosmo ZZ"), monitorsGitStatus = false)
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    require frontend.newEditorTab()
    require frontend.editorView.openFile(path)
    let selected = frontend.documentTabs.selectedDocumentTabIdentifier
    require frontend.editorView.editor.handleTextInput("A changed")
    require frontend.editorView.editor.handleKey("Esc")
    require frontend.window.makeFirstResponder(frontend.editorView)
    require frontend.window.dispatchTextInput("ZZ")
    frontend.editorView.refresh()
    check frontend.documentTabs.selectedDocumentTabIdentifier != selected
    check readFile(path) == "original changed"

  test "parsed native quit stops a mapping before trailing source edits":
    let editor = newKosmoEditor("original")
    defer:
      editor.close()
    require editor.command("nnoremap C-y : q Enter i X Esc")
    require editor.handleKey("C-y")
    check editor.activeText() == "original"
    let request = editor.takeHostCommandRequest()
    require request.isSome
    check request.get.kind == KosmoHostCommandKind.CloseTab
    check editor.takeHostCommandRequest().isNone

  test "targeted delete retains buffer identity and refuses dirty targets":
    let editor = newKosmoEditor("dirty")
    defer:
      editor.close()
    let first = editor.tabs()[0].id
    require editor.newEmptyBuffer().isSome
    require editor.command("bd " & $first)
    var request = editor.takeHostCommandRequest()
    require request.isSome
    check request.get.kind == KosmoHostCommandKind.DeleteBuffer
    check request.get.bufferId == some(first)
    check not editor.closeTab(first).closed
    require editor.command("bd! " & $first)
    request = editor.takeHostCommandRequest()
    require request.isSome
    check request.get.forceClose
    check editor.closeTab(request.get.bufferId.get, discardChanges = true).closed
    check editor.bufferText(first).isNone

  test "named buffer deletion removes shared projections and keeps unrelated selection":
    let directory = createTempDir("kosmo-delete-name-", "")
    defer:
      removeDir(directory)
    let path = directory / "target.txt"
    writeFile(path, "target")
    let frontend = newKosmoApplication(
      newApplication("Kosmo Delete Shared Buffer"), monitorsGitStatus = false
    )
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    require frontend.openPath(path)
    let editor = frontend.editorView.editor
    let target = editor.tabs()[0].id
    require frontend.command("vsplit")
    require frontend.newEditorTab()
    let source = KosmoEditorView(frontend.window.firstResponder())
    let selected = source.documentTabs.selectedDocumentTabIdentifier
    require frontend.command("bd missing.txt", source)
    check editor.bufferText(target).isSome
    check source.documentTabs.selectedDocumentTabIdentifier == selected
    require frontend.command("bd target.txt", source)
    check editor.bufferText(target).isNone
    check frontend.editorGroups().len == 1
    check source.documentTabs.selectedDocumentTabIdentifier == selected
    check source.documentTabs.len == 1

  test "idle revisions report text changes without depending on Git":
    let editor = newKosmoEditor()
    defer:
      editor.close()
    editor.gitStatusEnabled = false
    discard editor.pollFrontendWork()
    let previous = editor.frontendRevision()
    require editor.handleKey("i")
    require editor.handleTextInput("new text")
    check editor.pollFrontendWork()
    check editor.frontendRevision() > previous

  test "workspace reload applies EditorConfig and preserves dirty buffers":
    let directory = createTempDir("kosmo-reload-", "")
    defer:
      removeDir(directory)
    let path = directory / "sample.nim"
    writeFile(directory / ".editorconfig", "root = true\n[*]\nindent_size = 2\n")
    writeFile(path, "before\n")
    let editor = newKosmoEditor(workingDirectory = directory)
    defer:
      editor.close()
    require editor.openFile(path).loaded
    writeFile(
      directory / ".editorconfig",
      "root = true\n[*]\nindent_size = 4\nindent_style = space\n",
    )
    writeFile(path, "after\n")
    editor.reloadUnmodifiedFile(path)
    check editor.activeText() == "after"
    require editor.handleTextInput("o")
    require editor.handleKey("Tab")
    require editor.handleTextInput("x")
    require editor.handleKey("Esc")
    check editor.activeText().endsWith("\n    x")
    check editor.undo()
    check editor.undo()
    check editor.activeText() == "before"
    require editor.redo()
    require editor.handleKey("i")
    require editor.handleTextInput("unsaved")
    let dirty = editor.activeText()
    writeFile(path, "external\n")
    editor.reloadUnmodifiedFile(path)
    check editor.activeText() == dirty

  test "recovery restores into the original stable buffer and supports undo":
    let directory = createTempDir("kosmo-recovery-", "")
    defer:
      removeDir(directory)
    let path = directory / "sample.txt"
    writeFile(path, "on disk")
    let editor = newKosmoEditor()
    defer:
      editor.close()
    editor.configureRecovery(directory / "recovery")
    require editor.openFile(path).loaded
    let original = editor.tabs()[0].id
    require editor.handleTextInput("A recovered")
    require editor.handleKey("Esc")
    let copies = editor.preserveModifiedBuffers()
    require copies.len == 1
    require editor.undo()
    require editor.restoreRecoveryCopy(copies[0]).loaded
    check editor.tabs().len == 1
    check editor.tabs()[0].id == original
    check editor.activeText() == "on disk recovered"
    check readFile(path) == "on disk"
    check editor.undo()
    check editor.activeText() == "on disk"
    check editor.discardRecoveryCopy(copies[0]).loaded
    check editor.recoveryEntries().len == 0

  test "native recovery restores while Input is forced without a hidden split":
    let directory = createTempDir("kosmo-native-recovery-", "")
    defer:
      removeDir(directory)
    let path = directory / "sample.txt"
    writeFile(path, "on disk")
    let frontend = newKosmoApplication(
      newApplication("Kosmo Recovered Work"), monitorsGitStatus = false
    )
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    let editor = frontend.editorView.editor
    editor.configureRecovery(directory / "recovery")
    require frontend.openPath(path)
    let original = frontend.documentTabs.selectedDocumentTabIdentifier
    require editor.handleTextInput("A recovered")
    require editor.handleKey("Esc")
    require editor.preserveModifiedBuffers().len == 1
    require editor.undo()
    require frontend.command("recover!")
    check frontend.documentTabs.selectedDocumentTabIdentifier ==
      KosmoRecoveryTabIdentifier
    let documents = frontend.editorGroups()[0].documents()
    require documents.len == 1
    let recovery = KosmoRecoveryView(documents[0].contentView)
    check frontend.window.firstResponder() == recovery.preferredResponder()
    editor.forceInputMode = true
    require recovery.restoreSelected()
    check frontend.documentTabs.selectedDocumentTabIdentifier == original
    check editor.activeText() == "on disk recovered"
    check editor.mode() == KosmoEditorMode.Insert
    check editor.moeWindowCount() == 1
    check editor.tabs().len == 1
    check editor.undo()
    check editor.activeText() == "on disk"

  test "jobs output uses a reusable native document without adding engine tabs":
    let frontend = newKosmoApplication(
      newApplication("Kosmo Native Output"), monitorsGitStatus = false
    )
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let editor = frontend.editorView.editor
    let original = editor.tabs().len
    require frontend.command("jobs")
    frontend.editorView.refresh()
    check editor.tabs().len == original
    check frontend.documentTabs.indexOfDocumentTabIdentifier(KosmoOutputTabIdentifier) >=
      0
    var documents = 0
    for group in frontend.editorGroups():
      for document in group.documents():
        if document.identifier == KosmoOutputTabIdentifier:
          inc documents
    check documents == 1
