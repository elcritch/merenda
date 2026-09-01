import std/[os, strutils, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

proc pressControlKey(window: Window, key: Key): bool =
  window.dispatchKeyDown(KeyEvent(key: key, keyCode: key.ord, modifiers: {kmControl}))

proc pressPaneKey(
    window: Window, key: Key, text: string, modifiers: set[nimkit.KeyModifier]
): bool =
  window.dispatchKeyDown(
    KeyEvent(text: text, key: key, keyCode: key.ord, modifiers: modifiers)
  )

suite "Kosmo synthetic shortcut input":
  test "close tab defaults do not consume the Vim control-W namespace":
    let
      bindings = initKosmoKeyBindings()
      controlW = KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
      commandW = KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmCommand})
      controlF4 = KeyEvent(key: keyF4, keyCode: keyF4.ord, modifiers: {kmControl})
      firstStroke = bindings.match([controlW])
      closeSequence = bindings.match([controlW, controlW])
      commandShortcut = bindings.match([commandW])
      fallbackShortcut = bindings.match([controlF4])

    check firstStroke.kind == kbmNone
    check closeSequence.kind == kbmNone
    when defined(macosx) or defined(macos):
      check commandShortcut.kind == kbmCommand
      check commandShortcut.selector == actionSelector(KosmoCloseTabAction)
      check fallbackShortcut.kind == kbmNone
    else:
      check fallbackShortcut.kind == kbmCommand
      check fallbackShortcut.selector == actionSelector(KosmoCloseTabAction)

  test "split sequences duplicate a lone empty editor tab":
    let frontend = newKosmoApplication(newApplication("Kosmo Empty Split Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)
    let sourceModels = frontend.documentTabs.documentTabModels()
    require sourceModels.len == 1

    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressControlKey(keyV)
    frontend.contentView.layoutSubtreeIfNeeded()

    let groups = frontend.editorGroups()
    require groups.len == 2
    check groups[0].editorView != groups[1].editorView
    check groups[0].pane.documentTabs.len == 1
    check groups[1].pane.documentTabs.len == 1
    check groups[0].pane.documentTabs.documentTabModels()[0].identifier ==
      sourceModels[0].identifier
    check groups[1].pane.documentTabs.documentTabModels()[0].identifier ==
      sourceModels[0].identifier
    check frontend.editorView.editor.tabs().len == 1

  test "split sequences duplicate a lone file tab":
    let
      root = createTempDir("merenda-kosmo-synthetic-lone-file-", "")
      path = root / "only.txt"
      frontend = newKosmoApplication(newApplication("Kosmo Lone File Split Test"))
    writeFile(path, "only")
    defer:
      frontend.close()
      removeFile(path)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(path)
    check frontend.window.makeFirstResponder(frontend.editorView)
    let sourceModels = frontend.documentTabs.documentTabModels()
    require sourceModels.len == 1

    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressControlKey(keyS)
    frontend.contentView.layoutSubtreeIfNeeded()

    let groups = frontend.editorGroups()
    require groups.len == 2
    require frontend.dockView.rootView() of SplitView
    check SplitView(frontend.dockView.rootView()).splitAxis == laVertical
    check groups[0].editorView != groups[1].editorView
    check groups[0].pane.documentTabs.documentTabModels()[0].identifier ==
      sourceModels[0].identifier
    check groups[1].pane.documentTabs.documentTabModels()[0].identifier ==
      sourceModels[0].identifier
    check frontend.editorView.editor.tabs().len == 1

    check groups[1].pane.documentTabs.closeDocumentTabAtIndex(0)
    check frontend.editorGroups().len == 1
    check groups[0].pane.documentTabs.len == 1
    check groups[0].pane.documentTabs.documentTabModels()[0].identifier ==
      sourceModels[0].identifier
    check frontend.editorView.editor.tabs().len == 1

  test "split sequences wait for the second key before moving the active tab":
    let
      root = createTempDir("merenda-kosmo-synthetic-split-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let scenarios: array[2, tuple[secondKey: Key, axis: LayoutAxis]] =
      [(secondKey: keyS, axis: laVertical), (secondKey: keyV, axis: laHorizontal)]
    for scenario in scenarios:
      let frontend = newKosmoApplication(newApplication("Kosmo Synthetic Split Test"))
      defer:
        frontend.close()
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      check frontend.openPath(firstPath)
      check frontend.openPath(secondPath)
      check frontend.window.makeFirstResponder(frontend.editorView)

      check frontend.window.pressControlKey(keyW)
      check frontend.editorGroups().len == 1
      check frontend.editorView.editor.tabs()[1].active

      check frontend.window.pressControlKey(scenario.secondKey)
      frontend.contentView.layoutSubtreeIfNeeded()

      let groups = frontend.editorGroups()
      require groups.len == 2
      require frontend.dockView.rootView() of SplitView
      check SplitView(frontend.dockView.rootView()).splitAxis == scenario.axis
      check groups[0].pane.documentTabs.documentTabModels()[0].title == "first.txt"
      check groups[1].pane.documentTabs.documentTabModels()[0].title == "second.txt"
      check frontend.window.firstResponder == groups[1].editorView

  test "shared prefix sequences perform the command selected by the second key":
    let
      root = createTempDir("merenda-kosmo-synthetic-prefix-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
      bindingsPath = root / "keybindings.json"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    writeFile(
      bindingsPath,
      """{
  "kosmo.nextTab": "ctrl-w ctrl-j",
  "kosmo.previousTab": "ctrl-w ctrl-k"
}""",
    )
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeFile(bindingsPath)
      removeDir(root)

    let frontend = newKosmoApplication(
      newApplication("Kosmo Synthetic Prefix Test"), keyBindingsPath = bindingsPath
    )
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)
    check frontend.window.makeFirstResponder(frontend.editorView)
    check frontend.editorView.editor.tabs()[1].active

    check frontend.window.pressControlKey(keyW)
    check frontend.editorView.editor.tabs()[1].active
    check frontend.window.pressControlKey(keyJ)
    check frontend.editorView.editor.tabs()[0].active

    check frontend.window.pressControlKey(keyW)
    check frontend.editorView.editor.tabs()[0].active
    check frontend.window.pressControlKey(keyK)
    check frontend.editorView.editor.tabs()[1].active

  test "control-W n creates an empty buffer in a GUI split":
    let
      root = createTempDir("merenda-kosmo-moe-sequence-", "")
      path = root / "matches.txt"
    writeFile(path, "needle zero\nneedle one\nneedle two")
    defer:
      removeFile(path)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Moe Sequence Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(path)
    check frontend.window.makeFirstResponder(frontend.editorView)

    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "/", key: keySlash, keyCode: keySlash.ord)
    )
    check frontend.window.dispatchTextInput("needle")
    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
    )
    check frontend.window.pressControlKey(keyW)
    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "n", key: keyN, keyCode: keyN.ord)
    )
    let groups = frontend.editorGroups()
    require groups.len == 2
    check groups[0].pane.documentTabs.documentTabModels()[0].title == "matches.txt"
    check groups[1].pane.documentTabs.documentTabModels()[0].title == "No Name"
    check frontend.window.firstResponder == groups[1].editorView

  test "control-W control-W navigates panes and control-W c closes a pane":
    let frontend = newKosmoApplication(newApplication("Kosmo Vim Pane Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)

    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressControlKey(keyV)
    frontend.contentView.layoutSubtreeIfNeeded()
    let groups = frontend.editorGroups()
    require groups.len == 2
    check frontend.window.firstResponder == groups[1].editorView

    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressControlKey(keyW)
    check frontend.window.firstResponder == groups[0].editorView

    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressControlKey(keyL)
    check frontend.window.firstResponder == groups[1].editorView

    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressControlKey(keyC)
    check frontend.editorGroups().len == 1
    check frontend.window.firstResponder == groups[0].editorView

  test "Tab stays available for focus traversal until Moe enters insert mode":
    let frontend = newKosmoApplication(newApplication("Kosmo Insert Tab Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)
    let tabEvent = KeyEvent(key: keyTab, keyCode: keyTab.ord)

    check not frontend.editorView.performKeyEquivalentInChain(tabEvent)
    check frontend.editorView.editor.handleKey("i")
    check frontend.editorView.editor.mode() == KosmoEditorMode.Insert
    check frontend.editorView.performKeyEquivalentInChain(tabEvent)
    check frontend.window.firstResponder == frontend.editorView
    check frontend.editorView.editor.handleKey("Esc")
    let tab = frontend.editorView.editor.tabs()[0]
    check frontend.editorView.editor.bufferText(tab.id).get == "\t"

  test "Markdown previews share Vim pane commands and retain navigation":
    let
      root = createTempDir("merenda-kosmo-markdown-pane-", "")
      path = root / "README.md"
      source = "# Preview\n\n" & "scrollable line\n".repeat(120)
      frontend = newKosmoApplication(newApplication("Kosmo Markdown Pane Test"))
    writeFile(path, source)
    defer:
      frontend.close()
      removeFile(path)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 720, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.openPath(path)
    let preview = frontend.editorPane.markdownView
    require preview.waitForMarkdownParsing()
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.window.makeFirstResponder(preview)

    let beforeNavigation = preview.scrollView().contentOffset().y
    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "j", key: keyJ, keyCode: keyJ.ord)
    )
    check frontend.window.animationScheduler().tick(140.ms) == 1
    check preview.scrollView().contentOffset().y > beforeNavigation

    check frontend.window.pressControlKey(keyW)
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    let afterEscape = preview.scrollView().contentOffset().y
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord)
    )
    check frontend.window.animationScheduler().tick(140.ms) == 1
    check preview.scrollView().contentOffset().y > afterEscape

    let afterCancelledNavigation = preview.scrollView().contentOffset().y
    check frontend.window.pressControlKey(keyW)
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord)
    )
    check frontend.window.animationScheduler().tick(140.ms) == 1
    check frontend.editorGroups().len == 1
    check preview.scrollView().contentOffset().y > afterCancelledNavigation

    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyV, "v", {})
    frontend.contentView.layoutSubtreeIfNeeded()
    var groups = frontend.editorGroups()
    require groups.len == 2
    check frontend.window.firstResponder == groups[1].pane.markdownView

    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyW, "w", {})
    check frontend.window.firstResponder == groups[0].pane.markdownView
    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyJ, "j", {})
    check frontend.window.firstResponder == groups[0].pane.markdownView
    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyK, "k", {})
    check frontend.window.firstResponder == groups[0].pane.markdownView
    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyL, "l", {})
    check frontend.window.firstResponder == groups[1].pane.markdownView
    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyH, "h", {})
    check frontend.window.firstResponder == groups[0].pane.markdownView

    let splitView = SplitView(frontend.dockView.rootView())
    let beforeResize = splitView.positionOfDivider(0)
    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyDot, ">", {nimkit.kmShift})
    check splitView.positionOfDivider(0) > beforeResize
    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyComma, "<", {nimkit.kmShift})
    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyEqual, "=", {})

    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyS, "s", {})
    frontend.contentView.layoutSubtreeIfNeeded()
    groups = frontend.editorGroups()
    require groups.len == 3
    check frontend.window.firstResponder == groups[^1].pane.markdownView
    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyEqual, "+", {nimkit.kmShift})
    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyMinus, "-", {})

    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyN, "n", {})
    groups = frontend.editorGroups()
    require groups.len == 4
    check groups[^1].pane.documentTabs.documentTabModels()[0].title == "No Name"

    require frontend.window.makeFirstResponder(groups[0].pane.markdownView)
    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressPaneKey(keyC, "c", {})
    check frontend.editorGroups().len == 3

  test "hybrid input keeps insert-mode control-W in Moe":
    let frontend = newKosmoApplication(newApplication("Kosmo Insert Control-W Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)
    check frontend.editorView.editor.handleKey("i")
    check frontend.editorView.editor.handleTextInput("alpha beta")

    check frontend.window.pressControlKey(keyW)
    check frontend.editorView.editor.handleKey("Esc")
    let tab = frontend.editorView.editor.tabs()[0]
    check frontend.editorView.editor.bufferText(tab.id).get == "alpha "

  test "native input routes selection and undo through Moe semantics":
    let
      frontend = newKosmoApplication(newApplication("Kosmo Native Editing Test"))
      pasteboard = generalPasteboard()
      previousClipboard = pasteboard.plainText()
    defer:
      discard pasteboard.setPlainText(previousClipboard)
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)
    frontend.setEditorInputPolicy(KosmoEditorInputPolicy.Native)
    check frontend.editorView.editor.handleKey("i")
    check frontend.editorView.editor.handleTextInput("alpha beta")
    check frontend.editorView.editor.handleKey("Esc")
    check frontend.editorView.editor.handleKey("0")
    check frontend.editorView.editor.handleKey("v")
    check frontend.editorView.editor.handleKey("e")

    let primary = frontend.shortcutProfile().primaryModifiers()
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyC, keyCode: keyC.ord, modifiers: primary)
    )
    check pasteboard.plainText() == "alpha"
    check frontend.editorView.editor.currentSelection().isSome

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyX, keyCode: keyX.ord, modifiers: primary)
    )
    let tab = frontend.editorView.editor.tabs()[0]
    check frontend.editorView.editor.bufferText(tab.id).get == " beta"
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyZ, keyCode: keyZ.ord, modifiers: primary)
    )
    check frontend.editorView.editor.bufferText(tab.id).get == "alpha beta"

  test "Escape cancels a pending sequence before the next shortcut key":
    let
      root = createTempDir("merenda-kosmo-synthetic-cancel-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
      bindingsPath = root / "keybindings.json"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    writeFile(bindingsPath, """{"kosmo.nextTab": "ctrl-w ctrl-j"}""")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeFile(bindingsPath)
      removeDir(root)

    let frontend = newKosmoApplication(
      newApplication("Kosmo Synthetic Cancel Test"), keyBindingsPath = bindingsPath
    )
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)
    check frontend.window.makeFirstResponder(frontend.editorView)
    check frontend.editorView.editor.tabs()[1].active

    check frontend.window.pressControlKey(keyW)
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    discard frontend.window.pressControlKey(keyJ)
    check frontend.editorView.editor.tabs()[1].active

    check frontend.window.pressControlKey(keyW)
    check frontend.window.pressControlKey(keyJ)
    check frontend.editorView.editor.tabs()[0].active
