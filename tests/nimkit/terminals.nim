import std/[strutils, unittest]

import merenda/nimkit/terminal/[terminalparser, terminalscreen]

proc feed(screen: var TerminalScreen, parser: var TerminalParser, value: string) =
  parser.feed(screen, value)

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

    screen.feed(parser, "\x1b[?1;6;1003;1004;1006;2004h\x1b[5 q\x1b[?25l")

    check screen.modes.applicationCursorKeys
    check screen.modes.origin
    check screen.modes.mouseTracking == tmtAny
    check screen.modes.mouseEncoding == tmeSgr
    check screen.modes.focusReporting
    check screen.modes.bracketedPaste
    check screen.cursor.shape == tcsBar
    check screen.cursor.blinking
    check not screen.cursor.visible

    screen.feed(parser, "\x1b[?1;6;1003;1004;1006;2004l\x1b[2 q\x1b[?25h")
    check not screen.modes.applicationCursorKeys
    check not screen.modes.origin
    check screen.modes.mouseTracking == tmtNone
    check screen.modes.mouseEncoding == tmeX10
    check not screen.modes.focusReporting
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
