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

proc typeNativeText(window: Window, text: string) =
  for character in text:
    let value = $character
    discard window.dispatchKeyDown(
      KeyEvent(key: keyForText(value), keyCode: keyCodeForText(value))
    )
    check window.dispatchTextInput(value)

proc typeCoalescedNativeText(window: Window, text: string) =
  for character in text:
    let value = $character
    discard window.dispatchKeyDown(
      KeyEvent(key: keyForText(value), keyCode: keyCodeForText(value))
    )
  check window.dispatchTextInput(text)

proc displayedGridText(view: MonoTextView): string =
  for row in 0 ..< view.lineCount():
    for column in 0 ..< view.columnCount(row):
      result.add view.cellAt(row, column).text
    result.add '\n'

proc buttonWithTitle(view: View, title: string): Button =
  if view of Button and Button(view).title == title:
    return Button(view)
  for child in view.subviews():
    result = child.buttonWithTitle(title)
    if not result.isNil:
      return

func rectCenter(rect: Rect): Point =
  initPoint(
    rect.origin.x + rect.size.width / 2.0'f32,
    rect.origin.y + rect.size.height / 2.0'f32,
  )

proc clickModalButton(window: Window, title: string): bool =
  let button = window.contentView().buttonWithTitle(title)
  if button.isNil:
    return
  window.clickAt(button.pointToWindow(button.bounds().rectCenter()))

