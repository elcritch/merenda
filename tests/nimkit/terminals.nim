import std/[monotimes, os, sequtils, strutils, tempfiles, times, unittest]

import terminex

import sigils/core

import merenda/nimkit/accessibility/accessibilityprotocols
import merenda/nimkit/app/[animations, application, pasteboards, windows]
import merenda/nimkit/foundation/[events, selectors, types]
import merenda/nimkit/responder/responders
import merenda/nimkit/terminal/terminalviews
import merenda/nimkit/text/monotextviews
import merenda/nimkit/view/views

type TerminalInteractionSpy = ref object of Agent
  links: seq[string]
  notifications: seq[AccessibilityNotification]

type TerminalEditingFallback = ref object of Responder
  commands: seq[string]

protocol TerminalEditingFallbackCommands of TextEditingCommandProtocol:
  method insertNewline(fallback: TerminalEditingFallback, args: ActionArgs) =
    discard args
    fallback.commands.add "insertNewline"

  method deleteBackward(fallback: TerminalEditingFallback, args: ActionArgs) =
    discard args
    fallback.commands.add "deleteBackward"

  method deleteForward(fallback: TerminalEditingFallback, args: ActionArgs) =
    discard args
    fallback.commands.add "deleteForward"

proc rememberTerminalLink(spy: TerminalInteractionSpy, link: string) {.slot.} =
  spy.links.add link

proc rememberTerminalAccessibility(
    spy: TerminalInteractionSpy, notification: AccessibilityNotification
) {.slot.} =
  spy.notifications.add notification

proc feed(screen: var TerminexScreen, parser: var TerminexParser, value: string) =
  parser.feed(screen, value)

proc pollUntilExit(
    session: CompactTerminalSession[TerminexCell], timeout = initDuration(seconds = 3)
): bool =
  let deadline = getMonoTime() + timeout
  while session.running() and getMonoTime() < deadline:
    discard session.poll()
    if session.running():
      sleep(5)
  not session.running()

proc pollUntilText(
    session: CompactTerminalSession[TerminexCell],
    expected: string,
    timeout = initDuration(seconds = 3),
): bool =
  let deadline = getMonoTime() + timeout
  while getMonoTime() < deadline:
    discard session.poll()
    if expected in session.screen().plainText():
      return true
    sleep(5)

proc tickUntilNormalizedText(
    window: Window,
    view: TerminalView,
    expected: string,
    timeout = initDuration(seconds = 3),
): bool =
  let deadline = getMonoTime() + timeout
  while getMonoTime() < deadline:
    discard window.animationScheduler().tick(initDuration(milliseconds = 16))
    let rendered = view.stringValue().replace("\n", " ").splitWhitespace().join(" ")
    if expected in rendered:
      return true
    sleep(5)

