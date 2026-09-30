import std/[monotimes, options, os, strutils, tempfiles, times, unittest]

import sigils

import merenda/nimkit
import merenda/nimkit/text/monotextviews as monoTextViews
import merenda/kosmo/kosmo

proc command(frontend: KosmoApplication, view: KosmoEditorView, text: string): bool =
  frontend.window.makeFirstResponder(view) and frontend.window.dispatchTextInput(":") and
    frontend.window.dispatchTextInput(text) and
    frontend.window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))

proc currentText(editor: KosmoEditor): string =
  for tab in editor.tabs():
    if tab.active:
      return editor.bufferText(tab.id).get("")

proc displayedText(view: KosmoEditorView): string =
  monoTextViews.stringValue(MonoTextView(view))

suite "Kosmo Moe host commands":
  test "split commands duplicate the selected buffer into native panes":
    for scenario in [
      ("split", laVertical),
      ("sp", laVertical),
      ("vsplit", laHorizontal),
      ("vs", laHorizontal),
    ]:
      let frontend = newKosmoApplication(newApplication("Kosmo Ex Split Test"))
      defer:
        frontend.close()
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      let editor = frontend.editorView.editor
      require editor.handleKey("i")
      require editor.handleTextInput("first buffer\nsecond line\nthird line")
      require editor.handleKey("Esc")
      frontend.editorView.refresh()
      require frontend.newEditorTab()
      let source = frontend.editorView
      let selectedTab = frontend.documentTabs.selectedDocumentTabIdentifier
      let originalTabs = frontend.documentTabs.len

      require frontend.command(source, scenario[0])
      frontend.contentView.layoutSubtreeIfNeeded()
      let groups = frontend.editorGroups()
      require groups.len == 2
      check frontend.dockView.rootView() of SplitView
      check SplitView(frontend.dockView.rootView()).splitAxis == scenario[1]
      check groups[0].pane.documentTabs.len == originalTabs
      check groups[0].pane.documentTabs.selectedDocumentTabIdentifier == selectedTab
      check groups[1].pane.documentTabs.len == 1
      check groups[1].pane.documentTabs.selectedDocumentTabIdentifier == selectedTab
      check groups[1].editorView == KosmoEditorView(frontend.window.firstResponder())
      check editor.tabs().len == originalTabs
      check editor.moeWindowCount() == 1

      require frontend.command(groups[1].editorView, "q")
      check frontend.editorGroups().len == 1
      check editor.tabs().len == originalTabs
      check editor.moeWindowCount() == 1

  test "split filenames resolve in the editor directory and preserve the source":
    let
      root = createTempDir("kosmo-ex-split-file-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "source line\nsource cursor\nsource last")
    writeFile(secondPath, "destination text")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)
    for splitCommand in ["split", "vsplit"]:
      let frontend = newKosmoApplication(newApplication("Kosmo Ex Split File Test"))
      defer:
        frontend.close()
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      require frontend.openPath(firstPath)
      let
        source = frontend.editorView
        editor = source.editor
        originalTab = frontend.documentTabs.selectedDocumentTabIdentifier
      editor.workingDirectory = root
      require editor.revealLocation(1, 3)
      source.refresh()
      require frontend.command(source, splitCommand & " second.txt")
      let groups = frontend.editorGroups()
      require groups.len == 2
      check groups[0].pane.documentTabs.len == 1
      check groups[0].pane.documentTabs.selectedDocumentTabIdentifier == originalTab
      check groups[1].pane.documentTabs.len == 1
      check groups[1].pane.documentTabs.selectedDocumentTabItem().title == "second.txt"
      check editor.currentText() == "destination text"
      require groups[0].pane.documentTabs.selectDocumentTabWithIdentifier(originalTab)
      require frontend.window.makeFirstResponder(groups[0].editorView)
      check editor.currentText() == readFile(firstPath)
      check editor.bufferCursor() == KosmoBufferCursor(line: 1, column: 3)
      check editor.tabs().len == 2
      check editor.moeWindowCount() == 1

  test "failed split file opens leave the source and pane count intact":
    let
      root = createTempDir("kosmo-ex-split-invalid-", "")
      binaryPath = root / "binary.dat"
    writeFile(binaryPath, "\0\0\0binary")
    defer:
      removeFile(binaryPath)
      removeDir(root)
    let frontend = newKosmoApplication(newApplication("Kosmo Ex Split Failure Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let editor = frontend.editorView.editor
    editor.workingDirectory = root
    require editor.handleKey("i")
    require editor.handleTextInput("unsaved source")
    require editor.handleKey("Esc")
    frontend.editorView.refresh()
    require frontend.command(frontend.editorView, "vsplit binary.dat")
    check frontend.editorGroups().len == 1
    check editor.tabs().len == 1
    check editor.currentText() == "unsaved source"
    check editor.moeWindowCount() == 1
    check "binary" in frontend.statusLabel.text

  test "new and vnew create empty buffers in native panes":
    for scenario in [("new", laVertical), ("vnew", laHorizontal)]:
      let frontend = newKosmoApplication(newApplication("Kosmo Ex New Test"))
      defer:
        frontend.close()
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      let editor = frontend.editorView.editor
      require editor.handleKey("i")
      require editor.handleTextInput("unsaved original")
      require editor.handleKey("Esc")
      frontend.editorView.refresh()
      let originalTab = frontend.documentTabs.selectedDocumentTabIdentifier
      require frontend.command(frontend.editorView, scenario[0])
      let groups = frontend.editorGroups()
      require groups.len == 2
      check SplitView(frontend.dockView.rootView()).splitAxis == scenario[1]
      check groups[0].pane.documentTabs.selectedDocumentTabIdentifier == originalTab
      check groups[1].pane.documentTabs.selectedDocumentTabIdentifier != originalTab
      check editor.currentText() == ""
      check editor.tabs().len == 2
      check editor.moeWindowCount() == 1
      require groups[0].pane.documentTabs.selectDocumentTabWithIdentifier(originalTab)
      require frontend.window.makeFirstResponder(groups[0].editorView)
      check editor.currentText() == "unsaved original"

  test "Config keeps interactive state without a hidden split or scratch tab":
    let frontend = newKosmoApplication(newApplication("Kosmo In Place Config Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let
      source = frontend.editorView
      editor = source.editor
    require editor.handleKey("i")
    require editor.handleTextInput("source text must stay in its own tab")
    require editor.handleKey("Esc")
    source.refresh()
    let originalTab = frontend.documentTabs.selectedDocumentTabIdentifier

    for _ in 0 ..< 3:
      require frontend.command(source, "config")
      check frontend.documentTabs.len == 2
      check frontend.documentTabs.selectedDocumentTabIdentifier ==
        KosmoConfigTabIdentifier
      check editor.configViewerFocused()
      check editor.moeWindowCount() == 1
      check editor.tabs().len == 1
      check "source text" notin source.displayedText()
      require frontend.documentTabs.selectDocumentTabWithIdentifier(originalTab)
      check editor.configViewerOpen()
      check not editor.configViewerFocused()
      check editor.currentText() == "source text must stay in its own tab"
      check editor.moeWindowCount() == 1

    require frontend.documentTabs.selectDocumentTabWithIdentifier(
      KosmoConfigTabIdentifier
    )
    require frontend.command(source, "q")
    check not editor.configViewerOpen()
    check frontend.documentTabs.len == 1
    check frontend.documentTabs.selectedDocumentTabIdentifier == originalTab
    check editor.currentText() == "source text must stay in its own tab"
    check editor.moeWindowCount() == 1

  test "Config can remain open while another pane edits the source":
    let frontend = newKosmoApplication(newApplication("Kosmo Config Pane Focus Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let
      source = frontend.editorView
      editor = source.editor
      originalTab = frontend.documentTabs.selectedDocumentTabIdentifier
    require frontend.command(source, "config")
    require frontend.documentTabs.selectDocumentTabWithIdentifier(originalTab)
    require frontend.command(source, "vsplit")
    let groups = frontend.editorGroups()
    require groups.len == 2
    require frontend.command(groups[1].editorView, "config")
    check groups[0].pane.documentTabs.selectedDocumentTabIdentifier ==
      KosmoConfigTabIdentifier
    check groups[0].editorView == KosmoEditorView(frontend.window.firstResponder())
    check editor.configViewerFocused()
    require frontend.window.makeFirstResponder(groups[1].editorView)
    check groups[1].editorView == KosmoEditorView(frontend.window.firstResponder())
    check not editor.configViewerFocused()
    check editor.configViewerOpen()
    require frontend.window.dispatchTextInput("i")
    require frontend.window.dispatchTextInput("text in the second pane")
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    check editor.currentText() == "text in the second pane"
    check editor.moeWindowCount() == 1
    let configIndex =
      groups[0].pane.documentTabs.indexOfDocumentTabIdentifier(KosmoConfigTabIdentifier)
    require configIndex >= 0
    require groups[0].pane.documentTabs.closeDocumentTabAtIndex(configIndex)
    check not editor.configViewerOpen()
    check editor.tabs().len == 1
    check editor.currentText() == "text in the second pane"

  test "quit closes a shared unsaved projection and force quit discards only its own buffer":
    let frontend = newKosmoApplication(newApplication("Kosmo Ex Safe Close Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let editor = frontend.editorView.editor
    require editor.handleKey("i")
    require editor.handleTextInput("unsaved shared buffer")
    require editor.handleKey("Esc")
    frontend.editorView.refresh()
    require frontend.command(frontend.editorView, "vsplit")
    require frontend.command(frontend.editorGroups()[1].editorView, "q")
    check frontend.editorGroups().len == 1
    check editor.currentText() == "unsaved shared buffer"
    check editor.tabs().len == 1
    require frontend.newEditorTab()
    require editor.handleKey("i")
    require editor.handleTextInput("discard this tab")
    require editor.handleKey("Esc")
    frontend.editorView.refresh()
    require frontend.command(frontend.editorView, "q!")
    check editor.tabs().len == 1
    check editor.currentText() == "unsaved shared buffer"

  test "runtime mappings open host Config and native panes":
    let frontend = newKosmoApplication(newApplication("Kosmo Host Mapping Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let editor = frontend.editorView.editor
    let originalTab = frontend.documentTabs.selectedDocumentTabIdentifier
    require frontend.command(frontend.editorView, "nmap C-y mode_switch config")
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyY, keyCode: keyY.ord, modifiers: {kmControl})
    )
    check frontend.documentTabs.selectedDocumentTabIdentifier == KosmoConfigTabIdentifier
    check editor.configViewerFocused()
    check editor.moeWindowCount() == 1
    require frontend.documentTabs.selectDocumentTabWithIdentifier(originalTab)
    require frontend.command(frontend.editorView, "nnoremap C-w C-w n")
    require editor.hasWindowKeyMapping()
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
    )
    check frontend.editorGroups().len == 2
    check editor.tabs().len == 2
    check editor.moeWindowCount() == 1

  test "a pane mapping stops replay before trailing edits reach the source buffer":
    let frontend = newKosmoApplication(newApplication("Kosmo Host Replay Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let editor = frontend.editorView.editor
    let originalBuffer = editor.tabs()[0].id
    require editor.handleKey("i")
    require editor.handleTextInput("original")
    require editor.handleKey("Esc")
    frontend.editorView.refresh()
    require frontend.command(frontend.editorView, "nnoremap C-y C-w n i X Esc")
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyY, keyCode: keyY.ord, modifiers: {kmControl})
    )
    check frontend.editorGroups().len == 2
    check editor.bufferText(originalBuffer).get("") == "original"
    check editor.currentText() == ""
    check editor.moeWindowCount() == 1

  test "Config applies edits and retains its selected setting across tab switches":
    let frontend = newKosmoApplication(newApplication("Kosmo Config Edit Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let editor = frontend.editorView.editor
    let originalTab = frontend.documentTabs.selectedDocumentTabIdentifier
    let originalForceMode = editor.forceInputMode()
    require frontend.command(frontend.editorView, "config")
    require frontend.window.dispatchTextInput("/forceInsertMode")
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    check editor.forceInputMode() != originalForceMode
    require frontend.documentTabs.selectDocumentTabWithIdentifier(originalTab)
    require frontend.documentTabs.selectDocumentTabWithIdentifier(
      KosmoConfigTabIdentifier
    )
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    check editor.forceInputMode() == originalForceMode
    check editor.moeWindowCount() == 1
    require frontend.command(frontend.editorView, "help")
    check frontend.documentTabs.selectedDocumentTabIdentifier == KosmoHelpTabIdentifier
    check editor.configViewerOpen()
    check not editor.configViewerFocused()
    require frontend.documentTabs.selectDocumentTabWithIdentifier(
      KosmoConfigTabIdentifier
    )
    check editor.configViewerFocused()
    check editor.moeWindowCount() == 1

  test "Filer split-open keys create native panes and drop the listing":
    let root = createTempDir("kosmo-host-filer-", "")
    let path = root / "chosen.txt"
    writeFile(path, "chosen text")
    defer:
      removeFile(path)
      removeDir(root)
    for (notation, axis) in [("h", laVertical), ("v", laHorizontal)]:
      let frontend = newKosmoApplication(newApplication("Kosmo Filer Split Test"))
      defer:
        frontend.close()
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      frontend.editorView.editor.workingDirectory = root
      require frontend.command(frontend.editorView, "e .")
      check frontend.editorView.editor.mode() == KosmoEditorMode.Other
      require frontend.window.dispatchTextInput("G")
      require frontend.window.dispatchTextInput(notation)
      check frontend.editorGroups().len == 2
      check SplitView(frontend.dockView.rootView()).splitAxis == axis
      check frontend.editorView.editor.currentText() == "chosen text"
      check frontend.editorView.editor.mode() == KosmoEditorMode.Normal
      check frontend.editorView.editor.tabs().len == 2
      check frontend.editorView.editor.moeWindowCount() == 1

  test "ambiguous Moe mappings fire from the frontend idle poll":
    let frontend = newKosmoApplication(newApplication("Kosmo Mapping Timeout Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.command(frontend.editorView, "nnoremap g C-w n")
    require frontend.command(frontend.editorView, "nnoremap gg C-w n")
    require frontend.window.dispatchTextInput("g")
    check frontend.editorGroups().len == 1
    let deadline = getMonoTime() + initDuration(seconds = 10)
    while frontend.editorGroups().len != 2 and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      if frontend.editorView.editor.pollGitStatus():
        frontend.editorView.refresh()
      sleep(1)
    check frontend.editorGroups().len == 2
    check frontend.editorView.editor.tabs().len == 2
    check frontend.editorView.editor.moeWindowCount() == 1
