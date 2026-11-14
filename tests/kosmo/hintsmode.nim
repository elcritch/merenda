## Hint mode matching, labels, overlay interaction, and pane dispatch.
import std/[monotimes, os, strutils, tempfiles, times, unittest]

import sigils/threads
import ../support/terminalhelpers
import fixtures/ui
import merenda/nimkit
import merenda/kosmo/kosmo
import merenda/kosmo/hintsmode
from merenda/nimkit/foundation/mainthreadwork import drainMainThreadWork

proc labelEvent(value: char, text = $value): KeyEvent =
  let key =
    if value in 'a' .. 'z':
      Key(ord(keyA) + ord(value) - ord('a'))
    elif value in '1' .. '9':
      Key(ord(key1) + ord(value) - ord('1'))
    elif value == '0':
      key0
    else:
      keyUnknown
  KeyEvent(key: key, keyCode: key.ord, text: text)

proc f6Event(modifiers: set[nimkit.KeyModifier] = {}): KeyEvent =
  KeyEvent(key: keyF6, keyCode: keyF6.ord, modifiers: modifiers)

proc escapeEvent(): KeyEvent =
  KeyEvent(key: keyEscape, keyCode: keyEscape.ord)

proc hintPaths(kind: KosmoHintKind, text: string, workingDirectory = ""): seq[string] =
  for candidate in kind.kosmoHintSpans(text, workingDirectory):
    result.add candidate.text

proc presentSyntheticWindow(app: Application, frontend: KosmoApplication) =
  app.addWindow(frontend.window)
  frontend.window.setContentView(frontend.contentView)
  frontend.contentView.frame = rect(0, 0, 900, 600)
  frontend.contentView.layoutSubtreeIfNeeded()