proc terminalCellPoint(view: TerminalView, row, column: int): Point =
  let metrics = view.monoTextMetrics()
  view.pointToWindow(
    initPoint(
      view.padding() + metrics.cellWidth * (column.float32 + 0.5'f32),
      view.padding() + metrics.lineHeight * (row.float32 + 0.5'f32),
    )
  )

func normalizedTerminalOutput(session: CompactTerminalSession[TerminexCell]): string =
  session.screen().plainText().replace("\n", " ").splitWhitespace().join(" ")

func terminalLineText(screen: TerminexScreen, row: int): string =
  if row notin 0 ..< screen.rows:
    return
  for cell in screen.lineAt(row):
    if not cell.continuation:
      result.add(if cell.text.len > 0: cell.text else: " ")
  result = result.strip(leading = false, trailing = true, chars = {' '})

func currentTerminalLine(session: CompactTerminalSession[TerminexCell]): string =
  let screen = session.screen()
  screen.terminalLineText(screen.cursor.position.row)

func currentRenderedTerminalLine(view: TerminalView): string =
  let
    row = view.session().screenInfo().cursor.position.row
    lines = view.lines()
  if row in 0 ..< lines.len:
    result = lines[row].strip(leading = false, trailing = true, chars = {' '})

func renderedTerminalTail(view: TerminalView): string =
  let
    row = view.session().screenInfo().cursor.position.row
    lines = view.lines()
  for index in max(row, 0) ..< lines.len:
    result.add lines[index]

proc tickUntilCurrentLineContains(
    window: Window,
    view: TerminalView,
    expected: string,
    timeout = initDuration(seconds = 3),
): bool =
  let deadline = getMonoTime() + timeout
  while getMonoTime() < deadline:
    discard window.animationScheduler().tick(initDuration(milliseconds = 16))
    if expected in view.session().currentTerminalLine():
      return true
    sleep(5)

proc tickUntilCurrentLineAfterChange(
    window: Window,
    view: TerminalView,
    generation: uint64,
    expected: string,
    timeout = initDuration(seconds = 3),
): bool =
  let deadline = getMonoTime() + timeout
  while getMonoTime() < deadline:
    discard window.animationScheduler().tick(initDuration(milliseconds = 16))
    if view.session().screenInfo().generation != generation and
        view.session().currentTerminalLine() == expected:
      return true
    sleep(5)

suite "nimkit terminal screen and parser":
  test "screen starts with bounded dimensions and terminal defaults":
    let screen = initTerminalScreen(0, -1, maxScrollback = -4)

    check screen.columns == 1
    check screen.rows == 1
    check screen.maxScrollback == 0
    check screen.cursor.position == initTerminalPosition(0, 0)
    check screen.cursor.visible
    check screen.cursor.blinking
    check screen.cursor.shape == tcsBlock
    check screen.modes.autoWrap
    check screen.cellAt(0, 0) == initTerminalCell()

  test "printable text controls wrapping and scrollback":
    var
      screen = initTerminalScreen(5, 3, maxScrollback = 2)
      parser = initTerminalParser()

    screen.feed(parser, "ABCDE")
    check screen.cursor.position == initTerminalPosition(0, 4)
    screen.feed(parser, "F\r\nG\r\nH\r\nI")

    check screen.scrollbackCount == 2
    check screen.plainText() == "ABCDE\nF\nG\nH\nI"
    check screen.cursor.position == initTerminalPosition(2, 1)

  test "bounded scrollback retains newest lines in logical order":
    var
      screen = initTerminalScreen(8, 2, maxScrollback = 3)
      parser = initTerminalParser()

    screen.feed(parser, "zero\r\none\r\ntwo\r\nthree\r\nfour\r\nfive")

    let scrollback = toSeq(scrollbackLines(screen))
    check screen.scrollbackCount == 3
    check scrollback[0][0].text == "o"
    check scrollback[1][0].text == "t"
    check scrollback[1][1].text == "w"
    check scrollback[2][0].text == "t"
    check scrollback[2][1].text == "h"
    check screen.lineAtAbsolute(0)[0].text == "o"
    check screen.lineAtAbsolute(2)[0].text == "t"
    check screen.lineAtAbsolute(2)[1].text == "h"
    check screen.plainText() == "one\ntwo\nthree\nfour\nfive"

  test "carriage return line feed tab and backspace follow VT semantics":
    var
      screen = initTerminalScreen(12, 4)
      parser = initTerminalParser()

    screen.feed(parser, "abc\rZ\n\tQ\bR")

    check screen.cellAt(0, 0).text == "Z"
    check screen.cellAt(0, 1).text == "b"
    check screen.cellAt(1, 8).text == "R"
    check screen.cursor.position == initTerminalPosition(1, 9)
    check screen.plainText(includeScrollback = false).splitLines()[1] ==
      repeat(' ', 8) & "R"

  test "UTF-8 input is incremental and preserves wide and combining clusters":
    var
      screen = initTerminalScreen(8, 2)
      parser = initTerminalParser()

    screen.feed(parser, "A\xe6\x97")
    check screen.cellAt(0, 0).text == "A"
    check screen.cellAt(0, 1).text.len == 0

    screen.feed(parser, "\xa5e\xcc")
    screen.feed(parser, "\x81B")

    check screen.cellAt(0, 1).text == "日"
    check screen.cellAt(0, 2).continuation
    check screen.cellAt(0, 3).text == "e\xcc\x81"
    check screen.cellAt(0, 4).text == "B"
    check screen.cursor.position.column == 5

  test "invalid UTF-8 is replaced without swallowing following bytes":
    var
      screen = initTerminalScreen(10, 2)
      parser = initTerminalParser()

    screen.feed(parser, "\xc0A\xed\xa0\x80B")

    check screen.cellAt(0, 0).text == "\xef\xbf\xbd"
    check screen.cellAt(0, 1).text == "A"
    check screen.cellAt(0, 2).text == "\xef\xbf\xbd"
    check screen.cellAt(0, 3).text == "\xef\xbf\xbd"
    check screen.cellAt(0, 4).text == "\xef\xbf\xbd"
    check screen.cellAt(0, 5).text == "B"

  test "incremental CSI moves the cursor and edits cells":
    var
      screen = initTerminalScreen(10, 5)
      parser = initTerminalParser()

    screen.feed(parser, "0123456789\r\nabcdefghij")
    screen.feed(parser, "\x1b[2;")
    screen.feed(parser, "4H\x1b[2@XY\x1b[2P\x1b[3X")

    check screen.cursor.position == initTerminalPosition(1, 5)
    check screen.plainText(includeScrollback = false).splitLines()[0] == "0123456789"
    check screen.plainText(includeScrollback = false).splitLines()[1] == "abcXY"

    screen.feed(parser, "\x1b[5A\x1b[99C")
    check screen.cursor.position == initTerminalPosition(0, 9)

  test "erase operations clear requested line and display ranges":
    var
      screen = initTerminalScreen(6, 3)
      parser = initTerminalParser()

    screen.feed(parser, "AAAAAA\r\nBBBBBB\r\nCCCCCC\x1b[2;3H\x1b[1K")
    check screen.cellAt(1, 0).text.len == 0
    check screen.cellAt(1, 2).text.len == 0
    check screen.cellAt(1, 3).text == "B"

    screen.feed(parser, "\x1b[0J")
    check screen.cellAt(0, 0).text == "A"
    check screen.cellAt(1, 3).text.len == 0
    check screen.cellAt(2, 0).text.len == 0

    screen.feed(parser, "\x1b[3J")
    check screen.scrollbackCount == 0

  test "clearing scrollback preserves the live screen":
    var
      screen = initTerminalScreen(6, 2)
      parser = initTerminalParser()
    screen.feed(parser, "zero\r\none\r\ntwo")
    let visibleText = screen.plainText(includeScrollback = false)

    check screen.scrollbackCount == 1
    screen.clearScrollback()

    check screen.scrollbackCount == 0
    check screen.plainText(includeScrollback = false) == visibleText

  test "scroll regions and line insertion leave outside rows unchanged":
    var
      screen = initTerminalScreen(5, 5)
      parser = initTerminalParser()

    screen.feed(parser, "0\r\n1\r\n2\r\n3\r\n4")
    screen.feed(parser, "\x1b[2;4r\x1b[3;1H\x1b[L")

    check screen.cellAt(0, 0).text == "0"
    check screen.cellAt(1, 0).text == "1"
    check screen.cellAt(2, 0).text.len == 0
    check screen.cellAt(3, 0).text == "2"
    check screen.cellAt(4, 0).text == "4"

    screen.feed(parser, "\x1b[M")
    check screen.cellAt(2, 0).text == "2"
    check screen.cellAt(3, 0).text.len == 0
    check screen.scrollbackCount == 0

  test "graphic rendition supports attributes indexed and true colors":
    var
      screen = initTerminalScreen(8, 2)
      parser = initTerminalParser()

    screen.feed(parser, "\x1b[1;3;4;38;5;200;48;2;10;20;30mX\x1b[22;23;24;39;49mY")

    let first = screen.cellAt(0, 0)
    check taBold in first.style.attributes
    check taItalic in first.style.attributes
    check taUnderline in first.style.attributes
    check first.style.foreground == indexedTerminalColor(200)
    check first.style.background == rgbTerminalColor(10, 20, 30)

    let second = screen.cellAt(0, 1)
    check second.style.attributes == {}
    check second.style.foreground.kind == tckDefault
    check second.style.background.kind == tckDefault

  test "truncated extended colors do not become unrelated attributes":
    var
      screen = initTerminalScreen(4, 1)
      parser = initTerminalParser()

    screen.feed(parser, "\x1b[38;5mA\x1b[0;48;2;12;34mB")

    check screen.cellAt(0, 0).style.attributes == {}
    check screen.cellAt(0, 1).style.attributes == {}

  test "OSC metadata hyperlinks and clipboard requests terminate across chunks":
    var
      screen = initTerminalScreen(12, 2)
      parser = initTerminalParser()

    screen.feed(parser, "\x1b]2;Build output\x1b")
    screen.feed(parser, "\\\x1b]7;file:///tmp/project\x07")
    screen.feed(parser, "\x1b]8;id=docs;https://example.com\x07link\x1b]8;;\x07")
    screen.feed(parser, "\x1b]52;c;aGVsbG8=\x07")

    check screen.title == "Build output"
    check screen.currentDirectory == "file:///tmp/project"
    check screen.cellAt(0, 0).style.hyperlink == "https://example.com"
    check screen.cellAt(0, 4).style.hyperlink.len == 0
    check screen.clipboardText == "hello"
    check screen.clipboardRequestPending

  test "device queries queue replies for the session transport":
    var
      screen = initTerminalScreen(20, 10)
      parser = initTerminalParser()

    screen.feed(parser, "\x1b[4;7H\x1b[5n\x1b[6n\x1b[c\x1b[>c")

    check screen.pendingReplies() ==
      @["\x1b[0n", "\x1b[4;7R", "\x1b[?62;22c", "\x1b[>0;1;0c"]
    check screen.takePendingReplies().len == 4
    check screen.pendingReplies().len == 0

  test "private modes expose application input mouse paste and cursor state":
    var
      screen = initTerminalScreen(20, 5)
      parser = initTerminalParser()

    screen.feed(parser, "\x1b[?1;6;1003;1004;1006;1007;2004h\x1b[5 q\x1b[?25l")

    check screen.modes.applicationCursorKeys
    check screen.modes.origin
    check screen.modes.mouseTracking == tmtAny
    check screen.modes.mouseEncoding == tmeSgr
    check screen.modes.focusReporting
    check screen.modes.alternateScroll
    check screen.modes.bracketedPaste
    check screen.cursor.shape == tcsBar
    check screen.cursor.blinking
    check not screen.cursor.visible

    screen.feed(parser, "\x1b[?1;6;1003;1004;1006;1007;2004l\x1b[2 q\x1b[?25h")
    check not screen.modes.applicationCursorKeys
    check not screen.modes.origin
    check screen.modes.mouseTracking == tmtNone
    check screen.modes.mouseEncoding == tmeX10
    check not screen.modes.focusReporting
    check not screen.modes.alternateScroll
    check not screen.modes.bracketedPaste
    check screen.cursor.shape == tcsBlock
    check not screen.cursor.blinking
    check screen.cursor.visible

  test "alternate screen restores the primary contents and optional cursor":
    var
      screen = initTerminalScreen(10, 4)
      parser = initTerminalParser()

    screen.feed(parser, "primary\x1b[3;4H\x1b[?1049h")
    check screen.alternateScreen
    check screen.plainText() == ""
    screen.feed(parser, "alternate\x1b[?1049l")

    check not screen.alternateScreen
    check screen.plainText() == "primary"
    check screen.cursor.position == initTerminalPosition(2, 3)

  test "alternate screen overflow remains available in scrollback":
    var
      screen = initTerminalScreen(12, 3)
      parser = initTerminalParser()

    screen.feed(
      parser, "\x1b[?1049halternate-0\r\nalternate-1\r\nalternate-2\r\nalternate-3"
    )

    check screen.alternateScreen
    check screen.scrollbackCount == 1
    check screen.lineAtAbsolute(0)[0].text == "a"
    check screen.lineAtAbsolute(0)[10].text == "0"

    screen.feed(parser, "\x1b[?1049l")

    check not screen.alternateScreen
    check screen.scrollbackCount == 1
    check screen.lineAtAbsolute(0)[0].text == "a"
    check screen.lineAtAbsolute(0)[10].text == "0"

  test "save restore reset and resize keep cursor and wide-cell invariants":
    var
      screen = initTerminalScreen(8, 4)
      parser = initTerminalParser()

    screen.feed(parser, "A日\x1b7\x1b[4;8H\x1b8")
    check screen.cursor.position == initTerminalPosition(0, 3)

    screen.resize(2, 2)
    check screen.columns == 2
    check screen.rows == 2
    check screen.cellAt(0, 0).text == "A"
    check screen.cellAt(0, 1).text.len == 0
    check not screen.cellAt(0, 1).continuation

    screen.feed(parser, "\x1bc")
    check screen.plainText() == ""
    check screen.cursor.position == initTerminalPosition(0, 0)
    check screen.modes.autoWrap

  test "oversized control strings are bounded and recover to normal text":
    var
      screen = initTerminalScreen(20, 2)
      parser = initTerminalParser()

    screen.feed(parser, "\x1b[" & repeat('1', MaxTerminalCsiBytes + 2) & "Z")
    check parser.state == tpsGround
    screen.feed(parser, "ok")
    check screen.plainText().endsWith("ok")

    parser.reset()
    screen.feed(parser, "\x1b]2;" & repeat('x', MaxTerminalStringBytes + 2))
    check parser.state == tpsGround

  test "ignored DCS payload cannot leak printable bytes into the screen":
    var
      screen = initTerminalScreen(20, 2)
      parser = initTerminalParser()

    screen.feed(parser, "before\x1bP1;2|private payload\x1b\\after")

    check screen.plainText() == "beforeafter"

suite "nimkit terminal sessions":
  test "session can parse supplied output before starting a process":
    let session = newCompactTerminalSession(12, 2)

    session.processOutput("plain \x1b[32mgreen")

    check session.state == tssIdle
    check session.screen().plainText() == "plain green"
    check session.screen().cellAt(0, 6).style.foreground == indexedTerminalColor(2)
    expect TerminexSessionError:
      session.write("input")

  when defined(posix):
    test "PTY drains styled output and reports the child exit status":
      let session = spawnCompactTerminalSession(
        initTerminalSpawnOptions(command = "printf '\\033[31mred\\033[0m\\n'; exit 7"),
        columns = 20,
        rows = 4,
      )
      defer:
        session.close()

      check session.pollUntilExit()
      check session.state == tssExited
      check session.exitCode == 7
      check "red" in session.screen().plainText()
      check session.screen().cellAt(0, 0).style.foreground == indexedTerminalColor(1)

    test "PTY applies working directory environment and terminal size":
      let root = createTempDir("merenda-terminal-session-", "")
      defer:
        removeDir(root)
      let session = spawnCompactTerminalSession(
        initTerminalSpawnOptions(
          command =
            "printf '%s\\n%s\\n%s\\n' \"$(basename \"$PWD\")\" \"$TERM\" " &
            "\"$NIMKIT_TEST\"; stty size",
          workingDirectory = root,
          environment = [initTerminalEnvironmentVariable("NIMKIT_TEST", "ready")],
        ),
        columns = 80,
        rows = 7,
      )
      defer:
        session.close()

      check session.pollUntilExit()
      let output = session.screen().plainText()
      check root.extractFilename() in output
      check "xterm-256color" in output
      check "ready" in output
      check "7 80" in output

    test "PTY accepts interactive input without blocking the caller":
      let session = spawnCompactTerminalSession(
        initTerminalSpawnOptions(
          command = "IFS= read -r value; printf 'reply:%s' \"$value\""
        ),
        columns = 30,
        rows = 4,
      )
      defer:
        session.close()

      session.write("hello\r")
      check session.pollUntilText("reply:hello")
      check session.pollUntilExit()
      check session.exitCode == 0

    test "PTY resize reaches the child process":
      let session = spawnCompactTerminalSession(
        initTerminalSpawnOptions(command = "sleep 0.05; stty size"),
        columns = 10,
        rows = 3,
      )
      defer:
        session.close()

      session.resize(33, 7)
      check session.screen().columns == 33
      check session.screen().rows == 7
      check session.pollUntilExit()
      check "7 33" in session.screen().plainText()

    test "closing a live PTY reaps its owned child":
      let session = spawnCompactTerminalSession(
        initTerminalSpawnOptions(command = "sleep 30"), columns = 10, rows = 3
      )

      check session.running()
      session.close()
      check session.state == tssClosed
      check not session.running()
      session.close()
  else:
    test "unsupported platforms report a catchable spawn error":
      let session = newCompactTerminalSession()
      expect TerminexSessionError:
        session.start()
      check session.state == tssFailed

suite "nimkit terminal views":
  test "terminal cells map colors attributes and decorations into mono cells":
    var
      screen = initTerminalScreen(4, 1)
      parser = initTerminalParser()
    screen.feed(parser, "\x1b[1;2;3;4;9;53;38;5;196;48;2;10;20;30;58;2;1;2;3mX")

    let cell = terminalCellToMonoTextCell(
      screen.cellAt(0, 0), initTerminalPalette(), selected = true
    )

    check cell.text == "X"
    check cell.hasForegroundColor
    check cell.hasBackgroundColor
    check cell.backgroundColor == initTerminalPalette().selection
    check mttBold in cell.traits
    check mttFaint in cell.traits
    check mttItalic in cell.traits
    check mtdUnderline in cell.decorations
    check mtdStrikethrough in cell.decorations
    check mtdOverline in cell.decorations
    check cell.hasDecorationColor

  test "terminal key translation covers every supported keyboard input":
    let
      modes = initTerminalModes()
      specialInputs = [
        (keyEnter, "\r"),
        (keyBackspace, "\x7f"),
        (keyTab, "\t"),
        (keyEscape, "\x1b"),
        (keyArrowUp, "\x1b[A"),
        (keyArrowDown, "\x1b[B"),
        (keyArrowRight, "\x1b[C"),
        (keyArrowLeft, "\x1b[D"),
        (keyHome, "\x1b[H"),
        (keyEnd, "\x1b[F"),
        (keyInsert, "\x1b[2~"),
        (keyDelete, "\x1b[3~"),
        (keyPageUp, "\x1b[5~"),
        (keyPageDown, "\x1b[6~"),
      ]
      functionInputs = [
        "\x1bOP", "\x1bOQ", "\x1bOR", "\x1bOS", "\x1b[15~", "\x1b[17~", "\x1b[18~",
        "\x1b[19~", "\x1b[20~", "\x1b[21~", "\x1b[23~", "\x1b[24~", "\x1b[25~",
        "\x1b[26~", "\x1b[28~",
      ]

    for (key, expected) in specialInputs:
      check terminalKeyInput(KeyEvent(key: key), modes) == expected
    for key in keyA .. keyZ:
      let expected = $char(key.ord - keyA.ord + 1)
      check terminalKeyInput(KeyEvent(key: key, modifiers: {kmControl}), modes) ==
        expected
    for index, expected in functionInputs:
      let key = Key(keyF1.ord + index)
      check terminalKeyInput(KeyEvent(key: key), modes) == expected

    check terminalKeyInput(KeyEvent(key: keySpace, modifiers: {kmControl}), modes) ==
      "\x00"
    check terminalKeyInput(KeyEvent(key: key2, modifiers: {kmControl}), modes) == "\x00"
    check terminalKeyInput(KeyEvent(key: keyLeftBracket, modifiers: {kmControl}), modes) ==
      "\x1b"
    check terminalKeyInput(KeyEvent(key: keyBackslash, modifiers: {kmControl}), modes) ==
      "\x1c"
    check terminalKeyInput(
      KeyEvent(key: keyRightBracket, modifiers: {kmControl}), modes
    ) == "\x1d"
    check terminalKeyInput(KeyEvent(key: key6, modifiers: {kmControl}), modes) == "\x1e"
    check terminalKeyInput(KeyEvent(key: keyMinus, modifiers: {kmControl}), modes) ==
      "\x1f"
    check terminalKeyInput(KeyEvent(key: keyBackspace, modifiers: {kmControl}), modes) ==
      "\x7f"
    check terminalKeyInput(KeyEvent(key: keyTab, modifiers: {kmShift}), modes) ==
      "\x1b[Z"
    check terminalKeyInput(KeyEvent(text: "x", key: keyX, modifiers: {kmOption}), modes) ==
      "\x1bx"
    check terminalKeyInput(
      KeyEvent(text: "ƒ", key: keyF, modifiers: {kmOption}), modes
    ) == "\x1bf"
    check terminalKeyInput(
      KeyEvent(text: "∫", key: keyB, modifiers: {kmOption}), modes
    ) == "\x1bb"
    check terminalKeyInput(
      KeyEvent(text: "ƒ", key: keyF, modifiers: {kmOption}),
      modes,
      optionAsMeta = false,
    ).len == 0
    check terminalKeyInput(KeyEvent(key: keyF, modifiers: {kmControl, kmOption}), modes) ==
      "\x1b\x06"
    check terminalKeyInput(KeyEvent(text: "X", key: keyX, modifiers: {kmShift}), modes) ==
      "X"
    check terminalKeyInput(
      KeyEvent(text: "c", key: keyC, modifiers: {kmCommand}), modes
    ).len == 0
    check terminalKeyInput(KeyEvent(key: keyUnknown), modes).len == 0

    var applicationModes = modes
    applicationModes.applicationCursorKeys = true
    check terminalKeyInput(KeyEvent(key: keyArrowUp), applicationModes) == "\x1bOA"
    check terminalKeyInput(KeyEvent(key: keyArrowDown), applicationModes) == "\x1bOB"
    check terminalKeyInput(KeyEvent(key: keyArrowRight), applicationModes) == "\x1bOC"
    check terminalKeyInput(KeyEvent(key: keyArrowLeft), applicationModes) == "\x1bOD"
    check terminalKeyInput(KeyEvent(key: keyHome), applicationModes) == "\x1bOH"
    check terminalKeyInput(KeyEvent(key: keyEnd), applicationModes) == "\x1bOF"

  test "terminal clipboard shortcuts use platform conventions":
    when defined(macosx) or defined(macos):
      check terminalShortcutModifiers() == {kmCommand}
    else:
      check terminalShortcutModifiers() == {kmControl, kmShift}

  test "terminal links use the platform link modifier":
    when defined(macosx) or defined(macos):
      check terminalLinkModifiers() == {kmCommand}
    else:
      check terminalLinkModifiers() == {kmControl}

  test "view renders an idle session and resizes its screen to cell geometry":
    let
      session = newCompactTerminalSession(columns = 12, rows = 3)
      view = newTerminalView(session, frame = rect(0, 0, 240, 100))
    session.processOutput("plain \x1b[31mred")

    discard view.poll()
    check view.cellAt(0, 0).text == "p"
    check view.cellAt(0, 6).text == "r"
    check view.cellAt(0, 6).foregroundColor == view.palette().colors[1]

    let oldSize = (session.screen().columns, session.screen().rows)
    view.frame = rect(0, 0, 360, 160)
    view.resizeToFit()
    check session.screen().columns > oldSize[0]
    check session.screen().rows > oldSize[1]
    check view.lineCount == session.screen().rows
    check view.maxColumnCount == session.screen().columns

  test "terminal views use compact scrollback sessions":
    let view = newTerminalView(frame = rect(0, 0, 240, 100))
    let session: TerminalViewSession = view.session()
    check not session.isNil

  test "terminal views suppress the outer focus ring":
    let view = newTerminalView(frame = rect(0, 0, 240, 100))
    check view.focusRingType == frtNone
    check view.allowsLinkActivation
    check view.optionAsMeta
    view.optionAsMeta = false
    check not view.optionAsMeta

  test "window text and key dispatch reach an interactive child process":
    when defined(posix):
      let
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(
            command = "stty -echo; IFS= read -r value; printf 'reply:%s' \"$value\""
          ),
          columns = 30,
          rows = 4,
        )
        view = newTerminalView(session, frame = rect(0, 0, 360, 120))
        window = newWindow("Terminal input", frame = rect(0, 0, 360, 120))
      defer:
        view.close()
      window.setContentView(view)
      check window.makeFirstResponder(view)

      check window.dispatchTextInput("hello")
      check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
      check session.pollUntilText("reply:hello")
      discard view.poll()
      check "reply:hello" in view.stringValue()

  test "window dispatch sends navigation control keys and ordinary paste":
    when defined(posix):
      let
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo min 0 time 10; printf ready; " &
              "dd bs=1 count=64 2>/dev/null | od -An -tx1"
          ),
          columns = 50,
          rows = 4,
        )
        view = newTerminalView(session, frame = rect(0, 0, 500, 120))
        window = newWindow("Terminal keyboard", frame = rect(0, 0, 500, 120))
      defer:
        view.close()
      window.setContentView(view)
      check window.makeFirstResponder(view)
      check session.pollUntilText("ready")

      check window.dispatchTextInput("ab")
      check window.dispatchKeyDown(
        KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord)
      )
      check window.dispatchKeyDown(
        KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord)
      )
      check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
      check window.dispatchKeyDown(
        KeyEvent(key: keyTab, keyCode: keyTab.ord, modifiers: {kmShift})
      )
      check window.dispatchKeyDown(
        KeyEvent(key: keyC, keyCode: keyC.ord, modifiers: {kmControl})
      )
      check window.dispatchKeyDown(
        KeyEvent(key: keyL, keyCode: keyL.ord, modifiers: {kmControl})
      )
      check window.dispatchKeyDown(
        KeyEvent(text: "x", key: keyX, keyCode: keyX.ord, modifiers: {kmOption})
      )
      discard generalPasteboard().setPlainText("YZ")
      check window.dispatchKeyDown(
        KeyEvent(key: keyV, keyCode: keyV.ord, modifiers: terminalShortcutModifiers())
      )

      check session.pollUntilExit()
      check "61 62 7f 1b 5b 44 09 1b 5b 5a 03 0c 1b 78 59 5a" in
        session.normalizedTerminalOutput()

  test "terminal captures basic input and editing keys before application commands":
    when defined(posix):
      let
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf ready; " &
              "dd bs=1 count=11 2>/dev/null | od -An -tx1"
          ),
          columns = 60,
          rows = 4,
        )
        view = newTerminalView(session, frame = rect(0, 0, 600, 120))
        window = newWindow("Terminal basic input", frame = rect(0, 0, 600, 120))
        fallback = TerminalEditingFallback()
      defer:
        view.close()
      initResponder(fallback)
      discard fallback.withProtocol(TerminalEditingFallbackCommands)
      window.setNextResponder(fallback)
      window.setContentView(view)
      check window.makeFirstResponder(view)
      check session.pollUntilText("ready")

      check window.dispatchTextInput("abc")
      check window.dispatchKeyDown(
        KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
      )
      check window.dispatchKeyDown(
        KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord)
      )
      check window.dispatchKeyDown(
        KeyEvent(key: keyH, keyCode: keyH.ord, modifiers: {kmControl})
      )
      check window.dispatchKeyDown(KeyEvent(key: keyDelete, keyCode: keyDelete.ord))
      check window.dispatchKeyDown(
        KeyEvent(key: keyD, keyCode: keyD.ord, modifiers: {kmControl})
      )

      let expected = "61 62 63 0d 7f 08 1b 5b 33 7e 04"
      check window.tickUntilNormalizedText(view, expected)
      check fallback.commands.len == 0

  test "focus regain modifier release keeps terminal editing keys usable":
    when defined(posix):
      let
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf ready; " &
              "dd bs=1 count=6 2>/dev/null | od -An -tx1"
          ),
          columns = 50,
          rows = 4,
        )
        view = newTerminalView(session, frame = rect(0, 0, 500, 120))
        terminalWindow = newWindow("Detached terminal", frame = rect(0, 0, 500, 120))
        mainWindow = newWindow("Main window", frame = rect(0, 0, 500, 120))
        app = newApplication("Terminal modifier recovery")
      defer:
        view.close()

      terminalWindow.setContentView(view)
      mainWindow.setContentView(newView(frame = rect(0, 0, 500, 120)))
      app.addWindow(mainWindow)
      app.addWindow(terminalWindow)
      app.activateWindow(mainWindow)
      app.activateWindow(terminalWindow)
      check terminalWindow.makeFirstResponder(view)
      check session.pollUntilText("ready")

      # Model Cmd-Tab returning to this window while Command is still held.
      # The first modifier event received after focus returns is its release.
      check terminalWindow.dispatchFlagsChanged(
        KeyEvent(key: keyLeftCommand, keyCode: keyLeftCommand.ord, modifiers: {})
      )

      check terminalWindow.dispatchTextInput("ab")
      check terminalWindow.dispatchKeyDown(
        KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
      )
      check terminalWindow.dispatchKeyDown(
        KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord)
      )
      check terminalWindow.sendAction(insertNewline(), DynamicAgent(view))
      check terminalWindow.sendAction(deleteBackward(), DynamicAgent(view))

      check session.pollUntilExit()
      check "61 62 0d 7f 0d 7f" in session.normalizedTerminalOutput()

  when defined(posix) and not defined(windows):
    test "Bash receives every terminal input path exactly once":
      let bashPath = findExe("bash")
      if bashPath.len == 0:
        skip()
      else:
        let
          command =
            "export PS1='bash-input$ ' PS2='> ' HISTFILE=/dev/null " &
            "INPUTRC=/dev/null LC_ALL=C; exec " & quoteShell(bashPath) &
            " --noprofile --norc -i"
          session = spawnCompactTerminalSession(
            initTerminalSpawnOptions(command = command, shell = bashPath),
            columns = 100,
            rows = 8,
          )
          view = newTerminalView(session, frame = rect(0, 0, 900, 180))
          window = newWindow("Bash terminal input", frame = rect(0, 0, 900, 180))
        defer:
          view.close()
        window.setContentView(view)
        check window.makeFirstResponder(view)
        check window.tickUntilCurrentLineContains(view, "bash-input$")

        var generation = session.screenInfo().generation
        check window.dispatchTextInput(
          "input_count=0; capture_input() { " & "input_count=$((input_count + 1)); " &
            "printf 'input-ready-%s\\n' \"$input_count\"; " & "IFS= read -e value; " &
            "printf 'input-result-%s:%s\\n' \"$input_count\" \"$value\"; }"
        )
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilCurrentLineAfterChange(view, generation, "bash-input$")

        check window.dispatchTextInput("capture_input")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "input-ready-1")
        check window.dispatchTextInput("abcdef")
        check window.dispatchKeyDown(
          KeyEvent(key: keyB, keyCode: keyB.ord, modifiers: {kmControl})
        )
        # Model the duplicate control text callbacks Cocoa used to emit.
        check window.dispatchTextInput("\x02")
        check window.dispatchTextInput("X")
        check window.dispatchKeyDown(
          KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: {kmControl})
        )
        check window.dispatchTextInput("\x06")
        check window.dispatchTextInput("Y")
        check window.dispatchKeyDown(
          KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl})
        )
        check window.dispatchTextInput("\x01")
        check window.dispatchTextInput("0")
        check window.dispatchKeyDown(
          KeyEvent(key: keyE, keyCode: keyE.ord, modifiers: {kmControl})
        )
        check window.dispatchTextInput("\x05")
        check window.dispatchTextInput("9")
        check window.dispatchKeyDown(
          KeyEvent(key: keyH, keyCode: keyH.ord, modifiers: {kmControl})
        )
        check window.dispatchTextInput("\x08")
        check window.dispatchKeyDown(
          KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl})
        )
        check window.dispatchTextInput("\x01")
        check window.dispatchKeyDown(
          KeyEvent(key: keyD, keyCode: keyD.ord, modifiers: {kmControl})
        )
        check window.dispatchTextInput("\x04")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "input-result-1:abcdeXfY")

        check window.dispatchTextInput("capture_input")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "input-ready-2")
        check window.dispatchTextInput("ace")
        check window.dispatchKeyDown(KeyEvent(key: keyHome, keyCode: keyHome.ord))
        check window.dispatchKeyDown(
          KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord)
        )
        check window.dispatchTextInput("b")
        check window.dispatchKeyDown(KeyEvent(key: keyEnd, keyCode: keyEnd.ord))
        check window.dispatchKeyDown(
          KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord)
        )
        check window.dispatchTextInput("d")
        check window.dispatchKeyDown(
          KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord)
        )
        check window.dispatchTextInput("d")
        check window.dispatchKeyDown(KeyEvent(key: keyDelete, keyCode: keyDelete.ord))
        check window.dispatchTextInput("e")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "input-result-2:abcde")

        check window.dispatchTextInput("capture_input")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "input-ready-3")
        check window.dispatchTextInput("ac")
        check window.dispatchKeyDown(KeyEvent(key: keyHome, keyCode: keyHome.ord))
        check window.dispatchKeyDown(
          KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord)
        )
        check window.dispatchTextInput("b")
        check window.sendAction(deleteForward(), DynamicAgent(view))
        check window.dispatchTextInput("c")
        check window.sendAction(deleteBackward(), DynamicAgent(view))
        check window.dispatchTextInput("c")
        discard generalPasteboard().setPlainText("XY")
        check window.dispatchKeyDown(
          KeyEvent(key: keyV, keyCode: keyV.ord, modifiers: terminalShortcutModifiers())
        )
        check window.sendAction(insertNewline(), DynamicAgent(view))
        check window.tickUntilNormalizedText(view, "input-result-3:abcXY")

        check window.dispatchTextInput("capture_input")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "input-ready-4")
        check window.dispatchTextInput("one three")
        check window.dispatchKeyDown(
          KeyEvent(text: "∫", key: keyB, keyCode: keyB.ord, modifiers: {kmOption})
        )
        # Cocoa follows the physical Option keydown with the composed glyph.
        check window.dispatchTextInput("∫")
        check window.dispatchTextInput("two ")
        check window.dispatchKeyDown(
          KeyEvent(text: "ƒ", key: keyF, keyCode: keyF.ord, modifiers: {kmOption})
        )
        check window.dispatchTextInput("ƒ")
        check window.dispatchTextInput("!")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "input-result-4:one two three!")

    test "Bash receives common Readline editing and shell control inputs":
      let bashPath = findExe("bash")
      if bashPath.len == 0:
        skip()
      else:
        let
          root = createTempDir("merenda-terminal-common-input-", "")
          completionFile = root / "common-input-target.txt"
        writeFile(completionFile, "")
        defer:
          removeFile(completionFile)
          removeDir(root)

        let
          command =
            "export PS1='bash-common$ ' PS2='> ' HISTFILE=/dev/null " &
            "INPUTRC=/dev/null LC_ALL=C; exec " & quoteShell(bashPath) &
            " --noprofile --norc -i"
          session = spawnCompactTerminalSession(
            initTerminalSpawnOptions(
              command = command, shell = bashPath, workingDirectory = root
            ),
            columns = 100,
            rows = 10,
          )
          view = newTerminalView(session, frame = rect(0, 0, 900, 220))
          window = newWindow("Common Bash input", frame = rect(0, 0, 900, 220))
        defer:
          view.close()
        window.setContentView(view)
        check window.makeFirstResponder(view)
        check window.tickUntilCurrentLineContains(view, "bash-common$")

        var generation = session.screenInfo().generation
        check window.dispatchTextInput(
          "set -o emacs; common_count=0; common_input() { " &
            "common_count=$((common_count + 1)); " &
            "printf 'common-ready-%s\\n' \"$common_count\"; " & "IFS= read -e value; " &
            "printf 'common-result-%s:%s\\n' \"$common_count\" \"$value\"; }"
        )
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilCurrentLineAfterChange(view, generation, "bash-common$")

        check window.dispatchTextInput("common_input")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "common-ready-1")
        check window.dispatchTextInput("alpha beta gamma")
        check window.dispatchKeyDown(
          KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl})
        )
        for _ in 0 ..< 6:
          check window.dispatchKeyDown(
            KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: {kmControl})
          )
        check window.dispatchKeyDown(
          KeyEvent(key: keyK, keyCode: keyK.ord, modifiers: {kmControl})
        )
        check window.dispatchTextInput("delta")
        check window.dispatchKeyDown(
          KeyEvent(key: keyU, keyCode: keyU.ord, modifiers: {kmControl})
        )
        check window.dispatchKeyDown(
          KeyEvent(key: keyY, keyCode: keyY.ord, modifiers: {kmControl})
        )
        check window.dispatchKeyDown(
          KeyEvent(key: keyJ, keyCode: keyJ.ord, modifiers: {kmControl})
        )
        check window.tickUntilNormalizedText(view, "common-result-1:alpha delta")

        check window.dispatchTextInput("common_input")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "common-ready-2")
        check window.dispatchTextInput("acb")
        check window.dispatchKeyDown(
          KeyEvent(key: keyT, keyCode: keyT.ord, modifiers: {kmControl})
        )
        check window.dispatchKeyDown(
          KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
        )
        check window.dispatchKeyDown(
          KeyEvent(key: keyY, keyCode: keyY.ord, modifiers: {kmControl})
        )
        check window.dispatchKeyDown(
          KeyEvent(key: keyM, keyCode: keyM.ord, modifiers: {kmControl})
        )
        check window.tickUntilNormalizedText(view, "common-result-2:abc")

        check window.dispatchTextInput("common_input")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "common-ready-3")
        check window.dispatchTextInput("one two three")
        check window.dispatchKeyDown(
          KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl})
        )
        check window.dispatchKeyDown(
          KeyEvent(text: "∂", key: keyD, keyCode: keyD.ord, modifiers: {kmOption})
        )
        # Cocoa follows the physical Option keydown with the composed glyph.
        check window.dispatchTextInput("∂")
        check window.dispatchTextInput("zero")
        check window.dispatchKeyDown(
          KeyEvent(key: keyE, keyCode: keyE.ord, modifiers: {kmControl})
        )
        check window.dispatchKeyDown(
          KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord, modifiers: {kmOption})
        )
        check window.dispatchTextInput("four")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "common-result-3:zero two four")

        check window.dispatchTextInput("common_input")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "common-ready-4")
        check window.dispatchTextInput("left right")
        check window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
        check window.dispatchKeyDown(KeyEvent(text: "b", key: keyB, keyCode: keyB.ord))
        check window.dispatchTextInput("middle ")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "common-result-4:left middle right")

        check window.dispatchTextInput("common_input")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "common-ready-5")
        check window.dispatchTextInput("common-input-ta")
        check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(
          view, "common-result-5:common-input-target.txt"
        )

        check window.dispatchTextInput("common_input")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "common-ready-6")
        check window.dispatchTextInput("ctrl-l-value")
        check window.dispatchKeyDown(
          KeyEvent(key: keyL, keyCode: keyL.ord, modifiers: {kmControl})
        )
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "common-result-6:ctrl-l-value")

        generation = session.screenInfo().generation
        check window.dispatchTextInput("interrupted command")
        check window.dispatchKeyDown(
          KeyEvent(key: keyC, keyCode: keyC.ord, modifiers: {kmControl})
        )
        # Model a duplicate Cocoa control-character text callback.
        check window.dispatchTextInput("\x03")
        check window.tickUntilCurrentLineAfterChange(view, generation, "bash-common$")
        check window.dispatchTextInput("printf 'ctrl-c-recovered\\n'")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "ctrl-c-recovered")

        check window.dispatchTextInput(
          "history_count=$((history_count + 1)); " &
            "printf 'history-result-%s\\n' \"$history_count\""
        )
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "history-result-1")
        check window.dispatchKeyDown(KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord))
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "history-result-2")

        check window.dispatchTextInput("arrow-saved")
        check window.dispatchKeyDown(KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord))
        check window.dispatchKeyDown(
          KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord)
        )
        check window.tickUntilCurrentLineContains(view, "bash-common$ arrow-saved")
        check window.dispatchKeyDown(
          KeyEvent(key: keyU, keyCode: keyU.ord, modifiers: {kmControl})
        )
        check window.dispatchTextInput("control-saved")
        check window.dispatchKeyDown(
          KeyEvent(key: keyP, keyCode: keyP.ord, modifiers: {kmControl})
        )
        check window.dispatchKeyDown(
          KeyEvent(key: keyN, keyCode: keyN.ord, modifiers: {kmControl})
        )
        check window.tickUntilCurrentLineContains(view, "bash-common$ control-saved")
        check window.dispatchKeyDown(
          KeyEvent(key: keyU, keyCode: keyU.ord, modifiers: {kmControl})
        )

        check window.dispatchKeyDown(
          KeyEvent(key: keyD, keyCode: keyD.ord, modifiers: {kmControl})
        )
        check window.dispatchTextInput("\x04")
        check session.pollUntilExit()

    test "a second Bash reverse search starts with an empty query":
      let bashPath = findExe("bash")
      if bashPath.len == 0:
        skip()
      else:
        let
          searchMarker = "reverse_search_" & repeat('z', 100)
          command =
            "export PS1='bash-test$ ' PS2='> ' HISTFILE=/dev/null " &
            "INPUTRC=/dev/null LC_ALL=C; exec " & quoteShell(bashPath) &
            " --noprofile --norc -i"
          session = spawnCompactTerminalSession(
            initTerminalSpawnOptions(command = command, shell = bashPath),
            columns = 100,
            rows = 8,
          )
          view = newTerminalView(session, frame = rect(0, 0, 900, 180))
          window = newWindow("Bash reverse search", frame = rect(0, 0, 900, 180))
        defer:
          view.close()
        window.setContentView(view)
        check window.makeFirstResponder(view)
        check window.tickUntilCurrentLineContains(view, "bash-test$")

        var generation = session.screenInfo().generation
        check window.dispatchTextInput("history -c")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilCurrentLineAfterChange(view, generation, "bash-test$")
        generation = session.screenInfo().generation
        check window.dispatchTextInput("search_count=0")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilCurrentLineAfterChange(view, generation, "bash-test$")
        generation = session.screenInfo().generation
        check window.dispatchTextInput(
          "search_count=$((search_count + 1)); " &
            "echo search_execution_done_$search_count # " & searchMarker
        )
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "search_execution_done_1")
        check window.tickUntilCurrentLineAfterChange(view, generation, "bash-test$")

        check window.dispatchKeyDown(
          KeyEvent(key: keyR, keyCode: keyR.ord, modifiers: {kmControl})
        )
        check window.dispatchTextInput(searchMarker)
        check window.tickUntilCurrentLineContains(view, repeat('z', 20))
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check window.tickUntilNormalizedText(view, "search_execution_done_2")
        check window.tickUntilCurrentLineContains(view, "bash-test$")

        check window.dispatchKeyDown(
          KeyEvent(key: keyR, keyCode: keyR.ord, modifiers: {kmControl})
        )
        check window.tickUntilCurrentLineContains(view, "reverse-i-search")
        let
          secondSearchLine = session.currentTerminalLine()
          secondRenderedLine = view.currentRenderedTerminalLine()
          secondRenderedTail = view.renderedTerminalTail()
        checkpoint "second Bash search screen row: " & secondSearchLine.escape()
        checkpoint "second Bash search rendered row: " & secondRenderedLine.escape()
        checkpoint "second Bash search rendered tail: " & secondRenderedTail.escape()
        check searchMarker notin secondSearchLine
        check searchMarker notin secondRenderedLine
        check repeat('z', 20) notin secondRenderedTail

  test "attached running views poll from the window animation scheduler":
    when defined(posix):
      let
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(command = "printf automatic"), columns = 20, rows = 3
        )
        view = newTerminalView(session, frame = rect(0, 0, 260, 90))
        window = newWindow("Terminal polling", frame = rect(0, 0, 260, 90))
      defer:
        view.close()
      window.setContentView(view)

      let deadline = getMonoTime() + initDuration(seconds = 3)
      while ("automatic" notin view.stringValue() or session.running()) and
          getMonoTime() < deadline:
        discard window.animationScheduler().tick(initDuration(milliseconds = 16))
        sleep(5)

      check "automatic" in view.stringValue()
      check not session.running()

  test "resizing the window updates the visible grid and child PTY":
    when defined(posix):
      let
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(
            command = "stty -echo; printf ready; IFS= read -r ignored; stty size"
          ),
          columns = 20,
          rows = 3,
        )
        view = newTerminalView(session, frame = rect(0, 0, 260, 90))
        window = newWindow("Terminal resize", frame = rect(0, 0, 260, 90))
      defer:
        view.close()
      window.setContentView(view)
      view.layoutSubtreeIfNeeded()
      check window.makeFirstResponder(view)
      check session.pollUntilText("ready")
      let initialSize = (session.screen().columns, session.screen().rows)

      window.frame = rect(0, 0, 520, 200)
      view.layoutSubtreeIfNeeded()
      let resizedSize = (session.screen().columns, session.screen().rows)
      check resizedSize[0] > initialSize[0]
      check resizedSize[1] > initialSize[1]
      check view.maxColumnCount == resizedSize[0]
      check view.lineCount == resizedSize[1]

      check window.dispatchTextInput("resized")
      check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
      check session.pollUntilExit()
      check $resizedSize[1] & " " & $resizedSize[0] in session.screen().plainText()

  test "mouse drag word line and select-all interactions use responder commands":
    let
      session = newCompactTerminalSession(columns = 20, rows = 3)
      view = newTerminalView(session, frame = rect(0, 0, 300, 90))
      window = newWindow("Terminal selection", frame = rect(0, 0, 300, 90))
    session.processOutput("alpha beta\r\nsecond line")
    discard view.poll()
    window.setContentView(view)
    let
      dragStart = view.terminalCellPoint(0, 0)
      dragEnd = view.terminalCellPoint(0, 4)
      wordPoint = view.terminalCellPoint(0, 7)
      linePoint = view.terminalCellPoint(1, 3)
      originalText = session.screen().plainText()

    check window.mouseDownAt(dragStart, clickCount = 1)
    check window.mouseDraggedAt(dragEnd)
    check window.mouseUpAt(dragEnd, clickCount = 1)
    check view.selectionText() == "alpha"

    check window.mouseDownAt(dragEnd, clickCount = 1)
    check window.mouseDraggedAt(dragStart)
    check window.mouseUpAt(dragStart, clickCount = 1)
    check view.selectionText() == "alpha"

    check window.mouseDownAt(wordPoint, clickCount = 2)
    check window.mouseUpAt(wordPoint, clickCount = 2)
    check view.hasSelection()
    check view.selectionText() == "beta"
    check window.dispatchKeyDown(
      KeyEvent(key: keyC, keyCode: keyC.ord, modifiers: terminalShortcutModifiers())
    )
    check generalPasteboard().plainText() == "beta"

    check window.mouseDownAt(linePoint, clickCount = 3)
    check window.mouseUpAt(linePoint, clickCount = 3)
    check view.selectionText() == "second line"

    check window.dispatchKeyDown(
      KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: terminalShortcutModifiers())
    )
    check view.selectionText().strip() == "alpha beta\nsecond line"
    check window.dispatchKeyDown(
      KeyEvent(key: keyX, keyCode: keyX.ord, modifiers: terminalShortcutModifiers())
    )
    check generalPasteboard().plainText().strip() == "alpha beta\nsecond line"
    check session.screen().plainText() == originalText

  test "single click focuses the terminal and clears selection without selecting a cell":
    let
      session = newCompactTerminalSession(columns = 20, rows = 3)
      view = newTerminalView(session, frame = rect(0, 0, 300, 90))
      peer = newView(frame = rect(300, 0, 60, 90))
      root = newView(frame = rect(0, 0, 360, 90))
      window = newWindow("Terminal click focus", frame = rect(0, 0, 360, 90))
    session.processOutput("alpha beta")
    discard view.poll()
    peer.acceptsFirstResponder = true
    root.addSubview(view)
    root.addSubview(peer)
    window.setContentView(root)
    let point = view.terminalCellPoint(0, 2)

    check window.mouseDownAt(point, clickCount = 2)
    check window.mouseUpAt(point, clickCount = 2)
    check view.hasSelection()
    check window.makeFirstResponder(peer)

    check window.mouseDownAt(point, clickCount = 1)
    check window.mouseUpAt(point, clickCount = 1)
    check window.firstResponder() == Responder(view)
    check not view.hasSelection()
    check view.selectionText().len == 0
    check view.cellAt(0, 2).backgroundColor != view.palette().selection

  test "selection copy and backspace keep working during live terminal output":
    when defined(posix):
      let
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf 'copy target\\033[2;1Hready'; " &
              "(i=0; while :; do " & "printf '\\033[2;1Hstatus %03d' \"$i\"; " &
              "i=$(((i + 1) % 1000)); sleep 0.01; done) & producer=$!; " &
              "bytes=$(dd bs=1 count=4 2>/dev/null | od -An -tx1 | " &
              "tr -d '[:space:]'); " &
              "kill \"$producer\" 2>/dev/null; wait \"$producer\" 2>/dev/null; " &
              "printf '\\033[3;1Hinput:%s' \"$bytes\""
          ),
          columns = 30,
          rows = 4,
        )
        view = newTerminalView(session, frame = rect(0, 0, 360, 120))
        window = newWindow("Terminal live selection", frame = rect(0, 0, 360, 120))
      defer:
        view.close()
      session.readLimit = 16 * 1024
      window.setContentView(view)
      check window.makeFirstResponder(view)
      check session.pollUntilText("status")
      discard view.poll()

      let
        dragStart = view.terminalCellPoint(0, 0)
        dragEnd = view.terminalCellPoint(0, 3)
      check window.mouseDownAt(dragStart, clickCount = 1)
      check window.mouseDraggedAt(dragEnd)
      check window.mouseUpAt(dragEnd, clickCount = 1)
      check view.selectionText() == "copy"
      for _ in 0 ..< 5:
        discard window.animationScheduler().tick(initDuration(milliseconds = 16))
        sleep(5)
      check view.selectionText() == "copy"
      check window.dispatchKeyDown(
        KeyEvent(key: keyC, keyCode: keyC.ord, modifiers: terminalShortcutModifiers())
      )
      check generalPasteboard().plainText() == "copy"

      check window.dispatchKeyDown(
        KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord)
      )
      check not view.hasSelection()
      check view.cellAt(0, 0).backgroundColor != view.palette().selection
      check window.dispatchTextInput("ab")
      check window.dispatchKeyDown(
        KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord)
      )

      check session.pollUntilExit()
      check "input:7f61627f" in session.screen().plainText()

  test "scrolling moves only the viewport with a fractional grid offset":
    let
      session = newCompactTerminalSession(columns = 10, rows = 3)
      view = newTerminalView(session, frame = rect(0, 0, 180, 80))
      window = newWindow("Terminal scroll", frame = rect(0, 0, 180, 80))
      spy = TerminalInteractionSpy()
    session.processOutput("zero\r\none\r\ntwo\r\nthree\r\nfour")
    discard view.poll()
    let cursorBefore = session.screen().cursor.position
    window.setContentView(view)
    view.connect(accessibilityNotificationPosted, spy, rememberTerminalAccessibility)
    let point = view.pointToWindow(initPoint(10, 10))

    check window.dispatchScrollWheel(
      ScrollEvent(location: point, deltaY: 0.5'f32, phase: sepChanged)
    )
    check view.scrollPosition() == 0.5'f32
    check view.gridOffset().y < 0.0'f32
    check view.cellAt(0, 0).text == "o"
    check spy.notifications == @[anValueChanged]
    check session.screen().cursor.position == cursorBefore

    check window.dispatchScrollWheel(
      ScrollEvent(location: point, deltaY: 0.25'f32, phase: sepChanged)
    )
    check view.scrollPosition() == 0.75'f32
    check view.cellAt(0, 0).text == "o"
    check spy.notifications == @[anValueChanged]

    check window.dispatchScrollWheel(
      ScrollEvent(location: point, deltaY: 20.0'f32, phase: sepEnded)
    )
    check view.scrollPosition() == session.screen().scrollbackCount().float32
    check view.cellAt(0, 0).text == "z"
    check spy.notifications == @[anValueChanged, anValueChanged]
    check session.screen().cursor.position == cursorBefore

  test "scrolling inspects history while a fullscreen Bash app is running":
    when defined(posix):
      let bashPath = findExe("bash")
      if bashPath.len == 0:
        skip()
      else:
        let
          command =
            "stty -echo; printf '\\033[?1049h'; " &
            "printf 'alternate-0\\r\\nalternate-1\\r\\nalternate-2\\r\\n" &
            "alternate-3\\r\\nalternate-4\\r\\nalternate-ready'; " &
            "IFS= read -r value; " & "printf '\\033[?1049lrestored:%s' \"$value\""
          session = spawnCompactTerminalSession(
            initTerminalSpawnOptions(command = command, shell = bashPath),
            columns = 24,
            rows = 4,
          )
          view = newTerminalView(session, frame = rect(0, 0, 320, 100))
          window =
            newWindow("Fullscreen terminal history", frame = rect(0, 0, 320, 100))
        defer:
          view.close()
        window.setContentView(view)
        check window.makeFirstResponder(view)
        check session.pollUntilText("alternate-ready")
        discard view.poll()

        let point = view.pointToWindow(initPoint(10, 10))
        check session.screenInfo().alternateScreen
        check session.screenInfo().scrollbackCount == 2
        check window.dispatchScrollWheel(
          ScrollEvent(location: point, deltaY: 2.0'f32, phase: sepChanged)
        )
        check view.scrollPosition() == 2.0'f32
        check view.stringValue().splitLines()[0].strip() == "alternate-0"

        check window.dispatchTextInput("done")
        check window.dispatchKeyDown(
          KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
        )
        check session.pollUntilExit()
        check "restored:done" in session.normalizedTerminalOutput()

  test "alternate scroll sends cursor keys to a fullscreen Bash app":
    when defined(posix):
      let bashPath = findExe("bash")
      if bashPath.len == 0:
        skip()
      else:
        let
          command =
            "stty raw -echo; printf '\\033[?1;1007;1049hready'; " &
            "dd bs=1 count=6 2>/dev/null | od -An -tx1"
          session = spawnCompactTerminalSession(
            initTerminalSpawnOptions(command = command, shell = bashPath),
            columns = 40,
            rows = 4,
          )
          view = newTerminalView(session, frame = rect(0, 0, 400, 120))
          window = newWindow("Terminal alternate scroll", frame = rect(0, 0, 400, 120))
        defer:
          view.close()
        window.setContentView(view)
        check window.makeFirstResponder(view)
        check session.pollUntilText("ready")
        discard view.poll()
        let point = view.pointToWindow(initPoint(10, 10))

        check session.screenInfo().alternateScreen
        check session.screenInfo().modes.alternateScroll
        check session.screenInfo().modes.applicationCursorKeys
        check window.dispatchScrollWheel(
          ScrollEvent(location: point, deltaY: 1.0'f32, phase: sepChanged)
        )
        check window.dispatchScrollWheel(
          ScrollEvent(location: point, deltaY: -1.0'f32, phase: sepChanged)
        )
        check view.scrollPosition() == 0.0'f32
        check session.pollUntilExit()
        check "1b 4f 41 1b 4f 42" in session.normalizedTerminalOutput()

  test "window scrolling stays correct with a full scrollback buffer":
    let
      session = newCompactTerminalSession(columns = 24, rows = 5, maxScrollback = 1_000)
      view = newTerminalView(session, frame = rect(0, 0, 320, 120))
      window = newWindow("Terminal large scrollback", frame = rect(0, 0, 320, 120))
    var output = newStringOfCap(16_000)
    for line in 0 .. 1_002:
      if line > 0:
        output.add "\r\n"
      output.add "row " & $line
    session.processOutput(output)
    discard view.poll()
    window.setContentView(view)
    let
      point = view.pointToWindow(initPoint(10, 10))
      cursorBefore = session.screenInfo().cursor.position

    check session.screenInfo().scrollbackCount == 998
    check window.dispatchScrollWheel(
      ScrollEvent(location: point, deltaY: 400.0'f32, phase: sepChanged)
    )
    check view.scrollPosition() == 400.0'f32
    check view.stringValue().splitLines()[0].strip() == "row 598"
    check session.screenInfo().cursor.position == cursorBefore

    check window.dispatchScrollWheel(
      ScrollEvent(location: point, deltaY: 10_000.0'f32, phase: sepChanged)
    )
    check view.scrollPosition() == 998.0'f32
    check view.stringValue().splitLines()[0].strip() == "row 0"

    check window.dispatchScrollWheel(
      ScrollEvent(location: point, deltaY: -10_000.0'f32, phase: sepEnded)
    )
    check view.scrollPosition() == 0.0'f32
    check view.stringValue().splitLines()[0].strip() == "row 998"
    check session.screenInfo().cursor.position == cursorBefore

  test "terminal shortcut and Control-L clear scrollback through window input":
    let
      session = newCompactTerminalSession(columns = 8, rows = 2)
      view = newTerminalView(session, frame = rect(0, 0, 180, 70))
      window = newWindow("Terminal clear scrollback", frame = rect(0, 0, 180, 70))
    window.setContentView(view)
    check window.makeFirstResponder(view)

    session.processOutput("zero\r\none\r\ntwo")
    discard view.poll()
    let visibleAfterCommand = session.screen().plainText(includeScrollback = false)
    check session.screen().scrollbackCount() == 1
    check window.dispatchKeyDown(
      KeyEvent(key: keyK, keyCode: keyK.ord, modifiers: terminalShortcutModifiers())
    )
    check session.screen().scrollbackCount() == 0
    check session.screen().plainText(includeScrollback = false) == visibleAfterCommand
    check view.scrollPosition() == 0.0'f32

    session.processOutput("\r\nthree\r\nfour")
    discard view.poll()
    let visibleAfterControl = session.screen().plainText(includeScrollback = false)
    check session.screen().scrollbackCount() > 0
    check window.dispatchKeyDown(
      KeyEvent(key: keyL, keyCode: keyL.ord, modifiers: {kmControl})
    )
    check session.screen().scrollbackCount() == 0
    check session.screen().plainText(includeScrollback = false) == visibleAfterControl
    check view.scrollPosition() == 0.0'f32

  test "Shift preserves local selection and scrolling during mouse tracking":
    let
      session = newCompactTerminalSession(columns = 12, rows = 3)
      view = newTerminalView(session, frame = rect(0, 0, 220, 90))
      window = newWindow("Terminal Shift mouse", frame = rect(0, 0, 220, 90))
    session.processOutput("\x1b[?1003;1006hone\r\ntwo\r\nthree\r\nfour\r\nfive")
    discard view.poll()
    window.setContentView(view)
    let
      dragStart = view.terminalCellPoint(0, 0)
      dragEnd = view.terminalCellPoint(0, 4)

    check session.screen().modes.mouseTracking == tmtAny
    check window.mouseDownAt(dragStart, clickCount = 1, modifiers = {kmShift})
    check window.mouseDraggedAt(dragEnd, modifiers = {kmShift})
    check window.mouseUpAt(dragEnd, clickCount = 1, modifiers = {kmShift})
    check view.selectionText() == "three"

    check window.dispatchScrollWheel(
      ScrollEvent(
        location: dragStart, deltaY: 1.0'f32, phase: sepChanged, modifiers: {kmShift}
      )
    )
    check view.scrollPosition() == 1.0'f32

  test "scrollback remains the default after an application enables mouse tracking":
    for usesAlternateScreen in [false, true]:
      let
        session = newCompactTerminalSession(columns = 12, rows = 3)
        view = newTerminalView(session, frame = rect(0, 0, 220, 90))
        window = newWindow("Terminal application history", frame = rect(0, 0, 220, 90))
        alternateScreenInput = if usesAlternateScreen: "\x1b[?1049h" else: ""
      session.processOutput(
        alternateScreenInput & "\x1b[?1003;1006hone\r\ntwo\r\nthree\r\nfour\r\nfive"
      )
      discard view.poll()
      window.setContentView(view)
      let point = view.terminalCellPoint(0, 0)

      check session.screenInfo().alternateScreen == usesAlternateScreen
      check session.screenInfo().modes.mouseTracking == tmtAny
      check session.screenInfo().scrollbackCount == 2
      check window.dispatchScrollWheel(
        ScrollEvent(location: point, deltaY: 1.0'f32, phase: sepChanged)
      )
      check view.scrollPosition() == 1.0'f32
      check view.stringValue().splitLines()[0].strip() == "two"

  test "Codex resume history inserted above its composer remains scrollable":
    for usesAlternateScreen in [false, true]:
      let
        session = newCompactTerminalSession(columns = 24, rows = 5)
        view = newTerminalView(session, frame = rect(0, 0, 320, 120))
        window = newWindow("Codex resume history", frame = rect(0, 0, 320, 120))
        alternateScreenInput = if usesAlternateScreen: "\x1b[?1049h\x1b[?1007h" else: ""
      # Codex commits resumed history through a top-anchored scroll region so
      # its live composer can remain in the rows below that region.
      var output = alternateScreenInput & "\x1b[?2026h\x1b[1;3r\x1b[3;1H"
      for line in 0 .. 7:
        output.add "\r\ncodex-history-" & $line
      output.add "\x1b[r\x1b[5;1H> \x1b[?2026l"
      session.processOutput(output)
      discard view.poll()
      window.setContentView(view)
      let point = view.terminalCellPoint(0, 0)

      check session.screenInfo().alternateScreen == usesAlternateScreen
      check session.screenInfo().modes.alternateScroll == usesAlternateScreen
      check session.screenInfo().scrollbackCount == 8
      check window.dispatchScrollWheel(
        ScrollEvent(location: point, deltaY: 100.0'f32, phase: sepChanged)
      )
      check view.scrollPosition() == 8.0'f32
      check "codex-history-0" in view.stringValue()

  test "paste honors bracketed paste mode through responder commands":
    when defined(posix):
      let
        expected = "\x1b[200~pasted\x1b[201~"
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf ready; dd bs=1 count=" & $expected.len &
              " 2>/dev/null | od -An -tx1"
          ),
          columns = 60,
          rows = 4,
        )
        view = newTerminalView(session, frame = rect(0, 0, 600, 120))
        window = newWindow("Terminal paste", frame = rect(0, 0, 600, 120))
      defer:
        view.close()
      session.processOutput("\x1b[?2004h")
      window.setContentView(view)
      check window.makeFirstResponder(view)
      check session.pollUntilText("ready")
      discard generalPasteboard().setPlainText("pasted")

      check window.dispatchKeyDown(
        KeyEvent(key: keyV, keyCode: keyV.ord, modifiers: terminalShortcutModifiers())
      )
      check session.pollUntilExit()
      check "1b 5b 32 30 30 7e 70 61 73 74 65 64 1b 5b 32 30 31 7e" in
        session.screen().plainText().replace("\n", " ").splitWhitespace().join(" ")

  test "application mouse tracking receives input when scrollback is empty":
    when defined(posix):
      let
        expectedBytes = 28
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf ready; dd bs=1 count=" & $expectedBytes &
              " 2>/dev/null | od -An -tx1"
          ),
          columns = 80,
          rows = 4,
        )
        view = newTerminalView(session, frame = rect(0, 0, 800, 120))
        window = newWindow("Terminal mouse", frame = rect(0, 0, 800, 120))
      defer:
        view.close()
      session.processOutput("\x1b[?1000;1006h")
      window.setContentView(view)
      check session.pollUntilText("ready")
      let point = view.pointToWindow(
        initPoint(
          view.padding() + view.monoTextMetrics().cellWidth * 0.5'f32,
          view.padding() + view.monoTextMetrics().lineHeight * 0.5'f32,
        )
      )

      check window.mouseDownAt(point)
      check window.mouseUpAt(point)
      check window.dispatchScrollWheel(
        ScrollEvent(location: point, deltaY: 1.0'f32, phase: sepChanged)
      )
      check session.pollUntilExit()
      let output =
        session.screen().plainText().replace("\n", " ").splitWhitespace().join(" ")
      check "1b 5b 3c 30 3b 31 3b 31 4d" in output
      check "1b 5b 3c 30 3b 31 3b 31 6d" in output
      check "1b 5b 3c 36 34 3b 31 3b 31 4d" in output

  test "first responder changes report terminal focus to the child":
    when defined(posix):
      let
        expectedBytes = 6
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf ready; dd bs=1 count=" & $expectedBytes &
              " 2>/dev/null | od -An -tx1"
          ),
          columns = 30,
          rows = 4,
        )
        view = newTerminalView(session, frame = rect(0, 0, 300, 120))
        peer = newView(frame = rect(300, 0, 60, 120))
        root = newView(frame = rect(0, 0, 360, 120))
        window = newWindow("Terminal focus", frame = rect(0, 0, 360, 120))
      defer:
        view.close()
      peer.acceptsFirstResponder = true
      root.addSubview(view)
      root.addSubview(peer)
      window.setContentView(root)
      check session.pollUntilText("ready")
      session.processOutput("\x1b[?1004h")

      check window.makeFirstResponder(view)
      check window.makeFirstResponder(peer)
      check session.pollUntilExit()
      check "1b 5b 49 1b 5b 4f" in session.normalizedTerminalOutput()

  test "modifier-click activates OSC hyperlinks through mouse dispatch":
    let
      session = newCompactTerminalSession(columns = 24, rows = 2)
      view = newTerminalView(session, frame = rect(0, 0, 300, 80))
      window = newWindow("Terminal hyperlink", frame = rect(0, 0, 300, 80))
      spy = TerminalInteractionSpy()
    session.processOutput(
      "\x1b]8;;https://example.com/docs\x07documentation\x1b]8;;\x07"
    )
    discard view.poll()
    view.connect(terminalHyperlinkWasActivated, spy, rememberTerminalLink)
    window.setContentView(view)
    let point = view.terminalCellPoint(0, 3)

    discard window.mouseMovedAt(point, modifiers = terminalLinkModifiers())
    check mtdUnderline in view.cellAt(0, 3).decorations
    check window.mouseDownAt(point, clickCount = 1, modifiers = terminalLinkModifiers())
    check window.mouseUpAt(point, clickCount = 1, modifiers = terminalLinkModifiers())
    check spy.links == @["https://example.com/docs"]

  test "modifier-hover reveals plain URLs and link activation can be disabled":
    let
      session = newCompactTerminalSession(columns = 40, rows = 2)
      view = newTerminalView(session, frame = rect(0, 0, 480, 80))
      window = newWindow("Terminal URL", frame = rect(0, 0, 480, 80))
      spy = TerminalInteractionSpy()
    session.processOutput("\x1b[?1000;1006hSee (https://example.com/docs).")
    discard view.poll()
    view.connect(terminalHyperlinkWasActivated, spy, rememberTerminalLink)
    window.setContentView(view)
    check window.makeFirstResponder(view)
    let
      point = view.terminalCellPoint(0, 10)
      modifierKey =
        when defined(macosx) or defined(macos): keyLeftCommand else: keyLeftControl

    discard window.mouseMovedAt(point)
    check mtdUnderline notin view.cellAt(0, 10).decorations
    check window.dispatchFlagsChanged(
      KeyEvent(
        key: modifierKey, keyCode: modifierKey.ord, modifiers: terminalLinkModifiers()
      )
    )
    check mtdUnderline notin view.cellAt(0, 4).decorations
    check mtdUnderline in view.cellAt(0, 5).decorations
    check mtdUnderline in view.cellAt(0, 28).decorations
    check mtdUnderline notin view.cellAt(0, 29).decorations
    check window.mouseDownAt(point, clickCount = 1, modifiers = terminalLinkModifiers())
    check window.mouseUpAt(point, clickCount = 1, modifiers = terminalLinkModifiers())
    check spy.links == @["https://example.com/docs"]

    view.allowsLinkActivation = false
    check not view.allowsLinkActivation
    check mtdUnderline notin view.cellAt(0, 10).decorations
    discard window.mouseMovedAt(point, modifiers = terminalLinkModifiers())
    check mtdUnderline notin view.cellAt(0, 10).decorations
    check window.mouseDownAt(point, clickCount = 1, modifiers = terminalLinkModifiers())
    check spy.links == @["https://example.com/docs"]

  test "OSC clipboard writes remain opt-in":
    let
      session = newCompactTerminalSession(columns = 20, rows = 2)
      view = newTerminalView(session, frame = rect(0, 0, 240, 80))
    discard generalPasteboard().setPlainText("existing")
    session.processOutput("\x1b]52;c;bmV3IHZhbHVl\x07")

    discard view.poll()
    check generalPasteboard().plainText() == "existing"
    check session.screen().clipboardRequestPending

    view.allowsClipboardWrites = true
    discard view.poll()
    check generalPasteboard().plainText() == "new value"
    check not session.screen().clipboardRequestPending