proc clickSelectedTabClose(frontend: KosmoApplication): bool =
  let tabRect =
    frontend.documentTabs.documentTabRect(frontend.documentTabs.selectedIndex)
  for x in [tabRect.minX + 15.0'f32, tabRect.maxX - 15.0'f32]:
    discard frontend.window.clickAt(
      frontend.documentTabs.pointToWindow(
        initPoint(x, tabRect.origin.y + tabRect.size.height / 2.0'f32)
      )
    )
    if not frontend.application.modalSession().isNil:
      return true

suite "Kosmo synthetic shortcut input":
  test "three editor panes preserve native insert input in every pane":
    let frontend = newKosmoApplication(newApplication("Kosmo Multi-Pane Input Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)

    for _ in 0 ..< 2:
      check frontend.window.pressControlKey(keyW)
      check frontend.window.pressControlKey(keyN)
    let groups = frontend.editorGroups()
    require groups.len == 3

    let inserted = ["iiii", "alpha", "xyz"]
    for index, group in groups:
      require frontend.window.makeFirstResponder(group.editorView)
      frontend.window.typeNativeText("i" & inserted[index])
      check frontend.window.dispatchKeyDown(
        KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
      )
      var activeTab: KosmoTab
      for tab in frontend.editorView.editor.tabs():
        if tab.active:
          activeTab = tab
          break
      check frontend.editorView.editor.bufferText(activeTab.id).get == inserted[index]
      check group.editorView.displayedGridText().contains(inserted[index])

  test "three editor panes preserve coalesced committed insert input":
    let frontend = newKosmoApplication(newApplication("Kosmo Batched Input Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)

    for _ in 0 ..< 2:
      check frontend.window.pressControlKey(keyW)
      check frontend.window.pressControlKey(keyN)
    let groups = frontend.editorGroups()
    require groups.len == 3

    let inserted = ["iiii", "alpha", "xyz"]
    for index, group in groups:
      require frontend.window.makeFirstResponder(group.editorView)
      frontend.window.typeCoalescedNativeText("i" & inserted[index])
      check frontend.window.dispatchKeyDown(
        KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
      )
      var activeTab: KosmoTab
      for tab in frontend.editorView.editor.tabs():
        if tab.active:
          activeTab = tab
          break
      check frontend.editorView.editor.bufferText(activeTab.id).get == inserted[index]
      check group.editorView.displayedGridText().contains(inserted[index])

  test "inactive pane refreshes preserve the focused pane insert session":
    let frontend = newKosmoApplication(newApplication("Kosmo Pane Refresh Input Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)

    for _ in 0 ..< 2:
      check frontend.window.pressControlKey(keyW)
      check frontend.window.pressControlKey(keyN)
    let groups = frontend.editorGroups()
    require groups.len == 3
    require frontend.window.makeFirstResponder(groups[0].editorView)

    frontend.window.typeNativeText("i")
    require frontend.editorView.editor.mode() == KosmoEditorMode.Insert
    var targetTab: KosmoTab
    for tab in frontend.editorView.editor.tabs():
      if tab.active:
        targetTab = tab
        break
    groups[1].editorView.refresh()
    require frontend.editorView.editor.mode() == KosmoEditorMode.Insert

    for character in "alpha":
      frontend.window.typeNativeText($character)
      require frontend.editorView.editor.mode() == KosmoEditorMode.Insert
      groups[1].editorView.refresh()
      require frontend.editorView.editor.mode() == KosmoEditorMode.Insert

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    check frontend.editorView.editor.bufferText(targetTab.id).get == "alpha"

  test "close tab defaults do not consume the Vim control-W namespace":
    let
      bindings = initKosmoKeyBindings(
        KosmoShortcutProfile.Platform, KosmoShortcutPlatform.LinuxBsd
      )
      macBindings =
        initKosmoKeyBindings(KosmoShortcutProfile.MacOS, KosmoShortcutPlatform.MacOS)
      controlW = KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
      commandW = KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmCommand})
      controlF4 = KeyEvent(key: keyF4, keyCode: keyF4.ord, modifiers: {kmControl})
      firstStroke = bindings.match([controlW])
      closeSequence = bindings.match([controlW, controlW])
      commandShortcut = macBindings.match([commandW])
      fallbackShortcut = bindings.match([controlF4])

    check firstStroke.kind == kbmNone
    check closeSequence.kind == kbmNone
    check commandShortcut.kind == kbmCommand
    check commandShortcut.selector == actionSelector(KosmoCloseTabAction)
    check fallbackShortcut.kind == kbmCommand
    check fallbackShortcut.selector == actionSelector(KosmoCloseTabAction)

  test "close tab confirms before discarding modified files":
    let
      root = createTempDir("merenda-kosmo-close-tab-confirm-", "")
      path = root / "modified.txt"
      frontend = newKosmoApplication(
        newApplication("Kosmo Close Tab Confirmation Test"),
        root,
        monitorsGitStatus = false,
      )
    writeFile(path, "original")
    defer:
      frontend.close()
      removeFile(path)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.openPath(path)
    require frontend.window.makeFirstResponder(frontend.editorView)
    require frontend.editorView.editor.handleKey("i")
    require frontend.editorView.editor.handleTextInput("!")
    require frontend.editorView.editor.handleKey("Esc")
    require frontend.editorView.editor.tabs()[0].modified
    let originalIdentifier = frontend.documentTabs.selectedDocumentTabIdentifier

    check frontend.clickSelectedTabClose()
    let session = frontend.application.modalSession()
    require not session.isNil
    check session.window.title == "Unsaved Changes"
    let confirmationBelongsToWindow = session.parentWindow == frontend.window
    check confirmationBelongsToWindow
    check session.mode == msmWindowModal
    check session.window.clickModalButton("Cancel")
    check frontend.application.modalSession().isNil
    check not frontend.window.isClosed
    check frontend.editorView.editor.tabs()[0].modified

    require frontend.editorView.editor.handleKey("i")
    require frontend.editorView.editor.mode() == KosmoEditorMode.Insert
    check frontend.clickSelectedTabClose()
    check frontend.application.modalSession().window.clickModalButton("Discard")
    check frontend.application.modalSession().isNil
    check not frontend.window.isClosed
    var modifiedFileStillOpen = false
    for tab in frontend.editorView.editor.tabs():
      if tab.filePath.isSome and tab.filePath.get == path:
        modifiedFileStillOpen = true
    check not modifiedFileStillOpen
    check readFile(path) == "original"
    require frontend.documentTabs.len == 1
    check frontend.documentTabs.selectedDocumentTabIdentifier != originalIdentifier
    check "original" notin frontend.editorView.displayedGridText()
    require frontend.editorView.editor.tabs().len == 1
    let replacement = frontend.editorView.editor.tabs()[0]
    check replacement.filePath.isNone
    check frontend.editorView.editor.bufferText(replacement.id) == some("")
    let editorHasFocus = frontend.window.firstResponder() == frontend.editorView
    check editorHasFocus
    frontend.window.typeNativeText("ireplacement")
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    check frontend.editorView.editor.bufferText(replacement.id) == some("replacement")

  test "discarding a modified middle tab in insert mode selects its next tab":
    let
      root = createTempDir("merenda-kosmo-discard-middle-", "")
      frontend = newKosmoApplication(
        newApplication("Kosmo Discard Middle Tab"), root, monitorsGitStatus = false
      )
    defer:
      frontend.close()
      removeDir(root)
    for name in ["first", "middle", "next", "last"]:
      let path = root / (name & ".txt")
      writeFile(path, name)
      require frontend.openPath(path)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let models = frontend.documentTabs.documentTabModels()
    require models.len == 4
    require frontend.documentTabs.selectDocumentTabWithIdentifier(models[1].identifier)
    require frontend.editorView.editor.handleKey("i")
    require frontend.editorView.editor.handleTextInput("modified ")
    require frontend.editorView.editor.mode() == KosmoEditorMode.Insert
    frontend.editorView.refresh()
    check frontend.clickSelectedTabClose()
    require not frontend.application.modalSession().isNil
    check frontend.application.modalSession().window.clickModalButton("Discard")
    check frontend.application.modalSession().isNil
    check frontend.documentTabs.len == 3
    check frontend.documentTabs.selectedDocumentTabIdentifier == models[2].identifier
    check "next" in frontend.editorView.displayedGridText()
    check "modified middle" notin frontend.editorView.displayedGridText()
    check readFile(root / "middle.txt") == "middle"

  test "close window confirms before discarding modified files":
    let
      root = createTempDir("merenda-kosmo-close-window-confirm-", "")
      path = root / "modified.txt"
      frontend = newKosmoApplication(
        newApplication("Kosmo Close Window Confirmation Test"),
        root,
        monitorsGitStatus = false,
      )
    writeFile(path, "original")
    defer:
      frontend.close()
      removeFile(path)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.openPath(path)
    require frontend.window.makeFirstResponder(frontend.editorView)
    require frontend.editorView.editor.handleKey("i")
    require frontend.editorView.editor.handleTextInput("!")
    require frontend.editorView.editor.handleKey("Esc")
    require frontend.editorView.editor.tabs()[0].modified

    check frontend.window.dispatchKeyDown(
      KeyEvent(
        key: keyW, keyCode: keyW.ord, modifiers: shortcutModifiers() + {nimkit.kmShift}
      )
    )
    let session = frontend.application.modalSession()
    require not session.isNil
    check session.window.title == "Unsaved Changes"
    check session.window.clickModalButton("Cancel")
    check frontend.application.modalSession().isNil
    check not frontend.window.isClosed

    check frontend.window.dispatchKeyDown(
      KeyEvent(
        key: keyW, keyCode: keyW.ord, modifiers: shortcutModifiers() + {nimkit.kmShift}
      )
    )
    check frontend.application.modalSession().window.clickModalButton("Discard")
    check frontend.application.modalSession().isNil
    check frontend.window.isClosed

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
    discard frontend.window.animationScheduler().tick(140.ms)
    check preview.scrollView().contentOffset().y > beforeNavigation

    check frontend.window.pressControlKey(keyW)
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    let afterEscape = preview.scrollView().contentOffset().y
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord)
    )
    discard frontend.window.animationScheduler().tick(140.ms)
    check preview.scrollView().contentOffset().y > afterEscape

    let afterCancelledNavigation = preview.scrollView().contentOffset().y
    check frontend.window.pressControlKey(keyW)
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord)
    )
    discard frontend.window.animationScheduler().tick(140.ms)
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