suite "Kosmo hint mode":
  test "link hints stop at punctuation, quotes, and brackets":
    check hintPaths(khkLink, "go to https://example.com/a, now") ==
      @["https://example.com/a"]
    check hintPaths(khkLink, "(see https://example.com/x)") == @[
      "https://example.com/x"
    ]
    check hintPaths(khkLink, "https://en.wikipedia.org/wiki/Foo_(bar)") ==
      @["https://en.wikipedia.org/wiki/Foo_(bar)"]
    check hintPaths(khkLink, "<https://example.com/autolink>") ==
      @["https://example.com/autolink"]
    check hintPaths(khkLink, "xhttps://example.com/embedded").len == 0
    check hintPaths(khkLink, "HTTP://EXAMPLE.COM/Case").len == 1
    check hintPaths(khkLink, "ftp://files.example.com/x").len == 1
    check hintPaths(khkLink, "gemini://gemini.example.net/page").len == 1
    check hintPaths(khkLink, "no urls here").len == 0
    check hintPaths(khkLink, "https://a").len == 0

  test "path hints keep locations and resolve existing files":
    let root = createTempDir("kosmo-hints-", "")
    defer:
      removeDir(root)
    let source = root / "src" / "answer.nim"
    createDir(source.parentDir())
    writeFile(source, "let answer = 42\n")
    writeFile(root / "answer.nim", "let top = 1\n")
    check hintPaths(khkPath, "open " & source, root) == @[source]
    check hintPaths(khkPath, "review " & source & ":12", root) == @[source & ":12"]
    let nimLocations = "fails at " & source & "(12, 5) today"
    let matches = khkPath.kosmoHintSpans(nimLocations, root)
    require matches.len == 1
    check matches[0].text == source & "(12, 5)"
    require matches[0].fileLocation.isSome
    check matches[0].fileLocation.get().path == source
    check matches[0].fileLocation.get().line == 12
    check matches[0].fileLocation.get().column == 5
    check hintPaths(khkPath, "(see " & source & ")", root) == @[source]
    check hintPaths(khkPath, "missing/file/that/exists/not.nim", root).len == 0
    check hintPaths(khkPath, "and/or", root).len == 0
    check hintPaths(khkPath, "review answer.nim there", root) == @["answer.nim"]

  test "word and hash hints follow Kitty's boundaries":
    check hintPaths(khkWord, "e.g. foo_bar/baz λος ok") ==
      @["e.g.", "foo_bar/baz", "λος"]
    check hintPaths(khkWord, "open https://example.com/x now") ==
      @["open", "https://example.com/x", "now"]
    check hintPaths(khkHash, "commit abcdef123456 deadbeef 1234567 abc123") ==
      @["abcdef123456", "deadbeef", "1234567"]
    check hintPaths(khkHash, "ABCDEF123456").len == 0

  test "hint labels stay prefix-free with the shortest at the bottom":
    check encodeHintLabel(0) == "0"
    check encodeHintLabel(9) == "9"
    check encodeHintLabel(35) == "z"
    check encodeHintLabel(36) == "00"
    check encodeHintLabel(37) == "01"
    for count in [1, 2, 5, 26, 27, 35, 36, 40, 80, 200]:
      var hints: seq[KosmoHint]
      for index in 0 ..< count:
        hints.add KosmoHint(text: $index)
      hints.assignKosmoHintLabels()
      let
        skip = max(1, (max(count, 2) - 2) div (KosmoHintAlphabet.len - 1))
        bottom = encodeHintLabel(skip)
      check hints[hints.high].label == bottom
      check hints[0].label.len >= bottom.len
      for first in hints:
        for second in hints:
          if first.text != second.text:
            check not first.label.startsWith(second.label)

  test "markdown hints copy through the overlay and restore focus":
    let
      root = createTempDir("kosmo-markdown-hints-", "")
      path = root / "hints.md"
      app = newApplication("Kosmo Markdown Hints")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
      pasteboard = generalPasteboard()
      previousClipboard = pasteboard.plainText()
    defer:
      discard pasteboard.setPlainText(previousClipboard)
      frontend.close()
      removeDir(root)
    # The URL is the bottom-most word, so it receives the shortest label.
    writeFile(path, "See <https://example.com/from-markdown>\n")
    app.presentSyntheticWindow(frontend)
    require frontend.openPath(path)
    let view = frontend.editorPane.markdownView
    require view.waitForMarkdownParsing()
    require view.waitForMarkdownLayout()
    require frontend.window.makeFirstResponder(view.textView())
    require frontend.window.dispatchKeyDown(f6Event({kmOption}))
    let textView = view.textView()
    check kosmoHintsVisible(textView)
    check frontend.window.firstResponder() != Responder(textView)
    require frontend.window.dispatchKeyDown(labelEvent('1'))
    check pasteboard.plainText() == "https://example.com/from-markdown"
    check not kosmoHintsVisible(textView)
    check frontend.window.firstResponder() == Responder(textView)

  test "editor word hints copy from the visible grid and skip chrome":
    let
      root = createTempDir("kosmo-editor-hints-", "")
      path = root / "hints.nim"
      app = newApplication("Kosmo Editor Hints")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
      pasteboard = generalPasteboard()
      previousClipboard = pasteboard.plainText()
    defer:
      discard pasteboard.setPlainText(previousClipboard)
      frontend.close()
      removeDir(root)
    writeFile(path, "alpha beta gamma\n")
    app.presentSyntheticWindow(frontend)
    require frontend.openPath(path)
    let editorView = frontend.editorView
    require frontend.window.makeFirstResponder(editorView)
    require frontend.window.dispatchKeyDown(f6Event({kmOption}))
    check kosmoHintsVisible(editorView)
    # Three words: the bottom word gets the shortest label.
    require frontend.window.dispatchKeyDown(labelEvent('1'))
    check pasteboard.plainText() == "gamma"
    check not kosmoHintsVisible(editorView)
    check frontend.window.firstResponder() == Responder(editorView)
    # Escape dismisses without activating anything.
    require frontend.window.dispatchKeyDown(f6Event({kmOption}))
    require frontend.window.dispatchKeyDown(escapeEvent())
    check not kosmoHintsVisible(editorView)
    check pasteboard.plainText() == "gamma"

  test "terminal word hints collect from the visible screen":
    let
      app = newApplication("Kosmo Terminal Hints")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
      session = newTerminalViewSession(columns = 40, rows = 5)
      terminal = newKosmoTerminalView(session, frame = rect(0, 0, 640, 160))
      pasteboard = generalPasteboard()
      previousClipboard = pasteboard.plainText()
    defer:
      discard pasteboard.setPlainText(previousClipboard)
      terminal.close()
      frontend.close()
    app.presentSyntheticWindow(frontend)
    require frontend.openDocument(
      newKosmoPaneDocument("kosmo.test.hints-terminal", "Terminal", terminal)
    )
    require frontend.window.firstResponder() == Responder(terminal)
    session.processOutput("build output alpha beta\r\n")
    discard terminal.pollSettled()
    require frontend.window.dispatchKeyDown(f6Event({kmOption}))
    check kosmoHintsVisible(terminal)
    require frontend.window.dispatchKeyDown(labelEvent('1'))
    check pasteboard.plainText() == "beta"
    check frontend.window.firstResponder() == Responder(terminal)

  test "terminal insert hints type the picked location into the terminal":
    let
      root = createTempDir("kh-insert-", "")
      source = root / "insert.nim"
      app = newApplication("Kosmo Terminal Insert")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
      session = newTerminalViewSession(columns = 40, rows = 5)
      terminal = newKosmoTerminalView(session, frame = rect(0, 0, 640, 160))
    defer:
      terminal.close()
      frontend.close()
      removeDir(root)
    writeFile(source, "let inserted = true\n")
    app.presentSyntheticWindow(frontend)
    require frontend.openDocument(
      newKosmoPaneDocument("kosmo.test.hints-insert", "Terminal", terminal)
    )
    require frontend.window.firstResponder() == Responder(terminal)
    session.processOutput(source & "\r\n")
    discard terminal.pollSettled()
    check terminal.lastInputError() == ""
    require frontend.window.dispatchKeyDown(f6Event({nimkit.kmControl, nimkit.kmShift}))
    check kosmoHintsVisible(terminal)
    require frontend.window.dispatchKeyDown(labelEvent('1', text = ""))
    check not kosmoHintsVisible(terminal)
    # The picked location was typed into the terminal's program input; the
    # idle test session has no program, so the write attempt is recorded.
    check terminal.lastInputError() != ""

  test "plain F6 falls through to the terminal without visible links":
    let
      app = newApplication("Kosmo F6 Fallthrough")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
      session = newTerminalViewSession(columns = 40, rows = 5)
      terminal = newKosmoTerminalView(session, frame = rect(0, 0, 640, 160))
    defer:
      terminal.close()
      frontend.close()
    app.presentSyntheticWindow(frontend)
    require frontend.openDocument(
      newKosmoPaneDocument("kosmo.test.hints-fallthrough", "Terminal", terminal)
    )
    require frontend.window.firstResponder() == Responder(terminal)
    # An htop-like screen: text, but no URLs, so the link hint command
    # declines and the key reaches the program instead of opening hint mode.
    session.processOutput("load average: 0.4 0.3 0.2\r\n")
    discard terminal.pollSettled()
    check terminal.lastInputError() == ""
    discard frontend.window.dispatchKeyDown(f6Event())
    check not kosmoHintsVisible(terminal)
    check terminal.lastInputError() != ""

  test "git diff hints collect from materialized file sections":
    let
      snapshot = parseGitDiff(
        "diff --git a/source.nim b/source.nim\n@@ -0,0 +1,4 @@\n" &
          "+see https://example.com/diff-link\n+alpha beta gamma\n" &
          "+delta epsilon zeta\n+eta theta iota\n"
      )
      panel = newKosmoGitDiffPanel(snapshot)
      window = newWindow("Git diff hints", frame = rect(0, 0, 700, 280))
      pasteboard = generalPasteboard()
      previousClipboard = pasteboard.plainText()
    defer:
      discard pasteboard.setPlainText(previousClipboard)
      panel.close()
      window.close()
    window.setContentView(panel)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    let code = panel.textViewForFile(0)
    require not code.isNil
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while getMonoTime() < deadline and code.frame().h <= 0:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      discard drainMainThreadWork()
      panel.layoutSubtreeIfNeeded()
      discard panel.buildRenders()
      sleep(1)
    require code.frame().h > 0
    # Hint markers only cover visible text, so scroll the section into view.
    panel.scrollView.contentOffset = initPoint(0, code.frame().minY)
    panel.layoutSubtreeIfNeeded()
    require performKosmoHintModeInChain(
      panel,
      KosmoHintModeArgs(
        kind: khkLink, action: khaCopy, activation: KosmoHintActivation()
      ),
    )
    check kosmoHintsVisible(panel.documentView)
    let overlay = panel.documentView.hintOverlayForView()
    let hints = overlay.presentedHints()
    require hints.len == 1
    check hints[0].text == "https://example.com/diff-link"
    require window.dispatchKeyDown(labelEvent('1'))
    check pasteboard.plainText() == "https://example.com/diff-link"
    check not kosmoHintsVisible(panel.documentView)

  test "github hints resolve paths against the repository root":
    let
      root = createTempDir("kosmo-github-hints-", "")
      source = root / "src" / "reported.nim"
      pasteboard = generalPasteboard()
      previousClipboard = pasteboard.plainText()
    defer:
      discard pasteboard.setPlainText(previousClipboard)
      removeDir(root)
    createDir(source.parentDir())
    writeFile(source, "let reported = true\n")
    var snapshot = GitHubSnapshot(rootPath: root)
    snapshot.items.add parseGitHubItems(
      "[{\"number\":9,\"title\":\"Crash\",\"body\":\"Fails at src/reported.nim:12 " &
        "after https://example.com/issue-link\"," &
        "\"url\":\"https://github.com/o/r/issues/9\",\"state\":\"OPEN\",\"author\":null," &
        "\"labels\":[],\"updatedAt\":\"2026-11-01T12:00:00Z\"}]",
      ghikIssue,
    )
    let
      panel = newKosmoGitHubPanel(snapshot)
      window = newWindow("GitHub hints", frame = rect(0, 0, 700, 600))
    defer:
      panel.close()
      window.close()
    window.setContentView(panel)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForGitHub()
    panel.markdownView.expandMarkdownHeadings()
    require panel.waitForGitHub()
    let textView = panel.markdownView.textView()
    require window.makeFirstResponder(textView)
    require performKosmoHintModeInChain(
      Responder(textView), KosmoHintModeArgs(kind: khkPath, action: khaCopy)
    )
    check kosmoHintsVisible(textView)
    let hints = textView.hintOverlayForView().presentedHints()
    require hints.len == 1
    # The location resolves against the panel's repository root, not the
    # process working directory.
    require hints[0].fileLocation.isSome
    check hints[0].fileLocation.get().path == source
    check hints[0].fileLocation.get().line == 12
    require window.dispatchKeyDown(labelEvent(hints[0].label[0], text = ""))
    check pasteboard.plainText() == "src/reported.nim:12"
    check not kosmoHintsVisible(textView)

  test "hint requests decline on responder chains without a hint surface":
    let window = newWindow("No hint surface", frame = rect(0, 0, 320, 200))
    defer:
      window.close()
    check not performKosmoHintModeInChain(
      window.firstResponder(), KosmoHintModeArgs(kind: khkLink, action: khaCopy)
    )

  test "insert requests decline on surfaces without terminal insertion":
    let
      root = createTempDir("kosmo-hints-decline-", "")
      path = root / "decline.nim"
      app = newApplication("Kosmo Hints Decline")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
    defer:
      frontend.close()
      removeDir(root)
    # Words are visible, but only the focused terminal attaches an insert hook,
    # so the editor must decline instead of showing markers that do nothing.
    writeFile(path, "alpha beta gamma\n")
    app.presentSyntheticWindow(frontend)
    require frontend.openPath(path)
    let editorView = frontend.editorView
    require frontend.window.makeFirstResponder(editorView)
    check not performKosmoHintModeInChain(
      editorView, KosmoHintModeArgs(kind: khkWord, action: khaInsert)
    )
    check not kosmoHintsVisible(editorView)

  test "hint keys select labels without event text like real backends":
    let
      root = createTempDir("kosmo-editor-hints-real-", "")
      path = root / "real.nim"
      app = newApplication("Kosmo Editor Real Backend Hints")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
      pasteboard = generalPasteboard()
      previousClipboard = pasteboard.plainText()
    defer:
      discard pasteboard.setPlainText(previousClipboard)
      frontend.close()
      removeDir(root)
    writeFile(path, "alpha beta gamma\n")
    app.presentSyntheticWindow(frontend)
    require frontend.openPath(path)
    let editorView = frontend.editorView
    require frontend.window.makeFirstResponder(editorView)
    require frontend.window.dispatchKeyDown(f6Event({kmOption}))
    check kosmoHintsVisible(editorView)
    # Real backends deliver key events without text and route the character
    # through a separate text commit.
    require frontend.window.dispatchKeyDown(labelEvent('1', text = ""))
    check pasteboard.plainText() == "gamma"
    check not kosmoHintsVisible(editorView)
    # The matching text commit must not reach the editor buffer.
    discard frontend.window.dispatchTextInput("1")
    var activeTab: KosmoTab
    for tab in frontend.editorView.editor.tabs():
      if tab.active:
        activeTab = tab
        break
    let buffer = frontend.editorView.editor.bufferText(activeTab.id)
    require buffer.isSome
    check "1" notin buffer.get()

  test "multi-character labels survive each typed character":
    let
      root = createTempDir("kosmo-editor-hints-multi-", "")
      path = root / "multi.nim"
      app = newApplication("Kosmo Editor Multi Hints")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
      pasteboard = generalPasteboard()
      previousClipboard = pasteboard.plainText()
    defer:
      discard pasteboard.setPlainText(previousClipboard)
      frontend.close()
      removeDir(root)
    var words: seq[string]
    for index in 1 .. 40:
      words.add "word" & $index
    writeFile(path, words.join(" ") & "\n")
    app.presentSyntheticWindow(frontend)
    require frontend.openPath(path)
    let editorView = frontend.editorView
    require frontend.window.makeFirstResponder(editorView)
    require frontend.window.dispatchKeyDown(f6Event({kmOption}))
    let overlay = editorView.hintOverlayForView()
    require not overlay.isNil
    var twoCharacter: KosmoHint
    for hint in overlay.presentedHints():
      if hint.label.len == 2:
        twoCharacter = hint
        break
    require twoCharacter.label.len == 2
    check twoCharacter.text.len > 0
    # Typing the first label character filters instead of ending the session.
    require frontend.window.dispatchKeyDown(
      labelEvent(twoCharacter.label[0], text = "")
    )
    check kosmoHintsVisible(editorView)
    require frontend.window.dispatchKeyDown(
      labelEvent(twoCharacter.label[1], text = "")
    )
    check pasteboard.plainText() == twoCharacter.text
    check not kosmoHintsVisible(editorView)
    check frontend.window.firstResponder() == Responder(editorView)

  test "declined hint requests report in the status bar":
    let
      root = createTempDir("kosmo-hint-decline-", "")
      path = root / "decline.txt"
      app = newApplication("Kosmo Hint Decline")
      frontend = newKosmoApplication(app, monitorsGitStatus = false)
    defer:
      frontend.close()
      removeDir(root)
    # The buffer holds a hash, but only far below the visible rows, so the
    # focused editor collects nothing and the request must not fail silently.
    writeFile(
      path, "no hashes up here\n" & repeat("filler\n", 300) & "deadbeef1234567\n"
    )
    app.presentSyntheticWindow(frontend)
    require frontend.openPath(path)
    let editorView = frontend.editorView
    require frontend.window.makeFirstResponder(editorView)
    require frontend.window.dispatchKeyDown(f6Event({nimkit.kmControl}))
    check not kosmoHintsVisible(editorView)
    # The fall-through key refreshes the editor, which composes the host
    # message into the status bar ahead of mode and file.
    checkpoint "hash decline status: " & frontend.statusLabel.text
    check frontend.statusLabel.text.startsWith("No visible hashes to copy")
    # Insertion needs a focused terminal, which the editor also declines.
    require frontend.window.dispatchKeyDown(f6Event({nimkit.kmControl, nimkit.kmShift}))
    check not kosmoHintsVisible(editorView)
    checkpoint "insert decline status: " & frontend.statusLabel.text
    check frontend.statusLabel.text.startsWith(
      "No visible paths to insert into the focused terminal"
    )

  test "workspace advertises URL opening on every platform":
    let app = newApplication("Kosmo Hint Workspace")
    check app.workspace().supports(wfOpenUrls)

  test "editor path hints survive Moe indentation guides":
    let
      root = createTempDir("kosmo-editor-hints-indent-", "")
      app = newApplication("Kosmo Editor Indent Hints")
      # Opening the temp root as the window's project makes the editor resolve
      # the buffer's relative paths against it, like compiler output in a
      # project.
      frontend = newKosmoApplication(app, root, monitorsGitStatus = false)
    defer:
      frontend.close()
      removeDir(root)
    # Moe renders the last leading space of an indented line as a vertical
    # indentation guide; glued paths must still resolve. The targets are
    # temporary files with traceable content instead of platform files such
    # as /etc/passwd, so hints resolve on macOS, Linux, and Windows alike.
    let
      targets = root / "targets"
      plain = targets / "plain.txt"
      indented = targets / "indented.txt"
      prefixed = targets / "prefixed.txt"
    createDir(targets)
    writeFile(plain, "plain hint target\n")
    writeFile(indented, "indented hint target\n")
    writeFile(prefixed, "prefixed hint target\n")
    writeFile(
      root / "indent.txt",
      "targets/plain.txt\n   targets/indented.txt\ntest: targets/prefixed.txt\n",
    )
    app.presentSyntheticWindow(frontend)
    require frontend.openPath(root / "indent.txt")
    let editorView = frontend.editorView
    require frontend.window.makeFirstResponder(editorView)
    require frontend.window.dispatchKeyDown(f6Event({nimkit.kmShift}))
    check kosmoHintsVisible(editorView)
    let overlay = editorView.hintOverlayForView()
    var texts: seq[string]
    for hint in overlay.presentedHints():
      texts.add hint.text
    check texts == @[
      "targets/plain.txt", "targets/indented.txt", "targets/prefixed.txt"
    ]
    var indentedHint: KosmoHint
    for hint in overlay.presentedHints():
      if hint.text == "targets/indented.txt":
        indentedHint = hint
    require indentedHint.label.len == 1
    require indentedHint.fileLocation.isSome
    check indentedHint.fileLocation.get().path == normalizedPath(absolutePath(indented))
    require frontend.window.dispatchKeyDown(
      labelEvent(indentedHint.label[0], text = "")
    )
    check not kosmoHintsVisible(editorView)
    # The picked location opened in a new editor tab holding the target's
    # traceable content.
    var opened = false
    for tab in frontend.editorView.editor.tabs():
      if tab.filePath == some(indentedHint.fileLocation.get().path):
        opened = true
        let buffer = frontend.editorView.editor.bufferText(tab.id)
        require buffer.isSome
        check "indented hint target" in buffer.get()
    check opened

  test "hint actions route through the surface activation":
    var inserted: seq[string]
    var activation = KosmoHintActivation(
      insertText: proc(text: string): bool =
        inserted.add text
        true
    )
    check runKosmoHintAction(KosmoHint(text: "src/foo.nim"), khaInsert, activation)
    check inserted == @["src/foo.nim"]
    activation.insertText = proc(text: string): bool =
      false
    check not runKosmoHintAction(KosmoHint(text: "src/foo.nim"), khaInsert, activation)
    check runKosmoHintAction(KosmoHint(text: "any snippet"), khaCopy, activation)
    check generalPasteboard().plainText() == "any snippet"

  test "hint commands register configurable shortcuts without conflicts":
    let table = initKosmoKeyBindings(defaultKosmoShortcutProfile())
    var bound: seq[CommandSelector]
    for binding in table.bindings:
      bound.add binding.selector
    for action in [
      KosmoHintOpenUrlAction, KosmoHintOpenPathAction, KosmoHintCopyWordAction,
      KosmoHintCopyHashAction, KosmoHintInsertAction,
    ]:
      check actionSelector(action) in bound
