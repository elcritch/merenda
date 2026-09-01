## Synthetic user-input coverage for Kosmo's numbered panel shortcuts.
import std/[os, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

proc commandNumberEvent(number: range[1 .. 8]): KeyEvent =
  let key = Key(key1.ord + number - 1)
  KeyEvent(key: key, keyCode: key.ord, modifiers: shortcutModifiers())

proc presentSyntheticWindow(app: Application, frontend: KosmoApplication) =
  app.addWindow(frontend.window)
  frontend.window.setContentView(frontend.contentView)
  frontend.contentView.layoutSubtreeIfNeeded()
  doAssert frontend.window.makeFirstResponder(frontend.editorView)
  app.activateWindow(frontend.window)

proc firstResponderIs(window: Window, expected: Responder): bool =
  window.firstResponder == expected

suite "Kosmo synthetic panel shortcuts":
  test "native primary-1 focuses the file browser in the focused project window":
    let
      firstRoot = createTempDir("merenda-kosmo-panel-first-", "")
      secondRoot = createTempDir("merenda-kosmo-panel-second-", "")
      app = newApplication("Kosmo Panel Focus Test")
      manager = newKosmoWindowManager(app)
      first = newKosmoApplication(manager, firstRoot)
      second = newKosmoApplication(manager, secondRoot)
    defer:
      manager.close()
      removeDir(firstRoot)
      removeDir(secondRoot)
    require not first.isNil
    require not second.isNil
    app.presentSyntheticWindow(first)
    app.presentSyntheticWindow(second)
    check first.window.firstResponderIs(first.editorView)
    check second.window.firstResponderIs(second.editorView)

    first.window.dispatchHostFocusChanged(true)
    check app.performMenuKeyEquivalent(commandNumberEvent(1))

    check first.window.firstResponderIs(first.fileTree)
    check second.window.firstResponderIs(second.editorView)

  test "native primary-2 focuses the first editor in the focused project window":
    let
      firstRoot = createTempDir("merenda-kosmo-editor-first-", "")
      secondRoot = createTempDir("merenda-kosmo-editor-second-", "")
      app = newApplication("Kosmo Editor Focus Test")
      manager = newKosmoWindowManager(app)
      first = newKosmoApplication(manager, firstRoot)
      second = newKosmoApplication(manager, secondRoot)
    defer:
      manager.close()
      removeDir(firstRoot)
      removeDir(secondRoot)
    require not first.isNil
    require not second.isNil
    app.presentSyntheticWindow(first)
    app.presentSyntheticWindow(second)
    check first.showFileExplorer()
    check first.window.firstResponderIs(first.fileTree)

    first.window.dispatchHostFocusChanged(true)
    check app.performMenuKeyEquivalent(commandNumberEvent(2))

    check first.window.firstResponderIs(first.editorView)
    check second.window.firstResponderIs(second.editorView)
