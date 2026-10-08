import std/[os, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

proc keyEvent(key: Key, modifiers: set[nimkit.KeyModifier] = {}, text = ""): KeyEvent =
  KeyEvent(key: key, keyCode: key.ord, modifiers: modifiers, text: text)

proc controlKey(key: Key): KeyEvent =
  keyEvent(key, {nimkit.kmControl})

func terminalIsFocused(window: Window, terminal: KosmoTerminalView): bool =
  window.firstResponder() == Responder(terminal)

proc terminalDocument(identifier: string): KosmoPaneDocument =
  let terminal = newKosmoTerminalView()
  newKosmoPaneDocument(
    identifier,
    "Terminal",
    terminal,
    onClose = proc(document: KosmoPaneDocument): bool =
      discard document
      terminal.close()
      true,
    onDuplicate = proc(document: KosmoPaneDocument): KosmoPaneDocument =
      terminalDocument(document.identifier & ".copy"),
  )

suite "Kosmo terminal input routing":
  test "hybrid pane chords include Control aliases and arrows":
    for entry in [
      (keyV, kpcSplitRight),
      (keyS, kpcSplitBelow),
      (keyN, kpcNewBelow),
      (keyW, kpcFocusNext),
      (keyH, kpcFocusLeft),
      (keyJ, kpcFocusBelow),
      (keyK, kpcFocusAbove),
      (keyL, kpcFocusRight),
      (keyC, kpcClose),
      (keyArrowLeft, kpcFocusLeft),
      (keyArrowDown, kpcFocusBelow),
      (keyArrowUp, kpcFocusAbove),
      (keyArrowRight, kpcFocusRight),
    ]:
      for modifiers in [{}, {nimkit.kmControl}]:
        var state: TerminalShortcutState
        check state.routeTerminalKey(controlKey(keyW), KosmoTerminalInputPolicy.Hybrid).kind ==
          tkrConsume
        let route = state.routeTerminalKey(
          keyEvent(entry[0], modifiers), KosmoTerminalInputPolicy.Hybrid
        )
        check route.kind == tkrPane
        check route.command == entry[1]
        check route.keys.len == 0

  test "unclaimed chords are replayed intact and Escape cancels prefixes":
    var state: TerminalShortcutState
    let prefix = controlKey(keyW)
    discard state.routeTerminalKey(prefix, KosmoTerminalInputPolicy.Hybrid)
    let unknown = controlKey(keyQ)
    let route = state.routeTerminalKey(unknown, KosmoTerminalInputPolicy.Hybrid)
    check route.kind == tkrRaw
    check route.keys == @[prefix, unknown]
    discard state.routeTerminalKey(prefix, KosmoTerminalInputPolicy.Hybrid)
    check state.routeTerminalKey(keyEvent(keyEscape), KosmoTerminalInputPolicy.Hybrid).kind ==
      tkrConsume
    check state.routeTerminalKey(keyEvent(keyV), KosmoTerminalInputPolicy.Hybrid).kind ==
      tkrPass

  test "clipboard interception is the Windows and Linux default":
    for intercept in [true, false]:
      var state: TerminalShortcutState
      check state.routeTerminalKey(
        controlKey(keyC),
        KosmoTerminalInputPolicy.Hybrid,
        interceptClipboard = intercept,
      ).kind == (if intercept: tkrCopy else: tkrPass)
      check state.routeTerminalKey(
        controlKey(keyV),
        KosmoTerminalInputPolicy.Hybrid,
        interceptClipboard = intercept,
      ).kind == (if intercept: tkrPaste else: tkrPass)
      check state.routeTerminalKey(
        controlKey(keyX),
        KosmoTerminalInputPolicy.Hybrid,
        interceptClipboard = intercept,
      ).kind == tkrPass

  test "Ctrl-backslash quotes clipboard and complete pane shortcuts":
    var state: TerminalShortcutState
    let modes = TerminexModes()
    for key in [keyC, keyV, keyBackslash]:
      check state.routeTerminalKey(
        controlKey(keyBackslash), KosmoTerminalInputPolicy.Hybrid
      ).kind == tkrConsume
      let route = state.routeTerminalKey(
        controlKey(key), KosmoTerminalInputPolicy.Hybrid, interceptClipboard = true
      )
      check route.kind == tkrRaw
      check route.keys == @[controlKey(key)]
      check terminalKeyInput(route.keys[0], modes) == (
        case key
        of keyC: "\x03"
        of keyV: "\x16"
        else: "\x1c"
      )
    discard
      state.routeTerminalKey(controlKey(keyBackslash), KosmoTerminalInputPolicy.Hybrid)
    check state.routeTerminalKey(controlKey(keyW), KosmoTerminalInputPolicy.Hybrid).kind ==
      tkrRaw
    let continuation = state.routeTerminalKey(
      controlKey(keyV), KosmoTerminalInputPolicy.Hybrid, interceptClipboard = true
    )
    check continuation.kind == tkrRaw
    check continuation.keys == @[controlKey(keyV)]
    check state.routeTerminalKey(
      controlKey(keyV), KosmoTerminalInputPolicy.Hybrid, interceptClipboard = true
    ).kind == tkrPaste
    discard
      state.routeTerminalKey(controlKey(keyBackslash), KosmoTerminalInputPolicy.Hybrid)
    discard state.routeTerminalKey(controlKey(keyW), KosmoTerminalInputPolicy.Hybrid)
    check state.routeTerminalKey(controlKey(keyW), KosmoTerminalInputPolicy.Hybrid).kind ==
      tkrRaw
    check state.routeTerminalKey(
      controlKey(keyV), KosmoTerminalInputPolicy.Hybrid, interceptClipboard = true
    ).kind == tkrPaste

  test "raw mode sends Control keys including the quoting prefix":
    var state: TerminalShortcutState
    discard state.routeTerminalKey(controlKey(keyW), KosmoTerminalInputPolicy.Hybrid)
    for key in [keyW, keyC, keyV, keyBackslash]:
      let route = state.routeTerminalKey(
        controlKey(key), KosmoTerminalInputPolicy.Raw, interceptClipboard = true
      )
      check route.kind == tkrRaw
      check route.keys == @[controlKey(key)]
    check state.routeTerminalKey(keyEvent(keyV), KosmoTerminalInputPolicy.Hybrid).kind ==
      tkrPass

  test "terminal pane splitting navigation and text commits stay scoped":
    let
      app = newApplication("Hybrid Terminal Panes")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
      document = terminalDocument("test.hybrid-terminal")
      terminal = KosmoTerminalView(document.contentView)
    defer:
      frontend.close()
      frontend.window.close()
    app.addWindow(frontend.window)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 1000, 700)
    require frontend.openDocument(document)
    # A single document duplicates on split; multiple tabs move the selected tab.
    require frontend.documentTabs.closeDocumentTabAtIndex(0)
    require frontend.documentTabs.len == 1
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.window.terminalIsFocused(terminal)
    require frontend.window.dispatchKeyDown(controlKey(keyW))
    require frontend.window.dispatchKeyDown(keyEvent(keyV, text = "v"))
    check frontend.editorGroups().len == 2
    frontend.contentView.layoutSubtreeIfNeeded()
    let second = frontend.window.firstResponder()
    require second of KosmoTerminalView
    check not frontend.window.terminalIsFocused(terminal)
    # The native text commit for a consumed continuation must not reach the new pane.
    check frontend.window.dispatchTextInput("v")
    require frontend.window.dispatchKeyDown(controlKey(keyW))
    require frontend.window.dispatchKeyDown(keyEvent(keyArrowLeft))
    check frontend.window.terminalIsFocused(terminal)
    require frontend.window.dispatchKeyDown(controlKey(keyBackslash))
    require frontend.window.dispatchKeyDown(controlKey(keyW))
    require frontend.window.dispatchKeyDown(keyEvent(keyV, text = "v"))
    check frontend.editorGroups().len == 2
    check frontend.window.terminalIsFocused(terminal)

  test "focused raw terminals beat configured window shortcut prefixes":
    let
      frontend = newKosmoApplication(
        newApplication("Raw Prefix Priority"), monitorsGitStatus = false
      )
      terminal = newKosmoTerminalView()
    defer:
      terminal.close()
      frontend.close()
      frontend.window.close()
    frontend.window.setContentView(frontend.contentView)
    require frontend.openDocument(
      newKosmoPaneDocument("raw-terminal", "Terminal", terminal)
    )
    frontend.terminalInputPolicy = KosmoTerminalInputPolicy.Raw
    var bindings = frontend.window.keyBindings()
    discard bindings.remove(initKeyStroke(keyW, {nimkit.kmControl}))
    bindings.add(
      initKeySequence([initKeyStroke(keyW, {nimkit.kmControl}), initKeyStroke(keyV)]),
      actionSelector(KosmoSplitVerticalAction),
    )
    frontend.window.setKeyBindings(bindings)
    require frontend.window.dispatchKeyDown(controlKey(keyW))
    discard frontend.window.dispatchKeyDown(keyEvent(keyV, text = "v"))
    check frontend.editorGroups().len == 1
    check frontend.window.terminalIsFocused(terminal)

  test "focus and policy changes clear unfinished terminal chords":
    let
      frontend = newKosmoApplication(
        newApplication("Terminal Prefix Reset"), monitorsGitStatus = false
      )
      document = terminalDocument("reset-terminal")
      terminal = KosmoTerminalView(document.contentView)
    defer:
      frontend.close()
      frontend.window.close()
    frontend.window.setContentView(frontend.contentView)
    require frontend.openDocument(document)
    require frontend.window.dispatchKeyDown(controlKey(keyW))
    require frontend.window.makeFirstResponder(frontend.editorView)
    require frontend.window.makeFirstResponder(terminal)
    discard frontend.window.dispatchKeyDown(keyEvent(keyV, text = "v"))
    check frontend.editorGroups().len == 1
    frontend.window.setKeyWindow(true)
    require frontend.window.dispatchKeyDown(controlKey(keyW))
    frontend.window.setKeyWindow(false)
    frontend.window.setKeyWindow(true)
    discard frontend.window.dispatchKeyDown(keyEvent(keyV, text = "v"))
    check frontend.editorGroups().len == 1
    require frontend.window.dispatchKeyDown(controlKey(keyW))
    frontend.terminalInputPolicy = KosmoTerminalInputPolicy.Raw
    frontend.terminalInputPolicy = KosmoTerminalInputPolicy.Hybrid
    discard frontend.window.dispatchKeyDown(keyEvent(keyV, text = "v"))
    check frontend.editorGroups().len == 1

  test "settings persist terminal policy across windows and new documents":
    let
      root = createTempDir("kosmo-terminal-policy-", "")
      path = root / "config.json"
      manager =
        newKosmoWindowManager(newApplication("Terminal Policy"), configPath = path)
      first = newKosmoApplication(manager, monitorsGitStatus = false)
      second = newKosmoApplication(manager, monitorsGitStatus = false)
      terminal = newKosmoTerminalView()
    defer:
      terminal.close()
      manager.close()
      removeDir(root)
    require first.openDocument(
      newKosmoPaneDocument("settings-terminal", "Terminal", terminal)
    )
    check first.terminalInputPolicy() == KosmoTerminalInputPolicy.Hybrid
    require first.showSettings()
    let control = first.settingsWindow().contentView().viewWithIdentifier(
        KosmoTerminalInputPolicyIdentifier
      )
    require control of ComboBox
    ComboBox(control).activateItemAtIndex(1)
    check first.terminalInputPolicy() == KosmoTerminalInputPolicy.Raw
    check second.terminalInputPolicy() == KosmoTerminalInputPolicy.Raw
    check terminal.terminalInputPolicy() == KosmoTerminalInputPolicy.Raw
    check loadKosmoConfig(path).terminalInput == "raw"
    let reloaded = newKosmoWindowManager(
      newApplication("Reloaded Terminal Policy"), configPath = path
    )
    defer:
      reloaded.close()
    check newKosmoApplication(reloaded, monitorsGitStatus = false).terminalInputPolicy() ==
      KosmoTerminalInputPolicy.Raw
    let third = newKosmoApplication(manager, monitorsGitStatus = false)
    let futureTerminal = newKosmoTerminalView()
    defer:
      futureTerminal.close()
    require third.openDocument(
      newKosmoPaneDocument("future-terminal", "Terminal", futureTerminal)
    )
    check futureTerminal.terminalInputPolicy() == KosmoTerminalInputPolicy.Raw
    ComboBox(control).activateItemAtIndex(0)
    check futureTerminal.terminalInputPolicy() == KosmoTerminalInputPolicy.Hybrid
    check loadKosmoConfig(path).terminalInput == "hybrid"
