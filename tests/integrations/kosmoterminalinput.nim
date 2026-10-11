## Hybrid terminal routing against a live PTY, with bounded readiness and teardown.

import std/[monotimes, os, strutils, times, unittest]
import sigils/threads
import merenda/nimkit
import merenda/kosmo/kosmo
import ../support/terminalhelpers

proc waitForTerminalText(view: TerminalView, text: string): bool =
  let deadline = getMonoTime() + initDuration(seconds = 10)
  while getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    discard view.poll()
    if text in view.session().screen().plainText().splitWhitespace().join(" "):
      return true
    sleep(1)

suite "Kosmo terminal shortcut PTY input":
  when defined(posix):
    test "editor pane shortcuts do not leak text into the destination PTY":
      let
        session = spawnTerminalViewSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf 'READY\\n'; dd bs=1 count=2 2>/dev/null | od -An -tx1"
          ),
          columns = 80,
          rows = 4,
        )
        terminal = newKosmoTerminalView(session, frame = rect(0, 0, 800, 160))
        frontend = newKosmoApplication(
          newApplication("Editor to Terminal Shortcuts"), monitorsGitStatus = false
        )
        window = frontend.window
      defer:
        frontend.close()
        terminal.close()
        session.waitForCommands()
        window.close()
      window.setContentView(frontend.contentView)
      frontend.contentView.frame = rect(0, 0, 1000, 700)
      frontend.contentView.layoutSubtreeIfNeeded()
      require terminal.waitForTerminalText("READY")
      require frontend.openDocument(
        newKosmoPaneDocument("shortcut-terminal", "Terminal", terminal)
      )
      let prefix = KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
      require window.dispatchKeyDown(prefix)
      require window.dispatchKeyDown(KeyEvent(key: keyV, keyCode: keyV.ord))
      frontend.contentView.layoutSubtreeIfNeeded()
      let groups = frontend.editorGroups()
      require groups.len == 2
      for text in ["l", ""]:
        require window.makeFirstResponder(groups[0].editorView)
        require window.dispatchKeyDown(prefix)
        require window.dispatchKeyDown(
          KeyEvent(key: keyL, keyCode: keyL.ord, text: text)
        )
        let terminalFocused = window.firstResponder() == Responder(terminal)
        require terminalFocused
        require window.dispatchTextInput(if text.len > 0: text else: "λ")
      for key in [keyX, keyZ]:
        discard window.dispatchKeyDown(KeyEvent(key: key, keyCode: key.ord))
        require window.dispatchTextInput(if key == keyX: "x" else: "z")
      # Only the two ordinary characters should reach the PTY: no l or λ.
      require terminal.waitForTerminalText("78 7a")

    test "quoted and raw shortcuts reach the PTY exactly once":
      let
        session = spawnTerminalViewSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf 'READY\\n'; dd bs=1 count=8 2>/dev/null | od -An -tx1"
          ),
          columns = 80,
          rows = 4,
        )
        terminal = newKosmoTerminalView(session, frame = rect(0, 0, 800, 160))
        window = newWindow("Quoted Terminal Shortcuts", frame = rect(0, 0, 800, 160))
      defer:
        terminal.close()
        session.waitForCommands()
        window.close()
      var paneCommands: seq[KosmoPaneCommand]
      terminal.paneCommandHandler = proc(command: KosmoPaneCommand): bool =
        paneCommands.add command
        true
      window.setContentView(terminal)
      require window.makeFirstResponder(terminal)
      require terminal.waitForTerminalText("READY")
      let control = proc(key: Key): KeyEvent =
        KeyEvent(key: key, keyCode: key.ord, modifiers: {kmControl})
      require window.dispatchKeyDown(control(keyW))
      require window.dispatchKeyDown(KeyEvent(key: keyV, keyCode: keyV.ord))
      # Native physical events omit text; the commit can follow a different layout.
      require window.dispatchTextInput("ν")
      check paneCommands == @[kpcSplitRight]
      for key in [keyC, keyV, keyW]:
        require window.dispatchKeyDown(control(keyBackslash))
        require window.dispatchKeyDown(control(key))
      require window.dispatchKeyDown(control(keyV))
      terminal.terminalInputPolicy = KosmoTerminalInputPolicy.Raw
      for key in [keyBackslash, keyW, keyC, keyV]:
        require window.dispatchKeyDown(control(key))
      require terminal.waitForTerminalText("03 16 17 16 1c 17 03 16")
      check paneCommands == @[kpcSplitRight]
