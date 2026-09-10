## Process-level coverage for the shell environment used by Kosmo terminals.

import std/[monotimes, os, strutils, tempfiles, times, unittest]

import merenda/nimkit
import merenda/nimkit/text/monotextviews as monoTextViews
import merenda/kosmo/kosmo

const KosmoLoginPathMarker = "/kosmo/login-profile/bin"

proc pollUntilExit(
    session: TerminalViewSession, timeout = initDuration(seconds = 10)
): bool =
  let deadline = getMonoTime() + timeout
  while getMonoTime() < deadline:
    discard session.poll()
    if session.state() == tssExited:
      return true
    sleep(5)
  session.state() == tssExited

suite "Kosmo terminal environment":
  when defined(macosx):
    test "interactive shells inherit the login profile PATH":
      let
        root = createTempDir("merenda-kosmo-login-shell-", "")
        app = newApplication("Kosmo Login Shell Test")
        frontend = newKosmoApplication(app, monitorsGitStatus = false)
      defer:
        frontend.close()
        removeDir(root)

      writeFile(
        root / ".zprofile", "export PATH='" & KosmoLoginPathMarker & ":'$PATH\n"
      )
      writeFile(root / ".zshrc", "printf 'KOSMO_PATH=%s\\n' \"$PATH\"\nexit\n")

      require frontend.openTerminal(
        initTerminalSpawnOptions(
          shell = "/bin/zsh",
          workingDirectory = root,
          environment = [initTerminalEnvironmentVariable("ZDOTDIR", root)],
        )
      )
      require frontend.editorPane.contentView of KosmoTerminalView
      let session = KosmoTerminalView(frontend.editorPane.contentView).session()

      require session.pollUntilExit()
      check KosmoLoginPathMarker in session.screen().plainText().replace("\n", "")

suite "Terminal scrollback input":
  when defined(posix):
    test "Enter returns scrolled history to the live screen immediately":
      let
        session = newCompactTerminalSession(columns = 16, rows = 2, maxScrollback = 4)
        view = newTerminalView(session)
      defer:
        view.close()
      session.start(initTerminalSpawnOptions(command = "cat"))
      require session.running()
      session.processOutput("old\r\nmiddle\r\ncurrent")
      discard view.poll()
      view.selectTerminalRange(
        TerminalSelection(
          anchor: initTerminalPosition(0, 0), extent: initTerminalPosition(0, 3)
        )
      )
      view.clearSelection()
      require view.scrollPosition() > 0
      require view.performTerminalKeyEquivalent(
        KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
      )
      check view.scrollPosition() == 0
      check monoTextViews.stringValue(view).startsWith("middle")
