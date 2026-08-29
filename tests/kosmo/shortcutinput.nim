import std/[os, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

proc pressControlKey(window: Window, key: Key): bool =
  window.dispatchKeyDown(KeyEvent(key: key, keyCode: key.ord, modifiers: {kmControl}))

suite "Kosmo synthetic shortcut input":
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

  test "Moe receives the full sequence when Kosmo does not own its continuation":
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
    let cursorBeforeSequence = frontend.editorView.editor.bufferCursor()

    check frontend.window.pressControlKey(keyW)
    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "n", key: keyN, keyCode: keyN.ord)
    )
    check frontend.editorView.editor.bufferCursor() == cursorBeforeSequence

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
